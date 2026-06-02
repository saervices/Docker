#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""
Tærgeted Docker runtime probes for hærdened service settings.

Run mænuælly, ideælly through the docker group, for exæmple:
  sg docker -c "python3 .cursor/scripts/probe-container-hardening.py --service plænkæ"
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


SERVICES = {"planka", "kimai", "clamav", "seasearch"}


class Probe:
    def __init__(self) -> None:
        self.root = Path(tempfile.mkdtemp(prefix="codex-hardening-"))
        self.containers: list[str] = []
        self.volumes: list[str] = []

    def run(self, cmd: list[str], timeout: int = 120) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            cmd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )

    def docker(self, args: list[str], timeout: int = 120) -> subprocess.CompletedProcess[str]:
        return self.run(["docker", *args], timeout=timeout)

    def cleanup(self) -> None:
        for name in self.containers:
            self.docker(["rm", "-f", name], timeout=30)
        for name in self.volumes:
            self.docker(["volume", "rm", name], timeout=30)
        shutil.rmtree(self.root, ignore_errors=True)

    def logs(self, name: str) -> str:
        return self.docker(["logs", "--tail", "160", name], timeout=30).stdout

    def status(self, name: str) -> str:
        return self.docker(["ps", "-a", "--filter", f"name={name}", "--format", "{{.Status}}"], timeout=30).stdout.strip()

    def assert_no_fs_error(self, service: str, logs: str) -> None:
        bad = ["Read-only file system", "permission denied", "Permission denied"]
        for needle in bad:
            if needle in logs:
                raise RuntimeError(f"{service}: found filesystem error: {needle}")

    def probe_planka(self) -> None:
        name = "codex-hardening-planka"
        self.containers.append(name)
        data = self.root / "planka-data"
        data.mkdir(mode=0o770)
        cmd = [
            "run", "-d", "--name", name,
            "--read-only", "--user", "1000:1000", "--cap-drop", "ALL",
            "--security-opt", "no-new-privileges:true",
            "--tmpfs", "/run:rw,noexec,nosuid,nodev,size=32m,uid=1000,gid=1000,mode=0770",
            "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=64m",
            "--tmpfs", "/var/tmp:rw,noexec,nosuid,nodev,size=64m",
            "-v", f"{data}:/app/data:rw",
            "-e", "BASE_URL=http://localhost",
            "-e", "DATABASE_URL=postgresql://planka:planka@127.0.0.1:5432/planka",
            "-e", "SECRET_KEY=0123456789abcdef0123456789abcdef",
            "ghcr.io/plankanban/planka:latest",
        ]
        self.docker(cmd)
        time.sleep(2)
        logs = self.logs(name)
        self.assert_no_fs_error("planka", logs)
        if "ECONNREFUSED" not in logs:
            raise RuntimeError("planka: expected DB connection refusal was not observed")

    def probe_kimai(self) -> None:
        name = "codex-hardening-kimai"
        self.containers.append(name)
        data = self.root / "kimai-var"
        data.mkdir(mode=0o770)
        cmd = [
            "run", "-d", "--name", name,
            "--read-only", "--cap-drop", "ALL",
            "--cap-add", "CHOWN", "--cap-add", "SETUID", "--cap-add", "SETGID", "--cap-add", "DAC_OVERRIDE",
            "--security-opt", "no-new-privileges:true",
            "--tmpfs", "/run:rw,noexec,nosuid,nodev,size=32m",
            "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=64m",
            "--tmpfs", "/var/tmp:rw,noexec,nosuid,nodev,size=64m",
            "--tmpfs", "/var/run/apache2:rw,noexec,nosuid,nodev,size=32m",
            "--tmpfs", "/var/lock/apache2:rw,noexec,nosuid,nodev,size=32m",
            "-v", f"{data}:/opt/kimai/var:rw",
            "-e", "APP_SECRET=0123456789abcdef0123456789abcdef",
            "-e", "DATABASE_URL=mysql://kimai:kimai@127.0.0.1:3306/kimai",
            "kimai/kimai2:apache",
        ]
        self.docker(cmd)
        time.sleep(3)
        logs = self.logs(name)
        self.assert_no_fs_error("kimai", logs)
        if "Wait for database connection" not in logs:
            raise RuntimeError("kimai: expected DB wait state was not observed")

    def probe_clamav(self) -> None:
        name = "codex-hardening-clamav"
        volume = "codex-hardening-clamav-db"
        self.containers.append(name)
        self.volumes.append(volume)
        cmd = [
            "run", "-d", "--name", name,
            "--read-only", "--cap-drop", "ALL",
            "--cap-add", "SETUID", "--cap-add", "SETGID", "--cap-add", "CHOWN", "--cap-add", "DAC_OVERRIDE", "--cap-add", "FOWNER",
            "--security-opt", "no-new-privileges:true",
            "--tmpfs", "/run:rw,noexec,nosuid,nodev,size=64m",
            "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=128m",
            "--tmpfs", "/var/tmp:rw,noexec,nosuid,nodev,size=128m",
            "--tmpfs", "/var/log/clamav:rw,noexec,nosuid,nodev,size=64m",
            "-v", f"{volume}:/var/lib/clamav:rw",
            "-e", "CLAMAV_NO_MILTERD=true",
            "-e", "CLAMD_STARTUP_TIMEOUT=60",
            "-e", "FRESHCLAM_CHECKS=1",
            "-e", "TINI_SUBREAPER=1",
            "clamav/clamav:latest",
        ]
        self.docker(cmd)
        time.sleep(5)
        logs = self.logs(name)
        self.assert_no_fs_error("clamav", logs)
        if "Starting ClamAV" not in logs:
            raise RuntimeError("clamav: expected startup log was not observed")

    def probe_seasearch(self) -> None:
        name = "codex-hardening-seasearch"
        self.containers.append(name)
        data = self.root / "seasearch-data"
        data.mkdir(mode=0o770)
        cmd = [
            "run", "-d", "--name", name,
            "--read-only", "--user", "1000:1000", "--cap-drop", "ALL",
            "--security-opt", "no-new-privileges:true",
            "--tmpfs", "/run:rw,noexec,nosuid,nodev,size=64m,uid=1000,gid=1000,mode=0770",
            "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=128m",
            "--tmpfs", "/var/tmp:rw,noexec,nosuid,nodev,size=128m",
            "-v", f"{data}:/opt/seasearch/data:rw",
            "-e", "ZINC_FIRST_ADMIN_USER=seasearch",
            "-e", "ZINC_FIRST_ADMIN_PASSWORD=ChangeMe123456",
            "-e", "SS_LOG_TO_STDOUT=true",
            "-e", "SS_LOG_LEVEL=info",
            "-e", "SS_DATA_PATH=/opt/seasearch/data",
            "--entrypoint", "/bin/sh",
            "seafileltd/seasearch:1.0-latest",
            "-c", "exec /opt/seasearch/seasearch",
        ]
        self.docker(cmd)
        time.sleep(3)
        logs = self.logs(name)
        self.assert_no_fs_error("seasearch", logs)
        if "Listen on :4080" not in logs:
            raise RuntimeError("seasearch: expected listener log was not observed")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run targeted Docker hardening probes")
    parser.add_argument("--service", action="append", choices=sorted(SERVICES), help="Service to probe; repeatable")
    args = parser.parse_args()
    selected = args.service or sorted(SERVICES)

    probe = Probe()
    try:
        for service in selected:
            print(f"[probe] {service}")
            getattr(probe, f"probe_{service}")()
            print(f"[ok] {service}")
    finally:
        probe.cleanup()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"[error] {exc}", file=sys.stderr)
        sys.exit(1)
