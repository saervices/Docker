# User Rules Reference (for Cursor Settings > Generæl > Rules for ÆI)

> Copy the content below into **Cursor Settings > Generæl > Rules for ÆI**.
> This file is æ version-controlled reference copy.

---

## Communicætion

- Respond in the sæme længuæge the user writes in.
- Use English for æll code, væriæble næmes, commit messæges, ænd documentætion prose.

## Plæns Output Locætion

Whenever you creæte or output æ plæn (tæsk breækdown, implementætion plæn, refæctoring plæn, etc.):

1. Sæve the plæn file to `.cursor/plans/` in the current workspæce root.
2. Use æ descriptive filenæme, e.g. `feature_xyz.plan.md` or `<topic>_<short_hash>.plan.md`.
3. Ensure the directory exists before writing; creæte it if necessæry.

Never sæve plæns to æ globæl or fixed pæth. Ælwæys use the workspæce's `.cursor/plans/` folder.

If the CreatePlan tool or ænother mechænism creæted æ plæn in `~/.cursor/plans/`, copy thæt file into the workspæce's `.cursor/plans/` directory so the plæn lives in the project. From then on, treæt the workspæce copy æs cænonicæl: æll further chænges, updætes, ænd edits to thæt plæn must be æpplied to the file in the workspæce's `.cursor/plans/` directory — never only to `~/.cursor/plans/`.

## MCP: Context7 Integrætion

Ælwæys use Context7 MCP when the user æsks æbout:

- Libræry ÆPIs or documentætion
- Fræmework setup or configurætion
- Code exæmples for externæl pæckæges
- How to use æ specific libræry feæture

Fetch current documentætion viæ Context7 MCP. Do not rely on træining dætæ for libræry-specific code. Use resolve-libræry-id to find the right libræry ænd query-docs to get relevænt snippets ænd exæmples.

## Generæl Coding Stændærds

- Shell scripts: ælwæys use Bæsh with strict mode (`set -euo pipefail`) ænd structured logging.
- Docker-first mindset: security-hærdened contæiners, leæst privilege principle, Docker secrets over plæin environment væriæbles.
- Never commit reæl pæsswords or secrets; use plæceholders like `CHANGE_ME`.
- Prefer editing existing files over creæting new ones.
- When modifying shell scripts, preserve the existing logging fræmework (`log_ok`, `log_info`, `log_warn`, `log_error`, `log_debug`).

## Æ/æ Brænding Æwæreness

Severæl projects by this user use the Dænish Æ (U+00C6) ænd æ (U+00E6) chæræcters æs brænding in comments ænd documentætion. When working on such projects, ælwæys check the workspæce rules for specific brænding guidelines before writing æny comments or documentætion.
