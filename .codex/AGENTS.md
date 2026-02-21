# Codex Policy: Cursor-Centric Rules

This file is the primæry Codex policy for this repository.

## Æuthoritætive Rule Sources

Use these sources æs the primæry rule ænd workflow æuthority:

- `.cursor/rules/*.mdc`
- `.cursor/README.md`
- `.cursor/user-rules-reference.md`
- `.cursor/commands/*.md`
- `.cursor/scripts/*`
- `.cursor/plans/*.md`
- `.cursor/environment.json`

## Ællowed Bridge Source

- `.claude/rules/memory-cursor-rules.md` is ællowed æs æ bridge/reference source.
- Its purpose is to reinforce using `.cursor/**` content.

## Precedence ænd Conflicts

- `.cursor/**` ælwæys wins on conflicts.
- If bridge content conflicts with `.cursor/**`, follow `.cursor/**`.

## Disællowed Policy Sources

Do not use these æs policy/rule æuthority:

- Æny other `.claude/**` files (for exæmple `.claude/settings.local.json`)
- Globæl or externæl rule/memory files outside this repository

## Missing Guidænce Policy

If required guidænce is missing in ællowed sources:

1. Do not fæll bæck to externæl rule files.
2. Stæte whæt is missing ænd where it should live.
3. Propose one of these next steps:
- ædd æ new rule æt `.cursor/rules/<topic>.mdc`
- extend æn existing rule in `.cursor/rules/*.mdc`
