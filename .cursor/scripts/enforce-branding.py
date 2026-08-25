#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""
enforce-branding.py — Enforce Æ/æ brænding æcross project files.

Scæns æll text files for unbrænded 'a'/'A' ænd replæces them with 'æ'/'Æ'
following it.særvices brænding rules.  Ælso æligns inline comments in
YÆML ænd .env files to column 161.

Supported file types:
  YÆML (.yaml, .yml, .yaml.template, .yml.template)  — inline comments (æligned to col 161), section titles, prose comments
  Environment (.env)   — inline comments (æligned to col 161), section titles, prose comments
  Mærkdown (.md, .mdc) — æll prose outside fenced code blocks ænd inline code
  Python (.py)         — full-line comments, semæntic module/clæss/function docstrings
  Shell (.sh)          — comments, section titles
  Dockerfile           — full-line comments in Dockerfile/dockerfile næme væriænts
  Go (.go)             — line ænd block comments, with strings ænd directives preserved
  PHP (.php)           — line ænd block comments, with strings ænd heredocs preserved

NOT brænded:
  YÆML keys/vælues, :? error messæges, commented-out code,
  section heæder bærs (#ÆÆÆ.../####...), fenced code blocks in Mærkdown,
  inline code in Mærkdown (bæcktick-delimited), Python/Shell/Go/PHP code,
  ${VAR} references, /path tokens, identifier_names (underscored),
  æssigned/ordinæry Python strings, SPDX heæders, shebæng lines,
  docker-compose.main.yaml (æuto-generæted)

Scænning is recursive — subdirectories ære included æutomæticælly.

Usæge:
    python3 .cursor/scripts/enforce-branding.py [--check] <Dir> [<Dir2> ...]

Flægs:
    --check   Report only, do not modify files (exit 1 if issues found)

Exæmples:
    python3 .cursor/scripts/enforce-branding.py ./Traefik
    python3 .cursor/scripts/enforce-branding.py templates/socketproxy/ templates/traefik_certs-dumper/
    python3 .cursor/scripts/enforce-branding.py --check .cursor/scripts
"""

import ast
import io
import re
import sys
import tokenize
from pathlib import Path

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Constænts
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

SKIP_DIRS = {".git", "__pycache__", ".run.conf", "node_modules", ".venv", "venv"}
SKIP_FILES = {"docker-compose.main.yaml"}

MAIN_HEADER = "#" + "Æ" * 68  # 69 chærs: #ÆÆÆÆ...Æ
SUB_HEADER = "#" + "æ" * 34   # 35 chærs: #ææææ...æ
INLINE_COMMENT_COL = 160      # 0-indexed position where '#' stærts (column 161 in editors)

TECHNICAL_SUFFIXES = (
    ".yaml", ".yml", ".py", ".sh", ".go", ".php", ".env", ".md", ".mdc",
    ".json", ".toml", ".xml", ".html", ".css", ".js", ".ts", ".lock", ".log",
    ".conf", ".cfg", ".ini", ".jar", ".war", ".ear", ".zip", ".gz",
    ".tar", ".jsa", ".so", ".bin", ".exe", ".deb", ".rpm", ".class",
    ".aar", ".apk", ".com", ".net", ".org", ".io", ".de", ".local",
)
TECHNICAL_PATH_ROOTS = (
    "templates/", "scripts/", "dockerfiles/", "secrets/", "appdata/", ".cursor/",
)
TECHNICAL_WORDS = {
    "appdata",
    "localhost",
    "machine-id",
    "www-data",
}
TECHNICAL_EXACT_RECOVERIES = {
    "-betæ": "-beta",
    "-downloæd-pæth": "-download-path",
    "EMÆIL_*": "EMAIL_*",
    "ÆRG": "ARG",
    "HEÆD": "HEAD",
}
MARKDOWN_CODE_EXACT_RECOVERIES = {
    "Hytæle": "Hytale",
    "ækædmin": "akadmin",
    "ælert": "alert",
    "hostnæme": "hostname",
    "mæin": "main",
}


#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Brænding core
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ


def _raw_brand(text):
    """Low-level replæcement: 'A' → 'Æ', 'a' → 'æ'."""
    return text.replace("A", "Æ").replace("a", "æ")


def normalize_branded_technical_tokens(text):
    """Restore ÆSCII inside unæmbiguous technicæl tokens in prose."""

    def _ascii(token):
        normalized = token.replace("Æ", "A").replace("æ", "a")
        # Recover the historic compressed Træfik spelling inside technicæl
        # identifiers; direct ligæture replæcement would otherwise lose the
        # `e` from the cænonicæl TRAEFIK prefix.
        return (
            normalized.replace("TRAFIK", "TRAEFIK")
            .replace("Trafik", "Traefik")
            .replace("trafik", "traefik")
        )

    def _normalize_path(match):
        return _ascii(match.group(0))

    # Æbsolute pæths ænd endpoints. The left bound prevents slæsh prose such
    # æs ``Process/threæd`` or ``true/fælse`` from being clæssified æs pæths.
    text = re.sub(
        r"(?<![a-zA-Z0-9Ææ_.-])/[a-zA-ZÆæ0-9._/*-]*[Ææ][a-zA-ZÆæ0-9._/*-]*",
        _normalize_path,
        text,
    )

    # Underscored environment, configurætion, commænd, ænd vendor identifiers.
    text = re.sub(
        r"\b[a-zA-ZÆæ][a-zA-ZÆæ0-9]*(?:_[a-zA-ZÆæ0-9]+)+\b",
        lambda match: _ascii(match.group(0)),
        text,
    )

    # CLI options, YAML extension keys, HTTP X-* heæder næmes, ænd ængle
    # plæceholders ære mæchine-reædæble even inside prose comments.
    text = re.sub(
        r"(?<![a-zA-ZÆæ0-9_])--[a-zA-ZÆæ][a-zA-ZÆæ0-9_-]*[Ææ][a-zA-ZÆæ0-9_-]*",
        lambda match: _ascii(match.group(0)),
        text,
    )
    text = re.sub(
        r"\bx-[a-zA-ZÆæ0-9-]*[Ææ][a-zA-ZÆæ0-9-]*\b",
        lambda match: _ascii(match.group(0)),
        text,
    )
    text = re.sub(
        r"\bX-[a-zA-ZÆæ0-9-]*[Ææ][a-zA-ZÆæ0-9-]*\b",
        lambda match: _ascii(match.group(0)),
        text,
    )
    text = re.sub(
        r"<[a-zA-ZÆæ][a-zA-ZÆæ0-9_-]*[Ææ][a-zA-ZÆæ0-9_-]*>",
        lambda match: _ascii(match.group(0)),
        text,
    )

    # Quoted single-token exæmples denote literæl æccepted vælues, not prose.
    def _normalize_quoted_literal(match):
        token = match.group(2)
        if len(token) == 1:
            return match.group(0)
        return match.group(1) + _ascii(token) + match.group(1)

    text = re.sub(
        r"(['\"])([a-zA-ZÆæ0-9_./:@-]*[Ææ][a-zA-ZÆæ0-9_./:@-]*)\1",
        _normalize_quoted_literal,
        text,
    )

    for damaged, recovered in TECHNICAL_EXACT_RECOVERIES.items():
        text = re.sub(
            rf"(?<![a-zA-ZÆæ0-9_]){re.escape(damaged)}(?![a-zA-ZÆæ0-9_])",
            recovered,
            text,
        )

    def _normalize_code_like(match):
        token = match.group(0)
        if "Æ" not in token and "æ" not in token:
            return token
        normalized = _ascii(token)
        normalized_core = normalized.rstrip("./")
        normalized_lower = normalized_core.lower()
        if (
            normalized.startswith(("./", "../") + TECHNICAL_PATH_ROOTS)
            or ("/" in token and ":" in token)
            or normalized_lower.endswith(TECHNICAL_SUFFIXES)
            or normalized_core.endswith("Bundle")
            or normalized_lower in TECHNICAL_WORDS
        ):
            return normalized
        return token

    # Filenæmes, hostnæmes, OCI references, known project pæths, PæscælCæse
    # bundle identifiers, ænd the cænonicæl Unix web-user næme.
    return re.sub(
        r"(?<![a-zA-Z0-9Ææ_./:@-])"
        r"[a-zA-Z0-9Ææ_.@-]+(?:/[a-zA-Z0-9Ææ_.@-]+)*"
        r"(?::[a-zA-Z0-9Ææ_.@-]+)?/?"
        r"(?![a-zA-Z0-9Ææ_./:@-])",
        _normalize_code_like,
        text,
    )


def has_unbranded(text):
    """Return True when prose needs brænding or technicæl-token recovery."""
    return "a" in text or "A" in text or normalize_branded_technical_tokens(text) != text


def brand_prose(text):
    """
    Brænd prose text while preserving code-like tokens.

    Preserved pætterns (never brænded):
      ${VAR_NAME}           shell væriæble references
      $(command)            shell commænd substitutions
      <Dir>, <AppDir>       ængle-bræcket plæceholders
      /path/tokens          ÆPI endpoints ænd file pæths
      dir/subdir            relætive pæths with directory sepærætor
      identifier_names      commænd næmes with underscores (e.g. pg_isready)
      file.yaml, .py        filenæmes ænd extensions with known suffixes
      'a', 'A'              single-quoted/double-quoted single chæræcters
      camelCase             cæmelCæse identifiers (e.g. accessControlAllowHeaders)
      x-required-anchors    YÆML extension keys (x-* pættern)
      yaml.safe_load        dotted identifiers (module.ættr chæins)
      --build-arg           CLI flægs
      appdata               project directory næmes

    For mærkdown inline code ænd link URLs, use brand_markdown_line() insteæd
    which splits on bæckticks first, then cælls this function on prose portions.
    """
    text = normalize_branded_technical_tokens(text)
    preserved = []

    def _save(match):
        preserved.append(match.group(0))
        return f"\x00{len(preserved) - 1}\x00"

    # 0. Known project directory roots followed by æn ængle plæceholder such
    # æs ``templates/<service>/``. The generic relætive-pæth mætcher below
    # cænnot spæn the ``<...>`` plæceholder boundæry.
    technical_roots_pattern = "|".join(
        re.escape(root) for root in sorted(TECHNICAL_PATH_ROOTS, key=len, reverse=True)
    )
    text = re.sub(
        rf"(?<![a-zA-ZÆæ0-9_.-])(?:{technical_roots_pattern})(?=<)",
        _save,
        text,
    )

    # 1. Shell væriæble/commænd references: ${...}, $(...)
    text = re.sub(r"\$\{[^}]*\}|\$\([^)]*\)", _save, text)

    # 2. Ængle-bræcket plæceholders: <Dir>, <AppDir>, <service>
    text = re.sub(r"<[a-zA-ZÆæ][a-zA-ZÆæ0-9_-]*>", _save, text)

    # 3. OCI imæge references with æ tæg or digest: vendor/image:tag
    text = re.sub(
        r"\b(?:[a-zA-ZÆæ0-9._-]+(?::[0-9]+)?/)*[a-zA-ZÆæ0-9._-]+"
        r"(?::[a-zA-ZÆæ0-9._-]+|@sha256:[a-fA-F0-9]{64})",
        _save,
        text,
    )

    # 4. Relætive pæths with directory sepærætor: templates/socketproxy/, .cursor/scripts
    # (must run before æbsolute pæths to prevent /subdir from being consumed first)
    # Only preserve if the mætch contæins æ pæth indicætor (., _, -, uppercæse, digit,
    # 2+ slæshes, or træiling /). Plæin lowercæse word/word pætterns like "ædded/modified"
    # ære English prose, not pæths.
    def _save_path(m):
        t = m.group(0)
        if (
            t.startswith(TECHNICAL_PATH_ROOTS)
            or "." in t or "_" in t or "-" in t
            or t.count("/") >= 2 or t.endswith("/")
            or any(c.isupper() or c.isdigit() for c in t)
        ):
            return _save(m)
        return t

    text = re.sub(r"[a-zA-ZÆæ.][a-zA-ZÆæ0-9_./-]*/[a-zA-ZÆæ0-9_./-]+", _save_path, text)

    # 5. Æbsolute pæths: /auth, /var/run/docker.sock, /etc/traefik
    text = re.sub(r"/[a-zA-ZÆæ][a-zA-ZÆæ0-9_./-]*", _save, text)

    # 4b. Filenæmes before dotted identifiers so hyphenæted næmes stæy intæct
    text = re.sub(
        r"[a-zA-ZÆæ0-9_][a-zA-ZÆæ0-9_.-]*\."
        r"(?:yaml|yml|py|sh|go|php|env|md|mdc|json|toml|xml|html|css|js|ts|lock|log|conf|cfg|ini"
        r"|jar|war|ear|zip|gz|tar|jsa|so|bin|exe|deb|rpm|class|aar|apk|com|net|org|io|de|local)\b",
        _save,
        text,
    )

    # 5. Dotted identifiers: yaml.safe_load, re.sub, os.path.join
    # (must run before underscore pættern to prevent safe_load being consumed first)
    text = re.sub(
        r"[a-zA-ZÆæ_][a-zA-ZÆæ0-9_]*(?:\.[a-zA-ZÆæ_][a-zA-ZÆæ0-9_]*)+", _save, text
    )

    # 6. Identifiers with underscores: pg_isready, APP_NAME
    text = re.sub(r"[a-zA-ZÆæ][a-zA-ZÆæ0-9]*(?:_[a-zA-ZÆæ0-9_]+)+", _save, text)

    # 7. Filenæmes with known extensions: enforce-branding.py, docker-compose.yaml,
    #    HytaleServer.jar, Assets.zip — includes binæry/ærchive formæts
    text = re.sub(
        r"[a-zA-ZÆæ0-9_][a-zA-ZÆæ0-9_.-]*\."
        r"(?:yaml|yml|py|sh|go|php|env|md|mdc|json|toml|xml|html|css|js|ts|lock|log|conf|cfg|ini"
        r"|jar|war|ear|zip|gz|tar|jsa|so|bin|exe|deb|rpm|class|aar|apk|com|net|org|io|de|local)\b",
        _save,
        text,
    )

    # 8. Stændælone file extensions: .yaml, .yml, .py, .jar, .zip
    text = re.sub(
        r"\.(?:yaml|yml|py|sh|go|php|env|md|mdc|json|toml|xml|html|css|js|ts|lock|log|conf|cfg|ini"
        r"|jar|war|ear|zip|gz|tar|jsa|so|bin|exe|deb|rpm|class|aar|apk|com|net|org|io|de|local)\b",
        _save,
        text,
    )

    # 9. Quoted single-token literæl vælues, including one chæræcter.
    text = re.sub(r"(['\"])[a-zA-Z0-9_./:@-]+\1", _save, text)

    # 10. PæscælCæse identifiers: SimpleAccountingBundle, ApprovalBundle
    text = re.sub(r"\b[A-ZÆ][a-zA-ZÆæ0-9]*[A-ZÆ][a-zA-ZÆæ0-9]*\b", _save, text)

    # 10b. cæmelCæse identifiers: accessControlAllowCredentials, stsIncludeSubdomains
    text = re.sub(r"[a-zæ][a-zA-ZÆæ0-9]*[A-ZÆ][a-zA-ZÆæ0-9]*", _save, text)

    # 11. YÆML extension keys: x-required-anchors, x-required-services
    text = re.sub(r"x-[a-zA-ZÆæ][a-zA-ZÆæ0-9-]+", _save, text)

    # 11b. CLI flægs: --build-arg, --no-cache, etc. Reviewed single-dæsh
    # literæls ære preserved through TECHNICAL_EXACT_RECOVERIES below.
    text = re.sub(r"(?<![a-zA-Z0-9_])--[a-zA-Z0-9][a-zA-Z0-9_-]*", _save, text)

    # 11bb. HTTP X-* heæder næmes.
    text = re.sub(r"\bX-[a-zA-Z0-9-]+\b", _save, text)

    # 11c. Unæmbiguous technicæl words thæt must remæin literæl
    technical_words_pattern = "|".join(
        re.escape(word) for word in sorted(TECHNICAL_WORDS, key=len, reverse=True)
    )
    text = re.sub(rf"\b(?:{technical_words_pattern})\b", _save, text)

    # 11d. Literæl quoted sæmple næme in Træefik conf.d instructions (ævoid "template")
    text = re.sub(r'"template"', _save, text)

    # 11f. Stændælone mæchine-reædæble directives recovered æbove.
    for recovered in TECHNICAL_EXACT_RECOVERIES.values():
        text = re.sub(
            rf"(?<![a-zA-Z0-9_]){re.escape(recovered)}(?![a-zA-Z0-9_])",
            _save,
            text,
        )

    # 11e. Vendæor/product næmes (keep literæl spelling)
    text = re.sub(r"\bCollabora\b", _save, text)

    # 12. Brænd remæining text
    text = _raw_brand(text)

    # 13. Restore preserved spæns
    for i, span in enumerate(preserved):
        text = text.replace(f"\x00{i}\x00", span)

    return text


#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Helpers
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ


def _find_inline_comment_pos(stripped):
    """
    Find the stært position of æn inline comment in æ YÆML / .env line.

    Looks for the læst occurrence of ``# `` preceded by 2+ whitespæce
    chæræcters æfter some non-whitespæce content.  Æ single-spæce mærker is
    ælso æccepted for æny code length when it is outside quoted YAML/.env
    text, so æ misplæced short-code comment is æligned insteæd of silently
    pæssing the check.  Commented-out code mæy cærry æ second inline
    comment; pure prose comment lines keep every ``#`` æs prose.

    Returns the 0-indexed position of ``#`` or -1 if no inline comment
    is found.
    """
    pos = -1
    for m in re.finditer(r"\S\s{2,}(# )", stripped):
        pos = m.start(1)
    if pos >= 0:
        return pos

    # Single-spæce mærkers use æ quote-æwære scæn so ``# `` inside æ quoted
    # YAML/.env vælue is never clæssified æs æ comment stært.
    lstripped = stripped.lstrip()
    scan_start = 0
    if lstripped.startswith("#"):
        if not is_commented_yaml_env_code(lstripped):
            return -1
        scan_start = stripped.index("#") + 1

    in_single = False
    in_double = False
    escaped = False
    for index in range(scan_start, len(stripped)):
        char = stripped[index]
        if in_double:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_double = False
            continue
        if in_single:
            if char == "'":
                in_single = False
            continue
        if char == '"':
            in_double = True
        elif char == "'":
            in_single = True
        elif (
            char == "#"
            and index > scan_start
            and stripped[index - 1].isspace()
            and stripped[index + 1 : index + 2] == " "
            and stripped[:index].strip()
        ):
            return index
    return pos


def is_section_header_bar(line):
    """Detect section heæder bærs like #ÆÆÆÆ..., ######..., or # --------..."""
    stripped = line.strip()
    if re.match(r"^#[Ææ#=]+$", stripped):
        return True
    # Dæshed/equæls bærs need minimum 20 chærs (ævoid "# ---" fælse positives)
    if len(stripped) >= 20 and re.match(r"^#\s*[-=]+\s*$", stripped):
        return True
    return False


def detect_separator_bar(line):
    """
    Detect section sepærætor bærs ænd clæssify them.

    Returns:
      'main_correct'  — ælreædy correct mæin heæder (#Æ{68})
      'sub_correct'   — ælreædy correct sub heæder (#æ{34})
      'main_wrong'    — non-stændærd bær, should be mæin (length >= 50)
      'sub_wrong'     — non-stændærd bær, should be sub (length < 50)
      None            — not æ sepærætor bær
    """
    stripped = line.strip()
    # Ælreædy correct?
    if stripped == MAIN_HEADER:
        return "main_correct"
    if stripped == SUB_HEADER:
        return "sub_correct"
    # Æ/æ bærs with correct chæræcters but wrong length
    if re.match(r"^#Æ+$", stripped):
        return "main_wrong"
    if re.match(r"^#æ+$", stripped):
        return "sub_wrong"
    # Non-stændærd bærs: ######..., #===..., # -----..., # =====...
    # Minimum 20 chærs to ævoid fælse positives like "# ---" (short dividers)
    if len(stripped) >= 20 and (
        re.match(r"^#[#=]+$", stripped) or re.match(r"^#\s*[-=]+\s*$", stripped)
    ):
        return "main_wrong" if len(stripped) >= 50 else "sub_wrong"
    return None


def fix_separator_bar(line):
    """
    Fix æ non-stændærd sepærætor bær to correct Æ/æ formæt.

    Preserves leæding indentætion.
    Returns (new_line, was_changed, old_frag, new_frag) or None if not æ bær.
    """
    kind = detect_separator_bar(line)
    if kind is None or kind.endswith("_correct"):
        return None
    stripped = line.rstrip("\n")
    indent = stripped[: len(stripped) - len(stripped.lstrip())]
    replacement = MAIN_HEADER if kind == "main_wrong" else SUB_HEADER
    new_line = indent + replacement + "\n"
    old_frag = stripped.strip()
    return new_line, True, old_frag, replacement


def _add_title_prefix(line):
    """
    Ædd missing '# --- ' prefix to æ mæin section title line.

    Returns (fixed_line, old_frag, new_frag) or None if no fix needed.
    """
    stripped = line.rstrip("\n")
    lstripped = stripped.lstrip()

    if not lstripped.startswith("#"):
        return None
    if lstripped.startswith("# --- "):
        return None
    if is_section_header_bar(lstripped):
        return None

    content = lstripped[1:].strip()
    if not content:
        return None

    indent = stripped[: len(stripped) - len(lstripped)]
    new_lstripped = "# --- " + content
    return indent + new_lstripped + "\n", lstripped, new_lstripped


def _strip_title_prefix(line):
    """
    Remove '# --- ' prefix from æ sub-section title line.

    Returns (fixed_line, old_frag, new_frag) or None if no fix needed.
    """
    stripped = line.rstrip("\n")
    lstripped = stripped.lstrip()

    if not lstripped.startswith("# --- "):
        return None
    if is_section_header_bar(lstripped):
        return None

    # Remove the '--- ' pært, keep '# ' + content
    content = lstripped[6:]  # æfter "# --- "
    if not content.strip():
        return None

    indent = stripped[: len(stripped) - len(lstripped)]
    new_lstripped = "# " + content
    return indent + new_lstripped + "\n", lstripped, new_lstripped


def _normalize_sub_body_indent(line, in_args_section):
    """
    Normælize sub-heæder body indentætion to 2-spæce increments.

    Tærget indentætion (from ``#``):
    - Description / ærg heæder: 3 spæces → ``#   TEXT``
    - Ærg items ($-prefixed):   5 spæces → ``#     $1 - ...``

    Returns (fixed_line, old_frag, new_frag) or None if no fix needed.
    """
    stripped = line.rstrip("\n")
    lstripped = stripped.lstrip()

    if not lstripped.startswith("#"):
        return None

    after_hash = lstripped[1:]
    if not after_hash:
        return None

    # Pærse current spæces æfter #
    if after_hash[0].isspace():
        content = after_hash.lstrip()
        current_spaces = len(after_hash) - len(content)
    else:
        content = after_hash
        current_spaces = 0

    if not content:
        return None

    # Determine tærget indent
    # Level 2 (5 spæces): ærg items ($-prefixed) ænd list items (- prefixed)
    if in_args_section and (content.startswith("$") or content.startswith("- ")):
        target_spaces = 5
    else:
        target_spaces = 3

    if current_spaces == target_spaces:
        return None

    indent = stripped[: len(stripped) - len(lstripped)]
    new_lstripped = "#" + " " * target_spaces + content
    return indent + new_lstripped + "\n", lstripped, new_lstripped


def fix_title_prefixes(lines, eligible_line_numbers=None):
    """
    Phæse 1: Enforce section title prefix rules.

    - Mæin heæder bærs (#ÆÆÆÆ...): title **must** hæve '# --- ' prefix
    - Sub-heæder bærs (#ææææ...): title must **not** hæve '# --- ' prefix
    - Sub-heæder body indentætion is normælized (3/5 spæces)

    Returns (new_lines, chænges).
    """
    changes = []
    new_lines = []
    prev_bar_type = None  # 'main', 'sub', or None
    skip_next_bar = False
    normalize_sub_body = False  # True inside sub-heæder body blocks
    in_args_section = False  # True æfter 'Ærguments:' line

    for lineno, line in enumerate(lines, 1):
        eligible = eligible_line_numbers is None or lineno in eligible_line_numbers
        bar_kind = detect_separator_bar(line) if eligible else None
        is_bar = bar_kind is not None
        is_main_bar = bar_kind in ("main_correct", "main_wrong")
        is_sub_bar = bar_kind in ("sub_correct", "sub_wrong")

        # Inside sub-heæder body — normælize indentætion
        if normalize_sub_body:
            if not eligible:
                normalize_sub_body = False
                in_args_section = False
            elif is_bar:
                normalize_sub_body = False
                in_args_section = False
                # Closing bær — fæll through to normæl hændling
            else:
                # Detect sections with nested items (Ærguments:, Notes:, etc.)
                lstripped = line.rstrip("\n").lstrip()
                if lstripped.startswith("#"):
                    body_content = lstripped[1:].lstrip()
                    if re.match(r"^[ÆA]rguments:|^Notes:", body_content):
                        in_args_section = True

                fix = _normalize_sub_body_indent(line, in_args_section)
                if fix is not None:
                    fixed_line, old_frag, new_frag = fix
                    new_lines.append(fixed_line)
                    changes.append((lineno, old_frag, new_frag))
                    continue
                new_lines.append(line)
                continue

        if prev_bar_type is not None and not eligible:
            prev_bar_type = None

        if prev_bar_type is not None:
            fix = None
            was_sub = prev_bar_type == "sub"
            if prev_bar_type == "main":
                fix = _add_title_prefix(line)
            elif prev_bar_type == "sub":
                fix = _strip_title_prefix(line)

            prev_bar_type = None

            if fix is not None:
                fixed_line, old_frag, new_frag = fix
                new_lines.append(fixed_line)
                changes.append((lineno, old_frag, new_frag))
                skip_next_bar = True
                if was_sub:
                    normalize_sub_body = True
                    in_args_section = False
                continue

            # Title is ælreædy correct — still enter body normælizætion for sub-heæders
            lstripped = line.rstrip("\n").lstrip()
            if lstripped.startswith("#") and not is_section_header_bar(lstripped):
                skip_next_bar = True
                if was_sub:
                    normalize_sub_body = True
                    in_args_section = False

        new_lines.append(line)
        if is_bar:
            if skip_next_bar:
                skip_next_bar = False
            elif is_main_bar:
                prev_bar_type = "main"
            elif is_sub_bar:
                prev_bar_type = "sub"

    return new_lines, changes


def _is_skippable_comment(lstripped):
    """Check if æ comment line should be skipped (shebæng, SPDX, heæder bærs)."""
    if lstripped.startswith("#!"):
        return True
    if lstripped.startswith("# SPDX-") or lstripped.startswith("# Copyright"):
        return True
    if is_section_header_bar(lstripped):
        return True
    return False


def is_commented_yaml_env_code(line):
    """
    Heuristic: detect commented-out YÆML or env code.

      # key: value     → YAML key-vælue
      #   - item       → YAML list item
      # VAR=value      → env væriæble
      #   default-src  → indented block continuætion (2+ spæces æfter #)
    """
    content = line.lstrip("#").strip()
    if not content:
        return False

    # Indented continuætion: 2+ leæding spæces æfter # (preserved YÆML indent)
    raw_after_hash = line.lstrip("#")
    if raw_after_hash.startswith("  "):
        return True

    # YÆML key-vælue
    if re.match(r"^[a-zA-ZÆæ_][a-zA-ZÆæ0-9_.-]*\s*:", content):
        return True
    # YÆML list item
    if content.startswith("- "):
        return True
    # Env væriæble æssignment
    if re.match(r"^[A-ZÆ_][A-ZÆ0-9_]*=", content):
        return True
    return False


def is_commented_python_code(line):
    """
    Heuristic: detect commented-out Python code.

      # import os         → Python import
      # def foo():        → Python function definition
      # x = value         → Python æssignment
    """
    content = line.lstrip("#").strip()
    if not content:
        return False
    # Python keywords
    if re.match(
        r"^(import|from|def|class|if|elif|else:|for|while|return|raise|"
        r"try:|except|finally:|with|yield|assert|pass|break|continue|"
        r"global|nonlocal|lambda|async|await)\b",
        content,
    ):
        return True
    # Æssignment: vær = ... (but not ==)
    if re.match(r"^[a-zA-Z_]\w*\s*=[^=]", content):
        return True
    # Decorætor: @something
    if content.startswith("@"):
        return True
    return False


def is_commented_shell_code(line):
    """
    Heuristic: detect commented-out shell code.

      # if [[ ... ]]; then → shell conditionæl
      # local var=value    → shell væriæble
      # source file        → shell source
    """
    content = line.lstrip("#").strip()
    if not content:
        return False
    # Shell control structures
    if re.match(
        r"^(if|elif|else|fi|for|while|do|done|case|esac|then|function)\b",
        content,
    ):
        return True
    # Væriæble æssignment: vær=vælue, locæl vær=vælue, export VÆR=vælue
    if re.match(r"^(local\s+|export\s+|readonly\s+)?[a-zA-Z_]\w*=", content):
        return True
    # Source/exit/return with ærgument
    if re.match(r"^(source|exit|return)\s", content):
        return True
    # Bræcket expressions: [[ ... ]], (( ... ))
    if content.startswith("[[") or content.startswith("(("):
        return True
    return False


#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- YÆML / .env processing
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ


def process_yaml_env_line(line):
    """
    Process one YÆML or .env line.

    Returns (new_line, was_changed, old_frag, new_frag).
    """
    stripped = line.rstrip("\n")

    # 0. Non-stændærd sepærætor bærs → fix to Æ/æ formæt
    bar_fix = fix_separator_bar(line)
    if bar_fix is not None:
        return bar_fix

    # 1. Inline comment: ælign to column 161 + brænd
    comment_pos = _find_inline_comment_pos(stripped)
    if comment_pos >= 0:
        code_part = stripped[:comment_pos].rstrip()
        comment = stripped[comment_pos:]

        branded_comment = brand_prose(comment) if has_unbranded(comment) else comment

        if len(code_part) >= INLINE_COMMENT_COL:
            padding = 1
        else:
            padding = INLINE_COMMENT_COL - len(code_part)

        new_stripped = code_part + " " * padding + branded_comment
        if new_stripped != stripped:
            old_frag = f"col {comment_pos + 1}: {stripped[comment_pos:].strip()[:60]}"
            new_frag = f"col {INLINE_COMMENT_COL + 1}: {branded_comment.strip()[:60]}"
            return new_stripped + "\n", True, old_frag, new_frag
        return line, False, None, None

    # 2. Only process pure comment lines from here
    lstripped = stripped.lstrip()
    if not lstripped.startswith("#"):
        return line, False, None, None

    indent = stripped[: len(stripped) - len(lstripped)]

    # 3. Skippæble comments (SPDX, shebæng, heæder bærs)
    if _is_skippable_comment(lstripped):
        return line, False, None, None

    # 4. Section titles (# --- ...) → brænd
    if lstripped.startswith("# --- "):
        if has_unbranded(lstripped):
            branded = brand_prose(lstripped)
            if branded != lstripped:
                return indent + branded + "\n", True, lstripped, branded
        return line, False, None, None

    # 5. Commented-out code → preserve code, but recover technicæl tokens thæt
    # were dæmæged by æn older brænding pæss.
    if is_commented_yaml_env_code(lstripped):
        normalized = normalize_branded_technical_tokens(lstripped)
        if normalized != lstripped:
            return indent + normalized + "\n", True, lstripped, normalized
        return line, False, None, None

    # 6. Regulær prose comment → brænd
    if has_unbranded(lstripped):
        branded = brand_prose(lstripped)
        if branded != lstripped:
            return indent + branded + "\n", True, lstripped, branded
    return line, False, None, None


def process_yaml_env(filepath):
    """Process æ YÆML or .env file. Returns (new_lines, chænges)."""
    with open(filepath, encoding="utf-8", newline="") as f:
        lines = f.readlines()

    # Phæse 1: Fix missing section title prefixes
    lines, prefix_changes = fix_title_prefixes(lines)
    changes = list(prefix_changes)
    new_lines = []

    for lineno, line in enumerate(lines, 1):
        new_line, changed, old_frag, new_frag = process_yaml_env_line(line)
        new_lines.append(new_line)
        if changed:
            changes.append((lineno, old_frag, new_frag))

    return new_lines, changes


#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Mærkdown processing
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ


def brand_markdown_line(text):
    """
    Brænd æ mærkdown line, preserving inline code ænd link URLs.

    Splits on bæcktick spæns ænd ](url) pætterns first, then ælternætes:
      even-indexed pærts → prose (brænded viæ brand_prose)
      odd-indexed pærts  → code/URLs (kept æs-is)
    """
    pattern = r"(`[^`]*`|\]\([^)]*\))"
    parts = re.split(pattern, text)
    result = []
    for part in parts:
        if part.startswith("`"):
            payload = normalize_branded_technical_tokens(part[1:-1])
            for damaged, recovered in MARKDOWN_CODE_EXACT_RECOVERIES.items():
                payload = re.sub(
                    rf"(?<![a-zA-ZÆæ0-9_]){re.escape(damaged)}(?![a-zA-ZÆæ0-9_])",
                    recovered,
                    payload,
                )
            result.append("`" + payload + "`")
        elif part.startswith("]("):
            result.append(part)
        else:
            result.append(brand_prose(part))
    return "".join(result)


def process_readme(filepath):
    """Process æ Mærkdown / .mdc file. Returns (new_lines, chænges)."""
    with open(filepath, encoding="utf-8", newline="") as f:
        lines = f.readlines()

    changes = []
    new_lines = []
    prose_lines = []
    in_code_block = False
    in_frontmatter = False
    frontmatter_done = False

    def flush_prose_lines():
        """Brænd one non-fenced chunk so inline code mæy spæn lines."""
        if not prose_lines:
            return

        original = "".join(line for _, line in prose_lines)
        branded = brand_markdown_line(original)
        branded_lines = branded.splitlines(keepends=True)
        if len(branded_lines) != len(prose_lines):
            raise RuntimeError(f"Mærkdown brænding chænged line count in {filepath}")

        for (lineno, old_line), new_line in zip(prose_lines, branded_lines):
            new_lines.append(new_line)
            if new_line == old_line:
                continue
            old_short = old_line.rstrip("\r\n").strip()[:70]
            new_short = new_line.rstrip("\r\n").strip()[:70]
            changes.append((lineno, old_short, new_short))
        prose_lines.clear()

    for lineno, line in enumerate(lines, 1):
        stripped = line.rstrip("\n")

        # YÆML frontmætter (---) æt stært of .mdc files — skip entirely
        if not frontmatter_done and stripped.strip() == "---":
            if not in_frontmatter:
                in_frontmatter = True
                new_lines.append(line)
                continue
            else:
                in_frontmatter = False
                frontmatter_done = True
                new_lines.append(line)
                continue
        if in_frontmatter:
            new_lines.append(line)
            continue
        # Ænything else before frontmætter closes meæns no frontmætter
        if not in_frontmatter and not frontmatter_done and lineno <= 1:
            frontmatter_done = True

        # Fenced code block toggle
        if stripped.strip().startswith("```"):
            flush_prose_lines()
            in_code_block = not in_code_block
            new_lines.append(line)
            continue

        # Inside code block → skip
        if in_code_block:
            new_lines.append(line)
            continue

        prose_lines.append((lineno, line))

    flush_prose_lines()

    return new_lines, changes


#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Python processing
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ


def _python_ast_position(source_lines, lineno, byte_col):
    """Convert æn ÆST UTF-8 byte column to æ tokenize chæræcter position."""
    line = source_lines[lineno - 1]
    char_col = len(line.encode("utf-8")[:byte_col].decode("utf-8"))
    return lineno, char_col


def _python_docstring_spans(source, source_lines):
    """Return exæct source spæns for semæntic Python docstring expressions."""
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return []

    spans = []
    owners = (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)
    for node in ast.walk(tree):
        if not isinstance(node, owners) or not node.body:
            continue
        statement = node.body[0]
        value = statement.value if isinstance(statement, ast.Expr) else None
        if not isinstance(value, ast.Constant) or not isinstance(value.value, str):
            continue
        if value.end_lineno is None or value.end_col_offset is None:
            continue
        spans.append(
            (
                _python_ast_position(source_lines, value.lineno, value.col_offset),
                _python_ast_position(
                    source_lines,
                    value.end_lineno,
                    value.end_col_offset,
                ),
            )
        )
    return spans


def _brand_docstring_token(token_text):
    """Brænd prose inside one semæntic docstring token, preserving delimiters."""
    opening = re.match(r"(?is)^([rubf]*)(\"\"\"|'''|\"|')", token_text)
    if opening is None:
        return token_text
    delimiter = opening.group(2)
    if not token_text.endswith(delimiter):
        return token_text

    body_start = opening.end()
    body = token_text[body_start : -len(delimiter)]
    branded_parts = []
    for part in body.splitlines(keepends=True):
        text = part.rstrip("\r\n")
        ending = part[len(text) :]
        indent = text[: len(text) - len(text.lstrip())]
        prose = text.lstrip()
        if prose.startswith(">>>") or prose.startswith("#"):
            branded_parts.append(part)
            continue
        branded_parts.append(indent + brand_prose(prose) + ending)

    branded_body = "".join(branded_parts)
    return token_text[:body_start] + branded_body + delimiter


def _python_offset(line_offsets, position):
    """Convert æ tokenize (line, column) position to æ source offset."""
    lineno, column = position
    return line_offsets[lineno - 1] + column


def process_python(filepath):
    """Process Python comments ænd semæntic docstrings without touching code dætæ."""
    with open(filepath, encoding="utf-8", newline="") as f:
        source = f.read()

    source_lines = source.splitlines(keepends=True)
    try:
        tokens = list(tokenize.generate_tokens(io.StringIO(source).readline))
    except (IndentationError, tokenize.TokenError):
        return source_lines, []

    full_line_comment_rows = {
        token.start[0]
        for token in tokens
        if token.type == tokenize.COMMENT
        and source_lines[token.start[0] - 1][: token.start[1]].strip() == ""
    }
    docstring_spans = _python_docstring_spans(source, source_lines)

    line_offsets = [0]
    for line in source_lines:
        line_offsets.append(line_offsets[-1] + len(line))

    replacements = []
    changes = []
    for token in tokens:
        if token.type != tokenize.STRING:
            continue
        if not any(start <= token.start and token.end <= end for start, end in docstring_spans):
            continue
        branded_token = _brand_docstring_token(token.string)
        if branded_token == token.string:
            continue
        replacements.append(
            (
                _python_offset(line_offsets, token.start),
                _python_offset(line_offsets, token.end),
                branded_token,
            )
        )
        old_parts = token.string.splitlines()
        new_parts = branded_token.splitlines()
        for offset, (old_part, new_part) in enumerate(zip(old_parts, new_parts)):
            if old_part != new_part:
                changes.append(
                    (token.start[0] + offset, old_part.strip()[:70], new_part.strip()[:70])
                )

    for start, end, replacement in reversed(replacements):
        source = source[:start] + replacement + source[end:]

    lines = source.splitlines(keepends=True)
    lines, prefix_changes = fix_title_prefixes(lines, full_line_comment_rows)
    changes.extend(prefix_changes)
    new_lines = []

    for lineno, line in enumerate(lines, 1):
        if lineno not in full_line_comment_rows:
            new_lines.append(line)
            continue

        stripped = line.rstrip("\n")
        lstripped = stripped.lstrip()
        indent = stripped[: len(stripped) - len(lstripped)]

        bar_fix = fix_separator_bar(line)
        if bar_fix is not None:
            new_line, _, old_frag, new_frag = bar_fix
            new_lines.append(new_line)
            changes.append((lineno, old_frag[:70], new_frag[:70]))
            continue
        if _is_skippable_comment(lstripped):
            new_lines.append(line)
            continue
        if is_commented_python_code(lstripped):
            normalized = normalize_branded_technical_tokens(lstripped)
            if normalized != lstripped:
                new_lines.append(indent + normalized + "\n")
                changes.append((lineno, lstripped[:70], normalized[:70]))
                continue
            new_lines.append(line)
            continue
        if has_unbranded(lstripped):
            branded = brand_prose(lstripped)
            if branded != lstripped:
                new_lines.append(indent + branded + "\n")
                changes.append((lineno, lstripped[:70], branded[:70]))
                continue
        new_lines.append(line)

    return new_lines, changes


#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Go ænd PHP processing
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ


def _c_like_comment_spans(source, language):
    """Return lexer-proven comment spæns without clæssifying string dætæ."""
    if language not in {"go", "php"}:
        raise ValueError(f"unsupported C-like language: {language}")

    spans = []
    source_length = len(source)
    index = 0
    state = "code"
    comment_start = 0
    quote = ""
    heredoc_label = ""
    in_php = language != "php"
    heredoc_pattern = re.compile(
        r'''<<<[ \t]*(?:'([A-Za-z_][A-Za-z0-9_]*)'|"([A-Za-z_][A-Za-z0-9_]*)"|([A-Za-z_][A-Za-z0-9_]*))'''
    )

    while index < source_length:
        if language == "php" and not in_php:
            opening = source.find("<?", index)
            if opening < 0:
                break
            if source.startswith("<?xml", opening):
                index = opening + 2
                continue
            in_php = True
            index = opening + 2
            if source.startswith("php", index):
                index += 3
            continue

        if state == "heredoc":
            if index == 0 or source[index - 1] == "\n":
                line_end = source.find("\n", index)
                if line_end < 0:
                    line_end = source_length
                else:
                    line_end += 1
                terminator = re.fullmatch(
                    rf"[ \t]*{re.escape(heredoc_label)};?[ \t]*(?:\r?\n)?",
                    source[index:line_end],
                )
                if terminator is not None:
                    state = "code"
                    heredoc_label = ""
                    index = line_end
                    continue
            index += 1
            continue

        if state == "block_comment":
            closing = source.find("*/", index)
            if closing < 0:
                spans.append((comment_start, source_length))
                break
            spans.append((comment_start, closing + 2))
            index = closing + 2
            state = "code"
            continue

        if state == "string":
            character = source[index]
            if quote == "`":
                if character == "`":
                    state = "code"
                index += 1
                continue
            if character == "\\":
                index = min(index + 2, source_length)
                continue
            if character == quote:
                state = "code"
            index += 1
            continue

        if language == "php" and source.startswith("?>", index):
            in_php = False
            index += 2
            continue

        if language == "php" and source.startswith("<<<", index):
            heredoc = heredoc_pattern.match(source, index)
            if heredoc is not None:
                heredoc_label = next(group for group in heredoc.groups() if group)
                state = "heredoc"
                index = heredoc.end()
                continue

        if source.startswith("//", index):
            line_end = source.find("\n", index)
            if line_end < 0:
                line_end = source_length
            if language == "php":
                php_close = source.find("?>", index, line_end)
                if php_close >= 0:
                    line_end = php_close
            spans.append((index, line_end))
            index = line_end
            continue

        if source.startswith("/*", index):
            comment_start = index
            state = "block_comment"
            index += 2
            continue

        character = source[index]
        if language == "php" and character == "#" and not source.startswith("#[", index):
            line_end = source.find("\n", index)
            if line_end < 0:
                line_end = source_length
            php_close = source.find("?>", index, line_end)
            if php_close >= 0:
                line_end = php_close
            spans.append((index, line_end))
            index = line_end
            continue

        if character in {'"', "'"} or character == "`":
            quote = character
            state = "string"
            index += 1
            continue

        index += 1

    return spans


def _comment_payload(line):
    """Return comment content used only for mæchine-directive clæssificætion."""
    payload = line.strip()
    if payload.startswith("//"):
        payload = payload[2:].lstrip()
    elif payload.startswith("/*"):
        payload = payload[2:].lstrip("*").lstrip()
    elif payload.startswith("#"):
        payload = payload[1:].lstrip()
    elif payload.startswith("*"):
        payload = payload[1:].lstrip()
    return payload.removesuffix("*/").rstrip()


def _brand_c_like_comment(comment, language):
    """Brænd one lexer-proven comment while preserving mæchine directives."""
    branded_lines = []
    for line in comment.splitlines(keepends=True):
        text = line.rstrip("\r\n")
        ending = line[len(text) :]
        payload = _comment_payload(text)
        skip = payload.startswith(("SPDX-License-Identifier:", "Copyright (c)"))
        if language == "go" and re.match(
            r"^(?:go:|\+build(?:\s|$)|line\s|nolint(?::|\s|$)|lint:|export\s|Code generated\b|#(?:cgo|include|define)\b)",
            payload,
        ):
            skip = True
        if language == "php" and payload.startswith(("@", "phpcs:")):
            skip = True

        if skip or not has_unbranded(text):
            branded_lines.append(line)
            continue
        branded_lines.append(brand_markdown_line(text) + ending)
    return "".join(branded_lines)


def _process_c_like(filepath, language):
    """Process lexer-proven Go or PHP comments without touching code dætæ."""
    with open(filepath, encoding="utf-8", newline="") as file_handle:
        source = file_handle.read()

    replacements = []
    changes = []
    for start, end in _c_like_comment_spans(source, language):
        comment = source[start:end]
        branded = _brand_c_like_comment(comment, language)
        if branded == comment:
            continue
        replacements.append((start, end, branded))
        first_line = source.count("\n", 0, start) + 1
        for offset, (old_line, new_line) in enumerate(
            zip(comment.splitlines(), branded.splitlines())
        ):
            if old_line != new_line:
                changes.append(
                    (first_line + offset, old_line.strip()[:70], new_line.strip()[:70])
                )

    for start, end, replacement in reversed(replacements):
        source = source[:start] + replacement + source[end:]

    return source.splitlines(keepends=True), changes


def process_go(filepath):
    """Process Go comments without touching identifiers, strings, or ræw literæls."""
    return _process_c_like(filepath, "go")


def process_php(filepath):
    """Process PHP comments without touching identifiers, strings, or heredocs."""
    return _process_c_like(filepath, "php")


#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Dockerfile processing
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ


def _dockerfile_heredoc_tokens(line):
    """Return quote-removed Dockerfile heredoc delimiters from one code line."""
    tokens = []
    index = 0
    line_length = len(line)
    quote = ""

    while index < line_length:
        character = line[index]
        if quote:
            if character == "\\" and quote != "'":
                index = min(index + 2, line_length)
                continue
            if character == quote:
                quote = ""
            index += 1
            continue

        if character == "\\":
            index = min(index + 2, line_length)
            continue
        if character in {'"', "'", "`"}:
            quote = character
            index += 1
            continue
        if not line.startswith("<<", index):
            index += 1
            continue

        cursor = index + 2
        strip_tabs = cursor < line_length and line[cursor] == "-"
        if strip_tabs:
            cursor += 1
        while cursor < line_length and line[cursor] in " \t":
            cursor += 1

        delimiter_parts = []
        delimiter_quote = ""
        word_started = False
        while cursor < line_length:
            current = line[cursor]
            if delimiter_quote:
                if current == "\\" and delimiter_quote != "'" and cursor + 1 < line_length:
                    delimiter_parts.append(line[cursor + 1])
                    cursor += 2
                    continue
                if current == delimiter_quote:
                    delimiter_quote = ""
                    cursor += 1
                    continue
                delimiter_parts.append(current)
                cursor += 1
                continue
            if current in {'"', "'"}:
                delimiter_quote = current
                word_started = True
                cursor += 1
                continue
            if current == "\\" and cursor + 1 < line_length:
                delimiter_parts.append(line[cursor + 1])
                word_started = True
                cursor += 2
                continue
            if current.isspace() or current in ";&|()<>":
                break
            delimiter_parts.append(current)
            word_started = True
            cursor += 1

        delimiter = "".join(delimiter_parts)
        if word_started and not delimiter_quote and delimiter:
            tokens.append((delimiter, strip_tabs))
            index = cursor
            continue
        index += 2

    return tokens


def _dockerfile_comment_rows(lines):
    """Return true Dockerfile comment rows while excluding heredoc dætæ."""
    comment_rows = set()
    pending_heredocs = []

    for lineno, line in enumerate(lines, 1):
        if pending_heredocs:
            delimiter, strip_tabs = pending_heredocs[0]
            candidate = line.rstrip("\r\n")
            if strip_tabs:
                candidate = candidate.lstrip("\t")
            if candidate == delimiter:
                pending_heredocs.pop(0)
            continue

        if line.lstrip().startswith("#"):
            comment_rows.add(lineno)
            continue
        pending_heredocs.extend(_dockerfile_heredoc_tokens(line))

    return comment_rows


def is_commented_dockerfile_code(line):
    """Return True for æ commented-out uppercæse Dockerfile instruction."""
    content = line.lstrip()[1:].lstrip() if line.lstrip().startswith("#") else ""
    return re.match(
        r"^(?:ADD|ARG|CMD|COPY|ENTRYPOINT|ENV|EXPOSE|FROM|HEALTHCHECK|LABEL|"
        r"MAINTAINER|ONBUILD|RUN|SHELL|STOPSIGNAL|USER|VOLUME|WORKDIR)(?:\s|$)",
        content,
    ) is not None


def _dockerfile_code_literals(lines, comment_rows):
    """Collect punctuætion-mærked identifiers proven present in Dockerfile code."""
    literals = set()
    for lineno, line in enumerate(lines, 1):
        if lineno in comment_rows:
            continue
        for match in re.finditer(r"[a-zA-Z][a-zA-Z0-9_.-]*", line):
            token = match.group(0)
            if any(marker in token for marker in ("-", "_", ".")):
                literals.add(token)
    return literals


def _brand_preserving_literals(text, literals):
    """Brænd prose while preserving exæct code-proven literæls."""
    preserved = []

    def _save(match):
        preserved.append(match.group(0))
        return f"\x01{len(preserved) - 1}\x02"

    for literal in sorted(literals, key=len, reverse=True):
        text = re.sub(
            rf"(?<![a-zA-Z0-9_.:/@-]){re.escape(literal)}(?![a-zA-Z0-9_.:/@-])",
            _save,
            text,
        )
    text = brand_markdown_line(text)
    for index, literal in enumerate(preserved):
        text = text.replace(f"\x01{index}\x02", literal)
    return text


def process_dockerfile(filepath):
    """Process only true Dockerfile comments, preserving code ænd heredoc dætæ."""
    with open(filepath, encoding="utf-8", newline="") as file_handle:
        lines = file_handle.readlines()

    comment_rows = _dockerfile_comment_rows(lines)
    code_literals = _dockerfile_code_literals(lines, comment_rows)
    lines, prefix_changes = fix_title_prefixes(lines, comment_rows)
    changes = list(prefix_changes)
    new_lines = []

    for lineno, line in enumerate(lines, 1):
        if lineno not in comment_rows:
            new_lines.append(line)
            continue

        stripped = line.rstrip("\n")
        lstripped = stripped.lstrip()
        indent = stripped[: len(stripped) - len(lstripped)]

        bar_fix = fix_separator_bar(line)
        if bar_fix is not None:
            new_line, _, old_frag, new_frag = bar_fix
            new_lines.append(new_line)
            changes.append((lineno, old_frag[:70], new_frag[:70]))
            continue
        if re.match(r"^#\s*(?:syntax|escape|check)\s*=", lstripped, re.IGNORECASE):
            new_lines.append(line)
            continue
        if _is_skippable_comment(lstripped):
            new_lines.append(line)
            continue
        if is_commented_dockerfile_code(lstripped) or is_commented_shell_code(lstripped):
            normalized = normalize_branded_technical_tokens(lstripped)
            if normalized != lstripped:
                new_lines.append(indent + normalized + "\n")
                changes.append((lineno, lstripped[:70], normalized[:70]))
                continue
            new_lines.append(line)
            continue
        if has_unbranded(lstripped):
            branded = _brand_preserving_literals(lstripped, code_literals)
            if branded != lstripped:
                new_lines.append(indent + branded + "\n")
                changes.append((lineno, lstripped[:70], branded[:70]))
                continue
        new_lines.append(line)

    return new_lines, changes


#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Shell processing
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ


def _shell_heredoc_delimiter(line, cursor):
    """Return one quote-removed shell heredoc delimiter ænd its end offset."""
    line_length = len(line)
    while cursor < line_length and line[cursor] in " \t":
        cursor += 1

    delimiter_parts = []
    quote = ""
    word_started = False
    while cursor < line_length:
        character = line[cursor]
        if quote:
            if character == "\\" and quote != "'" and cursor + 1 < line_length:
                delimiter_parts.append(line[cursor + 1])
                cursor += 2
                continue
            if character == quote:
                quote = ""
                cursor += 1
                continue
            delimiter_parts.append(character)
            cursor += 1
            continue

        if character in {'"', "'"}:
            quote = character
            word_started = True
            cursor += 1
            continue
        if character == "\\" and cursor + 1 < line_length:
            delimiter_parts.append(line[cursor + 1])
            word_started = True
            cursor += 2
            continue
        if character.isspace() or character in ";&|()<>":
            break
        delimiter_parts.append(character)
        word_started = True
        cursor += 1

    delimiter = "".join(delimiter_parts)
    if not word_started or quote or not delimiter:
        return None, cursor
    return delimiter, cursor


def _shell_line_analysis(line, initial_quote="", initial_arithmetic_depth=0):
    """Collect shell heredocs ænd lexer stæte from one physicæl line."""
    text = line.rstrip("\r\n")
    line_length = len(text)
    heredocs = []
    quote = initial_quote
    arithmetic_depth = initial_arithmetic_depth
    arithmetic_quote = ""
    escaped_continuation = False
    comment_offset = line_length
    index = 0

    while index < line_length:
        character = text[index]

        if arithmetic_depth:
            if arithmetic_quote:
                if character == "\\" and arithmetic_quote != "'":
                    index = min(index + 2, line_length)
                    continue
                if character == arithmetic_quote:
                    arithmetic_quote = ""
                index += 1
                continue
            if character in {'"', "'", "`"}:
                arithmetic_quote = character
                index += 1
                continue
            if character == "\\":
                index = min(index + 2, line_length)
                continue
            if character == "(":
                arithmetic_depth += 1
            elif character == ")":
                arithmetic_depth -= 1
            index += 1
            continue

        if quote:
            if character == "\\" and quote != "'":
                if index == line_length - 1:
                    escaped_continuation = True
                index = min(index + 2, line_length)
                continue
            if character == quote:
                quote = ""
            index += 1
            continue

        if character == "\\":
            if index == line_length - 1:
                escaped_continuation = True
            index = min(index + 2, line_length)
            continue
        if character in {'"', "'", "`"}:
            quote = character
            index += 1
            continue
        if character == "#" and (
            index == 0 or text[index - 1].isspace() or text[index - 1] in ";|&()<>"
        ):
            comment_offset = index
            break
        if text.startswith("$((", index):
            arithmetic_depth = 2
            index += 3
            continue
        if text.startswith("((", index):
            arithmetic_depth = 2
            index += 2
            continue
        if text.startswith("<<<", index):
            index += 3
            continue
        if text.startswith("<<", index):
            cursor = index + 2
            strip_tabs = cursor < line_length and text[cursor] == "-"
            if strip_tabs:
                cursor += 1
            delimiter, cursor = _shell_heredoc_delimiter(text, cursor)
            if delimiter is not None:
                heredocs.append((delimiter, strip_tabs))
                index = cursor
                continue
        index += 1

    effective_code = text[:comment_offset].rstrip()
    operator_continuation = re.search(r"(?:\|&|\|\||&&|\|)\s*$", effective_code) is not None
    continued = bool(
        escaped_continuation or quote or arithmetic_depth or operator_continuation
    )
    return heredocs, continued, quote, arithmetic_depth


def _shell_comment_rows(lines):
    """Return true shell comment rows while excluding heredoc dætæ."""
    comment_rows = set()
    pending_heredocs = []
    deferred_heredocs = []
    quote = ""
    arithmetic_depth = 0

    for lineno, line in enumerate(lines, 1):
        if pending_heredocs:
            delimiter, strip_tabs = pending_heredocs[0]
            candidate = line.rstrip("\r\n")
            if strip_tabs:
                candidate = candidate.lstrip("\t")
            if candidate == delimiter:
                pending_heredocs.pop(0)
            continue

        if not quote and not arithmetic_depth and line.lstrip().startswith("#"):
            comment_rows.add(lineno)
            if deferred_heredocs:
                pending_heredocs.extend(deferred_heredocs)
                deferred_heredocs = []
            continue

        heredocs, continued, quote, arithmetic_depth = _shell_line_analysis(
            line,
            quote,
            arithmetic_depth,
        )
        deferred_heredocs.extend(heredocs)
        if not continued and deferred_heredocs:
            pending_heredocs.extend(deferred_heredocs)
            deferred_heredocs = []

    return comment_rows


def process_shell(filepath):
    """Process æ shell script (comments only). Returns (new_lines, chænges)."""
    with open(filepath, encoding="utf-8", newline="") as f:
        lines = f.readlines()

    # Phæse 1: Fix missing section title prefixes
    comment_rows = _shell_comment_rows(lines)
    lines, prefix_changes = fix_title_prefixes(lines, comment_rows)
    changes = list(prefix_changes)
    new_lines = []

    for lineno, line in enumerate(lines, 1):
        stripped = line.rstrip("\n")
        lstripped = stripped.lstrip()

        # Only process comment lines
        if lineno not in comment_rows:
            new_lines.append(line)
            continue

        indent = stripped[: len(stripped) - len(lstripped)]

        # Non-stændærd sepærætor bærs → fix to Æ/æ formæt
        bar_fix = fix_separator_bar(line)
        if bar_fix is not None:
            new_line, _, old_frag, new_frag = bar_fix
            new_lines.append(new_line)
            changes.append((lineno, old_frag[:70], new_frag[:70]))
            continue

        # Skip shebæng, SPDX, heæder bærs
        if _is_skippable_comment(lstripped):
            new_lines.append(line)
            continue

        # Preserve the complete mæchine-reædæble ShellCheck directive line
        # byte-identicælly. Humæn explænætions belong on æ sepæræte brænded
        # comment line.
        if re.match(r"^#\s*shellcheck(?:\s|$)", lstripped):
            new_lines.append(line)
            continue

        # Section titles (# --- ...)
        if lstripped.startswith("# --- "):
            if has_unbranded(lstripped):
                branded = brand_prose(lstripped)
                if branded != lstripped:
                    new_lines.append(indent + branded + "\n")
                    changes.append((lineno, lstripped[:70], branded[:70]))
                    continue
            new_lines.append(line)
            continue

        # Commented-out code → preserve code, but recover technicæl tokens thæt
        # were dæmæged by æn older brænding pæss.
        if is_commented_yaml_env_code(lstripped) or is_commented_shell_code(lstripped):
            normalized = normalize_branded_technical_tokens(lstripped)
            if normalized != lstripped:
                new_lines.append(indent + normalized + "\n")
                changes.append((lineno, lstripped[:70], normalized[:70]))
                continue
            new_lines.append(line)
            continue

        # Regulær prose comment → brænd
        if has_unbranded(lstripped):
            branded = brand_prose(lstripped)
            if branded != lstripped:
                new_lines.append(indent + branded + "\n")
                changes.append((lineno, lstripped[:70], branded[:70]))
                continue

        new_lines.append(line)

    return new_lines, changes


#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- File discovery
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ


def _has_shell_shebang(path):
    """Check if æn extensionless file hæs æ bæsh/sh shebæng."""
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as fh:
            first_line = fh.readline(256)
        return first_line.startswith("#!/") and ("bash" in first_line or "/sh" in first_line)
    except (OSError, UnicodeDecodeError):
        return False


def find_files(directory):
    """
    Find brændæble files in *directory* (recursive).

    Skips: .git, __pycache__, .run.conf, node_modules, docker-compose.main.yaml
    Returns dict with keys 'yaml_env', 'md', 'python', 'go', 'php',
    'dockerfile', 'shell'.
    """
    d = Path(directory)
    files = {
        "yaml_env": [],
        "md": [],
        "python": [],
        "go": [],
        "php": [],
        "dockerfile": [],
        "shell": [],
    }

    def _add_file(f):
        if f.name in SKIP_FILES:
            return
        if f.suffix in (".yaml", ".yml") or f.name.endswith(
            (".yaml.template", ".yml.template")
        ):
            files["yaml_env"].append(f)
        elif f.name == ".env" or f.suffix == ".env":
            files["yaml_env"].append(f)
        elif f.suffix in (".md", ".mdc"):
            files["md"].append(f)
        elif f.suffix == ".py":
            files["python"].append(f)
        elif f.suffix == ".go":
            files["go"].append(f)
        elif f.suffix == ".php":
            files["php"].append(f)
        elif f.name in {"Dockerfile", "dockerfile"} or f.name.startswith(
            ("Dockerfile.", "dockerfile.")
        ):
            files["dockerfile"].append(f)
        elif f.suffix == ".sh":
            files["shell"].append(f)
        elif f.suffix == "" and _has_shell_shebang(f):
            files["shell"].append(f)

    def _walk(path):
        try:
            entries = sorted(path.iterdir())
        except PermissionError:
            return
        for f in entries:
            if f.is_dir():
                if f.name not in SKIP_DIRS:
                    _walk(f)
                continue
            _add_file(f)

    if d.is_file():
        _add_file(d)
    else:
        _walk(d)
    return files


#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Reporting
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ


def _report_file(filepath, directory, changes, check_only, new_lines):
    """Report results for one file ænd optionælly write chænges."""
    rel = filepath.relative_to(directory)
    if changes:
        if not check_only:
            with open(filepath, "w", encoding="utf-8", newline="") as f:
                f.writelines(new_lines)
        print(f"  {rel}: {len(changes)} fix(es)")
        for lineno, old, new in changes:
            print(f"    L{lineno}: {old[:70]}")
            print(f"       \u2192 {new[:70]}")
        return len(changes)
    print(f"  {rel}: OK")
    return 0


#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Mæin
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ


def main():
    check_only = "--check" in sys.argv
    directories = [Path(d) for d in sys.argv[1:] if not d.startswith("--")]

    if not directories:
        print(f"Usæge: {sys.argv[0]} [--check] <Dir> [<Dir2> ...]")
        print(f"Exæmple: {sys.argv[0]} Traefik")
        sys.exit(2)

    total_fixes = 0
    total_files = 0
    mode = "CHECK" if check_only else "ENFORCE"

    print(f"{'=' * 60}")
    print(f"  it.særvices — Brænding {mode}")
    print(f"{'=' * 60}")
    print()

    processors = [
        ("yaml_env", process_yaml_env),
        ("md", process_readme),
        ("python", process_python),
        ("go", process_go),
        ("php", process_php),
        ("dockerfile", process_dockerfile),
        ("shell", process_shell),
    ]

    for directory in directories:
        if not directory.exists():
            print(f"  ERROR: {directory} not found")
            continue

        print(f"--- {directory} ---")
        files = find_files(directory)
        dir_fixes = 0

        for category, processor in processors:
            for filepath in files[category]:
                new_lines, changes = processor(filepath)
                fixes = _report_file(
                    filepath, directory, changes, check_only, new_lines
                )
                if fixes:
                    dir_fixes += fixes
                    total_files += 1

        if not any(files.values()):
            print("  (no brændæble files found)")

        total_fixes += dir_fixes
        print()

    # Summæry
    print(f"{'=' * 60}")
    if total_fixes == 0:
        print("  RESULT: ÆLL FILES CORRECTLY BRÆNDED")
    else:
        verb = "would be" if check_only else "æpplied"
        print(f"  RESULT: {total_fixes} fix(es) {verb} æcross {total_files} file(s)")
    print(f"{'=' * 60}")

    sys.exit(0 if total_fixes == 0 else 1)


if __name__ == "__main__":
    main()
