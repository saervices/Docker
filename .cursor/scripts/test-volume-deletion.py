#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Regression tests for fæil-closed run.sh Docker-volume deletion."""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
RUN_SH = REPO_ROOT / "run.sh"

DOCKER_STUB = r"""#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${DOCKER_LOG:?}"

if [[ "${1:-}" == "compose" && "${2:-}" == "version" ]]; then
  printf 'Docker Compose version v2.39.0\n'
  exit 0
fi

if [[ "${1:-}" == "compose" ]]; then
  action=""
  for argument in "$@"; do
    case "$argument" in
      config|ps|down)
        action="$argument"
        ;;
    esac
  done

  case "$action" in
    config)
      [[ "${DOCKER_SCENARIO:-}" != "config_fail" ]] || exit 42
      case "${DOCKER_SCENARIO:-}" in
        missing_project)
          printf '%s\n' '{"services":{"app":{"image":"busybox:latest"}},"volumes":{"data":{"name":"fixture_data"}}}'
          ;;
        invalid_volume)
          printf '%s\n' '{"name":"fixture","services":{"app":{"image":"busybox:latest"}},"volumes":{"data":{}}}'
          ;;
        external_only)
          printf '%s\n' '{"name":"fixture","services":{"app":{"image":"busybox:latest"}},"volumes":{"shared":{"name":"shared_external","external":true}}}'
          ;;
        duplicate_name)
          printf '%s\n' '{"name":"fixture","services":{"app":{"image":"busybox:latest"}},"volumes":{"data":{"name":"fixture_data"},"alias":{"name":"fixture_data"}}}'
          ;;
        *)
          printf '%s\n' '{"name":"fixture","services":{"app":{"image":"busybox:latest"}},"volumes":{"data":{"name":"fixture_data"},"custom":{"name":"custom_volume"},"shared":{"name":"shared_external","external":true}}}'
          ;;
      esac
      ;;
    ps)
      [[ "${DOCKER_SCENARIO:-}" != "ps_fail" ]] || exit 43
      [[ "${DOCKER_RUNNING:-false}" != "true" ]] || printf 'container-id\n'
      ;;
    down)
      [[ "${DOCKER_SCENARIO:-}" != "down_fail" ]] || exit 44
      ;;
    *)
      exit 45
      ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "volume" && "${2:-}" == "ls" ]]; then
  [[ "${DOCKER_SCENARIO:-}" != "volume_list_fail" ]] || exit 46
  if [[ "${DOCKER_SCENARIO:-}" == "no_existing" ]]; then
    printf 'unrelated_volume\n'
  else
    printf 'fixture_data\ncustom_volume\nshared_external\nunrelated_volume\n'
  fi
  exit 0
fi

if [[ "${1:-}" == "volume" && "${2:-}" == "rm" ]]; then
  if [[ "${DOCKER_SCENARIO:-}" == "rm_fail" && "${3:-}" == "custom_volume" ]]; then
    exit 47
  fi
  exit 0
fi

exit 48
"""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def run_case(
    name: str,
    *,
    confirmation: str = "",
    scenario: str = "",
    running: bool = False,
    extra_args: tuple[str, ...] = (),
) -> tuple[subprocess.CompletedProcess[str], list[str]]:
    case_root = Path(tempfile.mkdtemp(prefix=f"run-volume-{name}.", dir="/tmp"))
    try:
        project = case_root / "Fixture"
        stub_dir = case_root / "bin"
        project.mkdir()
        stub_dir.mkdir()
        shutil.copy2(RUN_SH, case_root / "run.sh")
        (case_root / "run.sh").chmod(0o755)
        (project / ".env").write_text("APP_NAME=fixture\n", encoding="utf-8")
        (project / "docker-compose.main.yaml").write_text(
            "services:\n  app:\n    image: busybox:latest\nvolumes:\n  data:\n",
            encoding="utf-8",
        )
        docker_stub = stub_dir / "docker"
        docker_stub.write_text(DOCKER_STUB, encoding="utf-8")
        docker_stub.chmod(0o755)
        call_log = case_root / "docker.calls"

        environment = os.environ.copy()
        environment.update(
            {
                "PATH": f"{stub_dir}:{environment['PATH']}",
                "DOCKER_LOG": str(call_log),
                "DOCKER_SCENARIO": scenario,
                "DOCKER_RUNNING": "true" if running else "false",
            }
        )
        result = subprocess.run(
            [str(case_root / "run.sh"), "Fixture", "--delete_volumes", *extra_args],
            cwd=case_root,
            env=environment,
            input=confirmation,
            text=True,
            capture_output=True,
            check=False,
        )
        calls = call_log.read_text(encoding="utf-8").splitlines() if call_log.exists() else []
        return result, calls
    finally:
        shutil.rmtree(case_root)


def mutation_calls(calls: list[str]) -> list[str]:
    return [call for call in calls if " down " in f" {call} " or call.startswith("volume rm ")]


def main() -> None:
    result, calls = run_case("eof")
    require(result.returncode != 0, "EOF confirmation must fail")
    require(not mutation_calls(calls), "EOF confirmation mutated Docker state")

    result, calls = run_case("mismatch", confirmation="DELETE wrong\n")
    require(result.returncode != 0, "mismatched confirmation must fail")
    require(not mutation_calls(calls), "mismatched confirmation mutated Docker state")

    result, calls = run_case("force", extra_args=("--force",))
    require(result.returncode != 0, "--force must not bypass typed confirmation")
    require(not mutation_calls(calls), "--force bypassed deletion confirmation")

    result, calls = run_case("dry-run", extra_args=("--dry-run",), running=True)
    require(result.returncode == 0, "dry-run must succeed")
    require(not mutation_calls(calls), "dry-run mutated Docker state")

    result, calls = run_case("stopped", confirmation="DELETE fixture\n")
    require(result.returncode == 0, "confirmed stopped-project deletion failed")
    require("volume rm fixture_data" in calls, "default volume was not removed")
    require("volume rm custom_volume" in calls, "custom rendered volume name was not removed")
    require("volume rm shared_external" not in calls, "external volume was removed")
    require("volume rm unrelated_volume" not in calls, "unrelated volume was removed")
    require(not any(" down " in f" {call} " for call in calls), "stopped project was unnecessarily shut down")

    result, calls = run_case("running", confirmation="DELETE fixture\n", running=True)
    require(result.returncode == 0, "confirmed running-project deletion failed")
    down_index = next(index for index, call in enumerate(calls) if " down " in f" {call} ")
    first_rm = next(index for index, call in enumerate(calls) if call.startswith("volume rm "))
    require(down_index < first_rm, "volume removal preceded Compose shutdown")

    for scenario in ("missing_project", "invalid_volume"):
        result, calls = run_case(scenario, scenario=scenario)
        require(result.returncode != 0, f"{scenario} must fail")
        require(not mutation_calls(calls), f"{scenario} mutated Docker state")

    for scenario in ("external_only", "no_existing"):
        result, calls = run_case(scenario, scenario=scenario)
        require(result.returncode == 0, f"{scenario} must be a safe no-op")
        require(not mutation_calls(calls), f"{scenario} mutated Docker state")

    result, calls = run_case(
        "duplicate-name", confirmation="DELETE fixture\n", scenario="duplicate_name"
    )
    require(result.returncode == 0, "duplicate rendered volume names must be de-duplicated")
    require(calls.count("volume rm fixture_data") == 1, "duplicate volume was removed more than once")

    for scenario in ("config_fail", "volume_list_fail", "ps_fail", "down_fail"):
        result, calls = run_case(
            scenario,
            confirmation="DELETE fixture\n",
            scenario=scenario,
            running=scenario == "down_fail",
        )
        require(result.returncode != 0, f"{scenario} must fail")
        require(not any(call.startswith("volume rm ") for call in calls), f"{scenario} removed a volume")

    result, calls = run_case("rm-fail", confirmation="DELETE fixture\n", scenario="rm_fail")
    require(result.returncode != 0, "volume removal failure must propagate")
    require("volume rm custom_volume" in calls, "removal failure path was not exercised")

    print("PASS: 16 fail-closed Docker-volume deletion scenarios")


if __name__ == "__main__":
    main()
