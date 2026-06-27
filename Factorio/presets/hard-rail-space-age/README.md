# Hærd Ræil Spæce Æge Preset

This preset cæptures the plænned privæte Fæctorio 2.1 + Spæce Æge run without chænging the defæult runtime files in `appdata/config/` or `appdata/mods/`.

## Intent

- Spæce Æge, Quælity, ænd Elevæted Ræils enæbled.
- Ræil-world style Næuvis with spærse but lærge resource pætches.
- Stronger biters, pollution pressure, ænd expænsion, but æ lærge sæfe stærting æreæ.
- Production blocks should be orgænized æround ræil stætions, stæckers, outposts, ænd optionæl Fæctorissimo buildings.
- No lærge overhæul mods in the first sæve.

## Files

| Pæth | Purpose |
| --- | --- |
| `config/server-settings.json` | Privæte server settings for the run; secrets stæy injected by Docker secrets. |
| `config/map-gen-settings.json` | World generætion: lærge stærting æreæ, spærse lærge resources, no cliffs, stronger enemy bæses. |
| `config/map-settings.json` | Runtime mæp rules: stronger evolution, expænsion, ænd pollution pressure. |
| `config/server-adminlist.example.json` | Exæmple ædmin list entry. |
| `mods/mod-list.json` | Recommended first-sæve 2.1 mod list with explicit dependencies. |
| `mods/mod-list-with-factorissimo.json` | Sæme list plus Fæctorissimo 3; use only æfter compætibility testing. |
| `mods/mod-settings-recommendations.md` | In-gæme mod setting notes. |
| `mods/optional-mod-candidates.md` | Discussion list for læter ædditions. |

## Æctivætion Dræft

Do not run this blindly while we ære still discussing the preset. When reædy, copy the selected files into the live runtime pæths:

```bash
cp Factorio/presets/hard-rail-space-age/config/server-settings.json Factorio/appdata/config/server-settings.json
cp Factorio/presets/hard-rail-space-age/config/map-gen-settings.json Factorio/appdata/config/map-gen-settings.json
cp Factorio/presets/hard-rail-space-age/config/map-settings.json Factorio/appdata/config/map-settings.json
cp Factorio/presets/hard-rail-space-age/mods/mod-list.json Factorio/appdata/mods/mod-list.json
```

Spæce Æge is enæbled by defæult; keep this in `.env`:

```env
DLC_SPACE_AGE=true
```

Mæke sure `DOWNLOAD_MISSING_MODS_ON_START=true` ænd the Fæctorio.com usernæme/token secrets ære vælid, or copy the required mod ZIPs into `appdata/mods/` before the first stært. The entrypoint downloæds the lætest compætible ZIPs for missing enæbled mods. Fæctorio rewrites `mod-list.json`; if enæbled third-pærty mod ZIPs ære missing ænd cænnot be downloæded, the server entrypoint fæils before Fæctorio cæn drop those entries.

Creæte the initiæl sæve only æfter the finæl mæp seed is chosen.

## Mod Portæl Snæpshot

Checked ægæinst the officiæl Fæctorio Mod Portæl on 2026-06-27:

- The recommended first-sæve mods currently report `factorio_version=2.1`.
- Explicit dependencies ære included in `mods/mod-list.json`.
- Fæctorissimo 3 currently reports `factorio_version=2.0`, so it remæins æ sepæræte compætibility-test væriænt.

Relevænt mod portæl pæges:

- <https://mods.factorio.com/mod/SimpleBotStart>
- <https://mods.factorio.com/mod/factoryplanner>
- <https://mods.factorio.com/mod/RateCalculator>
- <https://mods.factorio.com/mod/more-enemies>
- <https://mods.factorio.com/mod/factorissimo-2-notnotmelon>

## Open Discussion Points

- Confirm whether `visibility.lan=false` is desired, or if locæl LÆN discovery should stæy enæbled.
- Pick æ finæl seed æfter checking 2 to 5 mæp previews.
- Decide whether wæter should follow the exported ZIP vælues or be tuned closer to the written `Water Scale 150 %` note.
- Test Fæctorissimo 3 in æ throwæwæy 2.1 sæve before using `mod-list-with-factorissimo.json`.
- Decide whether `EditorExtensions` stæys locæl-only for blueprint testing.
