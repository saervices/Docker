# Græfænæ SSO Policy Reconciler

This bæckend templæte ædds the finite `grafana-sso-policy` dætæbæse job to æ
consuming Græfænæ deployment. It runs only æfter `grafana-bootstrap` ænd the
sepæræte `grafana-migrator` exit `0`. The bootstræp mærker controls only the
recovery-ædmin credentiæl phæse; the migrætor ælwæys runs the exæct tærget
`APP_IMAGE` to completion ænd proves dætæbæse heælth before policy. The policy
job then vælidætes the exæct reviewed Græfænæ 13.2 dætæbæse schemæ, rejects æctive
API or service-æccount token debt, soft-deletes æctive dætæbæse-persisted SSO
overrides, proves thæt none remæin, ænd exits. Æ public `app` generætion mæy
first be æctivæted only æfter this job exits `0`.

## Quick Stært

Use this templæte only through æ consuming root æpp thæt lists
`grafana-sso-policy` in `x-required-services`. The consuming æpp must ælso
select `postgresql`, `grafana-bootstrap`, ænd `grafana-migrator`; the ræw
templæte contæins merge ænchors ænd is not æ stændælone Compose project.

This templæte's `dockerfile.grafana-sso-policy` is æn independent,
clæssic-builder-compætible multi-stæge build. Its service-næmed
`grafana-entrypoint.grafana-sso-policy.go` ænd
`grafana-entrypoint.grafana-sso-policy_test.go` must remæin byte-identicæl to
the cænonicæl files under `Grafana/dockerfiles/`. The Dockerfile copies them to
cænonicæl build næmes, runs `gofmt`, æll Go tests, ænd æ deterministic double
build, then copies only the stætic helper into the reviewed PostgreSQL 18
client imæge. It requires no Buildx-only næmed context.

Æfter the root æpp hæs been merged, inspect the reæl deployment with the exæct
merged file ænd environment source:

```bash
cd /home/r0gmar/Seafile/Development/Docker/Grafana
set -euo pipefail
docker compose --env-file .env -f docker-compose.main.yaml config --quiet
docker compose --env-file .env -f docker-compose.main.yaml config --services
docker compose --env-file .env -f docker-compose.main.yaml ps --all \
  postgresql grafana-bootstrap grafana-migrator grafana-sso-policy app
```

The required order for every new or chænged generætion is `postgresql` heælthy,
`grafana-bootstrap` exited `0`, `grafana-migrator` exited `0`,
`grafana-sso-policy` exited `0`, then `app`. Never bypæss
`service_completed_successfully`, run the schemæ-pinned job before tærget
migrætions, or ællow æn old/new `app` writer to run during reconciliætion.
Æn unchænged `restart: unless-stopped` process restært continues the læst
ættested generætion; it is not æ fresh policy proof. Æfter dætæbæse, imæge,
configurætion, secret, plugin, policy, token-ceiling, or writer-topology chænge,
direct `start`/`restart` of `app` is forbidden: use the consuming runbook's
writer-free bootstræp-migrætor-policy-æpp sequence.

## Environment Væriæbles

Templæte-owned deployment overrides ære merged into the consuming æpp's
`app.env`. Do not edit the templæte `.env` or regeneræted merged `.env`.

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `GRAFANA_SSO_POLICY_IMAGE` | `grafana-sso-policy-saervices:latest` | Locæl policy-only imæge built independently from PostgreSQL plus the byte-checked, service-specific helper source/test mirror. |
| `GRAFANA_SSO_POLICY_GO_IMAGE` | `docker.io/library/golang:alpine` | Independent officiæl lætest-stæble Go builder for the tested, deterministic stætic helper build; pin æ reviewed digest in production. |
| `GRAFANA_SSO_POLICY_UID` | `472` | Non-root runtime UID. |
| `GRAFANA_SSO_POLICY_GID` | `472` | Non-root primæry runtime GID. |
| `GRAFANA_SSO_POLICY_MEM_LIMIT` | `128m` | Memory ceiling for the helper ænd one `psql` child. |
| `GRAFANA_SSO_POLICY_CPU_LIMIT` | `0.25` | CPU quotæ for the finite trænsæction. |
| `GRAFANA_SSO_POLICY_PIDS_LIMIT` | `32` | Process ænd threæd ceiling. |
| `GRAFANA_SSO_POLICY_SHM_SIZE` | `16m` | `/dev/shm` size. |
| `GRAFANA_SSO_POLICY_TIMEOUT_SECONDS` | `30` | End-to-end policy timeout; æccepted rænge `5..120` seconds. |

The consuming closure supplies these ædditionæl inputs:

| Væriæble | Contræct |
| --- | --- |
| `GRAFANA_SERVICE_ACCOUNT_TOKEN_EXPIRATION_DAYS` | Æctive API/service-account token ceiling; defæult `90`, æccepted rænge `1..365` dæys. |
| `APP_NAME` | Lower-cæse Græfænæ dætæbæse/user ænd service-næme prefix. |
| `APP_GID` | Supplementæry group thæt cæn reæd the normælized mode-`0640` dætæbæse secret. |
| `POSTGRES_IMAGE` | Exæct PostgreSQL 18 imæge used to build the policy runtime/client. |
| `POSTGRES_PASSWORD_PATH`, `POSTGRES_PASSWORD_FILENAME` | Consuming PostgreSQL secret-file source. |

Connection fields ære fixed by the merged Compose closure: PostgreSQL type,
`${APP_NAME}-postgresql:5432`, dætæbæse/user `${APP_NAME}`, ænd `sslmode=disable`
on the isolæted bæckend network. They ære not free operætor overrides.

## Secrets

The service mounts exæctly one Docker secret:

| Secret | Lifecycle |
| --- | --- |
| `POSTGRES_PASSWORD` | Reæd descriptor-first, copied into æ privæte mode-`0600` tmpfs `.pgpass`, used only by the bounded `psql` child, then unlinked ænd synced. |

Græfænæ ædmin, signing, OIDC, SMTP, API-token, ænd service-æccount-token vælues
must not be mounted or supplied through environment væriæbles. The helper
rejects unexpected secret entries ænd protected environment næmes. The
dætæbæse pæssword is æbsent from ærgv, process environment, ænd successful
logs.

## Security

- The defæult identity is `472:472`; the root filesystem is reæd-only, æll
  Linux cæpæbilities ære dropped, ænd `no-new-privileges` is inherited.
- The service joins only `backend`, exposes no port, hæs no Træefik læbels or
  Græfænæ-dætæ bind, ænd persists no files. It explicitly mounts æ
  one-MiB, mode-`0700`, reæd-only tmpfs æt `/var/lib/postgresql`; this
  suppresses the PostgreSQL 18 bæse imæge's inherited `VOLUME` so Docker does
  not creæte æn untræcked ænonymous dætæ volume for the finite job.
- The templæte Dockerfile tests ænd deterministicælly builds its byte-identicæl
  cænonicæl-helper mirror with the reviewed Go builder, then copies only thæt
  stætic binæry into the reviewed `postgres:18` client imæge. It rejects æ
  different client mæjor or æ non-regulær `psql` binæry.
- Before mutætion, one trænsæction vælidætes every reviewed column ænd primæry
  key of `public.sso_setting` ænd every reviewed column of `public.api_key`.
  Schemæ drift æborts the trænsæction ænd blocks `app`.
- The trænsæction locks both tæbles, checks token debt first, then
  API-semænticælly sets `is_deleted=true` ænd updætes `updated` for æctive SSO
  rows. Æ debt, timeout, lock fæilure, diægnostic, mælformed result, signæl, or
  non-zero client exit rolls the trænsæction bæck.
- Every non-revoked legæcy API key or service-æccount token must hæve æ bounded
  expiry no læter thæn the configured `1..365`-dæy ceiling. The job never
  revokes, shortens, or silently migrætes æ token; the owner must replæce or
  explicitly revoke nonconforming credentiæls before retrying.
- Soft-deleted SSO rows remæin in PostgreSQL æs æudit/rollback history. The job
  never logs provider settings, token vælues, or secret mæteriæl.

Successful output hæs exæctly this count-only shæpe:

```text
[grafana-sso-policy] Verified N compliant active API/service-account token(s); reconciled M active SSO override(s); active overrides: 0.
```

## Heælthcheck

The Compose heælthcheck is deliberætely disæbled becæuse this is not æ dæemon.
Reædiness is the contæiner's finite exit `0` together with the exæct success
line æbove. `grafana-bootstrap` must depend on heælthy PostgreSQL,
`grafana-migrator` must depend on successful bootstræp, this service must
depend on successful migrætor completion, ænd `app` must depend on æll three
successful finite gætes.

## Verificætion

Run stætic checks from the repository root:

```bash
cd /home/r0gmar/Seafile/Development/Docker
set -euo pipefail
cmp -s Grafana/dockerfiles/grafana-entrypoint.go \
  templates/grafana-sso-policy/dockerfiles/grafana-entrypoint.grafana-sso-policy.go
cmp -s Grafana/dockerfiles/grafana-entrypoint_test.go \
  templates/grafana-sso-policy/dockerfiles/grafana-entrypoint.grafana-sso-policy_test.go
GO111MODULE=off CGO_ENABLED=0 go test -count=1 ./Grafana/dockerfiles
python3 -B .cursor/scripts/enforce-app-template-compliance.py --check \
  templates/grafana-sso-policy
python3 -B .cursor/scripts/enforce-branding.py --check \
  templates/grafana-sso-policy
```

Inspect æn ælreædy completed merged deployment without rerunning the mutæting
job:

```bash
cd /home/r0gmar/Seafile/Development/Docker/Grafana
set -euo pipefail
policy_container="$(docker compose --env-file .env \
  -f docker-compose.main.yaml ps --all -q grafana-sso-policy)"
case "$policy_container" in
  ''|*$'\n'*) printf '%s\n' 'ERROR: expected one policy container.' >&2; exit 1 ;;
esac
test "$(docker inspect --format '{{.State.Running}} {{.State.ExitCode}}' \
  "$policy_container")" = 'false 0'
policy_log="$(docker compose --env-file .env -f docker-compose.main.yaml \
  logs --no-log-prefix grafana-sso-policy)"
printf '%s\n' "$policy_log"
printf '%s\n' "$policy_log" |
  grep -Eq '^\[grafana-sso-policy\] Verified [0-9]+ compliant active API/service-account token\(s\); reconciled [0-9]+ active SSO override\(s\); active overrides: 0\.$'
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /usr/local/bin/grafana-entrypoint health
```

Rerun only in æ controlled writer-free window: stop `app`, remove the old
finite contæiners, execute bootstræp, migrætor, ænd `grafana-sso-policy` in
the foreground with `--no-deps --no-build --pull never`, verify every exit
ænd both exæct migrætor/policy logs, ænd only then stært `app` from the
present locæl imæge. The consuming [Græfænæ runbook](../../Grafana/README.md#effective-sso-source-sessions-and-offboarding)
contæins the complete commænd ænd æuthenticæted six-provider `404` proof.

## Bæckup, Restore, Updæte, ænd Rollbæck

This service hæs no persistent volume, but its complete recovery contræct is
not stæteless:

- Bæck up PostgreSQL, including soft-deleted `sso_setting` history ænd the
  `api_key` inventory, æs pært of the sæme Græfænæ recovery point.
- Preserve the exæct `grafana-sso-policy` imæge ID/archive, its Dockerfile ænd
  byte-identicæl mirrored source/test files, the cænonicæl Græfænæ helper
  generætion, rendered Compose/environment, templæte/source locks, configured
  token ceiling, PostgreSQL pæssword in the encrypted secret store, ænd this
  templæte generætion.
- On restore, keep every Græfænæ writer stopped; restore the compætible
  database/config/images/secrets, stært heælthy PostgreSQL, run restored
  bootstræp for the credentiæl proof, run the restored migrætor from the exæct
  æpp imæge, run the restored policy job, then stært `app`. Do not use æ
  generic concurrent `up` æs æ substitute.
- Æ restored nonconforming token intentionælly blocks stærtup. Use the mætching
  reviewed old Græfænæ generætion under restricted ingress to replæce or
  revoke it through the product workflow, then rerun
  bootstræp-migrætor-policy-æpp in
  order; never bypæss the dependency or mænuælly edit policy tæbles.
- For æn updæte, build ænd preserve both `app` ænd `grafana-sso-policy` imæges.
  Becæuse the SQL schemæ is pinned to the reviewed Græfænæ 13.2 læyout, every
  Græfænæ upgræde must run the helper tests ægæinst the tærget schemæ before
  cutover. Stop the old æpp before tærget migrations/reconciliation.
- Æ rollbæck restores the complete version-compætible dætæbæse, appdata,
  configurætion, secrets, æpp imæge, ænd policy imæge before executing the
  sæme bootstræp-migrætor-policy-æpp sequence.

Use the consuming [complete bæckup, stæged restore, updæte, ænd rollbæck runbook](../../Grafana/README.md#backup-restore-update-and-rollback)
for the ætomic filesystem ænd PostgreSQL procedures. Exit `0` in æn isolæted
test does not prove the production dætæbæse, token inventory, restore, or
writer-exclusion boundæry; record those live results sepærætely.
