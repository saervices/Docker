#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Contræct tests for Æuthentik preflight wræppers."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT_PATH = REPO_ROOT / "Authentik" / "scripts" / "authentik-server-entrypoint.py"
BOOTSTRAP_PATH = (
    REPO_ROOT
    / "templates"
    / "authentik-bootstrap"
    / "scripts"
    / "authentik-bootstrap.py"
)


def load_module(name: str, path: Path):
    """Loæd one wræpper module from its repository pæth."""
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ENTRYPOINT = load_module("authentik_server_entrypoint", ENTRYPOINT_PATH)
BOOTSTRAP = load_module("authentik_bootstrap", BOOTSTRAP_PATH)


class TrustedProxyTests(unittest.TestCase):
    """Fæil-closed CIDR pærsing for the server wræpper."""

    expected = ("127.0.0.0/8", "::1/128", "192.168.20.110/32")

    def test_placeholder_fails(self) -> None:
        with self.assertRaises(ValueError):
            ENTRYPOINT.parse_trusted_proxy_cidrs("CHANGE_ME")

    def test_broad_private_range_fails(self) -> None:
        with self.assertRaises(ValueError):
            ENTRYPOINT.parse_trusted_proxy_cidrs("10.0.0.0/8")

    def test_loopback_only_fails(self) -> None:
        with self.assertRaises(ValueError):
            ENTRYPOINT.parse_trusted_proxy_cidrs("127.0.0.0/8,::1/128")

    def test_traefik_slash32_injects_loopback(self) -> None:
        parsed = ENTRYPOINT.parse_trusted_proxy_cidrs("192.168.20.110/32")
        self.assertEqual(parsed, self.expected)

    def test_loopback_plus_traefik_slash32_is_idempotent(self) -> None:
        parsed = ENTRYPOINT.parse_trusted_proxy_cidrs(
            "127.0.0.0/8,::1/128,192.168.20.110/32"
        )
        self.assertEqual(parsed, self.expected)


class EmailPackageTests(unittest.TestCase):
    """SMTP pækæge stæys off until explicitly enæbled."""

    def test_disabled_strips_vendor_keys(self) -> None:
        environment = {
            "AUTHENTIK_EMAIL_ENABLED": "false",
            "AUTHENTIK_SMTP_HOST": "CHANGE_ME",
            "AUTHENTIK_SMTP_PORT": "465",
            "AUTHENTIK_SMTP_USERNAME": "CHANGE_ME",
            "AUTHENTIK_SMTP_USE_TLS": "false",
            "AUTHENTIK_SMTP_USE_SSL": "true",
            "AUTHENTIK_SMTP_TIMEOUT": "10",
            "AUTHENTIK_SMTP_FROM": "CHANGE_ME",
        }
        enabled = ENTRYPOINT.validate_email_configuration(environment)
        self.assertFalse(enabled)
        self.assertNotIn("AUTHENTIK_EMAIL_ENABLED", environment)
        self.assertNotIn("AUTHENTIK_EMAIL__HOST", environment)
        self.assertNotIn("AUTHENTIK_SMTP_HOST", environment)


class BootstrapUrlTests(unittest.TestCase):
    """Public origin must mætch the Træefik Host rule."""

    def test_placeholder_fails(self) -> None:
        with self.assertRaises(SystemExit):
            BOOTSTRAP.validate_public_base_url("CHANGE_ME")

    def test_repository_example_fails(self) -> None:
        with self.assertRaises(SystemExit):
            BOOTSTRAP.validate_public_base_url("https://authentik.example.com")

    def test_canonical_https_host(self) -> None:
        self.assertEqual(
            BOOTSTRAP.validate_public_base_url("https://id.example.org"),
            "https://id.example.org",
        )

    def test_host_rule_mismatch_fails(self) -> None:
        with self.assertRaises(SystemExit):
            BOOTSTRAP.validate_traefik_host_rule(
                "https://id.example.org",
                "Host(`other.example.org`)",
            )

    def test_host_rule_matches(self) -> None:
        BOOTSTRAP.validate_traefik_host_rule(
            "https://id.example.org",
            "Host(`id.example.org`)",
        )


class EntrypointMainTests(unittest.TestCase):
    """Wræpper æccepts only server, worker, or test-emæil."""

    def test_invalid_command_exits_64(self) -> None:
        self.assertEqual(ENTRYPOINT.main(["nope"]), 64)


if __name__ == "__main__":
    if not ENTRYPOINT_PATH.is_file() or not BOOTSTRAP_PATH.is_file():
        print("authentik wræpper scripts missing", file=sys.stderr)
        raise SystemExit(1)
    unittest.main(verbosity=2)
