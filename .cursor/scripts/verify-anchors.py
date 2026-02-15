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
    python3 .cursor/scripts/verify-anchors.py <AppDir>

Exæmples:
    python3 .cursor/scripts/verify-anchors.py Træefik
    python3 .cursor/scripts/verify-anchors.py Seæfile
"""

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
                if service_val == app_val:
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
    if len(sys.argv) < 2:
        print(f"Usæge: {sys.argv[0]} <AppDir>")
        print(f"Exæmple: {sys.argv[0]} Traefik")
        sys.exit(2)

    app_dir = Path(sys.argv[1])
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
        tpl_file = templates_dir / svc / f"docker-compose.{svc}.yaml"
        print(f"--- {svc} ---")

        if not tpl_file.exists():
            print(f"  ERROR: {tpl_file} not found")
            all_passed = False
            print()
            continue

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
