#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Docker-free ædversæriæl checks for strict recovery contæiner closure."""

from __future__ import annotations

import re
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


@dataclass(frozen=True)
class Contract:
    readme: str
    sentinel: str
    services: tuple[str, ...]
    finite_services: tuple[str, ...] = ()


CONTRACTS = (
    Contract(
        "Traefik/README.md",
        'CLEAN_COMPOSE=(env -i PATH="$PATH" docker compose',
        ("app", "crowdsec_agent", "socketproxy", "traefik_certs-dumper"),
    ),
    Contract(
        "Authentik/README.md",
        'CLEAN_CONFIG_YAML="$("${CLEAN_COMPOSE[@]}" config)"',
        (
            "app",
            "authentik-bootstrap",
            "authentik-worker",
            "postgresql",
            "postgresql_maintenance",
        ),
        ("authentik-bootstrap",),
    ),
    Contract(
        "Grafana/README.md",
        'clean_backup_compose_base=(env -i PATH="$PATH" docker compose',
        (
            "app",
            "grafana-bootstrap",
            "grafana-migrator",
            "grafana-sso-policy",
            "postgresql",
            "postgresql_maintenance",
        ),
        ("grafana-bootstrap", "grafana-migrator", "grafana-sso-policy"),
    ),
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def fenced_bash_blocks(text: str) -> list[str]:
    return [match.group(1) + "\n" for match in re.finditer(
        r"(?ms)^```bash\n(.*?)^```[ \t]*$", text
    )]


def selected_block(contract: Contract) -> str:
    text = (REPO_ROOT / contract.readme).read_text(encoding="utf-8")
    matches = [block for block in fenced_bash_blocks(text)
               if contract.sentinel in block]
    require(len(matches) == 1,
            f"{contract.readme}: expected one strict recovery block")
    return matches[0]


def bash_syntax(block: str, name: str) -> None:
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".bash") as stream:
        stream.write(block)
        stream.flush()
        result = subprocess.run(
            ["bash", "-n", stream.name],
            check=False,
            capture_output=True,
            text=True,
        )
    require(result.returncode == 0,
            f"{name}: Bash syntax failed: {result.stderr.strip()}")


def static_contract(contract: Contract, block: str) -> int:
    expected_literal = "\\n".join(sorted(contract.services))
    checks = {
        "clean Compose render": 'env -i PATH="$PATH" docker compose' in block,
        "clean/runtime render parity": (
            "CONFIG_YAML" in block or "compose.runtime.json" in block
            or 'cmp -s <("${clean_backup_compose_base[@]}" config)' in block
        ),
        "exact service literal": expected_literal in block,
        "per-service direct label inventory": (
            'containers_output="$(docker ps -aq' in block
            and '--filter "label=com.docker.compose.project=' in block
            and '--filter "label=com.docker.compose.service=$service"' in block
        ),
        "actual image config hash": (
            'container_image_ref="$(docker inspect' in block
            and 'com.docker.compose.config-hash' in block
            and 'config --hash "$service"' in block
        ),
        "whole-project direct inventory": (
            'project_containers_output="$(docker ps -aq' in block
            and (
                'test "${#project_containers[@]}" -eq "${#services[@]}"' in block
                or '[[ "${#project_containers[@]}" -eq "${#services[@]}" ]]'
                in block
            )
        ),
        "orphan service rejection": (
            'seen_services[$container_service]' in block
            and 'service_containers[$container_service]' in block
        ),
    }
    for description, passed in checks.items():
        require(passed, f"{contract.readme}: missing {description}")
    for service in contract.finite_services:
        require(service in block, f"{contract.readme}: missing finite service {service}")
    if contract.finite_services:
        require(".State.ExitCode" in block and "false:0" in block,
                f"{contract.readme}: finite jobs are not required to exit zero")
    stop_token = {
        "Traefik/README.md": '"${COMPOSE[@]}" stop',
        "Authentik/README.md": '"${COMPOSE[@]}" stop app authentik-worker',
        "Grafana/README.md": '"${backup_compose[@]}" stop app',
    }[contract.readme]
    stop_index = block.find(stop_token)
    require(stop_index >= 0, f"{contract.readme}: writer stop is missing")
    require(block.find('config --hash "$service"') < stop_index,
            f"{contract.readme}: config hash follows writer mutation")
    require(block.find('project_containers_output="$(docker ps -aq') < stop_index,
            f"{contract.readme}: project closure follows writer mutation")
    return len(checks) + len(contract.finite_services) + 3


def accept_inventory(
    expected: tuple[str, ...],
    containers: tuple[tuple[str, str, bool, int, bool], ...],
    finite: tuple[str, ...],
) -> bool:
    """Model the fæil-closed inværiænts embedded in æll three runbooks."""

    if len(containers) != len(expected):
        return False
    by_service: dict[str, tuple[str, str, bool, int, bool]] = {}
    for row in containers:
        container_id, service, running, exit_code, config_hash_matches = row
        if not container_id or service not in expected or service in by_service:
            return False
        if not config_hash_matches:
            return False
        if service in finite:
            if running or exit_code != 0:
                return False
        elif not running:
            return False
        by_service[service] = row
    return set(by_service) == set(expected)


def adversarial_model(contract: Contract) -> int:
    expected = contract.services
    finite = contract.finite_services
    valid = tuple(
        (f"id-{service}", service, service not in finite, 0, True)
        for service in expected
    )
    require(accept_inventory(expected, valid, finite),
            f"{contract.readme}: valid fixture rejected")
    fixtures = (
        valid[:-1],
        valid + (("id-orphan", "removed-writer", True, 0, True),),
        valid[:-1] + (("id-duplicate", expected[0], True, 0, True),),
        (("",) + valid[0][1:],) + valid[1:],
        (valid[0][:-1] + (False,),) + valid[1:],
    )
    if finite:
        index = expected.index(finite[0])
        running_finite = list(valid)
        running_finite[index] = (
            running_finite[index][0], finite[0], True, 0, True
        )
        failed_finite = list(valid)
        failed_finite[index] = (
            failed_finite[index][0], finite[0], False, 1, True
        )
        fixtures += (tuple(running_finite), tuple(failed_finite))
    for fixture in fixtures:
        require(not accept_inventory(expected, fixture, finite),
                f"{contract.readme}: hostile inventory accepted")
    return 1 + len(fixtures)


def main() -> int:
    checks = 0
    for contract in CONTRACTS:
        block = selected_block(contract)
        bash_syntax(block, contract.readme)
        checks += 1
        checks += static_contract(contract, block)
        checks += adversarial_model(contract)
    print(f"PASS: strict recovery container closure ({checks} checks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
