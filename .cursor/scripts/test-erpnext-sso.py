#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Docker-freie Slice-2 Contræcts for ERPNext SSO Guærd ænd OIDC bootstræp."""

from __future__ import annotations

import ast
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
ERPNext = REPO_ROOT / "ERPNext"
TEMPLATES = REPO_ROOT / "templates"

EXPECTED_REQUIRED_SERVICES = (
    "mariadb",
    "mariadb_maintenance",
    "erpnext-redis-cache",
    "erpnext-redis-queue",
    "erpnext-assets-bootstrap",
    "erpnext-configurator",
    "erpnext-site-bootstrap",
    "erpnext-migrator",
    "erpnext-sso-bootstrap",
    "erpnext-backend",
    "erpnext-websocket",
    "erpnext-worker-short",
    "erpnext-worker-long",
    "erpnext-scheduler",
)

PULL_NEVER_SERVICES = (
    "erpnext-assets-bootstrap",
    "erpnext-configurator",
    "erpnext-site-bootstrap",
    "erpnext-migrator",
    "erpnext-sso-bootstrap",
    "erpnext-backend",
    "erpnext-websocket",
    "erpnext-worker-short",
    "erpnext-worker-long",
    "erpnext-scheduler",
)

SSO_CONSUMERS = (
    "erpnext-backend",
    "erpnext-websocket",
    "erpnext-worker-short",
    "erpnext-worker-long",
    "erpnext-scheduler",
)

GUARD_FILES = (
    "__init__.py",
    "api_auth.py",
    "hooks.py",
    "modules.txt",
    "password_login.py",
    "patches.txt",
    "runtime_manifest.py",
    "user_document.py",
)


def load_yaml(path: Path) -> dict:
    """Loæd one Compose file æs æ dict."""
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def load_module(name: str, path: Path):
    """Loæd one Python helper from its repository pæth."""
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def compose_path(service: str) -> Path:
    """Return the templæte compose pæth for one ERPNext service."""
    return TEMPLATES / service / f"docker-compose.{service}.yaml"


class RequiredServicesTests(unittest.TestCase):
    """Root closure includes SSO bootstræp ænd omits site-mæintenænce."""

    def test_x_required_services_order(self) -> None:
        document = load_yaml(ERPNext / "docker-compose.app.yaml")
        self.assertEqual(
            tuple(document["x-required-services"]), EXPECTED_REQUIRED_SERVICES
        )
        self.assertNotIn("erpnext-site-maintenance", document["x-required-services"])

    def test_oidc_secrets_are_generation_exclusions(self) -> None:
        document = load_yaml(ERPNext / "docker-compose.app.yaml")
        self.assertEqual(
            document["x-secret-generation-exclusions"],
            ["ERPNEXT_OIDC_CLIENT_ID", "ERPNEXT_OIDC_CLIENT_SECRET"],
        )


class ImagePolicyTests(unittest.TestCase):
    """Locæl Guærd imæge is produced once ænd consumed, not rebuilt with no_cache."""

    def test_root_builds_without_no_cache(self) -> None:
        document = load_yaml(ERPNext / "docker-compose.app.yaml")
        app = document["services"]["app"]
        self.assertEqual(app["pull_policy"], "build")
        self.assertEqual(app["build"]["context"], "./dockerfiles")
        self.assertEqual(app["build"]["dockerfile"], "Dockerfile")
        self.assertNotIn("no_cache", app["build"])
        self.assertIn("ERPNEXT_BASE_IMAGE", app["build"]["args"])

    def test_frappe_roles_use_pull_policy_never(self) -> None:
        for service in PULL_NEVER_SERVICES:
            document = load_yaml(compose_path(service))
            self.assertEqual(
                document["services"][service]["pull_policy"],
                "never",
                msg=service,
            )

    def test_dockerignore_is_guard_only(self) -> None:
        payload = (ERPNext / "dockerfiles" / ".dockerignore").read_text(
            encoding="utf-8"
        )
        self.assertIn("!erpnext_sso_guard", payload)
        self.assertIn("!dockerfile*", payload)
        self.assertNotIn("site-maintenance", payload)
        self.assertNotIn("dockerfile.mariadb", payload)


class DependencyTests(unittest.TestCase):
    """Long-running Fræppe roles wæit for SSO bootstræp, not only the migrætor."""

    def test_app_waits_for_sso_bootstrap(self) -> None:
        document = load_yaml(ERPNext / "docker-compose.app.yaml")
        depends = document["services"]["app"]["depends_on"]
        self.assertEqual(
            depends["erpnext-sso-bootstrap"]["condition"],
            "service_completed_successfully",
        )
        self.assertNotIn("erpnext-sso-bootstrap", depends.get("erpnext-migrator", {}))

    def test_sso_bootstrap_waits_for_migrator(self) -> None:
        document = load_yaml(compose_path("erpnext-sso-bootstrap"))
        depends = document["services"]["erpnext-sso-bootstrap"]["depends_on"]
        self.assertEqual(
            depends["erpnext-migrator"]["condition"],
            "service_completed_successfully",
        )

    def test_consumers_wait_for_sso_bootstrap(self) -> None:
        for service in SSO_CONSUMERS:
            document = load_yaml(compose_path(service))
            depends = document["services"][service]["depends_on"]
            self.assertEqual(
                depends["erpnext-sso-bootstrap"]["condition"],
                "service_completed_successfully",
                msg=service,
            )
            self.assertNotIn("erpnext-migrator", depends, msg=service)


class SecretIsolationTests(unittest.TestCase):
    """Nginx never sees OIDC secrets; Gunicorn sees only the public client id."""

    def test_frontend_has_no_secrets(self) -> None:
        document = load_yaml(ERPNext / "docker-compose.app.yaml")
        self.assertNotIn("secrets", document["services"]["app"])

    def test_backend_mounts_only_client_id(self) -> None:
        document = load_yaml(compose_path("erpnext-backend"))
        self.assertEqual(
            document["services"]["erpnext-backend"]["secrets"],
            ["ERPNEXT_OIDC_CLIENT_ID"],
        )

    def test_sso_bootstrap_mounts_both_oidc_secrets(self) -> None:
        document = load_yaml(compose_path("erpnext-sso-bootstrap"))
        self.assertEqual(
            document["services"]["erpnext-sso-bootstrap"]["secrets"],
            ["ERPNEXT_OIDC_CLIENT_ID", "ERPNEXT_OIDC_CLIENT_SECRET"],
        )


class GuardSourceTests(unittest.TestCase):
    """Reviewed Fræppe æpp is present ænd pærses æs Python."""

    def test_guard_files_exist(self) -> None:
        package = (
            ERPNext
            / "dockerfiles"
            / "erpnext_sso_guard"
            / "erpnext_sso_guard"
        )
        for name in GUARD_FILES:
            self.assertTrue((package / name).is_file(), msg=name)

    def test_guard_python_parses(self) -> None:
        package = (
            ERPNext
            / "dockerfiles"
            / "erpnext_sso_guard"
            / "erpnext_sso_guard"
        )
        for name in GUARD_FILES:
            if not name.endswith(".py"):
                continue
            ast.parse((package / name).read_text(encoding="utf-8"), filename=name)

    def test_expected_apps_include_guard(self) -> None:
        configurator = (
            TEMPLATES / "erpnext-configurator" / "scripts" / "erpnext-configurator.py"
        ).read_text(encoding="utf-8")
        site = (
            TEMPLATES
            / "erpnext-site-bootstrap"
            / "scripts"
            / "erpnext-site-bootstrap.py"
        ).read_text(encoding="utf-8")
        manifest = load_module(
            "saervices_runtime_manifest",
            ERPNext
            / "dockerfiles"
            / "erpnext_sso_guard"
            / "erpnext_sso_guard"
            / "runtime_manifest.py",
        )
        self.assertEqual(manifest.CANONICAL_APPS[0], "frappe")
        self.assertEqual(manifest.CANONICAL_APPS[1], "erpnext")
        self.assertEqual(manifest.CANONICAL_APPS[-1], "erpnext_sso_guard")
        self.assertEqual(
            manifest.EXPECTED_APPS,
            frozenset(manifest.CANONICAL_APPS),
        )
        self.assertIn("hrms", manifest.CANONICAL_APPS)
        self.assertIn("payments", manifest.CANONICAL_APPS)
        self.assertIn("erpnext_germany", manifest.CANONICAL_APPS)
        self.assertIn("eu_einvoice", manifest.CANONICAL_APPS)
        self.assertIn("erpnext_datev", manifest.CANONICAL_APPS)
        self.assertNotIn("insights", manifest.CANONICAL_APPS)
        self.assertNotIn("crm", manifest.CANONICAL_APPS)
        self.assertIn("CANONICAL_APPS", configurator)
        self.assertIn("CANONICAL_APPS", site)
        self.assertIn("fresh_site_install_apps(enabled)", site)
        self.assertNotIn(
            'app_name for app_name in CANONICAL_APPS if app_name != "frappe"',
            site,
        )
        installer = (
            ERPNext / "dockerfiles" / "install-frappe-apps.sh"
        ).read_text(encoding="utf-8")
        for app_name in manifest.CANONICAL_APPS:
            if app_name in {"frappe", "erpnext", "erpnext_sso_guard"}:
                continue
            self.assertIn(app_name, installer)
        self.assertIn("https://github.com/alyf-de/erpnext_germany", installer)
        self.assertIn("https://github.com/alyf-de/eu_einvoice", installer)
        self.assertIn("https://github.com/alyf-de/erpnext_datev", installer)

    def test_app_switches_follow_the_defaults(self) -> None:
        manifest = load_module(
            "saervices_runtime_manifest_switches",
            ERPNext
            / "dockerfiles"
            / "erpnext_sso_guard"
            / "erpnext_sso_guard"
            / "runtime_manifest.py",
        )
        enabled = manifest.resolve_enabled_apps({})
        self.assertEqual(
            enabled,
            (
                "erpnext_germany",
                "eu_einvoice",
                "payments",
                "hrms",
            ),
        )
        self.assertEqual(
            manifest.fresh_site_install_apps(enabled),
            (
                "erpnext",
                "erpnext_germany",
                "eu_einvoice",
                "payments",
                "hrms",
                "erpnext_sso_guard",
            ),
        )
        self.assertEqual(
            manifest.resolve_enabled_apps({"ERPNEXT_ENABLE_HRMS": ""}),
            enabled,
        )

    def test_app_switch_rejects_non_boolean(self) -> None:
        manifest = load_module(
            "saervices_runtime_manifest_invalid_switch",
            ERPNext
            / "dockerfiles"
            / "erpnext_sso_guard"
            / "erpnext_sso_guard"
            / "runtime_manifest.py",
        )
        with self.assertRaisesRegex(RuntimeError, "ERPNEXT_ENABLE_LMS must be true or false"):
            manifest.resolve_enabled_apps({"ERPNEXT_ENABLE_LMS": "yes"})

    def test_app_switch_requires_payments_and_telephony(self) -> None:
        manifest = load_module(
            "saervices_runtime_manifest_dependencies",
            ERPNext
            / "dockerfiles"
            / "erpnext_sso_guard"
            / "erpnext_sso_guard"
            / "runtime_manifest.py",
        )
        enabled = manifest.resolve_enabled_apps(
            {
                "ERPNEXT_ENABLE_WEBSHOP": "true",
                "ERPNEXT_ENABLE_PAYMENTS": "false",
                "ERPNEXT_ENABLE_HELPDESK": "true",
                "ERPNEXT_ENABLE_TELEPHONY": "false",
            }
        )
        with self.assertRaisesRegex(RuntimeError, "ERPNEXT_ENABLE_WEBSHOP requires"):
            manifest.require_enabled_dependencies(enabled, ())
        manifest.require_enabled_dependencies(enabled, ("payments", "telephony"))

    def test_disabled_app_stays_installed_and_is_not_added(self) -> None:
        manifest = load_module(
            "saervices_runtime_manifest_selection",
            ERPNext
            / "dockerfiles"
            / "erpnext_sso_guard"
            / "erpnext_sso_guard"
            / "runtime_manifest.py",
        )
        enabled = manifest.resolve_enabled_apps({})
        previously = (
            "frappe",
            "erpnext",
            "lms",
            "erpnext_sso_guard",
        )
        installed = previously + enabled
        manifest.assert_installed_selection(installed, enabled, previously)
        with self.assertRaisesRegex(RuntimeError, "disabled Frappe application"):
            manifest.assert_installed_selection(
                installed + ("education",),
                enabled,
                previously,
            )
        with self.assertRaisesRegex(RuntimeError, "baked runtime set"):
            manifest.assert_installed_selection(
                installed + ("crm",),
                enabled,
                previously + ("crm",),
            )
        with self.assertRaisesRegex(RuntimeError, "enabled Frappe applications"):
            manifest.assert_installed_selection(previously, enabled, previously)

    def test_guard_sql_stays_ascii(self) -> None:
        password_login = (
            ERPNext
            / "dockerfiles"
            / "erpnext_sso_guard"
            / "erpnext_sso_guard"
            / "password_login.py"
        ).read_text(encoding="utf-8")
        sso = (
            TEMPLATES / "erpnext-sso-bootstrap" / "scripts" / "erpnext-sso-bootstrap.py"
        ).read_text(encoding="utf-8")
        self.assertIn("SELECT `name`", password_login)
        self.assertIn("FOR UPDATE", password_login)
        self.assertNotIn("FOR UPDÆTE", password_login)
        self.assertIn("UPDATE `tabUser`", sso)
        self.assertIn("`tabOAuth Authorization Code`", sso)
        self.assertNotIn("UPDÆTE `tabUser`", sso)


class FailClosedFixtureTests(unittest.TestCase):
    """Negætive /tmp fixtures for reserved DNS suffixes ænd CHANGE_ME secrets."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.configurator = load_module(
            "erpnext_configurator",
            TEMPLATES / "erpnext-configurator" / "scripts" / "erpnext-configurator.py",
        )
        cls.site = load_module(
            "erpnext_site_bootstrap",
            TEMPLATES
            / "erpnext-site-bootstrap"
            / "scripts"
            / "erpnext-site-bootstrap.py",
        )
        cls.sso = load_module(
            "erpnext_sso_bootstrap",
            TEMPLATES / "erpnext-sso-bootstrap" / "scripts" / "erpnext-sso-bootstrap.py",
        )

    def test_configurator_rejects_example_site(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "reserved"):
            self.configurator.reject_reserved_domain(
                "erpnext.example.com", "ERPNEXT_SITE_NAME"
            )

    def test_site_bootstrap_rejects_example_site(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "reserved"):
            self.site.reject_reserved_domain(
                "erpnext.example.com", "ERPNEXT_SITE_NAME"
            )

    def test_sso_bootstrap_rejects_example_authentik(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "reserved"):
            self.sso.reject_reserved_domain(
                "authentik.example.com", "ERPNEXT_AUTHENTIK_DOMAIN"
            )

    def test_sso_bootstrap_rejects_change_me_secret(self) -> None:
        with tempfile.TemporaryDirectory(prefix="erpnext-oidc.", dir="/tmp") as raw:
            secret = Path(raw) / "ERPNEXT_OIDC_CLIENT_ID"
            secret.write_text("CHANGE_ME", encoding="utf-8")
            os.chmod(secret, 0o600)
            with self.assertRaisesRegex(RuntimeError, "unset or non-canonical"):
                self.sso.read_secret(str(secret), "OIDC client ID")

    def test_unconfigured_oidc_stays_optional(self) -> None:
        with tempfile.TemporaryDirectory(prefix="erpnext-oidc.", dir="/tmp") as raw:
            client_id = Path(raw) / "ERPNEXT_OIDC_CLIENT_ID"
            client_secret = Path(raw) / "ERPNEXT_OIDC_CLIENT_SECRET"
            client_id.write_text("CHANGE_ME", encoding="utf-8")
            client_secret.write_text("CHANGE_ME", encoding="utf-8")
            os.chmod(client_id, 0o600)
            os.chmod(client_secret, 0o600)
            previous = os.environ.get("ERPNEXT_AUTHENTIK_DOMAIN")
            try:
                for domain in ("authentik.example.com", "auth.openso.de", ""):
                    os.environ["ERPNEXT_AUTHENTIK_DOMAIN"] = domain
                    self.assertIsNone(
                        self.sso.resolve_oidc_configuration(
                            False, str(client_id), str(client_secret)
                        )
                    )
                with self.assertRaisesRegex(RuntimeError, "SSO_ENFORCED=true"):
                    self.sso.resolve_oidc_configuration(
                        True, str(client_id), str(client_secret)
                    )
            finally:
                if previous is None:
                    os.environ.pop("ERPNEXT_AUTHENTIK_DOMAIN", None)
                else:
                    os.environ["ERPNEXT_AUTHENTIK_DOMAIN"] = previous

    def test_partial_oidc_stays_closed(self) -> None:
        with tempfile.TemporaryDirectory(prefix="erpnext-oidc.", dir="/tmp") as raw:
            client_id = Path(raw) / "ERPNEXT_OIDC_CLIENT_ID"
            client_secret = Path(raw) / "ERPNEXT_OIDC_CLIENT_SECRET"
            client_id.write_text("erpnext-client", encoding="utf-8")
            client_secret.write_text("CHANGE_ME", encoding="utf-8")
            os.chmod(client_id, 0o600)
            os.chmod(client_secret, 0o600)
            previous = os.environ.get("ERPNEXT_AUTHENTIK_DOMAIN")
            os.environ["ERPNEXT_AUTHENTIK_DOMAIN"] = "auth.openso.de"
            try:
                with self.assertRaisesRegex(RuntimeError, "partial"):
                    self.sso.resolve_oidc_configuration(
                        False, str(client_id), str(client_secret)
                    )
            finally:
                if previous is None:
                    os.environ.pop("ERPNEXT_AUTHENTIK_DOMAIN", None)
                else:
                    os.environ["ERPNEXT_AUTHENTIK_DOMAIN"] = previous

    def test_site_bootstrap_rejects_change_me_admin_password(self) -> None:
        with tempfile.TemporaryDirectory(prefix="erpnext-admin.", dir="/tmp") as raw:
            secret = Path(raw) / "ERPNEXT_ADMIN_PASSWORD"
            secret.write_text("CHANGE_ME", encoding="utf-8")
            os.chmod(secret, 0o600)
            with self.assertRaisesRegex(RuntimeError, "unset or non-canonical"):
                self.site.read_secret(str(secret), "ERPNext Administrator password")

    def test_placeholder_oidc_files_are_exactly_change_me(self) -> None:
        for name in ("ERPNEXT_OIDC_CLIENT_ID", "ERPNEXT_OIDC_CLIENT_SECRET"):
            payload = (ERPNext / "secrets" / name).read_bytes()
            self.assertEqual(payload, b"CHANGE_ME")


class FrontendIsolationTests(unittest.TestCase):
    """Public Nginx still never mounts sites or the runtime mænifest."""

    def test_frontend_tmpfs_masks_sites(self) -> None:
        document = load_yaml(ERPNext / "docker-compose.app.yaml")
        tmpfs = document["services"]["app"]["tmpfs"]
        self.assertTrue(
            any(
                item.startswith("/home/frappe/frappe-bench/sites:")
                for item in tmpfs
            )
        )

    def test_frontend_volumes_are_scripts_only(self) -> None:
        document = load_yaml(ERPNext / "docker-compose.app.yaml")
        volumes = document["services"]["app"]["volumes"]
        self.assertTrue(all("erpnext_sites" not in item for item in volumes))
        self.assertTrue(all("erpnext_runtime_manifest" not in item for item in volumes))


if __name__ == "__main__":
    unittest.main()
