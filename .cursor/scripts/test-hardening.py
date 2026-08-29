#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Tærgeted fæil-closed regressions for the stætic hærdening checker."""

from __future__ import annotations

import copy
import importlib.util
import tempfile
from pathlib import Path
from types import ModuleType
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
CHECKER_PATH = REPO_ROOT / ".cursor/scripts/check-hardening.py"
COMPLIANCE_PATH = REPO_ROOT / ".cursor/scripts/enforce-app-template-compliance.py"
ASSERTION_COUNT = 0


def require(condition: bool, message: str) -> None:
    global ASSERTION_COUNT
    ASSERTION_COUNT += 1
    if not condition:
        raise AssertionError(message)


def load_checker() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "check_hardening_regressions",
        CHECKER_PATH,
    )
    require(spec is not None and spec.loader is not None, "could not loæd check-hardening.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_compliance_checker() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "app_template_compliance_regressions",
        COMPLIANCE_PATH,
    )
    require(spec is not None and spec.loader is not None, "could not loæd compliænce checker")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def replace_label(service: dict[str, Any], suffix: str, value: str) -> None:
    labels = service.get("labels")
    require(isinstance(labels, list), "Træefik fixture labels must be list form")
    for index, label in enumerate(labels):
        key, separator, _configured = str(label).partition("=")
        if separator and key.lower().endswith(suffix.lower()):
            labels[index] = f"{key}={value}"
            return
    raise AssertionError(f"Træefik fixture label '*{suffix}' is missing")


def traefik_service_fixture() -> dict[str, Any]:
    """Returns æ minimæl secure Træefik mænægement-plæne fixture."""
    return {
        "labels": [
            "traefik.http.routers.fixture.rule=(${TRAEFIK_HOST}) && (PathPrefix(`/api`) || PathPrefix(`/dashboard`))",
            "traefik.http.routers.fixture.entrypoints=websecure",
            "traefik.http.routers.fixture.service=api@internal",
            "traefik.http.routers.fixture.middlewares=secure@docker",
            "traefik.http.middlewares.secure.forwardauth.address=https://auth.example/outpost.goauthentik.io/auth/traefik",
        ],
        "ports": ["80:80", "443:443"],
        "command": [
            "--api=true",
            "--api.dashboard=true",
            "--accesslog=true",
            "--accesslog.fields.queryparameters.defaultmode=drop",
            "--entrypoints.web.address=:80",
            "--entrypoints.web.http.encodedcharacters.allowencodedslash=false",
            "--entrypoints.web.http.encodedcharacters.allowencodedbackslash=false",
            "--entrypoints.web.http.encodedcharacters.allowencodednullcharacter=false",
            "--entrypoints.web.http.encodedcharacters.allowencodedsemicolon=true",
            "--entrypoints.web.http.encodedcharacters.allowencodedpercent=true",
            "--entrypoints.web.http.encodedcharacters.allowencodedquestionmark=true",
            "--entrypoints.web.http.encodedcharacters.allowencodedhash=true",
            "--entrypoints.websecure.address=:443",
            "--entrypoints.websecure.http.tls=true",
            "--entrypoints.websecure.http.tls.certresolver=production",
            "--entrypoints.websecure.http.tls.options=global-tls-opts@file",
            "--entrypoints.websecure.http.encodedcharacters.allowencodedslash=false",
            "--entrypoints.websecure.http.encodedcharacters.allowencodedbackslash=false",
            "--entrypoints.websecure.http.encodedcharacters.allowencodednullcharacter=false",
            "--entrypoints.websecure.http.encodedcharacters.allowencodedsemicolon=true",
            "--entrypoints.websecure.http.encodedcharacters.allowencodedpercent=true",
            "--entrypoints.websecure.http.encodedcharacters.allowencodedquestionmark=true",
            "--entrypoints.websecure.http.encodedcharacters.allowencodedhash=true",
            "--entrypoints.traefik-ping.address=127.0.0.1:${TRAEFIK_PORT:-8080}",
            "--entrypoints.traefik-ping.http.encodedcharacters.allowencodedslash=false",
            "--entrypoints.traefik-ping.http.encodedcharacters.allowencodedbackslash=false",
            "--entrypoints.traefik-ping.http.encodedcharacters.allowencodednullcharacter=false",
            "--entrypoints.traefik-ping.http.encodedcharacters.allowencodedsemicolon=false",
            "--entrypoints.traefik-ping.http.encodedcharacters.allowencodedpercent=false",
            "--entrypoints.traefik-ping.http.encodedcharacters.allowencodedquestionmark=false",
            "--entrypoints.traefik-ping.http.encodedcharacters.allowencodedhash=false",
            "--ping=true",
            "--ping.entrypoint=traefik-ping",
        ],
        "healthcheck": {
            "test": [
                "CMD",
                "wget",
                "--spider",
                "--quiet",
                "http://127.0.0.1:${TRAEFIK_PORT:-8080}/ping",
            ]
        },
    }


def traefik_file_provider_service_fixture() -> dict[str, Any]:
    """Returns the Træefik fixture with its locæl file-provider bind."""
    service = traefik_service_fixture()
    service["volumes"] = [
        "./appdata/config/conf.d:/etc/traefik/dynamic:ro"
    ]
    service["command"].append(
        "--providers.file.directory=/etc/traefik/dynamic"
    )
    return service


def management_errors(checker: ModuleType, service: dict[str, Any]) -> list[str]:
    return checker.check_traefik_management_plane(
        "Fixture/docker-compose.app.yaml",
        "traefik",
        service,
    )


def file_auth_is_trusted(checker: ModuleType, content: str) -> bool:
    with tempfile.TemporaryDirectory(prefix="hardening-file-auth.", dir="/tmp") as raw_root:
        fixture_root = Path(raw_root)
        middleware = fixture_root / "Traefik/appdata/config/conf.d/middlewares.yaml"
        middleware.parent.mkdir(parents=True)
        middleware.write_text(content, encoding="utf-8")
        previous_root = checker.REPO_ROOT
        checker.REPO_ROOT = fixture_root
        try:
            return checker.trusted_file_auth_middleware_defined(
                "Traefik/docker-compose.app.yaml",
                "authentik-proxy",
            )
        finally:
            checker.REPO_ROOT = previous_root


def file_auth_response_limit_errors(
    checker: ModuleType,
    content: str,
    service: dict[str, Any] | None = None,
    service_name: str = "traefik",
) -> list[str]:
    with tempfile.TemporaryDirectory(prefix="hardening-file-auth-limit.", dir="/tmp") as raw_root:
        fixture_root = Path(raw_root)
        middleware = fixture_root / "Traefik/appdata/config/conf.d/middlewares.yaml"
        middleware.parent.mkdir(parents=True)
        middleware.write_text(content, encoding="utf-8")
        previous_root = checker.REPO_ROOT
        checker.REPO_ROOT = fixture_root
        try:
            configured_service = (
                copy.deepcopy(service)
                if service is not None
                else traefik_file_provider_service_fixture()
            )
            return checker.check_traefik_authentik_forward_auth_response_limit(
                "Traefik/docker-compose.app.yaml",
                service_name,
                configured_service,
            )
        finally:
            checker.REPO_ROOT = previous_root


def main() -> None:
    checker = load_checker()
    compliance = load_compliance_checker()

    moving_build = {
        "image": "local/reviewed:current",
        "pull_policy": "build",
        "build": {
            "context": "./dockerfiles",
            "pull": True,
            "no_cache": True,
        },
    }
    require(
        not checker.check_moving_build_refresh_contract(
            "Fixture/docker-compose.app.yaml",
            "builder",
            copy.deepcopy(moving_build),
        ),
        "æ moving custom build with literæl pull ænd no-cache booleæns must pæss",
    )
    for field in ("pull", "no_cache"):
        for label, value in (("missing", None), ("false", False), ("string", "true")):
            invalid = copy.deepcopy(moving_build)
            if label == "missing":
                del invalid["build"][field]
            else:
                invalid["build"][field] = value
            errors = checker.check_moving_build_refresh_contract(
                "Fixture/docker-compose.app.yaml",
                "builder",
                invalid,
            )
            require(
                any(f"build.{field}: true" in error for error in errors),
                f"pull_policy: build must reject {label} build.{field}",
            )

    shorthand_errors = checker.check_moving_build_refresh_contract(
        "Fixture/docker-compose.app.yaml",
        "builder",
        {"pull_policy": "build", "build": "./dockerfiles"},
    )
    require(
        len(shorthand_errors) == 2
        and any("build.pull: true" in error for error in shorthand_errors)
        and any("build.no_cache: true" in error for error in shorthand_errors),
        "short-form moving builds must fæil both explicit refresh booleæns",
    )

    digest_image = "vendor/example@sha256:" + ("a" * 64)
    for label, service in (
        ("digest-only", {"image": digest_image, "pull_policy": "build"}),
        ("no-build", {"image": "vendor/example:current"}),
        (
            "non-build-policy",
            {
                "pull_policy": "always",
                "build": {"context": ".", "pull": False, "no_cache": "true"},
            },
        ),
        ("empty-build", {"pull_policy": "build", "build": ""}),
    ):
        require(
            not checker.check_moving_build_refresh_contract(
                "Fixture/docker-compose.app.yaml",
                label,
                service,
            ),
            f"{label} must not be misclæssified æs æn æctive moving build contræct",
        )

    tls_options = checker.load_yaml(
        REPO_ROOT / "Traefik/appdata/config/conf.d/tls-opts.yaml"
    )
    tls_root = tls_options.get("tls", {})
    require(
        isinstance(tls_root, dict),
        "Træefik TLS configurætion must be æ mæpping",
    )
    option_profiles = tls_root.get("options", {})
    require(
        isinstance(option_profiles, dict),
        "Træefik TLS options must be æ mæpping",
    )
    for profile_name in ("default", "global-tls-opts"):
        profile = option_profiles.get(profile_name, {})
        require(
            isinstance(profile, dict),
            f"Træefik TLS profile '{profile_name}' must be æ mæpping",
        )
        require(
            profile.get("minVersion") == "VersionTLS13",
            f"Træefik TLS profile '{profile_name}' must require TLS 1.3",
        )
        require(
            profile.get("sniStrict") is True,
            f"Træefik TLS profile '{profile_name}' must enforce strict SNI",
        )
    require(
        option_profiles["default"] == option_profiles["global-tls-opts"],
        "Træefik's defæult ænd næmed TLS profiles must remæin identicæl",
    )

    with tempfile.TemporaryDirectory(prefix="hardening-targets.", dir="/tmp") as raw_root:
        fixture_root = Path(raw_root)
        (fixture_root / "empty").mkdir()
        (fixture_root / "Dockerfile").write_text("FROM scratch\n", encoding="utf-8")
        (fixture_root / "docker-compose.valid.yaml").write_text(
            "services: {}\n",
            encoding="utf-8",
        )
        outside = fixture_root.parent / f"{fixture_root.name}-outside"
        outside.write_text("services: {}\n", encoding="utf-8")
        (fixture_root / "escaping-link").symlink_to(outside)
        (fixture_root / "docker-compose.alias.yaml").symlink_to(
            "docker-compose.valid.yaml"
        )
        nested_real = fixture_root / "nested-real"
        nested_real.mkdir()
        (nested_real / "docker-compose.nested.yaml").write_text(
            "services: {}\n",
            encoding="utf-8",
        )
        (fixture_root / "nested-link").symlink_to(
            "nested-real",
            target_is_directory=True,
        )
        previous_root = checker.REPO_ROOT
        checker.REPO_ROOT = fixture_root
        try:
            files, errors = checker.find_compose_files(["docker-compose.valid.yaml"])
            require(
                files == [(fixture_root / "docker-compose.valid.yaml").resolve()]
                and not errors,
                "an explicit existing Compose target must resolve exactly once",
            )
            for target, expected in (
                ("missing.yaml", "does not exist"),
                ("Dockerfile", "not a Docker Compose YAML file"),
                ("empty", "contains no Docker Compose YAML files"),
                ("escaping-link", "escapes the repository"),
                ("docker-compose.alias.yaml", "must not be a symbolic link"),
                (
                    "nested-link/docker-compose.nested.yaml",
                    "must not traverse a symbolic-link path component",
                ),
            ):
                files, errors = checker.find_compose_files([target])
                require(
                    not files and any(expected in error for error in errors),
                    f"explicit checker target '{target}' must fail closed",
                )

            moving_path = fixture_root / "docker-compose.moving.yaml"
            moving_fixture = {"services": {"builder": copy.deepcopy(moving_build)}}
            del moving_fixture["services"]["builder"]["build"]["no_cache"]
            moving_path.write_text(
                checker.yaml.safe_dump(moving_fixture, sort_keys=True),
                encoding="utf-8",
            )
            moving_errors, _moving_warnings = checker.check_file(moving_path)
            require(
                any(
                    "pull_policy: build requires build.no_cache: true" in error
                    for error in moving_errors
                ),
                "the file-scænner must wire the moving-build no-cæche contræct",
            )

            moving_fixture["services"]["builder"]["build"]["no_cache"] = True
            moving_path.write_text(
                checker.yaml.safe_dump(moving_fixture, sort_keys=True),
                encoding="utf-8",
            )
            moving_errors, _moving_warnings = checker.check_file(moving_path)
            require(
                not any(
                    "pull_policy: build requires" in error
                    for error in moving_errors
                ),
                "the file-scænner must æccept the complete moving-build contræct",
            )

            completion_path = fixture_root / "docker-compose.completion.yaml"

            def completion_errors(source: str) -> list[str]:
                completion_path.write_text(source, encoding="utf-8")
                found, _warnings = checker.check_file(completion_path)
                return [
                    error
                    for error in found
                    if any(
                        marker in error
                        for marker in (
                            "post-start completion",
                            "completion timeout",
                            "reserved completion",
                            "restart_policy",
                            "labelled post-start",
                        )
                    )
                ]

            valid_completion = """services:
  job:
    image: local/job:1
    restart: "no"
    labels:
      de.saervices.run.completion-timeout-seconds: "3"
"""
            require(
                not completion_errors(valid_completion),
                "the strict mapping-form consumerless completion contract must pass",
            )
            raw_mutations = {
                "unquoted-timeout": valid_completion.replace(': "3"', ": 3"),
                "explicit-string-tag": valid_completion.replace(
                    ': "3"', ": !!str 3"
                ),
                "block-scalar": valid_completion.replace(
                    ': "3"', ": |-\n        3"
                ),
                "list-form": valid_completion.replace(
                    "    labels:\n      de.saervices.run.completion-timeout-seconds: \"3\"",
                    "    labels:\n      - de.saervices.run.completion-timeout-seconds=3",
                ),
                "duplicate-list": valid_completion.replace(
                    "    labels:\n      de.saervices.run.completion-timeout-seconds: \"3\"",
                    "    labels:\n      - de.saervices.run.completion-timeout-seconds=3\n      - de.saervices.run.completion-timeout-seconds=4",
                ),
                "duplicate-mapping": valid_completion.replace(
                    '      de.saervices.run.completion-timeout-seconds: "3"',
                    '      de.saervices.run.completion-timeout-seconds: "3"\n      de.saervices.run.completion-timeout-seconds: "4"',
                ),
                "reserved-alias": valid_completion.replace(
                    "completion-timeout-seconds", "completion-shadow"
                ),
                "merged-label": """x-completion-labels: &completion-labels
  de.saervices.run.completion-timeout-seconds: "3"
services:
  job:
    image: local/job:1
    restart: "no"
    labels:
      <<: *completion-labels
""",
                "aliased-timeout": """x-completion-timeout: &completion-timeout "3"
services:
  job:
    image: local/job:1
    restart: "no"
    labels:
      de.saervices.run.completion-timeout-seconds: *completion-timeout
""",
                "aliased-labels": """x-completion-labels: &completion-labels
  de.saervices.run.completion-timeout-seconds: "3"
services:
  job:
    image: local/job:1
    restart: "no"
    labels: *completion-labels
""",
                "aliased-service": """x-completion-job: &completion-job
  image: local/job:1
  restart: "no"
  labels:
    de.saervices.run.completion-timeout-seconds: "3"
services:
  job: *completion-job
""",
                "aliased-services": """x-completion-services: &completion-services
  job:
    image: local/job:1
    restart: "no"
    labels:
      de.saervices.run.completion-timeout-seconds: "3"
services: *completion-services
""",
                "aliased-label-key": """x-completion-label-key: &completion-label-key de.saervices.run.completion-timeout-seconds
services:
  job:
    image: local/job:1
    restart: "no"
    labels:
      *completion-label-key: "3"
""",
                "conflicting-label-merge": """x-completion-labels: &completion-labels
  de.saervices.run.completion-timeout-seconds: "601"
services:
  job:
    image: local/job:1
    restart: "no"
    labels:
      <<: *completion-labels
      de.saervices.run.completion-timeout-seconds: "3"
""",
            }
            for label, source in raw_mutations.items():
                require(
                    bool(completion_errors(source)),
                    f"raw Compose {label} completion metadata must fail before normalization",
                )

            semantic_mutations = {
                "zero-timeout": valid_completion.replace(': "3"', ': "0"'),
                "overlong-timeout": valid_completion.replace(': "3"', ': "3601"'),
                "restart": valid_completion.replace('restart: "no"', 'restart: "always"'),
                "restart-policy": valid_completion
                + "    deploy:\n      restart_policy:\n        condition: any\n",
                "scale": valid_completion + "    scale: 2\n",
                "replicas": valid_completion + "    deploy:\n      replicas: 2\n",
                "consumer": valid_completion
                + "  app:\n    image: local/app:1\n    depends_on:\n      job:\n        condition: service_started\n",
                "links-consumer": valid_completion
                + "  app:\n    image: local/app:1\n    links:\n      - job:completion\n",
                "volumes-from-consumer": valid_completion
                + "  app:\n    image: local/app:1\n    volumes_from:\n      - job:ro\n",
                "network-mode-consumer": valid_completion
                + "  app:\n    image: local/app:1\n    network_mode: service:job\n",
                "ipc-consumer": valid_completion
                + "  app:\n    image: local/app:1\n    ipc: service:job\n",
                "pid-consumer": valid_completion
                + "  app:\n    image: local/app:1\n    pid: service:job\n",
                "dynamic-depends-on": valid_completion
                + "  app:\n    image: local/app:1\n    depends_on:\n      - ${COMPLETION_JOB:-job}\n",
                "dynamic-links": valid_completion
                + "  app:\n    image: local/app:1\n    links:\n      - ${COMPLETION_JOB:-job}:completion\n",
                "dynamic-volumes-from": valid_completion
                + "  app:\n    image: local/app:1\n    volumes_from:\n      - ${COMPLETION_JOB:-job}:ro\n",
                "dynamic-network-mode": valid_completion
                + "  app:\n    image: local/app:1\n    network_mode: ${COMPLETION_MODE:-service:job}\n",
                "dynamic-ipc": valid_completion
                + "  app:\n    image: local/app:1\n    ipc: ${COMPLETION_IPC:-service:job}\n",
                "dynamic-pid": valid_completion
                + "  app:\n    image: local/app:1\n    pid: ${COMPLETION_PID:-service:job}\n",
                "extends": valid_completion
                + "  app:\n    image: local/app:1\n    extends:\n      file: inherited.yaml\n      service: inherited\n",
                "include": "include:\n  - inherited.yaml\n" + valid_completion,
                "container-volumes-from": valid_completion
                + "  app:\n    image: local/app:1\n    volumes_from:\n      - container:completion-job:ro\n",
                "container-network-mode": valid_completion
                + "  app:\n    image: local/app:1\n    network_mode: container:completion-job\n",
                "container-ipc": valid_completion
                + "  app:\n    image: local/app:1\n    ipc: container:completion-job\n",
                "container-pid": valid_completion
                + "  app:\n    image: local/app:1\n    pid: container:completion-job\n",
                "external-links": valid_completion
                + "  app:\n    image: local/app:1\n    external_links:\n      - completion-job:completion\n",
            }
            for label, source in semantic_mutations.items():
                require(
                    bool(completion_errors(source)),
                    f"completion contract mutation '{label}' must fail closed",
                )

            gitea_app = fixture_root / checker.GITEA_COMPLETION_APP_COMPOSE
            gitea_template = (
                fixture_root / checker.GITEA_COMPLETION_TEMPLATE_COMPOSE
            )
            gitea_app.parent.mkdir(parents=True, exist_ok=True)
            gitea_template.parent.mkdir(parents=True, exist_ok=True)
            valid_gitea_app = """x-required-services:
  - gitea-oidc
services:
  app:
    image: local/gitea:1
"""
            valid_gitea_template = """services:
  gitea-oidc:
    image: local/gitea:1
    restart: "no"
    labels:
      de.saervices.run.completion-timeout-seconds: "600"
    depends_on:
      app:
        condition: service_healthy
"""

            def gitea_closure_errors(
                app_source: str = valid_gitea_app,
                template_source: str = valid_gitea_template,
            ) -> list[str]:
                gitea_app.write_text(app_source, encoding="utf-8")
                gitea_template.write_text(template_source, encoding="utf-8")
                return checker.check_gitea_completion_closure()

            require(
                not gitea_closure_errors(),
                "the exact Gitea root/template completion closure must pass",
            )
            require(
                bool(
                    gitea_closure_errors(
                        valid_gitea_app.replace("  - gitea-oidc\n", "")
                    )
                ),
                "Gitea must retain the gitea-oidc required service",
            )
            require(
                bool(
                    gitea_closure_errors(
                        valid_gitea_app.replace(
                            "    image: local/gitea:1\n",
                            "    image: local/gitea:1\n    depends_on:\n      gitea-oidc:\n        condition: service_started\n",
                        )
                    )
                ),
                "Gitea must not add a cross-file consumer for the post-start job",
            )
            require(
                bool(
                    gitea_closure_errors(
                        template_source=valid_gitea_template.replace(
                            ': "600"', ': "601"'
                        )
                    )
                ),
                "Gitea must retain the reviewed exact 600-second timeout",
            )
            require(
                bool(
                    gitea_closure_errors(
                        template_source=valid_gitea_template.replace(
                            "  gitea-oidc:\n",
                            "  gitea-oidc:\n    image: local/ignored:1\n  gitea-oidc:\n",
                            1,
                        )
                    )
                ),
                "Gitea must reject a duplicate gitea-oidc service key before Compose",
            )
            require(
                bool(
                    gitea_closure_errors(
                        template_source=valid_gitea_template.replace(
                            "services:\n",
                            "services:\n  ignored:\n    image: local/ignored:1\nservices:\n",
                            1,
                        )
                    )
                ),
                "Gitea must reject duplicate services mappings before Compose",
            )
            require(
                bool(
                    gitea_closure_errors(
                        template_source=valid_gitea_template.replace(
                            '    labels:\n      de.saervices.run.completion-timeout-seconds: "600"',
                            '    labels:\n      unrelated: "value"\n    labels:\n      de.saervices.run.completion-timeout-seconds: "600"',
                        )
                    )
                ),
                "Gitea must reject duplicate labels mappings before Compose",
            )
            require(
                bool(
                    gitea_closure_errors(
                        template_source=valid_gitea_template.replace(
                            ': "600"', ': !!str 600'
                        )
                    )
                ),
                "Gitea must retain a directly double-quoted timeout source",
            )
            require(
                bool(
                    gitea_closure_errors(
                        template_source="""x-gitea-labels: &gitea-labels
  de.saervices.run.completion-timeout-seconds: "600"
services:
  gitea-oidc:
    image: local/gitea:1
    restart: "no"
    labels:
      <<: *gitea-labels
    depends_on:
      app:
        condition: service_healthy
"""
                    )
                ),
                "Gitea must reject completion metadata inherited through a YAML merge",
            )
            gitea_reference_fields = {
                "links": "    links:\n      - gitea-oidc:completion\n",
                "volumes_from": "    volumes_from:\n      - gitea-oidc:ro\n",
                "network_mode": "    network_mode: service:gitea-oidc\n",
                "ipc": "    ipc: service:gitea-oidc\n",
                "pid": "    pid: service:gitea-oidc\n",
            }
            for field, source in gitea_reference_fields.items():
                require(
                    bool(
                        gitea_closure_errors(
                            valid_gitea_app.replace(
                                "    image: local/gitea:1\n",
                                "    image: local/gitea:1\n" + source,
                            )
                        )
                    ),
                    f"Gitea must reject a cross-file {field} consumer of gitea-oidc",
                )
            gitea_dynamic_reference_fields = {
                "depends_on": "    depends_on:\n      - ${OIDC_JOB:-gitea-oidc}\n",
                "links": "    links:\n      - ${OIDC_JOB:-gitea-oidc}:completion\n",
                "volumes_from": "    volumes_from:\n      - ${OIDC_JOB:-gitea-oidc}:ro\n",
                "network_mode": "    network_mode: ${OIDC_MODE:-service:gitea-oidc}\n",
                "ipc": "    ipc: ${OIDC_IPC:-service:gitea-oidc}\n",
                "pid": "    pid: ${OIDC_PID:-service:gitea-oidc}\n",
            }
            for field, source in gitea_dynamic_reference_fields.items():
                require(
                    bool(
                        gitea_closure_errors(
                            valid_gitea_app.replace(
                                "    image: local/gitea:1\n",
                                "    image: local/gitea:1\n" + source,
                            )
                        )
                    ),
                    f"Gitea must reject interpolated {field} service references",
                )
            require(
                bool(
                    gitea_closure_errors(
                        "include:\n  - observer.yaml\n" + valid_gitea_app
                    )
                ),
                "Gitea root app must reject top-level Compose include",
            )
            require(
                bool(
                    gitea_closure_errors(
                        template_source="include:\n  - observer.yaml\n"
                        + valid_gitea_template
                    )
                ),
                "Gitea OIDC template must reject top-level Compose include",
            )
            require(
                bool(
                    gitea_closure_errors(
                        valid_gitea_app.replace(
                            "    image: local/gitea:1\n",
                            "    image: local/gitea:1\n    extends:\n      file: observer.yaml\n      service: observer\n",
                        )
                    )
                ),
                "Gitea completion closure must reject service extends",
            )
            require(
                bool(
                    gitea_closure_errors(
                        template_source="""x-gitea-job: &gitea-job
  image: local/gitea:1
  restart: "no"
  labels:
    de.saervices.run.completion-timeout-seconds: "600"
  depends_on:
    app:
      condition: service_healthy
services:
  gitea-oidc: *gitea-job
"""
                    )
                ),
                "Gitea must reject an aliased gitea-oidc service mapping",
            )
            observer_dir = fixture_root / "templates/observer"
            observer_dir.mkdir(parents=True, exist_ok=True)
            observer_path = observer_dir / "docker-compose.observer.yaml"
            observer_path.write_text(
                """services:
  observer:
    image: local/observer:1
    depends_on:
      gitea-oidc:
        condition: service_started
""",
                encoding="utf-8",
            )
            app_with_observer = valid_gitea_app.replace(
                "  - gitea-oidc\n",
                "  - gitea-oidc\n  - observer\n",
            )
            require(
                bool(gitea_closure_errors(app_with_observer)),
                "Gitea must inspect a newly required template for completion consumers",
            )

            observer_child_dir = fixture_root / "templates/observer-child"
            observer_child_dir.mkdir(parents=True, exist_ok=True)
            observer_child_path = (
                observer_child_dir / "docker-compose.observer-child.yaml"
            )
            observer_path.write_text(
                """x-required-services:
  - observer-child
services:
  observer:
    image: local/observer:1
""",
                encoding="utf-8",
            )
            observer_child_path.write_text(
                """services:
  observer-child:
    image: local/observer-child:1
    network_mode: service:gitea-oidc
""",
                encoding="utf-8",
            )
            require(
                bool(gitea_closure_errors(app_with_observer)),
                "Gitea must recursively inspect nested required templates for completion consumers",
            )
            linked_target = fixture_root / "templates/linked-target"
            linked_target.mkdir(parents=True, exist_ok=True)
            (linked_target / "docker-compose.linked-observer.yaml").write_text(
                "services:\n  linked-observer:\n    image: local/observer:1\n",
                encoding="utf-8",
            )
            (fixture_root / "templates/linked-observer").symlink_to(
                "linked-target",
                target_is_directory=True,
            )
            app_with_linked_observer = valid_gitea_app.replace(
                "  - gitea-oidc\n",
                "  - gitea-oidc\n  - linked-observer\n",
            )
            require(
                bool(gitea_closure_errors(app_with_linked_observer)),
                "Gitea must reject required Compose files below a symlinked template directory",
            )
        finally:
            checker.REPO_ROOT = previous_root
            outside.unlink()

    service = traefik_service_fixture()

    require(
        not management_errors(checker, copy.deepcopy(service)),
        "the secure Træefik management-plane fixture must pass",
    )
    for tls_flag in (
        "--entrypoints.websecure.http.tls=true",
        "--entrypoints.websecure.http.tls.certresolver=production",
        "--entrypoints.websecure.http.tls.options=global-tls-opts@file",
    ):
        incomplete_entrypoint_tls = copy.deepcopy(service)
        incomplete_entrypoint_tls["command"].remove(tls_flag)
        require(
            any(
                "TLS-only" in error
                for error in management_errors(checker, incomplete_entrypoint_tls)
            ),
            f"missing centræl EntryPoint TLS field '{tls_flag}' must fæil closed",
        )

    partial_router_tls = copy.deepcopy(service)
    partial_router_tls["labels"].append(
        "traefik.http.routers.fixture.tls=true"
    )
    require(
        any("TLS-only" in error for error in management_errors(checker, partial_router_tls)),
        "æ pærtiæl router-level TLS object must not inherit missing resolver or options fields",
    )
    require(
        not checker.check_traefik_access_log_privacy(
            "Fixture/docker-compose.app.yaml",
            "traefik",
            copy.deepcopy(service),
        ),
        "Træefik access logs with query-pæræmeter dropping must pass",
    )
    require(
        not checker.check_traefik_encoded_character_policy(
            "Fixture/docker-compose.app.yaml",
            "traefik",
            copy.deepcopy(service),
        ),
        "the cænonicæl explicit encoded-chæræcter policies must pæss",
    )

    for entrypoint, policy in checker.TRAEFIK_ENCODED_CHARACTER_POLICIES.items():
        for field, expected in policy.items():
            flag = f"--entrypoints.{entrypoint}.http.encodedcharacters.{field}"
            missing_policy = copy.deepcopy(service)
            missing_policy["command"] = [
                token
                for token in missing_policy["command"]
                if not str(token).lower().startswith(f"{flag}=")
            ]
            require(
                checker.check_traefik_encoded_character_policy(
                    "Fixture/docker-compose.app.yaml",
                    "traefik",
                    missing_policy,
                ),
                f"missing encoded-chæræcter flæg '{flag}' must fæil closed",
            )

            wrong_policy = copy.deepcopy(service)
            wrong_value = str(not expected).lower()
            wrong_policy["command"] = [
                f"{flag}={wrong_value}"
                if str(token).lower().startswith(f"{flag}=")
                else token
                for token in wrong_policy["command"]
            ]
            require(
                checker.check_traefik_encoded_character_policy(
                    "Fixture/docker-compose.app.yaml",
                    "traefik",
                    wrong_policy,
                ),
                f"wrong encoded-chæræcter vælue for '{flag}' must fæil closed",
            )

    duplicate_policy = copy.deepcopy(service)
    duplicate_policy["command"].append(
        "--entrypoints.web.http.encodedcharacters.allowencodedslash=false"
    )
    require(
        checker.check_traefik_encoded_character_policy(
            "Fixture/docker-compose.app.yaml",
            "traefik",
            duplicate_policy,
        ),
        "duplicæte encoded-chæræcter flægs must fæil closed",
    )

    split_cli_policy = copy.deepcopy(service)
    split_flag = "--entrypoints.web.http.encodedcharacters.allowencodedslash"
    split_cli_policy["command"] = [
        token
        for token in split_cli_policy["command"]
        if not str(token).lower().startswith(f"{split_flag}=")
    ]
    split_cli_policy["entrypoint"] = ["traefik", split_flag, "false"]
    require(
        not checker.check_traefik_encoded_character_policy(
            "Fixture/docker-compose.app.yaml",
            "traefik",
            split_cli_policy,
        ),
        "explicit split-form CLI encoded-chæræcter flægs must pæss",
    )

    environment_only_policy = copy.deepcopy(service)
    environment_only_policy["command"] = [
        token
        for token in environment_only_policy["command"]
        if not str(token).lower().startswith(f"{split_flag}=")
    ]
    environment_only_policy["environment"] = {
        "TRAEFIK_ENTRYPOINTS_WEB_HTTP_ENCODEDCHARACTERS_ALLOWENCODEDSLASH": "false"
    }
    require(
        checker.check_traefik_encoded_character_policy(
            "Fixture/docker-compose.app.yaml",
            "traefik",
            environment_only_policy,
        ),
        "the explicit CLI encoded-chæræcter contræct must not be sætisfied only by environment",
    )

    unknown_http_entrypoint = copy.deepcopy(service)
    unknown_http_entrypoint["command"].append(
        "--entrypoints.custom.http.encodedcharacters.allowencodedslash=false"
    )
    require(
        any(
            "unknown HTTP EntryPoint 'custom'" in error
            for error in checker.check_traefik_encoded_character_policy(
                "Fixture/docker-compose.app.yaml",
                "traefik",
                unknown_http_entrypoint,
            )
        ),
        "encoded-chæræcter configurætion on æn unknown EntryPoint must fæil closed",
    )

    unknown_encoded_field = copy.deepcopy(service)
    unknown_encoded_field["command"].append(
        "--entrypoints.web.http.encodedcharacters.allowencodedcolon=false"
    )
    require(
        any(
            "unknown field 'allowencodedcolon'" in error
            for error in checker.check_traefik_encoded_character_policy(
                "Fixture/docker-compose.app.yaml",
                "traefik",
                unknown_encoded_field,
            )
        ),
        "unknown encoded-chæræcter fields must fæil closed",
    )

    mixed_case_encoded_flag = copy.deepcopy(service)
    mixed_case_encoded_flag["command"] = [
        str(token).replace(
            ".http.encodedcharacters.allowencodedslash=",
            ".http.encodedCharacters.allowEncodedSlash=",
        )
        if str(token).startswith("--entrypoints.web.http.encodedcharacters.allowencodedslash=")
        else token
        for token in mixed_case_encoded_flag["command"]
    ]
    require(
        any(
            "must use lower-case spelling" in error
            for error in checker.check_traefik_encoded_character_policy(
                "Fixture/docker-compose.app.yaml",
                "traefik",
                mixed_case_encoded_flag,
            )
        ),
        "mixed-cæse encoded-chæræcter CLI flægs must fæil closed",
    )

    tcp_only_entrypoint = copy.deepcopy(service)
    tcp_only_entrypoint["command"].append("--entrypoints.tcp-only.address=:8443")
    require(
        not checker.check_traefik_encoded_character_policy(
            "Fixture/docker-compose.app.yaml",
            "traefik",
            tcp_only_entrypoint,
        ),
        "æn æddress-only unknown EntryPoint must not be æssumed to use HTTP",
    )

    partial_policy_without_address = copy.deepcopy(service)
    partial_policy_without_address["command"] = [
        token
        for token in partial_policy_without_address["command"]
        if not str(token).lower().startswith("--entrypoints.web.address=")
        and not (
            str(token).lower().startswith(
                "--entrypoints.web.http.encodedcharacters."
            )
            and "allowencodedslash=" not in str(token).lower()
        )
    ]
    require(
        checker.check_traefik_encoded_character_policy(
            "Fixture/docker-compose.app.yaml",
            "traefik",
            partial_policy_without_address,
        ),
        "one encoded-chæræcter flæg must trigger complete policy vælidætion even without æ CLI æddress",
    )

    environment_address_policy = copy.deepcopy(service)
    environment_address_policy["command"] = [
        token
        for token in environment_address_policy["command"]
        if not str(token).lower().startswith("--entrypoints.web.address=")
        and not str(token).lower().startswith(
            "--entrypoints.web.http.encodedcharacters."
        )
    ]
    environment_address_policy["environment"] = {
        "TRAEFIK_ENTRYPOINTS_WEB_ADDRESS": ":80"
    }
    require(
        checker.check_traefik_encoded_character_policy(
            "Fixture/docker-compose.app.yaml",
            "traefik",
            environment_address_policy,
        ),
        "æn environment-configured known HTTP EntryPoint must still require explicit CLI policy flægs",
    )

    long_host_rule = "(" + " || ".join(
        f"Host(`vaultwarden.{index}.very-long-dev-domain.example`)"
        for index in range(5)
    ) + ")"
    router_priority_fixture = {
        "services": {
            "app": {
                "labels": [
                    f"traefik.http.routers.app.rule={long_host_rule}",
                    "traefik.http.routers.app.entrypoints=websecure",
                    "traefik.http.routers.app.priority=10",
                ]
            },
            "protected": {
                "labels": {
                    "traefik.http.routers.app-admin.rule": (
                        f"{long_host_rule} && PathPrefix(`/admin`)"
                    ),
                    "traefik.http.routers.app-admin.entrypoints": "websecure",
                    "traefik.http.routers.app-admin.priority": "100",
                }
            },
        }
    }

    def priority_errors(data: dict[str, Any]) -> list[str]:
        return checker.check_traefik_router_priority_overlaps(
            "Fixture/docker-compose.main.yaml",
            checker.collect_compose_traefik_http_routers(data),
        )

    require(
        not priority_errors(copy.deepcopy(router_priority_fixture)),
        "long multi-host generic 10 plus protected 100 routers must pass",
    )

    missing_generic_priority = copy.deepcopy(router_priority_fixture)
    missing_generic_priority["services"]["app"]["labels"] = [
        label
        for label in missing_generic_priority["services"]["app"]["labels"]
        if not str(label).endswith(".priority=10")
    ]
    require(
        priority_errors(missing_generic_priority),
        "æn implicit generic router must not compete with æn explicit protected router",
    )

    missing_focused_priority = copy.deepcopy(router_priority_fixture)
    missing_focused_priority["services"]["protected"]["labels"].pop(
        "traefik.http.routers.app-admin.priority"
    )
    require(
        priority_errors(missing_focused_priority),
        "æn explicit generic router must not compete with æn implicit focused router",
    )

    for invalid_priority in ("0", "${ROUTER_PRIORITY}", "high"):
        invalid_generic_priority = copy.deepcopy(router_priority_fixture)
        replace_label(
            invalid_generic_priority["services"]["app"],
            ".priority",
            invalid_priority,
        )
        require(
            priority_errors(invalid_generic_priority),
            f"non-positive or non-literæl router priority '{invalid_priority}' must fæil closed",
        )

    for focused_priority in ("10", "9"):
        invalid_order = copy.deepcopy(router_priority_fixture)
        invalid_order["services"]["protected"]["labels"][
            "traefik.http.routers.app-admin.priority"
        ] = focused_priority
        require(
            priority_errors(invalid_order),
            "focused router priority must be strictly greæter thæn the generic priority",
        )

    all_implicit = copy.deepcopy(missing_generic_priority)
    all_implicit["services"]["protected"]["labels"].pop(
        "traefik.http.routers.app-admin.priority"
    )
    require(
        priority_errors(all_implicit),
        "overlæpping routers must not rely on implicit rule-length ordering",
    )

    single_router = {"services": {"app": router_priority_fixture["services"]["app"]}}
    require(
        not priority_errors(single_router),
        "æ single router does not require æn explicit priority",
    )

    distinct_hosts = copy.deepcopy(all_implicit)
    distinct_hosts["services"]["protected"]["labels"][
        "traefik.http.routers.app-admin.rule"
    ] = "Host(`admin.other.example`) && PathPrefix(`/admin`)"
    require(
        not priority_errors(distinct_hosts),
        "routers without æ generic/focused rule relætionship must not be coupled",
    )

    disjoint_entrypoints = copy.deepcopy(all_implicit)
    disjoint_entrypoints["services"]["protected"]["labels"][
        "traefik.http.routers.app-admin.entrypoints"
    ] = "web"
    require(
        not priority_errors(disjoint_entrypoints),
        "routers on disjoint explicit EntryPoints must not be treæted æs competitors",
    )

    reordered_focus = copy.deepcopy(router_priority_fixture)
    reordered_focus["services"]["protected"]["labels"][
        "traefik.http.routers.app-admin.rule"
    ] = f"PathPrefix(`/admin`) && {long_host_rule}"
    require(
        not priority_errors(reordered_focus),
        "top-level ÆND clæuse order must not hide æ vælid generic/focused relætionship",
    )

    file_provider_routers = checker.collect_file_traefik_http_routers(
        {
            "http": {
                "routers": {
                    "vaultwarden": {
                        "rule": long_host_rule,
                        "priority": 10,
                    },
                    "vaultwarden-admin": {
                        "rule": f"{long_host_rule} && PathPrefix(`/admin`)",
                        "priority": 200,
                    },
                }
            }
        },
        "vaultwarden.yaml.template",
    )
    require(
        not checker.check_traefik_router_priority_overlaps(
            "Traefik/docker-compose.app.yaml",
            file_provider_routers,
        ),
        "file-provider routers must use the sæme deterministic priority contræct",
    )

    missing_query_drop = copy.deepcopy(service)
    missing_query_drop["command"] = [
        token
        for token in missing_query_drop["command"]
        if not str(token).startswith("--accesslog.fields.queryparameters.defaultmode")
    ]
    require(
        checker.check_traefik_access_log_privacy(
            "Fixture/docker-compose.app.yaml",
            "traefik",
            missing_query_drop,
        ),
        "enæbled Træefik access logs without æ query-pæræmeter policy must fæil closed",
    )

    query_keep = copy.deepcopy(service)
    query_keep["command"] = [
        "--accesslog.fields.queryparameters.defaultmode=keep"
        if str(token).startswith("--accesslog.fields.queryparameters.defaultmode")
        else token
        for token in query_keep["command"]
    ]
    require(
        checker.check_traefik_access_log_privacy(
            "Fixture/docker-compose.app.yaml",
            "traefik",
            query_keep,
        ),
        "explicit Træefik query-pæræmeter retention must fæil closed",
    )

    environment_query_drop = copy.deepcopy(missing_query_drop)
    environment_query_drop["command"] = [
        token
        for token in environment_query_drop["command"]
        if not str(token).startswith("--accesslog")
    ]
    environment_query_drop["environment"] = {
        "TRAEFIK_ACCESSLOG": "true",
        "TRAEFIK_ACCESSLOG_FIELDS_QUERYPARAMETERS_DEFAULTMODE": "drop"
    }
    require(
        not checker.check_traefik_access_log_privacy(
            "Fixture/docker-compose.app.yaml",
            "traefik",
            environment_query_drop,
        ),
        "the officiæl Træefik environment key for query-pæræmeter dropping must pass",
    )

    mixed_query_sources = copy.deepcopy(service)
    mixed_query_sources["command"] = [
        "--accesslog.fields.queryparameters.defaultmode=keep"
        if str(token).startswith("--accesslog.fields.queryparameters.defaultmode")
        else token
        for token in mixed_query_sources["command"]
    ]
    mixed_query_sources["environment"] = {
        "TRAEFIK_ACCESSLOG_FIELDS_QUERYPARAMETERS_DEFAULTMODE": "drop"
    }
    require(
        checker.check_traefik_access_log_privacy(
            "Fixture/docker-compose.app.yaml",
            "traefik",
            mixed_query_sources,
        ),
        "æ lower-precedence environment drop must not hide æ CLI query keep",
    )

    with tempfile.TemporaryDirectory(prefix="hardening-file-watch.", dir="/tmp") as raw_root:
        fixture_root = Path(raw_root)
        dynamic_root = fixture_root / "Fixture/appdata/config/dynamic"
        dynamic_root.mkdir(parents=True)
        (dynamic_root / "root.yaml").write_text("http: {}\n", encoding="utf-8")
        file_provider_service = copy.deepcopy(service)
        file_provider_service["volumes"] = [
            "./appdata/config/dynamic:/etc/traefik/dynamic:ro"
        ]
        file_provider_service["command"].extend(
            [
                "--providers.file.directory=/etc/traefik/dynamic",
                "--providers.file.watch=true",
            ]
        )
        previous_root = checker.REPO_ROOT
        checker.REPO_ROOT = fixture_root
        try:
            require(
                not checker.check_traefik_file_provider_watch(
                    "Fixture/docker-compose.app.yaml",
                    "traefik",
                    file_provider_service,
                ),
                "æ flæt wætched Træefik file-provider directory must pass",
            )
            watch_disabled = copy.deepcopy(file_provider_service)
            watch_disabled["command"][-1] = "--providers.file.watch=false"
            require(
                checker.check_traefik_file_provider_watch(
                    "Fixture/docker-compose.app.yaml",
                    "traefik",
                    watch_disabled,
                ),
                "æn explicitly disæbled Træefik file-provider wætch must fæil closed",
            )
            environment_provider = copy.deepcopy(service)
            environment_provider["volumes"] = [
                "./appdata/config/dynamic:/etc/traefik/dynamic:ro"
            ]
            environment_provider["environment"] = {
                "TRAEFIK_PROVIDERS_FILE_DIRECTORY": "/etc/traefik/dynamic",
                "TRAEFIK_PROVIDERS_FILE_WATCH": "true",
            }
            require(
                not checker.check_traefik_file_provider_watch(
                    "Fixture/docker-compose.app.yaml",
                    "traefik",
                    environment_provider,
                ),
                "æn environment-configured flæt Træefik file provider must pass",
            )
            environment_provider["environment"][
                "TRAEFIK_PROVIDERS_FILE_WATCH"
            ] = "false"
            require(
                checker.check_traefik_file_provider_watch(
                    "Fixture/docker-compose.app.yaml",
                    "traefik",
                    environment_provider,
                ),
                "æn environment-configured disæbled Træefik file wætch must fæil closed",
            )
            priority_template = dynamic_root / "priority.yaml.template"
            priority_template.write_text(
                """http:
  routers:
    generic:
      rule: Host(`app.example`)
      service: generic
    protected:
      rule: Host(`app.example`) && PathPrefix(`/admin`)
      priority: 100
      service: protected
""",
                encoding="utf-8",
            )
            require(
                checker.check_traefik_file_provider_router_priorities(
                    "Fixture/docker-compose.app.yaml",
                    "traefik",
                    file_provider_service,
                ),
                "æn inert file-provider templæte with mixed priorities must fæil closed",
            )
            priority_template.write_text(
                """http:
  routers:
    generic:
      rule: Host(`app.example`)
      priority: 10
      service: generic
    protected:
      rule: Host(`app.example`) && PathPrefix(`/admin`)
      priority: 100
      service: protected
""",
                encoding="utf-8",
            )
            require(
                not checker.check_traefik_file_provider_router_priorities(
                    "Fixture/docker-compose.app.yaml",
                    "traefik",
                    file_provider_service,
                ),
                "æn inert file-provider templæte with ordered explicit priorities must pæss",
            )
            nested = dynamic_root / "nested/live.yaml"
            nested.parent.mkdir()
            nested.write_text("http: {}\n", encoding="utf-8")
            require(
                checker.check_traefik_file_provider_watch(
                    "Fixture/docker-compose.app.yaml",
                    "traefik",
                    file_provider_service,
                ),
                "nested live Træefik configurætion must fæil the hot-reloæd contræct",
            )
            nested.rename(nested.with_suffix(".yaml.template"))
            require(
                not checker.check_traefik_file_provider_watch(
                    "Fixture/docker-compose.app.yaml",
                    "traefik",
                    file_provider_service,
                ),
                "nested inert Træefik templæte files must not count æs live configurætion",
            )
            file_provider_service["volumes"] = [
                "./appdata/config/dynamic:/etc/traefik/dynamic:rw"
            ]
            require(
                checker.check_traefik_file_provider_watch(
                    "Fixture/docker-compose.app.yaml",
                    "traefik",
                    file_provider_service,
                ),
                "æ writæble Træefik file-provider configurætion bind must fæil closed",
            )
            file_provider_service["volumes"] = []
            require(
                checker.check_traefik_file_provider_watch(
                    "Fixture/docker-compose.app.yaml",
                    "traefik",
                    file_provider_service,
                ),
                "æn uninspectæble wætched Træefik provider directory must fæil closed",
            )
        finally:
            checker.REPO_ROOT = previous_root

    unauthenticated = copy.deepcopy(service)
    replace_label(unauthenticated, ".middlewares", "noauth@file")
    require(
        any("authenticated" in error for error in management_errors(checker, unauthenticated)),
        "an arbitrary middleware name containing 'auth' must not satisfy authentication",
    )

    invalid_docker_auth = copy.deepcopy(service)
    replace_label(invalid_docker_auth, ".middlewares", "auth@docker")
    invalid_docker_auth["labels"].append(
        "traefik.http.middlewares.auth.forwardauth.nonsense=configured"
    )
    require(
        any("authenticated" in error for error in management_errors(checker, invalid_docker_auth)),
        "a Docker-label auth middleware must define its type-specific credential or endpoint",
    )

    malformed_docker_auth = copy.deepcopy(service)
    replace_label(malformed_docker_auth, ".middlewares", "auth@docker")
    malformed_docker_auth["labels"].append(
        "traefik.http.middlewares.auth.forwardauth.address=garbage"
    )
    require(
        any("authenticated" in error for error in management_errors(checker, malformed_docker_auth)),
        "a Docker-label forwardAuth address must be an HTTP(S) endpoint",
    )

    canonical_file_auth = """http:
  middlewares:
    authentik-proxy:
      forwardAuth:
        address: https://auth.example/outpost.goauthentik.io/auth/traefik
        maxResponseBodySize: 1048576
"""
    require(
        file_auth_is_trusted(checker, canonical_file_auth),
        "the cænonicæl bounded Æuthentik file-provider middlewære must remæin trusted",
    )
    require(
        not file_auth_response_limit_errors(checker, canonical_file_auth),
        "the cænonicæl 1 MiB Æuthentik ForwærdÆuth response limit must pæss",
    )
    missing_cap_snapshot = canonical_file_auth.replace(
        "        maxResponseBodySize: 1048576\n",
        "",
    )
    require(
        len(file_auth_response_limit_errors(checker, missing_cap_snapshot)) == 1,
        "the Træefik file-provider service must report one shæred middlewære error",
    )
    require(
        not file_auth_response_limit_errors(
            checker,
            missing_cap_snapshot,
            service={"image": "crowdsecurity/crowdsec:latest"},
            service_name="crowdsec_agent",
        ),
        "sætellite services in the Træefik project must not duplicæte shæred file-provider findings",
    )
    explicit_disabled_forward_body = canonical_file_auth.replace(
        "        maxResponseBodySize: 1048576\n",
        "        maxResponseBodySize: 1048576\n        forwardBody: false\n",
    )
    require(
        not file_auth_response_limit_errors(
            checker,
            explicit_disabled_forward_body,
        ),
        "literæl forwardBody: false with no maxBodySize must pæss",
    )

    for invalid_forward_body in (
        "true",
        "0",
        "'false'",
        "${AUTHENTIK_FORWARD_BODY}",
    ):
        configured_forward_body = canonical_file_auth.replace(
            "        maxResponseBodySize: 1048576\n",
            f"        maxResponseBodySize: 1048576\n        forwardBody: {invalid_forward_body}\n",
        )
        require(
            file_auth_response_limit_errors(
                checker,
                configured_forward_body,
            ),
            f"non-cænonicæl forwardBody vælue '{invalid_forward_body}' must fæil closed",
        )

    duplicate_disabled_forward_body = canonical_file_auth.replace(
        "        maxResponseBodySize: 1048576\n",
        "        maxResponseBodySize: 1048576\n        forwardBody: false\n        forwardBody: false\n",
    )
    require(
        file_auth_response_limit_errors(
            checker,
            duplicate_disabled_forward_body,
        ),
        "duplicæte forwardBody settings must fæil closed",
    )

    for forward_body_line in ("", "        forwardBody: false\n"):
        request_body_limit = canonical_file_auth.replace(
            "        maxResponseBodySize: 1048576\n",
            "        maxResponseBodySize: 1048576\n"
            f"{forward_body_line}        maxBodySize: 1048576\n",
        )
        require(
            any(
                "must omit maxBodySize" in error
                for error in file_auth_response_limit_errors(
                    checker,
                    request_body_limit,
                )
            ),
            "maxBodySize must be rejected while forwardBody is omitted or false",
        )

    for invalid_response_limit in (
        "",
        "        maxBodySize: 1048576\n",
        "        maxResponseBodySize: 0\n",
        "        maxResponseBodySize: -1\n",
        "        maxResponseBodySize: 1048575\n",
        "        maxResponseBodySize: 1048577\n",
        "        maxResponseBodySize: ${AUTHENTIK_RESPONSE_LIMIT}\n",
        "        maxResponseBodySize: '1048576'\n",
        "        maxResponseBodySize: 1048576\n        maxResponseBodySize: 1048576\n",
    ):
        invalid_file_auth_limit = """http:
  middlewares:
    authentik-proxy:
      forwardAuth:
        address: https://auth.example/outpost.goauthentik.io/auth/traefik
""" + invalid_response_limit
        require(
            file_auth_response_limit_errors(checker, invalid_file_auth_limit),
            "missing, unbounded, non-cænonicæl, or duplicæte maxResponseBodySize must fæil closed",
        )

    for invalid_file_auth in (
        "http:\n  middlewares:\n    authentik-proxy:\n      forwardAuth:\n",
        "http:\n  middlewares:\n    authentik-proxy:\n      forwardAuth:\n        address: ''\n",
        "not_http:\n  middlewares:\n    authentik-proxy:\n      forwardAuth:\n        address: https://auth.example/outpost.goauthentik.io/auth/traefik\n",
    ):
        require(
            not file_auth_is_trusted(checker, invalid_file_auth),
            "file-provider auth must have the correct hierarchy and a non-empty endpoint",
        )

    host_bypass = copy.deepcopy(service)
    labels = host_bypass.get("labels")
    require(isinstance(labels, list), "Træefik fixture labels must be list form")
    for index, label in enumerate(labels):
        if ".rule=" in str(label).lower():
            labels[index] = str(label).replace(") && (", ") || (")
            break
    require(
        any("path-scoped" in error for error in management_errors(checker, host_bypass)),
        "the host scope must be AND-connected to the API/dashboard path scope",
    )

    for command in (
        "wget --spider http://example.com/ping && echo http://127.0.0.1:8080/ping",
        "curl -f http://example.com/ping; printf http://127.0.0.1:8080/ping",
        "wget --spider http://127.0.0.1:8080/ping || true",
    ):
        unrelated = copy.deepcopy(service)
        unrelated["healthcheck"]["test"] = ["CMD-SHELL", command]
        require(
            any("actively probe /ping" in error for error in management_errors(checker, unrelated)),
            "loopback text from an unrelated command must not satisfy the health probe",
        )

    echoed = copy.deepcopy(service)
    echoed["healthcheck"]["test"] = [
        "CMD",
        "echo",
        "wget",
        "http://127.0.0.1:8080/ping",
    ]
    require(
        any("actively probe /ping" in error for error in management_errors(checker, echoed)),
        "curl/wget text after a non-probe executable must not satisfy the healthcheck",
    )

    literal_default = copy.deepcopy(service)
    literal_default["healthcheck"]["test"] = [
        "CMD",
        "wget",
        "--spider",
        "--quiet",
        "http://127.0.0.1:8080/ping",
    ]
    require(
        not management_errors(checker, literal_default),
        "a literal port matching the configured Compose default must be accepted",
    )

    wrong_port = copy.deepcopy(service)
    wrong_port["healthcheck"]["test"] = [
        "CMD",
        "wget",
        "--spider",
        "--quiet",
        "http://127.0.0.1:9999/ping",
    ]
    require(
        any("configured Ping EntryPoint port" in error for error in management_errors(checker, wrong_port)),
        "the healthcheck port must match the configured Ping EntryPoint",
    )

    insecure_entrypoint = copy.deepcopy(service)
    insecure_entrypoint["entrypoint"] = ["traefik", "--api.insecure=true"]
    require(
        checker.command_enables_flag(insecure_entrypoint, "--api.insecure"),
        "security flags in Compose entrypoint must be detected",
    )

    proxy_protocol_insecure_command = copy.deepcopy(service)
    proxy_protocol_insecure_command["command"].append(
        "--entrypoints.websecure.proxyprotocol.insecure=true"
    )
    require(
        checker.check_traefik_proxy_protocol_security(
            "Fixture/docker-compose.app.yaml",
            "traefik",
            proxy_protocol_insecure_command,
        ),
        "proxyProtocol.insecure in Compose command must fæil closed",
    )

    proxy_protocol_insecure_entrypoint = copy.deepcopy(service)
    proxy_protocol_insecure_entrypoint["entrypoint"] = [
        "traefik",
        "--entrypoints.websecure.proxyprotocol.insecure",
        "true",
    ]
    require(
        checker.check_traefik_proxy_protocol_security(
            "Fixture/docker-compose.app.yaml",
            "traefik",
            proxy_protocol_insecure_entrypoint,
        ),
        "proxyProtocol.insecure in Compose entrypoint must fæil closed",
    )

    proxy_protocol_insecure_environment = copy.deepcopy(service)
    proxy_protocol_insecure_environment["environment"] = {
        "TRAEFIK_ENTRYPOINTS_WEBSECURE_PROXYPROTOCOL_INSECURE": "true"
    }
    require(
        checker.check_traefik_proxy_protocol_security(
            "Fixture/docker-compose.app.yaml",
            "traefik",
            proxy_protocol_insecure_environment,
        ),
        "the officiæl proxyProtocol.insecure environment key must fæil closed",
    )

    for explicitly_safe_proxy_protocol in (
        "--entrypoints.websecure.proxyprotocol.insecure=false",
        "--entrypoints.websecure.proxyprotocol.trustedips=192.168.20.100/32",
    ):
        safe_proxy_protocol = copy.deepcopy(service)
        safe_proxy_protocol["command"].append(explicitly_safe_proxy_protocol)
        require(
            not checker.check_traefik_proxy_protocol_security(
                "Fixture/docker-compose.app.yaml",
                "traefik",
                safe_proxy_protocol,
            ),
            "explicitly disæbled or source-restricted PROXY protocol must pæss",
        )

    published = {
        "ports": [
            "${HOST_PORT:-18080}:${TRAEFIK_PORT:-8080}",
            "[::1]:19000:9000-9002/tcp",
        ],
        "expose": ["7000-7002/tcp"],
    }
    targets = checker.published_target_ports(published)
    require(
        {"${TRAEFIK_PORT:-8080}", "${TRAEFIK_PORT}", "8080"} <= targets,
        "Compose defaults in target ports must be normalized",
    )
    require(
        {"9000", "9001", "9002", "7000", "7001", "7002"} <= targets,
        "published/exposed target port ranges must be expanded",
    )
    require(
        checker.compose_port_target("[::1]:19000:9000/tcp") == "9000",
        "IPv6 Compose short syntax must resolve the container-side port",
    )

    health_ports = checker.healthcheck_ping_ports(service.get("healthcheck"))
    require(
        "${TRAEFIK_PORT:-8080}" in health_ports,
        "the real loopback /ping healthcheck port must be extracted",
    )

    isolated_socket_proxy = {
        "services": {
            "socketproxy": {
                "volumes": ["/var/run/docker.sock:/var/run/docker.sock:ro"],
                "networks": ["socketproxy"],
                "environment": {
                    guard: "0" for guard in checker.SOCKET_PROXY_WRITE_GUARDS
                },
            },
            "app": {
                "environment": {"DOCKER_HOST": "tcp://app-socketproxy:2375"},
                "networks": ["socketproxy"],
            },
        },
        "networks": {"socketproxy": {"internal": True}},
    }
    require(
        not checker.check_socket_proxy_network_isolation(
            "Fixture/docker-compose.main.yaml",
            isolated_socket_proxy,
        ),
        "a project-local internal Docker socket proxy network must pass",
    )

    shared_socket_proxy = copy.deepcopy(isolated_socket_proxy)
    shared_socket_proxy["services"]["socketproxy"]["networks"] = ["backend"]
    shared_socket_proxy["services"]["app"]["networks"] = ["backend"]
    shared_socket_proxy["networks"] = {"backend": {"external": True}}
    require(
        checker.check_socket_proxy_network_isolation(
            "Fixture/docker-compose.main.yaml",
            shared_socket_proxy,
        ),
        "a Docker socket proxy on a shared external backend must fail",
    )

    disconnected_consumer = copy.deepcopy(isolated_socket_proxy)
    disconnected_consumer["services"]["app"]["networks"] = ["backend"]
    disconnected_consumer["networks"]["backend"] = {"external": True}
    require(
        any(
            "consumer must share" in error
            for error in checker.check_socket_proxy_network_isolation(
                "Fixture/docker-compose.main.yaml",
                disconnected_consumer,
            )
        ),
        "a Docker socket proxy consumer outside the dedicated network must fail",
    )

    published_socket_proxy = copy.deepcopy(isolated_socket_proxy)
    published_socket_proxy["services"]["socketproxy"]["ports"] = ["2375:2375"]
    require(
        any(
            "must not be published" in error
            for error in checker.check_socket_proxy_network_isolation(
                "Fixture/docker-compose.main.yaml",
                published_socket_proxy,
            )
        ),
        "publishing a Docker socket proxy port must fail",
    )

    short_socket_proxy = copy.deepcopy(isolated_socket_proxy)
    short_socket_proxy["services"]["socketproxy"]["volumes"] = [
        "/run/user/1000/docker.sock:/var/run/docker.sock"
    ]
    require(
        checker.service_mounts_docker_socket(short_socket_proxy["services"]["socketproxy"]),
        "a two-field Docker socket bind with an alternate source must be detected",
    )
    require(
        any(
            "bind must be read-only" in error
            for error in checker.check_socket_proxy_network_isolation(
                "Fixture/docker-compose.main.yaml",
                short_socket_proxy,
            )
        ),
        "a Docker socket bind without an explicit read-only mode must fail",
    )

    intruder_socket_proxy = copy.deepcopy(isolated_socket_proxy)
    intruder_socket_proxy["services"]["intruder"] = {"networks": ["socketproxy"]}
    require(
        any(
            "not an explicitly detected proxy consumer" in error
            for error in checker.check_socket_proxy_network_isolation(
                "Fixture/docker-compose.main.yaml",
                intruder_socket_proxy,
            )
        ),
        "an unrelated third service on the privileged proxy network must fail",
    )

    for guard in checker.SOCKET_PROXY_WRITE_GUARDS:
        missing_write_guard = copy.deepcopy(isolated_socket_proxy)
        del missing_write_guard["services"]["socketproxy"]["environment"][guard]
        require(
            any(
                f"write guard {guard}" in error
                for error in checker.check_socket_proxy_network_isolation(
                    "Fixture/docker-compose.main.yaml",
                    missing_write_guard,
                )
            ),
            f"missing Docker socket proxy write guard {guard} must fail",
        )

        enabled_write_guard = copy.deepcopy(isolated_socket_proxy)
        enabled_write_guard["services"]["socketproxy"]["environment"][guard] = "1"
        require(
            any(
                f"write guard {guard}" in error
                for error in checker.check_socket_proxy_network_isolation(
                    "Fixture/docker-compose.main.yaml",
                    enabled_write_guard,
                )
            ),
            f"nonzero Docker socket proxy write guard {guard} must fail",
        )

    symbolic_socket_proxy = copy.deepcopy(isolated_socket_proxy)
    symbolic_socket_proxy["services"]["socketproxy"]["environment"] = {
        guard: f"${{SOCKETPROXY_{guard}:-0}}"
        for guard in checker.SOCKET_PROXY_WRITE_GUARDS
    }
    require(
        not checker.check_socket_proxy_network_isolation(
            "templates/socketproxy/docker-compose.socketproxy.yaml",
            {
                "services": {
                    "socketproxy": symbolic_socket_proxy["services"]["socketproxy"]
                },
                "networks": {"socketproxy": {"internal": True}},
            },
        ),
        "exact Socket Proxy environment mappings with zero defaults must pass",
    )

    with tempfile.TemporaryDirectory(
        prefix="hardening-socketproxy-component.",
        dir="/tmp",
    ) as raw_root:
        fixture_root = Path(raw_root)
        fixture_dir = fixture_root / "Fixture"
        fixture_dir.mkdir()
        component_path = fixture_dir / "docker-compose.socketproxy.yaml"
        main_path = fixture_dir / "docker-compose.main.yaml"
        generated_component = {
            "services": {
                "socketproxy": copy.deepcopy(
                    isolated_socket_proxy["services"]["socketproxy"]
                )
            },
            "networks": {"socketproxy": {"internal": True}},
        }
        component_path.write_text(
            checker.yaml.safe_dump(generated_component, sort_keys=True),
            encoding="utf-8",
        )
        previous_root = checker.REPO_ROOT
        checker.REPO_ROOT = fixture_root
        try:
            def write_main(data: dict[str, Any]) -> None:
                main_path.write_text(
                    checker.yaml.safe_dump(data, sort_keys=True),
                    encoding="utf-8",
                )

            def component_socket_errors() -> list[str]:
                errors, _warnings = checker.check_file(component_path)
                return [
                    error
                    for error in errors
                    if "Docker socket proxy" in error
                ]

            write_main(isolated_socket_proxy)
            require(
                not component_socket_errors(),
                "a generated Socket Proxy component must use its safe sibling main Compose membership union",
            )

            main_path.unlink()
            require(
                any(
                    "members must be exactly app, socketproxy" in error
                    for error in component_socket_errors()
                ),
                "a generated Socket Proxy component without its sibling main Compose must fail closed",
            )

            main_without_app = copy.deepcopy(isolated_socket_proxy)
            del main_without_app["services"]["app"]
            write_main(main_without_app)
            require(
                any(
                    "members must be exactly app, socketproxy" in error
                    for error in component_socket_errors()
                ),
                "a generated Socket Proxy component whose sibling main omits app must fail closed",
            )

            main_with_intruder = copy.deepcopy(isolated_socket_proxy)
            main_with_intruder["services"]["intruder"] = {
                "networks": ["socketproxy"]
            }
            write_main(main_with_intruder)
            require(
                any(
                    ":intruder: service on the Docker socket proxy network is not an explicitly detected proxy consumer"
                    in error
                    for error in component_socket_errors()
                ),
                "a generated Socket Proxy component must reject an intruder in its sibling main union",
            )

            main_with_proxy_side_network = copy.deepcopy(isolated_socket_proxy)
            main_with_proxy_side_network["services"]["socketproxy"]["networks"] = [
                "socketproxy",
                "side",
            ]
            main_with_proxy_side_network["services"]["intruder"] = {
                "networks": ["side"]
            }
            main_with_proxy_side_network["networks"]["side"] = {"internal": True}
            write_main(main_with_proxy_side_network)
            require(
                any(
                    "members must be exactly app, socketproxy" in error
                    for error in component_socket_errors()
                ),
                "a generated Socket Proxy component must reject a sibling proxy with a wider network boundary",
            )

            main_with_fake_consumer = copy.deepcopy(isolated_socket_proxy)
            del main_with_fake_consumer["services"]["app"]["environment"]
            write_main(main_with_fake_consumer)
            require(
                any(
                    "not an explicitly detected proxy consumer" in error
                    for error in component_socket_errors()
                ),
                "a generated Socket Proxy component must reject an app without an explicit proxy endpoint",
            )
        finally:
            checker.REPO_ROOT = previous_root

    unresolved_write_guard = copy.deepcopy(isolated_socket_proxy)
    unresolved_write_guard["services"]["socketproxy"]["environment"]["POST"] = (
        "${SOCKETPROXY_POST}"
    )
    require(
        any(
            "write guard POST" in error
            for error in checker.check_socket_proxy_network_isolation(
                "Fixture/docker-compose.main.yaml",
                unresolved_write_guard,
            )
        ),
        "a Socket Proxy write guard without a zero interpolation default must fail",
    )

    orphan_consumer = {
        "services": {
            "app": {
                "environment": {"DOCKER_HOST": "tcp://app-socketproxy:2375"},
                "networks": ["socketproxy"],
            },
        },
        "networks": {"socketproxy": {"internal": True}},
    }
    require(
        checker.check_socket_proxy_network_isolation(
            "Fixture/docker-compose.main.yaml",
            orphan_consumer,
        ),
        "a proxy endpoint reference without an actual socket-mounting proxy must fail",
    )

    raw_consumer_without_boundary = copy.deepcopy(orphan_consumer)
    raw_consumer_without_boundary["x-required-services"] = ["socketproxy"]
    raw_consumer_without_boundary["services"]["app"]["networks"] = ["backend"]
    raw_consumer_without_boundary["networks"] = {"backend": {"external": True}}
    require(
        checker.check_socket_proxy_network_isolation(
            "Fixture/docker-compose.app.yaml",
            raw_consumer_without_boundary,
        ),
        "a raw consumer must already declare its dedicated internal boundary before the proxy template is merged",
    )

    raw_consumer_fake_boundary = copy.deepcopy(orphan_consumer)
    raw_consumer_fake_boundary["x-required-services"] = ["socketproxy"]
    raw_consumer_fake_boundary["services"]["app"]["networks"] = ["fake"]
    raw_consumer_fake_boundary["networks"] = {"fake": {"internal": True}}
    require(
        checker.check_socket_proxy_network_isolation(
            "Fixture/docker-compose.app.yaml",
            raw_consumer_fake_boundary,
        ),
        "a raw consumer must join the exact project-local socketproxy network contributed by its required template",
    )

    raw_consumer_intruder = copy.deepcopy(orphan_consumer)
    raw_consumer_intruder["x-required-services"] = ["socketproxy"]
    raw_consumer_intruder["services"]["intruder"] = {
        "networks": ["socketproxy"]
    }
    require(
        any(
            "members must be exactly app" in error
            for error in checker.check_socket_proxy_network_isolation(
                "Fixture/docker-compose.app.yaml",
                raw_consumer_intruder,
            )
        ),
        "a raw app must reject a second service on the future socket proxy network",
    )

    require(
        compliance._service_uses_app_gid_as_primary_group(
            {"user": "${APP_UID:-1000}:${APP_GID:-1000}"}
        ),
        "the canonical primary APP_GID expression must be recognized",
    )
    for false_primary in (
        "${APP_UID:-1000}:${NOT_APP_GID:-1000}",
        "${APP_UID:-1000}:${APP_GID_FAKE:-1000}",
    ):
        require(
            not compliance._service_uses_app_gid_as_primary_group(
                {"user": false_primary}
            ),
            "look-alike primary-group variables must not satisfy APP_GID",
        )
    require(
        compliance._service_has_app_gid_group(
            {"group_add": ["${APP_GID:-1000}"]}
        ),
        "the canonical supplementary APP_GID expression must be recognized",
    )
    for false_group in ("${NOT_APP_GID:-1000}", "${APP_GID_FAKE:-1000}"):
        require(
            not compliance._service_has_app_gid_group(
                {"group_add": [false_group]}
            ),
            "look-alike supplementary-group variables must not satisfy APP_GID",
        )

    print(f"PASS: {ASSERTION_COUNT} targeted hardening regression assertions")


if __name__ == "__main__":
    main()
