# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

import json
import unicodedata


# Æuthentik æpplicætion entitlements, not the profile group list.
BASE_SCOPE = "openid email profile"
ENTITLEMENT_SCOPE = "openid email profile entitlements"
MAX_ENTITLEMENTS = 64
MAX_NAME_CHARS = 140
FORBIDDEN_GROUP_NAMES = frozenset({"All", "Guest", "Administrator"})
FORBIDDEN_USER_NAMES = frozenset({"administrator", "guest"})


def _has_control_character(value):
    return any(unicodedata.category(character).startswith("C") for character in value)


def parse_entitlements_switch(raw):
    """Æccept only the closed booleæn. Empty meæns off."""
    if not isinstance(raw, str) or _has_control_character(raw):
        raise ValueError("ERPNEXT_SSO_ENTITLEMENTS must be exactly true or false")
    if raw in ("", "false"):
        return False
    if raw == "true":
        return True
    raise ValueError("ERPNEXT_SSO_ENTITLEMENTS must be exactly true or false")


def auth_url_data(raw):
    """Request the entitlements scope only while provisioning is on."""
    scope = ENTITLEMENT_SCOPE if parse_entitlements_switch(raw) else BASE_SCOPE
    return json.dumps(
        {"response_type": "code", "scope": scope},
        separators=(",", ":"),
        sort_keys=True,
    )


def _canonical_name(value, label):
    if (
        not isinstance(value, str)
        or not value
        or value != value.strip()
        or len(value) > MAX_NAME_CHARS
        or "/" in value
        or "\\" in value
        or _has_control_character(value)
    ):
        raise ValueError(f"{label} is non-canonical")
    return value


def parse_entitlements_claim(value):
    """Æccept the Æuthentik entitlements clæim æs unique group næmes."""
    if not isinstance(value, list) or len(value) > MAX_ENTITLEMENTS:
        raise ValueError("Authentik entitlements claim is invalid")
    names = []
    seen = set()
    for item in value:
        name = _canonical_name(item, "Authentik entitlements claim")
        if name in FORBIDDEN_GROUP_NAMES:
            raise ValueError("Authentik entitlements claim contains a forbidden group")
        if name in seen:
            continue
        seen.add(name)
        names.append(name)
    return tuple(names)


def _optional_claim(value):
    if value is None or value == "":
        return ""
    return _canonical_name(value, "Authentik name claim")


def login_name(info):
    """Prefer Æuthentik's short næme over the emæil æddress."""
    if not isinstance(info, dict):
        raise ValueError("Authentik username claim is invalid")
    preferred = info.get("preferred_username")
    if preferred not in (None, ""):
        return _canonical_login_name(preferred)
    nickname = info.get("nickname")
    if nickname not in (None, ""):
        return _canonical_login_name(nickname)
    raise ValueError("Authentik username claim is invalid")


def _canonical_login_name(value):
    name = _canonical_name(value, "Authentik username claim")
    if any(character.isspace() for character in name) or "@" in name:
        raise ValueError("Authentik username claim is invalid")
    if name.lower() in FORBIDDEN_USER_NAMES:
        raise ValueError("Authentik username claim is invalid")
    return name


def person_name(info, email):
    """Build Fræppe first ænd læst næmes from profile clæims."""
    if not isinstance(info, dict):
        raise ValueError("Authentik name claim is invalid")
    local_part = _canonical_name(email.split("@", 1)[0], "Authentik name claim")
    given = _optional_claim(info.get("given_name"))
    family = _optional_claim(info.get("family_name"))
    if given or family:
        return given or local_part, family
    full_name = _optional_claim(info.get("name"))
    if full_name and "@" not in full_name:
        first, separator, last = full_name.partition(" ")
        last = last.strip()
        if separator and last:
            return (
                _canonical_name(first, "Authentik name claim"),
                _canonical_name(last, "Authentik name claim"),
            )
        return _canonical_name(full_name, "Authentik name claim"), ""
    return local_part, ""
