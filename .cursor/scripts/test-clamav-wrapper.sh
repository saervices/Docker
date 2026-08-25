#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
# Docker-free lifecycle regressions for the drift-locked ClamAV supervisor.

set -euo pipefail
umask 077

readonly TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)"

exec python3 - "$TEST_REPO_ROOT" <<'PY'
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest


REPOSITORY = Path(sys.argv[1]).resolve()
WRAPPER = REPOSITORY / "templates/clamav/scripts/clamav-start.sh"
COMPOSE = REPOSITORY / "templates/clamav/docker-compose.clamav.yaml"

FAKE_PROCESS = r'''#!/usr/bin/env python3
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time

name = Path(sys.argv[0]).name
markers = Path(os.environ["FAKE_MARKER_DIR"])
markers.mkdir(parents=True, exist_ok=True)

def mark(suffix, value="1"):
    path = markers / f"{name}.{suffix}"
    with path.open("a", encoding="utf-8") as handle:
        handle.write(f"{value}\n")

if name == "sha256sum":
    mark("sha-started")
    delay = float(os.environ.get("FAKE_SHA_DELAY", "0"))
    if delay:
        time.sleep(delay)
    result = subprocess.run(
        ["/usr/bin/sha256sum", *sys.argv[1:]],
        check=False,
        stdout=subprocess.PIPE,
    )
    sys.stdout.buffer.write(result.stdout)
    sys.stdout.flush()
    target = Path(sys.argv[-1])
    if os.environ.get("FAKE_SHA_REPLACE") == "1":
        source = target.read_bytes()
        mode = target.stat().st_mode & 0o777
        displaced = target.with_name(target.name + ".displaced")
        target.rename(displaced)
        target.write_bytes(source)
        target.chmod(mode)
    raise SystemExit(result.returncode)

if name == "sleep":
    behavior = os.environ.get("FAKE_SLEEP_BEHAVIOR", "delegate")
    if behavior.startswith("exit"):
        raise SystemExit(int(behavior.removeprefix("exit")))
    if behavior == "cleanup42" and any(markers.glob("*.signal")):
        raise SystemExit(42)
    raise SystemExit(
        subprocess.run(["/usr/bin/sleep", *sys.argv[1:]], check=False).returncode
    )

is_initial = name == "freshclam" and any(
    argument.startswith("--config-file=") for argument in sys.argv[1:]
)
if name == "chown":
    behavior = os.environ.get("FAKE_CHOWN_BEHAVIOR", "exit0")
    marker_name = "chown"
elif is_initial:
    behavior = os.environ.get("FAKE_INITIAL_BEHAVIOR", "exit0")
    marker_name = "freshclam.initial"
else:
    behavior = os.environ.get(f"FAKE_{name.upper()}_BEHAVIOR", "run")
    marker_name = name

(markers / f"{marker_name}.pid").write_text(str(os.getpid()), encoding="ascii")

def on_signal(signum, _frame):
    signal_path = markers / f"{marker_name}.signal"
    with signal_path.open("a", encoding="ascii") as handle:
        handle.write(f"{signum}\n")
    if behavior in {"ignore-term", "race127"}:
        return
    raise SystemExit(128 + signum)

signal.signal(signal.SIGTERM, on_signal)
signal.signal(signal.SIGINT, on_signal)

if behavior.startswith("exit"):
    raise SystemExit(int(behavior.removeprefix("exit")))

held_socket = None
if name == "clamd" and behavior != "socketless":
    socket_path = Path(os.environ["FAKE_SOCKET_PATH"])
    held_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    held_socket.bind(str(socket_path))
    held_socket.listen(1)

(markers / f"{marker_name}.ready").write_text("ready\n", encoding="ascii")

if behavior.startswith("ready-exit"):
    time.sleep(0.35)
    raise SystemExit(int(behavior.removeprefix("ready-exit")))
if behavior == "race127":
    release = markers / f"{marker_name}.release"
    while not release.exists():
        time.sleep(0.02)
    raise SystemExit(127)

while True:
    time.sleep(0.1)
'''


class Fixture:
    def __init__(self, parent: Path, name: str):
        self.root = parent / name
        self.root.mkdir(mode=0o700)
        self.markers = self.root / "markers"
        self.bin = self.root / "bin"
        self.run_clamav = self.root / "run/clamav"
        self.tmp = self.root / "tmp"
        self.var_lib = self.root / "var/lib/clamav"
        self.etc = self.root / "etc/clamav"
        for directory in (
            self.markers,
            self.bin,
            self.run_clamav,
            self.tmp,
            self.var_lib,
            self.etc,
            self.root / "var",
        ):
            directory.mkdir(parents=True, exist_ok=True)
        (self.var_lib / "main.cvd").write_bytes(b"test database\n")
        (self.etc / "clamd.conf").write_text("", encoding="utf-8")
        (self.etc / "freshclam.conf").write_text("", encoding="utf-8")

        fake_process = self.bin / "fake-process"
        fake_process.write_text(FAKE_PROCESS, encoding="utf-8")
        fake_process.chmod(0o755)
        for command in ("chown", "freshclam", "clamd", "sha256sum"):
            (self.bin / command).symlink_to(fake_process.name)

        self.vendor = self.root / "init"
        self.vendor.write_bytes(b"#!/bin/sh\nexit 0\n")
        self.vendor.chmod(0o755)
        self.wrapper = self.root / "clamav-start.sh"
        self._write_wrapper()
        self.output = self.root / "wrapper.out"
        self.process: subprocess.Popen[bytes] | None = None

    def _write_wrapper(self):
        source = WRAPPER.read_text(encoding="utf-8")
        vendor_bytes = self.vendor.read_bytes()
        metadata = self.vendor.stat()
        replacements = {
            "readonly CLAMAV_VENDOR_ENTRYPOINT='/init'": (
                f"readonly CLAMAV_VENDOR_ENTRYPOINT='{self.vendor}'"
            ),
            "readonly CLAMAV_VENDOR_SHA256='4034f6d63ee6c1d1ed3686733b5722f4b19055b623c82843927613f4e2f7c641'": (
                "readonly CLAMAV_VENDOR_SHA256='"
                + hashlib.sha256(vendor_bytes).hexdigest()
                + "'"
            ),
            "readonly CLAMAV_VENDOR_CONTRACT='755:1:0:0:3440'": (
                "readonly CLAMAV_VENDOR_CONTRACT='"
                f"755:1:{metadata.st_uid}:{metadata.st_gid}:{metadata.st_size}'"
            ),
            "readonly CLAMAV_SHUTDOWN_TIMEOUT=20": (
                "readonly CLAMAV_SHUTDOWN_TIMEOUT=2"
            ),
        }
        for old, new in replacements.items():
            if source.count(old) != 1:
                raise AssertionError(f"test transform anchor count drifted: {old}")
            source = source.replace(old, new)
        path_replacements = (
            ("/run/clamav", str(self.run_clamav)),
            ("/tmp/clamd.sock", str(self.tmp / "clamd.sock")),
            ("/var/lib/clamav", str(self.var_lib)),
            ("/etc/clamav", str(self.etc)),
            ("/tmp/freshclam_initial.conf", str(self.tmp / "freshclam_initial.conf")),
            ("/run/lock", str(self.root / "run/lock")),
            ("/var/lock", str(self.root / "var/lock")),
        )
        for old, new in path_replacements:
            if old not in source:
                raise AssertionError(f"test path anchor drifted: {old}")
            source = source.replace(old, new)
        self.wrapper.write_text(source, encoding="utf-8")
        self.wrapper.chmod(0o700)

    def environment(self, **updates: str) -> dict[str, str]:
        environment = os.environ.copy()
        environment.update(
            {
                "PATH": f"{self.bin}:/usr/bin:/bin",
                "FAKE_MARKER_DIR": str(self.markers),
                "FAKE_SOCKET_PATH": str(self.run_clamav / "clamd.sock"),
                "CLAMAV_NO_FRESHCLAMD": "false",
                "CLAMAV_NO_CLAMD": "false",
                "CLAMAV_NO_MILTERD": "true",
                "CLAMD_STARTUP_TIMEOUT": "3",
                "FRESHCLAM_CHECKS": "1",
            }
        )
        environment.update(updates)
        return environment

    def install_fake_sleep(self):
        (self.bin / "sleep").symlink_to("fake-process")

    def run(self, *arguments: str, timeout: float = 9, **environment: str):
        with self.output.open("wb") as output:
            completed = subprocess.run(
                ["/bin/sh", str(self.wrapper), *arguments],
                env=self.environment(**environment),
                stdout=output,
                stderr=subprocess.STDOUT,
                timeout=timeout,
                check=False,
            )
        return completed.returncode

    def start(self, **environment: str):
        output = self.output.open("wb")
        self.process = subprocess.Popen(
            ["/bin/sh", str(self.wrapper)],
            env=self.environment(**environment),
            stdout=output,
            stderr=subprocess.STDOUT,
        )
        output.close()
        return self.process

    def wait_path(self, relative: str, timeout: float = 6):
        target = self.markers / relative
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if target.exists():
                return target
            if self.process is not None and self.process.poll() is not None:
                break
            time.sleep(0.02)
        raise AssertionError(
            f"marker {relative} did not appear; output={self.output.read_text(errors='replace')}"
        )

    def child_identity(self, marker: str):
        pid = int(self.wait_path(marker).read_text(encoding="ascii"))
        stat_fields = Path(f"/proc/{pid}/stat").read_text(encoding="ascii").split()
        return pid, stat_fields[21]

    @staticmethod
    def identity_exists(identity: tuple[int, str]):
        pid, start_time = identity
        try:
            fields = Path(f"/proc/{pid}/stat").read_text(encoding="ascii").split()
        except (FileNotFoundError, ProcessLookupError):
            return False
        return fields[21] == start_time

    def assert_children_gone(self, testcase: unittest.TestCase):
        identities = []
        for pid_file in self.markers.glob("*.pid"):
            pid = int(pid_file.read_text(encoding="ascii"))
            try:
                fields = Path(f"/proc/{pid}/stat").read_text(encoding="ascii").split()
            except FileNotFoundError:
                continue
            identities.append((pid, fields[21]))
        deadline = time.monotonic() + 2
        while identities and time.monotonic() < deadline:
            identities = [item for item in identities if self.identity_exists(item)]
            time.sleep(0.02)
        testcase.assertEqual(identities, [], self.output.read_text(errors="replace"))

    def force_cleanup(self):
        if self.process is not None and self.process.poll() is None:
            self.process.kill()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
        for pid_file in self.markers.glob("*.pid"):
            try:
                os.kill(int(pid_file.read_text(encoding="ascii")), signal.SIGKILL)
            except (FileNotFoundError, ProcessLookupError, ValueError):
                pass


class ClamavSupervisorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="clamav-wrapper.")
        cls.root = Path(cls.temporary.name)
        cls.counter = 0

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def fixture(self):
        type(self).counter += 1
        fixture = Fixture(self.root, f"case-{self.counter:03d}")
        self.addCleanup(fixture.force_cleanup)
        return fixture

    def assert_process_status(self, fixture: Fixture, expected: int, timeout=9):
        assert fixture.process is not None
        try:
            status = fixture.process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            fixture.process.kill()
            fixture.process.wait(timeout=2)
            self.fail(f"wrapper timed out: {fixture.output.read_text(errors='replace')}")
        self.assertEqual(status, expected, fixture.output.read_text(errors="replace"))
        fixture.assert_children_gone(self)

    def test_static_compose_and_vendor_contract(self):
        source = WRAPPER.read_text(encoding="utf-8")
        compose = COMPOSE.read_text(encoding="utf-8")
        self.assertIn("CLAMAV_VENDOR_ENTRYPOINT='/init'", source)
        self.assertIn("4034f6d63ee6c1d1ed3686733b5722f4b19055b623c82843927613f4e2f7c641", source)
        self.assertIn("CLAMAV_VENDOR_CONTRACT='755:1:0:0:3440'", source)
        self.assertIn("readonly CLAMAV_SHUTDOWN_TIMEOUT=20", source)
        self.assertLess(source.index("unlink /run/clamav/clamd.sock"), source.index("Starting Freshclamd"))
        self.assertIn("- KILL", compose)
        self.assertIn("/usr/local/bin/clamav-start.sh:ro", compose)
        self.assertIn("entrypoint: ['/bin/sh', '/usr/local/bin/clamav-start.sh']", compose)

    def test_argument_feature_and_numeric_gates(self):
        cases = (
            ({}, ("unexpected",)),
            ({"CLAMAV_NO_FRESHCLAMD": "true"}, ()),
            ({"CLAMAV_NO_CLAMD": "true"}, ()),
            ({"CLAMAV_NO_MILTERD": "false"}, ()),
            ({"CLAMD_STARTUP_TIMEOUT": "3601"}, ()),
            ({"CLAMD_STARTUP_TIMEOUT": "invalid"}, ()),
            ({"FRESHCLAM_CHECKS": "0"}, ()),
            ({"FRESHCLAM_CHECKS": "51"}, ()),
            ({"FRESHCLAM_CHECKS": "invalid"}, ()),
        )
        for environment, arguments in cases:
            with self.subTest(environment=environment, arguments=arguments):
                fixture = self.fixture()
                self.assertNotEqual(fixture.run(*arguments, **environment), 0)
                fixture.assert_children_gone(self)

    def test_vendor_source_hostility_and_identity_drift(self):
        mutations = ("missing", "symlink", "hardlink", "mode", "hash", "identity")
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                fixture = self.fixture()
                environment = {}
                if mutation == "missing":
                    fixture.vendor.unlink()
                elif mutation == "symlink":
                    real = fixture.vendor.with_suffix(".real")
                    fixture.vendor.rename(real)
                    fixture.vendor.symlink_to(real)
                elif mutation == "hardlink":
                    os.link(fixture.vendor, fixture.vendor.with_suffix(".link"))
                elif mutation == "mode":
                    fixture.vendor.chmod(0o700)
                elif mutation == "hash":
                    content = fixture.vendor.read_bytes()
                    fixture.vendor.write_bytes(b"X" + content[1:])
                    fixture.vendor.chmod(0o755)
                elif mutation == "identity":
                    environment["FAKE_SHA_REPLACE"] = "1"
                self.assertNotEqual(fixture.run(**environment), 0)
                fixture.assert_children_gone(self)

    def test_startup_failures_propagate(self):
        fixture = self.fixture()
        self.assertEqual(fixture.run(FAKE_CHOWN_BEHAVIOR="exit7"), 7)
        fixture.assert_children_gone(self)
        fixture = self.fixture()
        (fixture.var_lib / "main.cvd").unlink()
        self.assertEqual(fixture.run(FAKE_INITIAL_BEHAVIOR="exit9"), 9)
        fixture.assert_children_gone(self)

    def test_pre_ready_essential_statuses_propagate(self):
        for daemon in ("FRESHCLAM", "CLAMD"):
            for natural_status, expected in ((0, 1), (2, 2), (127, 127), (143, 143)):
                with self.subTest(daemon=daemon, natural_status=natural_status):
                    fixture = self.fixture()
                    status = fixture.run(**{f"FAKE_{daemon}_BEHAVIOR": f"exit{natural_status}"})
                    self.assertEqual(status, expected, fixture.output.read_text(errors="replace"))
                    fixture.assert_children_gone(self)

    def test_post_ready_essential_statuses_propagate(self):
        for daemon in ("FRESHCLAM", "CLAMD"):
            for natural_status, expected in ((0, 1), (2, 2)):
                with self.subTest(daemon=daemon, natural_status=natural_status):
                    fixture = self.fixture()
                    status = fixture.run(
                        **{f"FAKE_{daemon}_BEHAVIOR": f"ready-exit{natural_status}"}
                    )
                    self.assertEqual(status, expected, fixture.output.read_text(errors="replace"))
                    fixture.assert_children_gone(self)

    def test_socket_timeout_stops_and_reaps_both_daemons(self):
        fixture = self.fixture()
        status = fixture.run(
            CLAMD_STARTUP_TIMEOUT="0",
            FAKE_CLAMD_BEHAVIOR="socketless",
        )
        self.assertEqual(status, 1, fixture.output.read_text(errors="replace"))
        fixture.assert_children_gone(self)

    def test_sleep_failure_is_not_masked_or_hotlooped(self):
        for status in (42, 127):
            with self.subTest(status=status):
                fixture = self.fixture()
                fixture.install_fake_sleep()
                self.assertEqual(
                    fixture.run(FAKE_SLEEP_BEHAVIOR=f"exit{status}"), status
                )
                fixture.assert_children_gone(self)

    def test_cleanup_sleep_failure_kills_and_reaps_before_propagation(self):
        fixture = self.fixture()
        fixture.install_fake_sleep()
        process = fixture.start(
            FAKE_FRESHCLAM_BEHAVIOR="ignore-term",
            FAKE_SLEEP_BEHAVIOR="cleanup42",
        )
        fixture.wait_path("clamd.ready")
        process.terminate()
        self.assert_process_status(fixture, 42)

    def _signal_and_expect_clean(self, marker: str, sent_signal: signal.Signals, **environment):
        fixture = self.fixture()
        process = fixture.start(**environment)
        fixture.wait_path(marker)
        process.send_signal(sent_signal)
        self.assert_process_status(fixture, 0)
        expected = str(int(sent_signal))
        for signal_file in fixture.markers.glob("*.signal"):
            self.assertIn(expected, signal_file.read_text(encoding="ascii").splitlines())
        return fixture

    def test_term_during_vendor_validation_is_clean_and_starts_no_daemon(self):
        fixture = self.fixture()
        process = fixture.start(FAKE_SHA_DELAY="1.5")
        fixture.wait_path("sha256sum.sha-started")
        process.terminate()
        self.assert_process_status(fixture, 0)
        self.assertFalse((fixture.markers / "freshclam.pid").exists())
        self.assertFalse((fixture.markers / "clamd.pid").exists())

    def test_term_during_chown_is_clean(self):
        self._signal_and_expect_clean(
            "chown.ready", signal.SIGTERM, FAKE_CHOWN_BEHAVIOR="run"
        )

    def test_term_during_initial_update_is_clean(self):
        fixture = self.fixture()
        (fixture.var_lib / "main.cvd").unlink()
        process = fixture.start(FAKE_INITIAL_BEHAVIOR="run")
        fixture.wait_path("freshclam.initial.ready")
        process.terminate()
        self.assert_process_status(fixture, 0)

    def test_term_during_socket_wait_is_clean(self):
        self._signal_and_expect_clean(
            "clamd.ready",
            signal.SIGTERM,
            FAKE_CLAMD_BEHAVIOR="socketless",
        )

    def test_term_and_int_in_steady_state_are_clean(self):
        for sent_signal in (signal.SIGTERM, signal.SIGINT):
            with self.subTest(sent_signal=sent_signal):
                self._signal_and_expect_clean("clamd.ready", sent_signal)

    def test_killed_essential_daemon_propagates_137_and_reaps_peer(self):
        fixture = self.fixture()
        fixture.start()
        clamd_identity = fixture.child_identity("clamd.pid")
        fixture.wait_path("clamd.ready")
        os.kill(clamd_identity[0], signal.SIGKILL)
        self.assert_process_status(fixture, 137)

    def test_term_resistant_peer_is_bounded_and_returns_137(self):
        fixture = self.fixture()
        process = fixture.start(FAKE_FRESHCLAM_BEHAVIOR="ignore-term")
        fixture.wait_path("clamd.ready")
        started = time.monotonic()
        process.terminate()
        self.assert_process_status(fixture, 137, timeout=7)
        self.assertLess(time.monotonic() - started, 6)

    def test_term_resistant_startup_child_is_bounded_and_returns_137(self):
        fixture = self.fixture()
        process = fixture.start(FAKE_CHOWN_BEHAVIOR="ignore-term")
        fixture.wait_path("chown.ready")
        started = time.monotonic()
        process.terminate()
        self.assert_process_status(fixture, 137, timeout=7)
        self.assertLess(time.monotonic() - started, 6)

    def test_natural_127_is_not_masked_by_term_race(self):
        fixture = self.fixture()
        process = fixture.start(FAKE_FRESHCLAM_BEHAVIOR="race127")
        fixture.wait_path("freshclam.ready")
        fixture.wait_path("clamd.ready")
        process.terminate()
        time.sleep(0.1)
        (fixture.markers / "freshclam.release").write_text("release\n", encoding="ascii")
        self.assert_process_status(fixture, 127)


suite = unittest.defaultTestLoader.loadTestsFromTestCase(ClamavSupervisorTests)
result = unittest.TextTestRunner(verbosity=2).run(suite)
raise SystemExit(0 if result.wasSuccessful() else 1)
PY
