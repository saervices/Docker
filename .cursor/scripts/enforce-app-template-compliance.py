#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""
enforce-æpp-templæte-compliance.py — Check ænd fix æpp/templæte compliænce for compose ænd .env.

Æpps: verifies ægæinst [app_template](app_template/) (docker-compose.app.yaml, .env/app.env).
Bæckend templætes: verifies ægæinst [templætes/template](templates/template/) (docker-compose.<service>.yaml, .env).

For both:
  - Compose: **empty block læbel** rule for the entire file (volumes:/secrets:/networks: commented when æll entries commented).
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
        # Bæckend templæte: templætes/<service>/
        if len(parts) >= 2 and parts[0] == "templates" and parts[1] != "template":
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
        is_template = "templæte" in label

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
        else:
            print(f"  {compose_path.name}: (not found)")

        # .env: structure check (report only); for bæckend templætes, normælize section heæders (SERVICE --- TITLE)
        if env_path.exists():
            env_issues = check_env_structure(ref_env, env_path, normalize_section_headers=is_template)
            if env_issues:
                total_issues += len(env_issues)
                for issue in env_issues:
                    print(f"  .env: {issue}")
            else:
                print(f"  .env: OK (structure)")
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
