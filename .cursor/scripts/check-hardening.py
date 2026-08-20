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
import glob
import json
import os
import posixpath
import re
import shlex
import sys
from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]

ALLOW_MISSING_READ_ONLY = {
    ("Kimai/docker-compose.app.yaml", "app"),
    ("Kimai/docker-compose.main.yaml", "app"),
    ("Seafile/docker-compose.app.yaml", "app"),
    ("templates/collabora/docker-compose.collabora.yaml", "collabora"),
    ("templates/seafile_seadoc-server/docker-compose.seafile_seadoc-server.yaml", "seafile_seadoc-server"),
    ("templates/seafile_thumbnail-server/docker-compose.seafile_thumbnail-server.yaml", "seafile_thumbnail-server"),
}

HIGH_RISK_CAPS = {"SYS_ADMIN", "SYS_MODULE", "SYS_PTRACE", "NET_ADMIN", "DAC_OVERRIDE"}
REQUIRED_ROOT_DOCKERIGNORE_PATTERNS = {
    ".env",
    ".env*",
    "*.env",
    "app.env",
    "app.env*",
    "appdata",
    "backup",
    "backups",
    "docker-compose.main.yaml",
    "log",
    "logs",
    "node_modules",
    "restore",
    "restores",
    "secrets",
}
REQUIRED_DOCKERFILES_DOCKERIGNORE_PATTERNS = {"*", "!.dockerignore"}
ROOT_DOCKERIGNORE_SENTINELS = {
    ".env",
    ".env.local",
    "app.env",
    "app.env.local",
    "service.env",
    "appdata/LEAK",
    "backup/LEAK",
    "backups/LEAK",
    "docker-compose.main.yaml",
    "log/LEAK",
    "logs/LEAK",
    "node_modules/LEAK",
    "restore/LEAK",
    "restores/LEAK",
    "secrets/LEAK",
}
ROOT_SENSITIVE_PATH_PARTS = {
    "appdata",
    "backup",
    "backups",
    "log",
    "logs",
    "node_modules",
    "restore",
    "restores",
    "secrets",
}


def rel(path: Path) -> str:
    return path.resolve().relative_to(REPO_ROOT).as_posix()


def as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


FALSE_VALUES = {"false", "0", "no", "off"}
SOCKET_PROXY_WRITE_GUARDS = (
    "POST",
    "ALLOW_START",
    "ALLOW_STOP",
    "ALLOW_RESTARTS",
    "ALLOW_PAUSE",
    "ALLOW_UNPAUSE",
)
TRUSTED_FILE_AUTH_MIDDLEWARES = {
    "authentik-proxy": ("forwardauth", "address"),
}
AUTHENTIK_FORWARD_AUTH_RESPONSE_LIMIT = "1048576"
TRAEFIK_ENCODED_CHARACTER_FIELDS = (
    "allowencodedslash",
    "allowencodedbackslash",
    "allowencodednullcharacter",
    "allowencodedsemicolon",
    "allowencodedpercent",
    "allowencodedquestionmark",
    "allowencodedhash",
)
TRAEFIK_ENCODED_CHARACTER_POLICIES = {
    "web": {
        "allowencodedslash": False,
        "allowencodedbackslash": False,
        "allowencodednullcharacter": False,
        "allowencodedsemicolon": True,
        "allowencodedpercent": True,
        "allowencodedquestionmark": True,
        "allowencodedhash": True,
    },
    "websecure": {
        "allowencodedslash": False,
        "allowencodedbackslash": False,
        "allowencodednullcharacter": False,
        "allowencodedsemicolon": True,
        "allowencodedpercent": True,
        "allowencodedquestionmark": True,
        "allowencodedhash": True,
    },
    "traefik-ping": {
        field: False for field in TRAEFIK_ENCODED_CHARACTER_FIELDS
    },
}


def command_tokens(service: dict[str, Any]) -> list[str]:
    tokens: list[str] = []
    for field in ("entrypoint", "command"):
        configured = service.get(field)
        values = [configured] if isinstance(configured, str) else as_list(configured)
        for value in values:
            try:
                tokens.extend(shlex.split(str(value)))
            except ValueError:
                tokens.extend(str(value).split())
    return tokens


def configured_value_is_enabled(value: Any) -> bool:
    return str(value).strip().strip("'\"").lower() not in FALSE_VALUES


def command_flag_state(service: dict[str, Any], flag: str) -> bool | None:
    tokens = command_tokens(service)
    normalized_flag = flag.lower()
    state: bool | None = None
    for index, token in enumerate(tokens):
        normalized_token = token.lower()
        if normalized_token == normalized_flag:
            next_value = tokens[index + 1] if index + 1 < len(tokens) else ""
            if next_value.lower() in FALSE_VALUES | {"true", "1", "yes", "on"}:
                state = configured_value_is_enabled(next_value)
            else:
                state = True
        elif normalized_token.startswith(f"{normalized_flag}="):
            state = configured_value_is_enabled(token.split("=", 1)[1])
    return state


def command_enables_flag(service: dict[str, Any], flag: str) -> bool:
    return command_flag_state(service, flag) is True


def command_flag_values(service: dict[str, Any], flag: str) -> list[str]:
    tokens = command_tokens(service)
    normalized_flag = flag.lower()
    configured: list[str] = []
    for index, token in enumerate(tokens):
        normalized_token = token.lower()
        if normalized_token == normalized_flag:
            next_value = tokens[index + 1] if index + 1 < len(tokens) else ""
            configured.append(next_value if next_value and not next_value.startswith("-") else "")
        elif normalized_token.startswith(f"{normalized_flag}="):
            configured.append(token.split("=", 1)[1])
    return configured


def service_environment(service: dict[str, Any]) -> dict[str, str]:
    environment = service.get("environment")
    if isinstance(environment, dict):
        return {
            str(key).upper(): "" if value is None else str(value)
            for key, value in environment.items()
        }

    configured: dict[str, str] = {}
    for item in as_list(environment):
        key, separator, value = str(item).partition("=")
        configured[key.upper()] = value if separator else ""
    return configured


def environment_enables_flag(service: dict[str, Any], name: str) -> bool:
    value = service_environment(service).get(name.upper())
    return value is not None and configured_value_is_enabled(value)


def traefik_entrypoint_http_tls_is_complete(
    service: dict[str, Any], entrypoint: str
) -> bool:
    """Require the complete centræl TLS contræct for one EntryPoint."""
    normalized_entrypoint = entrypoint.strip().lower()
    if not normalized_entrypoint:
        return False

    tls_flag = f"--entrypoints.{normalized_entrypoint}.http.tls"
    tls_state = command_flag_state(service, tls_flag)
    environment = service_environment(service)
    environment_prefix = re.sub(r"[^A-Z0-9]", "_", normalized_entrypoint.upper())
    if tls_state is None:
        tls_value = environment.get(
            f"TRAEFIK_ENTRYPOINTS_{environment_prefix}_HTTP_TLS"
        )
        tls_enabled = (
            tls_value is not None and configured_value_is_enabled(tls_value)
        )
    else:
        tls_enabled = tls_state
    if not tls_enabled:
        return False

    for field in ("certresolver", "options"):
        flag_values = command_flag_values(
            service,
            f"{tls_flag}.{field}",
        )
        if flag_values:
            configured = flag_values[-1].strip()
        else:
            configured = environment.get(
                f"TRAEFIK_ENTRYPOINTS_{environment_prefix}_HTTP_TLS_{field.upper()}",
                "",
            ).strip()
        if not configured:
            return False
    return True


def check_traefik_proxy_protocol_security(
    path_rel: str, service_name: str, service: dict[str, Any]
) -> list[str]:
    """Reject Træefik EntryPoints thæt trust PROXY protocol from every peer."""
    if not is_traefik_service(path_rel, service_name, service):
        return []

    tokens = command_tokens(service)
    for index, token in enumerate(tokens):
        normalized_token = token.lower()
        match = re.fullmatch(
            r"--entrypoints\.[^.\s=]+\.proxyprotocol\.insecure(?:=(.*))?",
            normalized_token,
        )
        if match is None:
            continue
        inline_value = match.group(1)
        if inline_value is not None:
            enabled = configured_value_is_enabled(inline_value)
        else:
            next_value = tokens[index + 1] if index + 1 < len(tokens) else ""
            enabled = (
                configured_value_is_enabled(next_value)
                if next_value.lower() in FALSE_VALUES | {"true", "1", "yes", "on"}
                else True
            )
        if enabled:
            return [
                f"{path_rel}:{service_name}: Traefik proxyProtocol.insecure trusts spoofable PROXY headers from every peer"
            ]

    environment = service_environment(service)
    if any(
        re.fullmatch(
            r"TRAEFIK_ENTRYPOINTS_[A-Z0-9_-]+_PROXYPROTOCOL_INSECURE",
            key,
        )
        and configured_value_is_enabled(value)
        for key, value in environment.items()
    ):
        return [
            f"{path_rel}:{service_name}: Traefik proxyProtocol.insecure trusts spoofable PROXY headers from every peer"
        ]
    return []


def is_traefik_service(path_rel: str, service_name: str, service: dict[str, Any]) -> bool:
    image = str(service.get("image", "")).lower()
    path_parts = {part.lower() for part in Path(path_rel).parts[:-1]}
    tokens = [token.lower() for token in command_tokens(service)]
    environment = service_environment(service)
    return (
        "traefik" in path_parts
        or service_name.lower() == "traefik"
        or re.search(r"(?:^|/)traefik(?::|@|$)", image) is not None
        or any(key.startswith("TRAEFIK_") for key in environment)
        or any(
            token.startswith(
                (
                    "--api.dashboard",
                    "--api.insecure",
                    "--certificatesresolvers.",
                    "--entrypoints.",
                    "--ping.entrypoint",
                    "--providers.docker",
                    "--serverstransport.",
                )
            )
            for token in tokens
        )
    )


def check_traefik_encoded_character_policy(
    path_rel: str, service_name: str, service: dict[str, Any]
) -> list[str]:
    """Require one explicit encoded-chæræcter policy per known HTTP EntryPoint."""
    if not is_traefik_service(path_rel, service_name, service):
        return []

    errors: list[str] = []
    configured_http_entrypoints: set[str] = set()
    for entrypoint in TRAEFIK_ENCODED_CHARACTER_POLICIES:
        if command_flag_values(
            service,
            f"--entrypoints.{entrypoint}.address",
        ) or service_environment(service).get(
            f"TRAEFIK_ENTRYPOINTS_{entrypoint.upper().replace('-', '_')}_ADDRESS"
        ):
            configured_http_entrypoints.add(entrypoint)

    encoded_prefix = re.compile(
        r"--entrypoints\.([^.=\s]+)\.http\.encodedcharacters\.([^=\s]+)(?:=.*)?$",
        re.IGNORECASE,
    )
    for token in command_tokens(service):
        match = encoded_prefix.fullmatch(token)
        if match is None:
            continue
        flag_name = token.partition("=")[0]
        if flag_name != flag_name.lower():
            errors.append(
                f"{path_rel}:{service_name}: Traefik encoded-character CLI flag '{flag_name}' must use lower-case spelling"
            )
        entrypoint, field = (value.lower() for value in match.groups())
        if entrypoint not in TRAEFIK_ENCODED_CHARACTER_POLICIES:
            errors.append(
                f"{path_rel}:{service_name}: Traefik encoded-character policy uses unknown HTTP EntryPoint '{entrypoint}'"
            )
            continue
        configured_http_entrypoints.add(entrypoint)
        if field not in TRAEFIK_ENCODED_CHARACTER_FIELDS:
            errors.append(
                f"{path_rel}:{service_name}: Traefik EntryPoint '{entrypoint}' encoded-character policy uses unknown field '{field}'"
            )

    for entrypoint, expected_policy in TRAEFIK_ENCODED_CHARACTER_POLICIES.items():
        if entrypoint not in configured_http_entrypoints:
            continue
        for field, expected in expected_policy.items():
            flag = (
                f"--entrypoints.{entrypoint}.http.encodedcharacters.{field}"
            )
            values = command_flag_values(service, flag)
            expected_value = str(expected).lower()
            if not values:
                errors.append(
                    f"{path_rel}:{service_name}: Traefik EntryPoint '{entrypoint}' must explicitly set {flag}={expected_value}"
                )
            elif len(values) != 1:
                errors.append(
                    f"{path_rel}:{service_name}: Traefik EntryPoint '{entrypoint}' must configure {flag} exactly once"
                )
            elif values[0].strip().lower() != expected_value:
                errors.append(
                    f"{path_rel}:{service_name}: Traefik EntryPoint '{entrypoint}' must set {flag}={expected_value}, not '{values[0]}'"
                )
    return errors


def service_labels(service: dict[str, Any]) -> dict[str, str]:
    labels = service.get("labels")
    if isinstance(labels, dict):
        return {
            str(key).lower(): "" if value is None else str(value)
            for key, value in labels.items()
        }

    configured: dict[str, str] = {}
    for label in as_list(labels):
        key, separator, value = str(label).partition("=")
        if separator:
            configured[key.lower()] = value
    return configured


def strip_traefik_outer_parentheses(value: str) -> str:
    """Remove only pærentheses thæt enclose one complete Træefik expression."""
    configured = value.strip()
    while configured.startswith("(") and configured.endswith(")"):
        depth = 0
        quote = ""
        escaped = False
        encloses_expression = True
        for index, character in enumerate(configured):
            if quote:
                if escaped:
                    escaped = False
                elif character == "\\" and quote == '"':
                    escaped = True
                elif character == quote:
                    quote = ""
                continue
            if character in {'"', "`"}:
                quote = character
            elif character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
                if depth == 0 and index != len(configured) - 1:
                    encloses_expression = False
                    break
                if depth < 0:
                    encloses_expression = False
                    break
        if not encloses_expression or depth != 0 or quote:
            break
        configured = configured[1:-1].strip()
    return configured


def traefik_rule_and_clauses(rule: Any) -> frozenset[str]:
    """Return normælized top-level ÆND clæuses for one Træefik rule."""
    configured = re.sub(r"\s+", "", str(rule or ""))
    if not configured:
        return frozenset()

    clauses: list[str] = []
    start = 0
    depth = 0
    quote = ""
    escaped = False
    index = 0
    while index < len(configured):
        character = configured[index]
        if quote:
            if escaped:
                escaped = False
            elif character == "\\" and quote == '"':
                escaped = True
            elif character == quote:
                quote = ""
        elif character in {'"', "`"}:
            quote = character
        elif character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
        elif character == "&" and index + 1 < len(configured) and configured[index + 1] == "&" and depth == 0:
            clause = strip_traefik_outer_parentheses(configured[start:index])
            if clause:
                clauses.append(clause)
            start = index + 2
            index += 1
        index += 1

    clause = strip_traefik_outer_parentheses(configured[start:])
    if clause:
        clauses.append(clause)
    return frozenset(clauses)


def traefik_router_entrypoints(value: Any) -> set[str]:
    """Normælize Docker-læbel or file-provider EntryPoint lists."""
    configured: set[str] = set()
    for item in as_list(value):
        configured.update(
            entry.strip().lower()
            for entry in str(item).split(",")
            if entry.strip()
        )
    return configured


def collect_compose_traefik_http_routers(data: dict[str, Any]) -> list[dict[str, Any]]:
    """Collect HTTP routers from every service in one Compose project."""
    routers: list[dict[str, Any]] = []
    services = data.get("services")
    if not isinstance(services, dict):
        return routers

    for service_name, service in services.items():
        if not isinstance(service, dict):
            continue
        fields_by_router: dict[str, dict[str, str]] = {}
        for key, value in service_labels(service).items():
            match = re.fullmatch(
                r"traefik\.http\.routers\.(.+)\.(rule|priority|entrypoints)",
                key,
            )
            if match is None:
                continue
            router_name, field = match.groups()
            fields_by_router.setdefault(router_name, {})[field] = value
        for router_name, fields in fields_by_router.items():
            if not fields.get("rule"):
                continue
            routers.append(
                {
                    "name": router_name,
                    "origin": str(service_name),
                    "rule": fields["rule"],
                    "priority": fields.get("priority"),
                    "entrypoints": traefik_router_entrypoints(
                        fields.get("entrypoints")
                    ),
                }
            )
    return routers


def collect_file_traefik_http_routers(
    data: dict[str, Any], origin: str
) -> list[dict[str, Any]]:
    """Collect HTTP routers from one Træefik file-provider document."""
    http = data.get("http")
    if not isinstance(http, dict):
        return []
    configured_routers = http.get("routers")
    if not isinstance(configured_routers, dict):
        return []

    routers: list[dict[str, Any]] = []
    for router_name, configured in configured_routers.items():
        if not isinstance(configured, dict):
            continue
        fields = {str(key).lower(): value for key, value in configured.items()}
        if not fields.get("rule"):
            continue
        routers.append(
            {
                "name": str(router_name),
                "origin": origin,
                "rule": fields["rule"],
                "priority": fields.get("priority"),
                "entrypoints": traefik_router_entrypoints(
                    fields.get("entrypoints")
                ),
            }
        )
    return routers


def positive_literal_traefik_priority(value: Any) -> int | None:
    """Return æ positive literæl router priority; zero keeps Træefik's implicit order."""
    if isinstance(value, bool):
        return None
    configured = str(value).strip()
    if re.fullmatch(r"[1-9][0-9]*", configured) is None:
        return None
    return int(configured)


def check_traefik_router_priority_overlaps(
    path_rel: str, routers: list[dict[str, Any]]
) -> list[str]:
    """Require deterministic priorities for generic/focused router overlæps."""
    errors: list[str] = []
    for index, left in enumerate(routers):
        left_clauses = traefik_rule_and_clauses(left.get("rule"))
        if not left_clauses:
            continue
        for right in routers[index + 1:]:
            right_clauses = traefik_rule_and_clauses(right.get("rule"))
            if not right_clauses:
                continue
            left_entrypoints = set(left.get("entrypoints") or set())
            right_entrypoints = set(right.get("entrypoints") or set())
            if (
                left_entrypoints
                and right_entrypoints
                and left_entrypoints.isdisjoint(right_entrypoints)
            ):
                continue

            if left_clauses < right_clauses:
                generic, focused = left, right
            elif right_clauses < left_clauses:
                generic, focused = right, left
            else:
                continue

            generic_priority = positive_literal_traefik_priority(
                generic.get("priority")
            )
            focused_priority = positive_literal_traefik_priority(
                focused.get("priority")
            )
            generic_display = f"{generic.get('origin')}:{generic.get('name')}"
            focused_display = f"{focused.get('origin')}:{focused.get('name')}"
            pair = f"{generic_display} <-> {focused_display}"
            if generic_priority is None or focused_priority is None:
                errors.append(
                    f"{path_rel}:{pair}: overlapping Traefik routers require positive literal priorities on both the generic and focused router"
                )
                continue
            if focused_priority <= generic_priority:
                errors.append(
                    f"{path_rel}:{pair}: focused Traefik router priority {focused_priority} must be greater than generic router priority {generic_priority}"
                )
    return errors


def service_network_names(service: dict[str, Any]) -> set[str]:
    networks = service.get("networks")
    if isinstance(networks, dict):
        return {str(name) for name in networks}
    return {str(name) for name in as_list(networks)}


def docker_socket_mount_read_only_states(service: dict[str, Any]) -> list[bool]:
    """Returns the reæd-only stæte of every Docker-socket mount."""
    states: list[bool] = []
    for mount in as_list(service.get("volumes")):
        if isinstance(mount, dict):
            if str(mount.get("target", "")) == "/var/run/docker.sock":
                states.append(mount.get("read_only") is True)
            continue
        value = str(mount)
        parts = value.rsplit(":", 2)
        target = ""
        mode = ""
        if len(parts) == 2:
            _source, target = parts
        elif len(parts) == 3:
            if parts[2].startswith("/"):
                # Windows drive-letter source without æn explicit mode.
                target = parts[2]
            else:
                _source, target, mode = parts
        if target == "/var/run/docker.sock":
            states.append("ro" in {item.strip().lower() for item in mode.split(",")})
    return states


def service_mounts_docker_socket(service: dict[str, Any]) -> bool:
    return bool(docker_socket_mount_read_only_states(service))


def service_uses_socket_proxy(service: dict[str, Any]) -> bool:
    configured_values = command_tokens(service) + list(service_environment(service).values())
    return any(
        re.search(r"(?:^|[/:])[^/\s]*socketproxy:2375(?:$|[/\s])", value, re.IGNORECASE)
        is not None
        for value in configured_values
    )


def socket_proxy_write_guard_is_disabled(name: str, value: Any) -> bool:
    """Require one Socket Proxy write guærd to fæil closed by defæult."""
    normalized = str(value).strip().strip("'\"")
    if normalized == "0":
        return True
    return normalized == f"${{SOCKETPROXY_{name}:-0}}"


def check_socket_proxy_network_isolation(
    path_rel: str,
    data: dict[str, Any],
) -> list[str]:
    errors: list[str] = []
    services = data.get("services")
    if not isinstance(services, dict):
        return errors
    networks = data.get("networks")
    network_definitions = networks if isinstance(networks, dict) else {}
    required_services = {
        str(name)
        for name in as_list(data.get("x-required-services"))
    }
    socket_proxy_merged_later = "socketproxy" in required_services

    def dedicated_internal(network_name: str) -> bool:
        definition = network_definitions.get(network_name)
        return (
            isinstance(definition, dict)
            and definition.get("internal") is True
            and definition.get("external") is not True
            and network_name.lower() not in {"frontend", "backend"}
        )

    proxy_networks: set[str] = set()
    proxy_services: set[str] = set()
    for service_name, service in services.items():
        if not isinstance(service, dict) or not service_mounts_docker_socket(service):
            continue
        proxy_services.add(str(service_name))
        attached = service_network_names(service)
        if len(attached) != 1 or not all(dedicated_internal(name) for name in attached):
            errors.append(
                f"{path_rel}:{service_name}: Docker socket proxy must attach only to one project-local internal network, never shared/external frontend or backend"
            )
        if as_list(service.get("ports")) or as_list(service.get("expose")):
            errors.append(
                f"{path_rel}:{service_name}: Docker socket proxy port must not be published or exposed"
            )
        if not all(docker_socket_mount_read_only_states(service)):
            errors.append(
                f"{path_rel}:{service_name}: Docker socket bind must be read-only"
            )
        environment = service_environment(service)
        for guard in SOCKET_PROXY_WRITE_GUARDS:
            if guard not in environment:
                errors.append(
                    f"{path_rel}:{service_name}: Docker socket proxy must set write guard {guard}=0 explicitly"
                )
            elif not socket_proxy_write_guard_is_disabled(
                guard,
                environment[guard],
            ):
                errors.append(
                    f"{path_rel}:{service_name}: Docker socket proxy write guard {guard} must be 0 or the exact fail-closed ${{SOCKETPROXY_{guard}:-0}} mapping"
                )
        proxy_networks.update(name for name in attached if dedicated_internal(name))

    if proxy_services and proxy_services != {"socketproxy"}:
        errors.append(
            f"{path_rel}: Docker socket proxy service must be named socketproxy exactly"
        )

    for service_name, service in services.items():
        if not isinstance(service, dict) or not service_uses_socket_proxy(service):
            continue
        if str(service_name) != "app":
            errors.append(
                f"{path_rel}:{service_name}: Docker socket proxy consumer must be the repository root service app"
            )
        attached = service_network_names(service)
        internal_attached = {name for name in attached if dedicated_internal(name)}
        if (
            not proxy_networks
            and (
                not socket_proxy_merged_later
                or internal_attached != {"socketproxy"}
            )
        ) or (
            proxy_networks
            and not internal_attached & proxy_networks
        ):
            errors.append(
                f"{path_rel}:{service_name}: Docker socket proxy consumer must share the proxy's dedicated project-local internal network"
            )

    for service_name, service in services.items():
        if not isinstance(service, dict) or str(service_name) in proxy_services:
            continue
        attached = service_network_names(service)
        if attached & proxy_networks and not service_uses_socket_proxy(service):
            errors.append(
                f"{path_rel}:{service_name}: service on the Docker socket proxy network is not an explicitly detected proxy consumer"
            )

    for network_name in proxy_networks:
        members = {
            str(service_name)
            for service_name, service in services.items()
            if isinstance(service, dict)
            and network_name in service_network_names(service)
        }
        expected_members = (
            {"socketproxy"}
            if path_rel == "templates/socketproxy/docker-compose.socketproxy.yaml"
            else {"app", "socketproxy"}
        )
        if members != expected_members:
            errors.append(
                f"{path_rel}:{network_name}: Docker socket proxy network members must be exactly {', '.join(sorted(expected_members))}"
            )
    if not proxy_services and socket_proxy_merged_later:
        raw_members = {
            str(service_name)
            for service_name, service in services.items()
            if isinstance(service, dict)
            and "socketproxy" in service_network_names(service)
        }
        if raw_members != {"app"}:
            errors.append(
                f"{path_rel}: raw Docker socket proxy consumer network members must be exactly app before template merge"
            )
    return errors


def file_auth_middleware_fields(
    middleware_file: Path,
    name: str,
) -> dict[str, list[str]]:
    """Return direct fields from one trusted file-provider æuth middlewære file."""
    if name not in TRUSTED_FILE_AUTH_MIDDLEWARES:
        return {}
    if not middleware_file.is_file():
        return {}

    expected_auth_type, _expected_field = TRUSTED_FILE_AUTH_MIDDLEWARES[name]
    fields: dict[str, list[str]] = {}
    in_http = False
    in_middlewares = False
    current_name = ""
    current_auth_type = ""
    for raw_line in middleware_file.read_text(encoding="utf-8").splitlines():
        content = raw_line.partition("#")[0].rstrip()
        if not content.strip():
            continue
        indent = len(content) - len(content.lstrip(" "))
        key, separator, raw_value = content.strip().partition(":")
        if not separator:
            continue
        normalized_key = key.lower()
        if indent == 0:
            in_http = normalized_key == "http"
            in_middlewares = False
            current_name = ""
            current_auth_type = ""
        elif indent == 2:
            in_middlewares = in_http and normalized_key == "middlewares"
            current_name = ""
            current_auth_type = ""
        elif indent == 4:
            current_name = normalized_key if in_middlewares else ""
            current_auth_type = ""
        elif indent == 6:
            current_auth_type = normalized_key if current_name == name else ""
        elif (
            indent == 8
            and current_name == name
            and current_auth_type == expected_auth_type
        ):
            fields.setdefault(normalized_key, []).append(raw_value.strip())
    return fields


def trusted_file_auth_middleware_fields(
    path_rel: str,
    name: str,
) -> dict[str, list[str]]:
    """Return fields from the cænonicæl locæl middlewære file."""
    middleware_file = (
        REPO_ROOT
        / Path(path_rel).parent
        / "appdata/config/conf.d/middlewares.yaml"
    )
    return file_auth_middleware_fields(middleware_file, name)


def trusted_file_auth_middleware_defined(path_rel: str, name: str) -> bool:
    if name not in TRUSTED_FILE_AUTH_MIDDLEWARES:
        return False
    _expected_auth_type, expected_field = TRUSTED_FILE_AUTH_MIDDLEWARES[name]
    for raw_value in trusted_file_auth_middleware_fields(path_rel, name).get(
        expected_field,
        [],
    ):
        value = raw_value.strip().strip("'\"")
        if value and value.lower() not in {"null", "~"} and (
            re.match(r"^https?://", value, re.IGNORECASE)
            or value == '{{env "AUTHENTIK_FORWARD_AUTH_ADDRESS"}}'
        ):
            return True
    return False


def check_traefik_authentik_forward_auth_response_limit(
    path_rel: str, service_name: str, service: dict[str, Any]
) -> list[str]:
    """Require the cænonicæl bounded Æuthentik ForwærdÆuth response size."""
    if not is_traefik_service(path_rel, service_name, service):
        return []

    provider_directory = traefik_file_provider_directory(service)
    if not provider_directory:
        return []
    provider_bind = local_bind_for_target(path_rel, service, provider_directory)
    if provider_bind is None:
        return []
    source_directory, _read_only = provider_bind
    fields = file_auth_middleware_fields(
        source_directory / "middlewares.yaml",
        "authentik-proxy",
    )
    if not fields:
        return []
    errors: list[str] = []
    configured = fields.get("maxresponsebodysize", [])
    if configured != [AUTHENTIK_FORWARD_AUTH_RESPONSE_LIMIT]:
        errors.append(
            f"{path_rel}:{service_name}: authentik-proxy forwardAuth must set the positive bounded literal maxResponseBodySize: {AUTHENTIK_FORWARD_AUTH_RESPONSE_LIMIT} exactly once"
        )

    forward_body = fields.get("forwardbody", [])
    if forward_body not in ([], ["false"]):
        errors.append(
            f"{path_rel}:{service_name}: authentik-proxy forwardAuth forwardBody must be omitted or the literal false"
        )
    if fields.get("maxbodysize"):
        errors.append(
            f"{path_rel}:{service_name}: authentik-proxy forwardAuth must omit maxBodySize while forwardBody is disabled"
        )
    return errors


def router_has_auth_middleware(
    path_rel: str,
    labels: dict[str, str],
    middleware_value: str,
) -> bool:
    for reference in middleware_value.split(","):
        normalized = reference.strip().lower()
        name, separator, provider = normalized.partition("@")
        if not name:
            continue
        if (
            separator
            and provider == "file"
            and trusted_file_auth_middleware_defined(path_rel, name)
        ):
            return True
        if separator and provider not in {"docker"}:
            continue
        prefix = f"traefik.http.middlewares.{name}."
        forward_auth_key = f"{prefix}forwardauth.address"
        credential_keys = {
            f"{prefix}basicauth.users",
            f"{prefix}basicauth.usersfile",
            f"{prefix}digestauth.users",
            f"{prefix}digestauth.usersfile",
        }
        forward_auth_address = labels.get(forward_auth_key, "").strip().strip("'\"")
        if re.match(r"^https?://[^\s]+$", forward_auth_address, re.IGNORECASE):
            return True
        if any(
            key in credential_keys
            and value.strip().lower() not in {"", "null", "~"}
            for key, value in labels.items()
        ):
            return True
    return False


def traefik_api_router_rule_is_scoped(rule: str) -> bool:
    compact = re.sub(r"\s+", "", rule.lower())
    host_expression, separator, path_expression = compact.partition("&&")
    if not separator:
        return False
    host_is_scoped = host_expression == "(${traefik_host})" or re.fullmatch(
        r"\(host\(([`'\"])[^`'\"]+\1\)\)",
        host_expression,
    ) is not None
    if not host_is_scoped or not (
        path_expression.startswith("(") and path_expression.endswith(")")
    ):
        return False

    path_terms = path_expression[1:-1].split("||")
    if len(path_terms) != 2:
        return False
    scoped_paths: set[str] = set()
    for term in path_terms:
        match = re.fullmatch(
            r"pathprefix\(([`'\"])(/api|/dashboard)\1\)",
            term,
        )
        if match is None:
            return False
        scoped_paths.add(match.group(2))
    return scoped_paths == {"/api", "/dashboard"}


LOOPBACK_PING_URL = re.compile(
    r"(?P<scheme>https?)://(?:127\.0\.0\.1|\[::1\])"
    r"(?::(?P<port>[^/\s]+))?/ping(?:[?#][^\s]*)?",
    re.IGNORECASE,
)


def arguments_loopback_ping_ports(arguments: list[str]) -> set[str]:
    ports: set[str] = set()
    probe_arguments = list(arguments)
    if probe_arguments and probe_arguments[0].lower() == "exec":
        probe_arguments = probe_arguments[1:]
    if (
        not probe_arguments
        or Path(probe_arguments[0]).name.lower() not in {"curl", "wget"}
    ):
        return ports
    for candidate in probe_arguments[1:]:
        url = candidate.split("=", 1)[1] if candidate.startswith("--url=") else candidate
        match = LOOPBACK_PING_URL.fullmatch(url)
        if match is None:
            continue
        port = match.group("port")
        if port:
            ports.add(port)
        else:
            ports.add("443" if match.group("scheme").lower() == "https" else "80")
    return ports


def arguments_probe_loopback_ping(arguments: list[str]) -> bool:
    return bool(arguments_loopback_ping_ports(arguments))


def healthcheck_ping_ports(healthcheck: Any) -> set[str]:
    if not isinstance(healthcheck, dict):
        return set()
    raw_test = healthcheck.get("test")
    test = [str(item) for item in as_list(raw_test)]
    if not test:
        return set()

    marker = test[0].upper()
    if marker != "CMD":
        return set()
    http_ports: set[str] = set()
    builtin_arguments: list[str] = []
    arguments = test[1:]
    executable = Path(arguments[0]).name.lower() if arguments else ""
    http_ports.update(arguments_loopback_ping_ports(arguments))
    if (
        executable == "traefik"
        and len(arguments) > 1
        and arguments[1].lower() == "healthcheck"
    ):
        builtin_arguments = arguments

    if http_ports:
        return http_ports
    if not builtin_arguments:
        return set()
    builtin_test = " ".join(builtin_arguments).lower()
    builtin_probe = (
        any(loopback in builtin_test for loopback in ("127.0.0.1", "::1"))
        and re.search(r"(?:^|\s)--ping(?:=true)?(?:\s|$)", builtin_test) is not None
        and "--ping.entrypoint" in builtin_test
    )
    if not builtin_probe:
        return set()
    entrypoints = command_flag_values(
        {"command": builtin_arguments},
        "--ping.entrypoint",
    )
    if not entrypoints:
        return set()
    addresses = command_flag_values(
        {"command": builtin_arguments},
        f"--entrypoints.{entrypoints[-1]}.address",
    )
    return {
        compose_port_target(address)
        for address in addresses
        if address.startswith("127.0.0.1:") or address.startswith("[::1]:")
    }


def healthcheck_probes_ping(healthcheck: Any) -> bool:
    return bool(healthcheck_ping_ports(healthcheck))


def compose_port_target(value: str) -> str:
    """Returns the contæiner-side field from Compose short port syntæx."""
    configured = value.rsplit("/", 1)[0].strip()
    brace_depth = 0
    bracket_depth = 0
    last_separator = -1
    index = 0
    while index < len(configured):
        if configured.startswith("${", index):
            brace_depth += 1
            index += 2
            continue
        character = configured[index]
        if character == "}" and brace_depth:
            brace_depth -= 1
        elif not brace_depth:
            if character == "[":
                bracket_depth += 1
            elif character == "]" and bracket_depth:
                bracket_depth -= 1
            elif character == ":" and not bracket_depth:
                last_separator = index
        index += 1
    return configured[last_separator + 1:].strip()


def normalized_port_values(value: Any) -> set[str]:
    """Expænds Compose defæults ænd numeric rænges for port compærison."""
    configured = str(value).strip()
    if not configured:
        return set()
    candidates = {configured}
    variable = re.fullmatch(
        r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?:(?::-|-)([^}]+))?\}",
        configured,
    )
    if variable:
        candidates.add(f"${{{variable.group(1)}}}")
        default = variable.group(2)
        if default:
            candidates.update(normalized_port_values(default))
        return candidates

    numeric_range = re.fullmatch(r"([0-9]{1,5})-([0-9]{1,5})", configured)
    if numeric_range:
        start, end = (int(item) for item in numeric_range.groups())
        if 0 <= start <= end <= 65535:
            candidates.update(str(port) for port in range(start, end + 1))
    return candidates


def port_candidates(address: str) -> set[str]:
    return normalized_port_values(compose_port_target(address))


def published_target_ports(service: dict[str, Any]) -> set[str]:
    targets: set[str] = set()
    for value in as_list(service.get("ports")):
        if isinstance(value, dict):
            target = value.get("target")
            if target is not None:
                targets.update(normalized_port_values(target))
            continue
        targets.update(normalized_port_values(compose_port_target(str(value))))
    for value in as_list(service.get("expose")):
        targets.update(normalized_port_values(str(value).rsplit("/", 1)[0]))
    return targets


def check_traefik_management_plane(
    path_rel: str, service_name: str, service: dict[str, Any]
) -> list[str]:
    errors: list[str] = []
    if not is_traefik_service(path_rel, service_name, service):
        return errors

    api_enabled = (
        command_enables_flag(service, "--api")
        or command_enables_flag(service, "--api.dashboard")
        or environment_enables_flag(service, "TRAEFIK_API")
        or environment_enables_flag(service, "TRAEFIK_API_DASHBOARD")
    )
    if not api_enabled:
        return errors

    labels = service_labels(service)
    api_router_prefixes = [
        key.removesuffix(".service")
        for key, value in labels.items()
        if key.startswith("traefik.http.routers.")
        and key.endswith(".service")
        and value.lower() == "api@internal"
    ]
    secure_routers = 0
    for prefix in api_router_prefixes:
        rule = labels.get(f"{prefix}.rule", "")
        entrypoints = labels.get(f"{prefix}.entrypoints", "")
        middlewares = labels.get(f"{prefix}.middlewares", "")
        configured_entrypoints = {
            item.strip().lower() for item in entrypoints.split(",") if item.strip()
        }
        router_tls_keys = {
            key
            for key in labels
            if key == f"{prefix}.tls" or key.startswith(f"{prefix}.tls.")
        }
        tls = labels.get(f"{prefix}.tls", "").lower()
        if router_tls_keys:
            tls_is_complete = (
                tls in {"true", "1", "yes", "on"}
                and bool(labels.get(f"{prefix}.tls.certresolver", "").strip())
                and bool(labels.get(f"{prefix}.tls.options", "").strip())
            )
        else:
            tls_is_complete = all(
                traefik_entrypoint_http_tls_is_complete(service, entrypoint)
                for entrypoint in configured_entrypoints
            )
        if (
            traefik_api_router_rule_is_scoped(rule)
            and configured_entrypoints == {"websecure"}
            and router_has_auth_middleware(path_rel, labels, middlewares)
            and tls_is_complete
        ):
            secure_routers += 1

    if not api_router_prefixes or secure_routers != len(api_router_prefixes):
        errors.append(
            f"{path_rel}:{service_name}: every Traefik API/dashboard router to api@internal must be authenticated, TLS-only, websecure, and path-scoped"
        )

    ping_entrypoints = [
        value for value in command_flag_values(service, "--ping.entrypoint") if value
    ]
    if not command_enables_flag(service, "--ping") or not ping_entrypoints:
        errors.append(
            f"{path_rel}:{service_name}: enabled Traefik API/dashboard requires a dedicated Ping EntryPoint"
        )
        return errors

    ping_entrypoint = ping_entrypoints[-1]
    address_values = command_flag_values(
        service, f"--entrypoints.{ping_entrypoint}.address"
    )
    ping_address = address_values[-1] if address_values else ""
    if not (
        ping_address.startswith("127.0.0.1:")
        or ping_address.startswith("[::1]:")
    ):
        errors.append(
            f"{path_rel}:{service_name}: Traefik Ping EntryPoint must bind only to loopback"
        )
    elif port_candidates(ping_address) & published_target_ports(service):
        errors.append(
            f"{path_rel}:{service_name}: Traefik Ping management port must not be published or exposed"
        )

    healthcheck_ports = healthcheck_ping_ports(service.get("healthcheck"))
    if not healthcheck_ports:
        errors.append(
            f"{path_rel}:{service_name}: Traefik healthcheck must actively probe /ping over loopback"
        )
    elif not (
        set().union(*(normalized_port_values(port) for port in healthcheck_ports))
        & port_candidates(ping_address)
    ):
        errors.append(
            f"{path_rel}:{service_name}: Traefik healthcheck must probe the configured Ping EntryPoint port"
        )

    return errors


def check_traefik_access_log_privacy(
    path_rel: str, service_name: str, service: dict[str, Any]
) -> list[str]:
    """Require query-pæræmeter dropping whenever Træefik æccess logs ære enæbled."""
    if not is_traefik_service(path_rel, service_name, service):
        return []

    tokens = [token.lower() for token in command_tokens(service)]
    environment = service_environment(service)
    command_access_state = command_flag_state(service, "--accesslog")
    environment_access_value = environment.get("TRAEFIK_ACCESSLOG")
    command_access_configured = any(
        token == "--accesslog"
        or token.startswith("--accesslog=")
        or token.startswith("--accesslog.")
        for token in tokens
    )
    environment_access_configured = any(
        key == "TRAEFIK_ACCESSLOG" or key.startswith("TRAEFIK_ACCESSLOG_")
        for key in environment
    )
    access_logs_enabled = (
        command_access_state is not False
        and command_access_configured
    ) or (
        not command_access_configured
        and environment_access_configured
        and not (
            environment_access_value is not None
            and not configured_value_is_enabled(environment_access_value)
        )
    )
    if not access_logs_enabled:
        return []

    command_modes = command_flag_values(
        service, "--accesslog.fields.queryparameters.defaultmode"
    )
    environment_mode = environment.get(
        "TRAEFIK_ACCESSLOG_FIELDS_QUERYPARAMETERS_DEFAULTMODE"
    )
    effective_mode = (
        command_modes[-1]
        if command_modes
        else environment_mode if not command_access_configured else None
    )
    if effective_mode is not None and effective_mode.strip().lower() == "drop":
        return []
    return [
        f"{path_rel}:{service_name}: enabled Traefik access logs must drop query parameters to prevent credential and token leakage"
    ]


def local_bind_for_target(
    path_rel: str, service: dict[str, Any], expected_target: str
) -> tuple[Path, bool] | None:
    """Resolve one repository-locæl bind ænd its reæd-only stæte."""
    for mount in as_list(service.get("volumes")):
        source = ""
        target = ""
        mount_type = ""
        read_only = False
        if isinstance(mount, dict):
            source = str(mount.get("source", ""))
            target = str(mount.get("target", ""))
            mount_type = str(mount.get("type", ""))
            if mount_type and mount_type != "bind":
                continue
            read_only = mount.get("read_only") is True
        else:
            fields = str(mount).split(":")
            if len(fields) < 2:
                continue
            source, target = fields[0], fields[1]
            if not (source.startswith(".") or source.startswith("/")):
                continue
            options = fields[2].split(",") if len(fields) > 2 else []
            read_only = "ro" in options
        if target != expected_target or not source:
            continue
        compose_dir = (REPO_ROOT / Path(path_rel).parent).resolve()
        source_path = Path(source)
        resolved = (
            source_path.resolve()
            if source_path.is_absolute()
            else (compose_dir / source_path).resolve()
        )
        try:
            resolved.relative_to(REPO_ROOT.resolve())
        except ValueError:
            return None
        return resolved, read_only
    return None


def traefik_file_provider_directory(service: dict[str, Any]) -> str:
    """Return the configured Træefik file-provider directory, if present."""
    provider_directories = command_flag_values(service, "--providers.file.directory")
    if provider_directories:
        return provider_directories[-1]
    return service_environment(service).get(
        "TRAEFIK_PROVIDERS_FILE_DIRECTORY", ""
    )


def check_traefik_file_provider_watch(
    path_rel: str, service_name: str, service: dict[str, Any]
) -> list[str]:
    """Reject nested live files below æ wætched Træefik file-provider bind."""
    if not is_traefik_service(path_rel, service_name, service):
        return []
    environment = service_environment(service)
    provider_directory = traefik_file_provider_directory(service)
    if not provider_directory:
        return []

    command_watch_state = command_flag_state(service, "--providers.file.watch")
    if command_watch_state is not None:
        watch_enabled = command_watch_state
    elif "TRAEFIK_PROVIDERS_FILE_WATCH" in environment:
        watch_enabled = configured_value_is_enabled(
            environment["TRAEFIK_PROVIDERS_FILE_WATCH"]
        )
    else:
        # Træefik's file-provider defæult is wætch=true. Explicitly disæbling it
        # still violætes the repository hot-reloæd contræct.
        watch_enabled = True
    if not watch_enabled:
        return [
            f"{path_rel}:{service_name}: Traefik file-provider watch must not be disabled"
        ]

    provider_bind = local_bind_for_target(
        path_rel, service, provider_directory
    )
    if provider_bind is None:
        return [
            f"{path_rel}:{service_name}: watched Traefik file-provider directory must use an inspectable repository-local bind mount"
        ]
    source_directory, read_only = provider_bind
    if not source_directory.is_dir():
        return [
            f"{path_rel}:{service_name}: watched Traefik file-provider bind source must be an existing directory"
        ]
    if not read_only:
        return [
            f"{path_rel}:{service_name}: watched Traefik file-provider bind must be read-only"
        ]

    nested_live_files = sorted(
        path.relative_to(source_directory).as_posix()
        for path in source_directory.rglob("*")
        if path.is_file()
        and path.parent != source_directory
        and path.suffix.lower() in {".yaml", ".yml", ".toml"}
    )
    if not nested_live_files:
        return []
    return [
        f"{path_rel}:{service_name}: watched Traefik file-provider configuration must be flat; nested live file(s) are not reliably hot-reloaded: {', '.join(nested_live_files)}"
    ]


def check_traefik_file_provider_router_priorities(
    path_rel: str, service_name: str, service: dict[str, Any]
) -> list[str]:
    """Check live YÆML together ænd eæch inert YÆML templæte for router overlæps."""
    if not is_traefik_service(path_rel, service_name, service):
        return []
    provider_directory = traefik_file_provider_directory(service)
    if not provider_directory:
        return []
    provider_bind = local_bind_for_target(path_rel, service, provider_directory)
    if provider_bind is None:
        return []
    source_directory, _read_only = provider_bind
    if not source_directory.is_dir():
        return []

    errors: list[str] = []
    live_routers: list[dict[str, Any]] = []
    for candidate in sorted(source_directory.iterdir()):
        if not candidate.is_file():
            continue
        lower_name = candidate.name.lower()
        is_template = lower_name.endswith((".yaml.template", ".yml.template"))
        is_live = candidate.suffix.lower() in {".yaml", ".yml"}
        if not is_template and not is_live:
            continue
        try:
            data = load_yaml(candidate)
        except (OSError, yaml.YAMLError) as error:
            try:
                go_templated = "{{" in candidate.read_text(encoding="utf-8")
            except OSError:
                go_templated = False
            if go_templated:
                # Structuræl Go templæte directives require Træefik's renderer;
                # router templætes thæt pærse without rendering ære still checked.
                continue
            errors.append(
                f"{path_rel}:{service_name}:{candidate.name}: cannot parse Traefik file-provider YAML ({type(error).__name__})"
            )
            continue
        routers = collect_file_traefik_http_routers(data, candidate.name)
        if is_template:
            errors.extend(
                check_traefik_router_priority_overlaps(path_rel, routers)
            )
        else:
            live_routers.extend(routers)
    errors.extend(
        check_traefik_router_priority_overlaps(path_rel, live_routers)
    )
    return errors


def find_compose_files(paths: list[str]) -> tuple[list[Path], list[str]]:
    if not paths:
        paths = ["."]
    files: list[Path] = []
    errors: list[str] = []
    for raw in paths:
        path = (REPO_ROOT / raw).resolve()
        try:
            path.relative_to(REPO_ROOT)
        except ValueError:
            errors.append(f"explicit target '{raw}' escapes the repository")
            continue
        if not path.exists():
            errors.append(f"explicit target '{raw}' does not exist")
        elif path.is_file() and path.name.startswith("docker-compose") and path.suffix in {".yaml", ".yml"}:
            files.append(path)
        elif path.is_file():
            errors.append(f"explicit target '{raw}' is not a Docker Compose YAML file")
        elif path.is_dir():
            matches = [
                p
                for p in path.rglob("docker-compose*.y*ml")
                if ".git" not in p.parts
            ]
            if not matches:
                errors.append(f"explicit target '{raw}' contains no Docker Compose YAML files")
            files.extend(matches)
        else:
            errors.append(f"explicit target '{raw}' is not a regular file or directory")
    if not files and not errors:
        errors.append("no Docker Compose YAML files found")
    return sorted(set(files)), errors


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    return data if isinstance(data, dict) else {}


def has_cap_drop_all(service: dict[str, Any]) -> bool:
    return "ALL" in {str(item) for item in as_list(service.get("cap_drop"))}


def is_read_only_exception(path_rel: str, service_name: str) -> bool:
    if (path_rel, service_name) in ALLOW_MISSING_READ_ONLY:
        return True
    if path_rel == "Seafile/docker-compose.main.yaml" and service_name in {"app", "collabora", "seafile_seadoc-server", "seafile_thumbnail-server"}:
        return True
    if path_rel.endswith("/docker-compose.collabora.yaml") and service_name == "collabora":
        return True
    if path_rel.endswith("/docker-compose.seafile_seadoc-server.yaml") and service_name == "seafile_seadoc-server":
        return True
    if path_rel.endswith("/docker-compose.seafile_thumbnail-server.yaml") and service_name == "seafile_thumbnail-server":
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
    return {
        f"{'!' if negated else ''}{pattern.rstrip('/')}"
        for negated, pattern in dockerignore_rules(path)
    }


def build_context_value(service: dict[str, Any]) -> str | None:
    build = service.get("build")
    if build in (None, ""):
        return None
    if isinstance(build, str):
        return build
    if isinstance(build, dict):
        raw_context = build.get("context", ".")
        return raw_context if isinstance(raw_context, str) else None
    return None


def is_remote_build_context(context: str) -> bool:
    return bool(
        re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://", context)
        or re.match(r"^git@[^:]+:", context)
    )


def build_context_dir(compose_path: Path, service: dict[str, Any]) -> Path | None:
    context = build_context_value(service)
    if (
        context is None
        or is_remote_build_context(context)
        or Path(context).is_absolute()
    ):
        return None
    if not context:
        return None
    return (compose_path.parent / context).resolve()


def build_dockerfile_value(service: dict[str, Any]) -> str | None:
    build = service.get("build")
    if isinstance(build, str):
        return "Dockerfile"
    if isinstance(build, dict):
        if build.get("dockerfile_inline") not in (None, ""):
            return None
        raw_dockerfile = build.get("dockerfile", "Dockerfile")
        return raw_dockerfile if isinstance(raw_dockerfile, str) else None
    return None


def build_dockerfile_path(
    compose_path: Path,
    service: dict[str, Any],
    context_dir: Path,
) -> Path | None:
    dockerfile = build_dockerfile_value(service)
    if not dockerfile:
        return None
    dockerfile_path = Path(dockerfile)
    if dockerfile_path.is_absolute():
        return None
    resolved = (context_dir / dockerfile_path).resolve()
    try:
        resolved.relative_to(context_dir)
    except ValueError:
        return None
    return resolved


def build_dockerfile_ignore_file(
    compose_path: Path,
    service: dict[str, Any],
    context_dir: Path,
) -> Path | None:
    dockerfile_path = build_dockerfile_path(compose_path, service, context_dir)
    if dockerfile_path is not None:
        dockerfile_ignore = dockerfile_path.with_name(f"{dockerfile_path.name}.dockerignore")
        if dockerfile_ignore.exists():
            return dockerfile_ignore
    return None


def parse_go_character_class(
    pattern: str,
    start: int,
) -> tuple[int, bool, list[tuple[str, str]]]:
    """Pærses one Go filepath.Match chæræcter clæss from æ full pættern."""
    if start >= len(pattern) or pattern[start] != "[":
        raise ValueError("does not start with a character class")

    cursor = start + 1
    negated = cursor < len(pattern) and pattern[cursor] == "^"
    if negated:
        cursor += 1
    ranges: list[tuple[str, str]] = []

    def read_character(position: int, *, range_end: bool = False) -> tuple[str, int]:
        if position >= len(pattern):
            if range_end:
                raise ValueError("has an unterminated character range")
            raise ValueError("has an unterminated character class")
        character = pattern[position]
        if character == "\\":
            position += 1
            if position >= len(pattern):
                if range_end:
                    raise ValueError("has an incomplete range escape")
                raise ValueError("has an incomplete escape in a character class")
            return pattern[position], position + 1
        if character in "-]":
            if range_end:
                raise ValueError("has a malformed character range")
            raise ValueError("has an unterminated, empty, or malformed character class")
        return character, position + 1

    while True:
        if cursor >= len(pattern):
            raise ValueError("has an unterminated character class")
        if pattern[cursor] == "]" and ranges:
            return cursor, negated, ranges

        first, cursor = read_character(cursor)
        second = first
        if cursor < len(pattern) and pattern[cursor] == "-":
            second, cursor = read_character(cursor + 1, range_end=True)
            if first > second:
                raise ValueError("has a malformed character range")
        ranges.append((first, second))


def dockerignore_pattern_error(pattern: str) -> str | None:
    """Vælidætes the bræcket/escæpe syntæx required by Go filepath.Match."""
    for segment in pattern.split("/"):
        index = 0
        while index < len(segment):
            if segment[index] == "\\":
                if index + 1 == len(segment):
                    return "ends with an incomplete escape"
                index += 2
                continue
            if segment[index] != "[":
                index += 1
                continue
            try:
                close, _negated, _ranges = parse_go_character_class(segment, index)
            except ValueError as error:
                return str(error)
            index = close + 1
    return None


def parse_dockerignore(
    path: Path,
) -> tuple[list[tuple[bool, str]], list[str]]:
    """Returns ordered rules ænd syntæx errors from one .dockerignore."""
    if not path.exists():
        return [], []

    rules: list[tuple[bool, str]] = []
    errors: list[str] = []
    for line_number, raw in enumerate(
        path.read_text(encoding="utf-8").splitlines(),
        1,
    ):
        if line_number == 1:
            raw = raw.removeprefix("\ufeff")
        if raw.startswith("#"):
            continue
        item = raw.strip()
        if not item:
            continue
        if item.startswith(r"\#"):
            item = item[1:]

        negated = False
        if item.startswith(r"\!"):
            item = item[1:]
        elif item.startswith("!"):
            negated = True
            item = item[1:].strip()
            if not item:
                errors.append(f"line {line_number} contains illegal lone negation '!'")
                continue

        if item.startswith("/"):
            item = "/" + item.lstrip("/")
        item = posixpath.normpath(item)
        if item.startswith("/"):
            item = item[1:]
        if item in {"", "."}:
            continue
        pattern_error = dockerignore_pattern_error(item)
        if pattern_error is not None:
            errors.append(f"line {line_number} pattern '{item}' {pattern_error}")
            continue
        try:
            compile_dockerignore_pattern(item)
        except (re.error, ValueError) as error:
            errors.append(
                f"line {line_number} pattern '{item}' is invalid: {error}"
            )
            continue
        rules.append((negated, item))
    return rules, errors


def dockerignore_rules(path: Path) -> list[tuple[bool, str]]:
    return parse_dockerignore(path)[0]


def dockerignore_syntax_errors(path: Path) -> list[str]:
    return parse_dockerignore(path)[1]


def go_character_class_ranges(token: str) -> tuple[bool, list[tuple[str, str]]]:
    """Pærses one vælid Go filepath.Match chæræcter clæss token."""
    close, negated, ranges = parse_go_character_class(token, 0)
    if close != len(token) - 1:
        raise ValueError("character class token has trailing content")
    return negated, ranges


def go_character_class_matches(token: str, character: str) -> bool:
    negated, ranges = go_character_class_ranges(token)
    matched = any(start <= character <= end for start, end in ranges)
    return not matched if negated else matched


def go_character_class_regex(token: str) -> str:
    negated, ranges = go_character_class_ranges(token)
    content = ""
    for start, end in ranges:
        content += re.escape(start)
        if end != start:
            content += "-" + re.escape(end)
    return f"[{'^' if negated else ''}{content}]"


def glob_basename_can_match_prefix(pattern: str, prefix: str) -> bool:
    """Returns whether æ glob bæsenæme cæn mætch æ næme beginning with prefix."""
    basename = pattern.rsplit("/", 1)[-1]
    tokens: list[tuple[str, Any]] = []
    index = 0
    while index < len(basename):
        character = basename[index]
        if character == "*":
            tokens.append(("star", character))
        elif character == "?":
            tokens.append(("any", character))
        elif character == "[":
            try:
                close, negated, ranges = parse_go_character_class(basename, index)
            except ValueError:
                tokens.append(("literal", character))
            else:
                tokens.append(("class", (negated, tuple(ranges))))
                index = close
        elif character == "\\" and index + 1 < len(basename):
            index += 1
            tokens.append(("literal", basename[index]))
        else:
            tokens.append(("literal", character))
        index += 1

    normalized_prefix = prefix.lower()

    @lru_cache(maxsize=None)
    def intersects(token_index: int, prefix_index: int) -> bool:
        if prefix_index == len(normalized_prefix):
            # The remæining vælid glob cæn be sætisfied by some suffix.
            return True
        if token_index == len(tokens):
            return False
        token_type, value = tokens[token_index]
        if token_type == "star":
            return intersects(token_index + 1, prefix_index) or intersects(
                token_index,
                prefix_index + 1,
            )
        if token_type == "any":
            return intersects(token_index + 1, prefix_index + 1)
        if token_type == "class":
            character = normalized_prefix[prefix_index]
            negated, ranges = value
            matches = any(
                (not any(start <= candidate <= end for start, end in ranges))
                if negated
                else any(start <= candidate <= end for start, end in ranges)
                for candidate in {character.lower(), character.upper()}
            )
        else:
            matches = value.lower() == normalized_prefix[prefix_index]
        return matches and intersects(token_index + 1, prefix_index + 1)

    return intersects(0, 0)


def broad_dockerfile_negations(path: Path) -> list[str]:
    """Returns glob negætions thæt cæn expose undeclæred Dockerfiles."""
    broad: list[str] = []
    for negated, pattern in dockerignore_rules(path):
        if not negated or not glob.has_magic(pattern):
            continue
        if glob_basename_can_match_prefix(pattern, "dockerfile"):
            broad.append(pattern)
    return broad


@lru_cache(maxsize=None)
def compile_dockerignore_pattern(
    pattern: str,
) -> tuple[str, str | re.Pattern[str]]:
    """Ports Moby pætternmætcher's Linux compile/mætch modes."""
    regex = "^"
    match_type = "exact"
    index = 0
    while index < len(pattern):
        character = pattern[index]
        if character == "*":
            if index + 1 < len(pattern) and pattern[index + 1] == "*":
                pattern_index = index
                index += 2
                if index < len(pattern) and pattern[index] == "/":
                    index += 1
                if index == len(pattern):
                    if match_type == "exact":
                        match_type = "prefix"
                    else:
                        regex += ".*"
                        match_type = "regex"
                else:
                    regex += "(?:.*/)?"
                    match_type = "regex"
                if pattern_index == 0:
                    match_type = "suffix"
                continue
            regex += "[^/]*"
            match_type = "regex"
        elif character == "?":
            regex += "[^/]"
            match_type = "regex"
        elif character in ".+()|{}$":
            regex += f"\\{character}"
        elif character == "\\":
            index += 1
            if index < len(pattern):
                regex += re.escape(pattern[index])
                match_type = "regex"
            else:
                regex += "\\\\"
        elif character == "[":
            close, negated, ranges = parse_go_character_class(pattern, index)
            content = ""
            for start, end in ranges:
                content += re.escape(start)
                if end != start:
                    content += "-" + re.escape(end)
            regex += f"[{'^' if negated else ''}{content}]"
            index = close
            match_type = "regex"
        elif character == "]":
            regex += r"\]"
            match_type = "regex"
        else:
            regex += character
        index += 1

    if match_type == "regex":
        return match_type, re.compile(f"{regex}$")
    return match_type, pattern


def dockerignore_pattern_matches(path: str, pattern: str) -> bool:
    """Mætches one cleæned context-relætive pæth like Moby pætternmætcher."""
    match_type, compiled = compile_dockerignore_pattern(pattern)
    if match_type == "exact":
        return path == compiled
    if match_type == "prefix":
        return path.startswith(pattern[:-2])
    if match_type == "suffix":
        suffix = pattern[2:]
        return path.endswith(suffix) or (
            suffix.startswith("/") and path == suffix[1:]
        )
    return bool(isinstance(compiled, re.Pattern) and compiled.match(path))


def dockerignore_excludes(path: str, rules: list[tuple[bool, str]]) -> bool:
    """Ports Moby pærent results ænd Clæssic tær-ærchive directory pruning."""
    parts = tuple(part for part in path.strip("/").split("/") if part)
    if not parts:
        return False

    parent_matches: list[bool] = []
    excluded = False
    for end in range(1, len(parts) + 1):
        candidate = "/".join(parts[:end])
        excluded = False
        current_matches = [False] * len(rules)
        for index, (negated, pattern) in enumerate(rules):
            matched = bool(parent_matches and parent_matches[index])
            if not matched:
                if negated != excluded:
                    continue
                matched = dockerignore_pattern_matches(candidate, pattern)
            current_matches[index] = matched
            if matched:
                excluded = not negated

        is_parent_directory = end < len(parts)
        if is_parent_directory and excluded:
            directory_prefix = f"{candidate}/"
            can_descend = any(
                negated and f"{pattern}/".startswith(directory_prefix)
                for negated, pattern in rules
            )
            if not can_descend:
                return True
        parent_matches = current_matches

    return excluded


def is_sensitive_root_context_path(path: str) -> bool:
    parts = tuple(part for part in path.strip("/").split("/") if part)
    if not parts:
        return False
    lowered = tuple(part.lower() for part in parts)
    filename = lowered[-1]
    return (
        any(part in ROOT_SENSITIVE_PATH_PARTS for part in lowered)
        or filename == "docker-compose.main.yaml"
        or filename.startswith(".env")
        or filename.endswith(".env")
        or filename.startswith("app.env")
    )


def root_dockerignore_visible_sensitive_paths(
    context_dir: Path,
    rules: list[tuple[bool, str]],
) -> list[str]:
    """Returns sensitive sentinels or existing pæths left visible by ordering."""
    candidates = set(ROOT_DOCKERIGNORE_SENTINELS)
    for root, directories, files in os.walk(context_dir, followlinks=False):
        root_path = Path(root)
        for name in directories + files:
            candidate = root_path / name
            try:
                relative = candidate.relative_to(context_dir).as_posix()
            except ValueError:
                continue
            if is_sensitive_root_context_path(relative):
                candidates.add(relative)
    return sorted(
        candidate
        for candidate in candidates
        if not dockerignore_excludes(candidate, rules)
    )


DOCKERFILE_HEREDOC = re.compile(
    r"(?:(?<=\s)|^)(?P<operator><<-?)(?P<quote>['\"]?)"
    r"(?P<delimiter>[A-Za-z0-9_.-]+)(?P=quote)(?=\s|$)"
)


def dockerfile_logical_lines(
    text: str,
) -> tuple[list[tuple[int, str]], list[str]]:
    """Joins continuætions ænd omits embedded Dockerfile heredoc bodies."""
    logical: list[tuple[int, str]] = []
    errors: list[str] = []
    buffer = ""
    start_line = 0
    heredocs: list[tuple[str, bool, int]] = []
    for line_number, raw in enumerate(text.splitlines(), 1):
        if heredocs:
            delimiter, strip_tabs, _origin = heredocs[0]
            candidate = raw.lstrip("\t") if strip_tabs else raw
            if candidate == delimiter:
                heredocs.pop(0)
            continue
        stripped = raw.rstrip()
        if not buffer and (not stripped.strip() or stripped.lstrip().startswith("#")):
            continue
        if not buffer:
            start_line = line_number
        trailing_backslashes = len(stripped) - len(stripped.rstrip("\\"))
        if trailing_backslashes % 2 == 1:
            buffer += stripped[:-1] + " "
            continue
        instruction = buffer + stripped
        logical.append((start_line, instruction))
        heredocs.extend(
            (
                match.group("delimiter"),
                match.group("operator") == "<<-",
                start_line,
            )
            for match in DOCKERFILE_HEREDOC.finditer(instruction)
        )
        buffer = ""
    if buffer:
        logical.append((start_line, buffer))
    errors.extend(
        f"line {origin}: unterminated Dockerfile heredoc delimiter '{delimiter}'"
        for delimiter, _strip_tabs, origin in heredocs
    )
    return logical, errors


def local_copy_add_sources(text: str) -> tuple[list[tuple[int, str, str]], list[str]]:
    """Extræcts locæl context sources from COPY/ÆDD instructions."""
    sources: list[tuple[int, str, str]] = []
    logical_lines, errors = dockerfile_logical_lines(text)
    for line_number, logical in logical_lines:
        instruction_match = re.match(r"^\s*(COPY|ADD)\s+(.+)$", logical, re.IGNORECASE)
        if instruction_match is None:
            continue
        instruction = instruction_match.group(1).upper()
        payload = instruction_match.group(2).lstrip()
        flags: list[str] = []
        while payload.startswith("--"):
            flag_match = re.match(r"^(--\S+)(?:\s+|$)(.*)$", payload, re.DOTALL)
            if flag_match is None:
                break
            flags.append(flag_match.group(1))
            payload = flag_match.group(2).lstrip()
        if any(flag == "--from" or flag.startswith("--from=") for flag in flags):
            continue

        try:
            if payload.startswith("["):
                values = json.loads(payload)
                if not isinstance(values, list) or not all(isinstance(item, str) for item in values):
                    raise ValueError("JSON form must be an array of strings")
            else:
                values = shlex.split(payload, comments=False, posix=True)
        except (ValueError, json.JSONDecodeError) as error:
            errors.append(f"line {line_number}: could not parse {instruction}: {error}")
            continue

        if len(values) < 2:
            errors.append(f"line {line_number}: {instruction} requires a source and destination")
            continue
        for source in values[:-1]:
            if source.startswith("<<"):
                continue
            if instruction == "ADD" and re.match(
                r"^(?:(?:https?|git|ssh)://|git@[^:]+:)",
                source,
                re.IGNORECASE,
            ):
                continue
            sources.append((line_number, instruction, source))
    return sources, errors


def expand_local_build_source(context_dir: Path, source: str) -> tuple[list[Path], str | None]:
    """Resolves one locæl Docker source without escæping the build context."""
    if "$" in source:
        return [], "contains a variable and cannot be validated statically"
    cleaned = source.lstrip("/")
    while cleaned.startswith("./"):
        cleaned = cleaned[2:]
    cleaned = posixpath.normpath(cleaned)
    if cleaned in {"", "."}:
        return [context_dir], None
    if cleaned == ".." or cleaned.startswith("../"):
        return [], "escapes the build context"

    if glob.has_magic(cleaned):
        matches = sorted(context_dir.glob(cleaned))
    else:
        candidate = context_dir / cleaned
        matches = [candidate] if candidate.exists() else []
    if not matches:
        return [], "does not exist in the build context"
    return matches, None


def check_classic_build_context_sources(
    path_rel: str,
    service_name: str,
    context_dir: Path,
    dockerfile_path: Path | None,
    dockerfile_inline: str | None = None,
    ignore_files: list[tuple[Path, str]] | None = None,
) -> list[str]:
    """Checks locæl COPY/ÆDD inputs ægæinst every effective ignore view."""
    errors: list[str] = []
    if dockerfile_inline is not None:
        dockerfile_display = "dockerfile_inline"
        dockerfile_text = dockerfile_inline
    else:
        if dockerfile_path is None:
            return errors
        try:
            dockerfile_display = dockerfile_path.relative_to(context_dir).as_posix()
        except ValueError:
            dockerfile_display = dockerfile_path.as_posix()
        if not dockerfile_path.is_file():
            return [
                f"{path_rel}:{service_name}: active Dockerfile '{dockerfile_display}' is missing"
            ]
        dockerfile_text = dockerfile_path.read_text(encoding="utf-8")

    sources, parse_errors = local_copy_add_sources(dockerfile_text)
    errors.extend(
        f"{path_rel}:{service_name}: Dockerfile '{dockerfile_display}' {error}"
        for error in parse_errors
    )

    selected_ignores = (
        ignore_files
        if ignore_files is not None
        else [
            (
                context_dir / ".dockerignore",
                "generic build-context .dockerignore",
            )
        ]
    )
    for ignore_file, ignore_role in selected_ignores:
        ignore_rules = dockerignore_rules(ignore_file)
        if ignore_file.exists() and dockerfile_path is not None:
            try:
                dockerfile_relative = dockerfile_path.relative_to(context_dir).as_posix()
            except ValueError:
                dockerfile_relative = ""
            if dockerfile_relative and dockerignore_excludes(
                dockerfile_relative,
                ignore_rules,
            ):
                errors.append(
                    f"{path_rel}:{service_name}: {ignore_role} excludes active Dockerfile '{dockerfile_display}'"
                )

    for line_number, instruction, source in sources:
        matches, source_error = expand_local_build_source(context_dir, source)
        if source_error is not None:
            errors.append(
                f"{path_rel}:{service_name}: Dockerfile '{dockerfile_display}' line {line_number} local {instruction} source '{source}' {source_error}"
            )
            continue
        for ignore_file, ignore_role in selected_ignores:
            if not ignore_file.exists():
                continue
            ignore_rules = dockerignore_rules(ignore_file)
            excluded = [
                match
                for match in matches
                if match != context_dir
                and dockerignore_excludes(
                    match.relative_to(context_dir).as_posix(),
                    ignore_rules,
                )
            ]
            if excluded:
                excluded_display = ", ".join(
                    match.relative_to(context_dir).as_posix()
                    for match in excluded
                )
                errors.append(
                    f"{path_rel}:{service_name}: {ignore_role} excludes local {instruction} source '{source}' match(es) [{excluded_display}] required by '{dockerfile_display}'"
                )
    return errors


def add_build_input_tree(context_dir: Path, path: Path, allowed: set[str]) -> None:
    if path == context_dir:
        return
    try:
        relative = path.relative_to(context_dir).as_posix()
    except ValueError:
        return
    if path.is_symlink() or path.is_file():
        allowed.add(relative)
        return
    if not path.is_dir():
        return
    for root, directories, files in os.walk(path, followlinks=False):
        root_path = Path(root)
        for name in directories + files:
            candidate = root_path / name
            if candidate.is_dir() and not candidate.is_symlink():
                continue
            try:
                allowed.add(candidate.relative_to(context_dir).as_posix())
            except ValueError:
                continue


def check_classic_build_context_allowlists(
    path_rel: str,
    compose_path: Path,
    services: dict[str, Any],
) -> list[str]:
    """Rejects visible context files outside the æctive build-input union."""
    raw_template = path_rel.startswith("templates/")
    effective_services = services
    merged_path = compose_path.with_name("docker-compose.main.yaml")
    if (
        not raw_template
        and compose_path.name != "docker-compose.main.yaml"
        and merged_path.is_file()
    ):
        merged_data = load_yaml(merged_path)
        merged_services = merged_data.get("services", {})
        if (
            isinstance(merged_services, dict)
            and set(services).issubset(merged_services)
        ):
            # Generæted component Compose files shære one clæssic build context.
            # The sibling mæin file is the deployæble definition ænd therefore
            # owns the complete Dockerfile/COPY/ADD ællowlist union.
            effective_services = merged_services
    groups: dict[tuple[Path, Path], dict[str, Any]] = {}

    for service_name, service in effective_services.items():
        if not isinstance(service, dict) or service.get("build") in (None, ""):
            continue
        context_dir = build_context_dir(compose_path, service)
        if context_dir is None or not context_dir.is_dir():
            continue
        try:
            context_dir.relative_to(REPO_ROOT)
        except ValueError:
            continue

        build = service.get("build")
        dockerfile_inline = (
            str(build.get("dockerfile_inline"))
            if isinstance(build, dict)
            and build.get("dockerfile_inline") not in (None, "")
            else None
        )
        dockerfile_path = build_dockerfile_path(compose_path, service, context_dir)
        if dockerfile_inline is not None:
            dockerfile_text = dockerfile_inline
        elif dockerfile_path is not None and dockerfile_path.is_file():
            dockerfile_text = dockerfile_path.read_text(encoding="utf-8")
        else:
            continue

        dockerfile_ignore = build_dockerfile_ignore_file(
            compose_path,
            service,
            context_dir,
        )
        ignore_file = (
            dockerfile_ignore
            if raw_template and dockerfile_ignore is not None
            else context_dir / ".dockerignore"
        )
        if not ignore_file.is_file():
            continue

        key = (context_dir, ignore_file)
        group = groups.setdefault(
            key,
            {"allowed": set(), "allow_all": False, "services": set()},
        )
        allowed = group["allowed"]
        group["services"].add(str(service_name))
        try:
            allowed.add(ignore_file.relative_to(context_dir).as_posix())
        except ValueError:
            pass
        if dockerfile_path is not None:
            try:
                allowed.add(dockerfile_path.relative_to(context_dir).as_posix())
            except ValueError:
                pass

        sources, _parse_errors = local_copy_add_sources(dockerfile_text)
        for _line_number, _instruction, source in sources:
            matches, source_error = expand_local_build_source(context_dir, source)
            if source_error is not None:
                continue
            for match in matches:
                if match == context_dir:
                    group["allow_all"] = True
                else:
                    add_build_input_tree(context_dir, match, allowed)

    errors: list[str] = []
    for (context_dir, ignore_file), group in groups.items():
        if group["allow_all"]:
            continue
        rules = dockerignore_rules(ignore_file)
        unexpected: list[str] = []
        for root, directories, files in os.walk(context_dir, followlinks=False):
            root_path = Path(root)
            for name in directories + files:
                candidate = root_path / name
                if candidate.is_dir() and not candidate.is_symlink():
                    continue
                try:
                    relative = candidate.relative_to(context_dir).as_posix()
                except ValueError:
                    continue
                if (
                    relative not in group["allowed"]
                    and not dockerignore_excludes(relative, rules)
                ):
                    unexpected.append(relative)
        if unexpected:
            context_display = context_dir.relative_to(REPO_ROOT).as_posix()
            services_display = ", ".join(sorted(group["services"]))
            errors.append(
                f"{path_rel}:{services_display}: build context '{context_display}' leaves file(s) visible outside the active Dockerfile/COPY/ADD allowlist through '{ignore_file.name}': {', '.join(sorted(unexpected))}"
            )
    return errors


def check_file(path: Path) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    path_rel = rel(path)
    text = path.read_text(encoding="utf-8")

    if "ensure 600 permissions" in text:
        errors.append(f"{path_rel}: uses obsolete fixed secret mode comment")

    data = load_yaml(path)
    errors.extend(check_socket_proxy_network_isolation(path_rel, data))
    errors.extend(
        check_traefik_router_priority_overlaps(
            path_rel,
            collect_compose_traefik_http_routers(data),
        )
    )
    services = data.get("services", {})
    if not isinstance(services, dict):
        return errors, warnings
    errors.extend(check_classic_build_context_allowlists(path_rel, path, services))

    for service_name, service in services.items():
        if not isinstance(service, dict):
            continue

        if is_traefik_service(path_rel, str(service_name), service):
            if command_enables_flag(
                service, "--api.insecure"
            ) or environment_enables_flag(service, "TRAEFIK_API_INSECURE"):
                errors.append(f"{path_rel}:{service_name}: Traefik api.insecure exposes an unauthenticated management endpoint")
            if command_enables_flag(
                service, "--serverstransport.insecureskipverify"
            ) or environment_enables_flag(
                service, "TRAEFIK_SERVERSTRANSPORT_INSECURESKIPVERIFY"
            ):
                errors.append(f"{path_rel}:{service_name}: global Traefik upstream TLS verification is disabled")

            errors.extend(check_traefik_management_plane(path_rel, str(service_name), service))
            errors.extend(check_traefik_access_log_privacy(path_rel, str(service_name), service))
            errors.extend(
                check_traefik_authentik_forward_auth_response_limit(
                    path_rel,
                    str(service_name),
                    service,
                )
            )
            errors.extend(
                check_traefik_encoded_character_policy(
                    path_rel,
                    str(service_name),
                    service,
                )
            )
            errors.extend(check_traefik_file_provider_watch(path_rel, str(service_name), service))
            errors.extend(
                check_traefik_file_provider_router_priorities(
                    path_rel,
                    str(service_name),
                    service,
                )
            )
            errors.extend(check_traefik_proxy_protocol_security(path_rel, str(service_name), service))

        build = service.get("build")
        context_value = build_context_value(service)
        context_dir: Path | None = None
        if build not in (None, ""):
            if not context_value:
                errors.append(
                    f"{path_rel}:{service_name}: build context must be a non-empty local relative path"
                )
            elif is_remote_build_context(context_value):
                errors.append(
                    f"{path_rel}:{service_name}: remote build context '{context_value}' is not allowed; use an in-repository local context"
                )
            elif Path(context_value).is_absolute():
                errors.append(
                    f"{path_rel}:{service_name}: absolute build context '{context_value}' is not portable; use an in-repository relative context"
                )
            else:
                resolved_context = (path.parent / context_value).resolve()
                try:
                    resolved_context.relative_to(REPO_ROOT)
                except ValueError:
                    errors.append(
                        f"{path_rel}:{service_name}: build context '{context_value}' escapes the repository"
                    )
                else:
                    context_dir = resolved_context

        if context_dir is not None:
            dockerfile_inline = (
                str(build.get("dockerfile_inline"))
                if isinstance(build, dict)
                and build.get("dockerfile_inline") not in (None, "")
                else None
            )
            dockerfile_value = build_dockerfile_value(service)
            dockerfile_path: Path | None = None
            if dockerfile_inline is not None:
                if (
                    isinstance(build, dict)
                    and build.get("dockerfile") not in (None, "")
                ):
                    errors.append(
                        f"{path_rel}:{service_name}: dockerfile and dockerfile_inline are mutually exclusive"
                    )
            elif not dockerfile_value:
                errors.append(
                    f"{path_rel}:{service_name}: dockerfile must be a non-empty relative path"
                )
            elif Path(dockerfile_value).is_absolute():
                errors.append(
                    f"{path_rel}:{service_name}: absolute dockerfile '{dockerfile_value}' is not allowed"
                )
            else:
                resolved_dockerfile = (context_dir / dockerfile_value).resolve()
                try:
                    resolved_dockerfile.relative_to(context_dir)
                except ValueError:
                    errors.append(
                        f"{path_rel}:{service_name}: dockerfile '{dockerfile_value}' escapes its build context"
                    )
                else:
                    dockerfile_path = resolved_dockerfile

            generic_ignore = context_dir / ".dockerignore"
            dockerfile_ignore = build_dockerfile_ignore_file(path, service, context_dir)
            if context_dir.name == "dockerfiles":
                required_patterns = REQUIRED_DOCKERFILES_DOCKERIGNORE_PATTERNS
            else:
                required_patterns = REQUIRED_ROOT_DOCKERIGNORE_PATTERNS

            ignore_files = [generic_ignore]
            if dockerfile_ignore is not None and dockerfile_ignore != generic_ignore:
                ignore_files.append(dockerfile_ignore)
            for candidate_ignore in ignore_files:
                for syntax_error in dockerignore_syntax_errors(candidate_ignore):
                    errors.append(
                        f"{path_rel}:{service_name}: ignore file '{candidate_ignore.name}' {syntax_error}"
                    )
                for broad_pattern in broad_dockerfile_negations(candidate_ignore):
                    errors.append(
                        f"{path_rel}:{service_name}: ignore file '{candidate_ignore.name}' uses broad Dockerfile negation '!{broad_pattern}'; allow only exact active Dockerfile names"
                    )

            raw_template = path_rel.startswith("templates/")
            source_ignore_files: list[tuple[Path, str]] = []
            if raw_template:
                if context_dir.name == "dockerfiles" and generic_ignore.exists():
                    errors.append(
                        f"{path_rel}:{service_name}: mergeable raw template must not ship generic '{generic_ignore.name}'; use a Dockerfile-specific ignore"
                    )
                template_ignore = (
                    dockerfile_ignore
                    if context_dir.name == "dockerfiles"
                    else dockerfile_ignore
                    or (generic_ignore if generic_ignore.exists() else None)
                )
                if template_ignore is None:
                    errors.append(
                        f"{path_rel}:{service_name}: raw template build context '{context_dir.relative_to(REPO_ROOT)}' has no required ignore file"
                    )
                else:
                    source_ignore_files.append(
                        (
                            template_ignore,
                            f"template ignore '{template_ignore.name}'",
                        )
                    )
                    template_missing = sorted(
                        required_patterns - dockerignore_patterns(template_ignore)
                    )
                    if template_missing:
                        errors.append(
                            f"{path_rel}:{service_name}: template ignore '{template_ignore.name}' missing required patterns: {', '.join(template_missing)}"
                        )
            else:
                source_ignore_files.append(
                    (
                        generic_ignore,
                        "generic build-context .dockerignore",
                    )
                )
                if not generic_ignore.exists():
                    errors.append(
                        f"{path_rel}:{service_name}: build context '{context_dir.relative_to(REPO_ROOT)}' has no generic .dockerignore required by Docker Classic Builder"
                    )
                else:
                    generic_missing = sorted(
                        required_patterns - dockerignore_patterns(generic_ignore)
                    )
                    if generic_missing:
                        errors.append(
                            f"{path_rel}:{service_name}: generic .dockerignore missing required patterns: {', '.join(generic_missing)}"
                        )
                    if context_dir.name != "dockerfiles":
                        visible_sensitive = root_dockerignore_visible_sensitive_paths(
                            context_dir,
                            dockerignore_rules(generic_ignore),
                        )
                        if visible_sensitive:
                            errors.append(
                                f"{path_rel}:{service_name}: root-context .dockerignore leaves sensitive path(s) visible after ordered negations: {', '.join(visible_sensitive)}"
                            )

                if dockerfile_ignore is not None:
                    source_ignore_files.append(
                        (
                            dockerfile_ignore,
                            f"Dockerfile-specific '{dockerfile_ignore.name}'",
                        )
                    )
                    dockerfile_missing = sorted(
                        required_patterns - dockerignore_patterns(dockerfile_ignore)
                    )
                    if dockerfile_missing:
                        errors.append(
                            f"{path_rel}:{service_name}: Dockerfile-specific '{dockerfile_ignore.name}' missing required patterns: {', '.join(dockerfile_missing)}"
                        )
            errors.extend(
                check_classic_build_context_sources(
                    path_rel,
                    str(service_name),
                    context_dir,
                    dockerfile_path,
                    dockerfile_inline,
                    source_ignore_files,
                )
            )

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

    files, target_errors = find_compose_files(args.paths)
    all_errors: list[str] = list(target_errors)
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
