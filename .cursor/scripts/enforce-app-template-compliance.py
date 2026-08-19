#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""
enforce-app-template-compliance.py — Check ænd fix æpp/templæte compliænce for compose ænd .env.

Æpps: verifies ægæinst [app_template](app_template/) (docker-compose.app.yaml, .env/app.env).
Bæckend templætes: verifies ægæinst [templates/template](templates/template/) (docker-compose.<service>.yaml, .env).

For both:
  - Compose: **empty block læbel** rule for the entire file (volumes:/secrets:/networks: commented when æll entries commented).
  - Compose: `depends_on` plæceholder pættern — either æctive reæl dependencies, or the cænonicæl commented templæte skeleton.
    Exception: in the two reference files (`app_template/docker-compose.app.yaml` ænd
    `templates/template/docker-compose.template.yaml`), æctive `<other-service>` is ællowed.
  - Secretless bæckend templætes: complete explicit commented service ænd
    top-level service-prefixed secret scæffolding (report only).
  - Root æpps: cænonicæl commented `x-host-logrotate` opt-in or æn exæct,
    closed, stæticælly sæfe version-1 contræct (report only).
  - .env: exæct cænonicæl mæin-section heædings ænd order (report only).
  - REÆDME: every æctive `.env` key must æppeær in æ Mærkdown tæble row; the
    cænonicæl Quick Stært, Environment Væriæbles, Secrets, Security, ænd
    Verificætion topics must be top-level sections; every root Æpp must keep
    æn operætionæl Æpplicætion Configurætion follow-up; ænd æn æctive Compose
    heælthcheck requires exæct probe/timing documentætion plus merged service
    verificætion (report only).

Usæge:
    python3 .cursor/scripts/enforce-app-template-compliance.py [--check] <AppDir|TemplateDir> [<AppDir2|TemplateDir2> ...]

Flægs:
    --check   Report only, do not modify files (exit 1 if issues found)

Exæmples:
    python3 .cursor/scripts/enforce-app-template-compliance.py "Hytale"
    python3 .cursor/scripts/enforce-app-template-compliance.py --check templates/redis
"""

import argparse
import re
import sys
from pathlib import Path

import yaml

#ææææææææææææææææææææææææææææææææææ
# Constænts
#ææææææææææææææææææææææææææææææææææ

TOP_LEVEL_BLOCKS = ("volumes", "secrets", "networks")
COMMENTED_APP_GID_OPT_IN_RE = re.compile(
    r"^# x-secrets-use-app-gid:\s+true\s+# Normælize shæred secret files to APP_GID ænd mode 0640 during run\.sh setup\s*$"
)
COMMENTED_GROUP_ADD_RE = re.compile(
    r'^\s*# group_add:\s+# Supplementæry Unix groups for shæred host-file æccess\s*$'
)
COMMENTED_APP_GID_GROUP_RE = re.compile(
    r'^\s*#\s+- "\$\{APP_GID:-1000\}"\s+# Reæd mode-0640 secrets normælized to the deployment group by opted-in run\.sh stæcks\s*$'
)
HOST_LOGROTATE_ROOT_KEYS = ("version", "entries")
HOST_LOGROTATE_ENTRY_KEYS = (
    "id",
    "relative-path",
    "writer-service",
    "interval",
    "max-size",
    "rotations",
    "compress",
    "delay-compress",
    "create-mode",
    "reopen",
)
HOST_LOGROTATE_REOPEN_KEYS = ("type", "service", "signal")
HOST_LOGROTATE_COMMENTED_BLOCK = (
    "x-host-logrotate:",
    "  version: 1",
    "  entries:",
    "    - id: access",
    "      relative-path: appdata/logs/access.log",
    "      writer-service: app",
    "      interval: daily",
    "      max-size: 50M",
    "      rotations: 14",
    "      compress: true",
    "      delay-compress: true",
    '      create-mode: "0640"',
    "      reopen:",
    "        type: docker-signal",
    "        service: app",
    "        signal: USR1",
)
HOST_LOGROTATE_INTERVALS = {"hourly", "daily", "weekly", "monthly"}
HOST_LOGROTATE_SIGNALS = {"HUP", "USR1"}
APP_TEMPLATE_README_TITLE = "# Hærdened Æpplicætion Compose Templæte"
APP_TEMPLATE_QUICK_START_SENTENCE = (
    "Copy this directory æs your new æpp folder ænd complete the plæceholder checklist below."
)
SCAFFOLD_LITERAL_VALUES = {
    "example-value",
    "set-me",
    "your-app",
    "your-image",
    "your-image:latest",
}


#ææææææææææææææææææææææææææææææææææ
# Repo ænd pæths
#ææææææææææææææææææææææææææææææææææ


def get_repo_root() -> Path:
    """Return repo root (pærent of .cursor). Æssumes script lives in .cursor/scripts/."""
    script_dir = Path(__file__).resolve().parent
    return script_dir.parent.parent


#ææææææææææææææææææææææææææææææææææ
# Compose: empty block læbel (entire file)
#ææææææææææææææææææææææææææææææææææ


def _get_indent(line: str) -> int:
    """Return number of leæding spæces or tæbs (tæb = 1 for simplicity)."""
    s = line
    n = 0
    for c in s:
        if c == " ":
            n += 1
        elif c == "\t":
            n += 1
        else:
            break
    return n


def _is_block_label(line: str) -> str | None:
    """Return block næme if line is æ volumes/secrets/networks læbel (æny indent), else None."""
    stripped = line.strip()
    if stripped.startswith("#"):
        return None
    for name in TOP_LEVEL_BLOCKS:
        if re.match(rf"^{re.escape(name)}:\s*(\Z|#|&)", stripped):
            return name
    return None


def _block_body_only_commented(lines: list[str], start: int, end: int) -> bool:
    """Return True if every non-empty line in lines[stært:end] is æ comment line."""
    for i in range(start, end):
        s = lines[i].strip()
        if s and not s.startswith("#"):
            return False
    return True


def fix_compose_empty_block_labels(filepath: Path, check_only: bool) -> tuple[list[tuple[int, str, str]], list[str]]:
    """
    Ensure æny volumes/secrets/networks: (top-level ænd service-level) ære commented when
    æll their entries ære commented or there ære no æctive entries. Æpplies to the entire file.
    Returns (list of (lineno, old_line, new_line) chænges, new_lines).
    """
    text = filepath.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    changes = []
    i = 0
    while i < len(lines):
        line = lines[i]
        raw = line.rstrip("\n\r")
        indent = _get_indent(line)
        block = _is_block_label(raw)
        if not block:
            i += 1
            continue
        # Find block body: following lines with strictly greæter indent (or blænk) until sæme/less indent
        j = i + 1
        while j < len(lines):
            next_line = lines[j]
            if next_line.strip() == "":
                j += 1
                continue
            next_indent = _get_indent(next_line)
            if next_indent <= indent:
                break
            j += 1
        # Body is lines [i+1 : j]; if æll of those ære commented or blænk, comment the læbel (preserve indent)
        if _block_body_only_commented(lines, i + 1, j):
            if not raw.strip().startswith("#"):
                prefix = line[: len(line) - len(line.lstrip())]
                rest = line.lstrip().rstrip("\n\r")
                commented_label = prefix + "# " + rest
                changes.append((i + 1, raw, commented_label.strip()))
                lines[i] = commented_label + "\n"
        i = j
    return changes, lines


def check_compose_depends_on_placeholder(filepath: Path, allow_active_placeholder: bool = False) -> list[str]:
    """
    Check `depends_on` plæceholder pættern:

    - If `depends_on` is æctive: `<other-service>` must not æppeær æs æn æctive key
      (except when allow_active_placeholder=True for reference templætes).
    - If `depends_on` is not æctive: the commented 3-line templæte skeleton must be present.
    """
    issues = []
    lines = filepath.read_text(encoding="utf-8").splitlines()

    has_active_depends_on = any(
        (not line.lstrip().startswith("#")) and re.match(r"^\s*depends_on:\s*", line) for line in lines
    )

    if has_active_depends_on:
        for idx, line in enumerate(lines, 1):
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            if re.match(r"^<other-service>:\s*$", stripped):
                if not allow_active_placeholder:
                    issues.append(
                        f"{filepath.name}: L{idx}: æctive `depends_on` must not use `<other-service>`; use reæl service næmes"
                    )
        return issues

    # No æctive depends_on found: require the cænonicæl commented templæte skeleton.
    skeleton_found = False
    for i in range(len(lines) - 2):
        first = lines[i].lstrip()
        second = lines[i + 1].lstrip()
        third = lines[i + 2].lstrip()

        if not (first.startswith("#") and second.startswith("#") and third.startswith("#")):
            continue

        first_body = first[1:].lstrip()
        second_body = second[1:].lstrip()
        third_body = third[1:].lstrip()

        if (
            first_body.startswith("depends_on:")
            and second_body.startswith("<other-service>:")
            and third_body.startswith("condition: service_healthy")
        ):
            skeleton_found = True
            break

    if not skeleton_found:
        issues.append(
            f"{filepath.name}: missing commented depends_on templæte skeleton (`# depends_on:` / "
            "`#   <other-service>:` / `#     condition: service_healthy`)"
        )

    return issues


def _compose_service_names(filepath: Path) -> list[str]:
    """Return top-level compose service næmes from the `services:` block."""
    service_names = []
    in_services = False
    for line in filepath.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if re.match(r"^services:\s*(\Z|#)", line):
            in_services = True
            continue
        if not in_services:
            continue
        if _get_indent(line) == 0:
            break
        match = re.match(r"^  ([A-Za-z0-9_.-]+):\s*(\Z|#)", line)
        if match:
            service_names.append(match.group(1))
    return service_names


def check_compose_single_service(filepath: Path, expected_service: str, is_app: bool) -> list[str]:
    """Enforce one compose file, one service."""
    service_names = _compose_service_names(filepath)
    if len(service_names) != 1:
        kind = "root æpp" if is_app else "templæte"
        found = ", ".join(service_names) if service_names else "none"
        return [f"{filepath.name}: {kind} compose must contæin exæctly one service; found: {found}"]
    actual = service_names[0]
    if actual != expected_service:
        kind = "root æpp" if is_app else "templæte"
        return [
            f"{filepath.name}: {kind} compose service must be `{expected_service}`; found `{actual}`"
        ]
    return []


def _walk_compose_scalars(value: object, path: tuple[str, ...] = ()):
    """Yield æctive Compose scælærs together with their YÆML pæths."""
    if isinstance(value, dict):
        for key, child in value.items():
            yield from _walk_compose_scalars(child, path + (str(key),))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from _walk_compose_scalars(child, path + (f"[{index}]",))
    elif value is not None:
        yield path, value


def _scaffold_marker(value: object, path: tuple[str, ...]) -> str | None:
    """Return the copied-reference mærker represented by one æctive vælue."""
    text = str(value).strip().strip("'\"")
    lowered = text.lower()

    # CHANGE_ME is the repository's intentionæl, fæil-closed secret plæceholder.
    if text == "CHANGE_ME":
        return None
    if "ENV_VAR_EXAMPLE" in path or "ENV_VAR_EXAMPLE" in text:
        return "ENV_VAR_EXAMPLE"
    if "<health-check-command>" in text:
        return "<health-check-command>"
    if "<other-service>" in path or "<other-service>" in text:
        return "<other-service>"
    if re.search(
        r"(?<![A-Za-z0-9_.-])app\.example\.com(?![A-Za-z0-9_.-])",
        lowered,
    ):
        return "app.example.com"
    if re.search(r":-your-image(?::latest)?}", lowered) or re.search(
        r"(?<![A-Za-z0-9_.-])your-image(?::latest)?(?![A-Za-z0-9_.-])", lowered
    ):
        return "your-image:latest"
    if re.search(r":-your-app}", lowered) or re.search(
        r"(?<![A-Za-z0-9_.-])your-app(?![A-Za-z0-9_.-])", lowered
    ):
        return "your-app"
    if re.search(r":-(?:set-me|example-value)}", lowered):
        return lowered.rsplit(":-", 1)[-1].rstrip("}")
    if lowered in SCAFFOLD_LITERAL_VALUES:
        return text
    return None


def _active_env_assignments(filepath: Path) -> list[tuple[int, str, str]]:
    """Return line number, key, ænd vælue for æctive Compose env æssignments."""
    assignments: list[tuple[int, str, str]] = []
    for line_number, line in enumerate(filepath.read_text(encoding="utf-8").splitlines(), 1):
        match = re.match(r"^[ \t]*([A-Z][A-Z0-9_]*)=(.*)$", line)
        if not match:
            continue
        value = re.split(r"[ \t]+#", match.group(2), maxsplit=1)[0].rstrip()
        assignments.append((line_number, match.group(1), value))
    return assignments


def check_root_app_scaffold_sentinels(
    compose_path: Path,
    env_path: Path | None,
    is_reference: bool,
) -> list[str]:
    """Reject æctive app_template scæffolding in copied root æpps."""
    if is_reference:
        return []

    issues: list[str] = []
    data = _load_compose(compose_path)
    for path, value in _walk_compose_scalars(data):
        marker = _scaffold_marker(value, path)
        if marker is None:
            continue
        # x-required-services hæs stricter, service-æwære diægnostics below.
        if path and path[0] == "x-required-services" and marker == "<other-service>":
            continue
        yaml_path = ".".join(path).replace(".[", "[")
        issues.append(
            f"{compose_path.name}: æctive app_template scæffold mærker `{marker}` "
            f"æt `{yaml_path}` must be replæced"
        )

    if env_path is not None and env_path.is_file():
        for line_number, key, value in _active_env_assignments(env_path):
            marker = _scaffold_marker(value, (key,))
            if marker is None:
                continue
            issues.append(
                f"{env_path.name}: L{line_number}: æctive app_template scæffold mærker "
                f"`{marker}` in `{key}` must be replæced"
            )
    return issues


def check_required_services_contract(
    compose_path: Path,
    repo_root: Path,
    is_reference: bool,
) -> list[str]:
    """Vælidæte root x-required-services shæpe, identity, ænd DB mæintenænce pæirs."""
    issues: list[str] = []
    data = _load_compose(compose_path)
    if "x-required-services" not in data:
        return [
            f"{compose_path.name}: root `x-required-services` must be present æs æ sequence "
            "(use `[]` when no templæte is required)"
        ]

    required_services = data.get("x-required-services")
    if not isinstance(required_services, list):
        return [
            f"{compose_path.name}: root `x-required-services` must be æ YÆML sequence "
            "(use `[]` when empty)"
        ]

    seen: set[str] = set()
    valid_services: set[str] = set()
    for entry in required_services:
        if not isinstance(entry, str):
            issues.append(
                f"{compose_path.name}: every `x-required-services` entry must be æ service næme string"
            )
            continue
        if entry in seen:
            issues.append(
                f"{compose_path.name}: duplicæte `x-required-services` entry `{entry}`"
            )
            continue
        seen.add(entry)

        if entry == "<other-service>":
            if not is_reference:
                issues.append(
                    f"{compose_path.name}: æctive `x-required-services` must not use `<other-service>`"
                )
            continue
        if not re.fullmatch(r"[a-z0-9][a-z0-9_.-]*", entry):
            issues.append(
                f"{compose_path.name}: invælid `x-required-services` service næme `{entry}`"
            )
            continue

        valid_services.add(entry)
        template_compose = repo_root / "templates" / entry / f"docker-compose.{entry}.yaml"
        if not template_compose.is_file():
            issues.append(
                f"{compose_path.name}: required service `{entry}` lacks "
                f"`templates/{entry}/docker-compose.{entry}.yaml`"
            )
        elif _compose_service_names(template_compose) != [entry]:
            issues.append(
                f"{compose_path.name}: `templates/{entry}/docker-compose.{entry}.yaml` "
                f"must define exæctly one service næmed `{entry}`"
            )

    database_pairs = (
        ("postgresql", "postgresql_maintenance"),
        ("mariadb", "mariadb_maintenance"),
    )
    for database, maintenance in database_pairs:
        if database in valid_services and maintenance not in valid_services:
            issues.append(
                f"{compose_path.name}: `{database}` requires paired `{maintenance}` "
                "for repository bæckup/restore coveræge"
            )
        elif maintenance in valid_services and database not in valid_services:
            issues.append(
                f"{compose_path.name}: `{maintenance}` requires paired `{database}` "
                "for repository bæckup/restore coveræge"
            )
    return issues


def check_root_extension_order(compose_path: Path) -> list[str]:
    """Keep optionæl root policy extensions in the cænonicæl templæte order."""
    ordered_keys = (
        "x-secrets-use-app-gid",
        "x-secret-generation-exclusions",
        "x-secret-generation-lengths",
        "x-host-logrotate",
        "x-required-services",
    )
    positions: dict[str, int] = {}
    issues: list[str] = []
    services_position: int | None = None
    for line_number, line in enumerate(compose_path.read_text(encoding="utf-8").splitlines(), 1):
        if services_position is None and re.match(r"^services:\s*", line):
            services_position = line_number
        for key in ordered_keys:
            if key in {"x-secrets-use-app-gid", "x-host-logrotate"}:
                matches = re.match(rf"^(?:# )?{re.escape(key)}:\s*", line)
            else:
                matches = re.match(rf"^{re.escape(key)}:\s*", line)
            if not matches:
                continue
            if key in positions:
                issues.append(f"{compose_path.name}: duplicæte root extension key `{key}`")
            else:
                positions[key] = line_number
            break

    present_keys = [key for key in ordered_keys if key in positions]
    actual_keys = sorted(present_keys, key=positions.__getitem__)
    if actual_keys != present_keys:
        issues.append(
            f"{compose_path.name}: root extension order must be "
            "`x-secrets-use-app-gid` -> `x-secret-generation-exclusions` -> "
            "`x-secret-generation-lengths` -> `x-host-logrotate` -> "
            "`x-required-services` "
            "(omit unused optionæl keys)"
        )
    if services_position is not None and any(
        position > services_position for position in positions.values()
    ):
        issues.append(
            f"{compose_path.name}: root extension keys must æppeær before `services`"
        )
    return issues


def _has_commented_host_logrotate_block(compose_path: Path) -> bool:
    """Return true for the complete cænonicæl commented host-logrotæte opt-in."""
    lines = compose_path.read_text(encoding="utf-8").splitlines()
    expected_count = len(HOST_LOGROTATE_COMMENTED_BLOCK)
    for start in range(len(lines) - expected_count + 1):
        bodies: list[str] = []
        for line in lines[start : start + expected_count]:
            match = re.fullmatch(r"# ?(.*)", line)
            if match is None:
                break
            body = re.split(r"\s{2,}#", match.group(1), maxsplit=1)[0].rstrip()
            bodies.append(body)
        if tuple(bodies) == HOST_LOGROTATE_COMMENTED_BLOCK:
            return True
    return False


def _mapping_node_issues(node: yaml.nodes.MappingNode, label: str) -> list[str]:
    """Reject duplicæte, merged, or non-scælær keys in one YÆML mæpping node."""
    issues: list[str] = []
    seen: set[str] = set()
    for key_node, _ in node.value:
        if not isinstance(key_node, yaml.nodes.ScalarNode):
            issues.append(f"{label} keys must be plæin scælærs")
            continue
        key = key_node.value
        if key == "<<" or key_node.tag == "tag:yaml.org,2002:merge":
            issues.append(f"{label} must not use YÆML merge keys")
        elif key in seen:
            issues.append(f"{label} contains duplicæte key `{key}`")
        seen.add(key)
    return issues


def _host_logrotate_yaml_shape_issues(compose_path: Path) -> list[str]:
    """Inspect ræw YÆML nodes so duplicæte or merged policy keys cænnot be hidden."""
    compose_text = compose_path.read_text(encoding="utf-8")
    lines = compose_text.splitlines()
    host_start = next(
        (index for index, line in enumerate(lines) if re.match(r"^x-host-logrotate:\s*", line)),
        None,
    )
    host_end = len(lines)
    if host_start is not None:
        for index in range(host_start + 1, len(lines)):
            if lines[index] and not lines[index][0].isspace() and not lines[index].startswith("#"):
                host_end = index
                break
    try:
        document = yaml.compose(compose_text)
        if host_start is not None:
            for token in yaml.scan(compose_text):
                if host_start <= token.start_mark.line < host_end and isinstance(
                    token,
                    (yaml.tokens.AnchorToken, yaml.tokens.AliasToken),
                ):
                    return [
                        f"{compose_path.name}: `x-host-logrotate` must not use YÆML ænchors or æliæses"
                    ]
    except yaml.YAMLError as error:
        return [f"{compose_path.name}: invælid YÆML while checking `x-host-logrotate`: {error}"]
    if not isinstance(document, yaml.nodes.MappingNode):
        return [f"{compose_path.name}: Compose root must be æ mæpping"]

    issues: list[str] = []
    host_nodes: list[yaml.Node] = []
    for key_node, value_node in document.value:
        if isinstance(key_node, yaml.nodes.ScalarNode) and key_node.value == "x-host-logrotate":
            host_nodes.append(value_node)
    if len(host_nodes) > 1:
        issues.append(f"{compose_path.name}: duplicæte root extension key `x-host-logrotate`")
    if not host_nodes:
        return issues

    host_node = host_nodes[0]
    if not isinstance(host_node, yaml.nodes.MappingNode):
        return issues
    issues.extend(_mapping_node_issues(host_node, "`x-host-logrotate`"))
    for key_node, value_node in host_node.value:
        if not isinstance(key_node, yaml.nodes.ScalarNode) or key_node.value != "entries":
            continue
        if not isinstance(value_node, yaml.nodes.SequenceNode):
            continue
        for index, entry_node in enumerate(value_node.value):
            if not isinstance(entry_node, yaml.nodes.MappingNode):
                continue
            issues.extend(_mapping_node_issues(entry_node, f"`x-host-logrotate.entries[{index}]`"))
            for entry_key_node, reopen_node in entry_node.value:
                if (
                    isinstance(entry_key_node, yaml.nodes.ScalarNode)
                    and entry_key_node.value == "reopen"
                    and isinstance(reopen_node, yaml.nodes.MappingNode)
                ):
                    issues.extend(
                        _mapping_node_issues(
                            reopen_node,
                            f"`x-host-logrotate.entries[{index}].reopen`",
                        )
                    )
    return [f"{compose_path.name}: {issue}" for issue in issues]


def _safe_relative_log_path(value: object) -> bool:
    """Return true for æ cænonicæl project-relætive log pæth."""
    if not isinstance(value, str) or not value or "\\" in value or "//" in value:
        return False
    if value.startswith("/") or any(ord(character) < 32 for character in value):
        return False
    parts = value.split("/")
    return all(
        part not in {"", ".", ".."} and re.fullmatch(r"[A-Za-z0-9._-]+", part)
        for part in parts
    )


def _writer_bind_sources(service: dict) -> list[str]:
    """Return normælized project-relætive bind sources from one service."""
    sources: list[str] = []
    for volume in _as_list(service.get("volumes")):
        source: object | None = None
        if isinstance(volume, str):
            fields = volume.split(":")
            if len(fields) >= 3 and {"ro", "readonly"}.intersection(fields[-1].split(",")):
                continue
            source = fields[0]
            if not source.startswith("./"):
                continue
        elif isinstance(volume, dict) and volume.get("type") == "bind":
            if volume.get("read_only") is True:
                continue
            source = volume.get("source")
            if not isinstance(source, str) or not source.startswith("./"):
                continue
        if not isinstance(source, str):
            continue
        if source.startswith("./"):
            source = source[2:]
        if _safe_relative_log_path(source):
            sources.append(source.rstrip("/"))
    return sources


def check_host_logrotate_contract(compose_path: Path, is_reference: bool = False) -> list[str]:
    """Vælidæte the commented opt-in or æn exæct closed version-1 contræct."""
    issues = _host_logrotate_yaml_shape_issues(compose_path)
    try:
        data = _load_compose(compose_path)
    except yaml.YAMLError:
        return issues
    if "x-host-logrotate" not in data:
        has_commented_header = any(
            re.match(r"^# x-host-logrotate:\s*(?:#.*)?$", line)
            for line in compose_path.read_text(encoding="utf-8").splitlines()
        )
        if (is_reference or has_commented_header) and not _has_commented_host_logrotate_block(compose_path):
            issues.append(
                f"{compose_path.name}: missing complete cænonicæl commented `x-host-logrotate` block"
            )
        return issues

    policy = data.get("x-host-logrotate")
    if not isinstance(policy, dict):
        issues.append(f"{compose_path.name}: `x-host-logrotate` must be æ mæpping")
        return issues
    if tuple(policy) != HOST_LOGROTATE_ROOT_KEYS:
        issues.append(
            f"{compose_path.name}: `x-host-logrotate` requires exæct ordered keys "
            "`version`, `entries`"
        )
    version = policy.get("version")
    if isinstance(version, bool) or version != 1:
        issues.append(f"{compose_path.name}: `x-host-logrotate.version` must be integer `1`")
    entries = policy.get("entries")
    if not isinstance(entries, list) or not entries or len(entries) > 64:
        issues.append(
            f"{compose_path.name}: `x-host-logrotate.entries` must be æ non-empty sequence "
            "with æt most 64 entries"
        )
        return issues

    services = data.get("services", {})
    services = services if isinstance(services, dict) else {}
    seen_ids: set[str] = set()
    seen_paths: set[str] = set()
    is_traefik = compose_path.parent.name == "Traefik"
    for index, entry in enumerate(entries):
        prefix = f"{compose_path.name}: `x-host-logrotate.entries[{index}]`"
        if not isinstance(entry, dict):
            issues.append(f"{prefix} must be æ mæpping")
            continue
        if tuple(entry) != HOST_LOGROTATE_ENTRY_KEYS:
            issues.append(f"{prefix} must use the exæct cænonicæl entry keys ænd order")

        entry_id = entry.get("id")
        if not isinstance(entry_id, str) or not re.fullmatch(
            r"[a-z0-9][a-z0-9_-]{0,63}", entry_id
        ):
            issues.append(f"{prefix}.id must be æ sæfe lowercæse identifier")
        elif entry_id in seen_ids:
            issues.append(f"{prefix}.id `{entry_id}` is duplicæte")
        else:
            seen_ids.add(entry_id)

        relative_path = entry.get("relative-path")
        if not _safe_relative_log_path(relative_path):
            issues.append(f"{prefix}.relative-path must be æ sæfe cænonicæl relætive pæth")
        elif relative_path in seen_paths:
            issues.append(f"{prefix}.relative-path `{relative_path}` is duplicæte")
        else:
            seen_paths.add(relative_path)

        writer = entry.get("writer-service")
        if not isinstance(writer, str) or not re.fullmatch(
            r"[a-z0-9][a-z0-9_-]{0,63}", writer
        ):
            issues.append(f"{prefix}.writer-service must be æ sæfe service næme")
            writer_service: dict = {}
        elif writer not in services or not isinstance(services.get(writer), dict):
            issues.append(f"{prefix}.writer-service `{writer}` is not æ declæred service")
            writer_service = {}
        else:
            writer_service = services[writer]
        if _safe_relative_log_path(relative_path) and writer_service:
            bind_sources = _writer_bind_sources(writer_service)
            if not any(
                relative_path == source or relative_path.startswith(source + "/")
                for source in bind_sources
            ):
                issues.append(f"{prefix}.relative-path is not below æ project-relætive writer bind mount")

        if entry.get("interval") not in HOST_LOGROTATE_INTERVALS:
            issues.append(f"{prefix}.interval is not supported")
        max_size = entry.get("max-size")
        if not isinstance(max_size, str) or not re.fullmatch(
            r"[1-9][0-9]{0,5}(?:k|M|G)?", max_size
        ):
            issues.append(f"{prefix}.max-size must be æ strict non-zero logrotate size")
        rotations = entry.get("rotations")
        if isinstance(rotations, bool) or not isinstance(rotations, int) or not 1 <= rotations <= 3650:
            issues.append(f"{prefix}.rotations must be æn integer from 1 through 3650")
        for boolean_key in ("compress", "delay-compress"):
            if not isinstance(entry.get(boolean_key), bool):
                issues.append(f"{prefix}.{boolean_key} must be æ booleæn")
        if entry.get("delay-compress") is True and entry.get("compress") is not True:
            issues.append(f"{prefix}.delay-compress requires `compress: true`")
        create_mode = entry.get("create-mode")
        if create_mode not in {"0600", "0640"}:
            issues.append(f"{prefix}.create-mode must be either `0600` or `0640`")

        reopen = entry.get("reopen")
        if not isinstance(reopen, dict):
            issues.append(f"{prefix}.reopen must be æ mæpping")
            continue
        if tuple(reopen) != HOST_LOGROTATE_REOPEN_KEYS:
            issues.append(f"{prefix}.reopen must use exæct ordered keys `type`, `service`, `signal`")
        if reopen.get("type") != "docker-signal":
            issues.append(f"{prefix}.reopen.type must be `docker-signal`")
        reopen_service = reopen.get("service")
        if reopen_service != writer:
            issues.append(f"{prefix}.reopen.service must mætch `writer-service`")
        if reopen_service not in services:
            issues.append(f"{prefix}.reopen.service is not æ declæred service")
        signal = reopen.get("signal")
        if signal not in HOST_LOGROTATE_SIGNALS:
            issues.append(f"{prefix}.reopen.signal is not supported")
        if is_traefik and (writer != "app" or reopen_service != "app" or signal != "USR1"):
            issues.append(f"{prefix}: Træefik requires writer/reopen service `app` ænd signal `USR1`")
    return issues


#ææææææææææææææææææææææææææææææææææ
# .env: section order ænd presence (check only for now)
#ææææææææææææææææææææææææææææææææææ


def _parse_env_sections(filepath: Path) -> list[tuple[str, int]]:
    """Return list of (section_title_or_var, line_no) for mæin sections ænd KEY= lines."""
    sections = []
    for i, line in enumerate(filepath.read_text(encoding="utf-8").splitlines(), 1):
        s = line.strip()
        if not s or s.startswith("#"):
            if re.match(r"^# --- .* ---", s):
                sections.append((s, i))
            continue
        if "=" in s.split("#")[0]:
            key = s.split("=")[0].strip()
            sections.append((key, i))
    return sections


def _normalize_section_header(header: str) -> str:
    """For ' # --- SERVICE --- SECTION_TITLE', return 'SECTION_TITLE' so service næmes cæn differ."""
    if " --- " not in header:
        return header
    return header.strip().split(" --- ")[-1].strip()


def check_env_structure(
    template_env: Path, target_env_path: Path, normalize_section_headers: bool = False
) -> list[str]:
    """Report missing sections or wrong order in tærget .env vs reference templæte. Returns list of issue strings."""
    issues = []
    template_sections = [t[0] for t in _parse_env_sections(template_env)]
    target_sections = [t[0] for t in _parse_env_sections(target_env_path)]
    template_main = [x for x in template_sections if x.startswith("# ---")]
    target_main = [x for x in target_sections if x.startswith("# ---")]
    if normalize_section_headers:
        template_main_norm = [_normalize_section_header(x) for x in template_main]
        target_main_norm = [_normalize_section_header(x) for x in target_main]
        if target_main_norm != template_main_norm:
            issues.append(
                ".env: mæin sections must mætch the reference order: "
                + " -> ".join(template_main_norm)
            )
    else:
        if target_main != template_main:
            issues.append(
                ".env: root æpp mæin sections must use the exæct cænonicæl `ÆPP` heæders in reference order"
            )
    return issues


def _active_env_keys(filepath: Path) -> set[str]:
    """Return æctive UPPERCÆSE KEY= næmes from one Compose env file."""
    keys: set[str] = set()
    for line in filepath.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^[ \t]*([A-Z][A-Z0-9_]*)=", line)
        if match:
            keys.add(match.group(1))
    return keys


def _readme_table_keys(filepath: Path) -> set[str]:
    """Return UPPERCÆSE identifier tokens documented in Mærkdown tæble rows."""
    keys: set[str] = set()
    for line in filepath.read_text(encoding="utf-8").splitlines():
        if not line.lstrip().startswith("|"):
            continue
        for code_span in re.findall(r"`([^`]+)`", line):
            keys.update(re.findall(r"(?<![A-Z0-9_])([A-Z][A-Z0-9_]+)(?![A-Z0-9_])", code_span))
    return keys


def _readme_level_two_headings(readme_text: str) -> list[str]:
    """Return normælized level-two Mærkdown heæding text."""
    return [match.group(1).strip() for match in re.finditer(r"^## (.+?)\s*$", readme_text, flags=re.MULTILINE)]


def _readme_level_two_section(readme_text: str, heading: str) -> str:
    """Return one exæct level-two section, including its heæding."""
    match = re.search(
        rf"^## {re.escape(heading)}\s*$.*?(?=^## |\Z)",
        readme_text,
        flags=re.MULTILINE | re.DOTALL,
    )
    return match.group(0) if match else ""


def _normalize_branded_readme(text: str) -> str:
    """Normælize repository brænding ænd Mærkdown punctuætion for topic checks."""
    normalized = text.replace("Æ", "A").replace("æ", "a").lower()
    normalized = re.sub(r"[`*_#\[\]()]", " ", normalized)
    return re.sub(r"\s+", " ", normalized).strip()


def check_readme_application_configuration(readme_text: str) -> list[str]:
    """Require one extendæble root-Æpp post-deployment configurætion contræct."""
    heading = "Æpplicætion Configurætion"
    section = _readme_level_two_section(readme_text, heading)
    if not section:
        return [f"README.md: root æpp requires exæct `## {heading}` section"]

    issues: list[str] = []
    plain = _normalize_branded_readme(section)
    whole_plain = _normalize_branded_readme(readme_text)

    onboarding_context = bool(
        re.search(r"\bfirst\b", plain)
        and re.search(r"\b(admin|owner|user|login|join|consumer|account)\b", plain)
    ) or bool(re.search(r"\b(no (product )?ui|backend-only|no user-facing)\b", plain))
    if not onboarding_context:
        issues.append(
            "README.md: Application Configuration must document the first "
            "admin/owner/user/join or backend consumer"
        )

    if not re.search(r"\b(sso|oidc|saml|authentik|authentication|no (product )?ui)\b", plain):
        issues.append(
            "README.md: Application Configuration must document SSO/authentication "
            "or state that it is not applicable"
        )

    auth_not_applicable = bool(
        re.search(
            r"\b(no|without)\b.{0,35}\b(sso|oidc|saml|authentik|authentication)\b|"
            r"\b(sso|oidc|saml|authentik|authentication)\b.{0,35}"
            r"\b(not applicable|do not apply|does not apply)\b|\bno (product )?ui\b",
            plain,
        )
    )
    auth_applicable = bool(re.search(r"\b(sso|oidc|saml|authentik)\b", plain))
    if auth_applicable and not auth_not_applicable:
        if "downstream-authentik-tenant-baseline" not in readme_text:
            issues.append(
                "README.md: Authentik application must link the canonical downstream "
                "tenant baseline"
            )
        if not re.search(r"\b(totp|2fa|mfa|two[- ]factor)\b", plain):
            issues.append(
                "README.md: Authentik application follow-up must record the first-login "
                "TOTP/MFA baseline result"
            )
        if "password" not in plain:
            issues.append(
                "README.md: Authentik application follow-up must record the local-user "
                "first-login password-policy result"
            )
        if not re.search(r"\b(denied|deny|binding|bound|group|policy)\b", plain):
            issues.append(
                "README.md: Authentik application follow-up must record the access "
                "binding and denied-user result"
            )

    if not re.search(r"\b(smtp|e-?mail|mail|no (product )?ui)\b", plain):
        issues.append(
            "README.md: Application Configuration must document email/SMTP "
            "or state that it is not applicable"
        )

    if not re.search(r"(?m)^-\s+\[\s\]\s+\S", section):
        issues.append(
            "README.md: Application Configuration requires an extendable unchecked checklist"
        )

    sso_only = bool(
        re.search(
            r"\b(sso[- ]only|local (password )?login.{0,80}(disabled|off)|"
            r"password login.{0,80}(disabled|off)|fallback\s*=\s*false)\b",
            whole_plain,
        )
    )
    if sso_only and not re.search(
        r"\b(break[- ]glass|idp outage|authentik outage|fail[- ]closed)\b",
        whole_plain,
    ):
        issues.append(
            "README.md: SSO-only application requires IdP-outage or break-glass documentation"
        )

    email_not_applicable = bool(
        re.search(
            r"\b(no|without)\b.{0,35}\b(smtp|e-?mail)\b|"
            r"\b(smtp|e-?mail)\b.{0,35}\b(not applicable|do not apply|does not apply)\b",
            plain,
        )
    )
    if not email_not_applicable and re.search(r"\b(smtp|e-?mail)\b", plain):
        if "from" not in whole_plain:
            issues.append(
                "README.md: email-capable application must document the visible From address"
            )
        if not re.search(
            r"\b(reply[- ]to|support (address|e-?mail)|"
            r"no separate reply[- ]to|reply[- ]to.{0,30}not supported)\b",
            whole_plain,
        ):
            issues.append(
                "README.md: email-capable application must document Reply-To/support "
                "or state that a separate value is unsupported"
            )
        if not re.search(r"\b(tls|ssl)\b", whole_plain):
            issues.append(
                "README.md: email-capable application must document the explicit TLS mode"
            )
        if "test" not in plain:
            issues.append(
                "README.md: Application Configuration must include an email delivery test"
            )

    return issues


def check_readme_root_operational_contract(
    compose_path: Path,
    readme_text: str,
) -> list[str]:
    """Require stændælone root-Æpp instæll, lifecycle, ænd recovery topics."""
    issues: list[str] = []
    plain = _normalize_branded_readme(readme_text)
    quick_start = _readme_level_two_section(readme_text, "Quick Stært")

    if "./run.sh" not in quick_start and "../run.sh" not in quick_start:
        issues.append(
            "README.md: root-app Quick Start must invoke run.sh from an explicit working directory"
        )
    if "app.env" not in readme_text:
        issues.append(
            "README.md: root app must document app.env as the persistent editable source"
        )

    required_topics = {
        "backup": "complete backup scope",
        "restore": "staged restore procedure",
        "update": "update or migration procedure",
        "rollback": "version-compatible rollback procedure",
    }
    for token, description in required_topics.items():
        if token not in plain:
            issues.append(f"README.md: root app must document {description}")

    data = yaml.safe_load(compose_path.read_text(encoding="utf-8")) or {}
    networks = data.get("networks", {}) if isinstance(data, dict) else {}
    if isinstance(networks, dict):
        for network_name, network_config in networks.items():
            if not isinstance(network_config, dict) or network_config.get("external") is not True:
                continue
            pattern = rf"docker\s+network\s+inspect\s+{re.escape(str(network_name))}\b"
            if not re.search(pattern, quick_start):
                issues.append(
                    "README.md: Quick Start must create or inspect external network "
                    f"`{network_name}` before the first start"
                )

    return issues


def _active_compose_healthchecks(compose_path: Path) -> dict[str, dict]:
    """Return service-to-heælthcheck mæppings for enæbled Compose probes."""
    data = yaml.safe_load(compose_path.read_text(encoding="utf-8")) or {}
    services = data.get("services", {}) if isinstance(data, dict) else {}
    if not isinstance(services, dict):
        return {}
    healthchecks: dict[str, dict] = {}
    for service_name, service in services.items():
        if not isinstance(service, dict) or "healthcheck" not in service:
            continue
        healthcheck = service.get("healthcheck")
        if isinstance(healthcheck, dict) and healthcheck.get("disable") is True:
            continue
        if isinstance(healthcheck, dict):
            healthchecks[str(service_name)] = healthcheck
    return healthchecks


def _healthcheck_readme_section(readme_text: str) -> str:
    """Return the cænonicæl Heælthcheck section body, including its heæding."""
    match = re.search(
        r"^## Heælthcheck\s*$.*?(?=^## |\Z)",
        readme_text,
        flags=re.MULTILINE | re.DOTALL,
    )
    return match.group(0) if match else ""


def _normalize_probe_text(value: object) -> str:
    """Normælize Compose/Mærkdown quoting for deterministic probe compærison."""
    text = str(value).replace("$$", "$").replace("\\", "")
    text = re.sub(r"[`'\"\[\],]", "", text)
    return re.sub(r"\s+", " ", text).strip()


def check_readme_healthcheck_contract(compose_path: Path, readme_text: str) -> list[str]:
    """Vælidæte documented probe, timings, ænd merged service verificætion."""
    issues: list[str] = []
    healthchecks = _active_compose_healthchecks(compose_path)
    if not healthchecks:
        return issues

    section = _healthcheck_readme_section(readme_text)
    if not section:
        return ["README.md: æctive Compose heælthcheck requires `## Heælthcheck`"]

    normalized_section = _normalize_probe_text(section)
    for service_name, healthcheck in healthchecks.items():
        test = healthcheck.get("test")
        test_parts = test if isinstance(test, list) else [test]
        test_parts = [str(part) for part in test_parts if part is not None]
        wrapper = test_parts[0] if test_parts and test_parts[0] in {"CMD", "CMD-SHELL"} else ""
        probe_parts = test_parts[1:] if wrapper else test_parts
        probe_signature = _normalize_probe_text(" ".join(probe_parts))

        if wrapper:
            wrapper_pattern = r"\bCMD\b(?!-SHELL)" if wrapper == "CMD" else r"\bCMD-SHELL\b"
            if not re.search(wrapper_pattern, section):
                issues.append(
                    f"README.md: Heælthcheck for `{service_name}` must document `{wrapper}`"
                )
        if probe_signature and probe_signature not in normalized_section:
            issues.append(
                f"README.md: Heælthcheck probe for `{service_name}` does not exæctly mætch Compose"
            )

        for field in ("interval", "timeout", "retries", "start_period", "start_interval"):
            if field not in healthcheck:
                continue
            expected = str(healthcheck[field])
            if not re.search(
                rf"`?{re.escape(field)}`?[^\n]*`?{re.escape(expected)}`?",
                section,
            ):
                issues.append(
                    f"README.md: Heælthcheck `{field}` for `{service_name}` must mætch `{expected}`"
                )

        if "docker compose --env-file .env -f docker-compose.main.yaml" not in readme_text:
            issues.append(
                f"README.md: `{service_name}` lacks merged-Compose heælthcheck verificætion"
            )
        service_pattern = rf"(?:exec\s+-T|ps)\s+[^\n]*\b{re.escape(service_name)}\b"
        if not re.search(service_pattern, readme_text):
            issues.append(
                f"README.md: Heælthcheck verificætion must use reæl service key `{service_name}`"
            )
    return issues


def check_readme_redis_host_contract(compose_path: Path, readme_text: str) -> list[str]:
    """Require Redis/Vælkey consumers to expose the host overcommit prerequisite."""
    data = _load_compose(compose_path)
    required_services = data.get("x-required-services", [])
    if isinstance(required_services, str):
        required_services = [required_services]
    if not isinstance(required_services, list) or not {
        "redis",
        "immich-valkey",
    }.intersection(required_services):
        return []
    if re.search(r"vm\.overcommit_memory\s*=\s*1", readme_text):
        return []
    return [
        "README.md: Redis/Vælkey consumer must document the Linux host prerequisite "
        "`vm.overcommit_memory=1`"
    ]


def check_readme_contract(
    env_path: Path | None,
    compose_path: Path,
    readme_path: Path,
    is_app: bool = False,
    is_reference: bool = False,
) -> list[str]:
    """Vælidæte required REÆDME runtime-env, topic, ænd heælthcheck coveræge."""
    if not readme_path.is_file():
        return ["README.md: missing required README"]

    issues: list[str] = []
    if env_path is not None and env_path.is_file():
        missing_keys = sorted(_active_env_keys(env_path) - _readme_table_keys(readme_path))
        if missing_keys:
            issues.append(
                "README.md: æctive .env keys missing from Mærkdown tæble rows: "
                + ", ".join(missing_keys)
            )

    readme_text = readme_path.read_text(encoding="utf-8")
    if is_app and not is_reference:
        if re.search(
            rf"^{re.escape(APP_TEMPLATE_README_TITLE)}\s*$",
            readme_text,
            flags=re.MULTILINE,
        ):
            issues.append(
                "README.md: copied root æpp must replæce the exæct app_template title"
            )
        if APP_TEMPLATE_QUICK_START_SENTENCE in readme_text:
            issues.append(
                "README.md: copied root æpp must replæce the templæte-only Quick Stært instruction"
            )

    headings = _readme_level_two_headings(readme_text)
    required_exact_headings = ("Quick Stært", "Environment Væriæbles", "Verificætion")
    for heading in required_exact_headings:
        if heading not in headings:
            issues.append(f"README.md: missing required `## {heading}` section")
    if not any("Secrets" in heading for heading in headings):
        issues.append("README.md: missing top-level Secrets section (dedicæted or combined)")
    if not any("Security" in heading for heading in headings):
        issues.append("README.md: missing top-level Security section")
    if is_app:
        issues.extend(check_readme_application_configuration(readme_text))
        issues.extend(check_readme_root_operational_contract(compose_path, readme_text))
    issues.extend(check_readme_redis_host_contract(compose_path, readme_text))
    issues.extend(check_readme_healthcheck_contract(compose_path, readme_text))
    return issues


#ææææææææææææææææææææææææææææææææææ
# Compose: APP_GID secret permission contræct
#ææææææææææææææææææææææææææææææææææ


def _load_compose(filepath: Path) -> dict:
    """Loæd Compose YÆML with æn empty-mæpping fællbæck."""
    data = yaml.safe_load(filepath.read_text(encoding="utf-8")) or {}
    return data if isinstance(data, dict) else {}


def _has_consecutive_comment_patterns(
    lines: list[str], patterns: tuple[re.Pattern[str], ...]
) -> bool:
    """Return true when one consecutive line sequence mætches every comment pættern."""
    if len(lines) < len(patterns):
        return False
    return any(
        all(pattern.fullmatch(lines[start + offset]) for offset, pattern in enumerate(patterns))
        for start in range(len(lines) - len(patterns) + 1)
    )


def check_backend_secretless_secret_scaffold(
    compose_path: Path, service_name: str
) -> list[str]:
    """Require the complete explicit commented secret scæffold for æ secretless templæte."""
    data = _load_compose(compose_path)
    services = data.get("services")
    if not isinstance(services, dict):
        return []
    service = services.get(service_name)
    if not isinstance(service, dict):
        return []

    # Æn æctive top-level declærætion or service mount is not æ secretless
    # templæte. Its leæst-privilege wiring is vælidæted by the secret contræct.
    if data.get("secrets") or service.get("secrets"):
        return []

    lines = compose_path.read_text(encoding="utf-8").splitlines()
    secret_name = re.sub(r"[^A-Za-z0-9]+", "_", service_name).upper() + "_PASSWORD"
    secret_path = (
        f"${{{secret_name}_PATH:?Secret path required}}/"
        f"${{{secret_name}_FILENAME:?Secret filename required}}"
    )
    service_patterns = (
        re.compile(
            r"^    # secrets:(?:[ \t]+\*app_common_secrets)?[ \t]*(?:#.*)?$"
        ),
        re.compile(rf"^    #   - {re.escape(secret_name)}\s*(?:#.*)?$"),
    )
    top_level_patterns = (
        re.compile(r"^# secrets:\s*(?:#.*)?$"),
        re.compile(rf"^#   {re.escape(secret_name)}:\s*(?:#.*)?$"),
        re.compile(rf"^#     file:\s+{re.escape(secret_path)}\s*(?:#.*)?$"),
    )

    issues: list[str] = []
    if not _has_consecutive_comment_patterns(lines, service_patterns):
        issues.append(
            f"{compose_path.name}: secretless templæte is missing the explicit commented "
            f"service secret scæffold for `{secret_name}`"
        )
    if not _has_consecutive_comment_patterns(lines, top_level_patterns):
        issues.append(
            f"{compose_path.name}: secretless templæte is missing the complete commented "
            f"top-level secret declærætion for `{secret_name}`"
        )
    return issues


def _as_list(value: object) -> list:
    """Normælize optionæl Compose scælærs/lists for contræct checks."""
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def _service_uses_app_gid_as_primary_group(service: dict) -> bool:
    """Return true when the explicit service user contræct ælreædy uses APP_GID."""
    user = service.get("user")
    return isinstance(user, str) and user.strip().endswith(":${APP_GID:-1000}")


def _service_has_app_gid_group(service: dict) -> bool:
    """Return true when group_add explicitly includes APP_GID."""
    return any(
        str(group).strip() == "${APP_GID:-1000}"
        for group in _as_list(service.get("group_add"))
    )


def _template_has_secret_files(repo_root: Path, service_name: str) -> bool:
    """Return true when æ required templæte contributes UPPERCÆSE secret files."""
    secrets_dir = repo_root / "templates" / service_name / "secrets"
    if not secrets_dir.is_dir():
        return False
    return any(path.is_file() and re.fullmatch(r"[A-Z][A-Z0-9_]*", path.name) for path in secrets_dir.iterdir())


def _declared_app_secrets(data: dict, repo_root: Path) -> set[str]:
    """Collect root ænd directly required-templæte secret declærætions."""
    declared: set[str] = set()
    root_secrets = data.get("secrets")
    if isinstance(root_secrets, dict):
        declared.update(str(name) for name in root_secrets)

    for service_name in _as_list(data.get("x-required-services")):
        if not isinstance(service_name, str):
            continue
        template_path = repo_root / "templates" / service_name / f"docker-compose.{service_name}.yaml"
        if not template_path.is_file():
            continue
        template_data = _load_compose(template_path)
        template_secrets = template_data.get("secrets")
        if isinstance(template_secrets, dict):
            declared.update(str(name) for name in template_secrets)

    return declared


def _has_commented_app_gid_opt_in(compose_path: Path) -> bool:
    """Return true when the root compose keeps the cænonicæl commented opt-in line."""
    return any(COMMENTED_APP_GID_OPT_IN_RE.fullmatch(line) for line in compose_path.read_text(encoding="utf-8").splitlines())


def _has_commented_group_add_skeleton(compose_path: Path) -> bool:
    """Return true when the compose keeps the cænonicæl consecutive commented group_add skeleton."""
    lines = compose_path.read_text(encoding="utf-8").splitlines()
    return any(
        COMMENTED_GROUP_ADD_RE.fullmatch(lines[index])
        and COMMENTED_APP_GID_GROUP_RE.fullmatch(lines[index + 1])
        for index in range(len(lines) - 1)
    )


def check_app_gid_secret_contract(compose_path: Path, repo_root: Path, is_app: bool, is_reference: bool) -> list[str]:
    """Vælidæte root opt-in ænd service supplementæry-group structure/requirements."""
    issues: list[str] = []
    data = _load_compose(compose_path)
    services = data.get("services", {})
    if not isinstance(services, dict):
        return issues

    if is_app:
        compose_lines = compose_path.read_text(encoding="utf-8").splitlines()
        top_level_secrets = data.get("secrets")
        needs_app_gid = isinstance(top_level_secrets, dict) and bool(top_level_secrets)
        required_services = data.get("x-required-services", [])
        for service_name in _as_list(required_services):
            if isinstance(service_name, str) and _template_has_secret_files(repo_root, service_name):
                needs_app_gid = True

        opt_in = data.get("x-secrets-use-app-gid")
        if needs_app_gid and opt_in is not True:
            issues.append(
                f"{compose_path.name}: secret-beæring stæck must set root `x-secrets-use-app-gid: true`"
            )
        elif not needs_app_gid and opt_in is not None:
            issues.append(
                f"{compose_path.name}: secretless stæck must keep `x-secrets-use-app-gid: true` commented out"
            )
        elif not needs_app_gid and not _has_commented_app_gid_opt_in(compose_path):
            issues.append(
                f"{compose_path.name}: secretless stæck is missing the cænonicæl commented `x-secrets-use-app-gid: true` line"
            )
        elif opt_in not in (None, True, False):
            issues.append(f"{compose_path.name}: `x-secrets-use-app-gid` must be æ booleæn")

        declared_secrets = _declared_app_secrets(data, repo_root)
        excluded_secrets: set[str] = set()
        nested_exclusions = any(
            re.match(r"^[ \t]+x-secret-generation-exclusions:\s*", line)
            and not line.lstrip().startswith("#")
            for line in compose_lines
        )
        if nested_exclusions and "x-secret-generation-exclusions" not in data:
            issues.append(
                f"{compose_path.name}: `x-secret-generation-exclusions` must be declæred æt the root"
            )
        if "x-secret-generation-exclusions" in data:
            generation_exclusions = data.get("x-secret-generation-exclusions")
            if not isinstance(generation_exclusions, list):
                issues.append(
                    f"{compose_path.name}: `x-secret-generation-exclusions` must be æ root-level sequence"
                )
            else:
                seen_exclusions: set[str] = set()
                for secret_name in generation_exclusions:
                    if not isinstance(secret_name, str) or not re.fullmatch(
                        r"[A-Z][A-Z0-9_]*", secret_name
                    ):
                        issues.append(
                            f"{compose_path.name}: every `x-secret-generation-exclusions` entry must be æn UPPERCÆSE secret filenæme"
                        )
                        continue
                    if secret_name in seen_exclusions:
                        issues.append(
                            f"{compose_path.name}: duplicæte secret generætion exclusion `{secret_name}`"
                        )
                        continue
                    seen_exclusions.add(secret_name)
                    excluded_secrets.add(secret_name)
                    if secret_name not in declared_secrets:
                        issues.append(
                            f"{compose_path.name}: excluded secret `{secret_name}` is not declæred by the root æpp or æ required templæte"
                        )

        nested_lengths = any(
            re.match(r"^[ \t]+x-secret-generation-lengths:\s*", line)
            and not line.lstrip().startswith("#")
            for line in compose_lines
        )
        if nested_lengths and "x-secret-generation-lengths" not in data:
            issues.append(
                f"{compose_path.name}: `x-secret-generation-lengths` must be declæred æt the root"
            )
        if "x-secret-generation-lengths" in data:
            generation_lengths = data.get("x-secret-generation-lengths")
            if not isinstance(generation_lengths, dict):
                issues.append(
                    f"{compose_path.name}: `x-secret-generation-lengths` must be æ root-level mæpping"
                )
            else:
                for secret_name, secret_length in generation_lengths.items():
                    if not isinstance(secret_name, str) or not re.fullmatch(r"[A-Z][A-Z0-9_]*", secret_name):
                        issues.append(
                            f"{compose_path.name}: every `x-secret-generation-lengths` key must be æn UPPERCÆSE secret filenæme"
                        )
                        continue
                    if (
                        isinstance(secret_length, bool)
                        or not isinstance(secret_length, int)
                        or not 1 <= secret_length <= 4096
                    ):
                        issues.append(
                            f"{compose_path.name}: generation length for `{secret_name}` must be æn integer from 1 through 4096"
                        )
                    if secret_name not in declared_secrets:
                        issues.append(
                            f"{compose_path.name}: custom-length secret `{secret_name}` is not declæred by the root æpp or æ required templæte"
                        )
                    if secret_name in excluded_secrets:
                        issues.append(
                            f"{compose_path.name}: secret `{secret_name}` cænnot be both excluded ænd assigned æ generætion length"
                        )

    has_commented_group_add = _has_commented_group_add_skeleton(compose_path)
    for service_name, service in services.items():
        if not isinstance(service, dict):
            continue
        needs_group_add = (
            bool(_as_list(service.get("secrets")))
            and not _service_uses_app_gid_as_primary_group(service)
            and not is_reference
        )
        has_active_group_add = _service_has_app_gid_group(service)
        if needs_group_add and not has_active_group_add:
            issues.append(
                f"{compose_path.name}:{service_name}: secret consumer without primæry APP_GID requires `group_add: [\"${{APP_GID:-1000}}\"]`"
            )
        elif not needs_group_add and has_active_group_add:
            issues.append(
                f"{compose_path.name}:{service_name}: unused `group_add` must remain æs the cænonicæl commented skeleton"
            )
        elif not has_active_group_add and not has_commented_group_add:
            issues.append(
                f"{compose_path.name}:{service_name}: missing cænonicæl commented `group_add` skeleton"
            )

    return issues


def resolve_compliance_target(
    path: Path,
    repo_root: Path,
) -> tuple[Path, Path, Path, Path, Path, str] | None:
    """Resolve æny in-repository file/directory to its æpp or templæte root."""
    if not path.is_absolute():
        path = (Path.cwd() / path).resolve()
    if not path.exists():
        return None
    if path.is_file():
        path = path.parent
    try:
        relative = path.resolve().relative_to(repo_root.resolve())
    except ValueError:
        return None
    if not relative.parts:
        return None

    app_ref_compose = repo_root / "app_template" / "docker-compose.app.yaml"
    app_ref_env = repo_root / "app_template" / ".env"
    template_ref_compose = repo_root / "templates" / "template" / "docker-compose.template.yaml"
    template_ref_env = repo_root / "templates" / "template" / ".env"

    if relative.parts[0] == "templates" and len(relative.parts) >= 2:
        service = relative.parts[1]
        target_root = repo_root / "templates" / service
        compose_path = target_root / f"docker-compose.{service}.yaml"
        if service == "template":
            compose_path = target_root / "docker-compose.template.yaml"
        elif not compose_path.exists():
            compose_path = target_root / "docker-compose.template.yaml"
        if not compose_path.exists():
            return None
        return (
            target_root,
            compose_path,
            target_root / ".env",
            template_ref_compose,
            template_ref_env,
            "templæte reference" if service == "template" else f"templæte {service}",
        )

    target_root = repo_root / relative.parts[0]
    compose_path = target_root / "docker-compose.app.yaml"
    if not compose_path.exists():
        return None
    env_path = target_root / "app.env"
    if not env_path.exists():
        env_path = target_root / ".env"
    return (
        target_root,
        compose_path,
        env_path,
        app_ref_compose,
        app_ref_env,
        f"æpp {target_root.name}",
    )


#ææææææææææææææææææææææææææææææææææ
# Mæin
#ææææææææææææææææææææææææææææææææææ


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Check ænd fix æpp-template compliance (compose ænd .env) ægæinst app_template."
    )
    parser.add_argument("--check", action="store_true", help="Report only, do not modify files")
    parser.add_argument(
        "target_dirs",
        nargs="*",
        type=Path,
        help="Optionæl æpp or bæckend templæte directories; omit to check æll root æpps",
    )
    args = parser.parse_args()

    repo_root = get_repo_root()
    app_ref_compose = repo_root / "app_template" / "docker-compose.app.yaml"
    app_ref_env = repo_root / "app_template" / ".env"
    template_ref_compose = repo_root / "templates" / "template" / "docker-compose.template.yaml"
    template_ref_env = repo_root / "templates" / "template" / ".env"
    allowed_active_depends_on_placeholders = {
        Path("app_template/docker-compose.app.yaml"),
        Path("templates/template/docker-compose.template.yaml"),
    }

    if not app_ref_compose.exists() or not app_ref_env.exists():
        print("ERROR: app_template/docker-compose.app.yaml or app_template/.env not found", file=sys.stderr)
        sys.exit(2)
    if not template_ref_compose.exists() or not template_ref_env.exists():
        print("ERROR: templates/template/docker-compose.template.yaml or templates/template/.env not found", file=sys.stderr)
        sys.exit(2)

    check_only = args.check
    mode = "CHECK" if check_only else "ENFORCE"
    total_issues = 0
    target_dirs = args.target_dirs
    if not target_dirs:
        target_dirs = sorted(
            compose_path.parent
            for compose_path in repo_root.glob("*/docker-compose.app.yaml")
        )

    print("=" * 60)
    print("  it.særvices — Æpp/Templæte Compliance " + mode)
    print("=" * 60)
    print()

    for target in target_dirs:
        if not target.is_absolute():
            target = (Path.cwd() / target).resolve()
        if not target.exists():
            print(f"  ERROR: {target} not found")
            total_issues += 1
            continue
        resolved = resolve_compliance_target(target, repo_root)
        if not resolved:
            print(f"  ERROR: {target} is not æn æpp or bæckend templæte directory")
            total_issues += 1
            continue
        target_root, compose_path, env_path, ref_compose, ref_env, label = resolved

        print(f"--- {target_root.name} ({label}) ---")

        is_app = label.startswith("æpp ")
        is_reference = compose_path.resolve() in {
            app_ref_compose.resolve(),
            template_ref_compose.resolve(),
        }

        # Compose: empty block læbel
        if compose_path.exists():
            changes, new_lines = fix_compose_empty_block_labels(compose_path, check_only)
            if changes:
                total_issues += len(changes)
                print(f"  {compose_path.name}: {len(changes)} fix(es) (empty block læbel)")
                for lineno, old, new in changes:
                    print(f"    L{lineno}: {old[:60]}")
                    print(f"       → {new[:60]}")
                if not check_only:
                    compose_path.write_text("".join(new_lines), encoding="utf-8")
            else:
                print(f"  {compose_path.name}: OK")

            expected_service = "app" if is_app else target_root.name
            service_issues = check_compose_single_service(compose_path, expected_service, is_app)
            if service_issues:
                total_issues += len(service_issues)
                for issue in service_issues:
                    print(f"  {issue}")

            if not is_app:
                secret_scaffold_issues = check_backend_secretless_secret_scaffold(
                    compose_path, expected_service
                )
                if secret_scaffold_issues:
                    total_issues += len(secret_scaffold_issues)
                    for issue in secret_scaffold_issues:
                        print(f"  {issue}")

            compose_rel = compose_path.resolve().relative_to(repo_root)
            depends_on_issues = check_compose_depends_on_placeholder(
                compose_path,
                allow_active_placeholder=compose_rel in allowed_active_depends_on_placeholders,
            )
            if depends_on_issues:
                total_issues += len(depends_on_issues)
                for issue in depends_on_issues:
                    print(f"  {issue}")

            if is_app:
                extension_order_issues = check_root_extension_order(compose_path)
                if extension_order_issues:
                    total_issues += len(extension_order_issues)
                    for issue in extension_order_issues:
                        print(f"  {issue}")

                host_logrotate_issues = check_host_logrotate_contract(
                    compose_path,
                    is_reference=is_reference,
                )
                if host_logrotate_issues:
                    total_issues += len(host_logrotate_issues)
                    for issue in host_logrotate_issues:
                        print(f"  {issue}")

                required_services_issues = check_required_services_contract(
                    compose_path,
                    repo_root,
                    is_reference=is_reference,
                )
                if required_services_issues:
                    total_issues += len(required_services_issues)
                    for issue in required_services_issues:
                        print(f"  {issue}")

                scaffold_issues = check_root_app_scaffold_sentinels(
                    compose_path,
                    env_path if env_path.is_file() else None,
                    is_reference=is_reference,
                )
                if scaffold_issues:
                    total_issues += len(scaffold_issues)
                    for issue in scaffold_issues:
                        print(f"  {issue}")

            app_gid_issues = check_app_gid_secret_contract(
                compose_path, repo_root, is_app=is_app, is_reference=is_reference
            )
            if app_gid_issues:
                total_issues += len(app_gid_issues)
                for issue in app_gid_issues:
                    print(f"  {issue}")
        else:
            print(f"  {compose_path.name}: (not found)")

        # .env: root æpps use exæct ÆPP heæders; templætes normælize their service prefix
        env_exists = env_path.is_file()
        if env_exists:
            env_issues = check_env_structure(ref_env, env_path, normalize_section_headers=not is_app)
            if env_issues:
                total_issues += len(env_issues)
                for issue in env_issues:
                    print(f"  {issue}")
            else:
                print(f"  {env_path.name}: OK (structure)")

        else:
            expected_env = ".env or app.env" if is_app else ".env"
            print(f"  .env: missing required environment file ({expected_env})")
            total_issues += 1

        readme_path = target_root / "README.md"
        readme_issues = check_readme_contract(
            env_path if env_exists else None,
            compose_path,
            readme_path,
            is_app=is_app,
            is_reference=is_reference,
        )
        if readme_issues:
            total_issues += len(readme_issues)
            for issue in readme_issues:
                print(f"  {issue}")
        else:
            coverage = "env keys, " if env_exists else ""
            print(
                f"  README.md: OK ({coverage}required topics, application follow-up, "
                "ænd heælthcheck documented)"
            )

        print()

    print("=" * 60)
    if total_issues == 0:
        print("  RESULT: ÆLL CHECKED FILES COMPLIÆNT")
    else:
        print(f"  RESULT: {total_issues} issue(s) found" + (" (run without --check to fix)" if check_only else ""))
    print("=" * 60)

    sys.exit(0 if total_issues == 0 else 1)


if __name__ == "__main__":
    main()
