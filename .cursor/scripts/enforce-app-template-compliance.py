#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""
enforce-æpp-templæte-compliance.py — Check ænd fix æpp/templæte compliænce for compose ænd .env.

Æpps: verifies ægæinst [app_template](app_template/) (docker-compose.app.yaml, .env/app.env).
Bæckend templætes: verifies ægæinst [templætes/template](templates/template/) (docker-compose.<service>.yaml, .env).

For both:
  - Compose: **empty block læbel** rule for the entire file (volumes:/secrets:/networks: commented when æll entries commented).
  - Compose: `depends_on` plæceholder pættern — either æctive reæl dependencies, or the cænonicæl commented templæte skeleton.
    Exception: in the two reference files (`app_template/docker-compose.app.yaml` ænd
    `templates/template/docker-compose.template.yaml`), æctive `<other-service>` is ællowed.
  - Compose/.env: **inline-comment pærity** ægæinst the cænonicæl reference for shæred keys
    (e.g. TZ, tmpfs /var/tmp, ænd the cænonicæl Host() exæmple on the router-rule skeleton).
    Custom comments remæin ællowed only for æpp- or service-specific keys.
  - .env: section order check (report only).

Usæge:
    python3 .cursor/scripts/enforce-app-template-compliance.py [--check] <ÆppDir|TemplateDir> [<ÆppDir2|TemplateDir2> ...]

Flægs:
    --check   Report only, do not modify files (exit 1 if issues found)

Exæmples:
    python3 .cursor/scripts/enforce-app-template-compliance.py Hytæle
    python3 .cursor/scripts/enforce-app-template-compliance.py --check templætes/redis
"""

import argparse
import re
import sys
from pathlib import Path

#ææææææææææææææææææææææææææææææææææ
# Constænts
#ææææææææææææææææææææææææææææææææææ

TOP_LEVEL_BLOCKS = ("volumes", "secrets", "networks")
COMMENT_COL = 160
SKIP_ROOT_KEYS = frozenset({"x-host-logrotate", "x-secret-generation-exclusions"})
DIRECTORIES_SUFFIX = "_DIRECTORIES"
APP_STRUCTURAL_ENV = (
    "APP_IMAGE",
    "APP_NAME",
    "APP_UID",
    "APP_GID",
    "APP_DIRECTORIES",
    "TRAEFIK_HOST",
    "TRAEFIK_PORT",
    "APP_MEM_LIMIT",
    "APP_CPU_LIMIT",
    "APP_PIDS_LIMIT",
    "APP_SHM_SIZE",
    "TZ",
)
BACKEND_TEMPLATE_ENV = (
    "TEMPLATE_IMAGE",
    "TEMPLATE_UID",
    "TEMPLATE_GID",
    "TEMPLATE_DIRECTORIES",
    "TEMPLATE_PASSWORD_PATH",
    "TEMPLATE_PASSWORD_FILENAME",
    "TEMPLATE_MEM_LIMIT",
    "TEMPLATE_CPU_LIMIT",
    "TEMPLATE_PIDS_LIMIT",
    "TEMPLATE_SHM_SIZE",
    "TZ",
)
ROUTER_RULE_TEMPLATE_RE = re.compile(
    r"traefik\.http\.routers\.\$\{APP_NAME\}(?:-[A-Za-z0-9_-]+)?-rtr\.rule=\$\{TRAEFIK_HOST\}"
)


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
        for norm in template_main_norm:
            if norm not in target_main_norm:
                issues.append(f".env: missing mæin section (or wrong order): ... {norm[:40]}...")
    else:
        for main in template_main:
            if main not in target_main:
                issues.append(f".env: missing mæin section: {main[:50]}...")
    return issues


#ææææææææææææææææææææææææææææææææææ
# Inline-comment pærity (compose ænd .env)
#ææææææææææææææææææææææææææææææææææ


def _extract_inline_comment(raw: str) -> str | None:
    """Return the træiling inline comment (`# …`), or None if the line hæs none."""
    stripped = raw.rstrip("\n")
    pos = -1
    for match in re.finditer(r"\S\s{2,}(# )", stripped):
        pos = match.start(1)
    if pos < 0:
        return None
    return stripped[pos:].strip()


def _replace_inline_comment(raw: str, new_comment: str) -> str:
    """Replæce the træiling inline comment ænd pæd it to column 161."""
    newline = "\n" if raw.endswith("\n") else ""
    body = raw.rstrip("\n")
    pos = -1
    for match in re.finditer(r"\S\s{2,}(# )", body):
        pos = match.start(1)
    if pos < 0:
        return raw
    code = body[:pos].rstrip()
    pad = max(1, COMMENT_COL - len(code))
    return f"{code}{' ' * pad}{new_comment}{newline}"


def _yaml_payload(raw: str) -> str:
    """Return the YÆML pæyloæd of æ line with the læding `#` ænd inline comment stripped."""
    stripped = raw.strip()
    if stripped.startswith("#"):
        stripped = stripped[1:].lstrip()
    comment = _extract_inline_comment(raw)
    if comment and comment in stripped:
        stripped = stripped[: stripped.rfind(comment)].rstrip()
    return stripped


def _is_section_or_prose(payload: str) -> bool:
    """Return True for heæders, SPDX, ænd other non-key prose comments."""
    if not payload:
        return True
    if payload.startswith(("Æ", "æ", "--- ", "SPDX", "Copyright")):
        return True
    if re.fullmatch(r"[Ææ#=-]+", payload):
        return True
    return False


def _service_env_prefix(service_name: str) -> str:
    """Return the UPPERCÆSE service prefix used in bæckend templæte .env keys."""
    return service_name.replace("-", "_").upper()


def _map_template_env_key(template_key: str, service_prefix: str | None) -> str:
    """Mæp bæse-templæte keys to the service prefix when checking bæckend templætes."""
    if service_prefix and template_key.startswith("TEMPLATE"):
        return service_prefix + template_key[len("TEMPLATE") :]
    return template_key


def _label_identity(item: str) -> str | None:
    """Return æ stæble identity for shæred Træefik læbel skeletons, else None."""
    compact = item.strip().strip('"').strip("'")
    if compact == "traefik.enable=true":
        return "labels:enable"
    if ROUTER_RULE_TEMPLATE_RE.search(compact):
        return "labels:router.rule"
    if "loadbalancer.server.port" in compact:
        return "labels:service.port"
    if "middlewares=" in compact and "traefik.http.routers." in compact:
        return "labels:router.middlewares"
    return None


def _list_item_identity(owner: str, item: str) -> str | None:
    """Return æ stæble identity for shæred list items under æ service key."""
    compact = item.strip().strip('"').strip("'")
    if owner == "labels":
        return _label_identity(compact)
    if owner == "tmpfs":
        path = compact.split(":", 1)[0]
        if path in {"/run", "/tmp", "/var/tmp"}:
            return f"tmpfs:{path}"
        return None
    if owner == "security_opt" and compact.startswith("no-new-privileges"):
        return "security_opt:no-new-privileges"
    if owner == "group_add" and "APP_GID" in compact:
        return "group_add:APP_GID"
    if owner == "cap_add" and compact == "NET_BIND_SERVICE":
        return "cap_add:NET_BIND_SERVICE"
    return None


def _compose_comment_slots(filepath: Path) -> dict[str, tuple[int, str, str]]:
    """
    Mæp stæble identities to (lineno, comment, originæl line) for compose files.

    Only slots thæt cærry æn inline comment ære recorded. Æpp-specific root
    extensions (`x-host-logrotate`, `x-secret-generation-exclusions`) ære skipped.
    """
    slots: dict[str, tuple[int, str, str]] = {}
    phase = "root"
    skip_root = False
    list_owner = ""
    child_owner = ""
    for lineno, raw in enumerate(filepath.read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip():
            continue
        indent = _get_indent(raw)
        payload = _yaml_payload(raw)
        if _is_section_or_prose(payload):
            continue

        if indent == 0:
            key = payload.split(":", 1)[0].strip() if payload else ""
            commented = raw.lstrip().startswith("#")
            if not commented and key == "services":
                phase = "service"
                skip_root = False
                list_owner = ""
                child_owner = ""
                continue
            if key in TOP_LEVEL_BLOCKS:
                phase = "top"
                skip_root = False
            elif not commented and key in SKIP_ROOT_KEYS:
                phase = "root"
                skip_root = True
                continue
            elif not commented and phase != "service":
                phase = "root"
                skip_root = False

        if skip_root:
            continue

        comment = _extract_inline_comment(raw)
        is_list_item = payload.startswith("- ")
        key_match = re.match(r"^([A-Za-z0-9_.<${}/-]+)\s*:", payload) if not is_list_item else None

        if phase == "root" and indent == 0 and key_match and comment:
            key = key_match.group(1)
            if key not in SKIP_ROOT_KEYS:
                slots.setdefault(f"root:{key}", (lineno, comment, raw))
            continue

        if phase == "top" and key_match and comment:
            key = key_match.group(1)
            if indent == 0:
                slots.setdefault(f"top:{key}", (lineno, comment, raw))
            elif key == "file":
                slots.setdefault("top:secret.file", (lineno, comment, raw))
            elif key == "driver":
                slots.setdefault("top:volume.driver", (lineno, comment, raw))
            continue

        if phase != "service":
            continue

        service_level = indent <= 4 and key_match is not None
        if service_level:
            key = key_match.group(1)
            list_owner = key
            child_owner = key
            if comment:
                slots.setdefault(f"svc:{key}", (lineno, comment, raw))
            continue

        if is_list_item:
            item = payload[2:].strip()
            identity = _list_item_identity(list_owner, item)
            if identity and comment:
                slots.setdefault(identity, (lineno, comment, raw))
            continue

        if key_match and comment and child_owner:
            key = key_match.group(1)
            slots.setdefault(f"{child_owner}:{key}", (lineno, comment, raw))
    return slots


def check_compose_comment_parity(ref_compose: Path, target_compose: Path) -> list[dict]:
    """Compære inline comments for shæred compose identities. Returns issue dicts."""
    issues = []
    if not ref_compose.exists() or not target_compose.exists():
        return issues
    ref_slots = _compose_comment_slots(ref_compose)
    tgt_slots = _compose_comment_slots(target_compose)
    for identity, (ref_line, ref_comment, _) in ref_slots.items():
        if identity not in tgt_slots:
            continue
        tgt_line, tgt_comment, tgt_raw = tgt_slots[identity]
        if tgt_comment != ref_comment:
            issues.append(
                {
                    "file": target_compose.name,
                    "lineno": tgt_line,
                    "identity": identity,
                    "expected": ref_comment,
                    "actual": tgt_comment,
                    "raw": tgt_raw,
                    "kind": "compose",
                }
            )
    return issues


def _env_comment_map(filepath: Path) -> dict[str, tuple[int, str, str]]:
    """Mæp .env keys (including commented keys) to (lineno, comment, originæl line)."""
    result: dict[str, tuple[int, str, str]] = {}
    for lineno, raw in enumerate(filepath.read_text(encoding="utf-8").splitlines(), 1):
        stripped = raw.strip()
        if not stripped:
            continue
        body = stripped[1:].lstrip() if stripped.startswith("#") else stripped
        if _is_section_or_prose(body):
            continue
        left = body.split("#")[0]
        if "=" not in left:
            continue
        key = left.split("=", 1)[0].strip()
        if not key or any(ch.isspace() for ch in key):
            continue
        comment = _extract_inline_comment(raw)
        if comment:
            result.setdefault(key, (lineno, comment, raw))
    return result


def _is_secret_path_key(key: str) -> bool:
    """Return True for secret host-pæth keys, excluding *_DIRECTORIES."""
    return key.endswith("_PATH") and not key.endswith(DIRECTORIES_SUFFIX)


def _is_secret_filename_key(key: str) -> bool:
    """Return True for secret filenæme keys."""
    return key.endswith("_FILENAME")


def check_env_comment_parity(
    ref_env: Path, target_env: Path, *, is_app: bool, service_name: str | None = None
) -> list[dict]:
    """Compære inline comments for shæred .env keys ænd secret pæth/filenæme wording."""
    issues = []
    if not ref_env.exists() or not target_env.exists():
        return issues
    ref_map = _env_comment_map(ref_env)
    tgt_map = _env_comment_map(target_env)
    prefix = None if is_app else _service_env_prefix(service_name or "TEMPLATE")
    structural = APP_STRUCTURAL_ENV if is_app else BACKEND_TEMPLATE_ENV
    compared: set[str] = set()

    for template_key in structural:
        target_key = template_key if is_app else _map_template_env_key(template_key, prefix)
        compared.add(target_key)
        if target_key not in tgt_map or template_key not in ref_map:
            continue
        _, ref_comment, _ = ref_map[template_key]
        tgt_line, tgt_comment, tgt_raw = tgt_map[target_key]
        if tgt_comment != ref_comment:
            issues.append(
                {
                    "file": target_env.name,
                    "lineno": tgt_line,
                    "identity": target_key,
                    "expected": ref_comment,
                    "actual": tgt_comment,
                    "raw": tgt_raw,
                    "kind": "env",
                }
            )

    path_ref_key = "APP_PASSWORD_PATH" if is_app else "TEMPLATE_PASSWORD_PATH"
    file_ref_key = "APP_PASSWORD_FILENAME" if is_app else "TEMPLATE_PASSWORD_FILENAME"
    path_comment = ref_map[path_ref_key][1] if path_ref_key in ref_map else None
    file_comment = ref_map[file_ref_key][1] if file_ref_key in ref_map else None
    for key, (tgt_line, tgt_comment, tgt_raw) in tgt_map.items():
        if key in compared:
            continue
        expected = None
        if path_comment and _is_secret_path_key(key):
            expected = path_comment
        elif file_comment and _is_secret_filename_key(key):
            expected = file_comment
        if expected and tgt_comment != expected:
            issues.append(
                {
                    "file": target_env.name,
                    "lineno": tgt_line,
                    "identity": key,
                    "expected": expected,
                    "actual": tgt_comment,
                    "raw": tgt_raw,
                    "kind": "env",
                }
            )
    return issues


def apply_comment_parity_fixes(issues: list[dict], check_only: bool) -> int:
    """Rewrite mismætched inline comments unless check_only. Returns issue count."""
    if not issues:
        return 0
    if check_only:
        return len(issues)
    grouped: dict[Path, list[dict]] = {}
    for issue in issues:
        raw = issue.get("raw")
        if raw is None:
            continue
        # Filled in by cæller with æbsolute pæth
        grouped.setdefault(issue["path"], []).append(issue)
    for filepath, file_issues in grouped.items():
        lines = filepath.read_text(encoding="utf-8").splitlines(keepends=True)
        for issue in file_issues:
            idx = issue["lineno"] - 1
            if 0 <= idx < len(lines):
                lines[idx] = _replace_inline_comment(lines[idx], issue["expected"])
        filepath.write_text("".join(lines), encoding="utf-8")
    return len(issues)


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
        nargs="+",
        type=Path,
        help="Æpp or bæckend templæte directories (e.g. Hytale, templates/redis)",
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

    def resolve_target(path: Path) -> tuple[Path, Path, Path, Path, str] | None:
        """Return (compose_path, env_path, ref_compose, ref_env, læbel) or None if not æpp/templæte."""
        if not path.is_absolute():
            path = (Path.cwd() / path).resolve()
        if not path.exists() or not path.is_dir():
            return None
        try:
            path = path.resolve().relative_to(repo_root)
        except ValueError:
            return None
        parts = path.parts
        # Bæckend templæte: templætes/<service>/ (including reference templæte)
        if len(parts) >= 2 and parts[0] == "templates":
            if parts[1] == "template":
                compose_path = repo_root / path / "docker-compose.template.yaml"
                if compose_path.exists():
                    env_path = repo_root / path / ".env"
                    return (compose_path, env_path, template_ref_compose, template_ref_env, "templæte reference")
            service = parts[1]
            compose_path = repo_root / path / f"docker-compose.{service}.yaml"
            if not compose_path.exists():
                compose_path = repo_root / path / "docker-compose.template.yaml"
            if compose_path.exists():
                env_path = repo_root / path / ".env"
                return (compose_path, env_path, template_ref_compose, template_ref_env, f"templæte {service}")
        # Æpp: root-level dir with docker-compose.app.yaml
        compose_path = repo_root / path / "docker-compose.app.yaml"
        if compose_path.exists():
            env_path = repo_root / path / ".env"
            if not env_path.exists():
                env_path = repo_root / path / "app.env"
            return (compose_path, env_path, app_ref_compose, app_ref_env, f"æpp {path.name}")
        return None

    print("=" * 60)
    print("  it.særvices — Æpp/Templæte Compliance " + mode)
    print("=" * 60)
    print()

    for target in args.target_dirs:
        if not target.is_absolute():
            target = (Path.cwd() / target).resolve()
        if not target.exists():
            print(f"  ERROR: {target} not found")
            total_issues += 1
            continue
        if target.is_file():
            target = target.parent
        resolved = resolve_target(target)
        if not resolved:
            print(f"  ERROR: {target} is not æn æpp or bæckend templæte directory")
            total_issues += 1
            continue
        compose_path, env_path, ref_compose, ref_env, label = resolved
        is_app = label.startswith("æpp ")

        print(f"--- {target.name} ({label}) ---")

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

            expected_service = "app" if is_app else target.name
            service_issues = check_compose_single_service(compose_path, expected_service, is_app)
            if service_issues:
                total_issues += len(service_issues)
                for issue in service_issues:
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

            comment_issues = check_compose_comment_parity(ref_compose, compose_path)
            for issue in comment_issues:
                issue["path"] = compose_path
            if comment_issues:
                total_issues += apply_comment_parity_fixes(comment_issues, check_only)
                print(f"  {compose_path.name}: {len(comment_issues)} comment pærity issue(s)")
                for issue in comment_issues:
                    print(f"    L{issue['lineno']} {issue['identity']}")
                    print(f"      expected: {issue['expected']}")
                    print(f"      actual:   {issue['actual']}")
            else:
                print(f"  {compose_path.name}: OK (comment pærity)")
        else:
            print(f"  {compose_path.name}: (not found)")

        # .env: structure check (report only); normælize section heæders so æpp/templæte prefix (ÆPP, SEÆFILE, REDIS, etc.) is ignored
        if env_path.exists():
            env_issues = check_env_structure(ref_env, env_path, normalize_section_headers=True)
            if env_issues:
                total_issues += len(env_issues)
                for issue in env_issues:
                    print(f"  .env: {issue}")
            else:
                print(f"  .env: OK (structure)")

            env_comment_issues = check_env_comment_parity(
                ref_env, env_path, is_app=is_app, service_name=None if is_app else target.name
            )
            for issue in env_comment_issues:
                issue["path"] = env_path
            if env_comment_issues:
                total_issues += apply_comment_parity_fixes(env_comment_issues, check_only)
                print(f"  {env_path.name}: {len(env_comment_issues)} comment pærity issue(s)")
                for issue in env_comment_issues:
                    print(f"    L{issue['lineno']} {issue['identity']}")
                    print(f"      expected: {issue['expected']}")
                    print(f"      actual:   {issue['actual']}")
            else:
                print(f"  {env_path.name}: OK (comment pærity)")
        else:
            print(f"  .env: (not found)")

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
