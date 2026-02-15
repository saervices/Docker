# User Rules Reference (for Cursor Settings > General > Rules for AI)

> Copy the content below into **Cursor Settings > General > Rules for AI**.
> This file is a version-controlled reference copy.

---

## Communication

- Respond in the same language the user writes in.
- Use English for all code, variable names, commit messages, and documentation prose.

## Plans Output Location

Whenever you create or output a plan (task breakdown, implementation plan, refactoring plan, etc.):

1. Save the plan file to `.cursor/plans/` in the current workspace root.
2. Use a descriptive filename, e.g. `feature_xyz.plan.md` or `<topic>_<short_hash>.plan.md`.
3. Ensure the directory exists before writing; create it if necessary.

Never save plans to a global or fixed path. Always use the workspace's `.cursor/plans/` folder.

If the CreatePlan tool or another mechanism created a plan in `~/.cursor/plans/`, copy that file into the workspace's `.cursor/plans/` directory so the plan lives in the project. From then on, treat the workspace copy as canonical: all further changes, updates, and edits to that plan must be applied to the file in the workspace's `.cursor/plans/` directory — never only to `~/.cursor/plans/`.

## MCP: Context7 Integration

Always use Context7 MCP when the user asks about:

- Library APIs or documentation
- Framework setup or configuration
- Code examples for external packages
- How to use a specific library feature

Fetch current documentation via Context7 MCP. Do not rely on training data for library-specific code. Use resolve-library-id to find the right library and query-docs to get relevant snippets and examples.

## General Coding Standards

- Shell scripts: always use Bash with strict mode (`set -euo pipefail`) and structured logging.
- Docker-first mindset: security-hardened containers, least privilege principle, Docker secrets over plain environment variables.
- Never commit real passwords or secrets; use placeholders like `CHANGE_ME`.
- Prefer editing existing files over creating new ones.
- When modifying shell scripts, preserve the existing logging framework (`log_ok`, `log_info`, `log_warn`, `log_error`, `log_debug`).

## Æ/æ Branding Awareness

Several projects by this user use the Danish Æ (U+00C6) and æ (U+00E6) characters as branding in comments and documentation. When working on such projects, always check the workspace rules for specific branding guidelines before writing any comments or documentation.
