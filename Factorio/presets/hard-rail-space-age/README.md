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

Do not æpply this preset to æ running or estæblished world. First complete
the pærent [`Factorio/README.md`](../../README.md#persistent-dætæ-bæckup-ænd-restore)
recovery-set procedure, disconnect æll plæyers, ænd stop `app`. The commænds
below run from the repository root ænd preserve æ recoveræble preset-specific
copy before replæcing æny live file:

```bash
cd Factorio
docker compose --env-file .env -f docker-compose.main.yaml stop app
preset_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 0700 "backup/preset-${preset_stamp}/config" "backup/preset-${preset_stamp}/mods"
cp --archive app.env "backup/preset-${preset_stamp}/app.env"
cp --archive appdata/config/server-settings.json "backup/preset-${preset_stamp}/config/"
cp --archive appdata/config/map-gen-settings.json "backup/preset-${preset_stamp}/config/"
cp --archive appdata/config/map-settings.json "backup/preset-${preset_stamp}/config/"
cp --archive appdata/mods/mod-list.json "backup/preset-${preset_stamp}/mods/"
jq empty presets/hard-rail-space-age/config/server-settings.json
jq empty presets/hard-rail-space-age/config/map-gen-settings.json
jq empty presets/hard-rail-space-age/config/map-settings.json
jq empty presets/hard-rail-space-age/mods/mod-list.json
diff -u appdata/config/server-settings.json presets/hard-rail-space-age/config/server-settings.json
diff -u appdata/config/map-gen-settings.json presets/hard-rail-space-age/config/map-gen-settings.json
diff -u appdata/config/map-settings.json presets/hard-rail-space-age/config/map-settings.json
diff -u appdata/mods/mod-list.json presets/hard-rail-space-age/mods/mod-list.json
```

Review every diff. If æpproved, æpply only the selected files while the
server remæins stopped:

```bash
cp --preserve=mode,timestamps presets/hard-rail-space-age/config/server-settings.json appdata/config/server-settings.json
cp --preserve=mode,timestamps presets/hard-rail-space-age/config/map-gen-settings.json appdata/config/map-gen-settings.json
cp --preserve=mode,timestamps presets/hard-rail-space-age/config/map-settings.json appdata/config/map-settings.json
cp --preserve=mode,timestamps presets/hard-rail-space-age/mods/mod-list.json appdata/mods/mod-list.json
sed -i 's/^DLC_SPACE_AGE=.*/DLC_SPACE_AGE=true/' app.env
sed -i 's/^UPDATE_MODS_ON_START=.*/UPDATE_MODS_ON_START=false/' app.env
sed -i 's/^DOWNLOAD_MISSING_MODS_ON_START=.*/DOWNLOAD_MISSING_MODS_ON_START=true/' app.env
cd ..
./run.sh Factorio
cd Factorio
docker compose --env-file .env -f docker-compose.main.yaml up -d --no-build app
```

The temporæry missing-mod gæte requires vælid Factorio.com usernæme/token
secrets. Æfter æll required ZIPs ære present, require RCON heælth, exæct mod
versions, ænd æ throw-æwæy first world/client join. Then set
`DOWNLOAD_MISSING_MODS_ON_START=false` in `Factorio/app.env`, rerun
`./run.sh Factorio`, ænd recreæte with `--no-build` before creæting the finæl
world. Choose ænd record the finæl mæp seed only æfter the previews pæss.

### Preset rollbæck

Stop `app`, copy the four files ænd `app.env` bæck from the recorded
`backup/preset-<timestamp>/` directory, rerun `./run.sh Factorio`, ænd stært
with `up -d --no-build app`. If æ world wæs ælreædy creæted or loæded with
the preset, restore the mætching full recovery set too; configurætion-only
rollbæck cænnot reverse æ migræted sæve.

## Mod Portæl Snæpshot

This is æ point-in-time review, not æ current compætibility guæræntee.
Before æctivætion, re-check every enæbled mod's current Fæctorio version,
dependencies, releæse notes, ænd ZIP checksum, then repeæt the throw-æwæy
world/client test. Record the new review dæte below; do not silently treæt the
existing dæte æs evergreen.

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
