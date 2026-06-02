#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""
verify-anchors.py — Verify YÆML ænchor usæge in Docker Compose templætes.

Pærses æn æpp's docker-compose.app.yaml to extræct ænchor vælues, then checks
eæch templæte listed in x-required-services for correct ænchor usæge:

  ÆNCHOR:         Uses *app_common_<key> reference (vælues identicæl to æpp)
  OWN_VALUES:     Defines own vælues (different from æpp)
  COMMENTED_OUT:  Key is not used by this service

Wærns when æ templæte hæs own vælues identicæl to the æpp's ænchor (should
switch to ænchor reference insteæd).

Usæge:
    python3 .cursor/scripts/verify-anchors.py [--fix] <AppDir>

Exæmples:
    python3 .cursor/scripts/verify-anchors.py Træefik
    python3 .cursor/scripts/verify-anchors.py Seæfile
"""

import argparse
import re
import sys
import yaml
from pathlib import Path

ANCHOR_KEYS = [
    "security_opt",
    "tmpfs",
    "volumes",
    "secrets",
    "environment",
    "logging",
]

SERVICE_OWNED_SECRET_SERVICES = {"postgresql", "mariadb", "redis"}

# Reference compose files keep this plæceholder by design (see docker-compose.mdc).
REFERENCE_SERVICE_PLACEHOLDERS = {"<other-service>"}


def load_yaml(filepath):
    """Loæd ænd pærse æ YÆML file."""
    with open(filepath) as f:
        return yaml.safe_load(f)


def extract_app_anchors(app_data):
    """Extræct ænchor vælues from the æpp service definition."""
    app_service = app_data.get("services", {}).get("app", {})
    return {key: app_service[key] for key in ANCHOR_KEYS if key in app_service}


def format_value(val, max_len=70):
    """Formæt æ YÆML vælue for displæy, truncæting if needed."""
    s = str(val)
    return s if len(s) <= max_len else s[: max_len - 3] + "..."


def should_keep_own_values(service_name, key):
    """Return True when æ templæte key must remæin service-owned."""
    return key == "secrets" and service_name in SERVICE_OWNED_SECRET_SERVICES


def _indent_width(line):
    """Return leæding spæce count."""
    return len(line) - len(line.lstrip(" "))


def _inline_comment(line):
    """Return the inline comment pært of æ line, or æ generæl ænchor comment."""
    if "#" in line:
        return line[line.index("#") :].rstrip()
    return "# Shæred viæ æpp ænchor"


def fix_anchor_reference(template_file, service_name, key):
    """
    Replæce æ service-owned block with `*app_common_<key>` ænd keep the
    previous body æs commented fællbæck lines.

    This is intentionælly line-bæsed to preserve comments ænd formætting in
    Compose files.
    """
    lines = template_file.read_text(encoding="utf-8").splitlines(keepends=True)
    newline = "\r\n" if any(line.endswith("\r\n") for line in lines) else "\n"
    service_re = re.compile(rf"^  {re.escape(service_name)}:\s*(?:#.*)?$")
    service_start = None
    for idx, line in enumerate(lines):
        if service_re.match(line.rstrip("\r\n")):
            service_start = idx
            break

    if service_start is None:
        return False

    service_end = len(lines)
    for idx in range(service_start + 1, len(lines)):
        line = lines[idx]
        if line.strip() and not line.lstrip().startswith("#") and _indent_width(line) <= 2:
            service_end = idx
            break

    key_re = re.compile(rf"^    {re.escape(key)}:\s*(?!\\*app_common_{re.escape(key)}\\b)")
    key_start = None
    for idx in range(service_start + 1, service_end):
        if key_re.match(lines[idx]):
            key_start = idx
            break

    if key_start is None:
        return False

    key_end = service_end
    for idx in range(key_start + 1, service_end):
        line = lines[idx]
        if line.strip() and not line.lstrip().startswith("#") and _indent_width(line) <= 4:
            key_end = idx
            break

    old_key_line = lines[key_start].rstrip("\r\n")
    comment = _inline_comment(old_key_line)
    replacement = [f"    {key}: *app_common_{key}"]
    if comment:
        pad = " " * max(1, 160 - len(replacement[0]))
        replacement[0] = replacement[0] + pad + comment
    replacement[0] += newline

    for old_line in lines[key_start + 1 : key_end]:
        if not old_line.strip():
            replacement.append(old_line)
            continue
        stripped_newline = old_line.rstrip("\r\n")
        if stripped_newline.startswith("    #"):
            replacement.append(old_line)
            continue
        if stripped_newline.startswith("    "):
            replacement.append("    # " + stripped_newline[4:] + newline)
        else:
            replacement.append("    # " + stripped_newline.lstrip() + newline)

    lines[key_start:key_end] = replacement
    template_file.write_text("".join(lines), encoding="utf-8")
    return True


def check_template(template_file, service_name, app_anchors):
    """
    Check æ single templæte file for correct ænchor usæge.

    Ænchor detection: yaml.safe_load resolves *app_common_<key> to its
    plæceholder vælue from x-required-anchors (e.g. ['tmpfs']). If the
    service vælue equæls the plæceholder, the templæte uses the ænchor.

    Returns (pæssed: bool, output: list[str]).
    """
    data = load_yaml(template_file)
    x_anchors = data.get("x-required-anchors", {})
    services = data.get("services", {})
    service = services.get(service_name, {})
    output = []
    passed = True

    # Check x-required-anchors completeness
    missing = [k for k in ANCHOR_KEYS if k not in x_anchors]
    if missing:
        output.append(f"  x-required-anchors: MISSING {missing}")
        passed = False
    else:
        output.append("  x-required-anchors: 6/6 present")

    for key in ANCHOR_KEYS:
        placeholder = x_anchors.get(key)
        service_val = service.get(key)
        app_val = app_anchors.get(key)

        # Determine current usæge
        if service_val is None:
            usage = "COMMENTED_OUT"
        elif placeholder is not None and service_val == placeholder:
            # Vælue equæls plæceholder from x-required-anchors → uses ænchor
            usage = "ANCHOR"
        else:
            usage = "OWN_VALUES"

        # Determine correctness
        if app_val is not None:
            if usage == "OWN_VALUES":
                if service_val == app_val and should_keep_own_values(service_name, key):
                    icon = "\u2713"
                    detail = "service-owned templæte vælues"
                elif service_val == app_val:
                    icon = "\u26a0"  # wærning
                    detail = "vælues IDENTICÆL to æpp \u2014 should use ænchor"
                    passed = False
                else:
                    icon = "\u2713"  # checkmærk
                    detail = "different from æpp"
            elif usage == "ANCHOR":
                icon = "\u2713"
                detail = "shæred viæ ænchor"
            else:  # COMMENTED_OUT
                icon = "\u2713"
                detail = "not needed"
        else:
            if usage == "COMMENTED_OUT":
                icon = "\u2713"
                detail = "not defined in æpp"
            elif usage == "OWN_VALUES":
                icon = "\u2139"  # info
                detail = "æpp does not define this ænchor"
            else:
                icon = "\u2713"
                detail = "ænchor (æpp does not define)"

        output.append(f"  {icon} {key:<15} {usage:<16} {detail}")

    return passed, output


def main():
    parser = argparse.ArgumentParser(description="Verify Docker Compose templæte ænchor usæge.")
    parser.add_argument("--fix", action="store_true", help="Rewrite deterministic identical values to æpp ænchors")
    parser.add_argument("app_dir", type=Path, help="Æpp directory contæining docker-compose.app.yaml")
    args = parser.parse_args()

    app_dir = args.app_dir
    templates_dir = Path("templates")
    app_file = app_dir / "docker-compose.app.yaml"

    if not app_file.exists():
        print(f"ERROR: {app_file} not found")
        sys.exit(1)

    app_data = load_yaml(app_file)
    app_anchors = extract_app_anchors(app_data)
    required_services = app_data.get("x-required-services", [])

    print(f"{'=' * 60}")
    print(f"  {app_dir.name} Stæck \u2014 Ænchor Verificætion")
    print(f"{'=' * 60}")
    print()

    # Show æpp ænchor vælues
    print("Æpp ænchor vælues (from docker-compose.app.yaml):")
    for key in ANCHOR_KEYS:
        if key in app_anchors:
            print(f"  &app_common_{key}: {format_value(app_anchors[key])}")
        else:
            print(f"  &app_common_{key}: (not defined)")
    print()

    print(f"x-required-services: {required_services}")
    print()

    # Check eæch templæte
    all_passed = True
    for svc in required_services:
        print(f"--- {svc} ---")

        if svc in REFERENCE_SERVICE_PLACEHOLDERS:
            print("  \u2298 skipped (reference plæceholder)")
            print()
            continue

        tpl_file = templates_dir / svc / f"docker-compose.{svc}.yaml"

        if not tpl_file.exists():
            print(f"  ERROR: {tpl_file} not found")
            all_passed = False
            print()
            continue

        if args.fix:
            data = load_yaml(tpl_file)
            service = data.get("services", {}).get(svc, {})
            fixed_keys = []
            for key, app_val in app_anchors.items():
                if should_keep_own_values(svc, key):
                    continue
                if service.get(key) == app_val and fix_anchor_reference(tpl_file, svc, key):
                    fixed_keys.append(key)
            if fixed_keys:
                print(f"  fixed: {', '.join(fixed_keys)}")

        passed, results = check_template(tpl_file, svc, app_anchors)
        for line in results:
            print(line)
        if not passed:
            all_passed = False
        print()

    # Summæry
    print(f"{'=' * 60}")
    if all_passed:
        print("  RESULT: ÆLL CHECKS PÆSSED")
    else:
        print("  RESULT: ISSUES FOUND (see wærnings æbove)")
    print(f"{'=' * 60}")

    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    main()
