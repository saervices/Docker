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


def require(condition: bool, message: str) -> None:
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
            "traefik.http.routers.fixture.tls=true",
            "traefik.http.middlewares.secure.forwardauth.address=https://auth.example/outpost.goauthentik.io/auth/traefik",
        ],
        "ports": ["80:80", "443:443"],
        "command": [
            "--api=true",
            "--api.dashboard=true",
            "--entrypoints.traefik-ping.address=127.0.0.1:${TRAEFIK_PORT:-8080}",
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


def management_errors(checker: ModuleType, service: dict[str, Any]) -> list[str]:
    return checker.check_traefik_management_plane(
        "Fixture/docker-compose.app.yaml",
        "traefik",
        service,
    )


def file_auth_is_trusted(checker: ModuleType, content: str) -> bool:
    with tempfile.TemporaryDirectory(prefix="hardening-file-auth.", dir="/tmp") as raw_root:
        fixture_root = Path(raw_root)
        middleware = fixture_root / "Traefik/appdata/config/middlewares.yaml"
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


def main() -> None:
    checker = load_checker()
    compliance = load_compliance_checker()

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
            ):
                files, errors = checker.find_compose_files([target])
                require(
                    not files and any(expected in error for error in errors),
                    f"explicit checker target '{target}' must fail closed",
                )
        finally:
            checker.REPO_ROOT = previous_root
            outside.unlink()

    service = traefik_service_fixture()

    require(
        not management_errors(checker, copy.deepcopy(service)),
        "the secure Træefik management-plane fixture must pass",
    )

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
            },
            "consumer": {
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
    shared_socket_proxy["services"]["consumer"]["networks"] = ["backend"]
    shared_socket_proxy["networks"] = {"backend": {"external": True}}
    require(
        checker.check_socket_proxy_network_isolation(
            "Fixture/docker-compose.main.yaml",
            shared_socket_proxy,
        ),
        "a Docker socket proxy on a shared external backend must fail",
    )

    disconnected_consumer = copy.deepcopy(isolated_socket_proxy)
    disconnected_consumer["services"]["consumer"]["networks"] = ["backend"]
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

    orphan_consumer = {
        "services": {
            "consumer": {
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
    raw_consumer_without_boundary["services"]["consumer"]["networks"] = ["backend"]
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
    raw_consumer_fake_boundary["services"]["consumer"]["networks"] = ["fake"]
    raw_consumer_fake_boundary["networks"] = {"fake": {"internal": True}}
    require(
        checker.check_socket_proxy_network_isolation(
            "Fixture/docker-compose.app.yaml",
            raw_consumer_fake_boundary,
        ),
        "a raw consumer must join the exact project-local socketproxy network contributed by its required template",
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

    print("PASS: 38 targeted hardening regression assertions")


if __name__ == "__main__":
    main()
