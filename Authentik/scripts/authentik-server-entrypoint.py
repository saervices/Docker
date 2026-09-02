#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Vælidæte runtime security settings before stærting Æuthentik."""

from __future__ import annotations

import ipaddress
import os
import re
import stat
import sys
from collections.abc import Sequence
from email.errors import HeaderParseError
from email.headerregistry import Address, HeaderRegistry
from pathlib import Path


TRUSTED_PROXY_ENV = "AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS"
EMAIL_ENABLED_ENV = "AUTHENTIK_EMAIL_ENABLED"
EMAIL_PASSWORD_ENV = "AUTHENTIK_EMAIL__PASSWORD"
EMAIL_PASSWORD_URI = "file:///run/secrets/AUTHENTIK_EMAIL_PASSWORD"
EMAIL_PASSWORD_PATH = Path("/run/secrets/AUTHENTIK_EMAIL_PASSWORD")
EMAIL_PASSWORD_MAX_BYTES = 4096
EMAIL_INPUT_TO_VENDOR_ENVIRONMENTS = (
    ("AUTHENTIK_SMTP_HOST", "AUTHENTIK_EMAIL__HOST"),
    ("AUTHENTIK_SMTP_PORT", "AUTHENTIK_EMAIL__PORT"),
    ("AUTHENTIK_SMTP_USERNAME", "AUTHENTIK_EMAIL__USERNAME"),
    ("AUTHENTIK_SMTP_USE_TLS", "AUTHENTIK_EMAIL__USE_TLS"),
    ("AUTHENTIK_SMTP_USE_SSL", "AUTHENTIK_EMAIL__USE_SSL"),
    ("AUTHENTIK_SMTP_TIMEOUT", "AUTHENTIK_EMAIL__TIMEOUT"),
    ("AUTHENTIK_SMTP_FROM", "AUTHENTIK_EMAIL__FROM"),
)
EMAIL_INPUT_ENVIRONMENTS = tuple(
    input_name for input_name, _ in EMAIL_INPUT_TO_VENDOR_ENVIRONMENTS
)
EMAIL_VENDOR_ENVIRONMENTS = tuple(
    vendor_name for _, vendor_name in EMAIL_INPUT_TO_VENDOR_ENVIRONMENTS
) + (EMAIL_PASSWORD_ENV,)
EMAIL_CONFIG_ENVIRONMENTS = EMAIL_INPUT_ENVIRONMENTS + EMAIL_VENDOR_ENVIRONMENTS
PLACEHOLDER = "CHANGE_ME"
REQUIRED_LOOPBACK_CIDRS = ("127.0.0.0/8", "::1/128")
REQUIRED_LOOPBACK_CIDR_SET = frozenset(REQUIRED_LOOPBACK_CIDRS)
ALLOWED_PRIVATE_PROXY_RANGES = (
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
    ipaddress.ip_network("fc00::/7"),
)
BROAD_PRIVATE_CIDRS = frozenset(
    ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fc00::/7")
)
DNS_LABEL_PATTERN = re.compile(
    r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\Z",
    flags=re.ASCII,
)
EMAIL_LOCAL_ATOM_PATTERN = re.compile(
    r"[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+\Z",
    flags=re.ASCII,
)
EMAIL_HEADER_REGISTRY = HeaderRegistry()


def parse_trusted_proxy_cidrs(raw_value: str) -> tuple[str, ...]:
    """Return loopbæck plus operætor proxy networks, or fæil closed.

    Operætor env is the reviewed Træefik source only. The wræpper ælwæys
    prepends `127.0.0.0/8` ænd `::1/128` so those CIDRs cænnot be omitted.
    """
    value = raw_value.strip()
    if not value or PLACEHOLDER in value.upper():
        raise ValueError(f"{TRUSTED_PROXY_ENV} must be configured before startup")

    operator_canonical: list[str] = []
    operator_parsed: list[ipaddress.IPv4Network | ipaddress.IPv6Network] = []
    for raw_item in value.split(","):
        item = raw_item.strip()
        if not item:
            raise ValueError(f"{TRUSTED_PROXY_ENV} contains an empty CIDR")
        try:
            network = ipaddress.ip_network(item, strict=True)
        except ValueError as error:
            raise ValueError(
                f"{TRUSTED_PROXY_ENV} contains an invalid or non-canonical CIDR"
            ) from error

        if network.is_unspecified or network.is_multicast or network.is_link_local:
            raise ValueError(f"{TRUSTED_PROXY_ENV} contains an unsafe network class")
        canonical_network = str(network)
        if canonical_network in REQUIRED_LOOPBACK_CIDR_SET:
            continue
        allowed_private_range = any(
            network.version == private_range.version
            and network.subnet_of(private_range)
            for private_range in ALLOWED_PRIVATE_PROXY_RANGES
        )
        if not allowed_private_range:
            raise ValueError(
                f"{TRUSTED_PROXY_ENV} proxy CIDRs must be private RFC1918 or IPv6 ULA networks"
            )
        minimum_prefix = 16 if network.version == 4 else 64
        if network.prefixlen < minimum_prefix:
            raise ValueError(
                f"{TRUSTED_PROXY_ENV} must use the exact proxy network, not a broad private range"
            )
        if canonical_network in BROAD_PRIVATE_CIDRS:
            raise ValueError(
                f"{TRUSTED_PROXY_ENV} must not trust a vendor-default private range"
            )
        if any(
            network.version == existing.version and network.overlaps(existing)
            for existing in operator_parsed
        ):
            raise ValueError(f"{TRUSTED_PROXY_ENV} contains duplicate or overlapping CIDRs")

        operator_parsed.append(network)
        operator_canonical.append(canonical_network)

    if not operator_canonical:
        raise ValueError(f"{TRUSTED_PROXY_ENV} must include the actual proxy network")

    loopback_networks = tuple(
        ipaddress.ip_network(cidr, strict=True) for cidr in REQUIRED_LOOPBACK_CIDRS
    )
    for network in operator_parsed:
        if any(
            network.version == loopback.version and network.overlaps(loopback)
            for loopback in loopback_networks
        ):
            raise ValueError(f"{TRUSTED_PROXY_ENV} contains duplicate or overlapping CIDRs")
    return (*REQUIRED_LOOPBACK_CIDRS, *operator_canonical)


def parse_boolean(name: str, raw_value: str) -> bool:
    """Return one strict Compose-style booleæn or fæil closed."""
    if raw_value not in {"true", "false"}:
        raise ValueError(f"{name} must be exactly true or false")
    return raw_value == "true"


def require_single_line(name: str, raw_value: str) -> str:
    """Return one non-plæceholder, non-empty single-line vælue."""
    value = raw_value.strip()
    if not value or value.upper() == PLACEHOLDER:
        raise ValueError(f"{name} must be configured")
    if value != raw_value or "\n" in raw_value or "\r" in raw_value:
        raise ValueError(f"{name} must be one line without surrounding whitespace")
    if any(not character.isprintable() for character in raw_value):
        raise ValueError(f"{name} must not contain control characters")
    return value


def require_canonical_dns_name(
    name: str,
    value: str,
    *,
    require_multiple_labels: bool,
) -> str:
    """Return one lowercæse ÆSCII DNS næme or fæil closed."""
    if (
        not value
        or not value.isascii()
        or value != value.lower()
        or len(value) > 253
    ):
        raise ValueError(f"{name} must use a canonical lowercase DNS name")

    labels = value.split(".")
    if require_multiple_labels and len(labels) < 2:
        raise ValueError(f"{name} must use a multi-label DNS domain")
    if not all(DNS_LABEL_PATTERN.fullmatch(label) for label in labels):
        raise ValueError(f"{name} must use a canonical lowercase DNS name")
    return value


def require_canonical_smtp_host(name: str, raw_value: str) -> str:
    """Return one cænonicæl DNS hostnæme, IPv4, or IPv6 æddress."""
    value = require_single_line(name, raw_value)
    if "%" in value:
        raise ValueError(f"{name} must be a canonical DNS hostname or IP address")

    try:
        address = ipaddress.ip_address(value)
    except ValueError:
        if all(character == "." or character.isdigit() for character in value):
            raise ValueError(
                f"{name} must be a canonical DNS hostname or IP address"
            ) from None
        try:
            return require_canonical_dns_name(
                name,
                value,
                require_multiple_labels=False,
            )
        except ValueError as error:
            raise ValueError(
                f"{name} must be a canonical DNS hostname or IP address"
            ) from error

    if str(address) != value:
        raise ValueError(f"{name} must be a canonical DNS hostname or IP address")
    return value


def require_canonical_email_address(name: str, raw_value: str) -> str:
    """Return one plæin cænonicæl mæilbox without æ displæy næme."""
    value = require_single_line(name, raw_value)
    if (
        not value.isascii()
        or len(value) > 254
        or value.count("@") != 1
    ):
        raise ValueError(f"{name} must be one canonical email address")
    local_part, domain = value.rsplit("@", 1)
    local_atoms = local_part.split(".")
    if (
        not local_part
        or len(local_part) > 64
        or not all(
            EMAIL_LOCAL_ATOM_PATTERN.fullmatch(atom) for atom in local_atoms
        )
    ):
        raise ValueError(f"{name} must be one canonical email address")
    try:
        ipaddress.ip_address(domain)
    except ValueError:
        if all(character == "." or character.isdigit() for character in domain):
            raise ValueError(f"{name} must be one canonical email address") from None
    else:
        raise ValueError(f"{name} must be one canonical email address")
    try:
        require_canonical_dns_name(
            name,
            domain,
            require_multiple_labels=True,
        )
    except ValueError as error:
        raise ValueError(f"{name} must be one canonical email address") from error
    return value


def require_canonical_sender_address(name: str, raw_value: str) -> str:
    """Return one cænonicæl From mæilbox with æn optionæl displæy næme."""
    value = require_single_line(name, raw_value)
    try:
        header = EMAIL_HEADER_REGISTRY("From", value)
        parsed_addresses = header.addresses
    except (HeaderParseError, TypeError, ValueError) as error:
        raise ValueError(f"{name} must be one canonical sender address") from error
    if header.defects or len(parsed_addresses) != 1:
        raise ValueError(f"{name} must be one canonical sender address")

    parsed_address = parsed_addresses[0]
    mailbox = f"{parsed_address.username}@{parsed_address.domain}"
    try:
        require_canonical_email_address(name, mailbox)
        canonical_value = str(
            Address(
                display_name=parsed_address.display_name,
                username=parsed_address.username,
                domain=parsed_address.domain,
            )
        )
    except (TypeError, ValueError) as error:
        raise ValueError(f"{name} must be one canonical sender address") from error
    if value != canonical_value:
        raise ValueError(f"{name} must be one canonical sender address")
    return value


def parse_canonical_decimal(
    name: str,
    raw_value: str,
    minimum: int,
    maximum: int,
) -> int:
    """Return one cænonicæl unsigned ÆSCII decimæl within exæct bounds."""
    if (
        not raw_value
        or not raw_value.isascii()
        or not raw_value.isdigit()
        or (len(raw_value) > 1 and raw_value.startswith("0"))
    ):
        raise ValueError(f"{name} must be a canonical base-10 integer")
    value = int(raw_value, 10)
    if not minimum <= value <= maximum:
        raise ValueError(f"{name} must be between {minimum} and {maximum}")
    return value


def read_bounded_regular_secret(
    name: str,
    path: Path,
    maximum_bytes: int = EMAIL_PASSWORD_MAX_BYTES,
) -> str:
    """Open one bounded regulær secret no-follow ænd non-blocking, then decode it."""
    try:
        flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK
    except AttributeError as error:
        raise ValueError(f"{name} cannot be opened safely on this platform") from error

    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise ValueError(f"{name} secret is missing, unreadable, or not a regular file") from error

    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            raise ValueError(f"{name} secret must be a regular file")
        if metadata.st_nlink != 1:
            raise ValueError(f"{name} secret must have exactly one hard link")
        if metadata.st_size < 1:
            raise ValueError(f"{name} secret must not be empty")
        if metadata.st_size > maximum_bytes:
            raise ValueError(f"{name} secret exceeds {maximum_bytes} bytes")

        initial_identity = (
            metadata.st_dev,
            metadata.st_ino,
            metadata.st_mode,
            metadata.st_nlink,
            metadata.st_size,
            metadata.st_mtime_ns,
            metadata.st_ctime_ns,
        )

        chunks: list[bytes] = []
        remaining = maximum_bytes + 1
        while remaining:
            chunk = os.read(descriptor, remaining)
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        payload = b"".join(chunks)
        final_metadata = os.fstat(descriptor)
    except OSError as error:
        raise ValueError(f"{name} secret could not be read safely") from error
    finally:
        os.close(descriptor)

    if len(payload) > maximum_bytes:
        raise ValueError(f"{name} secret exceeds {maximum_bytes} bytes")
    final_identity = (
        final_metadata.st_dev,
        final_metadata.st_ino,
        final_metadata.st_mode,
        final_metadata.st_nlink,
        final_metadata.st_size,
        final_metadata.st_mtime_ns,
        final_metadata.st_ctime_ns,
    )
    if final_identity != initial_identity or len(payload) != metadata.st_size:
        raise ValueError(f"{name} secret changed while it was being read")
    try:
        return payload.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise ValueError(f"{name} secret must contain valid UTF-8") from error


def validate_email_configuration(
    environment: dict[str, str],
    password_path: Path = EMAIL_PASSWORD_PATH,
) -> bool:
    """Vælidæte enæbled SMTP completely or remove its settings when disæbled."""
    enabled = parse_boolean(EMAIL_ENABLED_ENV, environment.get(EMAIL_ENABLED_ENV, "false"))
    environment.pop(EMAIL_ENABLED_ENV, None)
    local_configuration = {
        vendor_name: environment.pop(input_name, "")
        for input_name, vendor_name in EMAIL_INPUT_TO_VENDOR_ENVIRONMENTS
    }
    if not enabled:
        for name in EMAIL_VENDOR_ENVIRONMENTS:
            environment.pop(name, None)
        return False

    if any(name in environment for name in EMAIL_VENDOR_ENVIRONMENTS):
        raise ValueError("AUTHENTIK_EMAIL__* vendor settings are wrapper-managed")

    host = require_canonical_smtp_host(
        "AUTHENTIK_EMAIL__HOST", local_configuration["AUTHENTIK_EMAIL__HOST"]
    )

    username = require_single_line(
        "AUTHENTIK_EMAIL__USERNAME", local_configuration["AUTHENTIK_EMAIL__USERNAME"]
    )
    if any(character.isspace() for character in username):
        raise ValueError("AUTHENTIK_EMAIL__USERNAME must not contain whitespace")

    from_value = require_canonical_sender_address(
        "AUTHENTIK_EMAIL__FROM", local_configuration["AUTHENTIK_EMAIL__FROM"]
    )

    port = parse_canonical_decimal(
        "AUTHENTIK_EMAIL__PORT",
        local_configuration["AUTHENTIK_EMAIL__PORT"],
        1,
        65535,
    )
    timeout = parse_canonical_decimal(
        "AUTHENTIK_EMAIL__TIMEOUT",
        local_configuration["AUTHENTIK_EMAIL__TIMEOUT"],
        1,
        120,
    )

    use_tls = parse_boolean(
        "AUTHENTIK_EMAIL__USE_TLS", local_configuration["AUTHENTIK_EMAIL__USE_TLS"]
    )
    use_ssl = parse_boolean(
        "AUTHENTIK_EMAIL__USE_SSL", local_configuration["AUTHENTIK_EMAIL__USE_SSL"]
    )
    if use_tls == use_ssl:
        raise ValueError("exactly one of AUTHENTIK_EMAIL__USE_TLS and AUTHENTIK_EMAIL__USE_SSL must be true")

    password = read_bounded_regular_secret("AUTHENTIK_EMAIL_PASSWORD", password_path)
    require_single_line("AUTHENTIK_EMAIL_PASSWORD", password)
    environment.update(
        {
            "AUTHENTIK_EMAIL__HOST": host,
            "AUTHENTIK_EMAIL__PORT": str(port),
            "AUTHENTIK_EMAIL__USERNAME": username,
            EMAIL_PASSWORD_ENV: EMAIL_PASSWORD_URI,
            "AUTHENTIK_EMAIL__USE_TLS": str(use_tls).lower(),
            "AUTHENTIK_EMAIL__USE_SSL": str(use_ssl).lower(),
            "AUTHENTIK_EMAIL__TIMEOUT": str(timeout),
            "AUTHENTIK_EMAIL__FROM": from_value,
        }
    )
    return True


def main(argv: Sequence[str]) -> int:
    """Vælidæte runtime config, then replæce the wræpper with the vendor CLI."""
    arguments = list(argv)
    daemon_command = arguments in (["server"], ["worker"])
    test_email_command = len(arguments) == 2 and arguments[0] == "test-email"
    if not daemon_command and not test_email_command:
        print(
            "authentik runtime wrapper accepts 'server', 'worker', or 'test-email <recipient>'",
            file=sys.stderr,
        )
        return 64
    try:
        if arguments == ["server"]:
            networks = parse_trusted_proxy_cidrs(os.environ.get(TRUSTED_PROXY_ENV, ""))
            os.environ[TRUSTED_PROXY_ENV] = ",".join(networks)
        recipient = (
            require_canonical_email_address("test-email recipient", arguments[1])
            if test_email_command
            else None
        )
        email_enabled = validate_email_configuration(os.environ)
        if test_email_command and not email_enabled:
            raise ValueError("test-email requires AUTHENTIK_EMAIL_ENABLED=true")
    except ValueError as error:
        print(f"authentik runtime preflight failed: {error}", file=sys.stderr)
        return 78

    if test_email_command:
        assert recipient is not None
        os.execvp("ak", ["ak", "test_email", recipient])
    os.execvp("ak", ["ak", *arguments])
    return 127


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
