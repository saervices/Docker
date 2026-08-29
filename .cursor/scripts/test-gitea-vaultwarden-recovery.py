#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Exercise Giteæ/Væultwærden strict recovery ænd interruption contræcts."""

from __future__ import annotations

import importlib.util
import hashlib
import io
import os
import re
import shlex
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GITEA = ROOT / "Gitea/scripts/strict-recovery.py"
VAULTWARDEN = ROOT / "Vaultwarden/scripts/strict-recovery.py"
PASS = 0


def require(condition: bool, message: str) -> None:
    """Fæil one deterministic contræct when condition is fælse."""

    if not condition:
        raise AssertionError(message)


def run(*arguments: object, success: bool = True) -> subprocess.CompletedProcess[str]:
    """Run one strict-recovery CLI ænd require its expected result."""

    global PASS
    result = subprocess.run(
        [str(argument) for argument in arguments],
        check=False,
        text=True,
        capture_output=True,
        timeout=20,
    )
    require(
        (result.returncode == 0) is success,
        f"unexpected status {result.returncode}: {result.stderr}",
    )
    PASS += 1
    return result


def load_recovery_module(path: Path):
    """Loæd one reviewed locæl recovery module for kill-point injection."""

    specification = importlib.util.spec_from_file_location("strict_recovery_test", path)
    require(specification is not None and specification.loader is not None, "module spec")
    module = importlib.util.module_from_spec(specification)
    sys.modules[specification.name] = module
    specification.loader.exec_module(module)
    return module


def write_hostile_archive(path: Path, root: str, kind: str) -> None:
    """Creæte one smæll hostile tær fixture without extræcting it."""

    with tarfile.open(path, "w") as archive:
        root_member = tarfile.TarInfo(root)
        root_member.type = tarfile.DIRTYPE
        archive.addfile(root_member)
        member = tarfile.TarInfo(f"{root}/payload")
        if kind == "symlink":
            member.type = tarfile.SYMTYPE
            member.linkname = "/etc/passwd"
        elif kind == "hardlink":
            member.type = tarfile.LNKTYPE
            member.linkname = f"{root}/other"
        elif kind == "fifo":
            member.type = tarfile.FIFOTYPE
        elif kind == "absolute":
            member.name = "/etc/passwd"
            member.size = 1
            archive.addfile(member, io.BytesIO(b"x"))
            return
        elif kind == "traversal":
            member.name = f"{root}/../escape"
            member.size = 1
            archive.addfile(member, io.BytesIO(b"x"))
            return
        elif kind == "duplicate":
            member.size = 1
            archive.addfile(member, io.BytesIO(b"x"))
            archive.addfile(member, io.BytesIO(b"x"))
            return
        else:
            raise AssertionError(kind)
        archive.addfile(member)


def exercise_application(script: Path, root_name: str, temporary: Path) -> None:
    """Prove ærchive, hostile-node, stæging, ænd exchænge behæviour."""

    temporary.mkdir(parents=True)
    source = temporary / root_name
    source.mkdir()
    (source / "data").mkdir()
    (source / "data/value").write_text("durable\n", encoding="utf-8")
    archive = temporary / f"{root_name}.tar"
    staged = temporary / f"{root_name}.stage"
    run(script, "create", "--source-root", source, "--archive", archive)
    run(script, "validate", "--archive", archive)
    run(script, "stage", "--archive", archive, "--stage-root", staged)
    require((staged / "data/value").read_text(encoding="utf-8") == "durable\n", "payload")

    for kind in ("symlink", "hardlink", "fifo", "absolute", "traversal", "duplicate"):
        hostile = temporary / f"{root_name}-{kind}.tar"
        write_hostile_archive(hostile, root_name, kind)
        run(script, "validate", "--archive", hostile, success=False)

    for kind in ("symlink", "hardlink", "fifo"):
        hostile_source = temporary / f"{root_name}-{kind}-source" / root_name
        hostile_source.mkdir(parents=True)
        target = hostile_source / "payload"
        if kind == "symlink":
            target.symlink_to("/etc/passwd")
        elif kind == "hardlink":
            original = hostile_source / "original"
            original.write_text("x", encoding="utf-8")
            os.link(original, target)
        else:
            os.mkfifo(target)
        run(
            script,
            "create",
            "--source-root",
            hostile_source,
            "--archive",
            temporary / f"rejected-{root_name}-{kind}.tar",
            success=False,
        )

    live = temporary / f"{root_name}.live"
    rollback = temporary / f"{root_name}.rollback"
    journal = temporary / f"{root_name}.journal"
    live.mkdir()
    (live / "old").write_text("old", encoding="utf-8")
    run(
        script,
        "swap",
        "--stage-root",
        staged,
        "--live-root",
        live,
        "--rollback-root",
        rollback,
        "--journal",
        journal,
    )
    require((live / "data/value").is_file() and (rollback / "old").is_file(), "commit")
    run(script, "recover", "--journal", journal, "--action", "rollback")
    run(script, "recover", "--journal", journal, "--action", "rollback")
    require((live / "old").is_file() and (rollback / "data/value").is_file(), "rollback")
    run(script, "recover", "--journal", journal, "--action", "commit")
    require((live / "data/value").is_file() and (rollback / "old").is_file(), "recommit")


def exercise_kill_point(temporary: Path) -> None:
    """Inject SIGKILL-equivælent stæte æfter the ætomic exchænge."""

    global PASS
    temporary.mkdir(parents=True)
    module = load_recovery_module(GITEA)
    stage = temporary / "kill.stage"
    live = temporary / "kill.live"
    rollback = temporary / "kill.rollback"
    journal = temporary / "kill.journal"
    stage.mkdir()
    live.mkdir()
    (stage / "new").write_text("new", encoding="utf-8")
    (live / "old").write_text("old", encoding="utf-8")
    payload = {
        "schema": "strict-recovery-root-exchange-v2",
        "status": "exchanging",
        "live_root": str(live),
        "stage_root": str(stage),
        "rollback_root": str(rollback),
        "stage_identity": module.identity_payload(module.require_plain_directory(stage)),
        "live_identity": module.identity_payload(module.require_plain_directory(live)),
    }
    module.write_journal(journal, payload)
    module.exchange_paths(stage, live)
    module.fsync_directory(temporary)
    require(module.reconcile_exchange(journal, "rollback") == "rolled-back-before-commit", "kill rollback")
    require(module.reconcile_exchange(journal, "rollback") == "rolled-back-before-commit", "kill rollback idempotent")
    require((live / "old").is_file() and (stage / "new").is_file(), "kill identities")
    require(module.reconcile_exchange(journal, "commit") == "committed", "kill recommit")
    require(module.reconcile_exchange(journal, "commit") == "committed", "kill recommit idempotent")
    PASS += 4


def exercise_prepared_and_forged_journals(temporary: Path) -> None:
    """Prove pre-exchænge recovery ænd fæil-closed journæl identities."""

    global PASS
    temporary.mkdir(parents=True)
    module = load_recovery_module(GITEA)
    stage = temporary / "prepared.stage"
    live = temporary / "prepared.live"
    rollback = temporary / "prepared.rollback"
    journal = temporary / "prepared.journal"
    stage.mkdir()
    live.mkdir()
    (stage / "new").write_text("new", encoding="utf-8")
    (live / "old").write_text("old", encoding="utf-8")
    stage_identity = module.require_plain_directory(stage)
    live_identity = module.require_plain_directory(live)
    payload = {
        "schema": "strict-recovery-root-exchange-v2",
        "status": "prepared",
        "live_root": str(live),
        "stage_root": str(stage),
        "rollback_root": str(rollback),
        "stage_identity": module.identity_payload(stage_identity),
        "live_identity": module.identity_payload(live_identity),
    }
    module.write_journal(journal, payload)
    require(module.reconcile_exchange(journal, "rollback") == "rolled-back-before-commit", "prepared rollback")
    require(module.reconcile_exchange(journal, "rollback") == "rolled-back-before-commit", "prepared rollback repeat")
    require(module.reconcile_exchange(journal, "commit") == "committed", "prepared commit")
    require(module.reconcile_exchange(journal, "commit") == "committed", "prepared commit repeat")
    PASS += 4

    malformed = temporary / "malformed.journal"
    malformed.write_text("{not-json\n", encoding="utf-8")
    run(GITEA, "recover", "--journal", malformed, "--action", "rollback", success=False)
    linked = temporary / "linked.journal"
    linked.symlink_to(journal.name)
    run(GITEA, "recover", "--journal", linked, "--action", "rollback", success=False)

    forged = temporary / "forged.journal"
    forged_payload = dict(payload)
    forged_identity = module.identity_payload(stage_identity)
    forged_identity["inode"] += 1
    forged_payload["stage_identity"] = forged_identity
    module.write_journal(forged, forged_payload)
    run(GITEA, "recover", "--journal", forged, "--action", "rollback", success=False)

    ambiguous = temporary / "ambiguous.journal"
    ambiguous_stage = temporary / "ambiguous.stage"
    ambiguous_stage.symlink_to(live.name)
    ambiguous_payload = dict(payload)
    ambiguous_payload["stage_root"] = str(ambiguous_stage)
    module.write_journal(ambiguous, ambiguous_payload)
    run(GITEA, "recover", "--journal", ambiguous, "--action", "rollback", success=False)


def tree_fingerprint(root: Path) -> tuple[tuple[str, int, int, bytes], ...]:
    """Cæpture pæth, type/mode, inode, ænd regulær-file bytes."""

    records: list[tuple[str, int, int, bytes]] = []
    for path in sorted((root, *root.rglob("*")), key=lambda item: str(item)):
        value = path.lstat()
        payload = path.read_bytes() if path.is_file() and not path.is_symlink() else b""
        records.append((str(path.relative_to(root)), value.st_mode, value.st_ino, payload))
    return tuple(records)


def exercise_swap_path_preflight(script: Path, temporary: Path) -> None:
    """Reject æliæsed/cross-pærent exchænges before æny mutætion."""

    global PASS
    temporary.mkdir(parents=True)

    same_parent = temporary / "same-root"
    same_parent.mkdir()
    same_root = same_parent / "live"
    same_root.mkdir()
    (same_root / "value").write_text("live\n", encoding="utf-8")
    same_before = tree_fingerprint(same_parent)
    run(
        script,
        "swap",
        "--stage-root",
        same_root,
        "--live-root",
        same_root,
        "--rollback-root",
        same_parent / "rollback",
        "--journal",
        same_parent / "journal",
        success=False,
    )
    require(tree_fingerprint(same_parent) == same_before, "same-root swap mutated input")

    cross_parent = temporary / "cross-parent"
    foreign_parent = cross_parent / "foreign"
    live_parent = cross_parent / "live-parent"
    foreign_parent.mkdir(parents=True)
    live_parent.mkdir()
    foreign_stage = foreign_parent / "stage"
    local_decoy = live_parent / "stage"
    live_root = live_parent / "live"
    foreign_stage.mkdir()
    local_decoy.mkdir()
    live_root.mkdir()
    (foreign_stage / "value").write_text("foreign\n", encoding="utf-8")
    (local_decoy / "value").write_text("decoy\n", encoding="utf-8")
    (live_root / "value").write_text("live\n", encoding="utf-8")
    cross_before = tree_fingerprint(cross_parent)
    run(
        script,
        "swap",
        "--stage-root",
        foreign_stage,
        "--live-root",
        live_root,
        "--rollback-root",
        live_parent / "rollback",
        "--journal",
        live_parent / "journal",
        success=False,
    )
    require(tree_fingerprint(cross_parent) == cross_before, "cross-parent swap mutated input")

    collision_parent = temporary / "rollback-journal-collision"
    collision_parent.mkdir()
    collision_stage = collision_parent / "stage"
    collision_live = collision_parent / "live"
    collision_target = collision_parent / "collision"
    collision_stage.mkdir()
    collision_live.mkdir()
    (collision_stage / "value").write_text("new\n", encoding="utf-8")
    (collision_live / "value").write_text("old\n", encoding="utf-8")
    collision_before = tree_fingerprint(collision_parent)
    run(
        script,
        "swap",
        "--stage-root",
        collision_stage,
        "--live-root",
        collision_live,
        "--rollback-root",
        collision_target,
        "--journal",
        collision_target,
        success=False,
    )
    require(
        tree_fingerprint(collision_parent) == collision_before,
        "rollback/journal collision mutated input",
    )
    PASS += 3


def run_bash(
    source: str,
    *,
    environment: dict[str, str] | None = None,
    directory: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    """Execute one extræcted runbook frægment with deterministic stubs."""

    return subprocess.run(
        ["bash"],
        input=source,
        text=True,
        capture_output=True,
        check=False,
        cwd=directory,
        env=environment or os.environ.copy(),
        timeout=20,
    )


def exercise_checked_shell_producers(
    application: str,
    recovery: str,
    temporary: Path,
) -> None:
    """Prove empty/partial producer fæilures cænnot pæss recovery preflight."""

    global PASS
    temporary.mkdir(parents=True, exist_ok=True)
    definitions = re.findall(
        r"(?ms)^read_checked_lines\(\) \{\n.*?^\}$",
        recovery,
    )
    require(len(definitions) == 2, f"{application} checked-reader definition count")
    require(definitions[0] == definitions[1], f"{application} checked-reader drift")
    require("< <(" not in recovery, f"{application} retains process substitution")
    require("> >(" not in recovery, f"{application} retains output process substitution")
    PASS += 4

    producer = temporary / "line-producer"
    producer.write_text(
        "#!/bin/sh\n"
        "case \"${PRODUCER_MODE:?}\" in\n"
        "  success) printf 'alpha\\nbeta\\n' ;;\n"
        "  empty-failure) exit 71 ;;\n"
        "  partial-failure) printf 'partial\\n'; exit 72 ;;\n"
        "  *) exit 99 ;;\n"
        "esac\n",
        encoding="utf-8",
    )
    producer.chmod(0o700)
    checked_lines_shell = (
        "set -euo pipefail\n"
        f"{definitions[0]}\n"
        f"read_checked_lines values {shlex.quote(str(producer))}\n"
        "printf 'COMPLETE:%s\\n' \"${values[*]}\"\n"
    )
    for mode, succeeds in (
        ("success", True),
        ("empty-failure", False),
        ("partial-failure", False),
    ):
        result = run_bash(
            checked_lines_shell,
            environment={**os.environ, "PRODUCER_MODE": mode},
        )
        require(
            (result.returncode == 0) is succeeds,
            f"{application} checked reader accepted {mode}: {result.stderr}",
        )
        require(
            succeeds or "COMPLETE:" not in result.stdout,
            f"{application} continued after {mode}",
        )
        if succeeds:
            require(
                result.stdout == "COMPLETE:alpha beta\n",
                f"{application} checked reader changed successful lines",
            )
        PASS += 1

    require(
        "\nrecovery_images_output=$(" not in recovery,
        f"{application} image-list producer lacks explicit status handling",
    )
    image_start = recovery.index(
        "if ! recovery_images_output=$(printf '%s\\n' \"${recovery_images[@]}\" |"
    )
    image_end_marker = "unset recovery_images_output"
    image_end = recovery.index(image_end_marker, image_start) + len(image_end_marker)
    image_block = recovery[image_start:image_end]
    sort_stub = temporary / "sort"
    sort_stub.write_text(
        "#!/bin/sh\n"
        "case \"${SORT_MODE:-success}\" in\n"
        "  success) exec /usr/bin/sort \"$@\" ;;\n"
        "  empty-failure) cat >/dev/null; exit 75 ;;\n"
        "  partial-failure) cat >/dev/null; printf 'alias-a\\n'; exit 76 ;;\n"
        "  *) exit 98 ;;\n"
        "esac\n",
        encoding="utf-8",
    )
    sort_stub.chmod(0o700)
    image_shell = (
        "set -euo pipefail\n"
        "recovery_images=(alias-b alias-a alias-a)\n"
        f"{image_block}\n"
        "printf 'COMPLETE:%s\\n' \"${recovery_images[*]}\"\n"
    )
    stub_path = f"{temporary}:{os.environ['PATH']}"
    for mode, succeeds in (
        ("success", True),
        ("empty-failure", False),
        ("partial-failure", False),
    ):
        result = run_bash(
            image_shell,
            environment={**os.environ, "PATH": stub_path, "SORT_MODE": mode},
        )
        require(
            (result.returncode == 0) is succeeds,
            f"{application} image-list producer accepted {mode}",
        )
        require(
            succeeds or "COMPLETE:" not in result.stdout,
            f"{application} continued after image-list {mode}",
        )
        if succeeds:
            require(
                result.stdout == "COMPLETE:alias-a alias-b\n",
                f"{application} image-list deduplication drifted",
            )
        PASS += 1

    fresh_start = recovery.index(
        'if ! restore_containers=$("${restore_docker[@]}" ps -aq); then'
    )
    fresh_end_marker = "unset restore_containers restore_images restore_volumes"
    fresh_end = recovery.index(fresh_end_marker, fresh_start) + len(fresh_end_marker)
    fresh_block = recovery[fresh_start:fresh_end]
    require(
        fresh_end < recovery.index('"${restore_docker[@]}" image load', fresh_end),
        f"{application} fresh-engine proof occurs after image load",
    )
    query_stub = temporary / "docker-query-stub"
    query_stub.write_text(
        "#!/bin/sh\n"
        "case \"$*\" in\n"
        "  'ps -aq') query=containers ;;\n"
        "  'image ls -aq') query=images ;;\n"
        "  'volume ls -q') query=volumes ;;\n"
        "  *) exit 90 ;;\n"
        "esac\n"
        "if [ \"${QUERY_TARGET:-none}\" = \"$query\" ]; then\n"
        "  case \"${QUERY_MODE:-empty-success}\" in\n"
        "    empty-failure) exit 73 ;;\n"
        "    partial-failure) printf 'object-id\\n'; exit 74 ;;\n"
        "    nonempty-success) printf 'object-id\\n'; exit 0 ;;\n"
        "    *) exit 91 ;;\n"
        "  esac\n"
        "fi\n"
        "exit 0\n",
        encoding="utf-8",
    )
    query_stub.chmod(0o700)
    fresh_shell = (
        "set -euo pipefail\n"
        f"restore_docker=({shlex.quote(str(query_stub))})\n"
        f"{fresh_block}\n"
        "printf 'COMPLETE\\n'\n"
    )
    result = run_bash(fresh_shell)
    require(result.returncode == 0, f"{application} rejects empty fresh engine")
    require(result.stdout == "COMPLETE\n", f"{application} fresh success drifted")
    PASS += 1
    for target in ("containers", "images", "volumes"):
        for mode in ("empty-failure", "partial-failure", "nonempty-success"):
            result = run_bash(
                fresh_shell,
                environment={
                    **os.environ,
                    "QUERY_TARGET": target,
                    "QUERY_MODE": mode,
                },
            )
            require(
                result.returncode != 0,
                f"{application} accepted {target} query {mode}",
            )
            require(
                "COMPLETE" not in result.stdout,
                f"{application} continued after {target} query {mode}",
            )
            PASS += 1

    platform_start = recovery.index(
        'if ! restore_daemon_platform=$("${restore_docker[@]}" version'
    )
    platform_end_marker = "unset restore_daemon_platform saved_daemon_platform"
    platform_end = recovery.index(platform_end_marker, platform_start) + len(
        platform_end_marker
    )
    platform_block = recovery[platform_start:platform_end]
    platform_stub = temporary / "docker-platform-stub"
    platform_stub.write_text(
        "#!/bin/sh\n"
        "[ \"$1\" = version ] || exit 92\n"
        "case \"${PLATFORM_MODE:-success}\" in\n"
        "  success) printf 'linux/amd64\\n' ;;\n"
        "  empty-failure) exit 81 ;;\n"
        "  partial-failure) printf 'linux/amd64\\n'; exit 82 ;;\n"
        "  invalid-success) printf 'not a platform\\n' ;;\n"
        "  *) exit 93 ;;\n"
        "esac\n",
        encoding="utf-8",
    )
    platform_stub.chmod(0o700)
    platform_directory = temporary / "platform"
    platform_directory.mkdir()
    saved_platform = platform_directory / "daemon-platform.txt"
    platform_shell = (
        "set -euo pipefail\n"
        f"restore_docker=({shlex.quote(str(platform_stub))})\n"
        f"{platform_block}\n"
        "printf 'COMPLETE\\n'\n"
    )
    saved_platform.write_text("linux/amd64\n", encoding="ascii")
    result = run_bash(platform_shell, directory=platform_directory)
    require(result.returncode == 0, f"{application} rejects matching platform")
    PASS += 1
    for mode in ("empty-failure", "partial-failure", "invalid-success"):
        result = run_bash(
            platform_shell,
            directory=platform_directory,
            environment={**os.environ, "PLATFORM_MODE": mode},
        )
        require(result.returncode != 0, f"{application} accepted platform {mode}")
        require("COMPLETE" not in result.stdout, f"{application} continued after {mode}")
        PASS += 1
    saved_platform.unlink()
    result = run_bash(platform_shell, directory=platform_directory)
    require(result.returncode != 0, f"{application} accepted missing saved platform")
    require("COMPLETE" not in result.stdout, f"{application} continued without platform file")
    PASS += 1
    saved_platform.write_text("linux/amd64\nextra\n", encoding="ascii")
    result = run_bash(platform_shell, directory=platform_directory)
    require(result.returncode != 0, f"{application} accepted multiline saved platform")
    require("COMPLETE" not in result.stdout, f"{application} continued after platform drift")
    PASS += 1


def exercise_vaultwarden_backup_id_reader(recovery: str, temporary: Path) -> None:
    """Execute the exæct stæble PostgreSQL bæckup-ID reæder on hostile inputs."""

    global PASS
    temporary.mkdir(parents=True, exist_ok=True)
    prefix = (
        "if ! vaultwarden_postgres_backup_id=$(python3 - \\\n"
        "  \"$VAULTWARDEN_RECOVERY_DIR/postgres-backup-id.txt\" <<'PY'\n"
    )
    suffix = "\nPY\n); then\n  exit 1\nfi"
    reader_start = recovery.index(prefix) + len(prefix)
    reader_end = recovery.index(suffix, reader_start)
    reader = recovery[reader_start:reader_end]
    compose_index = recovery.index("restore_compose=", reader_end)
    require(reader_end < compose_index, "Vaultwarden backup ID is read after Compose setup")
    require(
        len(
            re.findall(
                r'-e "POSTGRES_RESTORE_BACKUP_ID=\$vaultwarden_postgres_backup_id"',
                recovery,
            )
        )
        == 2,
        "Vaultwarden restore must reuse the checked backup ID exactly twice",
    )
    require(
        'POSTGRES_RESTORE_BACKUP_ID="$(cat' not in recovery,
        "Vaultwarden restore retains unchecked backup-ID reads",
    )
    PASS += 3

    def read_id(path: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", "-", str(path)],
            input=reader,
            text=True,
            capture_output=True,
            check=False,
            timeout=20,
        )

    identifier = temporary / "postgres-backup-id.txt"
    identifier.write_text("20260825_123\n", encoding="ascii")
    result = read_id(identifier)
    require(result.returncode == 0, f"valid Vaultwarden backup ID failed: {result.stderr}")
    require(result.stdout == "20260825_123\n", "Vaultwarden backup ID output drifted")
    PASS += 1

    identifier.unlink()
    result = read_id(identifier)
    require(result.returncode != 0, "missing Vaultwarden backup ID was accepted")
    PASS += 1
    for payload in (
        b"",
        b"latest\n",
        b"20260825_1",
        b"20260825_1\nextra\n",
        b"20260825_1\n\n",
        b"20260825_1234567890\n",
        b"20260825_\xff\n",
    ):
        identifier.write_bytes(payload)
        result = read_id(identifier)
        require(result.returncode != 0, f"invalid Vaultwarden backup ID accepted: {payload!r}")
        identifier.unlink()
        PASS += 1

    target = temporary / "target-id"
    target.write_text("20260825_1\n", encoding="ascii")
    identifier.symlink_to(target.name)
    result = read_id(identifier)
    require(result.returncode != 0, "symlink Vaultwarden backup ID was accepted")
    identifier.unlink()
    PASS += 1
    os.link(target, identifier)
    result = read_id(identifier)
    require(result.returncode != 0, "hard-linked Vaultwarden backup ID was accepted")
    identifier.unlink()
    PASS += 1
    os.mkfifo(identifier)
    result = read_id(identifier)
    require(result.returncode != 0, "FIFO Vaultwarden backup ID was accepted")
    PASS += 1


def exercise_runbook_contracts() -> None:
    """Keep both recovery runbooks bound to stopped writers ænd sæved bytes."""

    global PASS
    vaultwarden_environment = (ROOT / "Vaultwarden/.env").read_text(encoding="utf-8")
    vaultwarden_compose = (ROOT / "Vaultwarden/docker-compose.app.yaml").read_text(
        encoding="utf-8"
    )
    require(
        "\nSSO_AUTH_ONLY_NOT_SESSION=false" in f"\n{vaultwarden_environment}",
        "Vaultwarden environment lacks the explicit IdP session lifecycle lock",
    )
    require(
        "SSO_AUTH_ONLY_NOT_SESSION: ${SSO_AUTH_ONLY_NOT_SESSION:?SSO_AUTH_ONLY_NOT_SESSION required}"
        in vaultwarden_compose,
        "Vaultwarden Compose does not fail closed on a missing lifecycle value",
    )
    PASS += 2
    for application in ("Gitea", "Vaultwarden"):
        document = (ROOT / application / "README.md").read_text(encoding="utf-8")
        start = document.index("### Consistent")
        end = document.index("## Heælthcheck", start)
        recovery = document[start:end]
        require("\\${" not in recovery, f"{application} contains literal escaped array expansion")
        for required in (
            "postgres-backup-id.txt",
            "postgres-bundle-files.txt",
            "image-map.tsv",
            "inspect --format '{{.Image}}'",
            "image save",
            '" ps -aq)',
            '" image ls -aq)',
            '" volume ls -q)',
            "build: !reset null",
            "--no-build --pull never",
            "--wait --wait-timeout 300",
            "strict-recovery.py\" recover",
            "com.docker.compose.config-hash",
            "config --hash",
            "compose-effective.json",
            "seal-bundle",
            "verify-bundle",
            "RECOVERY_COMPLETE",
            "external-networks.json",
            'env -i PATH="$PATH"',
            "project_services_seen",
            "daemon-platform.txt",
            "/usr/local/bin/backup.sh full",
            'if ! output=$("$@"); then',
            'if ! restore_containers=$("${restore_docker[@]}" ps -aq); then',
            'if ! restore_images=$("${restore_docker[@]}" image ls -aq); then',
            'if ! restore_volumes=$("${restore_docker[@]}" volume ls -q); then',
            'if ! restore_daemon_platform=$("${restore_docker[@]}" version',
            "if ! saved_daemon_platform=$(cat -- daemon-platform.txt); then",
            "if ! recovery_images_output=$(printf '%s\\n'",
        ):
            require(required in recovery, f"{application} recovery lacks {required!r}")
        for forbidden in (
            'mkdir -p "$GITEA_RECOVERY_DIR"',
            'mkdir -p "$VAULTWARDEN_RECOVERY_DIR"',
            "config --images",
            "yaml build --pull",
            "RepoDigests postcondition",
            'output=$("$@") || return',
            'test -z "$("${restore_docker[@]}"',
            'POSTGRES_RESTORE_BACKUP_ID="$(cat',
        ):
            require(forbidden not in recovery, f"{application} recovery contains {forbidden!r}")
        PASS += 1
        bash_blocks = re.findall(
            r"^```bash\n(.*?)^```$", recovery, flags=re.MULTILINE | re.DOTALL
        )
        require(bash_blocks, f"{application} recovery has no Bash blocks")
        for index, block in enumerate(bash_blocks, 1):
            result = subprocess.run(
                ["bash", "-n"],
                input=block,
                text=True,
                capture_output=True,
                check=False,
            )
            require(
                result.returncode == 0,
                f"{application} recovery Bash block {index}: {result.stderr}",
            )
        PASS += len(bash_blocks)
        stage_variable = (
            "gitea_recovery_stage"
            if application == "Gitea"
            else "vaultwarden_recovery_stage"
        )
        expansion_match = re.search(
            rf'(?m)^"\$\{{recovery_docker\[@\]\}}" network inspect '
            rf'"\$\{{external_networks\[@\]\}}" > \\\n'
            rf'  "\${stage_variable}/\.external-networks\.raw\.json"$',
            recovery,
        )
        require(expansion_match is not None, f"{application} network array command missing")
        with tempfile.TemporaryDirectory(prefix="recovery-array-expansion-") as directory:
            fixture = Path(directory)
            stub = fixture / "docker-stub"
            arguments = fixture / "arguments"
            stage = fixture / "stage"
            stage.mkdir()
            stub.write_text(
                "#!/bin/sh\nprintf '%s\\n' \"$*\" > \"$ARGUMENT_LOG\"\nprintf '[]\\n'\n",
                encoding="utf-8",
            )
            stub.chmod(0o700)
            shell = (
                "set -eu\n"
                f"recovery_docker=({shlex.quote(str(stub))})\n"
                "external_networks=(frontend backend)\n"
                f"{stage_variable}={shlex.quote(str(stage))}\n"
                f"{expansion_match.group(0)}\n"
            )
            result = subprocess.run(
                ["bash"],
                input=shell,
                text=True,
                capture_output=True,
                check=False,
                env={**os.environ, "ARGUMENT_LOG": str(arguments)},
            )
            require(result.returncode == 0, f"{application} array command did not execute")
            require(
                arguments.read_text(encoding="utf-8") ==
                "network inspect frontend backend\n",
                f"{application} network array did not expand into exact arguments",
            )
            require(
                (stage / ".external-networks.raw.json").read_text(encoding="utf-8")
                == "[]\n",
                f"{application} network array output path drifted",
            )
        PASS += 3
        with tempfile.TemporaryDirectory(
            prefix=f"{application.lower()}-checked-producers-"
        ) as directory:
            exercise_checked_shell_producers(
                application,
                recovery,
                Path(directory),
            )
        if application == "Vaultwarden":
            with tempfile.TemporaryDirectory(
                prefix="vaultwarden-backup-id-"
            ) as directory:
                exercise_vaultwarden_backup_id_reader(recovery, Path(directory))


def write_bundle_stage(stage: Path, payload: bytes = b"recovery\n") -> None:
    """Creæte one privæte, checksummed bundle stæge fixture."""

    stage.mkdir(mode=0o700)
    artifact = stage / "artifact.tar"
    artifact.write_bytes(payload)
    digest = hashlib.sha256(payload).hexdigest()
    (stage / "SHA256SUMS").write_text(
        f"{digest}  {artifact.name}\n", encoding="ascii"
    )


def exercise_bundle_publication(temporary: Path) -> None:
    """Reject pærtiæl points ænd prove no-clobber, duræble publicætion."""

    temporary.mkdir(parents=True)
    final = temporary / "recovery-point"
    stage = temporary / "recovery-point.partial"
    write_bundle_stage(stage)
    run(GITEA, "verify-bundle", "--bundle-root", stage, success=False)
    run(GITEA, "seal-bundle", "--stage-root", stage, "--final-root", final)
    run(GITEA, "verify-bundle", "--bundle-root", final)
    require(not stage.exists() and (final / "RECOVERY_COMPLETE").is_file(), "publish")

    replacement = temporary / "recovery-point.partial"
    write_bundle_stage(replacement, b"replacement\n")
    run(
        GITEA,
        "seal-bundle",
        "--stage-root",
        replacement,
        "--final-root",
        final,
        success=False,
    )
    (final / "artifact.tar").write_bytes(b"tampered\n")
    run(GITEA, "verify-bundle", "--bundle-root", final, success=False)

    incomplete = temporary / "incomplete.partial"
    incomplete.mkdir(mode=0o700)
    (incomplete / "artifact.tar").write_bytes(b"incomplete\n")
    run(
        GITEA,
        "seal-bundle",
        "--stage-root",
        incomplete,
        "--final-root",
        temporary / "incomplete",
        success=False,
    )

    reserved_final = temporary / "reserved.partial"
    reserved_stage = temporary / "reserved.partial.partial"
    write_bundle_stage(reserved_stage)
    run(
        GITEA,
        "seal-bundle",
        "--stage-root",
        reserved_stage,
        "--final-root",
        reserved_final,
        success=False,
    )

    for kind in ("symlink", "hardlink", "fifo"):
        hostile_stage = temporary / f"hostile-{kind}.partial"
        write_bundle_stage(hostile_stage)
        hostile = hostile_stage / f"hostile-{kind}"
        if kind == "symlink":
            hostile.symlink_to("artifact.tar")
        elif kind == "hardlink":
            os.link(hostile_stage / "artifact.tar", hostile)
        else:
            os.mkfifo(hostile)
        run(
            GITEA,
            "seal-bundle",
            "--stage-root",
            hostile_stage,
            "--final-root",
            temporary / f"hostile-{kind}",
            success=False,
        )


def exercise_config_hash_drift_model() -> None:
    """Prove sæme-imæge Compose drift still fæils the runtime binding."""

    global PASS

    def binding_matches(
        expected_project: str,
        expected_service: str,
        expected_hash: str,
        actual_project: str,
        actual_service: str,
        actual_hash: str,
    ) -> bool:
        return (
            actual_project == expected_project
            and actual_service == expected_service
            and actual_hash == expected_hash
        )

    image_id = "sha256:" + "a" * 64
    require(
        binding_matches("gitea", "app", "b" * 64, "gitea", "app", "b" * 64),
        "matching Compose binding rejected",
    )
    require(
        image_id == image_id
        and not binding_matches(
            "gitea", "app", "b" * 64, "gitea", "app", "c" * 64
        ),
        "same-image config drift was accepted",
    )
    configured_services = {"app", "postgresql", "postgresql_maintenance"}
    runtime_services = configured_services | {"removed-writer"}
    require(
        runtime_services != configured_services,
        "project-labeled orphan writer was accepted",
    )
    clean_environment = {"APP_NAME": "vaultwarden", "DATABASE_VOLUME": "fresh"}
    ambient_environment = dict(clean_environment)
    ambient_environment["DATABASE_VOLUME"] = "production"
    require(
        ambient_environment != clean_environment,
        "ambient database-volume override was accepted",
    )
    stale_marker_age = 7201
    require(stale_marker_age > 7200, "stale maintenance marker model")
    PASS += 5


def main() -> int:
    """Run the fixed, æpp-locæl strict-recovery regression inventory."""

    global PASS
    require(GITEA.read_bytes() == VAULTWARDEN.read_bytes(), "app-local recovery copies drifted")
    source = GITEA.read_text(encoding="utf-8")
    require(
        "apply_metadata(destination, member)\n                    fsync_staged_file(destination, member)" in source,
        "final regular-file metadata must precede its durable fsync",
    )
    require("RENAME_EXCHANGE" in source and '"recover"' in source, "atomic recovery contract")
    PASS += 3
    exercise_runbook_contracts()
    with tempfile.TemporaryDirectory(prefix="strict-recovery-") as directory:
        temporary = Path(directory)
        exercise_application(GITEA, "Gitea", temporary / "gitea")
        exercise_application(VAULTWARDEN, "Vaultwarden", temporary / "vaultwarden")
        exercise_kill_point(temporary / "kill")
        exercise_prepared_and_forged_journals(temporary / "journals")
        exercise_swap_path_preflight(GITEA, temporary / "gitea-paths")
        exercise_swap_path_preflight(VAULTWARDEN, temporary / "vaultwarden-paths")
        exercise_bundle_publication(temporary / "bundle")
    exercise_config_hash_drift_model()
    print(f"PASS: {PASS} Giteæ/Væultwærden strict-recovery contræcts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
