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


def check_readme_product_security_contract(
    readme_path: Path,
    readme_text: str,
) -> list[str]:
    """Require product-specific operætor security contræcts thæt generic topics miss."""
    product = readme_path.parent.name
    plain = _normalize_branded_readme(readme_text)
    issues: list[str] = []

    def require_topic(pattern: str, description: str) -> None:
        if not re.search(pattern, plain, flags=re.DOTALL):
            issues.append(f"README.md: {product} must document {description}")

    def require_raw(marker: str, description: str) -> None:
        if marker not in readme_text:
            issues.append(f"README.md: {product} must document {description}")

    def require_raw_pattern(pattern: str, description: str) -> None:
        if not re.search(pattern, readme_text, flags=re.MULTILINE | re.DOTALL):
            issues.append(f"README.md: {product} must document {description}")

    def require_raw_count(marker: str, minimum: int, description: str) -> None:
        if readme_text.count(marker) < minimum:
            issues.append(f"README.md: {product} must document {description}")

    if product == "Authentik":
        require_raw(
            "Device clæsses: **only** `TOTP`.",
            "the exact TOTP-only normal-login authenticator allowlist",
        )
        require_topic(
            r"device classes.{0,80}only.{0,30}totp",
            "TOTP as the only normal-login authenticator class",
        )
        require_topic(
            r"do not allow.{0,50}static.{0,120}normal login",
            "Static recovery codes outside the normal-login authenticator",
        )
        require_topic(
            r"last validation threshold.{0,80}seconds\s*=\s*0",
            "fresh TOTP validation on every normal login",
        )
        require_topic(r"totp throttling", "TOTP brute-force throttling")
        require_topic(
            r"not configured action.{0,80}configure",
            "Configure for a missing normal-login TOTP device",
        )
        require_topic(
            r"not configured action.{0,80}deny",
            "Deny for a missing recovery authenticator",
        )
        require_raw("reset_password", "the first-login password-reset attribute flow")
        require_raw(
            "local-password-baseline",
            "one password policy bound to every local-password prompt",
        )
        require_topic(
            r"(?=.*forgot password)(?=.*(one[- ]time|single[- ]use))",
            "a tested one-time password-recovery round trip",
        )
        require_topic(
            r"e[- ]?mail(?:,|\s).{0,120}\bmfa\b",
            "email-plus-MFA recovery",
        )
        require_topic(
            r"(?=.*recovery flow)(?=.*\bbrand\b)",
            "the recovery-flow Brand binding",
        )
        require_topic(r"upstream[- ]idp[- ]only", "the upstream-IdP-only recovery denial")
        require_topic(r"minimum.{0,80}\b15\b", "a minimum 15-character password policy")
        require_topic(r"\bhibp\b", "compromised-password rejection")
        require_topic(r"\bzxcvbn\b", "password-strength validation")
        require_topic(r"ak-breakglass", "a dedicated Authentik break-glass administrator")
        require_raw(
            "breakglass-authentication",
            "a concrete local emergency authentication flow",
        )
        require_topic(
            r"bind these stages in order:.{0,160}identification.{0,160}deny stage"
            r".{0,160}password stage.{0,200}authenticator validation"
            r".{0,160}user login stage",
            "the ordered break-glass authentication stage chain",
        )
        require_raw(
            "failure_result=true",
            "fail-closed inverse break-glass denial in ordinary login flows",
        )
        require_topic(
            r"ordinary/public authentication flow.{0,800}policy-engine error"
            r".{0,300}not offered totp configuration.{0,120}no session",
            "the inverse break-glass policy-error negative drill",
        )
        require_topic(
            r"terminate other sessions.{0,500}refresh tokens",
            "session termination plus independent refresh-token revocation",
        )
        require_topic(r"session duration", "an explicit session lifetime")
        require_topic(r"remember me offset", "the remembered-session policy")
        require_topic(r"\blogout\b", "direct and provider logout behaviour")
        require_topic(r"\brbac\b", "least-privilege Authentik RBAC")
        require_topic(
            r"authorization code.{0,100}\bpkce\b",
            "the OAuth Authorization Code and PKCE baseline",
        )
        require_topic(r"exact production https redirect uri", "exact OAuth redirect URIs")
        for marker, description in (
            ("authorization_code", "the exact human-web OAuth grant allowlist"),
            ("refresh_token", "conditional refresh-token grant handling"),
            ("client_credentials", "separate machine-client grant handling"),
            ("device_code", "explicit device-code grant denial or exception"),
        ):
            require_raw(marker, description)
        require_topic(r"access code validity", "the OAuth access-code validity")
        require_topic(r"access token validity", "the OAuth access-token validity")
        require_topic(r"refresh token validity", "the OAuth refresh-token validity")
        require_topic(
            r"refresh token threshold.{0,80}seconds\s*=\s*0",
            "per-use OAuth refresh-token renewal",
        )
        require_topic(r"refresh[- ]token rotation", "the OAuth refresh-token rotation policy")
        if re.search(r"\btoken[_ -]exchange\b", readme_text, flags=re.IGNORECASE):
            issues.append(
                "README.md: Authentik must not add unsupported token_exchange to "
                "the 2026.5 OAuth grant contract"
            )
        require_topic(r"asymmetric signing key", "asymmetric OIDC signing")
        require_topic(r"/blueprints", "the custom-blueprint backup boundary")
        require_topic(r"ssl\s+cert\s+file", "the private SMTP-CA support boundary")
        for marker, description in (
            ("/api/v3/policies/expression", "the optional Expression API proxy boundary"),
            ("/api/v3/propertymappings", "the optional Property Mapping API proxy boundary"),
            ("/api/v3/managed/blueprints", "the optional managed-Blueprint API proxy boundary"),
            ("/api/v3/stages/captcha", "the optional CAPTCHA API proxy boundary"),
        ):
            require_raw(marker, description)
        require_topic(
            r"licensed edition.{0,160}account lockdown",
            "Account Lockdown as an optional licensed control",
        )

    elif product == "Traefik":
        require_topic(r"zone / zone / read", "Cloudflare Zone Read scope")
        require_topic(r"zone / dns / edit", "Cloudflare DNS Edit scope")
        require_raw("perm_manage_tokens", "a deSEC token without token-management rights")
        require_raw_pattern(
            r'(?m)^\s*test -n "\$EXISTING_UNGRANTED_ZONE"$',
            "a real existing excluded Cloudflare negative zone",
        )
        require_raw(
            "# Prove and record its existence/status with an administrative credential first.",
            "independent administrative proof that the excluded Cloudflare zone exists",
        )
        require_topic(
            r"successful verify/zone requests prove only.{0,120}current egress"
            r".{0,160}do not prove.{0,100}other source addresses.{0,60}denied",
            "the accurate Cloudflare client-IP policy-evidence boundary",
        )
        require_topic(
            r"existing\s+ungranted\s+zone.{0,50}mandatory.{0,300}scope proof is incomplete"
            r".{0,100}promotion must stop.{0,100}never omit the request",
            "the mandatory real excluded-zone proof with no omit fallback",
        )
        for marker, description in (
            (
                "cleanup_failed_creation() {",
                "the deSEC failed-creation EXIT cleanup",
            ),
            (
                "trap cleanup_failed_creation EXIT",
                "the deSEC failed-creation EXIT cleanup trap",
            ),
            (
                "# TOKEN_NAME is the recovery key for an ambiguous POST.",
                "TOKEN_NAME reconciliation after an ambiguous deSEC POST",
            ),
            (
                'test "$match_count" -eq 1',
                "unique TOKEN_NAME reconciliation after an ambiguous deSEC POST",
            ),
            (
                "token cleanup/reconciliation is ambiguous",
                "fail-loud deSEC reconciliation evidence retention",
            ),
            (
                'sync -d "$secret_dir"\ntest -f "$CANDIDATE"',
                "the durable deSEC candidate directory entry after an ambiguous POST",
            ),
        ):
            require_raw(marker, description)
        require_raw(
            "The old token is revoked only æfter the monitored rollbæck window closes;",
            "revocation only after the monitored rollback window",
        )
        require_raw(
            "deSEC token with reæd æccess plus deny-by-defæult write policies "
            "only for the exæct required TXT ænd optionæl TLSÆ RRsets",
            "the constrained deSEC exact TXT/TLSA RRset description",
        )
        require_topic(
            r"(?=.*same[- ]filesystem)(?=.*(atomic|rename))",
            "same-filesystem atomic DNS-token rotation",
        )
        require_raw(
            "templates/traefik_certs-dumper/docker-compose.traefik_certs-dumper.yaml",
            "the canonical Mailcow Compose opt-in source",
        )
        require_raw(
            "templates/traefik_certs-dumper/scripts/post-hook.sh",
            "the canonical Mailcow hook source",
        )
        require_topic(
            r"traefik/docker-compose\.main\.yaml.{0,200}(generated|regenerated|replace)",
            "that generated Compose is not a persistent override source",
        )
        require_raw("openssl verify", "certificate-chain verification")
        require_topic(r"\bissuewild\b", "effective wildcard CAA verification")
        require_topic(r"\bdelv\b.{0,120}dnssec", "DNSSEC validation")
        for marker, description in (
            (
                'cmp "$STAGING_EXPECTED_SANS" "$STAGING_ACTUAL_SANS"',
                "the staging certificate exact SAN comparison",
            ),
            (
                'cmp "$STAGING_EXPECTED_SANS" "$STAGING_STORE_SANS"',
                "the staging ACME-store exact SAN comparison",
            ),
            (
                'cmp "$EXPECTED_SANS" "$STORE_ACTUAL_SANS"',
                "the production ACME-store exact SAN comparison",
            ),
            (
                "' \"$EXPECTED_SANS\")\"\n"
                'jq -er --argjson expected "$EXPECTED_STORE_NAMES_JSON"',
                "the expected-SAN inventory used for production store selection",
            ),
            (
                '--argjson expected "$EXPECTED_STORE_NAMES_JSON"',
                "the expected-SAN inventory binding for production store selection",
            ),
            (
                'select(. == $expected)]',
                "wildcard-capable exact production ACME-store certificate selection",
            ),
            (
                'else error("expected SAN inventory must match exactly one certificate") end',
                "single-certificate cardinality for production store selection",
            ),
            (
                'test "$setting" = dns-01',
                "the exact CAA validationmethods=dns-01 restriction",
            ),
            (
                'test "$setting" = "$ACME_ACCOUNT_URI"',
                "the exact CAA accounturi binding",
            ),
            (
                'test "$critical" -eq 0',
                "unknown critical CAA-tag rejection",
            ),
            (
                "ERROR: unsupported Lets Encrypt CAA parameter",
                "unsupported CAA-parameter rejection",
            ),
            (
                "if openssl s_client -brief -tls1_2",
                "the TLS 1.2 negative handshake proof",
            ),
            (
                "-servername strict-sni-canary.invalid",
                "the strict-SNI unknown-name negative proof",
            ),
            (
                'cmp "$BEFORE_IDENTITY" "$AFTER_IDENTITY"',
                "certificate fingerprint, serial, and SAN persistence across restart",
            ),
            (
                'cmp "$BEFORE_STORE_DIGEST" "$AFTER_STORE_DIGEST"',
                "ACME-store persistence across restart",
            ),
            (
                'test "$current_generation_after" = "$current_generation"',
                "current-generation identity persistence across restart",
            ),
            (
                'cmp "$BEFORE_GENERATION_DIGEST" "$AFTER_GENERATION_DIGEST"',
                "current-generation content persistence across restart",
            ),
            (
                "`DAC_OVERRIDE` ænd `CAP_CHOWN`",
                "the exact CrowdSec runtime capability pair",
            ),
            (
                "| Externæl stæte not reconstructed by the locæl ærchive |",
                "the external-state recovery matrix",
            ),
            (
                "source-commit.txt",
                "the exact repository source-commit lock",
            ),
            (
                "locked-origin-main-commit.txt",
                "the exact locked origin/main commit",
            ),
            (
                "canonical-template-source-lock.tsv",
                "the exact canonical-template source lock",
            ),
            (
                'test "$source_lock_lines" -eq 2',
                "the two-file canonical-template source-lock cardinality",
            ),
            (
                "`appdata/config/certs/files/current -> generation-<64-lowercase-hex>`",
                "the sole permitted files/current generation symlink",
            ),
            (
                "restore_exit_handler() {",
                "the unified restore cleanup and rollback handler",
            ),
            (
                "trap restore_exit_handler EXIT",
                "the unified restore EXIT cleanup and rollback trap",
            ),
            (
                "rollback_cutover || cleanup_rc=1",
                "fail-closed restore cutover rollback propagation",
            ),
            (
                "trap 'exit 129' HUP",
                "a nonzero restore HUP handler",
            ),
            (
                "trap 'exit 130' INT",
                "a nonzero restore INT handler",
            ),
            (
                "trap 'exit 143' TERM",
                "a nonzero restore TERM handler",
            ),
        ):
            require_raw(marker, description)
        require_raw_count(
            '$0 == "; fully validated" {count++}',
            2,
            "both exact saved-delv fully-validated marker cardinality checks",
        )
        for marker, description in (
            (
                'test "$staging_validation_count" -eq 1',
                "the staging saved-delv fully-validated marker cardinality",
            ),
            (
                'test "$validation_count" -eq 1',
                "each production saved-delv fully-validated marker cardinality",
            ),
        ):
            require_raw(marker, description)
        require_raw_pattern(
            r'(?m)^delv "\$STAGING_CHALLENGE" TXT >"\$STAGING_DNS"$',
            "fail-closed staging delv resolution",
        )
        require_raw_pattern(
            r'(?m)^\s*delv "\$qname" "\$qtype" >"\$DNS_RESPONSE"$',
            "fail-closed production delv resolution",
        )
        for marker, minimum, description in (
            (
                'cmp "$EXPECTED_SANS" "$ACTUAL_SANS"',
                2,
                "both production certificate exact SAN comparisons",
            ),
            (
                "grep -E 'TLSv1\\.3' \"$TLS_DUMP\" >/dev/null",
                2,
                "both TLS 1.3 positive handshake proofs",
            ),
            (
                'test "$link" = "$root/appdata/config/certs/files/current"',
                2,
                "both exact files/current-only symlink validations",
            ),
            (
                '[[ "$target" =~ ^generation-[0-9a-f]{64}$ ]]',
                2,
                "both 64-lowercase-hex generation target validations",
            ),
            (
                'test "$target_real" = "$files_real/$target"',
                2,
                "both generation-target containment validations",
            ),
        ):
            require_raw_count(marker, minimum, description)
        for marker, description in (
            (
                "| `app` finæl runtime | Locæl build from `traefik:3` |",
                "the Traefik final-runtime image inventory row",
            ),
            (
                "| `app` builder | `golang:alpine` |",
                "the Traefik Go-builder image inventory row",
            ),
            (
                "| `traefik_certs-dumper` finæl runtime | Locæl build from "
                "`ldez/traefik-certs-dumper:v2` |",
                "the certs-dumper final-runtime image inventory row",
            ),
            (
                "| `traefik_certs-dumper` builder | `golang:alpine` |",
                "the certs-dumper Go-builder image inventory row",
            ),
            (
                "| `socketproxy` | `lscr.io/linuxserver/socket-proxy:latest` |",
                "the socket-proxy runtime image inventory row",
            ),
            (
                "| `crowdsec_agent` | `crowdsecurity/crowdsec:latest` |",
                "the CrowdSec runtime image inventory row",
            ),
        ):
            require_raw(marker, description)
        require_raw_pattern(
            r"CUTOVER_STARTED=true\s+\"\$\{LIVE_COMPOSE\[@\]\}\" stop",
            "arming restore rollback before the first stop",
        )
        require_raw_pattern(
            r"VOLUME_REPLACE_ARMED=true\s+docker volume rm \"\$LIVE_VOLUME\"",
            "arming volume rollback before replacement",
        )
        require_raw_pattern(
            r"ROOT_SWAP_ARMED=true\s+mv -- \"\$REPO_ROOT/Traefik\" "
            r"\"\$ROLLBACK_ROOT\"",
            "arming root rollback before the first root move",
        )
        require_raw_pattern(
            r"restore_exit_handler\(\) \{.*?^\}\s*"
            r"trap restore_exit_handler EXIT\s*"
            r"trap 'exit 129' HUP\s*"
            r"trap 'exit 130' INT\s*"
            r"trap 'exit 143' TERM",
            "the signal-safe unified restore cleanup and rollback trap chain",
        )
        require_raw_pattern(
            r'test "\$peer_control_ready" = true\s+for path in '
            r'ping api/rawdata dashboard/; do',
            "a successful peer test-infrastructure control before endpoint denials",
        )
        for marker, description in (
            (
                '-showcerts -verify_return_error -verify_hostname "$EDGE_APEX"',
                "Edge apex s_client chain and hostname fail-closed flags",
            ),
            (
                '-CAfile "$CA_BUNDLE" </dev/null >"$EDGE_TLS_DUMP" 2>&1',
                "the Edge apex s_client CA bundle",
            ),
            (
                "grep -Eq '^[[:space:]]*Verify return code: 0 \\(ok\\)$' "
                '"$EDGE_TLS_DUMP"',
                "the exact successful Edge apex verification result",
            ),
            (
                'openssl verify -CAfile "$CA_BUNDLE" -untrusted "$EDGE_CHAIN"',
                "the separate Edge apex leaf and intermediate-chain verification",
            ),
            (
                '-purpose sslserver -verify_hostname "$EDGE_APEX" "$EDGE_LEAF"',
                "the separate Edge apex hostname verification",
            ),
        ):
            require_raw(marker, description)
        require_topic(
            r"renewal.{0,500}(serial|fingerprint).{0,500}(before|after)",
            "a longitudinal certificate-renewal proof",
        )

    elif product == "traefik_certs-dumper":
        require_raw(
            "templates/traefik_certs-dumper/docker-compose.traefik_certs-dumper.yaml",
            "the canonical Mailcow Compose opt-in source",
        )
        require_raw(
            "templates/traefik_certs-dumper/scripts/post-hook.sh",
            "the canonical Mailcow hook source",
        )
        require_topic(
            r"traefik/docker-compose\.main\.yaml.{0,180}(generated|replace)",
            "that generated deployment files are not persistent sources",
        )
        require_topic(
            r"set app gid.{0,80}at the same time.{0,120}both mode-\s*0640 secrets"
            r".{0,120}both service-level secret mounts",
            "APP_GID at the same time as both mode-0640 secret mounts",
        )
        require_topic(
            r"desec constrained read token.{0,120}deny[- ]by[- ]default writes"
            r".{0,120}exact txt/tlsa rrsets",
            "the constrained deSEC exact TXT/TLSA RRset description",
        )
        require_raw(
            "deSEC constræined reæd token with deny-by-defæult writes only for "
            "the exæct TXT/TLSÆ RRsets",
            "the constrained deSEC exact TXT/TLSA RRset description",
        )
        for marker, description in (
            (
                "`appdata/config/certs/files/current -> generation-<64-lowercase-hex>`",
                "the sole permitted files/current generation symlink",
            ),
            (
                'test "$MERGED_TEMPLATE_COMMIT" = "$ORIGIN_MAIN_COMMIT"',
                "the exact locked origin/main template identity",
            ),
            (
                'cmp "$source_compose"',
                "the canonical Mailcow Compose byte comparison",
            ),
            (
                'cmp "$source_hook" Traefik/scripts/post-hook.sh',
                "the canonical Mailcow hook byte comparison",
            ),
        ):
            require_raw(marker, description)
        require_raw_count(
            "--no-deps traefik_certs-dumper --preflight",
            2,
            "both fail-closed one-shot production preflights",
        )
        verification = _readme_level_two_section(readme_text, "Verificætion")
        for marker, description in (
            ("set -Eeuo pipefail", "strict mode in the Verification block"),
            (
                "test -f .env; test -f docker-compose.main.yaml",
                "fail-closed generated-file preflights in the Verification block",
            ),
            (
                "docker compose --env-file .env -f docker-compose.main.yaml config",
                "the merged Compose Verification check",
            ),
            (
                "certs-dumper-safe-reader --kind supervisor-ready "
                "--source /run/certs-dumper/ready --digest",
                "the committed-ready Verification probe",
            ),
        ):
            if marker not in verification:
                issues.append(f"README.md: {product} must document {description}")

    elif product == "crowdsec_agent":
        for pattern, description in (
            (r"\bno logs\b", "loss of the log source"),
            (r"not parsed|parsed counter.{0,80}(zero|0)", "a parse-zero failure"),
            (r"lapi unavailable", "LAPI unavailability"),
            (r"pending or revoked", "pending or revoked machine credentials"),
            (r"stale bouncer", "stale bouncer state"),
            (r"enforcement api failure", "enforcement API failure"),
            (r"quarantine", "credential quarantine"),
            (r"rollback", "credential re-registration rollback"),
        ):
            require_topic(pattern, description)
        if re.search(
            r"(?m)^\s*(?:sudo\s+)?rm\s+(?:-[^\s]+\s+)*[^\n]*local_api_credentials\.yaml",
            readme_text,
        ):
            issues.append(
                "README.md: crowdsec_agent must not delete live machine credentials blindly"
            )

        for marker, description in (
            (
                "CROWDSEC_REPLACEMENT_MACHINE",
                "an explicit distinct replacement-machine input",
            ),
            (
                "'exec cscli lapi register -u \"$LOCAL_API_URL\" --machine \"$1\"'",
                "the one-shot replacement registration with the exact machine name",
            ),
            (
                "test \"$crowdsec_new_machine\" = \"$crowdsec_replacement_machine\"",
                "credential login binding to the requested replacement machine",
            ),
            (
                'test "$crowdsec_old_machine" = "$CROWDSEC_EXPECTED_OLD_MACHINE"',
                "binding the parsed old login to the inspected remote machine",
            ),
            (
                "trap crowdsec_restore_on_error EXIT",
                "the registration transaction EXIT rollback",
            ),
            (
                "trap crowdsec_recover_new_on_error EXIT",
                "the manual rollback transaction EXIT recovery",
            ),
            (
                "crowdsec_on_hup() { exit 129; }",
                "a nonzero HUP handler",
            ),
            (
                "crowdsec_on_int() { exit 130; }",
                "a nonzero INT handler",
            ),
            (
                "crowdsec_on_term() { exit 143; }",
                "a nonzero TERM handler",
            ),
            (
                "#### Live End-to-End Evidence — mændætory full cænæry before remote deletion",
                "the executable full acquisition-to-enforcement canary procedure",
            ),
            (
                "crowdsec_reason=\"manual-canary-$(date -u +%Y%m%dT%H%M%SZ)-$$\"",
                "a unique synthetic-canary reason",
            ),
            (
                "cscli decisions delete --id \"$crowdsec_decision_id\"",
                "identity-safe exact decision-ID cleanup",
            ),
            (
                "IFS= read -r crowdsec_confirmation",
                "typed old-machine deletion confirmation input",
            ),
            (
                'test "$crowdsec_confirmation" = "$crowdsec_expected"',
                "exact typed old-machine deletion confirmation",
            ),
        ):
            require_raw(marker, description)

        for pattern, description in (
            (
                r"trusted.{0,100}management lan/vpn.{0,220}verified https",
                "the trusted-LAN/VPN versus verified-HTTPS transport boundary",
            ),
            (
                r"never use.{0,80}insecure-skip-verify",
                "the ban on disabling LAPI certificate verification",
            ),
            (
                r"does not change.{0,100}app name.{0,180}normal wrapper",
                "that replacement registration does not rename APP_NAME or the normal wrapper",
            ),
            (
                r"2xx.{0,80}baseline.{0,160}no pre-existing decision",
                "a 2xx baseline with no pre-existing source decision",
            ),
        ):
            require_topic(pattern, description)

        for line in readme_text.splitlines():
            stripped = line.strip()
            if not stripped.startswith("trap ") or stripped.startswith("trap -"):
                continue
            trap_tokens = stripped.split()
            if "EXIT" in trap_tokens and any(
                signal in trap_tokens for signal in ("HUP", "INT", "TERM")
            ):
                issues.append(
                    "README.md: crowdsec_agent must use separate signal traps that "
                    "flow through an EXIT rollback"
                )
                break

        registration_handler = re.search(
            r"crowdsec_restore_on_error\(\)\s*\{.*?^\}",
            readme_text,
            flags=re.MULTILINE | re.DOTALL,
        )
        if not registration_handler or (
            "crowdsec_activate_exact_old_credentials"
            not in registration_handler.group(0)
        ):
            issues.append(
                "README.md: crowdsec_agent registration EXIT rollback must restore "
                "the exact old credential identity before restart"
            )
        elif registration_handler.group(0).find(
            "crowdsec_activate_exact_old_credentials"
        ) > registration_handler.group(0).find("up -d crowdsec_agent"):
            issues.append(
                "README.md: crowdsec_agent registration EXIT rollback must restore "
                "old credentials before restart"
            )

        recovery_handler = re.search(
            r"crowdsec_recover_new_on_error\(\)\s*\{.*?^\}",
            readme_text,
            flags=re.MULTILINE | re.DOTALL,
        )
        if not recovery_handler or (
            "crowdsec_activate_exact_old_credentials" not in recovery_handler.group(0)
        ):
            issues.append(
                "README.md: crowdsec_agent rollback EXIT recovery must activate the "
                "exact old identity even when the active target is absent"
            )
        elif re.search(
            r"if\s+test\s+\"\$crowdsec_new_moved\"\s+-eq\s+1",
            recovery_handler.group(0),
        ):
            issues.append(
                "README.md: crowdsec_agent rollback must not gate old-identity "
                "restoration on crowdsec_new_moved"
            )
        elif recovery_handler.group(0).find(
            "crowdsec_activate_exact_old_credentials"
        ) > recovery_handler.group(0).find("up -d crowdsec_agent"):
            issues.append(
                "README.md: crowdsec_agent rollback EXIT recovery must restore old "
                "credentials before restart"
            )

        rollback_start = readme_text.find(
            "#### Rollbæck before deleting the old remote mæchine"
        )
        rollback_section = (
            readme_text[rollback_start:] if rollback_start >= 0 else ""
        )
        rollback_activation = re.search(
            r"crowdsec_activate_exact_old_credentials\(\)\s*\{.*?^\}",
            rollback_section,
            flags=re.MULTILINE | re.DOTALL,
        )
        if not rollback_activation or (
            'mv -T -- "$crowdsec_old_credentials" "$crowdsec_credentials"'
            not in rollback_activation.group(0)
        ):
            issues.append(
                "README.md: crowdsec_agent rollback must restore the quarantined "
                "old identity when the active target is absent with crowdsec_new_moved=0"
            )
        if re.search(
            r"(?:if\s+test|test)\s+\"\$crowdsec_new_moved\"\s+-eq\s+1"
            r".{0,240}mv\s+-T\s+--\s+\"\$crowdsec_old_credentials\"",
            rollback_section,
            flags=re.DOTALL,
        ):
            issues.append(
                "README.md: crowdsec_agent rollback must restore the old identity "
                "independently of crowdsec_new_moved"
            )

        reregistration_start = readme_text.find("### Re-registering the mæchine")
        preflight_status = readme_text.find(
            "crowdsec_agent cscli lapi status",
            reregistration_start,
        )
        first_stop = readme_text.find("stop crowdsec_agent", reregistration_start)
        if not (
            reregistration_start >= 0
            and preflight_status > reregistration_start
            and first_stop > preflight_status
        ):
            issues.append(
                "README.md: crowdsec_agent must complete read-only LAPI status "
                "preflight before the first service stop"
            )

        full_canary = readme_text.find(
            "#### Live End-to-End Evidence — mændætory full cænæry before remote deletion"
        )
        old_inspect = readme_text.find(
            'cscli machines inspect "$crowdsec_old_machine"',
            full_canary,
        )
        typed_confirmation = readme_text.find(
            'crowdsec_expected="DELETE ${crowdsec_old_machine} AFTER FULL CANARY',
            full_canary,
        )
        old_delete = readme_text.find(
            'cscli machines delete "$crowdsec_old_machine"',
            full_canary,
        )
        if not (
            full_canary >= 0
            and old_inspect > full_canary
            and typed_confirmation > old_inspect
            and old_delete > typed_confirmation
        ):
            issues.append(
                "README.md: crowdsec_agent old-machine deletion must follow the full "
                "canary, exact machine inspection, and typed confirmation"
            )
        all_old_deletes = [
            match.start()
            for match in re.finditer(
                re.escape('cscli machines delete "$crowdsec_old_machine"'),
                readme_text,
            )
        ]
        if len(all_old_deletes) != 1 or any(
            position <= typed_confirmation for position in all_old_deletes
        ):
            issues.append(
                "README.md: crowdsec_agent every old-machine delete must be the "
                "single post-canary, post-confirmation command"
            )

        for marker, description in (
            ("crowdsec_baseline_status", "the executable full-canary 2xx baseline"),
            ("metrics.before.json", "the full-canary pre-trigger metrics snapshot"),
            ("crowdsec_trigger_url", "the unique real-log trigger sequence"),
            ("crowdsec_alert_id", "the exact full-canary alert identity"),
            (
                "metrics show acquisition",
                "machine-readable acquisition metrics for the mandatory canary",
            ),
            (
                "$after[0].acquisition[$source].reads >",
                "a strict full-canary lines-read increase assertion",
            ),
            (
                "$after[0].acquisition[$source].parsed >",
                "a strict full-canary lines-parsed increase assertion",
            ),
            (
                'select((.machine_id? // "") == $machine)',
                "exact replacement-machine attribution from decision JSON",
            ),
            (
                'test "$crowdsec_bouncer_identity_after" = '
                '"$crowdsec_bouncer_identity_before"',
                "exact pre/post enforcement-bouncer identity binding",
            ),
            (
                'test "$crowdsec_bouncer_epoch_after" -gt '
                '"$crowdsec_bouncer_epoch_before"',
                "strict enforcement-bouncer pull advancement",
            ),
        ):
            require_raw(marker, description)

        full_canary_end = old_delete if old_delete > full_canary else len(readme_text)
        full_canary_section = (
            readme_text[full_canary:full_canary_end] if full_canary >= 0 else ""
        )
        if re.search(
            r"decisions\s+list\s+--machine\s+[\"']?\$crowdsec_",
            full_canary_section,
        ):
            issues.append(
                "README.md: crowdsec_agent cscli decisions --machine is a boolean "
                "flag and must not receive a machine-name argument"
            )
        if len(
            re.findall(
                r"decisions\s+list\s+--machine\s+\\?\s*--ip\b",
                full_canary_section,
            )
        ) < 2:
            issues.append(
                "README.md: crowdsec_agent must use boolean --machine plus --ip "
                "for both canary attribution and identity-safe cleanup"
            )
        if len(
            re.findall(
                r'select\(\(\.machine_id\? // ""\) == \$machine(?:\)| and)',
                full_canary_section,
            )
        ) < 3:
            issues.append(
                "README.md: crowdsec_agent must bind the alert, decision, and "
                "identity-safe cleanup to the exact replacement-machine field"
            )
        if re.search(r"(?m)^\s*diff(?:\s|$)", full_canary_section):
            issues.append(
                "README.md: crowdsec_agent mandatory canary metrics must assert "
                "strict read and parsed increases, not use a non-failing diff"
            )
        for metric_name, description in (
            ("reads", "a strict full-canary lines-read increase assertion"),
            ("parsed", "a strict full-canary lines-parsed increase assertion"),
        ):
            if (
                f"$after[0].acquisition[$source].{metric_name} >="
                in full_canary_section
            ):
                issues.append(
                    f"README.md: crowdsec_agent must document {description}"
                )
        if full_canary_section.count(
            "cscli --color no -o json bouncers list"
        ) < 2:
            issues.append(
                "README.md: crowdsec_agent mandatory canary must capture machine-readable "
                "pre/post bouncer state"
            )

    elif product == "socketproxy":
        require_topic(
            r":ro.{0,180}(not|does not).{0,80}(read[- ]only|readonly).{0,80}(api|docker)",
            "that a read-only socket mount does not make the Docker API read-only",
        )
        require_topic(r"post\s*=\s*0", "the global POST denial")
        require_topic(r"one[- ]consumer|exactly one", "the one-consumer network boundary")
        require_topic(r"socket[- ]equivalent", "socket-equivalent proxy sensitivity")
        for guard in (
            "SOCKETPROXY_POST",
            "SOCKETPROXY_ALLOW_START",
            "SOCKETPROXY_ALLOW_STOP",
            "SOCKETPROXY_ALLOW_RESTARTS",
            "SOCKETPROXY_ALLOW_PAUSE",
            "SOCKETPROXY_ALLOW_UNPAUSE",
        ):
            if not re.search(
                rf"\|\s*`{re.escape(guard)}`\s*\|\s*`0`\s*\|",
                readme_text,
            ):
                issues.append(
                    f"README.md: socketproxy must document `{guard}` with a zero default"
                )
        for runtime_guard in (
            "POST",
            "ALLOW_START",
            "ALLOW_STOP",
            "ALLOW_RESTARTS",
            "ALLOW_PAUSE",
            "ALLOW_UNPAUSE",
        ):
            require_raw(
                f'test "${{{runtime_guard}:-}}" = 0',
                f"a runtime zero assertion for {runtime_guard}",
            )
        require_topic(
            r"socketproxy allow restarts.{0,120}\bstop\b.{0,40}\brestart\b"
            r".{0,60}\bkill\b",
            "that ALLOW_RESTARTS grants stop, restart, and kill",
        )
        require_raw(
            'join(",")) == "app,socketproxy"',
            "the exact app-plus-socketproxy merged network membership check",
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
    issues.extend(check_readme_product_security_contract(readme_path, readme_text))
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
