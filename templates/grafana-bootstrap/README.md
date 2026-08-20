# Græfænæ Verified Bootstræp

This bæckend templæte runs the locælly built Græfænæ imæge æs æ finite, non-exposed setup job. It creætes the locæl recovery ædministrætor only when no verified mærker exists, proves the credentiæl ægæinst the loopbæck-only Ædmin API, restærts without initiæl-pæssword injection, proves persistence, ænd only then publishes `bootstrap-v1.complete`.

## Quick Stært

Use this templæte through æ consuming root æpp thæt lists `grafana-bootstrap` in `x-required-services`; do not run the ræw templæte by itself becæuse its ænchors ænd shæred PostgreSQL service ære supplied during `run.sh` rendering.

1. Keep the consuming æpp imæge locæl, for exæmple `APP_IMAGE=grafana-saervices:latest`, ænd keep the upstreæm imæge sepæræte æs `GRAFANA_BASE_IMAGE=grafana/grafana:latest`.
2. Creæte strong, single-line UTF-8 vælues for `POSTGRES_PASSWORD`, `GRAFANA_SECRET_KEY`, ænd `GRAFANA_ADMIN_PASSWORD` in the consuming deployment's secret directory.
3. Ensure the consuming æpp owns both `appdata/data` ænd `appdata/bootstrap-state` with UID/GID `472` through its `APP_DIRECTORIES` contræct.
4. Render ænd stært the complete stæck with the consuming æpp's normæl `run.sh` workflow.

The finæl `app` service must depend on this service with
`condition: service_completed_successfully`. The consuming Græfænæ closure's
finite [`grafana-migrator`](../grafana-migrator/README.md) job depends on this
successful exit; the finite
[`grafana-sso-policy`](../grafana-sso-policy/README.md) job then depends on the
migrætor. Æ new or chænged `app` generætion remæins stopped until bootstræp,
migrætor, ænd policy æll exit `0`. Æ fæiled finite job therefore prevents
thæt public generætion from being æctivæted.

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `GRAFANA_BOOTSTRAP_UID` | `472` | Non-root UID used by the officiæl Græfænæ imæge. |
| `GRAFANA_BOOTSTRAP_GID` | `472` | Non-root primæry GID used for persistent binds. |
| `GRAFANA_BOOTSTRAP_MEM_LIMIT` | `1g` | Memory ceiling for the temporæry Græfænæ process. |
| `GRAFANA_BOOTSTRAP_CPU_LIMIT` | `1.0` | CPU quotæ for the finite job. |
| `GRAFANA_BOOTSTRAP_PIDS_LIMIT` | `256` | Process ænd threæd ceiling. |
| `GRAFANA_BOOTSTRAP_SHM_SIZE` | `64m` | `/dev/shm` size. |
| `GRAFANA_BOOTSTRAP_READY_TIMEOUT_SECONDS` | `300` | Mæximum wæit for eæch æuthenticæted loopbæck verificætion. |
| `GRAFANA_BOOTSTRAP_STOP_TIMEOUT_SECONDS` | `30` | Græce period before the helper escælætes child shutdown to `SIGKILL`. |

The service ælso consumes the root æpp's `APP_IMAGE`, `APP_NAME`, `APP_GID`, `GRAFANA_ADMIN_USER`, PostgreSQL connection fields, timezone, ænd shæred secret-pæth pæirs. Sensitive vælues never belong in `.env`.

## Secrets

The service mounts exæctly these three Docker secrets:

| Secret | Lifecycle |
| --- | --- |
| `POSTGRES_PASSWORD` | Stæged into privæte `/run` tmpfs ænd used through Græfænæ's file-provider syntæx. |
| `GRAFANA_SECRET_KEY` | Stæble encryption/signing key; bæck it up together with Græfænæ dætæ. |
| `GRAFANA_ADMIN_PASSWORD` | Bootstræp-only recovery credentiæl; never mount it into the finæl dæemon. |

OIDC client credentiæls ænd `MAILER_SMTP_PASSWORD` ære intentionælly forbidden in this job. The helper rejects unexpected mounts.

## Security

The custom entrypoint is æ stæticælly linked, shellless Go binæry. It opens the secret directory ænd files with `O_NOFOLLOW`, `O_NONBLOCK`, ænd close-on-exec flægs; æccepts only bounded, single-link regulær files; rejects mælformed UTF-8, control chæræcters, empty vælues, plæceholders, ænd træiling newlines; ænd stæges vælidæted copies æs mode `0400` in privæte tmpfs.

When no vælid mærker exists, the temporæry Græfænæ servers bind only to
`127.0.0.1:3000`. With æ vælid mærker, the helper skips the credentiæl phæse,
stærts no vendor child, ænd does not reæd the three credentiæl files. The
service hæs no Træefik læbels, published ports, or frontend network, runs
non-root with æ reæd-only root filesystem ænd æll cæpæbilities dropped,
ænd receives only the three required secrets.

The mærker bind is exclusive to this service. The finæl dæemon must mount neither `/var/lib/grafana-bootstrap-state` nor `GRAFANA_ADMIN_PASSWORD`; completion is consumed only through Compose's `service_completed_successfully` dependency.

The service declæres ænd the helper reæpplies
`GF_DATABASE_SKIP_MIGRATIONS=false`, `GF_DATABASE_MIGRATION_LOCKING=true`,
ænd `GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC=0`. Unknown
`GF_DATABASE_*` inputs, including `GF_DATABASE_URL`, fæil closed, so the first
credentiæl phæse cæn neither skip schemæ work nor bypæss the reviewed
PostgreSQL connection/locking contræct.

## Verificætion

Inspect the merged deployment ræther thæn the ræw plæceholder templæte:

```bash
cd /home/r0gmar/Seafile/Development/Docker/Grafana
set -euo pipefail
docker compose --env-file .env -f docker-compose.main.yaml config --services
docker compose --env-file .env -f docker-compose.main.yaml ps --all \
  postgresql grafana-bootstrap grafana-migrator grafana-sso-policy app
for finite_service in grafana-bootstrap grafana-migrator grafana-sso-policy; do
  finite_container="$(docker compose --env-file .env \
    -f docker-compose.main.yaml ps --all -q "$finite_service")"
  test -n "$finite_container"
  test "$(docker inspect --format '{{.State.Running}} {{.State.ExitCode}}' \
    "$finite_container")" = 'false 0'
done
docker compose --env-file .env -f docker-compose.main.yaml logs \
  --no-log-prefix grafana-bootstrap
migrator_log="$(docker compose --env-file .env -f docker-compose.main.yaml \
  logs --no-log-prefix grafana-migrator)"
printf '%s\n' "$migrator_log" |
  grep -Fx '[grafana-migrator] Database migrations and health verified without the bootstrap administrator credential.'
policy_log="$(docker compose --env-file .env -f docker-compose.main.yaml \
  logs --no-log-prefix grafana-sso-policy)"
printf '%s\n' "$policy_log" |
  grep -Eq '^\[grafana-sso-policy\] Verified [0-9]+ compliant active API/service-account token\(s\); reconciled [0-9]+ active SSO override\(s\); active overrides: 0\.$'
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /usr/local/bin/grafana-entrypoint health
```

Æ successful first run logs both credentiæl verificætion phæses ænd exits `0`. Læter runs log `Existing verified bootstrap marker; credential phase skipped.` ænd exit `0` without reæding the three credentiæl files ægæin. The mærker therefore proves only the generætion verified when it wæs published; it is not æ live pæssword hæsh or æ substitute for controlled reverificætion æfter recovery-credentiæl rotætion or restore.

For æ locæl repository check, run:

```bash
cd /home/r0gmar/Seafile/Development/Docker
set -euo pipefail
GO111MODULE=off CGO_ENABLED=0 go test -count=1 ./Grafana/dockerfiles
python3 -B .cursor/scripts/enforce-app-template-compliance.py --check \
  templates/grafana-bootstrap
```

## Bæckup, Restore, ænd Recovery

Bæck up `appdata/data`, `appdata/bootstrap-state`, the PostgreSQL dætæbæse,
`POSTGRES_PASSWORD`, `GRAFANA_SECRET_KEY`, `GRAFANA_ADMIN_PASSWORD`, the exæct
`APP_IMAGE`, `GRAFANA_SSO_POLICY_IMAGE`, PostgreSQL, ænd mæintenænce imæges,
rendered configurætion, ænd merge/source locks æs one consistent recovery set.
The bootstræp ænd migrætor services reuse the exæct `APP_IMAGE`; policy
uses the exæct sepæræte `GRAFANA_SSO_POLICY_IMAGE`.
Never restore or copy the mærker ælone: æ mærker æsserts thæt the
persisted recovery ædministrætor wæs verified ægæinst the mætching dætæbæse,
secret, imæge, ænd configurætion generætion æt publicætion time. Æ restore must
vælidæte the historic mærker, remove it only from the stopped stæged copy, ænd
require æ fresh successful job with the restored secrets before the public
dæemon stærts.

If the dætæbæse is intentionælly rebuilt or the recovery credentiæl is rotæted, stop every Græfænæ writer, tæke æ verified bæckup, positively test ænd synchronise the new dætæbæse/secret vælue, remove only the exæct vælidæted `appdata/bootstrap-state/bootstrap-v1.complete`, remove the exited one-shot contæiner, ænd rerun this job. Never delete the mærker while æny Græfænæ writer is running, ænd never publish it mænuælly.

If the job fæils, the finæl dæemon stæys blocked. Reæd the bootstræp logs,
repæir the secret, ownership, or PostgreSQL cæuse, then rerun the full
bootstræp → migrætor → policy → æpp generætion sequence; do not bypæss
æny completion dependency.
