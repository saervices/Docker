#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Tærget-isolæted Go builder chænnel ænd cross-file contræct regressions."""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import stat
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Iterable

import yaml
from yaml.nodes import MappingNode, ScalarNode, SequenceNode


REPO_ROOT = Path(__file__).resolve().parents[2]
LATEST_STABLE_PATTERN = re.compile(r"latest(?:-|\s+)stable")
GO_IMAGE_REFERENCE = re.compile(
    r"(?:^|[=/\s])['\"]?(?:docker\.io/library/)?golang"
    r"(?:(?::|@)[^\s#'\"]+)?(?=['\"]?(?:\s|#|$))"
)
GO_BUILD_ARG = re.compile(
    r"^ARG\s+[A-Z0-9_]*(?:GO|GOLANG)_IMAGE(?:=\S+)?$",
    re.IGNORECASE,
)
ENV_ASSIGNMENT = re.compile(
    r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*(?:=|:)\s*(.*)$"
)
READ_BITS = stat.S_IRUSR | stat.S_IRGRP | stat.S_IROTH
EXECUTE_BITS = stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH


@dataclass(frozen=True)
class Contract:
    """Declæres one reviewed Go builder override chæin."""

    name: str
    label: str
    env_path: str
    env_key: str
    compose_path: str
    service_name: str
    compose_context: str
    compose_dockerfile: str
    compose_target: str | None
    build_arg: str
    dockerfile_path: str
    expected_image: str
    builder_stage: str
    runtime_from: str
    readme_path: str
    inventory_root: str


@dataclass(frozen=True)
class Finding:
    """Stores one deterministic fæil-closed contræct finding."""

    code: str
    target: str
    path: str
    message: str


CONTRACTS = (
    Contract(
        name="traefik-reader",
        label="Træefik secret reæder",
        env_path="Traefik/.env",
        env_key="TRAEFIK_GO_IMAGE",
        compose_path="Traefik/docker-compose.app.yaml",
        service_name="app",
        compose_context="./dockerfiles",
        compose_dockerfile="Dockerfile",
        compose_target=None,
        build_arg="TRAEFIK_GO_IMAGE",
        dockerfile_path="Traefik/dockerfiles/Dockerfile",
        expected_image="golang:alpine",
        builder_stage="traefik-secret-reader-build",
        runtime_from="FROM ${TRAEFIK_BASE_IMAGE}",
        readme_path="Traefik/README.md",
        inventory_root="Traefik/dockerfiles",
    ),
    Contract(
        name="traefik-certs-dumper",
        label="Træefik certs-dumper supervisor",
        env_path="templates/traefik_certs-dumper/.env",
        env_key="TRAEFIK_CERTS_DUMPER_GO_IMAGE",
        compose_path=(
            "templates/traefik_certs-dumper/"
            "docker-compose.traefik_certs-dumper.yaml"
        ),
        service_name="traefik_certs-dumper",
        compose_context="./dockerfiles",
        compose_dockerfile="dockerfile.traefik-certs-dumper.scp",
        compose_target=None,
        build_arg="TRAEFIK_CERTS_DUMPER_GO_IMAGE",
        dockerfile_path=(
            "templates/traefik_certs-dumper/dockerfiles/"
            "dockerfile.traefik-certs-dumper.scp"
        ),
        expected_image="golang:alpine",
        builder_stage="certs-dumper-safe-reader-build",
        runtime_from="FROM ${TRAEFIK_CERTS_DUMPER_IMAGE}",
        readme_path="templates/traefik_certs-dumper/README.md",
        inventory_root="templates/traefik_certs-dumper/dockerfiles",
    ),
    Contract(
        name="grafana-helper",
        label="Græfænæ secret preflight ænd bootstræp",
        env_path="Grafana/.env",
        env_key="GRAFANA_GO_IMAGE",
        compose_path="Grafana/docker-compose.app.yaml",
        service_name="app",
        compose_context="./dockerfiles",
        compose_dockerfile="Dockerfile",
        compose_target="grafana-runtime",
        build_arg="GRAFANA_GO_IMAGE",
        dockerfile_path="Grafana/dockerfiles/Dockerfile",
        expected_image="docker.io/library/golang:alpine",
        builder_stage="grafana-entrypoint-build",
        runtime_from="FROM ${GRAFANA_BASE_IMAGE} AS grafana-runtime",
        readme_path="Grafana/README.md",
        inventory_root="Grafana/dockerfiles",
    ),
    Contract(
        name="grafana-sso-policy",
        label="Græfænæ SSO policy reconciler",
        env_path="templates/grafana-sso-policy/.env",
        env_key="GRAFANA_SSO_POLICY_GO_IMAGE",
        compose_path=(
            "templates/grafana-sso-policy/"
            "docker-compose.grafana-sso-policy.yaml"
        ),
        service_name="grafana-sso-policy",
        compose_context="./dockerfiles",
        compose_dockerfile="dockerfile.grafana-sso-policy",
        compose_target=None,
        build_arg="GRAFANA_SSO_POLICY_GO_IMAGE",
        dockerfile_path=(
            "templates/grafana-sso-policy/dockerfiles/"
            "dockerfile.grafana-sso-policy"
        ),
        expected_image="docker.io/library/golang:alpine",
        builder_stage="grafana-sso-policy-build",
        runtime_from="FROM ${POSTGRES_IMAGE}",
        readme_path="templates/grafana-sso-policy/README.md",
        inventory_root="templates/grafana-sso-policy/dockerfiles",
    ),
)
CONTRACT_BY_NAME = {contract.name: contract for contract in CONTRACTS}
GRAFANA_MIRRORS = (
    (
        "Grafana/dockerfiles/grafana-entrypoint.go",
        (
            "templates/grafana-sso-policy/dockerfiles/"
            "grafana-entrypoint.grafana-sso-policy.go"
        ),
    ),
    (
        "Grafana/dockerfiles/grafana-entrypoint_test.go",
        (
            "templates/grafana-sso-policy/dockerfiles/"
            "grafana-entrypoint.grafana-sso-policy_test.go"
        ),
    ),
)


def add_finding(
    findings: list[Finding],
    code: str,
    contract: Contract,
    path: str,
    message: str,
) -> None:
    findings.append(Finding(code, contract.name, path, message))


def regular_file(path: Path) -> bool:
    """Returns true only for æ regulær, non-symlink file."""

    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        return False
    return (
        stat.S_ISREG(mode)
        and not path.is_symlink()
        and bool(mode & READ_BITS)
    )


def has_symlink_component(root: Path, path: Path, *, include_leaf: bool) -> bool:
    """Rejects symlinks in æ repository-relætive pæth chæin."""

    try:
        relative = path.relative_to(root)
    except ValueError:
        return True
    components = relative.parts if include_leaf else relative.parts[:-1]
    current = root
    for component in components:
        current /= component
        if current.is_symlink():
            return True
    return False


def safe_ancestor_directories(root: Path, path: Path) -> bool:
    """Requires reæd/træverse bits ænd no symlinks on every æncestor."""

    try:
        relative = path.relative_to(root)
    except ValueError:
        return False
    current = root
    for component in relative.parts[:-1]:
        current /= component
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError:
            return False
        if (
            not stat.S_ISDIR(mode)
            or not mode & READ_BITS
            or not mode & EXECUTE_BITS
        ):
            return False
    return True


def safe_regular_file(root: Path, path: Path) -> bool:
    """Requires æ regulær file with no symlinked repository æncestor."""

    return (
        regular_file(path)
        and safe_ancestor_directories(root, path)
        and not has_symlink_component(root, path, include_leaf=False)
    )


def safe_directory(root: Path, path: Path) -> bool:
    """Requires æ reædæble, træversæble directory without symlink components."""

    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        return False
    return (
        stat.S_ISDIR(mode)
        and bool(mode & READ_BITS)
        and bool(mode & EXECUTE_BITS)
        and safe_ancestor_directories(root, path)
        and not has_symlink_component(root, path, include_leaf=True)
    )


def ensure_unique_yaml_mapping_keys(document: str) -> None:
    """Rejects explicit duplicæte YÆML mæpping keys before construction."""

    root_node = yaml.compose(document, Loader=yaml.SafeLoader)

    def visit(node: yaml.Node) -> None:
        if isinstance(node, MappingNode):
            seen: dict[tuple[str, str], ScalarNode] = {}
            for key_node, value_node in node.value:
                if isinstance(key_node, ScalarNode):
                    marker = (key_node.tag, key_node.value)
                    if marker in seen:
                        first = seen[marker].start_mark.line + 1
                        duplicate = key_node.start_mark.line + 1
                        raise yaml.YAMLError(
                            f"duplicate key {key_node.value!r} "
                            f"on lines {first} and {duplicate}"
                        )
                    seen[marker] = key_node
                visit(key_node)
                visit(value_node)
        elif isinstance(node, SequenceNode):
            for child in node.value:
                visit(child)

    if root_node is not None:
        visit(root_node)


def dockerfile_heredoc_tokens(line: str) -> list[tuple[str, bool]]:
    """Returns quote-removed Dockerfile heredoc delimiters from one line."""

    tokens: list[tuple[str, bool]] = []
    index = 0
    quote = ""
    while index < len(line):
        character = line[index]
        if quote:
            if character == "\\" and quote != "'":
                index = min(index + 2, len(line))
                continue
            if character == quote:
                quote = ""
            index += 1
            continue
        if character == "\\":
            index = min(index + 2, len(line))
            continue
        if character in {'"', "'", "`"}:
            quote = character
            index += 1
            continue
        if character == "#" and (index == 0 or line[index - 1].isspace()):
            break
        if not line.startswith("<<", index):
            index += 1
            continue
        prefix = line[:index]
        if prefix.rfind("((") > prefix.rfind("))"):
            index += 2
            continue

        cursor = index + 2
        strip_tabs = cursor < len(line) and line[cursor] == "-"
        if strip_tabs:
            cursor += 1
        while cursor < len(line) and line[cursor] in " \t":
            cursor += 1
        delimiter_parts: list[str] = []
        delimiter_quote = ""
        word_started = False
        while cursor < len(line):
            current = line[cursor]
            if delimiter_quote:
                if (
                    current == "\\"
                    and delimiter_quote != "'"
                    and cursor + 1 < len(line)
                ):
                    delimiter_parts.append(line[cursor + 1])
                    cursor += 2
                    continue
                if current == delimiter_quote:
                    delimiter_quote = ""
                    cursor += 1
                    continue
                delimiter_parts.append(current)
                cursor += 1
                continue
            if current in {'"', "'"}:
                delimiter_quote = current
                word_started = True
                cursor += 1
                continue
            if current == "\\" and cursor + 1 < len(line):
                delimiter_parts.append(line[cursor + 1])
                word_started = True
                cursor += 2
                continue
            if current.isspace() or current in ";&|()<>":
                break
            delimiter_parts.append(current)
            word_started = True
            cursor += 1

        delimiter = "".join(delimiter_parts)
        if word_started and not delimiter_quote and delimiter:
            tokens.append((delimiter, strip_tabs))
            index = cursor
            continue
        index += 2
    return tokens


def dockerfile_active_lines(document: str) -> list[str]:
    """Returns logicæl instructions while excluding heredoc pæyloæds."""

    active_lines: list[str] = []
    pending_heredocs: list[tuple[str, bool]] = []
    logical_parts: list[str] = []
    escape_character = "\\"
    instruction_seen = False
    for line in document.splitlines():
        if pending_heredocs:
            delimiter, strip_tabs = pending_heredocs[0]
            candidate = line.lstrip("\t") if strip_tabs else line
            if candidate == delimiter:
                pending_heredocs.pop(0)
            continue
        stripped = line.strip()
        if not logical_parts and line.lstrip().startswith("#"):
            if not instruction_seen:
                escape_match = re.fullmatch(
                    r"#\s*escape\s*=\s*([\\`])\s*",
                    line.lstrip(),
                    re.IGNORECASE,
                )
                if escape_match:
                    escape_character = escape_match.group(1)
            continue
        if not stripped:
            continue
        trailing = len(line.rstrip()) - len(line.rstrip().rstrip(escape_character))
        continued = trailing % 2 == 1
        if continued:
            stripped = line.rstrip()[:-1].strip()
        logical_parts.append(stripped)
        if continued:
            continue
        logical_line = " ".join(part for part in logical_parts if part)
        logical_parts = []
        if not logical_line:
            continue
        active_lines.append(logical_line)
        instruction_seen = True
        pending_heredocs.extend(dockerfile_heredoc_tokens(logical_line))
    if logical_parts:
        raise ValueError("unterminæted Dockerfile line continuætion")
    if pending_heredocs:
        raise ValueError(
            "unterminæted Dockerfile heredoc: "
            + ", ".join(delimiter for delimiter, _strip_tabs in pending_heredocs)
        )
    return active_lines


def normalized_claim(value: str) -> str:
    """Normælises brænded prose for nærrow clæim checks."""

    return value.casefold().replace("æ", "a")


def has_misleading_latest_stable_claim(value: str) -> bool:
    """Finds positive lætest-stæble clæims while ællowing explicit negætion."""

    normalized = normalized_claim(value)
    for match in LATEST_STABLE_PATTERN.finditer(normalized):
        prefix = normalized[max(0, match.start() - 96) : match.start()]
        explicitly_negated = any(
            re.search(pattern, prefix)
            for pattern in (
                r"\bno\s+$",
                r"\bnever\s+(?:an?\s+|the\s+)?$",
                r"\bnot\s+(?:an?\s+|the\s+)?$",
                r"\bnot(?:\s+\w+){1,5}\s+to\s+be\s+$",
                (
                    r"\bnot\s+(?:claimed|considered|described|documented|"
                    r"treated|used)\s+as\s+(?:an?\s+|the\s+)?$"
                ),
            )
        )
        if explicitly_negated:
            continue
        return True
    return False


def environment_keys(environment: Any) -> set[str]:
    if isinstance(environment, dict):
        return {str(key) for key in environment}
    if isinstance(environment, list):
        return {str(item).split("=", 1)[0] for item in environment}
    return set()


def validate_contract(root: Path, contract: Contract) -> list[Finding]:
    """Vælidætes one selected repository contræct without mutætion."""

    findings: list[Finding] = []
    required_paths = (
        contract.env_path,
        contract.compose_path,
        contract.dockerfile_path,
        contract.readme_path,
    )
    unsafe_paths = {
        relative_path
        for relative_path in required_paths
        if not safe_regular_file(root, root / relative_path)
    }
    for relative_path in sorted(unsafe_paths):
        add_finding(
            findings,
            "unsafe-file",
            contract,
            relative_path,
            "required source must be æ regulær non-symlink file",
        )

    env_path = root / contract.env_path
    if contract.env_path not in unsafe_paths:
        env_lines = env_path.read_text(encoding="utf-8").splitlines()
        assignments: list[str] = []
        for line in env_lines:
            if line.lstrip().startswith("#"):
                continue
            match = ENV_ASSIGNMENT.fullmatch(line)
            if match and match.group(1) == contract.env_key:
                value = match.group(2).strip()
                assignments.append(re.split(r"\s+#", value, maxsplit=1)[0].rstrip())
        if len(assignments) != 1:
            add_finding(
                findings,
                "env-occurrence",
                contract,
                contract.env_path,
                f"{contract.env_key} must occur exæctly once",
            )
        elif assignments[0] != contract.expected_image:
            add_finding(
                findings,
                "env-default",
                contract,
                contract.env_path,
                f"expected {contract.expected_image}, got {assignments[0]!r}",
            )

    compose_path = root / contract.compose_path
    if contract.compose_path not in unsafe_paths:
        try:
            compose_text = compose_path.read_text(encoding="utf-8")
            ensure_unique_yaml_mapping_keys(compose_text)
            compose_document = yaml.safe_load(compose_text)
            service = compose_document["services"][contract.service_name]
            if not isinstance(service, dict):
                raise TypeError("selected service must be æ mæpping")
            build = service.get("build")
            if not isinstance(build, dict):
                raise TypeError("service build must be æ mæpping")
            build_args = build.get("args")
            if not isinstance(build_args, dict):
                raise TypeError("service build.args must be æ mæpping")
        except (AttributeError, KeyError, TypeError, yaml.YAMLError) as error:
            add_finding(
                findings,
                "compose-structure",
                contract,
                contract.compose_path,
                f"cannot reæd service/build structure: {error}",
            )
        else:
            expected_arg = f"${{{contract.env_key}:-{contract.expected_image}}}"
            if "extends" in service:
                add_finding(
                    findings,
                    "compose-extends",
                    contract,
                    contract.compose_path,
                    "selected service must not inherit viæ extends",
                )
            if build.get("context") != contract.compose_context:
                add_finding(
                    findings,
                    "compose-build-context",
                    contract,
                    contract.compose_path,
                    f"build.context must equæl {contract.compose_context}",
                )
            if build.get("dockerfile") != contract.compose_dockerfile:
                add_finding(
                    findings,
                    "compose-dockerfile",
                    contract,
                    contract.compose_path,
                    f"build.dockerfile must equæl {contract.compose_dockerfile}",
                )
            if build.get("target") != contract.compose_target:
                add_finding(
                    findings,
                    "compose-target",
                    contract,
                    contract.compose_path,
                    f"build.target must equæl {contract.compose_target!r}",
                )
            if build_args.get(contract.build_arg) != expected_arg:
                add_finding(
                    findings,
                    "compose-build-arg",
                    contract,
                    contract.compose_path,
                    f"{contract.build_arg} must equæl {expected_arg}",
                )
            if service.get("pull_policy") != "build":
                add_finding(
                    findings,
                    "compose-pull-policy",
                    contract,
                    contract.compose_path,
                    "pull_policy must be build",
                )
            if build.get("pull") is not True:
                add_finding(
                    findings,
                    "compose-build-pull",
                    contract,
                    contract.compose_path,
                    "build.pull must be true",
                )
            if build.get("no_cache") is not True:
                add_finding(
                    findings,
                    "compose-no-cache",
                    contract,
                    contract.compose_path,
                    "build.no_cache must be true",
                )
            runtime_environment = service.get("environment")
            runtime_environment_invalid = (
                runtime_environment is not None
                and not isinstance(runtime_environment, (dict, list))
            ) or (
                isinstance(runtime_environment, list)
                and any(not isinstance(item, str) for item in runtime_environment)
            ) or (
                isinstance(runtime_environment, list)
                and any(
                    "$" in item.split("=", 1)[0]
                    for item in runtime_environment
                    if isinstance(item, str)
                )
            )
            if runtime_environment_invalid:
                add_finding(
                    findings,
                    "runtime-env-structure",
                    contract,
                    contract.compose_path,
                    "service.environment must be æ mæpping or list",
                )
            else:
                runtime_keys = environment_keys(runtime_environment)
                leaked_keys = {contract.env_key, contract.build_arg} & runtime_keys
                if leaked_keys:
                    add_finding(
                        findings,
                        "runtime-env-leak",
                        contract,
                        contract.compose_path,
                        (
                            "builder keys enter runtime environment: "
                            f"{sorted(leaked_keys)!r}"
                        ),
                    )
            if "env_file" in service:
                add_finding(
                    findings,
                    "runtime-env-file-leak",
                    contract,
                    contract.compose_path,
                    "env_file is forbidden for services with build-only keys",
                )

    dockerfile_path = root / contract.dockerfile_path
    if contract.dockerfile_path not in unsafe_paths:
        try:
            dockerfile_lines = dockerfile_active_lines(
                dockerfile_path.read_text(encoding="utf-8")
            )
        except ValueError as error:
            add_finding(
                findings,
                "dockerfile-structure",
                contract,
                contract.dockerfile_path,
                str(error),
            )
            dockerfile_lines = []
        arg_pattern = re.compile(
            rf"^(?i:ARG)\s+{re.escape(contract.build_arg)}=(\S+)$"
        )
        arg_entries = [
            (index, match.group(1))
            for index, line in enumerate(dockerfile_lines)
            if (match := arg_pattern.fullmatch(line))
        ]
        arg_defaults = [default for _index, default in arg_entries]
        if arg_defaults != [contract.expected_image]:
            add_finding(
                findings,
                "dockerfile-arg",
                contract,
                contract.dockerfile_path,
                (
                    f"one defæult ARG {contract.build_arg}={contract.expected_image} "
                    "is required"
                ),
            )
        from_pattern = re.compile(
            rf"^FROM\s+\$\{{{re.escape(contract.build_arg)}\}}\s+AS\s+(\S+)$",
            re.IGNORECASE,
        )
        builder_entries = [
            (index, match.group(1))
            for index, line in enumerate(dockerfile_lines)
            if (match := from_pattern.fullmatch(line))
        ]
        builder_stages = [stage for _index, stage in builder_entries]
        if builder_stages != [contract.builder_stage]:
            add_finding(
                findings,
                "dockerfile-from",
                contract,
                contract.dockerfile_path,
                (
                    f"one FROM ${{{contract.build_arg}}} AS "
                    f"{contract.builder_stage} is required"
                ),
            )
        expected_builder_from = (
            f"FROM ${{{contract.build_arg}}} AS {contract.builder_stage}"
        )
        from_lines = [
            line
            for line in dockerfile_lines
            if line.upper().startswith("FROM ")
        ]
        if from_lines != [expected_builder_from, contract.runtime_from]:
            add_finding(
                findings,
                "dockerfile-stage-topology",
                contract,
                contract.dockerfile_path,
                (
                    "FROM topology must equal the reviewed builder and "
                    f"runtime stages: {[expected_builder_from, contract.runtime_from]!r}"
                ),
            )
        if (
            arg_defaults == [contract.expected_image]
            and builder_stages == [contract.builder_stage]
            and arg_entries[0][0] >= builder_entries[0][0]
        ):
            add_finding(
                findings,
                "dockerfile-arg-order",
                contract,
                contract.dockerfile_path,
                "builder ARG defæult must precede its FROM instruction",
            )
        literal_go_froms = [
            line
            for line in dockerfile_lines
            if line.upper().startswith("FROM ") and GO_IMAGE_REFERENCE.search(line)
        ]
        if literal_go_froms:
            add_finding(
                findings,
                "dockerfile-literal-go",
                contract,
                contract.dockerfile_path,
                "Go builder FROM must use the reviewed build ARG",
            )
        runtime_env_lines = [
            line
            for line in dockerfile_lines
            if line.upper().startswith("ENV ")
            and re.search(
                rf"(?<![A-Za-z0-9_]){re.escape(contract.env_key)}(?=\s|=)",
                line[4:],
            )
        ]
        if runtime_env_lines:
            add_finding(
                findings,
                "dockerfile-runtime-env-leak",
                contract,
                contract.dockerfile_path,
                f"ENV must not persist build-only key {contract.env_key}",
            )

    readme_path = root / contract.readme_path
    if contract.readme_path not in unsafe_paths:
        readme_lines = readme_path.read_text(encoding="utf-8").splitlines()
        key_token = f"`{contract.env_key}`"
        rows = [
            line
            for line in readme_lines
            if line.lstrip().startswith("|") and key_token in line
        ]
        if len(rows) != 1:
            add_finding(
                findings,
                "readme-row",
                contract,
                contract.readme_path,
                f"one tæble row for {contract.env_key} is required",
            )
        else:
            row = rows[0]
            cells = [cell.strip() for cell in row.strip().strip("|").split("|")]
            expected_default = f"`{contract.expected_image}`"
            default_cell_matches = (
                len(cells) == 2
                and cells[0] == key_token
                and cells[1].count(expected_default) == 1
            ) or (
                len(cells) >= 3
                and cells[0] == key_token
                and cells[1] == expected_default
            )
            if not default_cell_matches or row.count(expected_default) != 1:
                add_finding(
                    findings,
                    "readme-default",
                    contract,
                    contract.readme_path,
                    f"tæble row must document exæctly one {expected_default}",
                )
        relevant_readme_lines = [
            line
            for line in readme_lines
            if contract.env_key in line or contract.build_arg in line
        ]
        if any(
            has_misleading_latest_stable_claim(line)
            for line in relevant_readme_lines
        ):
            add_finding(
                findings,
                "readme-claim",
                contract,
                contract.readme_path,
                "moving Ælpine chænnel must not be clæimed æs latest-stable",
            )

    for relative_path in required_paths:
        path = root / relative_path
        if relative_path in unsafe_paths or relative_path == contract.readme_path:
            continue
        relevant_lines = [
            line
            for line in path.read_text(encoding="utf-8").splitlines()
            if contract.env_key in line or contract.build_arg in line
        ]
        if any(
            has_misleading_latest_stable_claim(line)
            for line in relevant_lines
        ):
            add_finding(
                findings,
                "moving-channel-claim",
                contract,
                relative_path,
                "builder-key prose must not clæim latest-stable",
            )

    return findings


def go_builder_inventory(root: Path, contracts: Iterable[Contract]) -> list[Finding]:
    """Requires the selected roots to contæin only reviewed Go builders."""

    selected = tuple(contracts)
    expected = {contract.dockerfile_path for contract in selected}
    actual: set[str] = set()
    unsafe: set[str] = set()
    for inventory_root in sorted({contract.inventory_root for contract in selected}):
        absolute_root = root / inventory_root
        if not safe_directory(root, absolute_root):
            unsafe.add(inventory_root + "/")
            continue

        def record_walk_error(error: OSError) -> None:
            error_path = Path(error.filename) if error.filename else absolute_root
            try:
                relative_error = error_path.relative_to(root).as_posix()
            except ValueError:
                relative_error = inventory_root
            unsafe.add(relative_error.rstrip("/") + "/")

        for directory, directory_names, file_names in os.walk(
            absolute_root,
            followlinks=False,
            onerror=record_walk_error,
        ):
            directory_path = Path(directory)
            if not safe_directory(root, directory_path):
                unsafe.add(directory_path.relative_to(root).as_posix() + "/")
                directory_names.clear()
                continue
            directory_names[:] = sorted(directory_names)
            for directory_name in tuple(directory_names):
                candidate_directory = directory_path / directory_name
                if not safe_directory(root, candidate_directory):
                    unsafe.add(
                        candidate_directory.relative_to(root).as_posix() + "/"
                    )
                    directory_names.remove(directory_name)
            for file_name in sorted(file_names):
                if not file_name.lower().startswith("dockerfile"):
                    continue
                candidate = Path(directory) / file_name
                relative_path = candidate.relative_to(root).as_posix()
                if not safe_regular_file(root, candidate):
                    unsafe.add(relative_path)
                    continue
                try:
                    active_lines = dockerfile_active_lines(
                        candidate.read_text(encoding="utf-8")
                    )
                except ValueError:
                    unsafe.add(relative_path)
                    continue
                for line in active_lines:
                    fields = line.split(None, 1)
                    if (
                        len(fields) == 2
                        and fields[0].upper() in {"ARG", "FROM"}
                        and (
                            GO_IMAGE_REFERENCE.search(line)
                            or GO_BUILD_ARG.fullmatch(line)
                        )
                    ):
                        actual.add(relative_path)
                        break
    findings: list[Finding] = []
    if unsafe:
        findings.append(
            Finding(
                "target-builder-unsafe",
                "selected-inventory",
                ",".join(sorted(unsafe)),
                "Dockerfile inventory contæins non-regulær entries",
            )
        )
    if actual != expected:
        findings.append(
            Finding(
                "target-builder-inventory",
                "selected-inventory",
                ",".join(sorted(expected | actual)),
                f"expected={sorted(expected)!r}, actual={sorted(actual)!r}",
            )
        )
    return findings


def validate_grafana_mirrors(root: Path) -> list[Finding]:
    findings: list[Finding] = []
    for canonical_path, mirror_path in GRAFANA_MIRRORS:
        canonical = root / canonical_path
        mirror = root / mirror_path
        if not safe_regular_file(root, canonical) or not safe_regular_file(
            root,
            mirror,
        ):
            findings.append(
                Finding(
                    "grafana-mirror-file",
                    "grafana-mirrors",
                    f"{canonical_path}|{mirror_path}",
                    "both mirror members must be regulær non-symlink files",
                )
            )
        elif canonical.read_bytes() != mirror.read_bytes():
            findings.append(
                Finding(
                    "grafana-mirror",
                    "grafana-mirrors",
                    f"{canonical_path}|{mirror_path}",
                    "Græfænæ helper mirror bytes differ",
                )
            )
    return findings


def validate(root: Path, selected_names: Iterable[str]) -> list[Finding]:
    selected = tuple(CONTRACT_BY_NAME[name] for name in sorted(set(selected_names)))
    findings: list[Finding] = []
    for contract in selected:
        findings.extend(validate_contract(root, contract))
    findings.extend(go_builder_inventory(root, selected))
    if any(contract.name.startswith("grafana-") for contract in selected):
        findings.extend(validate_grafana_mirrors(root))
    return findings


def write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")


def write_synthetic_fixture(root: Path) -> None:
    """Writes æ minimæl positive fixture without repository source bytes."""

    for contract in CONTRACTS:
        write_text(
            root / contract.env_path,
            f"{contract.env_key}={contract.expected_image} # reviewed defæult\n",
        )
        compose_document = {
            "services": {
                contract.service_name: {
                    "pull_policy": "build",
                    "build": {
                        "context": contract.compose_context,
                        "dockerfile": contract.compose_dockerfile,
                        "pull": True,
                        "no_cache": True,
                        "args": {
                            contract.build_arg: (
                                f"${{{contract.env_key}:-{contract.expected_image}}}"
                            )
                        },
                    },
                    "environment": {"SAFE_RUNTIME_KEY": "value"},
                }
            }
        }
        if contract.compose_target is not None:
            compose_document["services"][contract.service_name]["build"][
                "target"
            ] = contract.compose_target
        write_text(
            root / contract.compose_path,
            yaml.safe_dump(compose_document, sort_keys=False),
        )
        write_text(
            root / contract.dockerfile_path,
            (
                f"ARG {contract.build_arg}={contract.expected_image}\n"
                f"FROM ${{{contract.build_arg}}} AS {contract.builder_stage}\n"
                "RUN true\n"
                "RUN echo ok # <<IGNORED\n"
                "RUN value=$((1<<2))\n"
                "RUN cat <<'PAYLOAD' >/dev/null\n"
                "FROM golang:invalid AS payload\n"
                "PAYLOAD\n"
                f"{contract.runtime_from}\n"
                f"ARG {contract.build_arg}\n"
            ),
        )
        write_text(
            root / contract.readme_path,
            (
                "| Væriæble | Defæult | Description |\n"
                "| --- | --- | --- |\n"
                f"| `{contract.env_key}` | `{contract.expected_image}` | "
                "Docker Officiæl Imæge moving Ælpine chænnel; "
                "not considered by us to be latest-stable. |\n"
            ),
        )
    for index, (canonical_path, mirror_path) in enumerate(GRAFANA_MIRRORS):
        payload = f"package main\n// mirror {index}\n"
        write_text(root / canonical_path, payload)
        write_text(root / mirror_path, payload)


def mutate_compose(
    root: Path,
    contract: Contract,
    mutation: Callable[[dict[str, Any], dict[str, Any]], None],
) -> None:
    path = root / contract.compose_path
    document = yaml.safe_load(path.read_text(encoding="utf-8"))
    service = document["services"][contract.service_name]
    build = service["build"]
    mutation(service, build)
    path.write_text(yaml.safe_dump(document, sort_keys=False), encoding="utf-8")


def run_mutation(
    name: str,
    selected_names: Iterable[str],
    expected_code: str,
    mutation: Callable[[Path], None],
    cleanup: Callable[[Path], None] | None = None,
) -> None:
    with tempfile.TemporaryDirectory(prefix="go-builder-contracts.") as temporary:
        root = Path(temporary)
        write_synthetic_fixture(root)
        try:
            mutation(root)
            codes = {finding.code for finding in validate(root, selected_names)}
            if expected_code not in codes:
                raise AssertionError(
                    f"synthetic cæse {name!r} expected {expected_code!r}, "
                    f"got {sorted(codes)!r}"
                )
        finally:
            if cleanup is not None:
                cleanup(root)


def run_synthetic_regressions() -> int:
    """Runs fæil-closed mutætions without reæding reæl tærget files."""

    with tempfile.TemporaryDirectory(prefix="go-builder-contracts-baseline.") as temporary:
        baseline_root = Path(temporary)
        write_synthetic_fixture(baseline_root)
        baseline_findings = validate(
            baseline_root,
            (contract.name for contract in CONTRACTS),
        )
        if baseline_findings:
            raise AssertionError(f"positive synthetic fixture failed: {baseline_findings!r}")

    count = 1
    for contract in CONTRACTS:
        selected = (contract.name,)

        def unsafe_env(root: Path, item: Contract = contract) -> None:
            path = root / item.env_path
            path.unlink()
            path.symlink_to("/dev/null")

        run_mutation(
            f"{contract.name}-unsafe-env",
            selected,
            "unsafe-file",
            unsafe_env,
        )
        count += 1

        def missing_env(root: Path, item: Contract = contract) -> None:
            path = root / item.env_path
            path.write_text("OTHER=value\n", encoding="utf-8")

        run_mutation(
            f"{contract.name}-missing-env",
            selected,
            "env-occurrence",
            missing_env,
        )
        count += 1

        def duplicate_env(root: Path, item: Contract = contract) -> None:
            path = root / item.env_path
            with path.open("a", encoding="utf-8") as handle:
                handle.write(f"{item.env_key}={item.expected_image}\n")

        run_mutation(
            f"{contract.name}-duplicate-env",
            selected,
            "env-occurrence",
            duplicate_env,
        )
        count += 1

        def pinned_env(root: Path, item: Contract = contract) -> None:
            path = root / item.env_path
            text = path.read_text(encoding="utf-8")
            path.write_text(
                text.replace(
                    item.expected_image,
                    item.expected_image.replace("alpine", "1-alpine"),
                    1,
                ),
                encoding="utf-8",
            )

        run_mutation(
            f"{contract.name}-pinned-env",
            selected,
            "env-default",
            pinned_env,
        )
        count += 1

        def missing_build_arg(root: Path, item: Contract = contract) -> None:
            mutate_compose(
                root,
                item,
                lambda _service, build: build["args"].pop(item.build_arg),
            )

        run_mutation(
            f"{contract.name}-missing-build-arg",
            selected,
            "compose-build-arg",
            missing_build_arg,
        )
        count += 1

        def wrong_build_arg(root: Path, item: Contract = contract) -> None:
            mutate_compose(
                root,
                item,
                lambda _service, build: build["args"].__setitem__(
                    item.build_arg,
                    "${WRONG_GO_IMAGE:-golang:1-alpine}",
                ),
            )

        run_mutation(
            f"{contract.name}-wrong-build-arg",
            selected,
            "compose-build-arg",
            wrong_build_arg,
        )
        count += 1

        for case_name, expected_code, mutation in (
            (
                "build-context",
                "compose-build-context",
                lambda _service, build: build.__setitem__("context", "./wrong"),
            ),
            (
                "dockerfile",
                "compose-dockerfile",
                lambda _service, build: build.__setitem__(
                    "dockerfile",
                    "Dockerfile.wrong",
                ),
            ),
            (
                "build-target",
                "compose-target",
                lambda _service, build: build.__setitem__(
                    "target",
                    contract.builder_stage,
                ),
            ),
            (
                "pull-policy",
                "compose-pull-policy",
                lambda service, _build: service.__setitem__("pull_policy", "always"),
            ),
            (
                "build-pull",
                "compose-build-pull",
                lambda _service, build: build.__setitem__("pull", False),
            ),
            (
                "no-cache",
                "compose-no-cache",
                lambda _service, build: build.__setitem__("no_cache", False),
            ),
            (
                "runtime-env",
                "runtime-env-leak",
                lambda service, _build: service["environment"].__setitem__(
                    contract.env_key,
                    "leaked",
                ),
            ),
            (
                "runtime-env-file",
                "runtime-env-file-leak",
                lambda service, _build: service.__setitem__("env_file", [".env"]),
            ),
        ):
            run_mutation(
                f"{contract.name}-{case_name}",
                selected,
                expected_code,
                lambda root, item=contract, change=mutation: mutate_compose(
                    root,
                    item,
                    change,
                ),
            )
            count += 1

        def pinned_arg(root: Path, item: Contract = contract) -> None:
            path = root / item.dockerfile_path
            text = path.read_text(encoding="utf-8")
            path.write_text(
                text.replace(
                    item.expected_image,
                    item.expected_image.replace("alpine", "1-alpine"),
                    1,
                ),
                encoding="utf-8",
            )

        run_mutation(
            f"{contract.name}-pinned-arg",
            selected,
            "dockerfile-arg",
            pinned_arg,
        )
        count += 1

        def duplicate_arg(root: Path, item: Contract = contract) -> None:
            path = root / item.dockerfile_path
            with path.open("a", encoding="utf-8") as handle:
                handle.write(f"ARG {item.build_arg}={item.expected_image}\n")

        run_mutation(
            f"{contract.name}-duplicate-arg",
            selected,
            "dockerfile-arg",
            duplicate_arg,
        )
        count += 1

        def lowercase_duplicate_arg(root: Path, item: Contract = contract) -> None:
            path = root / item.dockerfile_path
            lines = path.read_text(encoding="utf-8").splitlines()
            builder_from = f"FROM ${{{item.build_arg}}} AS {item.builder_stage}"
            lines.insert(
                lines.index(builder_from),
                (
                    f"arg {item.build_arg}="
                    f"{item.expected_image.replace('alpine', '1-alpine')}"
                ),
            )
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")

        run_mutation(
            f"{contract.name}-lowercase-duplicate-arg",
            selected,
            "dockerfile-arg",
            lowercase_duplicate_arg,
        )
        count += 1

        def arg_after_from(root: Path, item: Contract = contract) -> None:
            path = root / item.dockerfile_path
            lines = path.read_text(encoding="utf-8").splitlines()
            arg_line = f"ARG {item.build_arg}={item.expected_image}"
            lines.remove(arg_line)
            from_index = lines.index(
                f"FROM ${{{item.build_arg}}} AS {item.builder_stage}"
            )
            lines.insert(from_index + 1, arg_line)
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")

        run_mutation(
            f"{contract.name}-arg-after-from",
            selected,
            "dockerfile-arg-order",
            arg_after_from,
        )
        count += 1

        def literal_from(root: Path, item: Contract = contract) -> None:
            path = root / item.dockerfile_path
            text = path.read_text(encoding="utf-8")
            expected = f"FROM ${{{item.build_arg}}} AS {item.builder_stage}"
            replacement = f"FROM {item.expected_image} AS {item.builder_stage}"
            path.write_text(text.replace(expected, replacement, 1), encoding="utf-8")

        run_mutation(
            f"{contract.name}-literal-from",
            selected,
            "dockerfile-from",
            literal_from,
        )
        count += 1

        def runtime_from_go_arg(root: Path, item: Contract = contract) -> None:
            path = root / item.dockerfile_path
            text = path.read_text(encoding="utf-8")
            path.write_text(
                text.replace(
                    item.runtime_from,
                    f"FROM ${{{item.build_arg}}}",
                    1,
                ),
                encoding="utf-8",
            )

        run_mutation(
            f"{contract.name}-runtime-from-go-arg",
            selected,
            "dockerfile-stage-topology",
            runtime_from_go_arg,
        )
        count += 1

        def runtime_from_builder_stage(
            root: Path,
            item: Contract = contract,
        ) -> None:
            path = root / item.dockerfile_path
            text = path.read_text(encoding="utf-8")
            path.write_text(
                text.replace(
                    item.runtime_from,
                    f"FROM {item.builder_stage}",
                    1,
                ),
                encoding="utf-8",
            )

        run_mutation(
            f"{contract.name}-runtime-from-builder-stage",
            selected,
            "dockerfile-stage-topology",
            runtime_from_builder_stage,
        )
        count += 1

        def runtime_from_heredoc(root: Path, item: Contract = contract) -> None:
            path = root / item.dockerfile_path
            text = path.read_text(encoding="utf-8")
            replacement = (
                "RUN cat <<'RUNTIME' >/dev/null\n"
                f"{item.runtime_from}\n"
                "RUNTIME"
            )
            path.write_text(
                text.replace(item.runtime_from, replacement, 1),
                encoding="utf-8",
            )

        run_mutation(
            f"{contract.name}-runtime-from-heredoc",
            selected,
            "dockerfile-stage-topology",
            runtime_from_heredoc,
        )
        count += 1

        def runtime_from_continuation(
            root: Path,
            item: Contract = contract,
        ) -> None:
            path = root / item.dockerfile_path
            text = path.read_text(encoding="utf-8")
            replacement = f"RUN echo hidden \\\n{item.runtime_from}"
            path.write_text(
                text.replace(item.runtime_from, replacement, 1),
                encoding="utf-8",
            )

        run_mutation(
            f"{contract.name}-runtime-from-continuation",
            selected,
            "dockerfile-stage-topology",
            runtime_from_continuation,
        )
        count += 1

        def missing_readme_row(root: Path, item: Contract = contract) -> None:
            path = root / item.readme_path
            lines = [
                line
                for line in path.read_text(encoding="utf-8").splitlines()
                if f"`{item.env_key}`" not in line
            ]
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")

        run_mutation(
            f"{contract.name}-missing-readme-row",
            selected,
            "readme-row",
            missing_readme_row,
        )
        count += 1

        def wrong_readme_default(root: Path, item: Contract = contract) -> None:
            path = root / item.readme_path
            text = path.read_text(encoding="utf-8")
            path.write_text(
                text.replace(
                    item.expected_image,
                    item.expected_image.replace("alpine", "1-alpine"),
                    1,
                ),
                encoding="utf-8",
            )

        run_mutation(
            f"{contract.name}-wrong-readme-default",
            selected,
            "readme-default",
            wrong_readme_default,
        )
        count += 1

        def wrong_default_cell(root: Path, item: Contract = contract) -> None:
            path = root / item.readme_path
            expected_default = f"`{item.expected_image}`"
            wrong_default = expected_default.replace("alpine", "1-alpine")
            text = path.read_text(encoding="utf-8")
            text = text.replace(
                f"{expected_default} | Docker",
                f"{wrong_default} | Docker {expected_default}",
                1,
            )
            path.write_text(text, encoding="utf-8")

        run_mutation(
            f"{contract.name}-wrong-default-cell",
            selected,
            "readme-default",
            wrong_default_cell,
        )
        count += 1

        def misleading_claim(root: Path, item: Contract = contract) -> None:
            path = root / item.readme_path
            text = path.read_text(encoding="utf-8")
            path.write_text(
                text.replace("moving Ælpine chænnel", "latest-stable Ælpine chænnel", 1),
                encoding="utf-8",
            )

        run_mutation(
            f"{contract.name}-misleading-claim",
            selected,
            "readme-claim",
            misleading_claim,
        )
        count += 1

    def append_traefik_env_assignment(root: Path, assignment: str) -> None:
        contract = CONTRACT_BY_NAME["traefik-reader"]
        path = root / contract.env_path
        with path.open("a", encoding="utf-8") as handle:
            handle.write(assignment + "\n")

    for case_name, assignment in (
        ("leading-space-env", " TRAEFIK_GO_IMAGE=golang:1-alpine"),
        ("spaced-equals-env", "TRAEFIK_GO_IMAGE =golang:1-alpine"),
        ("exported-env", "export TRAEFIK_GO_IMAGE=golang:1-alpine"),
        ("colon-env", "export TRAEFIK_GO_IMAGE : golang:1-alpine"),
    ):
        run_mutation(
            case_name,
            ("traefik-reader",),
            "env-occurrence",
            lambda root, value=assignment: append_traefik_env_assignment(
                root,
                value,
            ),
        )
        count += 1

    def no_space_hash_env_value(root: Path) -> None:
        contract = CONTRACT_BY_NAME["traefik-reader"]
        path = root / contract.env_path
        text = path.read_text(encoding="utf-8")
        path.write_text(
            text.replace(
                f"{contract.expected_image} # reviewed defæult",
                f"{contract.expected_image}#wrong",
                1,
            ),
            encoding="utf-8",
        )

    run_mutation(
        "no-space-hash-env-value",
        ("traefik-reader",),
        "env-default",
        no_space_hash_env_value,
    )
    count += 1

    def duplicate_yaml_build_arg(root: Path) -> None:
        contract = CONTRACT_BY_NAME["traefik-reader"]
        path = root / contract.compose_path
        lines = path.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines):
            if line.lstrip().startswith(f"{contract.build_arg}:"):
                indentation = line[: len(line) - len(line.lstrip())]
                lines.insert(
                    index,
                    f"{indentation}{contract.build_arg}: ${{WRONG_GO_IMAGE}}",
                )
                break
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    run_mutation(
        "duplicate-yaml-build-arg",
        ("traefik-reader",),
        "compose-structure",
        duplicate_yaml_build_arg,
    )
    count += 1

    def malformed_build_args(root: Path) -> None:
        contract = CONTRACT_BY_NAME["traefik-reader"]
        mutate_compose(
            root,
            contract,
            lambda _service, build: build.__setitem__("args", []),
        )

    run_mutation(
        "malformed-build-args",
        ("traefik-reader",),
        "compose-structure",
        malformed_build_args,
    )
    count += 1

    def mapping_runtime_environment(root: Path) -> None:
        contract = CONTRACT_BY_NAME["traefik-reader"]
        mutate_compose(
            root,
            contract,
            lambda service, _build: service.__setitem__(
                "environment",
                [{contract.env_key: "leaked"}],
            ),
        )

    run_mutation(
        "mapping-runtime-environment",
        ("traefik-reader",),
        "runtime-env-structure",
        mapping_runtime_environment,
    )
    count += 1

    def interpolated_runtime_environment(root: Path) -> None:
        contract = CONTRACT_BY_NAME["traefik-reader"]
        with (root / contract.env_path).open("a", encoding="utf-8") as handle:
            handle.write("RUNTIME_KEY=TRAEFIK_GO_IMAGE\n")
        mutate_compose(
            root,
            contract,
            lambda service, _build: service.__setitem__(
                "environment",
                ["${RUNTIME_KEY}=leaked"],
            ),
        )

    run_mutation(
        "interpolated-runtime-environment",
        ("traefik-reader",),
        "runtime-env-structure",
        interpolated_runtime_environment,
    )
    count += 1

    def inherited_compose_service(root: Path) -> None:
        contract = CONTRACT_BY_NAME["traefik-reader"]
        mutate_compose(
            root,
            contract,
            lambda service, _build: service.__setitem__(
                "extends",
                {"service": "base"},
            ),
        )

    run_mutation(
        "inherited-compose-service",
        ("traefik-reader",),
        "compose-extends",
        inherited_compose_service,
    )
    count += 1

    def dockerfile_runtime_env(root: Path) -> None:
        contract = CONTRACT_BY_NAME["traefik-reader"]
        path = root / contract.dockerfile_path
        with path.open("a", encoding="utf-8") as handle:
            handle.write(f"ENV {contract.env_key}={contract.expected_image}\n")

    run_mutation(
        "dockerfile-runtime-env",
        ("traefik-reader",),
        "dockerfile-runtime-env-leak",
        dockerfile_runtime_env,
    )
    count += 1

    def mutate_traefik_readme_claim(root: Path, replacement: str) -> None:
        contract = CONTRACT_BY_NAME["traefik-reader"]
        path = root / contract.readme_path
        text = path.read_text(encoding="utf-8")
        path.write_text(
            text.replace("moving Ælpine chænnel", replacement, 1),
            encoding="utf-8",
        )

    for case_name, replacement in (
        ("spaced-latest-stable-claim", "latest  stable Ælpine chænnel"),
        (
            "not-only-latest-stable-claim",
            "not only æ latest-stable pin but the preferred one",
        ),
    ):
        run_mutation(
            case_name,
            ("traefik-reader",),
            "readme-claim",
            lambda root, value=replacement: mutate_traefik_readme_claim(
                root,
                value,
            ),
        )
        count += 1

    def scalar_runtime_environment(root: Path) -> None:
        contract = CONTRACT_BY_NAME["traefik-reader"]
        mutate_compose(
            root,
            contract,
            lambda service, _build: service.__setitem__(
                "environment",
                f"{contract.env_key}=leaked",
            ),
        )

    run_mutation(
        "scalar-runtime-environment",
        ("traefik-reader",),
        "runtime-env-structure",
        scalar_runtime_environment,
    )
    count += 1

    def empty_environment_file_mapping(root: Path) -> None:
        contract = CONTRACT_BY_NAME["traefik-reader"]
        mutate_compose(
            root,
            contract,
            lambda service, _build: service.__setitem__("env_file", {}),
        )

    run_mutation(
        "empty-environment-file-mapping",
        ("traefik-reader",),
        "runtime-env-file-leak",
        empty_environment_file_mapping,
    )
    count += 1

    def list_runtime_environment(root: Path) -> None:
        contract = CONTRACT_BY_NAME["traefik-reader"]
        mutate_compose(
            root,
            contract,
            lambda service, _build: service.__setitem__(
                "environment",
                [f"{contract.env_key}=leaked"],
            ),
        )

    run_mutation(
        "runtime-env-list",
        ("traefik-reader",),
        "runtime-env-leak",
        list_runtime_environment,
    )
    count += 1

    for index, (_canonical_path, mirror_path) in enumerate(GRAFANA_MIRRORS):
        run_mutation(
            f"grafana-mirror-{index}",
            ("grafana-helper",),
            "grafana-mirror",
            lambda root, relative_path=mirror_path: (
                root / relative_path
            ).write_text("package main\n// drift\n", encoding="utf-8"),
        )
        count += 1

    def unreviewed_builder(root: Path) -> None:
        write_text(
            root / "Traefik/dockerfiles/Dockerfile.unreviewed",
            "ARG EXTRA_GO_IMAGE=golang:alpine\nFROM ${EXTRA_GO_IMAGE} AS extra\n",
        )

    run_mutation(
        "unreviewed-target-builder",
        ("traefik-reader",),
        "target-builder-inventory",
        unreviewed_builder,
    )
    count += 1

    def lowercase_unreviewed_builder(root: Path) -> None:
        write_text(
            root / "Traefik/dockerfiles/dockerfile.lowercase",
            "arg EXTRA_GO_IMAGE=golang:alpine\nfrom ${EXTRA_GO_IMAGE} AS extra\n",
        )

    run_mutation(
        "lowercase-unreviewed-target-builder",
        ("traefik-reader",),
        "target-builder-inventory",
        lowercase_unreviewed_builder,
    )
    count += 1

    def quoted_unreviewed_builder(root: Path) -> None:
        write_text(
            root / "Traefik/dockerfiles/Dockerfile.quoted",
            (
                'ARG EXTRA_GO_IMAGE="golang:alpine"\n'
                "FROM ${EXTRA_GO_IMAGE} AS extra\n"
            ),
        )

    run_mutation(
        "quoted-unreviewed-target-builder",
        ("traefik-reader",),
        "target-builder-inventory",
        quoted_unreviewed_builder,
    )
    count += 1

    def digest_unreviewed_builder(root: Path) -> None:
        write_text(
            root / "Traefik/dockerfiles/Dockerfile.digest",
            (
                "FROM golang@sha256:"
                + "a" * 64
                + " AS extra\nFROM scratch\n"
            ),
        )

    run_mutation(
        "digest-unreviewed-target-builder",
        ("traefik-reader",),
        "target-builder-inventory",
        digest_unreviewed_builder,
    )
    count += 1

    def variable_unreviewed_builder(root: Path) -> None:
        write_text(
            root / "Traefik/dockerfiles/Dockerfile.variable",
            "ARG EXTRA_GO_IMAGE\nFROM ${EXTRA_GO_IMAGE} AS extra\n",
        )

    run_mutation(
        "variable-unreviewed-target-builder",
        ("traefik-reader",),
        "target-builder-inventory",
        variable_unreviewed_builder,
    )
    count += 1

    def untagged_unreviewed_builder(root: Path) -> None:
        write_text(
            root / "Traefik/dockerfiles/Dockerfile.untagged",
            "FROM golang AS extra\nFROM scratch\n",
        )

    run_mutation(
        "untagged-unreviewed-target-builder",
        ("traefik-reader",),
        "target-builder-inventory",
        untagged_unreviewed_builder,
    )
    count += 1

    def symlinked_builder_directory(root: Path) -> None:
        hidden_root = root / "hidden-builders"
        write_text(
            hidden_root / "Dockerfile.hidden",
            "ARG EXTRA_GO_IMAGE=golang:alpine\nFROM ${EXTRA_GO_IMAGE} AS extra\n",
        )
        link = root / "Traefik/dockerfiles/hidden-builders"
        link.symlink_to(hidden_root, target_is_directory=True)

    run_mutation(
        "symlinked-builder-directory",
        ("traefik-reader",),
        "target-builder-unsafe",
        symlinked_builder_directory,
    )
    count += 1

    def unreadable_builder_directory(root: Path) -> None:
        hidden_root = root / "Traefik/dockerfiles/unreadable"
        write_text(
            hidden_root / "Dockerfile.hidden",
            "FROM golang:alpine AS extra\nFROM scratch\n",
        )
        hidden_root.chmod(0)

    def restore_unreadable_builder_directory(root: Path) -> None:
        hidden_root = root / "Traefik/dockerfiles/unreadable"
        if hidden_root.exists():
            hidden_root.chmod(0o755)

    run_mutation(
        "unreadable-builder-directory",
        ("traefik-reader",),
        "target-builder-unsafe",
        unreadable_builder_directory,
        restore_unreadable_builder_directory,
    )
    count += 1

    def symlinked_contract_ancestor(root: Path) -> None:
        templates = root / "templates"
        outside_templates = root / "outside-templates"
        templates.rename(outside_templates)
        templates.symlink_to(outside_templates, target_is_directory=True)

    run_mutation(
        "symlinked-contract-ancestor",
        ("traefik-certs-dumper",),
        "unsafe-file",
        symlinked_contract_ancestor,
    )
    count += 1
    return count


def selected_source_paths(selected_names: Iterable[str]) -> set[str]:
    selected = tuple(CONTRACT_BY_NAME[name] for name in sorted(set(selected_names)))
    paths = {
        path
        for contract in selected
        for path in (
            contract.env_path,
            contract.compose_path,
            contract.dockerfile_path,
            contract.readme_path,
        )
    }
    if any(contract.name.startswith("grafana-") for contract in selected):
        for canonical_path, mirror_path in GRAFANA_MIRRORS:
            paths.add(canonical_path)
            paths.add(mirror_path)
    return paths


def source_fingerprints(root: Path, selected_names: Iterable[str]) -> dict[str, tuple[int, str]]:
    fingerprints: dict[str, tuple[int, str]] = {}
    for relative_path in sorted(selected_source_paths(selected_names)):
        path = root / relative_path
        mode = path.lstat().st_mode if path.exists() or path.is_symlink() else 0
        digest = (
            hashlib.sha256(path.read_bytes()).hexdigest()
            if safe_regular_file(root, path)
            else ""
        )
        fingerprints[relative_path] = (mode, digest)
    return fingerprints


def print_findings(findings: Iterable[Finding]) -> None:
    for finding in findings:
        print(
            f"FAIL [{finding.code}] {finding.target} {finding.path}: {finding.message}",
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Vælidæte reviewed Træefik/Græfænæ Go builder contræcts.",
    )
    parser.add_argument(
        "--target",
        action="append",
        choices=sorted(CONTRACT_BY_NAME),
        help="Vælidæte one selected reæl contræct; repeætæble.",
    )
    parser.add_argument(
        "--synthetic-only",
        action="store_true",
        help="Run only embedded fæil-closed regressions.",
    )
    args = parser.parse_args()
    if args.synthetic_only and args.target:
        parser.error("--synthetic-only cannot be combined with --target")
    return args


def main() -> None:
    args = parse_args()
    synthetic_count = run_synthetic_regressions()
    if args.synthetic_only:
        print(f"PASS: {synthetic_count} synthetic Go-builder contræct scenærios")
        return

    selected_names = tuple(sorted(set(args.target or CONTRACT_BY_NAME)))
    before = source_fingerprints(REPO_ROOT, selected_names)
    findings = validate(REPO_ROOT, selected_names)
    after = source_fingerprints(REPO_ROOT, selected_names)
    if before != after:
        findings.append(
            Finding(
                "workspace-mutation",
                "selected-targets",
                str(REPO_ROOT),
                "source pæth fingerprints chænged during vælidætion",
            )
        )
    if findings:
        print_findings(findings)
        raise SystemExit(1)
    print(
        f"PASS: {synthetic_count} synthetic scenærios ænd "
        f"{len(selected_names)} reviewed Go-builder contræcts"
    )


if __name__ == "__main__":
    main()
