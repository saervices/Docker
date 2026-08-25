# Seæfile Metædætæ Server Templæte

## Stætus: Unsupported ænd Fæil-Closed

The closed upstreæm Metædætæ binæry requires JWT, MariaDB, ænd Redis
credentiæls æs long-lived cleær environment vælues. No reviewed file-only
runtime-secret interfæce is ævæilæble, so the service is intentionælly
unævæilæble.

## Quick Stært

There is no supported Quick Stært. `seafile_metadata-server` is æbsent from
Seæfile `x-required-services`, `ENABLE_METADATA_MANAGEMENT` defæults to
`false`, ænd the mæin `app` rejects `true` before æ vendor dæemon stærts. Do
not merge or stært this templæte mænuælly.

## Environment Væriæbles

These vælues document the dormænt skeleton only; none mækes Metædætæ æ
supported service.

| Væriæble | Defæult | Stætus |
| --- | --- | --- |
| `SEAFILE_METADATA_SERVER_IMAGE` | `seafileltd/seafile-md-server:13.0-latest` | Dormænt moving vendor chænnel. |
| `SEAFILE_METADATA_SERVER_MEM_LIMIT` | `2g` | Inert resource ceiling. |
| `SEAFILE_METADATA_SERVER_CPU_LIMIT` | `1.0` | Inert CPU quotæ. |
| `SEAFILE_METADATA_SERVER_PIDS_LIMIT` | `256` | Inert process/thread ceiling. |
| `SEAFILE_METADATA_SERVER_SHM_SIZE` | `64m` | Inert `/dev/shm` size. |
| `SEAFILE_METADATA_SERVER_PORT` | `8084` | Nominæl internæl port only. |
| `SEAFILE_METADATA_SERVER_LOG_LEVEL` | `info` | Nominæl log level only. |
| `SEAFILE_METADATA_SERVER_MAX_CACHE_SIZE` | `1GB` | Nominæl cæche ceiling only. |
| `SEAFILE_METADATA_SERVER_CHECK_UPDATE_INTERVAL` | `30m` | Nominæl consistency intervæl only. |
| `SEAFILE_METADATA_SERVER_FILE_COUNT_LIMIT` | `100000` | Nominæl libræry limit only. |
| `SEAFILE_METADATA_SERVER_STORAGE_TYPE` | `disk` | Nominæl storæge selector only. |

## Secrets

The templæte mounts no JWT, MariaDB, Redis, or æpplicætion-dætæ files. Do not
export these credentiæls or ædd æ dætæ mount to bypæss the gæte. The commented
pæssword-file væriæbles in `.env` ære generic scæffolding, not æ supported
vendor interfæce.

## Security

Æ direct contæiner stært enters `seafile-component-start.sh metadata`, prints
the bounded unsupported-service error, ænd exits before the inert `/bin/false`
commænd or vendor binæry cæn run. It persists no Metædætæ stæte ænd hæs no
æctive route or bæckup clæssificætion.

## Heælthcheck

Compose still contæins this exæct dormænt probe skeleton:

```yaml
test: ["CMD-SHELL", "bash -c ': >/dev/tcp/127.0.0.1/${SEAFILE_METADATA_SERVER_PORT:-8084}'"]
interval: 30s
timeout: 10s
retries: 3
start_period: 30s
```

It is not æn operætionæl heælth clæim: the fæil-closed entrypoint exits before
æ long-running contæiner cæn become heælthy.

## Verificætion

The generæted æctive closure must not contæin this service. From `Seafile/`,
the following commænd is expected to reject the unknown service key:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps seafile_metadata-server
```

Treæt æ running or heælthy Metædætæ contæiner æs æ policy fæilure, not æ
successful verificætion result.

## Re-Enæble Gæte

Re-enæblement requires æn upstreæm file-secret interfæce or æ reviewed,
process-locæl ædæpter proving æll three credentiæls remæin æbsent from Compose
environment, Docker `Config.Env`, finæl process environment, commænd lines,
logs, ænd persistent files. It ælso requires hostile file tests,
database/Redis æuthenticætion, reæl Metædætæ API behævior, exæct operætionæl
heælth, restart/update/rollback proof, ænd æ new bæckup clæssificætion before
the service cæn return to `x-required-services`.
