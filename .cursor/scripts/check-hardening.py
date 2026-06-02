#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""
Stætic Docker Compose hærdening checks.

This script is intentionælly Docker-free so it cæn run in pre-commit. Runtime
contæiner probes belong in probe-container-hardening.py.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]

ALLOW_MISSING_READ_ONLY = {
    ("Kimai/docker-compose.app.yaml", "app"),
    ("Seafile/docker-compose.app.yaml", "app"),
    ("templates/collabora/docker-compose.collabora.yaml", "collabora"),
    ("templates/seafile_seadoc-server/docker-compose.seafile_seadoc-server.yaml", "seafile_seadoc-server"),
}

HIGH_RISK_CAPS = {"SYS_ADMIN", "SYS_MODULE", "SYS_PTRACE", "NET_ADMIN", "DAC_OVERRIDE"}
REQUIRED_ROOT_DOCKERIGNORE_PATTERNS = {"secrets", "appdata", ".env", "app.env"}
REQUIRED_DOCKERFILES_DOCKERIGNORE_PATTERNS = {"*", "!.dockerignore", "!Dockerfile", "!dockerfile*"}


def rel(path: Path) -> str:
    return path.resolve().relative_to(REPO_ROOT).as_posix()


def as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def find_compose_files(paths: list[str]) -> list[Path]:
    if not paths:
        paths = ["."]
    files: list[Path] = []
    for raw in paths:
        path = (REPO_ROOT / raw).resolve()
        if path.is_file() and path.name.startswith("docker-compose") and path.suffix in {".yaml", ".yml"}:
            files.append(path)
        elif path.is_dir():
            files.extend(
                p
                for p in path.rglob("docker-compose*.y*ml")
                if ".git" not in p.parts
            )
    return sorted(set(files))


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    return data if isinstance(data, dict) else {}


def has_cap_drop_all(service: dict[str, Any]) -> bool:
    return "ALL" in {str(item) for item in as_list(service.get("cap_drop"))}


def is_read_only_exception(path_rel: str, service_name: str) -> bool:
    if (path_rel, service_name) in ALLOW_MISSING_READ_ONLY:
        return True
    if path_rel == "Seafile/docker-compose.main.yaml" and service_name in {"app", "collabora", "seafile_seadoc-server"}:
        return True
    if path_rel.endswith("/docker-compose.collabora.yaml") and service_name == "collabora":
        return True
    if path_rel.endswith("/docker-compose.seafile_seadoc-server.yaml") and service_name == "seafile_seadoc-server":
        return True
    return False


def has_tmpfs(service: dict[str, Any]) -> bool:
    return "tmpfs" in service and bool(as_list(service.get("tmpfs")))


def tmpfs_values(service: dict[str, Any]) -> list[str]:
    return [str(item) for item in as_list(service.get("tmpfs"))]


def tmpfs_target_and_options(value: str) -> tuple[str, set[str]]:
    target, separator, raw_options = value.partition(":")
    if not separator:
        return target, set()
    return target, {option.strip() for option in raw_options.split(",") if option.strip()}


def has_tmpfs_path(service: dict[str, Any], target: str) -> bool:
    prefix = f"{target}:"
    return any(item == target or item.startswith(prefix) for item in tmpfs_values(service))


def dockerignore_patterns(path: Path) -> set[str]:
    if not path.exists():
        return set()
    patterns: set[str] = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        item = raw.strip()
        if not item or item.startswith("#"):
            continue
        patterns.add(item.rstrip("/"))
    return patterns


def build_context_dir(compose_path: Path, service: dict[str, Any]) -> Path | None:
    build = service.get("build")
    if build in (None, ""):
        return None
    if isinstance(build, str):
        context = build
    elif isinstance(build, dict):
        context = str(build.get("context", ""))
    else:
        return None
    if not context:
        return None
    return (compose_path.parent / context).resolve()


def build_dockerfile_path(compose_path: Path, service: dict[str, Any], context_dir: Path) -> Path | None:
    build = service.get("build")
    if not isinstance(build, dict):
        return None
    dockerfile = str(build.get("dockerfile", "Dockerfile"))
    if not dockerfile:
        return None
    dockerfile_path = Path(dockerfile)
    if dockerfile_path.is_absolute():
        return dockerfile_path
    return (context_dir / dockerfile_path).resolve()


def build_ignore_file(compose_path: Path, service: dict[str, Any], context_dir: Path) -> Path:
    dockerfile_path = build_dockerfile_path(compose_path, service, context_dir)
    if dockerfile_path is not None:
        dockerfile_ignore = dockerfile_path.with_name(f"{dockerfile_path.name}.dockerignore")
        if dockerfile_ignore.exists():
            return dockerfile_ignore
    return context_dir / ".dockerignore"


def check_file(path: Path) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    path_rel = rel(path)
    text = path.read_text(encoding="utf-8")

    if "ensure 600 permissions" in text:
        errors.append(f"{path_rel}: uses obsolete fixed secret mode comment")

    data = load_yaml(path)
    services = data.get("services", {})
    if not isinstance(services, dict):
        return errors, warnings

    for service_name, service in services.items():
        if not isinstance(service, dict):
            continue

        context_dir = build_context_dir(path, service)
        if context_dir is not None:
            ignore_file = build_ignore_file(path, service, context_dir)
            patterns = dockerignore_patterns(ignore_file)
            if not ignore_file.exists():
                errors.append(f"{path_rel}:{service_name}: build context '{context_dir.relative_to(REPO_ROOT)}' has no .dockerignore or Dockerfile-specific .dockerignore")
            else:
                if context_dir.name == "dockerfiles":
                    required_patterns = REQUIRED_DOCKERFILES_DOCKERIGNORE_PATTERNS
                else:
                    required_patterns = REQUIRED_ROOT_DOCKERIGNORE_PATTERNS
                missing = sorted(required_patterns - patterns)
                if missing:
                    errors.append(f"{path_rel}:{service_name}: .dockerignore missing required patterns: {', '.join(missing)}")

        if not has_cap_drop_all(service):
            errors.append(f"{path_rel}:{service_name}: missing cap_drop: [ALL]")

        read_only = service.get("read_only") is True
        if not read_only and not is_read_only_exception(path_rel, str(service_name)):
            errors.append(f"{path_rel}:{service_name}: read_only is not enabled and no exception is documented")

        if read_only and not has_tmpfs(service):
            errors.append(f"{path_rel}:{service_name}: read_only is enabled but tmpfs is missing")

        if read_only:
            for item in tmpfs_values(service):
                if not item.startswith("/"):
                    continue
                target, options = tmpfs_target_and_options(item)
                if not options:
                    warnings.append(f"{path_rel}:{service_name}: tmpfs path '{target}' has no explicit mount options")
                    continue
                if "nosuid" not in options:
                    warnings.append(f"{path_rel}:{service_name}: tmpfs path '{target}' is missing nosuid")
                if "nodev" not in options:
                    warnings.append(f"{path_rel}:{service_name}: tmpfs path '{target}' is missing nodev")
                if "noexec" not in options and "exec" not in options:
                    warnings.append(f"{path_rel}:{service_name}: tmpfs path '{target}' has no explicit exec/noexec decision")
                if not any(option.startswith("size=") for option in options):
                    warnings.append(f"{path_rel}:{service_name}: tmpfs path '{target}' has no explicit size limit")

        if service.get("user") in (None, ""):
            warnings.append(f"{path_rel}:{service_name}: user is not set; verify image needs root or switches internally")

        for cap in as_list(service.get("cap_add")):
            cap_name = str(cap).removeprefix("CAP_")
            if cap_name in HIGH_RISK_CAPS:
                warnings.append(f"{path_rel}:{service_name}: high-risk capability {cap_name} is enabled")

        if path_rel == "templates/clamav/docker-compose.clamav.yaml" and read_only:
            if not has_tmpfs_path(service, "/var/log/clamav"):
                errors.append(f"{path_rel}:{service_name}: ClamAV read_only requires /var/log/clamav tmpfs")

        if path_rel == "templates/seafile_seasearch/docker-compose.seafile_seasearch.yaml" and read_only:
            environment = service.get("environment", {})
            if not isinstance(environment, dict) or environment.get("SS_DATA_PATH") != "/opt/seasearch/data":
                errors.append(f"{path_rel}:{service_name}: SeaSearch read_only requires SS_DATA_PATH=/opt/seasearch/data")

        if path_rel == "templates/postgresql_maintenance/docker-compose.postgresql_maintenance.yaml":
            for volume in as_list(service.get("volumes")):
                value = str(volume)
                if ":/var/lib/postgresql/data:" in value and not value.endswith(":ro"):
                    errors.append(f"{path_rel}:{service_name}: default PGDATA maintenance mount must be read-only")

    return errors, warnings


def main() -> int:
    parser = argparse.ArgumentParser(description="Static Docker Compose hardening checks")
    parser.add_argument("paths", nargs="*", help="Files or directories to check")
    parser.add_argument("--quiet", action="store_true", help="Suppress warnings")
    args = parser.parse_args()

    files = find_compose_files(args.paths)
    all_errors: list[str] = []
    all_warnings: list[str] = []

    for file in files:
        errors, warnings = check_file(file)
        all_errors.extend(errors)
        all_warnings.extend(warnings)

    if all_errors:
        print("Hardening errors:")
        for error in all_errors:
            print(f"  - {error}")

    if all_warnings and not args.quiet:
        print("Hardening warnings:")
        for warning in all_warnings:
            print(f"  - {warning}")

    if all_errors:
        return 1
    if not args.quiet:
        print(f"Hardening check passed ({len(files)} compose files, {len(all_warnings)} warning(s)).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
