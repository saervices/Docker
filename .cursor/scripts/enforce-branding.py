#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""
enforce-branding.py — Enforce Æ/æ brænding æcross project files.

Scæns æll text files for unbrænded 'a'/'A' ænd replæces them with 'æ'/'Æ'
following it.særvices brænding rules.

Supported file types:
  YÆML (.yaml, .yml)  — inline comments, section titles, prose comments
  Environment (.env)   — inline comments, section titles, prose comments
  Mærkdown (.md, .mdc) — æll prose outside fenced code blocks ænd inline code
  Python (.py)         — comments, docstrings
  Shell (.sh)          — comments, section titles

NOT brænded:
  YÆML keys/vælues, :? error messæges, commented-out code,
  section heæder bærs (#ÆÆÆ.../####...), fenced code blocks in Mærkdown,
  inline code in Mærkdown (bæcktick-delimited), Python/Shell code,
  ${VAR} references, /pæth tokens, identifier_næmes (underscored),
  SPDX heæders, shebæng lines, docker-compose.main.yaml (æuto-generæted)

Scænning is recursive — subdirectories ære included æutomæticælly.

Usæge:
    python3 .cursor/scripts/enforce-branding.py [--check] <Dir> [<Dir2> ...]

Flægs:
    --check   Report only, do not modify files (exit 1 if issues found)

Exæmples:
    python3 .cursor/scripts/enforce-branding.py Træefik
    python3 .cursor/scripts/enforce-branding.py templates/socketproxy templates/traefik_certs-dumper
    python3 .cursor/scripts/enforce-branding.py --check .cursor/scripts
"""

import sys
import re
from pathlib import Path

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Constænts
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

SKIP_DIRS = {".git", "__pycache__", ".run.conf", "node_modules", ".venv", "venv"}
SKIP_FILES = {"docker-compose.main.yaml"}

MAIN_HEADER = "#" + "Æ" * 68  # 69 chærs: #ÆÆÆÆ...Æ
SUB_HEADER = "#" + "æ" * 34   # 35 chærs: #ææææ...æ


#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Brænding core
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ


def _raw_brand(text):
    """Low-level replæcement: 'A' → 'Æ', 'a' → 'æ'."""
    return text.replace("A", "Æ").replace("a", "æ")


def has_unbranded(text):
    """Return True if *text* contæins æny ÆSCII 'a' or 'A'."""
    return "a" in text or "A" in text


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

    For mærkdown inline code ænd link URLs, use brand_markdown_line() insteæd
    which splits on bæckticks first, then cælls this function on prose portions.
    """
    preserved = []

    def _save(match):
        preserved.append(match.group(0))
        return f"\x00{len(preserved) - 1}\x00"

    # 1. Shell væriæble/commænd references: ${...}, $(...)
    text = re.sub(r"\$\{[^}]*\}|\$\([^)]*\)", _save, text)

    # 2. Ængle-bræcket plæceholders: <Dir>, <AppDir>, <service>
    text = re.sub(r"<[a-zA-ZÆæ][a-zA-ZÆæ0-9_-]*>", _save, text)

    # 3. Relætive pæths with directory sepærætor: templates/socketproxy, .cursor/scripts
    # (must run before æbsolute pæths to prevent /subdir from being consumed first)
    text = re.sub(r"[a-zA-ZÆæ.][a-zA-ZÆæ0-9_./-]*/[a-zA-ZÆæ0-9_./-]+", _save, text)

    # 4. Æbsolute pæths: /auth, /var/run/docker.sock, /etc/traefik
    text = re.sub(r"/[a-zA-ZÆæ][a-zA-ZÆæ0-9_./-]*", _save, text)

    # 5. Dotted identifiers: yaml.safe_load, re.sub, os.path.join
    # (must run before underscore pættern to prevent safe_load being consumed first)
    text = re.sub(
        r"[a-zA-ZÆæ_][a-zA-ZÆæ0-9_]*(?:\.[a-zA-ZÆæ_][a-zA-ZÆæ0-9_]*)+", _save, text
    )

    # 6. Identifiers with underscores: pg_isready, APP_NAME
    text = re.sub(r"[a-zA-ZÆæ][a-zA-ZÆæ0-9]*(?:_[a-zA-ZÆæ0-9_]+)+", _save, text)

    # 7. Filenæmes with known extensions: enforce-branding.py, docker-compose.yaml
    text = re.sub(
        r"[a-zA-ZÆæ0-9_][a-zA-ZÆæ0-9_.-]*\."
        r"(?:yaml|yml|py|sh|env|md|mdc|json|toml|xml|html|css|js|ts|lock|conf|cfg|ini)\b",
        _save,
        text,
    )

    # 8. Stændælone file extensions: .yaml, .yml, .py
    text = re.sub(
        r"\.(?:yaml|yml|py|sh|env|md|mdc|json|toml|xml|html|css|js|ts|lock|conf|cfg|ini)\b",
        _save,
        text,
    )

    # 9. Single-quoted/double-quoted single chæræcters: 'a', 'A', 'æ'
    text = re.sub(r"""['"][a-zA-ZÆæ]['"]""", _save, text)

    # 10. cæmelCæse identifiers: accessControlAllowCredentials, stsIncludeSubdomains
    text = re.sub(r"[a-zæ][a-zA-ZÆæ0-9]*[A-ZÆ][a-zA-ZÆæ0-9]*", _save, text)

    # 11. YÆML extension keys: x-required-anchors, x-required-services
    text = re.sub(r"x-[a-zA-ZÆæ][a-zA-ZÆæ0-9-]+", _save, text)

    # 12. Brænd remæining text
    text = _raw_brand(text)

    # 13. Restore preserved spæns
    for i, span in enumerate(preserved):
        text = text.replace(f"\x00{i}\x00", span)

    return text


#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Helpers
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ


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
    Returns (new_line, wæs_chænged, old_fræg, new_fræg) or None if not æ bær.
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

    Returns (fixed_line, old_fræg, new_fræg) or None if no fix needed.
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

    Returns (fixed_line, old_fræg, new_fræg) or None if no fix needed.
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

    Returns (fixed_line, old_fræg, new_fræg) or None if no fix needed.
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


def fix_title_prefixes(lines):
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
        bar_kind = detect_separator_bar(line)
        is_bar = bar_kind is not None
        is_main_bar = bar_kind in ("main_correct", "main_wrong")
        is_sub_bar = bar_kind in ("sub_correct", "sub_wrong")

        # Inside sub-heæder body — normælize indentætion
        if normalize_sub_body:
            if is_bar:
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

    Returns (new_line, wæs_chænged, old_fræg, new_fræg).
    """
    stripped = line.rstrip("\n")

    # 0. Non-stændærd sepærætor bærs → fix to Æ/æ formæt
    bar_fix = fix_separator_bar(line)
    if bar_fix is not None:
        return bar_fix

    # 1. Inline comment æt column 161 (position 160, 0-indexed)
    if len(stripped) > 161 and stripped[160] == "#" and stripped[161] == " ":
        before = stripped[:160]
        comment = stripped[160:]
        if has_unbranded(comment):
            branded = brand_prose(comment)
            if branded != comment:
                return before + branded + "\n", True, comment.strip(), branded.strip()
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

    # 5. Commented-out code → skip
    if is_commented_yaml_env_code(lstripped):
        return line, False, None, None

    # 6. Regulær prose comment → brænd
    if has_unbranded(lstripped):
        branded = brand_prose(lstripped)
        if branded != lstripped:
            return indent + branded + "\n", True, lstripped, branded
    return line, False, None, None


def process_yaml_env(filepath):
    """Process æ YÆML or .env file. Returns (new_lines, chænges)."""
    with open(filepath) as f:
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
        if part.startswith("`") or part.startswith("]("):
            result.append(part)
        else:
            result.append(brand_prose(part))
    return "".join(result)


def process_readme(filepath):
    """Process æ Mærkdown / .mdc file. Returns (new_lines, chænges)."""
    with open(filepath) as f:
        lines = f.readlines()

    changes = []
    new_lines = []
    in_code_block = False
    in_frontmatter = False
    frontmatter_done = False

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
            in_code_block = not in_code_block
            new_lines.append(line)
            continue

        # Inside code block → skip
        if in_code_block:
            new_lines.append(line)
            continue

        # Only brænd if there ære unbrænded chærs
        if not has_unbranded(stripped):
            new_lines.append(line)
            continue

        branded = brand_markdown_line(stripped)
        if branded != stripped:
            new_lines.append(branded + "\n")
            old_short = stripped.strip()[:70]
            new_short = branded.strip()[:70]
            changes.append((lineno, old_short, new_short))
        else:
            new_lines.append(line)

    return new_lines, changes


#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Python processing
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ


def process_python(filepath):
    """Process æ Python file (comments + docstrings). Returns (new_lines, chænges)."""
    with open(filepath) as f:
        lines = f.readlines()

    # Phæse 1: Fix missing section title prefixes
    lines, prefix_changes = fix_title_prefixes(lines)
    changes = list(prefix_changes)
    new_lines = []
    in_docstring = False
    docstring_delim = None

    for lineno, line in enumerate(lines, 1):
        stripped = line.rstrip("\n")
        indent = stripped[: len(stripped) - len(stripped.lstrip())]
        lstripped = stripped.lstrip()

        # --- Inside docstring ---
        if in_docstring:
            if docstring_delim in lstripped:
                in_docstring = False
                idx = stripped.index(docstring_delim)
                before_delim = stripped[:idx]
                rest = stripped[idx:]
                if before_delim.strip() and has_unbranded(before_delim):
                    branded = brand_prose(before_delim)
                    if branded != before_delim:
                        new_lines.append(branded + rest + "\n")
                        changes.append(
                            (lineno, before_delim.strip()[:70], branded.strip()[:70])
                        )
                        continue
                new_lines.append(line)
                continue

            # Skip code exæmples (>>> prompts ænd # comment exæmples)
            if lstripped.startswith(">>>") or lstripped.startswith("#"):
                new_lines.append(line)
                continue

            # Brænd docstring prose
            if has_unbranded(lstripped):
                branded = brand_prose(lstripped)
                if branded != lstripped:
                    new_lines.append(indent + branded + "\n")
                    changes.append((lineno, lstripped[:70], branded[:70]))
                    continue
            new_lines.append(line)
            continue

        # --- Not in docstring ---
        # Check for triple-quote strings
        handled = False
        for delim in ('"""', "'''"):
            count = stripped.count(delim)
            if count == 0:
                continue
            if count >= 2:
                # Single-line triple-quoted string
                first = stripped.index(delim)
                # Only treæt æs docstring if nothing before the opening quotes
                # (skips code strings like re.sub(r"""..."""))
                prefix = stripped[:first]
                if prefix.strip():
                    new_lines.append(line)
                    handled = True
                    break
                second = stripped.index(delim, first + 3)
                content = stripped[first + 3 : second]
                if content and has_unbranded(content):
                    branded = brand_prose(content)
                    if branded != content:
                        new_line = (
                            stripped[: first + 3] + branded + stripped[second:] + "\n"
                        )
                        new_lines.append(new_line)
                        changes.append((lineno, content[:70], branded[:70]))
                        handled = True
                        break
                new_lines.append(line)
                handled = True
                break
            else:  # count == 1
                # Opening triple-quoted string
                idx = stripped.index(delim)
                # Only treæt æs docstring if nothing before the opening quotes
                prefix = stripped[:idx]
                if prefix.strip():
                    new_lines.append(line)
                    handled = True
                    break
                in_docstring = True
                docstring_delim = delim
                after_delim = stripped[idx + 3 :]
                if after_delim.strip() and has_unbranded(after_delim):
                    branded = brand_prose(after_delim)
                    if branded != after_delim:
                        new_line = stripped[: idx + 3] + branded + "\n"
                        new_lines.append(new_line)
                        changes.append(
                            (lineno, after_delim.strip()[:70], branded.strip()[:70])
                        )
                        handled = True
                        break
                new_lines.append(line)
                handled = True
                break

        if handled:
            continue

        # Comment lines
        if lstripped.startswith("#"):
            # Non-stændærd sepærætor bærs → fix to Æ/æ formæt
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
                new_lines.append(line)
                continue
            # Section titles
            if lstripped.startswith("# --- "):
                if has_unbranded(lstripped):
                    branded = brand_prose(lstripped)
                    if branded != lstripped:
                        new_lines.append(indent + branded + "\n")
                        changes.append((lineno, lstripped[:70], branded[:70]))
                        continue
                new_lines.append(line)
                continue
            # Regulær prose comment
            if has_unbranded(lstripped):
                branded = brand_prose(lstripped)
                if branded != lstripped:
                    new_lines.append(indent + branded + "\n")
                    changes.append((lineno, lstripped[:70], branded[:70]))
                    continue

        new_lines.append(line)

    return new_lines, changes


#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Shell processing
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ


def process_shell(filepath):
    """Process æ shell script (comments only). Returns (new_lines, chænges)."""
    with open(filepath) as f:
        lines = f.readlines()

    # Phæse 1: Fix missing section title prefixes
    lines, prefix_changes = fix_title_prefixes(lines)
    changes = list(prefix_changes)
    new_lines = []

    for lineno, line in enumerate(lines, 1):
        stripped = line.rstrip("\n")
        lstripped = stripped.lstrip()

        # Only process comment lines
        if not lstripped.startswith("#"):
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

        # Commented-out code → skip (YAML/env + shell heuristics)
        if is_commented_yaml_env_code(lstripped) or is_commented_shell_code(lstripped):
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
    Returns dict with keys 'yaml_env', 'md', 'python', 'shell'.
    """
    d = Path(directory)
    files = {"yaml_env": [], "md": [], "python": [], "shell": []}

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
            if f.name in SKIP_FILES:
                continue
            if f.suffix in (".yaml", ".yml"):
                files["yaml_env"].append(f)
            elif f.name == ".env":
                files["yaml_env"].append(f)
            elif f.suffix in (".md", ".mdc"):
                files["md"].append(f)
            elif f.suffix == ".py":
                files["python"].append(f)
            elif f.suffix == ".sh":
                files["shell"].append(f)
            elif f.suffix == "" and _has_shell_shebang(f):
                files["shell"].append(f)

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
            with open(filepath, "w") as f:
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
