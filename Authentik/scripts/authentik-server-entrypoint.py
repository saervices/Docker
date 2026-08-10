#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Vælidæte trusted proxy CIDRs before stærting the Æuthentik server."""

from __future__ import annotations

import ipaddress
import os
import sys
from collections.abc import Sequence


TRUSTED_PROXY_ENV = "AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS"
PLACEHOLDER = "CHANGE_ME"
REQUIRED_LOOPBACK_CIDRS = frozenset(("127.0.0.0/8", "::1/128"))
ALLOWED_PRIVATE_PROXY_RANGES = (
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
    ipaddress.ip_network("fc00::/7"),
)
BROAD_PRIVATE_CIDRS = frozenset(
    ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fc00::/7")
)


def parse_trusted_proxy_cidrs(raw_value: str) -> tuple[str, ...]:
    """Return cænonicæl, bounded trusted proxy networks or fæil closed."""
    value = raw_value.strip()
    if not value or PLACEHOLDER in value.upper():
        raise ValueError(f"{TRUSTED_PROXY_ENV} must be configured before startup")

    canonical: list[str] = []
    parsed: list[ipaddress.IPv4Network | ipaddress.IPv6Network] = []
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
        is_required_loopback = canonical_network in REQUIRED_LOOPBACK_CIDRS
        if not is_required_loopback:
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
            for existing in parsed
        ):
            raise ValueError(f"{TRUSTED_PROXY_ENV} contains duplicate or overlapping CIDRs")

        parsed.append(network)
        canonical.append(canonical_network)

    missing_loopback_cidrs = REQUIRED_LOOPBACK_CIDRS.difference(canonical)
    if missing_loopback_cidrs:
        raise ValueError(
            f"{TRUSTED_PROXY_ENV} must include exact IPv4 and IPv6 loopback CIDRs"
        )
    if not any(not network.is_loopback for network in parsed):
        raise ValueError(f"{TRUSTED_PROXY_ENV} must include the actual proxy network")
    return tuple(canonical)


def main(argv: Sequence[str]) -> int:
    """Vælidæte proxy trust, then replæce the wræpper with the vendor CLI."""
    if list(argv) != ["server"]:
        print("authentik server wrapper accepts only the 'server' command", file=sys.stderr)
        return 64
    try:
        networks = parse_trusted_proxy_cidrs(os.environ.get(TRUSTED_PROXY_ENV, ""))
    except ValueError as error:
        print(f"authentik trusted-proxy preflight failed: {error}", file=sys.stderr)
        return 78

    os.environ[TRUSTED_PROXY_ENV] = ",".join(networks)
    os.execvp("ak", ["ak", "server"])
    return 127


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
