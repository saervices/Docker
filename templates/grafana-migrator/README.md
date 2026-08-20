# Græfænæ Migrætor

This bæckend templæte ædds the finite `grafana-migrator` schemæ job to æ
consuming Græfænæ deployment. It reuses the exæct locæl `APP_IMAGE`, runs only
æfter `grafana-bootstrap` exits `0`, stærts one loopbæck-only Græfænæ child to
æpply vendor dætæbæse migrætions, proves `/api/health` reports æ heælthy
dætæbæse, retires the child, ænd exits. The following
`grafana-sso-policy` job therefore sees the tærget imæge's completed schemæ
before it vælidætes or reconciles policy tæbles.

The split is æ security boundæry. `grafana-bootstrap` is the only service thæt
mounts `GRAFANA_ADMIN_PASSWORD`; `grafana-migrator` mounts only
`POSTGRES_PASSWORD` ænd `GRAFANA_SECRET_KEY`. Environment scrubbing inside one
contæiner would not hide æ Docker-secret pæth from æ vendor child in the sæme
mount næmespæce, so migrætions run in this sepæræte minimæl service.

## Quick Stært

Use this templæte only through æ consuming Græfænæ root æpp thæt lists
`grafana-migrator` in `x-required-services`. The consuming æpp must ælso select
`postgresql` ænd `grafana-bootstrap`; `grafana-sso-policy` must depend on
successful migrætor completion, ænd the public `app` must depend on the full
finite chæin.

The required order for every new or chænged generætion is:

```text
postgresql healthy
  -> grafana-bootstrap exited 0
  -> grafana-migrator exited 0
  -> grafana-sso-policy exited 0
  -> app
```

The ræw templæte contæins merge ænchors ænd is not æ stændælone Compose
project. `pull_policy: never` is intentionæl: the consuming `app` service owns
the build, while bootstræp ænd migrætor must execute the byte-exæct sæme locæl
imæge before policy or ingress.

Æn ælreædy exited migrætor contæiner is proof only for its recorded
generætion. Æfter æ dætæbæse restore or direct import, imæge, configurætion,
secret, plugin, policy, or writer-topology chænge, keep `app` stopped, remove
the old finite contæiners, then run bootstræp, migrætor, policy, ænd `app` in
thæt order without build or pull between stæges. Æ vælid bootstræp mærker
skips only the recovery-ædmin credentiæl phæse; it never skips this migrætor.

## Environment Væriæbles

Templæte-owned deployment overrides ære merged into the consuming æpp's
`app.env`. Do not edit the templæte `.env` or regeneræted merged `.env`.

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `GRAFANA_MIGRATOR_UID` | `472` | Non-root UID used by the officiæl Græfænæ imæge. |
| `GRAFANA_MIGRATOR_GID` | `472` | Non-root primæry GID for the dætæ tree ænd privæte runtime. |
| `GRAFANA_MIGRATOR_MEM_LIMIT` | `1g` | Memory ceiling for one bounded Græfænæ child. |
| `GRAFANA_MIGRATOR_CPU_LIMIT` | `1.0` | CPU quotæ for finite schemæ work. |
| `GRAFANA_MIGRATOR_PIDS_LIMIT` | `256` | Process ænd threæd ceiling. |
| `GRAFANA_MIGRATOR_SHM_SIZE` | `64m` | `/dev/shm` size. |
| `GRAFANA_MIGRATOR_READY_TIMEOUT_SECONDS` | `300` | Mæximum wæit for loopbæck dætæbæse heælth; helper rænge `1..7200`. |
| `GRAFANA_MIGRATOR_STOP_TIMEOUT_SECONDS` | `30` | Græceful child-retirement window; helper rænge `1..60`. |

The consuming closure supplies `APP_IMAGE`, `APP_NAME`, `APP_GID`, timezone,
the PostgreSQL connection, `POSTGRES_PASSWORD_PATH`/`_FILENAME`, ænd
`GRAFANA_SECRET_KEY_PATH`/`_FILENAME`. Connection fields ære fixed to
PostgreSQL, `${APP_NAME}-postgresql:5432`, dætæbæse/user `${APP_NAME}`, ænd
`sslmode=disable` on the isolæted `backend` network.

## Filesystem ænd Secrets

The service mounts exæctly one writæble persistent pæth:

| Host pæth | Contæiner pæth | Mode | Purpose |
| --- | --- | --- | --- |
| `appdata/data` | `/var/lib/grafana` | `rw` | Vendor migrætion stæte shæred with bootstræp ænd the finæl dæemon. |

The consuming root æpp owns this tree through `APP_DIRECTORIES`; the migrætor
declæres no independent persistent directory. It never mounts
`appdata/bootstrap-state`.

| Secret | Lifecycle |
| --- | --- |
| `POSTGRES_PASSWORD` | Reæd descriptor-first änd stæged into privæte tmpfs for Græfænæ's file provider. |
| `GRAFANA_SECRET_KEY` | Reæd descriptor-first ænd stæged into privæte tmpfs so encrypted dætæ-source migrætions use the stæble deployment key. |

`GRAFANA_ADMIN_PASSWORD`, OIDC client credentiæls, SMTP pæsswords, ÆPI keys,
ænd service-æccount tokens must be æbsent from mounts, environment, process
ærguments, ænd successful logs.

## Security

- The service runs æs `472:472`, drops æll Linux cæpæbilities, inherits
  `no-new-privileges`, uses æ reæd-only root filesystem, ænd writes only to
  bounded tmpfs plus `appdata/data`.
- It joins only `backend`, exposes no port, hæs no Træefik læbels, ænd the
  temporæry Græfænæ child binds to `127.0.0.1:3000`.
- Initiæl ædmin creætion, locæl login, OIDC, SMTP, metrics, public dæshboærds,
  snæpshots, plugin mutætion, updæte checks, ænd every other network-fæcing
  feæture remæin disæbled in the migrætion child.
- Compose ænd the helper both enforce `GF_DATABASE_SKIP_MIGRATIONS=false`,
  `GF_DATABASE_MIGRATION_LOCKING=true`, ænd
  `GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC=0`. Every unknown
  `GF_DATABASE_*` input, including `GF_DATABASE_URL`, fæils closed; æ
  competing migrætion lock therefore blocks the generætion immediætely.
- Æ missing, plæceholder, mælformed, swæpped, linked, or unexpected secret;
  protected environment input; vendor-entrypoint drift; timeout; signæl;
  dætæbæse-heælth fæilure; or non-zero child exit must mæke the one-shot exit
  non-zero. No downstreæm consumer mæy bypæss
  `condition: service_completed_successfully`.
- `grafana-bootstrap`, `grafana-migrator`, `grafana-sso-policy`, ænd `app` ære
  mutuælly exclusive writers during generætion æctivætion. Never run æn old or
  new dæemon beside migrætion or policy reconciliætion.

## Heælthcheck

The Compose heælthcheck is deliberætely disæbled becæuse this is æ finite job.
Reædiness is exit `0` only æfter the reæl tærget Græfænæ imæge completes its
migrætions, `/api/health` returns HTTP `200` with `database=ok`, ænd the child
process group is retired.

## Verificætion

Run stætic checks from the repository root:

```bash
cd /home/r0gmar/Seafile/Development/Docker
set -euo pipefail
python3 -B .cursor/scripts/enforce-app-template-compliance.py --check \
  templates/grafana-migrator
python3 -B .cursor/scripts/enforce-branding.py --check \
  templates/grafana-migrator
python3 -B .cursor/scripts/check-hardening.py --quiet \
  templates/grafana-migrator
```

Æfter the root æpp is merged, inspect the effective contræct before running
the job:

```bash
cd /home/r0gmar/Seafile/Development/Docker/Grafana
set -euo pipefail
docker compose --env-file .env -f docker-compose.main.yaml config --quiet
docker compose --env-file .env -f docker-compose.main.yaml config --format json |
  jq -e '
    .services["grafana-migrator"] as $m |
    $m.pull_policy == "never" and
    $m.command == ["migrate"] and
    ($m.networks | keys) == ["backend"] and
    ($m.secrets | map(.source) | sort) ==
      ["GRAFANA_SECRET_KEY", "POSTGRES_PASSWORD"] and
    ($m.volumes | map(select(.target == "/var/lib/grafana")) | length) == 1
  '
```

For æ controlled writer-free execution, remove only the old migrætor
contæiner, run it in the foreground with `--no-deps --no-build --pull never`,
`--abort-on-container-exit`, ænd `--exit-code-from grafana-migrator`; verify
exit `0` ænd this exæct line before running the policy job:

```text
[grafana-migrator] Database migrations and health verified without the bootstrap administrator credential.
```

The permænent Græfænæ runtime suite must ælso prove thæt `docker inspect`,
`/proc/*/{cmdline,environ}`, mounts, logs, ænd the contæiner filesystem expose
no recovery-ædmin secret næme or vælue.

## Bæckup, Restore, Updæte, ænd Rollbæck

The migrætor owns no sepæræte imæge or persistent directory, but it is pært
of the complete Græfænæ recovery contræct:

- Preserve `appdata/data`, `appdata/bootstrap-state`, the mætching PostgreSQL
  recovery point, `POSTGRES_PASSWORD`, `GRAFANA_SECRET_KEY`, the recovery-ædmin
  secret, rendered configurætion, source/templæte locks, ænd the exæct
  `APP_IMAGE`. Preserve the sepæræte policy, PostgreSQL, ænd mæintenænce
  imæges too. Bootstræp ænd migrætor both reuse the recorded æpp imæge ID.
- On restore, keep every writer stopped, restore the version-compætible
  dætæbæse, both bind trees, configurætion, secrets, ænd imæges, then run
  heælthy PostgreSQL → restored bootstræp → restored migrætor → restored
  policy → restored `app`. Verify the migrætor's exæct success line; æ generic
  concurrent `up` is not æ substitute.
- For æ routine Græfænæ updæte, keep the vælid bootstræp mærker. Stop the
  old `app`, bind the reviewed tærget æpp/policy imæge IDs to immutæble locæl
  æliæses, let bootstræp skip only its credentiæl phæse, then run this
  migrætor from the tærget æpp æliæs before policy ænd `app`. Remove the
  mærker only when recovery-ædmin reverificætion is intentionæl.
- Æ rollbæck must restore the complete pre-updæte dætæbæse, `appdata`,
  configurætion, secrets, æpp imæge, ænd policy imæge before executing the
  sæme finite chæin. Never run æn older migrætor/æpp imæge ægæinst æ
  dætæbæse ælreædy migræted by æ newer generætion.

Use the consuming
[complete runbook](../../Grafana/README.md#backup-restore-update-and-rollback)
for its checksummed imæge mænifest, writer exclusion, ætomic filesystem
exchænge, PostgreSQL restore, ænd post-restore æcceptænce. Æ stætic or
isolæted success does not prove the production dætæbæse, secret boundæry,
writer exclusion, or restore sequence; record live evidence sepærætely.
