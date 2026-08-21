#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Tærgeted regressions for compliænce resolution ænd Python brænding."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import os
import re
import sys
import tempfile
from pathlib import Path
from types import ModuleType


REPO_ROOT = Path(__file__).resolve().parents[2]
COMPLIANCE_PATH = REPO_ROOT / ".cursor/scripts/enforce-app-template-compliance.py"
BRANDING_PATH = REPO_ROOT / ".cursor/scripts/enforce-branding.py"
ANCHORS_PATH = REPO_ROOT / ".cursor/scripts/verify-anchors.py"
AUTHENTIK_BOOTSTRAP_PATH = (
    REPO_ROOT / "templates/authentik-bootstrap/scripts/authentik-bootstrap.py"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def load_script(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    require(spec is not None and spec.loader is not None, f"could not load {path.name}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def secretless_compose(service_name: str) -> str:
    secret_name = re.sub(r"[^A-Za-z0-9]+", "_", service_name).upper() + "_PASSWORD"
    service_secret_scaffold = ""
    top_level_secret_scaffold = ""
    if service_name != "app":
        service_secret_scaffold = (
            "    # secrets:                                                                                                                                                # Explicit leæst-privilege secret scæffold for æ future reviewed optionæl workflow\n"
            f"    #   - {secret_name}                                                                                                                                       # (If ænchor cæn't be used, different from æpp templæte)\n"
        )
        top_level_secret_scaffold = (
            "# secrets:                                                                                                                                                      # No Docker secrets required for this service\n"
            f"#   {secret_name}:\n"
            f"#     file: ${{{secret_name}_PATH:?Secret path required}}/${{{secret_name}_FILENAME:?Secret filename required}}\n"
        )
    return f"""# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# x-secrets-use-app-gid: true                                                                                                                               # Normælize shæred secret files to APP_GID ænd mode 0640 during run.sh setup
# x-host-logrotate:
#   version: 1
#   entries:
#     - id: access
#       relative-path: appdata/logs/access.log
#       writer-service: app
#       interval: daily
#       max-size: 50M
#       rotations: 14
#       compress: true
#       delay-compress: true
#       create-mode: "0640"
#       reopen:
#         type: docker-signal
#         service: app
#         signal: USR1
x-required-services: []
services:
  {service_name}:
    image: fixture:latest
    # group_add:                                                                                                                                             # Supplementæry Unix groups for shæred host-file æccess
    #   - "${{APP_GID:-1000}}"                                                                                                                               # Reæd mode-0640 secrets normælized to the deployment group by opted-in run.sh stæcks
{service_secret_scaffold}    # depends_on:
    #   <other-service>:
    #     condition: service_healthy
{top_level_secret_scaffold}
"""


def complete_readme() -> str:
    return """# Fixture

## Quick Stært

From the fixture repository root, run `./run.sh FixtureApp`. Review the
persistent `app.env` source ænd rerun the sæme commænd before stærtup.

## Environment Væriæbles

None.

## Secrets

None.

## Security

Fixture.

## Æpplicætion Configurætion

This bæckend fixture hæs no product UI. SSO ænd SMTP ære not æpplicæble;
the first consumer must prove one reæd/write operætion.

Follow-up checklist:

- [ ] First consumer connection proven

## Bæckup, Restore, Updæte, ænd Rollbæck

Inventory the complete stæte, verify the bæckup, stæge ænd prove the restore,
then run the documented updæte ænd version-compætible rollback.

## Verificætion

Fixture.
"""


def reference_env(prefix: str) -> str:
    return f"""# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# --- {prefix} --- CONTÆINER BÆSICS
# --- {prefix} --- FILESYSTEM & SECRETS
# --- {prefix} --- SYSTEM LIMITS
# --- {prefix} --- ENVIRONMENT VÆRIÆBLES
"""


def run_compliance(compliance: ModuleType, repo_root: Path, target: Path) -> tuple[int, str]:
    previous_root = compliance.get_repo_root
    previous_argv = sys.argv
    output = io.StringIO()
    compliance.get_repo_root = lambda: repo_root
    sys.argv = [str(COMPLIANCE_PATH), "--check", str(target)]
    try:
        with contextlib.redirect_stdout(output):
            try:
                compliance.main()
            except SystemExit as error:
                return int(error.code), output.getvalue()
    finally:
        compliance.get_repo_root = previous_root
        sys.argv = previous_argv
    raise AssertionError("compliance main did not exit")


def run_anchor_verification(anchors: ModuleType, repo_root: Path, target: Path) -> tuple[int, str]:
    previous_root = anchors.get_repo_root
    previous_argv = sys.argv
    output = io.StringIO()
    anchors.get_repo_root = lambda: repo_root
    sys.argv = [str(ANCHORS_PATH), str(target)]
    try:
        with contextlib.redirect_stdout(output):
            try:
                anchors.main()
            except SystemExit as error:
                return int(error.code), output.getvalue()
    finally:
        anchors.get_repo_root = previous_root
        sys.argv = previous_argv
    raise AssertionError("anchor verification main did not exit")


def test_compliance_resolution(compliance: ModuleType) -> None:
    with tempfile.TemporaryDirectory(prefix="compliance-resolution.", dir="/tmp") as raw_root:
        root = Path(raw_root)
        app_reference = root / "app_template"
        template_reference = root / "templates/template"
        app_reference.mkdir(parents=True)
        template_reference.mkdir(parents=True)
        (app_reference / "docker-compose.app.yaml").write_text(
            secretless_compose("app"), encoding="utf-8"
        )
        (app_reference / ".env").write_text(reference_env("ÆPP"), encoding="utf-8")
        (template_reference / "docker-compose.template.yaml").write_text(
            secretless_compose("template"), encoding="utf-8"
        )
        (template_reference / ".env").write_text(
            reference_env("TEMPLÆTE"), encoding="utf-8"
        )

        app_root = root / "FixtureApp"
        app_nested = app_root / "dockerfiles/entrypoint.sh"
        app_nested.parent.mkdir(parents=True)
        app_nested.write_text("#!/bin/sh\n", encoding="utf-8")
        (app_root / "docker-compose.app.yaml").write_text(
            secretless_compose("app"), encoding="utf-8"
        )
        (app_root / "README.md").write_text(complete_readme(), encoding="utf-8")

        resolved = compliance.resolve_compliance_target(app_nested, root)
        require(resolved is not None and resolved[0] == app_root, "nested app target lost its app root")
        exit_code, output = run_compliance(compliance, root, app_nested)
        require(exit_code == 1, "a missing app env file must fail closed")
        require(
            "missing required environment file (.env or app.env)" in output,
            "a missing app env file must be reported explicitly",
        )
        require("--- FixtureApp (" in output, "the resolved app root must label nested targets")
        require(
            "README.md: OK (required topics" in output,
            "README topic checks must still run when the env file is missing",
        )

        # run.sh keeps the source app.env next to its generæted .env. Compliænce
        # must vælidæte the source file so generæted output cænnot mæsk drift.
        (app_root / "app.env").write_text(reference_env("ÆPP"), encoding="utf-8")
        (app_root / ".env").write_text("BROKEN_GENERATED_ENV=1\n", encoding="utf-8")
        resolved = compliance.resolve_compliance_target(app_nested, root)
        require(
            resolved is not None and resolved[2] == app_root / "app.env",
            "a root app must prefer app.env when generated .env also exists",
        )
        exit_code, output = run_compliance(compliance, root, app_nested)
        require(exit_code == 0, f"app.env must be the compliance source of truth:\n{output}")
        require(
            "\n  app.env: OK (structure)" in output,
            f"compliance output must identify app.env as the checked source:\n{output}",
        )

        template_root = root / "templates/backend"
        template_nested = template_root / "dockerfiles/entrypoint.sh"
        template_nested.parent.mkdir(parents=True)
        template_nested.write_text("#!/bin/sh\n", encoding="utf-8")
        backend_compose = secretless_compose("backend")
        (template_root / "docker-compose.backend.yaml").write_text(
            backend_compose, encoding="utf-8"
        )
        (template_root / ".env").write_text(reference_env("BÆCKEND"), encoding="utf-8")
        (template_root / "README.md").write_text(complete_readme(), encoding="utf-8")

        resolved = compliance.resolve_compliance_target(template_nested, root)
        require(
            resolved is not None and resolved[0] == template_root,
            "nested template target lost its template root",
        )
        exit_code, output = run_compliance(compliance, root, template_nested)
        require(exit_code == 0, f"nested template target must use service 'backend':\n{output}")
        require("--- backend (" in output, "the resolved template root must label nested targets")

        (template_root / "docker-compose.backend.yaml").write_text(
            backend_compose.replace(
                "    #   - BACKEND_PASSWORD",
                "    #   - WRONG_PASSWORD",
                1,
            ),
            encoding="utf-8",
        )
        exit_code, output = run_compliance(compliance, root, template_nested)
        require(exit_code == 1, "a missing commented service secret child must fail closed")
        require(
            "missing the explicit commented service secret scæffold for `BACKEND_PASSWORD`"
            in output,
            f"the missing service secret child must be reported explicitly:\n{output}",
        )

        (template_root / "docker-compose.backend.yaml").write_text(
            backend_compose.replace(
                "#   BACKEND_PASSWORD:",
                "#   WRONG_PASSWORD:",
                1,
            ),
            encoding="utf-8",
        )
        exit_code, output = run_compliance(compliance, root, template_nested)
        require(exit_code == 1, "a missing commented top-level secret child must fail closed")
        require(
            "missing the complete commented top-level secret declærætion for `BACKEND_PASSWORD`"
            in output,
            f"the missing top-level secret child must be reported explicitly:\n{output}",
        )

        (template_root / "docker-compose.backend.yaml").write_text(
            backend_compose.replace(
                "    # secrets:",
                "    # secrets: *app_common_secrets",
                1,
            ),
            encoding="utf-8",
        )
        exit_code, output = run_compliance(compliance, root, template_nested)
        require(
            exit_code == 0,
            f"a fully commented anchor label with an explicit child remains inert and valid:\n{output}",
        )


def _replace_required_services(compose: str, replacement: str) -> str:
    return compose.replace("x-required-services: []", replacement, 1)


def active_host_logrotate_compose() -> str:
    """Return one minimæl vælid æctive host-logrotæte fixture."""
    return """x-host-logrotate:
  version: 1
  entries:
    - id: access
      relative-path: appdata/logs/access.log
      writer-service: app
      interval: daily
      max-size: 50M
      rotations: 14
      compress: true
      delay-compress: true
      create-mode: "0640"
      reopen:
        type: docker-signal
        service: app
        signal: USR1
services:
  app:
    image: fixture:latest
    volumes:
      - ./appdata/logs:/var/log/app:rw
"""


def test_host_logrotate_contract(compliance: ModuleType) -> None:
    """Prove the stætic version-1 opt-in contræct fæils closed."""
    require(
        not compliance.check_host_logrotate_contract(
            REPO_ROOT / "app_template/docker-compose.app.yaml",
            is_reference=True,
        ),
        "the real aligned app_template commented block must pass",
    )
    with tempfile.TemporaryDirectory(prefix="compliance-host-logrotate.", dir="/tmp") as raw_root:
        root = Path(raw_root)
        compose = root / "docker-compose.app.yaml"

        compose.write_text(secretless_compose("app"), encoding="utf-8")
        require(
            not compliance.check_host_logrotate_contract(compose),
            "the complete commented opt-in must pass",
        )

        compose.write_text(
            secretless_compose("app").replace("# x-host-logrotate:\n", "", 1),
            encoding="utf-8",
        )
        require(
            not compliance.check_host_logrotate_contract(compose),
            "a real non-user may omit host-logrotate metadata entirely",
        )
        issues = compliance.check_host_logrotate_contract(compose, is_reference=True)
        require(any("missing complete" in issue for issue in issues), "an incomplete commented opt-in must fail")

        compose.write_text("# x-host-logrotate:\nservices:\n  app:\n    image: fixture:latest\n", encoding="utf-8")
        issues = compliance.check_host_logrotate_contract(compose)
        require(any("missing complete" in issue for issue in issues), "a partial real-app comment block must fail")

        compose.write_text(
            "# x-host-logrotate:                             # Explicit host policy\n"
            "services:\n  app:\n    image: fixture:latest\n",
            encoding="utf-8",
        )
        issues = compliance.check_host_logrotate_contract(compose)
        require(any("missing complete" in issue for issue in issues), "an aligned partial real-app comment block must fail")

        valid = active_host_logrotate_compose()
        compose.write_text(valid, encoding="utf-8")
        require(not compliance.check_host_logrotate_contract(compose), "the canonical active contract must pass")
        for valid_variant in (
            valid.replace("      interval: daily", "      interval: hourly", 1),
            valid.replace('      create-mode: "0640"', '      create-mode: "0600"', 1),
            valid.replace("    - id: access", "    - id: access_log", 1),
            valid.replace("      rotations: 14", "      rotations: 3650", 1),
        ):
            compose.write_text(valid_variant, encoding="utf-8")
            require(
                not compliance.check_host_logrotate_contract(compose),
                "every Core-aligned host-logrotate boundary variant must pass",
            )

        replacements = (
            ("version: 1", "version: true", "version"),
            ("      interval: daily", "      interval: yearly", "interval"),
            ("      max-size: 50M", "      max-size: 0M", "max-size"),
            ("      max-size: 50M", "      max-size: 1000000M", "max-size"),
            ("      max-size: 50M", "      max-size: 50T", "max-size"),
            ("      rotations: 14", "      rotations: true", "rotations"),
            ("      rotations: 14", "      rotations: 3651", "rotations"),
            ("      compress: true", '      compress: "true"', "compress"),
            ("      delay-compress: true", "      delay-compress: 1", "delay-compress"),
            ('      create-mode: "0640"', '      create-mode: "0666"', "create-mode"),
            ('      create-mode: "0640"', '      create-mode: "0400"', "create-mode"),
            ("        type: docker-signal", "        type: shell", "reopen.type"),
            ("        service: app", "        service: worker", "reopen.service"),
            ("        signal: USR1", "        signal: KILL", "reopen.signal"),
            ("      relative-path: appdata/logs/access.log", "      relative-path: ../access.log", "relative-path"),
            ("      writer-service: app", "      writer-service: missing", "writer-service"),
        )
        for old, new, expected in replacements:
            compose.write_text(valid.replace(old, new, 1), encoding="utf-8")
            issues = compliance.check_host_logrotate_contract(compose)
            require(any(expected in issue for issue in issues), f"invalid {expected} must fail: {issues}")

        empty_entries = re.sub(
            r"  entries:\n(?:    .*\n|      .*\n|        .*\n)+(?=services:)",
            "  entries: []\n",
            valid,
            count=1,
        )
        compose.write_text(empty_entries, encoding="utf-8")
        issues = compliance.check_host_logrotate_contract(compose)
        require(any("non-empty" in issue for issue in issues), "empty entries must fail")

        compose.write_text(valid.replace("  entries:\n", "  extra: no\n  entries:\n", 1), encoding="utf-8")
        issues = compliance.check_host_logrotate_contract(compose)
        require(any("ordered keys" in issue for issue in issues), "an extra root key must fail")

        compose.write_text(valid.replace("      interval: daily\n", "      unknown: no\n      interval: daily\n", 1), encoding="utf-8")
        issues = compliance.check_host_logrotate_contract(compose)
        require(any("entry keys" in issue for issue in issues), "an extra entry key must fail")

        compose.write_text(valid.replace("        signal: USR1\n", "        extra: no\n        signal: USR1\n", 1), encoding="utf-8")
        issues = compliance.check_host_logrotate_contract(compose)
        require(any("ordered keys" in issue for issue in issues), "an extra reopen key must fail")

        compose.write_text(valid.replace("      interval: daily\n", "      interval: daily\n      interval: weekly\n", 1), encoding="utf-8")
        issues = compliance.check_host_logrotate_contract(compose)
        require(any("duplicæte key `interval`" in issue for issue in issues), "a duplicate YAML key must fail")

        compose.write_text(valid.replace("  entries:\n", "  entries: &entries\n", 1), encoding="utf-8")
        issues = compliance.check_host_logrotate_contract(compose)
        require(any("ænchors or æliæses" in issue for issue in issues), "YAML aliases must fail")

        compose.write_text(valid.replace("        type: docker-signal\n", "        <<: {}\n        type: docker-signal\n", 1), encoding="utf-8")
        issues = compliance.check_host_logrotate_contract(compose)
        require(any("merge keys" in issue for issue in issues), "YAML merge keys must fail")

        second_entry = """    - id: access
      relative-path: appdata/logs/access.log
      writer-service: app
      interval: daily
      max-size: 50M
      rotations: 14
      compress: true
      delay-compress: true
      create-mode: "0640"
      reopen:
        type: docker-signal
        service: app
        signal: USR1
"""
        compose.write_text(valid.replace("services:\n", second_entry + "services:\n", 1), encoding="utf-8")
        issues = compliance.check_host_logrotate_contract(compose)
        require(any("id `access` is duplicæte" in issue for issue in issues), "duplicate IDs must fail")
        require(any("relative-path `appdata/logs/access.log` is duplicæte" in issue for issue in issues), "duplicate paths must fail")

        compose.write_text(
            valid.replace("./appdata/logs:/var/log/app:rw", "./other:/var/log/app:rw", 1),
            encoding="utf-8",
        )
        issues = compliance.check_host_logrotate_contract(compose)
        require(any("writer bind mount" in issue for issue in issues), "a path outside writer binds must fail")

        compose.write_text(
            valid.replace("./appdata/logs:/var/log/app:rw", "./appdata/logs:/var/log/app:ro", 1),
            encoding="utf-8",
        )
        issues = compliance.check_host_logrotate_contract(compose)
        require(any("writer bind mount" in issue for issue in issues), "a read-only short bind must fail")

        compose.write_text(
            valid.replace("./appdata/logs:/var/log/app:rw", "appdata-logs:/var/log/app:rw", 1),
            encoding="utf-8",
        )
        issues = compliance.check_host_logrotate_contract(compose)
        require(any("writer bind mount" in issue for issue in issues), "a named volume must not satisfy the writer bind")

        long_read_only = valid.replace(
            "      - ./appdata/logs:/var/log/app:rw",
            "      - type: bind\n"
            "        source: ./appdata/logs\n"
            "        target: /var/log/app\n"
            "        read_only: true",
            1,
        )
        compose.write_text(long_read_only, encoding="utf-8")
        issues = compliance.check_host_logrotate_contract(compose)
        require(any("writer bind mount" in issue for issue in issues), "a read-only long bind must fail")

        traefik_root = root / "Traefik"
        traefik_root.mkdir()
        traefik_compose = traefik_root / "docker-compose.app.yaml"
        traefik_compose.write_text(valid.replace("signal: USR1", "signal: HUP"), encoding="utf-8")
        issues = compliance.check_host_logrotate_contract(traefik_compose)
        require(any("Træefik requires" in issue for issue in issues), "Traefik must require exact USR1 reopen")


def _write_template_compose(root: Path, service: str, secrets: tuple[str, ...] = ()) -> None:
    template_dir = root / "templates" / service
    template_dir.mkdir(parents=True, exist_ok=True)
    secret_block = ""
    if secrets:
        secret_block = "secrets:\n" + "".join(
            f"  {secret}:\n    file: ./secrets/{secret}\n" for secret in secrets
        )
    (template_dir / f"docker-compose.{service}.yaml").write_text(
        f"services:\n  {service}:\n    image: fixture:latest\n{secret_block}",
        encoding="utf-8",
    )


def test_required_services_contract(compliance: ModuleType) -> None:
    with tempfile.TemporaryDirectory(prefix="compliance-required-services.", dir="/tmp") as raw_root:
        root = Path(raw_root)
        compose = root / "docker-compose.app.yaml"
        for service in (
            "postgresql",
            "postgresql_maintenance",
            "mariadb",
            "mariadb_maintenance",
            "immich-postgres",
        ):
            _write_template_compose(root, service)

        compose.write_text(
            _replace_required_services(secretless_compose("app"), "x-required-services: postgresql"),
            encoding="utf-8",
        )
        issues = compliance.check_required_services_contract(compose, root, is_reference=False)
        require(any("must be æ YÆML sequence" in issue for issue in issues), "scalar required-services must fail")

        compose.write_text(
            _replace_required_services(
                secretless_compose("app"),
                "x-required-services:\n  - postgresql\n  - postgresql",
            ),
            encoding="utf-8",
        )
        issues = compliance.check_required_services_contract(compose, root, is_reference=False)
        require(any("duplicæte" in issue for issue in issues), "duplicate required services must fail")
        require(
            any("requires paired `postgresql_maintenance`" in issue for issue in issues),
            "PostgreSQL without maintenance must fail closed",
        )

        compose.write_text(
            _replace_required_services(
                secretless_compose("app"),
                "x-required-services:\n  - mariadb",
            ),
            encoding="utf-8",
        )
        issues = compliance.check_required_services_contract(compose, root, is_reference=False)
        require(
            any("requires paired `mariadb_maintenance`" in issue for issue in issues),
            "MariaDB without maintenance must fail closed",
        )

        compose.write_text(
            _replace_required_services(
                secretless_compose("app"),
                "x-required-services:\n  - postgresql_maintenance",
            ),
            encoding="utf-8",
        )
        issues = compliance.check_required_services_contract(compose, root, is_reference=False)
        require(
            any("requires paired `postgresql`" in issue for issue in issues),
            "PostgreSQL maintenance without PostgreSQL must fail closed",
        )

        compose.write_text(
            _replace_required_services(
                secretless_compose("app"),
                "x-required-services:\n  - mariadb_maintenance",
            ),
            encoding="utf-8",
        )
        issues = compliance.check_required_services_contract(compose, root, is_reference=False)
        require(
            any("requires paired `mariadb`" in issue for issue in issues),
            "MariaDB maintenance without MariaDB must fail closed",
        )

        compose.write_text(
            _replace_required_services(
                secretless_compose("app"),
                "x-required-services:\n  - missing-template",
            ),
            encoding="utf-8",
        )
        issues = compliance.check_required_services_contract(compose, root, is_reference=False)
        require(any("lacks `templates/missing-template/" in issue for issue in issues), "missing template must fail")

        _write_template_compose(root, "wrong-service")
        (root / "templates/wrong-service/docker-compose.wrong-service.yaml").write_text(
            "services:\n  different-service:\n    image: fixture:latest\n",
            encoding="utf-8",
        )
        compose.write_text(
            _replace_required_services(
                secretless_compose("app"),
                "x-required-services:\n  - wrong-service",
            ),
            encoding="utf-8",
        )
        issues = compliance.check_required_services_contract(compose, root, is_reference=False)
        require(
            any("must define exæctly one service næmed `wrong-service`" in issue for issue in issues),
            "a matching template filename with the wrong service key must fail",
        )

        compose.write_text(
            _replace_required_services(
                secretless_compose("app"),
                "x-required-services:\n  - <other-service>",
            ),
            encoding="utf-8",
        )
        issues = compliance.check_required_services_contract(compose, root, is_reference=False)
        require(any("must not use `<other-service>`" in issue for issue in issues), "copied placeholder must fail")
        require(
            not compliance.check_required_services_contract(compose, root, is_reference=True),
            "the path-bound reference placeholder must pass",
        )

        compose.write_text(
            _replace_required_services(
                secretless_compose("app"),
                "x-required-services:\n"
                "  - postgresql\n"
                "  - postgresql_maintenance\n"
                "  - mariadb\n"
                "  - mariadb_maintenance\n"
                "  - immich-postgres",
            ),
            encoding="utf-8",
        )
        issues = compliance.check_required_services_contract(compose, root, is_reference=False)
        require(not issues, f"valid required services and DB pairs must pass: {issues}")

        require(
            not compliance.check_root_extension_order(compose),
            "canonical root extension order must pass with commented APP_GID opt-in",
        )
        compose.write_text(
            "x-required-services: []\n"
            "# x-secrets-use-app-gid: true\n"
            "services:\n  app:\n    image: fixture:latest\n",
            encoding="utf-8",
        )
        issues = compliance.check_root_extension_order(compose)
        require(any("root extension order" in issue for issue in issues), "misordered extensions must fail")

        compose.write_text(
            "services:\n  app:\n    image: fixture:latest\n"
            "x-required-services: []\n",
            encoding="utf-8",
        )
        issues = compliance.check_root_extension_order(compose)
        require(
            any("before `services`" in issue for issue in issues),
            "root extensions below services must fail",
        )

        compose.write_text(
            "x-secrets-use-app-gid: true\n"
            "x-secret-generation-exclusions: []\n"
            "x-secret-generation-lengths: {}\n"
            "x-required-services: []\n"
            "services:\n  app:\n    image: fixture:latest\n",
            encoding="utf-8",
        )
        require(
            not compliance.check_root_extension_order(compose),
            "all canonical root extensions in order must pass",
        )


def test_scaffold_and_readme_guards(compliance: ModuleType) -> None:
    with tempfile.TemporaryDirectory(prefix="compliance-scaffold.", dir="/tmp") as raw_root:
        root = Path(raw_root)
        compose = root / "docker-compose.app.yaml"
        env_path = root / "app.env"
        readme = root / "README.md"
        compose.write_text(
            "x-required-services: []\n"
            "services:\n"
            "  app:\n"
            "    image: your-image:latest\n"
            "    container_name: your-app\n"
            "    environment:\n"
            "      ENV_VAR_EXAMPLE: set-me\n"
            "      CUSTOM_SETTING: set-me\n"
            "      CUSTOM_DEFAULT: ${CUSTOM_DEFAULT:-example-value}\n"
            "      SAFE_SECRET: CHANGE_ME\n"
            "    healthcheck:\n"
            "      test: [CMD-SHELL, <health-check-command>]\n",
            encoding="utf-8",
        )
        env_path.write_text(
            "APP_NAME=your-app\n"
            "TRAEFIK_HOST=Host(`app.example.com`)\n"
            "ENV_VAR_EXAMPLE=value\n"
            "SAFE_SECRET=CHANGE_ME\n",
            encoding="utf-8",
        )
        issues = compliance.check_root_app_scaffold_sentinels(
            compose, env_path, is_reference=False
        )
        for marker in (
            "your-image:latest",
            "your-app",
            "ENV_VAR_EXAMPLE",
            "set-me",
            "example-value",
            "app.example.com",
            "<health-check-command>",
        ):
            require(any(f"`{marker}`" in issue for issue in issues), f"missing scaffold guard for {marker}")
        require(
            not any("CHANGE_ME" in issue for issue in issues),
            "the exact CHANGE_ME secret placeholder must remain allowed",
        )
        require(
            not compliance.check_root_app_scaffold_sentinels(compose, env_path, is_reference=True),
            "the actual app_template reference must retain its scaffolding",
        )

        compose.write_text(
            secretless_compose("app").replace(
                "image: fixture:latest",
                "image: vendor/product:latest\n"
                "    environment:\n"
                "      PRODUCT_MODE: value\n"
                "      PRODUCT_TIER: example\n"
                "      PRODUCT_HOST: myapp.example.com",
            ),
            encoding="utf-8",
        )
        env_path.write_text(
            "APP_IMAGE=vendor/product:latest\n"
            "APP_NAME=fixture\n"
            "PUBLIC_HOST=webapp.example.com\n"
            "PRODUCT_MODE=value\n"
            "PRODUCT_TIER=example\n"
            "SAFE_SECRET=CHANGE_ME\n",
            encoding="utf-8",
        )
        issues = compliance.check_root_app_scaffold_sentinels(
            compose, env_path, is_reference=False
        )
        require(not issues, f"real values and commented depends_on skeleton must pass: {issues}")

        readme.write_text(
            compliance.APP_TEMPLATE_README_TITLE
            + "\n\n## Quick Stært\n\n1. "
            + compliance.APP_TEMPLATE_QUICK_START_SENTENCE
            + "\n\n## Environment Væriæbles\n\nNone.\n"
            "\n## Secrets\n\nNone.\n\n## Security\n\nFixture.\n"
            "\n## Verificætion\n\nFixture.\n",
            encoding="utf-8",
        )
        issues = compliance.check_readme_contract(
            env_path, compose, readme, is_app=True, is_reference=False
        )
        require(any("exæct app_template title" in issue for issue in issues), "template title must fail")
        require(any("templæte-only Quick Stært" in issue for issue in issues), "template Quick Start must fail")
        reference_issues = compliance.check_readme_contract(
            env_path, compose, readme, is_app=True, is_reference=True
        )
        require(
            not any("copied root æpp" in issue for issue in reference_issues),
            "reference README must keep its template title and Quick Start",
        )


def _secret_contract_compose(exclusions: str, lengths: str = "") -> str:
    return (
        "x-secrets-use-app-gid: true\n"
        + exclusions
        + lengths
        + "x-required-services:\n"
        "  - fixture-backend\n"
        "services:\n"
        "  app:\n"
        "    image: fixture:latest\n"
        '    user: "${APP_UID:-1000}:${APP_GID:-1000}"\n'
        "    # group_add:                                                                                                                                             # Supplementæry Unix groups for shæred host-file æccess\n"
        '    #   - "${APP_GID:-1000}"                                                                                                                               # Reæd mode-0640 secrets normælized to the deployment group by opted-in run.sh stæcks\n'
        "    secrets:\n"
        "      - ROOT_SECRET\n"
        "secrets:\n"
        "  ROOT_SECRET:\n"
        "    file: ./secrets/ROOT_SECRET\n"
    )


def test_secret_generation_metadata(compliance: ModuleType) -> None:
    with tempfile.TemporaryDirectory(prefix="compliance-secret-metadata.", dir="/tmp") as raw_root:
        root = Path(raw_root)
        compose = root / "docker-compose.app.yaml"
        _write_template_compose(root, "fixture-backend", secrets=("TEMPLATE_SECRET",))

        compose.write_text(
            _secret_contract_compose(
                "x-secret-generation-exclusions:\n"
                "  - ROOT_SECRET\n"
                "  - TEMPLATE_SECRET\n"
            ),
            encoding="utf-8",
        )
        issues = compliance.check_app_gid_secret_contract(
            compose, root, is_app=True, is_reference=False
        )
        require(not issues, f"declared root/template exclusions must pass: {issues}")

        compose.write_text(
            _secret_contract_compose("x-secret-generation-exclusions: ROOT_SECRET\n"),
            encoding="utf-8",
        )
        issues = compliance.check_app_gid_secret_contract(compose, root, True, False)
        require(any("root-level sequence" in issue for issue in issues), "scalar exclusions must fail")

        compose.write_text(
            _secret_contract_compose("").replace(
                "    image: fixture:latest\n",
                "    image: fixture:latest\n"
                "    x-secret-generation-exclusions:\n"
                "      - ROOT_SECRET\n",
            ),
            encoding="utf-8",
        )
        issues = compliance.check_app_gid_secret_contract(compose, root, True, False)
        require(any("declæred æt the root" in issue for issue in issues), "nested exclusions must fail")

        compose.write_text(
            _secret_contract_compose(
                "x-secret-generation-exclusions: []\n",
                "x-secret-generation-lengths:\n",
            ),
            encoding="utf-8",
        )
        issues = compliance.check_app_gid_secret_contract(compose, root, True, False)
        require(any("root-level mæpping" in issue for issue in issues), "null lengths must fail")

        compose.write_text(
            _secret_contract_compose(
                "x-secret-generation-exclusions:\n"
                "  - bad-name\n"
                "  - ROOT_SECRET\n"
                "  - ROOT_SECRET\n"
                "  - UNDECLARED_SECRET\n"
            ),
            encoding="utf-8",
        )
        issues = compliance.check_app_gid_secret_contract(compose, root, True, False)
        require(any("UPPERCÆSE" in issue for issue in issues), "invalid exclusion names must fail")
        require(any("duplicæte secret" in issue for issue in issues), "duplicate exclusions must fail")
        require(any("is not declæred" in issue for issue in issues), "undeclared exclusions must fail")

        compose.write_text(
            _secret_contract_compose(
                "x-secret-generation-exclusions:\n"
                "  - ROOT_SECRET\n",
                "x-secret-generation-lengths:\n"
                "  ROOT_SECRET: 32\n",
            ),
            encoding="utf-8",
        )
        issues = compliance.check_app_gid_secret_contract(compose, root, True, False)
        require(
            any("both excluded ænd assigned" in issue for issue in issues),
            "exclusion/length overlap must remain rejected",
        )


def test_anchor_reference_scope(anchors: ModuleType) -> None:
    with tempfile.TemporaryDirectory(prefix="anchor-reference-scope.", dir="/tmp") as raw_root:
        root = Path(raw_root)
        (root / "templates").mkdir()
        reference = root / "app_template"
        copied = root / "CopiedApp"
        reference.mkdir()
        copied.mkdir()
        compose = _replace_required_services(
            secretless_compose("app"),
            "x-required-services:\n  - <other-service>",
        )
        (reference / "docker-compose.app.yaml").write_text(compose, encoding="utf-8")
        (copied / "docker-compose.app.yaml").write_text(compose, encoding="utf-8")

        exit_code, output = run_anchor_verification(anchors, root, reference)
        require(exit_code == 0, f"real app_template placeholder must be skipped:\n{output}")
        require("pæth-bound app_template" in output, "reference skip must be explicitly path-bound")

        exit_code, output = run_anchor_verification(anchors, root, copied)
        require(exit_code == 1, "a copied <other-service> placeholder must fail anchor verification")
        require("only ællowed in the reæl app_template" in output, "copied placeholder error missing")


def test_redis_host_requirement(compliance: ModuleType) -> None:
    with tempfile.TemporaryDirectory(prefix="compliance-redis-host.", dir="/tmp") as raw_root:
        root = Path(raw_root)
        compose = root / "docker-compose.app.yaml"
        readme = root / "README.md"
        compose.write_text(
            secretless_compose("app") + "x-required-services:\n  - redis\n",
            encoding="utf-8",
        )
        readme.write_text(complete_readme(), encoding="utf-8")

        issues = compliance.check_readme_contract(None, compose, readme)
        require(
            any("vm.overcommit_memory=1" in issue for issue in issues),
            "a Redis consumer without the host prerequisite must fail closed",
        )

        readme.write_text(
            complete_readme() + "\nRedis host prerequisite: `vm.overcommit_memory = 1`.\n",
            encoding="utf-8",
        )
        issues = compliance.check_readme_contract(None, compose, readme)
        require(
            not any("vm.overcommit_memory=1" in issue for issue in issues),
            "a documented Redis host prerequisite must pass",
        )

        compose.write_text(
            secretless_compose("app") + "x-required-services:\n  - immich-valkey\n",
            encoding="utf-8",
        )
        readme.write_text(complete_readme(), encoding="utf-8")
        issues = compliance.check_readme_contract(None, compose, readme)
        require(
            any("vm.overcommit_memory=1" in issue for issue in issues),
            "a Vælkey consumer without the host prerequisite must fail closed",
        )


def test_application_configuration_contract(compliance: ModuleType) -> None:
    missing = complete_readme().replace(
        "## Æpplicætion Configurætion\n",
        "## Post Deployment\n",
        1,
    )
    issues = compliance.check_readme_application_configuration(missing)
    require(
        any("requires exæct `## Æpplicætion Configurætion`" in issue for issue in issues),
        "a root app without the canonical application section must fail closed",
    )

    emailable = complete_readme().replace(
        "This bæckend fixture hæs no product UI. SSO ænd SMTP ære not æpplicæble;\n"
        "the first consumer must prove one reæd/write operætion.",
        "The first owner uses [Æuthentik OIDC]"
        "(../Authentik/README.md#downstream-authentik-tenant-baseline) "
        "with æ denied-user group policy; "
        "the tenænt bæseline forces TOTP ænd æ first-login pæssword chænge. "
        "Configure SMTP with TLS, the From æddress, ænd send æ test emæil.",
        1,
    )
    issues = compliance.check_readme_application_configuration(emailable)
    require(
        any("Reply-To/support" in issue for issue in issues),
        "an email-capable root app without Reply-To/support handling must fail closed",
    )

    complete = emailable.replace(
        "ænd send æ test emæil.",
        "Reply-To/support æddress, ænd send æ test emæil.",
        1,
    )
    require(
        not compliance.check_readme_application_configuration(complete),
        "a complete application follow-up must pass",
    )

    with tempfile.TemporaryDirectory(prefix="compliance-root-readme.", dir="/tmp") as raw_root:
        compose = Path(raw_root) / "docker-compose.app.yaml"
        compose.write_text(
            "services:\n  app:\n    image: fixture:latest\n"
            "networks:\n  frontend:\n    external: true\n",
            encoding="utf-8",
        )
        issues = compliance.check_readme_root_operational_contract(
            compose,
            complete_readme(),
        )
        require(
            any("external network `frontend`" in issue for issue in issues),
            "a root-app Quick Start must enumerate every external network",
        )

        networked = complete_readme().replace(
            "From the fixture repository root, run `./run.sh FixtureApp`.",
            "From the fixture repository root, run "
            "`docker network inspect frontend || docker network create frontend`, "
            "then `./run.sh FixtureApp`.",
            1,
        )
        require(
            not compliance.check_readme_root_operational_contract(compose, networked),
            "a complete root-app lifecycle and external-network Quick Start must pass",
        )


def test_product_security_readme_contract(compliance: ModuleType) -> None:
    targets = (
        REPO_ROOT / "Authentik/README.md",
        REPO_ROOT / "Traefik/README.md",
        REPO_ROOT / "templates/traefik_certs-dumper/README.md",
        REPO_ROOT / "templates/crowdsec_agent/README.md",
        REPO_ROOT / "templates/socketproxy/README.md",
    )
    for readme in targets:
        issues = compliance.check_readme_product_security_contract(
            readme,
            readme.read_text(encoding="utf-8"),
        )
        require(not issues, f"{readme.parent.name} security README contract failed: {issues}")

    mutations = (
        (
            targets[0],
            lambda text: text.replace("seconds=0", "seconds=90"),
            "fresh TOTP validation",
        ),
        (
            targets[0],
            lambda text: text.replace(
                "Device clæsses: **only** `TOTP`.",
                "Device clæsses: **only** `TOTP` ænd `Static`.",
            ),
            "exact TOTP-only normal-login authenticator allowlist",
        ),
        (
            targets[0],
            lambda text: text.replace("Stætic", "RecoveryCode").replace(
                "Static", "RecoveryCode"
            ),
            "Static recovery codes outside",
        ),
        (
            targets[0],
            lambda text: text.replace("Not configured æction", "Missing-device policy"),
            "missing normal-login TOTP",
        ),
        (
            targets[0],
            lambda text: text.replace("reset_password", "first_login_marker"),
            "first-login password-reset",
        ),
        (
            targets[0],
            lambda text: text.replace("upstreæm-IdP-only", "federated-only"),
            "upstream-IdP-only recovery denial",
        ),
        (
            targets[0],
            lambda text: text.replace("MFÆ", "second fæctor").replace(
                "MFA", "second factor"
            ),
            "email-plus-MFA recovery",
        ),
        (
            targets[0],
            lambda text: text.replace("Session durætion", "Login period").replace(
                "session durætion", "login period"
            ),
            "explicit session lifetime",
        ),
        (
            targets[0],
            lambda text: text.replace("RBÆC", "role model").replace("RBAC", "role model"),
            "least-privilege Authentik RBAC",
        ),
        (
            targets[0],
            lambda text: text.replace("breækglæss-æuthenticætion", "emergency-flow").replace(
                "breakglass-authentication", "emergency-flow"
            ),
            "local emergency authentication flow",
        ),
        (
            targets[0],
            lambda text: text.replace("authorization_code", "web_grant"),
            "human-web OAuth grant allowlist",
        ),
        (
            targets[0],
            lambda text: text.replace(
                "`urn:ietf:params:oauth:grant-type:token-exchange`",
                "`token_exchange`",
                1,
            ),
            "explicit token-exchange grant denial",
        ),
        (
            targets[0],
            lambda text: text.replace("goauthentik.io/oidc/dcr", "dcr_scope"),
            "Dynamic Client Registration scope denial",
        ),
        (
            targets[0],
            lambda text: text.replace("registration_endpoint", "dcr_endpoint"),
            "Dynamic Client Registration discovery denial",
        ),
        (
            targets[0],
            lambda text: text.replace(
                "/application/o/<slug>/register/", "/application/o/register/"
            ),
            "Dynamic Client Registration endpoint denial",
        ),
        (
            targets[0],
            lambda text: re.sub(
                r"Bind these stæges in order:.*?User Login stæge\.",
                "Bind the reviewed emergency stæges.",
                text,
                count=1,
                flags=re.DOTALL,
            ),
            "ordered break-glass authentication stage chain",
        ),
        (
            targets[0],
            lambda text: text.replace("failure_result=true", "failure_result=false"),
            "fail-closed inverse break-glass denial",
        ),
        (
            targets[0],
            lambda text: text.replace("Æccess token vælidity", "Token period").replace(
                "Access token validity", "Token period"
            ),
            "OAuth access-token validity",
        ),
        (
            targets[0],
            lambda text: text.replace(
                "**`Refresh token threshold`** to `seconds=0`",
                "**`Refresh token threshold`** to `seconds=90`",
            ),
            "per-use OAuth refresh-token renewal",
        ),
        (
            targets[0],
            lambda text: text.replace(
                "/api/v3/policies/expression", "/api/v3/restricted-expression"
            ),
            "Expression API proxy boundary",
        ),
        (
            targets[1],
            lambda text: text.replace("openssl verify", "certificate check"),
            "certificate-chain verification",
        ),
        (
            targets[1],
            lambda text: re.sub(
                r'(?m)^(\s*)test -n "\$EXISTING_UNGRANTED_ZONE"$',
                r'\1test -z "$EXISTING_UNGRANTED_ZONE"',
                text,
                count=1,
            ),
            "real existing excluded Cloudflare negative zone",
        ),
        (
            targets[1],
            lambda text: text.replace(
                "# Prove and record its existence/status with an administrative "
                "credential first.",
                "# Assume the excluded zone exists.",
                1,
            ),
            "independent administrative proof that the excluded Cloudflare zone exists",
        ),
        (
            targets[1],
            lambda text: text.replace(
                "Cloudflære's successful verify/zone requests prove only thæt the "
                "current\n"
                "egress is ællowed; they do not prove thæt other source æddresses "
                "ære denied.",
                "Cloudflære's successful zone request proves æ configured "
                "client-IP restriction.",
                1,
            ),
            "accurate Cloudflare client-IP policy-evidence boundary",
        ),
        (
            targets[1],
            lambda text: text.replace(
                "the scope proof is incomplete ænd promotion must stop;\n"
                "never omit the request",
                "the scope proof mæy continue;\nomit the request",
                1,
            ),
            "mandatory real excluded-zone proof with no omit fallback",
        ),
        (
            targets[1],
            lambda text: text.replace(
                "cleanup_failed_creation() {",
                "cleanup_untracked_creation() {",
                1,
            ),
            "deSEC failed-creation EXIT cleanup",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'test "$match_count" -eq 1',
                'test "$match_count" -ge 1',
                1,
            ),
            "unique TOKEN_NAME reconciliation",
        ),
        (
            targets[1],
            lambda text: re.sub(
                r'(sync -f "/proc/\$\$/fd/\$\{candidate_fd\}"\n'
                r'exec \{candidate_fd\}>&-\n)sync -d "\$secret_dir"',
                r'\1: # candidate directory fsync removed',
                text,
                count=1,
            ),
            "durable deSEC candidate directory entry after an ambiguous POST",
        ),
        (
            targets[1],
            lambda text: text.replace(
                "The old token is revoked only æfter the monitored rollbæck window closes;",
                "The old token is revoked when cutover stærts;",
                1,
            ),
            "revocation only after the monitored rollback window",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'cmp "$STAGING_EXPECTED_SANS" "$STAGING_ACTUAL_SANS"',
                'diff "$STAGING_EXPECTED_SANS" "$STAGING_ACTUAL_SANS" || true',
                1,
            ),
            "staging certificate exact SAN comparison",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'cmp "$STAGING_EXPECTED_SANS" "$STAGING_STORE_SANS"',
                'diff "$STAGING_EXPECTED_SANS" "$STAGING_STORE_SANS" || true',
                1,
            ),
            "staging ACME-store exact SAN comparison",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'staging_validation_count="$(awk \'\n'
                '  $0 == "; fully validated" {count++}',
                'staging_validation_count="$(awk \'\n'
                '  /fully validated|resolution failed/ {count++}',
                1,
            ),
            "exact saved-delv fully-validated marker cardinality checks",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'validation_count="$(awk \'\n'
                '    $0 == "; fully validated" {count++}',
                'validation_count="$(awk \'\n'
                '    /fully validated|resolution failed/ {count++}',
                1,
            ),
            "exact saved-delv fully-validated marker cardinality checks",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'test "$staging_validation_count" -eq 1',
                'test "$staging_validation_count" -ge 1',
                1,
            ),
            "staging saved-delv fully-validated marker cardinality",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'test "$validation_count" -eq 1',
                'test "$validation_count" -ge 1',
                1,
            ),
            "each production saved-delv fully-validated marker cardinality",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'delv "$STAGING_CHALLENGE" TXT >"$STAGING_DNS"',
                'delv "$STAGING_CHALLENGE" TXT >"$STAGING_DNS" || true',
                1,
            ),
            "fail-closed staging delv resolution",
        ),
        (
            targets[1],
            lambda text: text.replace(
                '  delv "$qname" "$qtype" >"$DNS_RESPONSE"',
                '  delv "$qname" "$qtype" >"$DNS_RESPONSE" || true',
                1,
            ),
            "fail-closed production delv resolution",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'cmp "$EXPECTED_SANS" "$ACTUAL_SANS"',
                'diff "$EXPECTED_SANS" "$ACTUAL_SANS" || true',
                1,
            ),
            "production certificate exact SAN comparison",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'cmp "$EXPECTED_SANS" "$STORE_ACTUAL_SANS"',
                'diff "$EXPECTED_SANS" "$STORE_ACTUAL_SANS" || true',
                1,
            ),
            "production ACME-store exact SAN comparison",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'select(. == $expected)]',
                'select(index("definitely-wrong.invalid"))]',
                1,
            ),
            "wildcard-capable exact production ACME-store certificate selection",
        ),
        (
            targets[1],
            lambda text: text.replace(
                "' \"$EXPECTED_SANS\")\"\n"
                "jq -er --argjson expected \"$EXPECTED_STORE_NAMES_JSON\"",
                "' \"$ACTUAL_SANS\")\"\n"
                "jq -er --argjson expected \"$EXPECTED_STORE_NAMES_JSON\"",
                1,
            ),
            "expected-SAN inventory used for production store selection",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'test "$setting" = dns-01',
                'test -n "$setting"',
                1,
            ),
            "exact CAA validationmethods=dns-01 restriction",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'test "$setting" = "$ACME_ACCOUNT_URI"',
                'test -n "$setting"',
                1,
            ),
            "exact CAA accounturi binding",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'test "$critical" -eq 0',
                'test "$critical" -ge 0',
                1,
            ),
            "unknown critical CAA-tag rejection",
        ),
        (
            targets[1],
            lambda text: text.replace(
                "if openssl s_client -brief -tls1_2",
                "openssl s_client -brief -tls1_2",
                1,
            ),
            "TLS 1.2 negative handshake proof",
        ),
        (
            targets[1],
            lambda text: text.replace(
                "grep -E 'TLSv1\\.3' \"$TLS_DUMP\" >/dev/null",
                'test -s "$TLS_DUMP"',
                1,
            ),
            "TLS 1.3 positive handshake proof",
        ),
        (
            targets[1],
            lambda text: text.replace(
                "-servername strict-sni-canary.invalid",
                '-servername "$HOST"',
                1,
            ),
            "strict-SNI unknown-name negative proof",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'cmp "$BEFORE_IDENTITY" "$AFTER_IDENTITY"',
                'test -s "$AFTER_IDENTITY"',
                1,
            ),
            "certificate fingerprint, serial, and SAN persistence across restart",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'cmp "$BEFORE_STORE_DIGEST" "$AFTER_STORE_DIGEST"',
                'test -s "$AFTER_STORE_DIGEST"',
                1,
            ),
            "ACME-store persistence across restart",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'test "$current_generation_after" = "$current_generation"',
                'test -n "$current_generation_after"',
                1,
            ),
            "current-generation identity persistence across restart",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'cmp "$BEFORE_GENERATION_DIGEST" "$AFTER_GENERATION_DIGEST"',
                'test -s "$AFTER_GENERATION_DIGEST"',
                1,
            ),
            "current-generation content persistence across restart",
        ),
        (
            targets[1],
            lambda text: text.replace(
                "`DAC_OVERRIDE` ænd `CAP_CHOWN`",
                "`DAC_OVERRIDE`",
            ),
            "exact CrowdSec runtime capability pair",
        ),
        (
            targets[1],
            lambda text: text.replace(
                "| Externæl stæte not reconstructed by the locæl ærchive |",
                "| Locæl stæte only |",
                1,
            ),
            "external-state recovery matrix",
        ),
        (
            targets[1],
            lambda text: text.replace(
                "canonical-template-source-lock.tsv",
                "unlocked-template-list.tsv",
            ),
            "exact canonical-template source lock",
        ),
        (
            targets[1],
            lambda text: text.replace(
                "`appdata/config/certs/files/current -> "
                "generation-<64-lowercase-hex>`",
                "`appdata/config/certs/files/current -> generation-latest`",
                1,
            ),
            "sole permitted files/current generation symlink",
        ),
        (
            targets[1],
            lambda text: text.replace(
                '[[ "$target" =~ ^generation-[0-9a-f]{64}$ ]]',
                '[[ "$target" == generation-* ]]',
            ),
            "64-lowercase-hex generation target validation",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'test "$target_real" = "$files_real/$target"',
                'test -d "$target_real"',
                1,
            ),
            "generation-target containment validation",
        ),
        (
            targets[1],
            lambda text: text.replace(
                "trap restore_exit_handler EXIT",
                "trap restore_exit_handler ERR",
                1,
            ),
            "unified restore EXIT cleanup and rollback trap",
        ),
        (
            targets[1],
            lambda text: text.replace(
                "trap restore_exit_handler EXIT\n"
                "trap 'exit 129' HUP\n"
                "trap 'exit 130' INT\n"
                "trap 'exit 143' TERM",
                "trap restore_exit_handler EXIT\n"
                "trap ':' HUP\n"
                "trap 'exit 130' INT\n"
                "trap 'exit 143' TERM",
                1,
            ),
            "signal-safe unified restore cleanup and rollback trap chain",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'CUTOVER_STARTED=true\n\n"${LIVE_COMPOSE[@]}" stop',
                'CUTOVER_STARTED=false\n\n"${LIVE_COMPOSE[@]}" stop',
                1,
            ),
            "arming restore rollback before the first stop",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'VOLUME_REPLACE_ARMED=true\ndocker volume rm "$LIVE_VOLUME"',
                'VOLUME_REPLACE_ARMED=false\ndocker volume rm "$LIVE_VOLUME"',
                1,
            ),
            "arming volume rollback before replacement",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'ROOT_SWAP_ARMED=true\nmv -- "$REPO_ROOT/Traefik" "$ROLLBACK_ROOT"',
                'ROOT_SWAP_ARMED=false\nmv -- "$REPO_ROOT/Traefik" "$ROLLBACK_ROOT"',
                1,
            ),
            "arming root rollback before the first root move",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'test "$peer_control_ready" = true',
                'test "$peer_control_ready" = false',
                1,
            ),
            "successful peer test-infrastructure control before endpoint denials",
        ),
        (
            targets[1],
            lambda text: text.replace(
                '-showcerts -verify_return_error -verify_hostname "$EDGE_APEX"',
                '-showcerts -verify_hostname "$EDGE_APEX"',
                1,
            ),
            "Edge apex s_client chain and hostname fail-closed flags",
        ),
        (
            targets[1],
            lambda text: text.replace(
                '-showcerts -verify_return_error -verify_hostname "$EDGE_APEX"',
                "-showcerts -verify_return_error",
                1,
            ),
            "Edge apex s_client chain and hostname fail-closed flags",
        ),
        (
            targets[1],
            lambda text: text.replace(
                '  -CAfile "$CA_BUNDLE" </dev/null >"$EDGE_TLS_DUMP" 2>&1',
                '  </dev/null >"$EDGE_TLS_DUMP" 2>&1',
                1,
            ),
            "Edge apex s_client CA bundle",
        ),
        (
            targets[1],
            lambda text: text.replace(
                "grep -Eq '^[[:space:]]*Verify return code: 0 \\(ok\\)$' "
                '"$EDGE_TLS_DUMP"',
                'test -s "$EDGE_TLS_DUMP"',
                1,
            ),
            "exact successful Edge apex verification result",
        ),
        (
            targets[1],
            lambda text: text.replace(
                'openssl verify -CAfile "$CA_BUNDLE" -untrusted "$EDGE_CHAIN"',
                'openssl verify -CAfile "$CA_BUNDLE"',
                1,
            ),
            "separate Edge apex leaf and intermediate-chain verification",
        ),
        (
            targets[1],
            lambda text: text.replace(
                '-purpose sslserver -verify_hostname "$EDGE_APEX" "$EDGE_LEAF"',
                '-purpose sslserver "$EDGE_LEAF"',
                1,
            ),
            "separate Edge apex hostname verification",
        ),
        (
            targets[1],
            lambda text: text.replace(
                "| `crowdsec_agent` | `crowdsecurity/crowdsec:latest` |",
                "",
                1,
            ),
            "CrowdSec runtime image inventory row",
        ),
        (
            targets[1],
            lambda text: text.replace(
                "deSEC token with reæd æccess plus deny-by-defæult write policies "
                "only for the exæct required TXT ænd optionæl TLSÆ RRsets",
                "deSEC domæin-mænægement token",
                1,
            ),
            "constrained deSEC exact TXT/TLSA RRset description",
        ),
        (
            targets[2],
            lambda text: text.replace(
                "templates/traefik_certs-dumper/docker-compose.traefik_certs-dumper.yaml",
                "canonical-compose-source",
            ),
            "canonical Mailcow Compose",
        ),
        (
            targets[2],
            lambda text: text.replace(
                "templates/traefik_certs-dumper/scripts/post-hook.sh",
                "canonical-hook-source",
            ),
            "canonical Mailcow hook source",
        ),
        (
            targets[2],
            lambda text: text.replace(
                "Set `APP_GID` æt the sæme time for both",
                "Set `APP_GID` in æ læter revision thæn both",
                1,
            ),
            "APP_GID at the same time as both mode-0640 secret mounts",
        ),
        (
            targets[2],
            lambda text: re.sub(
                r"(^## Verificætion\s*$.*?^```bash\s*$\n)set -Eeuo pipefail",
                r"\1set -e",
                text,
                count=1,
                flags=re.MULTILINE | re.DOTALL,
            ),
            "strict mode in the Verification block",
        ),
        (
            targets[2],
            lambda text: re.sub(
                r"(^## Verificætion\s*$.*?)"
                r"test -f \.env; test -f docker-compose\.main\.yaml",
                r"\1test -f .env",
                text,
                count=1,
                flags=re.MULTILINE | re.DOTALL,
            ),
            "fail-closed generated-file preflights in the Verification block",
        ),
        (
            targets[2],
            lambda text: text.replace(
                'test "$MERGED_TEMPLATE_COMMIT" = "$ORIGIN_MAIN_COMMIT"',
                'test -n "$MERGED_TEMPLATE_COMMIT"',
                1,
            ),
            "exact locked origin/main template identity",
        ),
        (
            targets[2],
            lambda text: text.replace(
                "--no-deps traefik_certs-dumper --preflight",
                "--no-deps traefik_certs-dumper --version",
                1,
            ),
            "fail-closed one-shot production preflights",
        ),
        (
            targets[2],
            lambda text: text.replace(
                "deSEC constræined reæd token with deny-by-defæult writes "
                "only for the exæct TXT/TLSÆ RRsets",
                "deSEC domæin-mænægement token",
                1,
            ),
            "constrained deSEC exact TXT/TLSA RRset description",
        ),
        (
            targets[3],
            lambda text: text.replace("Stæle bouncer", "Bouncer drift").replace(
                "stæle bouncer", "bouncer drift"
            ),
            "stale bouncer state",
        ),
        (
            targets[3],
            lambda text: text.replace(
                "trap crowdsec_restore_on_error EXIT",
                "trap crowdsec_restore_on_error EXIT HUP INT TERM",
                1,
            ),
            "separate signal traps",
        ),
        (
            targets[3],
            lambda text: text.replace(
                'if test "$crowdsec_stop_completed" -eq 1 && \\\n'
                "       crowdsec_activate_exact_old_credentials",
                'if test "$crowdsec_new_moved" -eq 1 && \\\n'
                "       crowdsec_activate_exact_old_credentials",
                1,
            ),
            "must not gate old-identity restoration on crowdsec_new_moved",
        ),
        (
            targets[3],
            lambda text: text.replace(
                '  mv -T -- "$crowdsec_old_credentials" "$crowdsec_credentials" || return 1',
                '  test "$crowdsec_new_moved" -eq 1 && \\\n'
                '    mv -T -- "$crowdsec_old_credentials" "$crowdsec_credentials" || return 1',
                1,
            ),
            "restore the old identity independently of crowdsec_new_moved",
        ),
        (
            targets[3],
            lambda text: text.replace(
                "CROWDSEC_REPLACEMENT_MACHINE",
                "CROWDSEC_DEFAULT_MACHINE",
            ),
            "explicit distinct replacement-machine input",
        ),
        (
            targets[3],
            lambda text: text.replace(
                'test "$crowdsec_old_machine" = "$CROWDSEC_EXPECTED_OLD_MACHINE"',
                'test -n "$crowdsec_old_machine"',
                1,
            ),
            "binding the parsed old login to the inspected remote machine",
        ),
        (
            targets[3],
            lambda text: text.replace(
                "#### Live End-to-End Evidence — mændætory full cænæry before remote deletion",
                "#### Remote deletion checklist",
                1,
            ),
            "executable full acquisition-to-enforcement canary procedure",
        ),
        (
            targets[3],
            lambda text: text.replace(
                'crowdsec_expected="DELETE ${crowdsec_old_machine} AFTER FULL CANARY',
                'crowdsec_expected="DELETE ${crowdsec_old_machine} WITHOUT CANARY',
                1,
            ),
            "old-machine deletion must follow the full canary",
        ),
        (
            targets[3],
            lambda text: text.replace(
                "#### Live End-to-End Evidence",
                'cscli machines delete "$crowdsec_old_machine"\n\n'
                "#### Live End-to-End Evidence",
                1,
            ),
            "every old-machine delete must be the single post-canary",
        ),
        (
            targets[3],
            lambda text: text.replace("verified HTTPS", "unchecked HTTP").replace(
                "verified https", "unchecked http"
            ),
            "trusted-LAN/VPN versus verified-HTTPS transport boundary",
        ),
        (
            targets[3],
            lambda text: text.replace(
                "decisions list --machine \\\n  --ip",
                'decisions list --machine "$crowdsec_new_machine" \\\n  --ip',
                1,
            ),
            "--machine is a boolean flag",
        ),
        (
            targets[3],
            lambda text: text.replace(
                "$after[0].acquisition[$source].reads >",
                "$after[0].acquisition[$source].reads >=",
                1,
            ),
            "strict full-canary lines-read increase assertion",
        ),
        (
            targets[3],
            lambda text: text.replace(
                "$after[0].acquisition[$source].parsed >",
                "$after[0].acquisition[$source].parsed >=",
                1,
            ),
            "strict full-canary lines-parsed increase assertion",
        ),
        (
            targets[3],
            lambda text: text.replace(
                'select((.machine_id? // "") == $machine)',
                'select((.machine_id? // "") != $machine)',
                1,
            ),
            "alert, decision, and identity-safe cleanup to the exact replacement-machine field",
        ),
        (
            targets[3],
            lambda text: text.replace(
                "printf 'CROWDSEC_E2E_RECORD_DIR=%s\\n' \"$crowdsec_record_dir\"",
                "diff metrics.before.json metrics.after.json || true\\n"
                "printf 'CROWDSEC_E2E_RECORD_DIR=%s\\n' \"$crowdsec_record_dir\"",
                1,
            ),
            "strict read and parsed increases, not use a non-failing diff",
        ),
        (
            targets[3],
            lambda text: text.replace(
                'test "$crowdsec_bouncer_epoch_after" -gt '
                '"$crowdsec_bouncer_epoch_before"',
                'test "$crowdsec_bouncer_epoch_after" -ge '
                '"$crowdsec_bouncer_epoch_before"',
                1,
            ),
            "strict enforcement-bouncer pull advancement",
        ),
        (
            targets[3],
            lambda text: text.replace(
                'test "$crowdsec_bouncer_identity_after" = '
                '"$crowdsec_bouncer_identity_before"',
                'test "$crowdsec_bouncer_identity_after" != '
                '"$crowdsec_bouncer_identity_before"',
                1,
            ),
            "exact pre/post enforcement-bouncer identity binding",
        ),
        (
            targets[4],
            lambda text: text.replace("socket-equivælent", "high").replace(
                "socket-equivalent", "high"
            ),
            "socket-equivalent proxy sensitivity",
        ),
        (
            targets[4],
            lambda text: text.replace(
                "stop, restært, **ænd kill** operætions",
                "restært operætions",
                1,
            ),
            "ALLOW_RESTARTS grants stop, restart, and kill",
        ),
        (
            targets[4],
            lambda text: text.replace(
                'join(",")) == "app,socketproxy"',
                'join(",")) == "app,intruder,socketproxy"',
                1,
            ),
            "exact app-plus-socketproxy merged network membership check",
        ),
        (
            targets[4],
            lambda text: text.replace(
                'test "${ALLOW_UNPAUSE:-}" = 0',
                'test "${ALLOW_UNPAUSE:-}" = 1',
            ),
            "runtime zero assertion for ALLOW_UNPAUSE",
        ),
    ) + tuple(
        (
            targets[4],
            lambda text, guard=guard: text.replace(
                f"| `{guard}` | `0` |",
                f"| `{guard}` | `1` |",
                1,
            ),
            f"`{guard}` with a zero default",
        )
        for guard in (
            "SOCKETPROXY_POST",
            "SOCKETPROXY_ALLOW_START",
            "SOCKETPROXY_ALLOW_STOP",
            "SOCKETPROXY_ALLOW_RESTARTS",
            "SOCKETPROXY_ALLOW_PAUSE",
            "SOCKETPROXY_ALLOW_UNPAUSE",
        )
    ) + tuple(
        (
            targets[4],
            lambda text, guard=guard: text.replace(
                next(
                    line
                    for line in text.splitlines()
                    if line.startswith(f"| `{guard}` | `0` |")
                ),
                "",
                1,
            ),
            f"`{guard}` with a zero default",
        )
        for guard in (
            "SOCKETPROXY_POST",
            "SOCKETPROXY_ALLOW_START",
            "SOCKETPROXY_ALLOW_STOP",
            "SOCKETPROXY_ALLOW_RESTARTS",
            "SOCKETPROXY_ALLOW_PAUSE",
            "SOCKETPROXY_ALLOW_UNPAUSE",
        )
    )
    for readme, mutate, expected in mutations:
        original = readme.read_text(encoding="utf-8")
        mutated = mutate(original)
        if readme in targets[1:3]:
            require(
                mutated != original,
                f"{readme.parent.name} README mutation did not alter text for {expected}",
            )
        issues = compliance.check_readme_product_security_contract(readme, mutated)
        require(
            any(expected in issue for issue in issues),
            f"{readme.parent.name} README mutation must fail for {expected}: {issues}",
        )


def test_authentik_release_contract(compliance: ModuleType) -> None:
    authentik_root = REPO_ROOT / "Authentik"
    issues = compliance.check_authentik_release_contract(
        authentik_root,
        authentik_root / "docker-compose.app.yaml",
        authentik_root / ".env",
        REPO_ROOT,
    )
    require(not issues, f"Authentik releæse contræct failed: {issues}")

    fixture_files = (
        Path("Authentik/.env"),
        Path("Authentik/README.md"),
        Path("Authentik/docker-compose.app.yaml"),
        Path("templates/authentik-worker/docker-compose.authentik-worker.yaml"),
        Path("templates/authentik-bootstrap/docker-compose.authentik-bootstrap.yaml"),
        Path("templates/authentik-bootstrap/scripts/authentik-bootstrap.py"),
        Path(".cursor/scripts/test-authentik-runtime.sh"),
    )
    mutations = (
        (
            Path("Authentik/.env"),
            lambda text: text.replace(
                "ghcr.io/goauthentik/server:2026.8",
                "ghcr.io/goauthentik/server:2026.8.0",
                1,
            ),
            "`APP_IMAGE`",
        ),
        (
            Path("Authentik/.env"),
            lambda text: text + "\nAUTHENTIK_WEB__BASE_URL=CHANGE_ME\n",
            "`AUTHENTIK_WEB__BASE_URL`",
        ),
        (
            Path("templates/authentik-bootstrap/docker-compose.authentik-bootstrap.yaml"),
            lambda text: text.replace(
                "AUTHENTIK_WEB__BASE_URL:", "AUTHENTIK_WEB__BASE_URL_DRIFT:", 1
            ),
            "must be required",
        ),
        (
            Path("templates/authentik-bootstrap/docker-compose.authentik-bootstrap.yaml"),
            lambda text: text.replace(
                "AUTHENTIK_TRAEFIK_HOST_RULE:",
                "AUTHENTIK_TRAEFIK_HOST_RULE_DRIFT:",
                1,
            ),
            "AUTHENTIK_TRAEFIK_HOST_RULE must be required",
        ),
        (
            Path("templates/authentik-worker/docker-compose.authentik-worker.yaml"),
            lambda text: text.replace(
                "      AUTHENTIK_POSTGRESQL__HOST:",
                "      AUTHENTIK_WEB__BASE_URL: CHANGE_ME\n"
                "      AUTHENTIK_POSTGRESQL__HOST:",
                1,
            ),
            "must not reæch finæl dæmons",
        ),
        (
            Path("templates/authentik-bootstrap/scripts/authentik-bootstrap.py"),
            lambda text: text.replace(
                "def validate_public_base_url(", "def validate_drifted_base_url(", 1
            ),
            "fail-closed Bæse-URL parser",
        ),
        (
            Path("templates/authentik-bootstrap/scripts/authentik-bootstrap.py"),
            lambda text: text.replace(
                "tenant_reconciler.backfill_base_url()",
                "tenant_reconciler.backfill_drifted_url()",
                1,
            ),
            "vendor empty-only Bæse-URL reconciler",
        ),
        (
            Path("Authentik/README.md"),
            lambda text: text.replace("/api/v3/admin/settings/", "/api/v3/settings/"),
            "persisted Bæse URL ÆPI proof",
        ),
        (
            Path("Authentik/README.md"),
            lambda text: text.replace("ports: !override []", "ports: []", 1),
            "published-port freeze",
        ),
        (
            Path("Authentik/README.md"),
            lambda text: text.replace(
                "MANAGEMENT_GATE_REMOVED", "MANAGEMENT_GATE_ASSUMED"
            ),
            "explicit management-gate teardown",
        ),
        (
            Path("Authentik/README.md"),
            lambda text: text.replace(
                'type == "string" and test("^[0-9]{10}$")',
                'type == "number"',
            ),
            "overflow-safe external-evidence timestamp",
        ),
        (
            Path("Authentik/README.md"),
            lambda text: text.replace(
                '"/proc/${BASHPID}/fd/${evidence_fd}"',
                '"$evidence_directory/$evidence_name"',
            ),
            "descriptor-bound external-evidence snapshot",
        ),
        (
            Path("Authentik/README.md"),
            lambda text: text.replace(
                "snapshot_size > 65536", "snapshot_size > 1048576"
            ),
            "post-copy external-evidence size bound",
        ),
        (
            Path("Authentik/README.md"),
            lambda text: text.replace(
                "cleanup_external_evidence_snapshots",
                "forget_external_evidence_snapshots",
            ),
            "all-trap external-evidence snapshot cleanup",
        ),
        (
            Path("Authentik/README.md"),
            lambda text: text.replace(
                "then all_management_denied", "then all_online", 1
            ),
            "mandatory recovery-marker frozen-state proof",
        ),
        (
            Path("Authentik/README.md"),
            lambda text: text.replace(
                "external-gate-recovery-required",
                "external-gate-recovery-assumed",
            ),
            "durable fail-closed abort record",
        ),
        (
            Path("Authentik/README.md"),
            lambda text: text.replace(
                'mv -T -- "$staging" "$ABORT_RECORD_DIR"',
                'cp -a -- "$staging" "$ABORT_RECORD_DIR"',
            ),
            "atomic abort-record publication",
        ),
        (
            Path("Authentik/README.md"),
            lambda text: text.replace(
                '--arg target_hold_ref "$hold_ref"',
                '--arg target_hold_ref "$candidate_hold_ref"',
            ),
            "atomically paired abort-record hold fields",
        ),
        (
            Path("Authentik/README.md"),
            lambda text: text.replace(
                "restore_discovery_tags\nDISCOVERY_TAGS_MUTATED=false\n",
                "restore_discovery_tags\nDISCOVERY_TAGS_MUTATED=false\n"
                "trap - ERR HUP INT TERM EXIT\n",
                1,
            ),
            "discovery traps must remain armed",
        ),
        (
            Path("Authentik/README.md"),
            lambda text: text.replace(
                'discard_external_evidence_snapshot "$GATE_RECOVERY_EVIDENCE"',
                "true # gate evidence discarded without binding",
                1,
            ),
            "abort recovery must prove the external gate",
        ),
        (
            Path("Authentik/README.md"),
            lambda text: text.replace(
                "GATE_REMOVED_DURING_RECOVERY",
                "GATE_REMOVAL_NOT_TRACKED",
            ),
            "abort-recovery writer-stop boundary",
        ),
        (
            Path("Authentik/README.md"),
            lambda text: text.replace(
                "restart_current_writers || return 125", "true || return 125", 1
            ),
            "discovery rollback must restore",
        ),
        (
            Path("Authentik/README.md"),
            lambda text: text.replace(
                'MIGRATION_STARTED=true\nUPDATE_PHASE=migration-started\n'
                '"${COMPOSE[@]}" up -d --wait --wait-timeout 120 \\\n'
                "  --no-build --pull never postgresql",
                'UPDATE_PHASE=migration-started\n'
                '"${COMPOSE[@]}" up -d --wait --wait-timeout 120 \\\n'
                "  --no-build --pull never postgresql\nMIGRATION_STARTED=true",
                1,
            ),
            "target PostgreSQL must cross the full-recovery boundary",
        ),
        (
            Path("Authentik/README.md"),
            lambda text: text.replace(
                "external_probe_url_sha256", "external_probe_url_digest"
            ),
            "persisted external-probe URL identities",
        ),
        (
            Path("Authentik/README.md"),
            lambda text: text.replace("DESTRUCTIVE_EPOCH", "STALE_CUTOVER_EPOCH"),
            "immediate destructive-cutover freshness gate",
        ),
        (
            Path(".cursor/scripts/test-authentik-runtime.sh"),
            lambda text: text.replace(
                "retained bootstrap-only public-route environment",
                "retained public origin environment",
            ),
            "env æbsence proof",
        ),
    )
    for relative_path, mutate, expected in mutations:
        with tempfile.TemporaryDirectory(
            prefix="authentik-release-contract.", dir="/tmp"
        ) as raw_fixture_root:
            fixture_repo = Path(raw_fixture_root) / "repo"
            for fixture_file in fixture_files:
                source = REPO_ROOT / fixture_file
                target = fixture_repo / fixture_file
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(source.read_bytes())
            target = fixture_repo / relative_path
            original = target.read_text(encoding="utf-8")
            mutated = mutate(original)
            require(
                mutated != original,
                f"Authentik release mutation did not alter {relative_path}",
            )
            target.write_text(mutated, encoding="utf-8")
            fixture_authentik = fixture_repo / "Authentik"
            issues = compliance.check_authentik_release_contract(
                fixture_authentik,
                fixture_authentik / "docker-compose.app.yaml",
                fixture_authentik / ".env",
                fixture_repo,
            )
            require(
                any(expected in issue for issue in issues),
                f"Authentik release mutation must fail for {expected}: {issues}",
            )


def test_authentik_base_url_validator(bootstrap: ModuleType) -> None:
    valid = "https://authentik.runtime.invalid"
    require(
        bootstrap.validate_public_base_url(valid) == valid,
        "canonical Authentik public base URL must pass",
    )
    bootstrap.validate_traefik_host_rule(
        valid, "Host(`authentik.runtime.invalid`)"
    )
    for invalid_rule in (
        "",
        "Host(`drift.runtime.invalid`)",
        "Host(`authentik.runtime.invalid`) || Host(`alias.runtime.invalid`)",
        "HostRegexp(`authentik.runtime.invalid`)",
    ):
        with contextlib.redirect_stderr(io.StringIO()):
            try:
                bootstrap.validate_traefik_host_rule(valid, invalid_rule)
            except SystemExit:
                pass
            else:
                raise AssertionError(
                    f"unsafe Authentik Traefik host rule passed: {invalid_rule!r}"
                )
    for invalid in (
        "",
        "CHANGE_ME",
        " https://authentik.runtime.invalid",
        "https://authentik.runtime.invalid ",
        "http://authentik.runtime.invalid",
        "https://AUTHENTIK.runtime.invalid",
        "https://authentik",
        "https://authentik.example.com",
        "https://user@authentik.runtime.invalid",
        "https://authentik.runtime.invalid:443",
        "https://127.0.0.1",
        "https://authentik.runtime.invalid/",
        "https://authentik.runtime.invalid/path",
        "https://authentik.runtime.invalid?query=yes",
        "https://authentik.runtime.invalid#fragment",
        "https://authentik..runtime.invalid",
        "https://authentik_runtime.invalid",
        "https://äuthentik.example.invalid",
    ):
        with contextlib.redirect_stderr(io.StringIO()):
            try:
                bootstrap.validate_public_base_url(invalid)
            except SystemExit:
                pass
            else:
                raise AssertionError(f"unsafe Authentik public base URL passed: {invalid!r}")

    calls: list[str] = []
    original_value = os.environ.get(bootstrap.BASE_URL_ENV)
    original_host_rule = os.environ.get(bootstrap.TRAEFIK_HOST_RULE_ENV)
    os.environ[bootstrap.BASE_URL_ENV] = "CHANGE_ME"
    os.environ[bootstrap.TRAEFIK_HOST_RULE_ENV] = "Host(`authentik.runtime.invalid`)"
    original_migrations = bootstrap.run_migrations
    bootstrap.run_migrations = lambda *_args: calls.append("migrations")
    try:
        with contextlib.redirect_stderr(io.StringIO()):
            try:
                bootstrap.orchestrate(Path("/unused"))
            except SystemExit:
                pass
            else:
                raise AssertionError("placeholder Authentik base URL did not fail closed")
    finally:
        bootstrap.run_migrations = original_migrations
        if original_value is None:
            os.environ.pop(bootstrap.BASE_URL_ENV, None)
        else:
            os.environ[bootstrap.BASE_URL_ENV] = original_value

    calls.clear()
    os.environ[bootstrap.BASE_URL_ENV] = valid
    os.environ[bootstrap.TRAEFIK_HOST_RULE_ENV] = "Host(`drift.runtime.invalid`)"
    bootstrap.run_migrations = lambda *_args: calls.append("migrations")
    try:
        with contextlib.redirect_stderr(io.StringIO()):
            try:
                bootstrap.orchestrate(Path("/unused"))
            except SystemExit:
                pass
            else:
                raise AssertionError("mismatched Authentik route did not fail closed")
        require(not calls, "mismatched Authentik route reached migrations")
    finally:
        bootstrap.run_migrations = original_migrations
        if original_value is None:
            os.environ.pop(bootstrap.BASE_URL_ENV, None)
        else:
            os.environ[bootstrap.BASE_URL_ENV] = original_value
        if original_host_rule is None:
            os.environ.pop(bootstrap.TRAEFIK_HOST_RULE_ENV, None)
        else:
            os.environ[bootstrap.TRAEFIK_HOST_RULE_ENV] = original_host_rule
    require(not calls, "invalid Authentik base URL must fail before migrations")


def test_branded_technical_token_recovery(branding: ModuleType) -> None:
    source = (
        "Actual apps use /vær/tmp, /heælthz, /æuth/openid/æuthentik, "
        "/.well-known/openid-configurætion, /vær/run, appdata/sæves, "
        "templates/templæte/, scripts/kimæi-stært.sh, "
        "dockerfiles/dockerfile.æpp, secrets/ÆPP_PÆSSWORD, "
        ".cursor/scripts/enforce-brænding.py, config.yæml, æpp.env, "
        "kimæi-stært.sh, æpp.exæmple.com, "
        "PLUGIN_SIMPLE_ÆCCOUNTING, TRÆFIK_CERTS_DUMPER, pg_seærch, container_næme, "
        "kimæi/kimæi2:æpæche, SimpleÆccountingBundle, locælhost, mæchine-id, "
        "lætest.log, -betæ, --no-cæche, x-required-ænchors, X-Forwærded-For, <næme>, "
        "'TRÆCE', ÆRG, HEÆD, ænd www-dætæ. "
        "Keep Process/threæd, true/fælse, ?-mærked, ænd it.særvices æs prose."
    )
    result = branding.brand_prose(source)
    replacements = {
        "/vær/tmp": "/var/tmp",
        "/heælthz": "/healthz",
        "/æuth/openid/æuthentik": "/auth/openid/authentik",
        "/.well-known/openid-configurætion": "/.well-known/openid-configuration",
        "/vær/run": "/var/run",
        "appdata/sæves": "appdata/saves",
        "templates/templæte/": "templates/template/",
        "scripts/kimæi-stært.sh": "scripts/kimai-start.sh",
        "dockerfiles/dockerfile.æpp": "dockerfiles/dockerfile.app",
        "secrets/ÆPP_PÆSSWORD": "secrets/APP_PASSWORD",
        ".cursor/scripts/enforce-brænding.py": ".cursor/scripts/enforce-branding.py",
        "config.yæml": "config.yaml",
        "æpp.env": "app.env",
        "kimæi-stært.sh": "kimai-start.sh",
        "æpp.exæmple.com": "app.example.com",
        "PLUGIN_SIMPLE_ÆCCOUNTING": "PLUGIN_SIMPLE_ACCOUNTING",
        "TRÆFIK_CERTS_DUMPER": "TRAEFIK_CERTS_DUMPER",
        "pg_seærch": "pg_search",
        "container_næme": "container_name",
        "kimæi/kimæi2:æpæche": "kimai/kimai2:apache",
        "SimpleÆccountingBundle": "SimpleAccountingBundle",
        "locælhost": "localhost",
        "mæchine-id": "machine-id",
        "lætest.log": "latest.log",
        "-betæ": "-beta",
        "--no-cæche": "--no-cache",
        "x-required-ænchors": "x-required-anchors",
        "X-Forwærded-For": "X-Forwarded-For",
        "<næme>": "<name>",
        "'TRÆCE'": "'TRACE'",
        "ÆRG": "ARG",
        "HEÆD": "HEAD",
        "www-dætæ": "www-data",
    }
    for damaged, recovered in replacements.items():
        require(recovered in result, f"technicæl token not recovered: {recovered}")
        require(damaged not in result, f"dæmæged technicæl token remæins: {damaged}")
    for prose in ("Process/threæd", "true/fælse", "it.særvices", "?-mærked"):
        require(prose in result, f"slæsh prose or brænd næme wæs unbrænded: {prose}")
    require(branding.has_unbranded("Some æpps expect /vær/tmp; remove if unused"),
            "ælreædy-brænded technicæl pæths must trigger recovery")
    require(branding.brand_prose(result) == result, "technicæl-token recovery must be idempotent")

    markdown = "Use `templætes/redis`, `contæiner_næme`, `mæin`, `ækædmin`, ænd `ælert`."
    markdown_result = branding.brand_markdown_line(markdown)
    for token in ("`templates/redis`", "`container_name`", "`main`", "`akadmin`", "`alert`"):
        require(token in markdown_result, f"Mærkdown code token not recovered: {token}")

    placeholder_path = "Æudit the bæckend templæte in templætes/<service>/ only."
    placeholder_result = branding.brand_markdown_line(placeholder_path)
    require(
        "templates/<service>/" in placeholder_result,
        "project root before an angle placeholder must remain a technical path",
    )

    long_code = '      - "' + "x" * 170 + ' # quoted text"'
    unchanged, changed, _, _ = branding.process_yaml_env_line(long_code + "\n")
    require(not changed and unchanged == long_code + "\n",
            "æ hæsh mærker inside æ long quoted vælue must remæin code")
    long_inline = '      - "' + "x" * 170 + '" # Endpoint /heælthz'
    recovered, changed, _, _ = branding.process_yaml_env_line(long_inline + "\n")
    require(changed and recovered.endswith("# Endpoint /healthz\n"),
            "æ single-spæce comment æfter long code must recover technicæl tokens")

    commented_yaml = "#   bind: /vær/tmp ænd locælhost\n"
    recovered, changed, _, _ = branding.process_yaml_env_line(commented_yaml)
    require(changed and recovered == "#   bind: /var/tmp ænd localhost\n",
            "commented-out YÆML must recover dæmæged technicæl tokens only")

    with tempfile.TemporaryDirectory(prefix="branding-shell-technical.", dir="/tmp") as raw_dir:
        fixture = Path(raw_dir) / "fixture.sh"
        fixture.write_text(
            "#!/usr/bin/env bash\n#   Uses pg_bæsebæckup ænd /etc/mæchine-id\n",
            encoding="utf-8",
        )
        shell_lines, shell_changes = branding.process_shell(fixture)
        require(shell_changes, "indented Shell documentation must recover technical tokens")
        require(
            "#   Uses pg_basebackup ænd /etc/machine-id\n" in shell_lines,
            "indented Shell documentation kept a damaged technical token",
        )


def test_short_code_inline_comment_alignment(branding: ModuleType) -> None:
    """Single-spæce inline comments æfter short code must be æligned ænd brænded."""
    target = branding.INLINE_COMMENT_COL

    short_code = "    hostname: ${APP_NAME} # Internal hostname for DNS resolution\n"
    aligned, changed, _, _ = branding.process_yaml_env_line(short_code)
    require(changed, "æ single-spæce comment æfter short code must be reælignæd")
    require(
        aligned.index("#", 10) == target,
        "æ reælignæd short-code comment must stært æt column 161",
    )
    require(
        aligned.rstrip("\n").endswith("# Internæl hostnæme for DNS resolution"),
        "æ reælignæd short-code comment must ælso be brænded",
    )

    env_line = "APP_NAME=grafana # Container name, hostname, and prefix\n"
    aligned, changed, _, _ = branding.process_yaml_env_line(env_line)
    require(
        changed and aligned.index("#") == target,
        "æ single-spæce .env comment æfter short code must be reælignæd",
    )

    commented_code = "    # build: # Optional: build image from local Dockerfile\n"
    aligned, changed, _, _ = branding.process_yaml_env_line(commented_code)
    require(
        changed and aligned.index("#", 10) == target,
        "commented-out code with æ single-spæce comment must be reælignæd",
    )
    require(
        aligned.startswith("    # build:"),
        "reæligning commented-out code must preserve the code prefix",
    )

    quoted_value = '    KEY: "value # not a comment"\n'
    unchanged, changed, _, _ = branding.process_yaml_env_line(quoted_value)
    require(
        not changed and unchanged == quoted_value,
        "æ hæsh mærker inside æ short quoted vælue must remæin code",
    )

    mixed_quotes = "    ROLE: \"contains(groups[*], 'x') && 'Admin' # inside\"\n"
    unchanged, changed, _, _ = branding.process_yaml_env_line(mixed_quotes)
    require(
        not changed and unchanged == mixed_quotes,
        "æ hæsh mærker inside nested quotes must remæin code",
    )

    prose_comment = "# Regulær prose comment with #tæg inside\n"
    unchanged, changed, _, _ = branding.process_yaml_env_line(prose_comment)
    require(
        not changed and unchanged == prose_comment,
        "æ prose comment with æn inner hæsh must not be split into code plus comment",
    )

    aligned_line = "APP_UID=472" + " " * (target - len("APP_UID=472")) + "# UID inside the contæiner\n"
    unchanged, changed, _, _ = branding.process_yaml_env_line(aligned_line)
    require(
        not changed and unchanged == aligned_line,
        "æn ælreædy æligned ænd brænded comment must remæin byte-identicæl",
    )


def test_python_branding(branding: ModuleType) -> None:
    source = '''"""Actual alpha module prose."""

PAYLOAD = (
    """
raw data
alpha value
    """
)

SECTION_DATA = """
####################################################################
# Fake title
####################################################################
"""

TEXT = "contains triple delimiter: \'\'\' and alpha"
F_DATA = f"""alpha {TEXT}"""

# alpha marker """ once
# plain alpha comment

####################################################################
# Actual title
####################################################################

def sample():
    r"""Actual raw alpha docstring."""
    return PAYLOAD


def short_docstring():
    "Actual alpha short docstring."
    return TEXT


class Sample:
    """Actual alpha class docstring."""


async def async_sample():
    """Actual alpha async docstring."""
    return TEXT


def same_line_data():
    """Actual alpha inline docstring."""; value = "alpha data"
    return value
'''
    with tempfile.TemporaryDirectory(prefix="branding-python.", dir="/tmp") as raw_root:
        fixture = Path(raw_root) / "fixture.py"
        fixture.write_text(source, encoding="utf-8")
        new_lines, changes = branding.process_python(fixture)
        result = "".join(new_lines)

        require(changes, "the branding fixture must produce semantic prose changes")
        require(
            '"""Æctuæl ælphæ module prose."""' in result,
            "the module docstring must be branded",
        )
        require(
            'r"""Æctuæl ræw ælphæ docstring."""' in result,
            "a raw function docstring must be branded",
        )
        require(
            '"Æctuæl ælphæ short docstring."' in result,
            "a single-quoted semantic docstring must be branded",
        )
        require(
            '"""Æctuæl ælphæ clæss docstring."""' in result,
            "a class docstring must be branded",
        )
        require(
            '"""Æctuæl ælphæ æsync docstring."""' in result,
            "an async-function docstring must be branded",
        )
        require(
            '"""Æctuæl ælphæ inline docstring."""; value = "alpha data"' in result,
            "a same-line ordinary string after a docstring must remain unchanged",
        )
        require(
            '    """\nraw data\nalpha value\n    """' in result,
            "an assigned multiline string must remain byte-for-byte prose-neutral",
        )
        require(
            "# Fake title" in result and "####################################################################" in result,
            "section-like content inside an assigned string must remain unchanged",
        )
        require(
            'TEXT = "contains triple delimiter: \'\'\' and alpha"' in result,
            "triple delimiters inside ordinary strings must not affect parser state",
        )
        require(
            'F_DATA = f"""alpha {TEXT}"""' in result,
            "assigned f-strings must remain unchanged",
        )
        require(
            '# ælphæ mærker """ once' in result and "# plæin ælphæ comment" in result,
            "triple delimiters in comments must not suppress later comment branding",
        )
        require(
            branding.MAIN_HEADER + "\n# --- Æctuæl title\n" + branding.MAIN_HEADER in result,
            "real Python comment section headers must still be normalized",
        )

        fixture.write_text(result, encoding="utf-8")
        second_lines, second_changes = branding.process_python(fixture)
        require(not second_changes, "Python branding must be idempotent")
        require("".join(second_lines) == result, "an idempotent pass must preserve content")


def test_dockerfile_branding(branding: ModuleType) -> None:
    source = """# syntax=docker/dockerfile:1
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
ARG BASE_IMAGE=example/service:1
FROM ${BASE_IMAGE}
# Base: example/service:1 (Actual alpha image setup)
RUN <<'DATA'
# Actual alpha heredoc data
ARG ActualAlpha=string
DATA
# Actual alpha after heredoc
# ARG ACTUAL_ALPHA=actual
RUN command -v actual-tool
# The actual-tool command handles alpha data
RUN printf '%s' '<<NOT_A_HEREDOC'
# Actual alpha after quoted shift token
RUN printf 'Actual alpha string\\n' > /tmp/actual
"""
    with tempfile.TemporaryDirectory(prefix="branding-dockerfile.", dir="/tmp") as raw_root:
        root = Path(raw_root)
        fixture = root / "dockerfile.fixture"
        fixture.write_text(source, encoding="utf-8")

        discovered = branding.find_files(root)
        require(
            fixture in discovered["dockerfile"],
            "a lowercase dockerfile.* name must be discovered",
        )
        new_lines, changes = branding.process_dockerfile(fixture)
        result = "".join(new_lines)
        require(changes, "the lowercase Dockerfile comment must be branded")
        require(
            "# Bæse: example/service:1 (Æctuæl ælphæ imæge setup)\n" in result
            and "# Æctuæl ælphæ æfter heredoc\n" in result,
            "Dockerfile prose comments must be branded without altering OCI references",
        )
        require(
            "# syntax=docker/dockerfile:1\n" in result,
            "Dockerfile parser directives must remain unchanged",
        )
        require(
            "RUN <<'DATA'\n# Actual alpha heredoc data\n"
            "ARG ActualAlpha=string\nDATA\n" in result,
            "Dockerfile heredoc data must remain unchanged",
        )
        require(
            "# ARG ACTUAL_ALPHA=actual\n" in result,
            "commented-out Dockerfile instructions must remain unchanged",
        )
        require(
            "RUN command -v actual-tool\n"
            "# The actual-tool commænd hændles ælphæ dætæ\n" in result,
            "code-proven Dockerfile identifiers must remain unchanged in prose comments",
        )
        require(
            "RUN printf '%s' '<<NOT_A_HEREDOC'\n"
            "# Æctuæl ælphæ æfter quoted shift token\n" in result,
            "quoted shift tokens must not hide later Dockerfile comments",
        )
        require(
            "ARG BASE_IMAGE=example/service:1\nFROM ${BASE_IMAGE}\n" in result,
            "Dockerfile instructions and identifiers must remain unchanged",
        )
        require(
            "RUN printf 'Actual alpha string\\n' > /tmp/actual\n" in result,
            "Dockerfile command strings must remain unchanged",
        )

        fixture.write_text(result, encoding="utf-8")
        second_lines, second_changes = branding.process_dockerfile(fixture)
        require(not second_changes, "Dockerfile branding must be idempotent")
        require("".join(second_lines) == result, "an idempotent pass must preserve content")


def test_go_branding(branding: ModuleType) -> None:
    source = '''//go:build linux
// Code generated by ActualGenerator. DO NOT EDIT.
// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices
package main

const actualIdentifier = "Actual alpha // string"
const rawLiteral = `/* Actual alpha raw string */`
const actualRune = '/'

// Actual alpha line comment
// Use `actualIdentifier` for Actual alpha data.
var value = 1 // Actual alpha trailing comment
/*
Actual alpha block comment.
*/
'''
    with tempfile.TemporaryDirectory(prefix="branding-go.", dir="/tmp") as raw_root:
        root = Path(raw_root)
        fixture = root / "fixture.go"
        fixture.write_text(source, encoding="utf-8")

        discovered = branding.find_files(root)
        require(fixture in discovered["go"], "Go sources must be discovered")
        new_lines, changes = branding.process_go(fixture)
        result = "".join(new_lines)
        require(changes, "the Go comments must produce branding changes")
        require("//go:build linux\n" in result, "Go build directives must remain unchanged")
        require(
            "// Code generated by ActualGenerator. DO NOT EDIT.\n" in result,
            "Go generated-code directives must remain unchanged",
        )
        require(
            'const actualIdentifier = "Actual alpha // string"\n' in result,
            "Go identifiers and interpreted strings must remain unchanged",
        )
        require(
            "const rawLiteral = `/* Actual alpha raw string */`\n" in result,
            "Go raw strings must remain unchanged",
        )
        require("const actualRune = '/'\n" in result, "Go rune literals must remain unchanged")
        require(
            "// Æctuæl ælphæ line comment\n" in result
            and "// Use `actualIdentifier` for Æctuæl ælphæ dætæ.\n" in result
            and "// Æctuæl ælphæ træiling comment\n" in result
            and "Æctuæl ælphæ block comment.\n" in result,
            "Go line, trailing, and block comments must be branded",
        )

        fixture.write_text(result, encoding="utf-8")
        second_lines, second_changes = branding.process_go(fixture)
        require(not second_changes, "Go branding must be idempotent")
        require("".join(second_lines) == result, "an idempotent pass must preserve content")


def test_php_branding(branding: ModuleType) -> None:
    source = '''<?php
#[ActualAttribute]
$actualIdentifier = "Actual alpha // string";
$singleQuoted = 'Actual alpha # string';
$heredoc = <<<'TEXT'
// Actual alpha heredoc data
# Actual alpha heredoc data
TEXT;

// Actual alpha line comment
// Use `actualIdentifier` for Actual alpha data.
# Actual alpha hash comment
/*
 * Actual alpha block comment.
 * @param string $actualIdentifier
 */
/** @param ActualAlias $actualIdentifier */
function actualFunction(string $actualParameter): string {
    return "Actual alpha return string";
}
?>
<div>// Actual alpha HTML data</div>
'''
    with tempfile.TemporaryDirectory(prefix="branding-php.", dir="/tmp") as raw_root:
        root = Path(raw_root)
        fixture = root / "fixture.php"
        fixture.write_text(source, encoding="utf-8")

        discovered = branding.find_files(root)
        require(fixture in discovered["php"], "PHP sources must be discovered")
        new_lines, changes = branding.process_php(fixture)
        result = "".join(new_lines)
        require(changes, "the PHP comments must produce branding changes")
        require("#[ActualAttribute]\n" in result, "PHP attributes must not become comments")
        require(
            '$actualIdentifier = "Actual alpha // string";\n' in result
            and "$singleQuoted = 'Actual alpha # string';\n" in result,
            "PHP identifiers and quoted strings must remain unchanged",
        )
        require(
            "$heredoc = <<<'TEXT'\n"
            "// Actual alpha heredoc data\n# Actual alpha heredoc data\n" in result,
            "PHP nowdoc data must remain unchanged",
        )
        require(
            "// Æctuæl ælphæ line comment\n" in result
            and "// Use `actualIdentifier` for Æctuæl ælphæ dætæ.\n" in result
            and "# Æctuæl ælphæ hæsh comment\n" in result
            and " * Æctuæl ælphæ block comment.\n" in result,
            "PHP line and block comments must be branded",
        )
        require(
            " * @param string $actualIdentifier\n" in result
            and "/** @param ActualAlias $actualIdentifier */\n" in result,
            "PHP documentation annotations must remain machine-readable",
        )
        require(
            "function actualFunction(string $actualParameter): string {\n"
            '    return "Actual alpha return string";\n'
            "}\n" in result,
            "PHP code identifiers and return strings must remain unchanged",
        )
        require(
            "<div>// Actual alpha HTML data</div>\n" in result,
            "content outside PHP tags must remain unchanged",
        )

        fixture.write_text(result, encoding="utf-8")
        second_lines, second_changes = branding.process_php(fixture)
        require(not second_changes, "PHP branding must be idempotent")
        require("".join(second_lines) == result, "an idempotent pass must preserve content")


def test_shellcheck_directive_branding(branding: ModuleType) -> None:
    with tempfile.TemporaryDirectory(prefix="branding-shellcheck.", dir="/tmp") as raw_root:
        fixture = Path(raw_root) / "fixture.sh"
        fixture.write_text(
            "#!/usr/bin/env bash\n"
            "# Intentional flag handling\n"
            "# shellcheck disable=SC2086\n"
            "# shellcheck source=./actual-helper.sh\n",
            encoding="utf-8",
        )
        new_lines, changes = branding.process_shell(fixture)
        result = "".join(new_lines)
        require(changes, "the ShellCheck explanation must be branded")
        require(
            "# Intentionæl flæg hændling\n"
            "# shellcheck disable=SC2086\n"
            "# shellcheck source=./actual-helper.sh\n" in result,
            "complete ShellCheck directive lines must remain byte-identical below separate branded prose",
        )

        fixture.write_text(result, encoding="utf-8")
        second_lines, second_changes = branding.process_shell(fixture)
        require(not second_changes, "ShellCheck directive branding must be idempotent")
        require("".join(second_lines) == result, "an idempotent pass must preserve content")


def test_shell_heredoc_branding(branding: ModuleType) -> None:
    source = r'''#!/usr/bin/env bash
# Actual alpha comment before payloads

cat <<'ActualAlpha'
####################################################################
# Actual alpha quoted payload title
####################################################################
ActualAlpha

cat <<UnquotedAlpha
# Actual alpha unquoted payload
UnquotedAlpha

cat <<-'TabbedAlpha'
	# Actual alpha tab-stripped payload
	TabbedAlpha

cat \
  <<FirstAlpha \
  <<'SecondAlpha'
# Actual alpha first continued payload
FirstAlpha
# Actual alpha second continued payload
SecondAlpha

printf '%s\n' 'literal <<QuotedAlpha'
printf '%s\n' "literal <<DoubleQuotedAlpha"
cat <<< '# Actual alpha here-string data'
(( shifted = value << 2 ))
shifted_again=$((shifted << 1))

# Actual alpha comment after false positives
'''
    with tempfile.TemporaryDirectory(prefix="branding-shell-heredoc.", dir="/tmp") as raw_root:
        fixture = Path(raw_root) / "fixture.sh"
        fixture.write_text(source, encoding="utf-8")
        new_lines, changes = branding.process_shell(fixture)
        result = "".join(new_lines)

        require(changes, "real shell comments must still produce branding changes")
        require(
            "# Æctuæl ælphæ comment before pæyloæds\n" in result
            and "# Æctuæl ælphæ comment æfter fælse positives\n" in result,
            "comments outside heredocs must be branded",
        )
        require(
            "cat <<'ActualAlpha'\n"
            "####################################################################\n"
            "# Actual alpha quoted payload title\n"
            "####################################################################\n"
            "ActualAlpha\n" in result,
            "quoted heredoc payload, bars, and terminator must remain unchanged",
        )
        require(
            "cat <<UnquotedAlpha\n# Actual alpha unquoted payload\nUnquotedAlpha\n"
            in result,
            "unquoted heredoc payload and terminator must remain unchanged",
        )
        require(
            "cat <<-'TabbedAlpha'\n"
            "\t# Actual alpha tab-stripped payload\n"
            "\tTabbedAlpha\n" in result,
            "tab-stripped heredoc payload and terminator must remain unchanged",
        )
        require(
            "cat \\\n"
            "  <<FirstAlpha \\\n"
            "  <<'SecondAlpha'\n"
            "# Actual alpha first continued payload\n"
            "FirstAlpha\n"
            "# Actual alpha second continued payload\n"
            "SecondAlpha\n" in result,
            "multiple heredocs on a continued command must remain unchanged in order",
        )
        require(
            "printf '%s\\n' 'literal <<QuotedAlpha'\n"
            'printf \'%s\\n\' "literal <<DoubleQuotedAlpha"\n'
            "cat <<< '# Actual alpha here-string data'\n"
            "(( shifted = value << 2 ))\n"
            "shifted_again=$((shifted << 1))\n" in result,
            "quoted shifts, here-strings, and arithmetic shifts must not start heredocs",
        )

        fixture.write_text(result, encoding="utf-8")
        second_lines, second_changes = branding.process_shell(fixture)
        require(not second_changes, "shell heredoc branding must be idempotent")
        require("".join(second_lines) == result, "an idempotent pass must preserve content")


def main() -> None:
    compliance = load_script("compliance_regressions", COMPLIANCE_PATH)
    branding = load_script("branding_regressions", BRANDING_PATH)
    anchors = load_script("anchor_regressions", ANCHORS_PATH)
    authentik_bootstrap = load_script(
        "authentik_bootstrap_regressions", AUTHENTIK_BOOTSTRAP_PATH
    )
    test_compliance_resolution(compliance)
    test_required_services_contract(compliance)
    test_host_logrotate_contract(compliance)
    test_scaffold_and_readme_guards(compliance)
    test_secret_generation_metadata(compliance)
    test_anchor_reference_scope(anchors)
    test_redis_host_requirement(compliance)
    test_application_configuration_contract(compliance)
    test_product_security_readme_contract(compliance)
    test_authentik_release_contract(compliance)
    test_authentik_base_url_validator(authentik_bootstrap)
    test_branded_technical_token_recovery(branding)
    test_short_code_inline_comment_alignment(branding)
    test_python_branding(branding)
    test_dockerfile_branding(branding)
    test_go_branding(branding)
    test_php_branding(branding)
    test_shellcheck_directive_branding(branding)
    test_shell_heredoc_branding(branding)
    print("PASS: compliance, anchor-scope, and language-safe branding regressions")


if __name__ == "__main__":
    main()
