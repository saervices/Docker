#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Docker-free regression tests for merged Clæssic-Builder contexts."""

from __future__ import annotations

import argparse
import copy
import importlib.util
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from types import ModuleType
from typing import Any

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
CHECKER_PATH = REPO_ROOT / ".cursor/scripts/check-hardening.py"
SENSITIVE_FIXTURE_PARTS = {
    ".git",
    "appdata",
    "backup",
    "backups",
    "data",
    "log",
    "logs",
    "node_modules",
    "restore",
    "restores",
    "secrets",
}
SENSITIVE_FIXTURE_FILES = {".env", "app.env", "docker-compose.main.yaml"}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def check_go_builder_channels() -> None:
    """Require every repository-owned Go helper builder to follow lætest stæble."""

    contracts = (
        (
            "Træefik secret reæder",
            REPO_ROOT / "Traefik/.env",
            "TRAEFIK_GO_IMAGE",
            REPO_ROOT / "Traefik/docker-compose.app.yaml",
            "app",
            "TRAEFIK_GO_IMAGE",
            REPO_ROOT / "Traefik/dockerfiles/Dockerfile",
            "golang:alpine",
            REPO_ROOT / "Traefik/README.md",
        ),
        (
            "Træefik certs-dumper supervisor",
            REPO_ROOT / "templates/traefik_certs-dumper/.env",
            "TRAEFIK_CERTS_DUMPER_GO_IMAGE",
            REPO_ROOT
            / "templates/traefik_certs-dumper/docker-compose.traefik_certs-dumper.yaml",
            "traefik_certs-dumper",
            "TRAEFIK_CERTS_DUMPER_GO_IMAGE",
            REPO_ROOT
            / "templates/traefik_certs-dumper/dockerfiles/dockerfile.traefik-certs-dumper.scp",
            "golang:alpine",
            REPO_ROOT / "templates/traefik_certs-dumper/README.md",
        ),
        (
            "Collæboræ preflight",
            REPO_ROOT / "templates/collabora/.env",
            "COLLABORA_GO_IMAGE",
            REPO_ROOT / "templates/collabora/docker-compose.collabora.yaml",
            "collabora",
            "COLLABORA_GO_IMAGE",
            REPO_ROOT / "templates/collabora/dockerfiles/dockerfile.collabora",
            "golang:alpine",
            REPO_ROOT / "templates/collabora/README.md",
        ),
        (
            "RustDesk runtime helper",
            REPO_ROOT / "RustDesk/.env",
            "RUSTDESK_GO_IMAGE",
            REPO_ROOT / "RustDesk/docker-compose.app.yaml",
            "app",
            "GO_IMAGE",
            REPO_ROOT / "RustDesk/dockerfiles/Dockerfile",
            "docker.io/library/golang:alpine",
            REPO_ROOT / "RustDesk/README.md",
        ),
        (
            "Mætrix LiveKit JWT heælthcheck",
            REPO_ROOT / "templates/matrix-livekit-jwt/.env",
            "MATRIX_LIVEKIT_JWT_BUILD_IMAGE",
            REPO_ROOT
            / "templates/matrix-livekit-jwt/docker-compose.matrix-livekit-jwt.yaml",
            "matrix-livekit-jwt",
            "MATRIX_LIVEKIT_JWT_BUILD_IMAGE",
            REPO_ROOT
            / "templates/matrix-livekit-jwt/dockerfiles/dockerfile.matrix-livekit-jwt",
            "golang:alpine",
            REPO_ROOT / "templates/matrix-livekit-jwt/README.md",
        ),
        (
            "Græfænæ secret preflight ænd bootstræp",
            REPO_ROOT / "Grafana/.env",
            "GRAFANA_GO_IMAGE",
            REPO_ROOT / "Grafana/docker-compose.app.yaml",
            "app",
            "GRAFANA_GO_IMAGE",
            REPO_ROOT / "Grafana/dockerfiles/Dockerfile",
            "docker.io/library/golang:alpine",
            REPO_ROOT / "Grafana/README.md",
        ),
        (
            "Græfænæ SSO policy reconciler",
            REPO_ROOT / "templates/grafana-sso-policy/.env",
            "GRAFANA_SSO_POLICY_GO_IMAGE",
            REPO_ROOT
            / "templates/grafana-sso-policy/docker-compose.grafana-sso-policy.yaml",
            "grafana-sso-policy",
            "GRAFANA_SSO_POLICY_GO_IMAGE",
            REPO_ROOT
            / "templates/grafana-sso-policy/dockerfiles/dockerfile.grafana-sso-policy",
            "docker.io/library/golang:alpine",
            REPO_ROOT / "templates/grafana-sso-policy/README.md",
        ),
        (
            "Giteæ secret reæder",
            REPO_ROOT / "Gitea/.env",
            "GITEA_GO_IMAGE",
            REPO_ROOT / "Gitea/docker-compose.app.yaml",
            "app",
            "GITEA_GO_IMAGE",
            REPO_ROOT / "Gitea/dockerfiles/Dockerfile",
            "docker.io/library/golang:alpine",
            REPO_ROOT / "Gitea/README.md",
        ),
    )

    expected_dockerfiles = {
        dockerfile_path.relative_to(REPO_ROOT).as_posix()
        for (
            _label,
            _env_path,
            _env_key,
            _compose_path,
            _service_name,
            _build_arg,
            dockerfile_path,
            _expected_image,
            _readme_path,
        ) in contracts
    }
    inventory = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
    ).stdout.decode("utf-8").split("\0")
    go_image_reference = re.compile(
        r"(?:^|[=/\s])(?:docker\.io/library/)?golang:[^\s#]+"
    )
    actual_dockerfiles: set[str] = set()
    for relative_path in inventory:
        candidate = REPO_ROOT / relative_path
        if not relative_path or not candidate.is_file():
            continue
        if not candidate.name.lower().startswith("dockerfile"):
            continue
        active_lines = (
            line.strip()
            for line in candidate.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        )
        if any(
            (line.startswith("ARG ") or line.startswith("FROM "))
            and go_image_reference.search(line)
            for line in active_lines
        ):
            actual_dockerfiles.add(relative_path)
    require(
        actual_dockerfiles == expected_dockerfiles,
        "Go builder inventory differs from the eight reviewed Dockerfiles: "
        f"expected={sorted(expected_dockerfiles)!r}, "
        f"actual={sorted(actual_dockerfiles)!r}",
    )

    for (
        label,
        env_path,
        env_key,
        compose_path,
        service_name,
        build_arg,
        dockerfile_path,
        expected_image,
        readme_path,
    ) in contracts:
        for required_path in (env_path, compose_path, dockerfile_path, readme_path):
            require(required_path.is_file(), f"{label}: missing {required_path}")

        env_matches = []
        for raw_line in env_path.read_text(encoding="utf-8").splitlines():
            if raw_line.startswith(f"{env_key}="):
                env_matches.append(raw_line.split("=", 1)[1].split("#", 1)[0].strip())
        require(
            env_matches == [expected_image],
            f"{label}: {env_key} must occur once with {expected_image}",
        )

        compose_document = yaml.safe_load(compose_path.read_text(encoding="utf-8"))
        service = compose_document["services"][service_name]
        build = service.get("build") or {}
        build_args = build.get("args") or {}
        expected_compose_arg = f"${{{env_key}:-{expected_image}}}"
        require(
            build_args.get(build_arg) == expected_compose_arg,
            f"{label}: {build_arg} must equal {expected_compose_arg}",
        )
        require(
            service.get("pull_policy") == "build"
            and build.get("pull") is True
            and build.get("no_cache") is True,
            f"{label}: moving builder requires pull_policy/build.pull/build.no_cache",
        )
        runtime_environment = service.get("environment") or {}
        runtime_keys = (
            set(runtime_environment)
            if isinstance(runtime_environment, dict)
            else {str(item).split("=", 1)[0] for item in runtime_environment}
        )
        require(
            env_key not in runtime_keys and build_arg not in runtime_keys,
            f"{label}: Go builder key must not enter the runtime environment",
        )

        dockerfile_text = dockerfile_path.read_text(encoding="utf-8")
        require(
            dockerfile_text.count(f"ARG {build_arg}={expected_image}") == 1,
            f"{label}: Dockerfile must expose one exact latest-stable ARG default",
        )
        require(
            dockerfile_text.count(f"FROM ${{{build_arg}}}") == 1,
            f"{label}: Dockerfile ARG must drive exactly one builder FROM",
        )
        require(
            expected_image in readme_path.read_text(encoding="utf-8"),
            f"{label}: README must document the exact Go builder default",
        )

    for canonical_name, mirrored_name in (
        (
            "grafana-entrypoint.go",
            "grafana-entrypoint.grafana-sso-policy.go",
        ),
        (
            "grafana-entrypoint_test.go",
            "grafana-entrypoint.grafana-sso-policy_test.go",
        ),
    ):
        canonical = REPO_ROOT / "Grafana/dockerfiles" / canonical_name
        mirrored = (
            REPO_ROOT
            / "templates/grafana-sso-policy/dockerfiles"
            / mirrored_name
        )
        require(
            mirrored.is_file() and canonical.read_bytes() == mirrored.read_bytes(),
            f"Græfænæ SSO policy helper mirror differs from {canonical_name}",
        )

    relay_env = REPO_ROOT / "templates/rustdesk-relay/.env"
    relay_values = [
        line.split("=", 1)[1].split("#", 1)[0].strip()
        for line in relay_env.read_text(encoding="utf-8").splitlines()
        if line.startswith("RUSTDESK_GO_IMAGE=")
    ]
    require(
        relay_values == ["docker.io/library/golang:alpine"],
        "RustDesk relæy must mirror the root latest-stable Go builder",
    )


def load_checker() -> ModuleType:
    spec = importlib.util.spec_from_file_location("check_hardening_build_contexts", CHECKER_PATH)
    require(spec is not None and spec.loader is not None, "could not loæd check-hardening.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def hardened_service(dockerfile: str) -> dict[str, Any]:
    return {
        "build": {"context": "./dockerfiles", "dockerfile": dockerfile},
        "image": "fixture:latest",
        "cap_drop": ["ALL"],
        "read_only": True,
        "tmpfs": ["/tmp:rw,nosuid,nodev,noexec,size=1m"],
        "user": "1000:1000",
    }


def synthetic_errors(
    checker: ModuleType,
    name: str,
    *,
    services: dict[str, dict[str, Any]],
    files: dict[str, str],
    context_subdir: str = "dockerfiles",
    relative_app: str = "Fixture",
    compose_name: str = "docker-compose.main.yaml",
    merged_services: dict[str, dict[str, Any]] | None = None,
) -> list[str]:
    with tempfile.TemporaryDirectory(prefix=f"build-context-{name}.", dir="/tmp") as raw_root:
        fixture_root = Path(raw_root)
        app_dir = fixture_root / relative_app
        file_root = app_dir / context_subdir
        file_root.mkdir(parents=True)
        for relative, content in files.items():
            target = file_root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
        compose = app_dir / compose_name
        compose.write_text(
            yaml.safe_dump({"services": services}, sort_keys=False),
            encoding="utf-8",
        )
        if merged_services is not None:
            (app_dir / "docker-compose.main.yaml").write_text(
                yaml.safe_dump({"services": merged_services}, sort_keys=False),
                encoding="utf-8",
            )

        previous_root = checker.REPO_ROOT
        checker.REPO_ROOT = fixture_root
        try:
            errors, _warnings = checker.check_file(compose)
        finally:
            checker.REPO_ROOT = previous_root
        return errors


def template_compose(template_name: str) -> Path:
    template_dir = REPO_ROOT / "templates" / template_name
    exact = template_dir / f"docker-compose.{template_name}.yaml"
    if exact.is_file():
        return exact
    candidates = sorted(template_dir.glob("docker-compose*.yaml"))
    require(len(candidates) == 1, f"templæte '{template_name}' hæs no unique Compose file")
    return candidates[0]


def required_templates(app_compose: Path) -> list[tuple[str, Path]]:
    data = yaml.safe_load(app_compose.read_text(encoding="utf-8")) or {}
    names = {
        str(item)
        for item in data.get("x-required-services") or []
        if not (str(item).startswith("<") and str(item).endswith(">"))
    }
    return [(name, template_compose(name)) for name in sorted(names)]


def overlay_build_inputs(source: Path, destination: Path, owner: str) -> None:
    """Copies only the dedicæted build tree; never deployment/runtime dætæ."""
    build_root = source / "dockerfiles"
    require(
        not build_root.is_symlink(),
        f"dedicated build root must not be a symlink: {owner}/dockerfiles",
    )
    if not build_root.is_dir():
        return
    require(
        build_root.resolve().parent == source.resolve(),
        f"dedicated build root escapes its owner: {owner}/dockerfiles",
    )
    for item in sorted(build_root.rglob("*")):
        require(
            not item.is_symlink(),
            f"build input symlink is not supported in the safe fixture: {owner}/{item.relative_to(source)}",
        )
        if not item.is_file():
            continue
        relative = item.relative_to(source)
        if item.name == ".gitkeep":
            continue
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            require(
                target.read_bytes() == item.read_bytes(),
                f"flættened file collision for '{relative}' from {owner}",
            )
            continue
        shutil.copy2(item, target)


def safe_repository_fixture_path(relative: Path) -> bool:
    filename = relative.name.lower()
    return (
        filename not in SENSITIVE_FIXTURE_FILES
        and not filename.startswith(".env")
        and not filename.endswith(".env")
        and not filename.startswith("app.env")
        and not any(
            part.lower() in SENSITIVE_FIXTURE_PARTS
            for part in relative.parts
        )
    )


def overlay_repository_inputs(
    source: Path,
    destination: Path,
    owner: str,
    *,
    repository_root: Path = REPO_ROOT,
    include_top_level_files: bool,
) -> None:
    """Copies Git-inventoried root-context inputs without deployment trees."""
    try:
        source_relative = source.resolve().relative_to(repository_root.resolve())
    except ValueError as error:
        raise AssertionError(f"repository fixture source escapes its repository: {owner}") from error
    result = subprocess.run(
        [
            "git",
            "-C",
            str(repository_root),
            "ls-files",
            "--cached",
            "-z",
            "--",
            source_relative.as_posix(),
        ],
        check=False,
        capture_output=True,
    )
    require(
        result.returncode == 0,
        f"could not inventory root-context inputs for {owner}: "
        + result.stderr.decode("utf-8", errors="replace").strip(),
    )
    untracked = subprocess.run(
        [
            "git",
            "-C",
            str(repository_root),
            "ls-files",
            "--others",
            "--exclude-standard",
            "-z",
            "--",
            source_relative.as_posix(),
        ],
        check=False,
        capture_output=True,
    )
    require(
        untracked.returncode == 0,
        f"could not inspect untracked root-context paths for {owner}",
    )
    untracked_count = sum(bool(item) for item in untracked.stdout.split(b"\0"))
    require(
        untracked_count == 0,
        f"root-context fixture for {owner} refuses {untracked_count} untracked path(s); "
        "stage/commit intentional build inputs or remove deployment data before auditing",
    )
    prefix = source_relative.parts
    for raw_path in result.stdout.split(b"\0"):
        if not raw_path:
            continue
        repository_relative = Path(raw_path.decode("utf-8"))
        require(
            repository_relative.parts[: len(prefix)] == prefix,
            f"Git inventory escaped source for {owner}: {repository_relative}",
        )
        relative = Path(*repository_relative.parts[len(prefix):])
        if not relative.parts:
            continue
        if not include_top_level_files and len(relative.parts) == 1:
            continue
        if not safe_repository_fixture_path(relative):
            continue
        item = repository_root / repository_relative
        require(
            not item.is_symlink(),
            f"repository build input symlink is not supported: {owner}/{relative}",
        )
        if not item.is_file():
            continue
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            require(
                target.read_bytes() == item.read_bytes(),
                f"flættened file collision for '{relative}' from {owner}",
            )
            continue
        shutil.copy2(item, target)


def check_safe_overlay() -> None:
    with tempfile.TemporaryDirectory(prefix="build-context-safe-overlay.", dir="/tmp") as raw_root:
        fixture_root = Path(raw_root)
        source = fixture_root / "source"
        destination = fixture_root / "destination"
        (source / "dockerfiles").mkdir(parents=True)
        (source / "secrets").mkdir()
        (source / "appdata").mkdir()
        (source / "dockerfiles/Dockerfile").write_text("FROM scratch\n", encoding="utf-8")
        (source / "secrets/DO_NOT_COPY").write_text("secret sentinel\n", encoding="utf-8")
        (source / "appdata/DO_NOT_COPY").write_text("runtime sentinel\n", encoding="utf-8")

        overlay_build_inputs(source, destination, "safe-overlay")
        require(
            (destination / "dockerfiles/Dockerfile").is_file(),
            "safe overlay omitted a dedicated build input",
        )
        require(
            not (destination / "secrets").exists()
            and not (destination / "appdata").exists(),
            "safe overlay copied deployment secrets or runtime data",
        )

        external = fixture_root / "external"
        external.mkdir()
        (external / "LEAK").write_text("secret sentinel\n", encoding="utf-8")
        symlink_source = fixture_root / "symlink-source"
        symlink_source.mkdir()
        (symlink_source / "dockerfiles").symlink_to(
            external,
            target_is_directory=True,
        )
        try:
            overlay_build_inputs(
                symlink_source,
                fixture_root / "symlink-destination",
                "symlink-overlay",
            )
        except AssertionError:
            pass
        else:
            raise AssertionError("safe overlay followed a symlinked build root")

        repository = fixture_root / "repository"
        repository.mkdir()
        subprocess.run(
            ["git", "init", "--quiet", str(repository)],
            check=True,
            capture_output=True,
        )
        root_source = repository / "Fixture"
        (root_source / "dockerfiles").mkdir(parents=True)
        (root_source / "src").mkdir()
        (root_source / "secrets").mkdir()
        (root_source / "appdata").mkdir()
        (root_source / "dockerfiles/Dockerfile").write_text("FROM scratch\n", encoding="utf-8")
        (root_source / "src/app.txt").write_text("tracked source\n", encoding="utf-8")
        (root_source / ".env.local").write_text("tracked secret\n", encoding="utf-8")
        (root_source / "service.env").write_text("tracked secret\n", encoding="utf-8")
        (root_source / "app.env.prod").write_text("tracked secret\n", encoding="utf-8")
        (root_source / ".dockerignore").write_text(
            ".env\napp.env\nappdata\nbackup\nbackups\n"
            "docker-compose.main.yaml\nnode_modules\nrestore\nrestores\nsecrets\n",
            encoding="utf-8",
        )
        (root_source / "secrets/DO_NOT_COPY").write_text("tracked secret\n", encoding="utf-8")
        (root_source / "appdata/DO_NOT_COPY").write_text("tracked runtime\n", encoding="utf-8")
        subprocess.run(
            ["git", "-C", str(repository), "add", "Fixture"],
            check=True,
            capture_output=True,
        )
        root_destination = fixture_root / "root-context-destination"
        overlay_repository_inputs(
            root_source,
            root_destination,
            "root-context-overlay",
            repository_root=repository,
            include_top_level_files=True,
        )
        require(
            (root_destination / ".dockerignore").is_file()
            and (root_destination / "dockerfiles/Dockerfile").is_file()
            and (root_destination / "src/app.txt").is_file(),
            "safe root-context overlay omitted version-controlled build inputs",
        )
        require(
            not (root_destination / "secrets").exists()
            and not (root_destination / "appdata").exists()
            and not (root_destination / ".env.local").exists()
            and not (root_destination / "service.env").exists()
            and not (root_destination / "app.env.prod").exists(),
            "safe root-context overlay copied tracked deployment data",
        )

        (root_source / "database").mkdir()
        (root_source / "database/LEAK").write_text(
            "untracked secret\n",
            encoding="utf-8",
        )
        untracked_destination = fixture_root / "untracked-destination"
        try:
            overlay_repository_inputs(
                root_source,
                untracked_destination,
                "untracked-root-context-overlay",
                repository_root=repository,
                include_top_level_files=True,
            )
        except AssertionError:
            pass
        else:
            raise AssertionError("safe root-context overlay accepted an untracked path")
        require(
            not untracked_destination.exists(),
            "safe root-context overlay read or copied an untracked path before rejecting it",
        )


def deep_merge(left: Any, right: Any) -> Any:
    if isinstance(left, dict) and isinstance(right, dict):
        merged = copy.deepcopy(left)
        for key, value in right.items():
            merged[key] = (
                deep_merge(merged[key], value)
                if key in merged
                else copy.deepcopy(value)
            )
        return merged
    return copy.deepcopy(right)


def merged_compose(compose_sources: list[tuple[str, Path]]) -> dict[str, Any]:
    merged: dict[str, Any] = {}
    for owner, compose in compose_sources:
        data = yaml.safe_load(compose.read_text(encoding="utf-8")) or {}
        require(isinstance(data, dict), f"{owner} Compose root must be a mæpping")
        for key in ("services", "volumes", "secrets", "networks"):
            value = data.get(key)
            if value is None:
                continue
            require(isinstance(value, dict), f"{owner} top-level '{key}' must be a mæpping")
            merged[key] = deep_merge(merged.get(key, {}), value)
    return merged


def selected_app_composes(app_dirs: list[str] | None) -> list[Path]:
    """Resolve explicit direct-child æpp directories or the full root-æpp inventory."""
    if app_dirs is None:
        app_composes = sorted(REPO_ROOT.glob("*/docker-compose.app.yaml"))
        require(app_composes, "no root æpp Compose files found")
        return app_composes

    app_composes: list[Path] = []
    seen: set[Path] = set()
    for raw_app_dir in app_dirs:
        relative = Path(raw_app_dir)
        require(
            not relative.is_absolute() and len(relative.parts) == 1,
            f"selected æpp must be a direct repository child: '{raw_app_dir}'",
        )
        app_dir = REPO_ROOT / relative
        require(
            app_dir.is_dir() and not app_dir.is_symlink(),
            f"selected æpp directory is missing or not a reæl directory: '{raw_app_dir}'",
        )
        app_compose = app_dir / "docker-compose.app.yaml"
        require(
            app_compose.is_file() and not app_compose.is_symlink(),
            f"selected æpp has no regulær docker-compose.app.yaml: '{raw_app_dir}'",
        )
        if app_compose in seen:
            continue
        seen.add(app_compose)
        app_composes.append(app_compose)
    return sorted(app_composes)


def check_real_flattened_apps(
    checker: ModuleType,
    app_composes: list[Path],
) -> tuple[int, int]:
    build_count = 0
    all_errors: list[str] = []

    with tempfile.TemporaryDirectory(prefix="build-context-real-apps.", dir="/tmp") as raw_root:
        fixture_root = Path(raw_root)
        for app_compose in app_composes:
            app_name = app_compose.parent.name
            flattened_app = fixture_root / app_name
            flattened_app.mkdir(parents=True)
            overlay_build_inputs(app_compose.parent, flattened_app, app_name)

            compose_sources: list[tuple[str, Path]] = [(app_name, app_compose)]
            for template_name, compose in required_templates(app_compose):
                overlay_build_inputs(
                    compose.parent,
                    flattened_app,
                    f"templæte {template_name}",
                )
                compose_sources.append((f"{app_name}/{template_name}", compose))

            flattened_compose = flattened_app / "docker-compose.main.yaml"
            rendered = merged_compose(compose_sources)
            services = rendered.get("services") or {}
            require(
                isinstance(services, dict),
                f"{app_name} merged services must be a mæpping",
            )
            root_context_needed = any(
                isinstance(service, dict)
                and service.get("build") not in (None, "")
                and checker.build_context_value(service) in {".", "./"}
                for service in services.values()
            )
            if root_context_needed:
                for index, (owner, compose) in enumerate(compose_sources):
                    overlay_repository_inputs(
                        compose.parent,
                        flattened_app,
                        owner,
                        include_top_level_files=index == 0,
                    )
            flattened_compose.write_text(
                yaml.safe_dump(rendered, sort_keys=False),
                encoding="utf-8",
            )
            if app_name == "Traefik":
                middleware = flattened_app / "appdata/config/conf.d/middlewares.yaml"
                middleware.parent.mkdir(parents=True)
                middleware.write_text(
                    "http:\n"
                    "  middlewares:\n"
                    "    authentik-proxy:\n"
                    "      forwardAuth:\n"
                    "        address: '{{env \"AUTHENTIK_FORWARD_AUTH_ADDRESS\"}}'\n"
                    "        maxResponseBodySize: 1048576\n",
                    encoding="utf-8",
                )
            for service_name, service in services.items():
                if not isinstance(service, dict) or service.get("build") in (None, ""):
                    continue
                context = checker.build_context_dir(flattened_compose, service)
                require(
                    context is not None,
                    f"{app_name}:{service_name} hæs an invalid build context",
                )
                require(
                    context == flattened_app or flattened_app in context.parents,
                    f"{app_name}:{service_name} build context escæpes the flættened æpp: '{context}'",
                )
                require(
                    context.is_dir(),
                    f"{app_name}:{service_name} build context is missing: '{context}'",
                )
                dockerfile = checker.build_dockerfile_path(
                    flattened_compose,
                    service,
                    context,
                )
                build = service.get("build")
                dockerfile_inline = (
                    str(build.get("dockerfile_inline"))
                    if isinstance(build, dict)
                    and build.get("dockerfile_inline") not in (None, "")
                    else None
                )
                build_count += 1
                require(
                    dockerfile is not None or dockerfile_inline is not None,
                    f"{app_name}:{service_name} hæs no resolvæble Dockerfile",
                )

            previous_root = checker.REPO_ROOT
            checker.REPO_ROOT = fixture_root
            try:
                merged_errors, _warnings = checker.check_file(flattened_compose)
            finally:
                checker.REPO_ROOT = previous_root
            all_errors.extend(merged_errors)

    require(
        not all_errors,
        "reæl root-æpp flættening failed:\n  - " + "\n  - ".join(all_errors),
    )
    return len(app_composes), build_count


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run synthetic Clæssic-Builder regressions and validate merged root-æpp "
            "build contexts. With no scope option, every root æpp is audited."
        ),
    )
    scope = parser.add_mutually_exclusive_group()
    scope.add_argument(
        "--app",
        "--app-dir",
        action="append",
        dest="app_dirs",
        metavar="APP_DIR",
        help=(
            "audit only this direct-child root æpp after the synthetic regressions; "
            "repeat for multiple æpps"
        ),
    )
    scope.add_argument(
        "--synthetic-only",
        action="store_true",
        help="run the synthetic regressions without auditing any reæl root æpp",
    )
    args = parser.parse_args()
    if not args.synthetic_only:
        try:
            args.app_composes = selected_app_composes(args.app_dirs)
        except AssertionError as error:
            parser.error(str(error))
    else:
        args.app_composes = []
    return args


def main() -> None:
    args = parse_args()
    checker = load_checker()
    scenario_count = 0
    check_safe_overlay()
    # The eight-tærget Go inventory is æ repository-wide releæse æudit.  Keep
    # scoped ``--app`` runs ænd ``--synthetic-only`` independent from unrelæted
    # worktree pæths, æs required by the stæged-scope vælidætion contræct.
    if args.app_dirs is None and not args.synthetic_only:
        check_go_builder_channels()

    def run_synthetic(
        name: str,
        *,
        services: dict[str, dict[str, Any]],
        files: dict[str, str],
        context_subdir: str = "dockerfiles",
        relative_app: str = "Fixture",
        compose_name: str = "docker-compose.main.yaml",
        merged_services: dict[str, dict[str, Any]] | None = None,
    ) -> list[str]:
        nonlocal scenario_count
        scenario_count += 1
        return synthetic_errors(
            checker,
            name,
            services=services,
            files=files,
            context_subdir=context_subdir,
            relative_app=relative_app,
            compose_name=compose_name,
            merged_services=merged_services,
        )

    common_ignore = "*\n!.dockerignore\n!Dockerfile\n"
    specific_postgresql = (
        common_ignore
        + "!dockerfile.postgresql\n"
        + "!init_extensions.postgresql.sh\n!entrypoint.postgresql.sh\n"
    )
    specific_maintenance = (
        common_ignore
        + "!dockerfile.supercronic.postgresql\n"
        + "!entrypoint.postgresql_maintenance.sh\n"
        + "!backup.postgresql_maintenance.sh\n"
    )
    flattened_files = {
        "Dockerfile": "FROM scratch\nCOPY entrypoint.sh /entrypoint.sh\n",
        "entrypoint.sh": "#!/bin/sh\n",
        "dockerfile.postgresql": (
            "FROM scratch\n"
            "COPY init_extensions.postgresql.sh /init.sh\n"
            "COPY entrypoint.postgresql.sh /entrypoint.sh\n"
        ),
        "dockerfile.postgresql.dockerignore": specific_postgresql,
        "init_extensions.postgresql.sh": "#!/bin/sh\n",
        "entrypoint.postgresql.sh": "#!/bin/sh\n",
        "dockerfile.supercronic.postgresql": (
            "FROM scratch\n"
            "COPY entrypoint.postgresql_maintenance.sh /entrypoint.sh\n"
            "COPY backup.postgresql_maintenance.sh /backup.sh\n"
        ),
        "dockerfile.supercronic.postgresql.dockerignore": specific_maintenance,
        "entrypoint.postgresql_maintenance.sh": "#!/bin/sh\n",
        "backup.postgresql_maintenance.sh": "#!/bin/sh\n",
    }
    flattened_services = {
        "app": hardened_service("Dockerfile"),
        "postgresql": hardened_service("dockerfile.postgresql"),
        "postgresql_maintenance": hardened_service("dockerfile.supercronic.postgresql"),
    }

    errors = run_synthetic(
        "vikunja-negative",
        services=flattened_services,
        files={**flattened_files, ".dockerignore": common_ignore + "!entrypoint.sh\n"},
    )
    for source in (
        "init_extensions.postgresql.sh",
        "entrypoint.postgresql.sh",
        "entrypoint.postgresql_maintenance.sh",
        "backup.postgresql_maintenance.sh",
    ):
        require(any(source in error for error in errors), f"missing Clæssic exclusion for {source}")

    errors = run_synthetic(
        "flattened-positive",
        services=flattened_services,
        files={
            **flattened_files,
            ".dockerignore": (
                common_ignore
                + "!dockerfile.postgresql\n"
                + "!dockerfile.supercronic.postgresql\n"
                + "!entrypoint.sh\n"
                + "!entrypoint.postgresql.sh\n"
                + "!entrypoint.postgresql_maintenance.sh\n"
                + "!backup.postgresql_maintenance.sh\n"
                + "!init_extensions.postgresql.sh\n"
            ),
        },
    )
    require(not errors, "complete flættened allow-list must pass: " + "; ".join(errors))

    nested_files = {
        "Dockerfile": "FROM scratch\nCOPY src/tool.sh /tool.sh\n",
        "src/tool.sh": "#!/bin/sh\n",
    }
    errors = run_synthetic(
        "direct-child-reinclude",
        services={"app": hardened_service("Dockerfile")},
        files={**nested_files, ".dockerignore": common_ignore + "!src/tool.sh\n"},
    )
    require(
        not errors,
        "Moby must permit a direct child re-include: " + "; ".join(errors),
    )
    errors = run_synthetic(
        "parent-tree-reinclude",
        services={"app": hardened_service("Dockerfile")},
        files={**nested_files, ".dockerignore": common_ignore + "!src\n"},
    )
    require(
        not errors,
        "a re-included directory must expose its tree: " + "; ".join(errors),
    )
    errors = run_synthetic(
        "wildcard-parent-pruning",
        services={"app": hardened_service("Dockerfile")},
        files={
            **nested_files,
            ".dockerignore": common_ignore + "!**/tool.sh\n",
        },
    )
    require(
        any("src/tool.sh" in error for error in errors),
        "Classic archive pruning must reject wildcard-only parent traversal",
    )

    basename_files = {
        "Dockerfile": "FROM scratch\nCOPY dir/file.txt /file.txt\n",
        "dir/file.txt": "fixture\n",
    }
    errors = run_synthetic(
        "nested-basename-negative",
        services={"app": hardened_service("Dockerfile")},
        files={
            **basename_files,
            ".dockerignore": (
                common_ignore
                + "!dir\n"
                + "dir/*\n"
                + "!file.txt\n"
            ),
        },
    )
    require(
        any("dir/file.txt" in error for error in errors),
        "a root-only basename negation must not re-include a nested file",
    )

    suffix_files = {
        "Dockerfile": "FROM scratch\nCOPY dir/abc /abc\n",
        "dir/abc": "fixture\n",
    }
    errors = run_synthetic(
        "moby-double-star-suffix",
        services={"app": hardened_service("Dockerfile")},
        files={
            **suffix_files,
            ".dockerignore": (
                common_ignore
                + "!dir\n"
                + "!dir/abc\n"
                + "**abc\n"
            ),
        },
    )
    require(
        any("dir/abc" in error for error in errors),
        "a leading Moby ** suffix pattern must match nested paths",
    )
    require(
        checker.dockerignore_pattern_matches("foo/child", "foo/**"),
        "Moby trailing ** prefix semantics were not preserved",
    )
    require(
        checker.dockerignore_pattern_matches("a/b", "a**b"),
        "Moby embedded ** semantics were not preserved",
    )

    ordered_files = {
        "Dockerfile": "FROM scratch\nADD payload.tar /payload.tar\nCOPY [\"config.json\", \"entrypoint.sh\", \"/out/\"]\nCOPY --from=builder /remote /remote\n",
        "payload.tar": "fixture\n",
        "config.json": "{}\n",
        "entrypoint.sh": "#!/bin/sh\n",
    }
    errors = run_synthetic(
        "add-negative",
        services={"app": hardened_service("Dockerfile")},
        files={
            **ordered_files,
            ".dockerignore": common_ignore + "!config.json\n!entrypoint.sh\n",
        },
    )
    require(any("local ADD source 'payload.tar'" in error for error in errors), "excluded ADD source was not detected")
    errors = run_synthetic(
        "ordered-positive",
        services={"app": hardened_service("Dockerfile")},
        files={
            **ordered_files,
            ".dockerignore": common_ignore + "!payload.tar\n!config.json\n!entrypoint.sh\npayload.tar\n!payload.tar\n",
        },
    )
    require(not errors, "læst negætion must re-include sources: " + "; ".join(errors))

    missing_generic_files = {
        "Dockerfile": "FROM scratch\nCOPY entrypoint.sh /entrypoint.sh\n",
        "Dockerfile.dockerignore": common_ignore + "!entrypoint.sh\n",
        "entrypoint.sh": "#!/bin/sh\n",
    }
    errors = run_synthetic(
        "missing-generic",
        services={"app": hardened_service("Dockerfile")},
        files=missing_generic_files,
    )
    require(
        any("no generic .dockerignore" in error for error in errors),
        "a Dockerfile-specific ignore must not replace the generic Classic view",
    )

    errors = run_synthetic(
        "excluded-dockerfile",
        services={"app": hardened_service("Dockerfile")},
        files={
            "Dockerfile": "FROM scratch\nCOPY entrypoint.sh /entrypoint.sh\n",
            "entrypoint.sh": "#!/bin/sh\n",
            ".dockerignore": (
                common_ignore
                + "!entrypoint.sh\n"
                + "Dockerfile\n"
            ),
        },
    )
    require(
        any("excludes active Dockerfile" in error for error in errors),
        "effective Dockerfile exclusion was not detected",
    )

    glob_files = {
        "Dockerfile": "FROM scratch\nCOPY config*.json /config/\n",
        "config.dev.json": "{}\n",
        "config.prod.json": "{}\n",
    }
    errors = run_synthetic(
        "partial-glob-negative",
        services={"app": hardened_service("Dockerfile")},
        files={
            **glob_files,
            ".dockerignore": (
                common_ignore
                + "!config*.json\n"
                + "config.prod.json\n"
            ),
        },
    )
    require(
        any("config.prod.json" in error for error in errors),
        "every filesystem member of a local glob must remain visible",
    )

    default_context_service = hardened_service("Dockerfile")
    del default_context_service["build"]["context"]
    root_ignore = "secrets\nappdata\n.env\napp.env\n"
    errors = run_synthetic(
        "default-root-context",
        services={"app": default_context_service},
        files={
            "Dockerfile": "FROM scratch\nCOPY missing.txt /missing.txt\n",
            ".dockerignore": root_ignore,
        },
        context_subdir="",
    )
    require(
        any("missing.txt" in error for error in errors),
        "detailed build without context must default to '.' and be checked",
    )
    for required_root_pattern in (
        "backup",
        "backups",
        "docker-compose.main.yaml",
        "node_modules",
        "restore",
        "restores",
    ):
        require(
            any(
                "missing required patterns" in error
                and required_root_pattern in error
                for error in errors
            ),
            f"root build contexts must require '{required_root_pattern}' exclusion",
        )

    complete_root_ignore = "\n".join(
        sorted(checker.REQUIRED_ROOT_DOCKERIGNORE_PATTERNS)
    ) + "\n"
    errors = run_synthetic(
        "complete-root-context-positive",
        services={"app": default_context_service},
        files={
            "Dockerfile": "FROM scratch\n",
            ".dockerignore": complete_root_ignore,
        },
        context_subdir="",
    )
    require(
        not errors,
        "complete root-context exclusions must pass: " + "; ".join(errors),
    )

    errors = run_synthetic(
        "root-context-sensitive-reinclude",
        services={"app": default_context_service},
        files={
            "Dockerfile": "FROM scratch\n",
            ".dockerignore": complete_root_ignore + "!secrets/LEAK\n",
        },
        context_subdir="",
    )
    require(
        any(
            "leaves sensitive path(s) visible" in error
            and "secrets/LEAK" in error
            for error in errors
        ),
        "ordered root-context negations must not re-expose sensitive descendants",
    )

    absolute_context_service = hardened_service("Dockerfile")
    absolute_context_service["build"]["context"] = "/srv/build-context"
    errors = run_synthetic(
        "absolute-context-negative",
        services={"app": absolute_context_service},
        files={},
    )
    require(
        any("absolute build context" in error for error in errors),
        "absolute host-specific build contexts must fail closed",
    )

    remote_context_service = hardened_service("Dockerfile")
    remote_context_service["build"]["context"] = (
        "https://github.com/example/project.git"
    )
    errors = run_synthetic(
        "remote-context-negative",
        services={"app": remote_context_service},
        files={},
    )
    require(
        any("remote build context" in error for error in errors),
        "remote build contexts must fail closed instead of becoming local paths",
    )

    escaping_context_service = hardened_service("Dockerfile")
    escaping_context_service["build"]["context"] = "../../outside"
    errors = run_synthetic(
        "escaping-context-negative",
        services={"app": escaping_context_service},
        files={},
    )
    require(
        any("escapes the repository" in error for error in errors),
        "relative build contexts escaping the repository must fail closed",
    )

    errors = run_synthetic(
        "absolute-dockerfile-negative",
        services={"app": hardened_service("/etc/hosts")},
        files={".dockerignore": common_ignore},
    )
    require(
        any("absolute dockerfile" in error for error in errors),
        "absolute host Dockerfiles must fail closed",
    )

    errors = run_synthetic(
        "escaping-dockerfile-negative",
        services={"app": hardened_service("../outside.Dockerfile")},
        files={".dockerignore": common_ignore},
    )
    require(
        any("escapes its build context" in error for error in errors),
        "relative Dockerfiles escaping their context must fail closed",
    )

    errors = run_synthetic(
        "remote-git-add",
        services={"app": hardened_service("Dockerfile")},
        files={
            "Dockerfile": (
                "FROM scratch\n"
                "ADD git@github.com:example/project.git /project\n"
            ),
            ".dockerignore": common_ignore,
        },
    )
    require(
        not errors,
        "remote Git ADD must not be treated as a local source: " + "; ".join(errors),
    )

    inline_service = hardened_service("Dockerfile")
    inline_service["build"].pop("dockerfile")
    inline_service["build"]["dockerfile_inline"] = (
        "FROM scratch\nCOPY entrypoint.sh /entrypoint.sh\n"
    )
    errors = run_synthetic(
        "inline-dockerfile-negative",
        services={"app": inline_service},
        files={
            "entrypoint.sh": "#!/bin/sh\n",
            ".dockerignore": common_ignore,
        },
    )
    require(
        any("entrypoint.sh" in error for error in errors),
        "dockerfile_inline local sources must be checked",
    )

    errors = run_synthetic(
        "invalid-ignore-syntax",
        services={"app": hardened_service("Dockerfile")},
        files={
            "Dockerfile": "FROM scratch\nCOPY entrypoint.sh /entrypoint.sh\n",
            "entrypoint.sh": "#!/bin/sh\n",
            ".dockerignore": (
                common_ignore
                + "[z-a]\n"
                + "[a-]\n"
                + "!\n"
                + "!entrypoint.sh\n"
            ),
        },
    )
    require(
        sum("ignore file '.dockerignore'" in error for error in errors) >= 3,
        "invalid/reversed ranges and lone negations must fail closed",
    )

    errors = run_synthetic(
        "canonical-ignore-positive",
        services={"app": hardened_service("Dockerfile")},
        files={
            "Dockerfile": "FROM scratch\nCOPY entrypoint.sh /entrypoint.sh\n",
            "entrypoint.sh": "#!/bin/sh\n",
            ".dockerignore": (
                "\ufeff*\n"
                "!//.dockerignore\n"
                "!//Dockerfile\n"
                "!//entrypoint.sh\n"
            ),
        },
    )
    require(
        not errors,
        "canonical BOM/root-anchored required patterns must pass: " + "; ".join(errors),
    )

    errors = run_synthetic(
        "heredoc-copy-positive",
        services={"app": hardened_service("Dockerfile")},
        files={
            "Dockerfile": (
                "FROM scratch\n"
                "COPY <<EOF /hello.txt\n"
                "COPY missing /must-remain-embedded\n"
                "EOF\n"
            ),
            ".dockerignore": common_ignore,
        },
    )
    require(
        not errors,
        "embedded Dockerfile heredoc content must not be treated as a context source: "
        + "; ".join(errors),
    )

    for index, broad_pattern in enumerate(
        (
            "dockerfile*",
            "dockerfile.prod*",
            "Dockerfile.*",
            "dockerfile.postgres?",
            "[d]ockerfile.release*",
            "[!d]ockerfile.release*",
            "[^x]ockerfile.release*",
            r"[\d]ockerfile.release*",
            r"[d\]]ockerfile.release*",
            r"[\]d]ockerfile.release*",
            "[^D]ockerfile.release*",
            "[^d]ockerfile.release*",
        ),
        1,
    ):
        errors = run_synthetic(
            f"broad-dockerfile-negation-{index}",
            services={"app": hardened_service("Dockerfile")},
            files={
                "Dockerfile": "FROM scratch\n",
                ".dockerignore": common_ignore + f"!{broad_pattern}\n",
            },
        )
        require(
            any("broad Dockerfile negation" in error for error in errors),
            f"Dockerfile-targeting glob '!{broad_pattern}' must fail closed",
        )
    require(
        checker.dockerignore_pattern_matches(
            "dockerfile.release",
            r"[\d]ockerfile*",
        ),
        "Go character-class escapes must remain literal instead of becoming Python regex categories",
    )
    require(
        checker.dockerignore_pattern_matches(
            "]ockerfile.release",
            r"[\]]ockerfile*",
        ),
        "an escaped closing bracket must remain a member of the Go character class",
    )
    require(
        checker.dockerignore_pattern_matches(
            "dockerfile.release",
            r"[\]d]ockerfile*",
        ),
        "the class parser must continue past an escaped closing bracket to the real delimiter",
    )
    require(
        checker.dockerignore_pattern_matches(
            "dockerfile.release",
            "[^D]ockerfile*",
        ),
        "Go character classes must preserve Linux case-sensitive negation semantics",
    )

    errors = run_synthetic(
        "benign-non-dockerfile-glob",
        services={"app": hardened_service("Dockerfile")},
        files={
            "Dockerfile": "FROM scratch\nCOPY config.dev.json /config.json\n",
            "config.dev.json": "{}\n",
            ".dockerignore": common_ignore + "!config*.json\n",
        },
    )
    require(
        not any("broad Dockerfile negation" in error for error in errors),
        "a glob that cannot expose a Dockerfile-prefixed basename must remain allowed",
    )

    for index, benign_pattern in enumerate(
        (
            r"[\]]ockerfile.release*",
            r"[x\]]ockerfile.release*",
        ),
        1,
    ):
        errors = run_synthetic(
            f"benign-escaped-bracket-negation-{index}",
            services={"app": hardened_service("Dockerfile")},
            files={
                "Dockerfile": "FROM scratch\n",
                ".dockerignore": common_ignore + f"!{benign_pattern}\n",
            },
        )
        require(
            not any("broad Dockerfile negation" in error for error in errors),
            f"benign escaped-bracket glob '!{benign_pattern}' must remain allowed",
        )

    errors = run_synthetic(
        "visible-file-outside-build-union",
        services={"app": hardened_service("Dockerfile")},
        files={
            "Dockerfile": "FROM scratch\n",
            "credentials.txt": "do-not-send\n",
            ".dockerignore": common_ignore + "!credentials.txt\n",
        },
    )
    require(
        any(
            "outside the active Dockerfile/COPY/ADD allowlist" in error
            and "credentials.txt" in error
            for error in errors
        ),
        "generic build contexts must reject unrelated re-included files",
    )

    component_service = hardened_service("dockerfile.primary")
    maintenance_service = hardened_service("dockerfile.maintenance")
    shared_context_files = {
        "dockerfile.primary": "FROM scratch\nCOPY primary.sh /primary.sh\n",
        "primary.sh": "#!/bin/sh\n",
        "dockerfile.maintenance": "FROM scratch\nCOPY maintenance.sh /maintenance.sh\n",
        "maintenance.sh": "#!/bin/sh\n",
        ".dockerignore": (
            "*\n!.dockerignore\n!dockerfile.primary\n!primary.sh\n"
            "!dockerfile.maintenance\n!maintenance.sh\n"
        ),
    }
    errors = run_synthetic(
        "generated-component-uses-main-build-union",
        services={"primary": component_service},
        merged_services={
            "primary": component_service,
            "maintenance": maintenance_service,
        },
        compose_name="docker-compose.primary.yaml",
        files=shared_context_files,
    )
    require(
        not any("outside the active Dockerfile/COPY/ADD allowlist" in error for error in errors),
        "a generated component Compose file must use its deployable main sibling's build-input union",
    )

    raw_template_files = {
        "Dockerfile": "FROM scratch\nCOPY entrypoint.fixture.sh /entrypoint.sh\n",
        "Dockerfile.dockerignore": common_ignore,
        "entrypoint.fixture.sh": "#!/bin/sh\n",
    }
    errors = run_synthetic(
        "raw-template-specific-source",
        services={"fixture": hardened_service("Dockerfile")},
        files=raw_template_files,
        relative_app="templates/Fixture",
    )
    require(
        any("entrypoint.fixture.sh" in error for error in errors),
        "raw template specific ignores must expose every local helper",
    )

    errors = run_synthetic(
        "raw-template-generic-forbidden",
        services={"fixture": hardened_service("Dockerfile")},
        files={
            "Dockerfile": "FROM scratch\n",
            ".dockerignore": common_ignore,
        },
        relative_app="templates/Fixture",
    )
    require(
        any("must not ship generic" in error for error in errors),
        "mergeable raw templates must not ship a generic .dockerignore",
    )

    if args.app_composes:
        app_count, build_count = check_real_flattened_apps(
            checker,
            args.app_composes,
        )
        print(
            f"PASS: {scenario_count} synthetic Clæssic-context scenarios and "
            f"{build_count} active builds across {app_count} root æpp directories; "
            "safe-overlay sentinel passed"
        )
    else:
        print(
            f"PASS: {scenario_count} synthetic Clæssic-context scenarios; "
            "reæl root-æpp audit not requested; safe-overlay sentinel passed"
        )


if __name__ == "__main__":
    main()
