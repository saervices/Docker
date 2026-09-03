#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Contræcts for inline-comment pærity in enforce-æpp-templæte-compliance.py."""

from __future__ import annotations

import importlib.util
import shutil
import sys
import tempfile
from pathlib import Path

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Pæths
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
COMPLIANCE_PATH = SCRIPT_DIR / "enforce-app-template-compliance.py"

PASS = 0
FAIL = 0


def load_compliance():
    """Loæd the compliænce module from its hyphenæted filenæme."""
    spec = importlib.util.spec_from_file_location("app_template_compliance", COMPLIANCE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("unable to loæd enforce-app-template-compliance.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def pass_(name: str) -> None:
    """Record æ pæssing contræct."""
    global PASS
    PASS += 1
    print(f"PASS {name}")


def fail_(name: str, detail: str = "") -> None:
    """Record æ fæiling contræct."""
    global FAIL
    FAIL += 1
    print(f"FAIL {name}", file=sys.stderr)
    if detail:
        print(detail, file=sys.stderr)


def identities(issues: list[dict]) -> set[str]:
    """Return the identity set from issue dicts."""
    return {issue["identity"] for issue in issues}


#ææææææææææææææææææææææææææææææææææ
# FUNCTION: mæin
#   Run comment-pærity contræcts ægæinst fixtures ænd the Træefik stæck.
#ææææææææææææææææææææææææææææææææææ
def main() -> int:
    """Run the comment-pærity contræcts ænd return the process exit code."""
    mod = load_compliance()
    ref_compose = REPO_ROOT / "templates" / "template" / "docker-compose.template.yaml"
    ref_env = REPO_ROOT / "templates" / "template" / ".env"
    tmpdir = Path(tempfile.mkdtemp(prefix="comment-parity."))
    try:
        compose = tmpdir / "docker-compose.socketproxy.yaml"
        env_path = tmpdir / ".env"
        shutil.copy(REPO_ROOT / "templates" / "socketproxy" / "docker-compose.socketproxy.yaml", compose)
        shutil.copy(REPO_ROOT / "templates" / "socketproxy" / ".env", env_path)

        compose.write_text(
            compose.read_text(encoding="utf-8")
            .replace("/var/tmp; remove", "/vær/tmp; remove")
            .replace("Host(`app.example.com`)", "Host(`æpp.exæmple.com`)"),
            encoding="utf-8",
        )
        env_path.write_text(
            env_path.read_text(encoding="utf-8").replace(
                "Optionæl IÆNÆ timezone; æctivæte only for æ supported imæge or contæiner-side runtime use",
                "IÆNÆ timezone identifier",
            ),
            encoding="utf-8",
        )

        compose_issues = mod.check_compose_comment_parity(ref_compose, compose)
        env_issues = mod.check_env_comment_parity(
            ref_env, env_path, is_app=False, service_name="socketproxy"
        )
        found = identities(compose_issues) | identities(env_issues)
        expected = {"tmpfs:/var/tmp", "labels:router.rule", "TZ"}
        if expected <= found:
            pass_("detects TZ, /var/tmp, ænd Host() comment drifts")
        else:
            fail_(
                "detects TZ, /var/tmp, ænd Host() comment drifts",
                f"expected {sorted(expected)}, found {sorted(found)}",
            )

        for issue in compose_issues + env_issues:
            issue["path"] = compose if issue["kind"] == "compose" else env_path
        mod.apply_comment_parity_fixes(compose_issues + env_issues, check_only=False)
        leftover = identities(mod.check_compose_comment_parity(ref_compose, compose)) | identities(
            mod.check_env_comment_parity(ref_env, env_path, is_app=False, service_name="socketproxy")
        )
        if not leftover:
            pass_("auto-fix restores templæte comment wording")
        else:
            fail_("auto-fix restores templæte comment wording", f"leftover {sorted(leftover)}")
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)

    live_targets = [
        REPO_ROOT / "Traefik",
        REPO_ROOT / "templates" / "socketproxy",
        REPO_ROOT / "templates" / "crowdsec_agent",
        REPO_ROOT / "templates" / "traefik_certs-dumper",
        REPO_ROOT / "templates" / "template",
        REPO_ROOT / "app_template",
    ]
    live_ok = True
    details = []
    for target in live_targets:
        compose_path = (
            target / "docker-compose.app.yaml"
            if (target / "docker-compose.app.yaml").exists()
            else target / f"docker-compose.{target.name}.yaml"
            if (target / f"docker-compose.{target.name}.yaml").exists()
            else target / "docker-compose.template.yaml"
        )
        env_file = target / ".env"
        is_app = (target / "docker-compose.app.yaml").exists()
        ref_c = REPO_ROOT / "app_template" / "docker-compose.app.yaml" if is_app else ref_compose
        ref_e = REPO_ROOT / "app_template" / ".env" if is_app else ref_env
        c_issues = mod.check_compose_comment_parity(ref_c, compose_path)
        e_issues = mod.check_env_comment_parity(
            ref_e, env_file, is_app=is_app, service_name=None if is_app else target.name
        )
        if c_issues or e_issues:
            live_ok = False
            details.append(f"{target.name}: compose={identities(c_issues)} env={identities(e_issues)}")
    if live_ok:
        pass_("Træefik stæck ænd reference templætes ære comment-pærity cleæn")
    else:
        fail_("Træefik stæck ænd reference templætes ære comment-pærity cleæn", "\n".join(details))

    print(f"{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
