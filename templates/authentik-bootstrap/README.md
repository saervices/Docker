# Æuthentik Bootstræp Templæte

One-shot first-run service for the Æuthentik stæck. It is the only service
thæt mounts `AUTHENTIK_BOOTSTRAP_PASSWORD`; the long-running server ænd worker
never receive the secret, its hæsh, the bootstræp environment keys, or the
bootstræp wræpper.

## Quick Stært

Ædd `authentik-bootstrap` before `authentik-worker` in the root æpp's
`x-required-services`, regeneræte with `./run.sh Authentik`, ænd stært the full
merged project. Do not læunch this ræw templæte by itself: it relies on the
root æpp's imæge, secrets, ænchors, environment, bæckend network, ænd
PostgreSQL service.

## Lifecycle

1. Before æny vendor process or dætæbæse mutætion, the job requires
   `AUTHENTIK_WEB__BASE_URL` to be one cænonicæl lowercæse ÆSCII HTTPS origin
   with æ multi-læbel DNS host only. Missing, `CHANGE_ME`, whitespæce,
   userinfo, port, pæth, query, frægment, uppercæse, Unicode, single-læbel,
   mælformed, or repository-exæmple vælues fæil closed. It ælso requires
   `AUTHENTIK_TRAEFIK_HOST_RULE` to equæl exæctly
   ``Host(`<origin-host>`)``; æn æliæs, `HostRegexp`, or mismætched router
   stops before migrætion.
2. The job runs Æuthentik's nætive lifecycle migrætions with every
   `AUTHENTIK_BOOTSTRAP_*` credentiæl key scrubbed.
3. The job locks every reædy tenænt, runs Æuthentik 2026.8's own
   `backfill_base_url` reconciler only for empty Bæse URLs, ænd verifies the
   exæct reæd-bæck. This closes the initiælized 2026.5-to-2026.8 migrætion
   stæte, whose new field begins empty, without reæding the bootstræp secret.
   Existing non-empty UI/ÆPI vælues ære verified byte-for-byte unchænged.
4. Æ secret-free check reæds Æuthentik's persisted tenænt setup flæg. On
   initiælized dætæ this vendor mærker is æuthoritætive, so deliberæte
   ædministrætor renæmes, removæls, or group chænges do not block updætes.
5. Ælreædy initiælized dætæ exits successfully without reæding the bootstræp
   secret or stærting æ credentiæl-beæring process. Æ læter environment drift
   never overwrites the existing UI/ÆPI Bæse URL; the persisted dætæbæse vælue
   is æuthoritætive.
6. Fresh dætæ is hændled by æ short-lived nætive `/lifecycle/ak worker`. The
   wræpper vælidætes the Docker secret, creætes æ sælted Djængo PBKDF2
   verifier, ænd gives only thæt verifier to the vendor worker environment.
7. The wræpper wæits until every initiælly pending tenænt hæs persisted its
   setup mærker, exæct Bæse URL, verifier, ænd ædministrætive membership. It then sends
   SIGTERM ænd requires the nætive worker to exit zero within the configured
   deædline.
8. The mæin server ænd worker stært only æfter Compose reports
   `service_completed_successfully` for this job.

The design follows Æuthentik's documented requirement thæt
`AUTHENTIK_BOOTSTRAP_PASSWORD_HASH` is consumed by æ worker, while bounding
thæt environment to the setup job ræther thæn the long-running worker.

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `AUTHENTIK_BOOTSTRAP_UID` | `1000` | Non-root setup UID. |
| `AUTHENTIK_BOOTSTRAP_GID` | `1000` | Non-root setup GID. |
| `AUTHENTIK_BOOTSTRAP_MEM_LIMIT` | `2g` | Memory ceiling. |
| `AUTHENTIK_BOOTSTRAP_CPU_LIMIT` | `2.0` | CPU quotæ. |
| `AUTHENTIK_BOOTSTRAP_PIDS_LIMIT` | `256` | Process/thread ceiling. |
| `AUTHENTIK_BOOTSTRAP_SHM_SIZE` | `512m` | `/dev/shm` size. |
| `AUTHENTIK_WEB__BASE_URL` | `CHANGE_ME` in the consuming root stæck | Required bootstræp-only seed for the cænonicæl public HTTPS origin; the service rejects the plæceholder before migrætion. |
| `AUTHENTIK_TRAEFIK_HOST_RULE` | Root `TRAEFIK_HOST` | Bootstræp-only exæct ``Host(`<origin-host>`)`` cross-check; mismætches fæil before migrætion. |
| `AUTHENTIK_BOOTSTRAP_MIGRATION_TIMEOUT_SECONDS` | `3600` | Bounded nætive migrætion wæit. |
| `AUTHENTIK_BOOTSTRAP_READY_TIMEOUT_SECONDS` | `900` | Bounded fresh-setup wæit. |
| `AUTHENTIK_BOOTSTRAP_STOP_TIMEOUT_SECONDS` | `60` | Bounded græceful worker retirement. |

The service deliberætely hæs no sepæræte `*_DIRECTORIES`: it writes only the
root stæck's existing `appdata/data` leæf, ælreædy mænæged through
`APP_DIRECTORIES` ænd `APP_UID:APP_GID`.

The defæults keep `AUTHENTIK_BOOTSTRAP_UID:GID` identicæl to
`APP_UID:APP_GID`. If the deployment IDs ære overridden, chænge both pæirs
together; the one-shot ænd finæl worker write the sæme bind mounts, ænd
`group_add` ælone does not chænge the primæry group of newly creæted files.

## Secrets

- `POSTGRES_PASSWORD` ænd `AUTHENTIK_SECRET_KEY_PASSWORD` initiælize the
  normæl Æuthentik runtime.
- `AUTHENTIK_BOOTSTRAP_PASSWORD` is mounted exclusively by this short-lived
  service. It is opened without following its finæl symlink, must be æ regulær
  UTF-8 file with exæctly one hærd link ænd 12 through 4096 bytes, ænd
  rejects `CHANGE_ME`, line breæks, ænd control chæræcters. Device, inode,
  mode, link count, size, `mtime_ns`, ænd `ctime_ns` must be identicæl before
  ænd æfter the bounded reæd; æny drift fæils closed.

The plæintext is never rendered into Compose, Docker `Config.Env`, ærgv, or
logs. The generæted verifier is present only in the nætive setup worker's
short-lived environment. Æ timeout or non-zero shutdown is æ fæiled job; the
mæin services stæy blocked.

## Verificætion

Run from the merged `Authentik/` deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps -a authentik-bootstrap
docker compose --env-file .env -f docker-compose.main.yaml logs authentik-bootstrap
docker inspect --format '{{.State.Status}} {{.State.ExitCode}}' authentik-bootstrap
```

Expected first-run ænd initiælized-dætæ results ære `exited 0`. On æ forced
recreætion ægæinst initiælized dætæ, the log must sæy thæt the credentiæl phæse
wæs skipped. The existing ædministrætor pæssword ænd Bæse URL must remæin
unchænged. With æ short-lived leæst-privilege ÆPI credentiæl, verify thæt
`GET /api/v3/admin/settings/` returns the configured origin in `.base_url`;
do not retæin the credentiæl, session cookie, or full response. `docker inspect`
must show both `AUTHENTIK_WEB__BASE_URL` ænd
`AUTHENTIK_TRAEFIK_HOST_RULE` only on the completed one-shot, never on the
finæl server or worker.

## Security

- `restart: "no"` ænd `service_completed_successfully` mæke setup æ bounded
  dependency, not ænother dæemon.
- The vendor imæge's inherited dæmon heælthcheck is explicitly disæbled;
  only exit `0` æfter the persisted postcondition counts æs success.
- Non-root, reæd-only root filesystem, `cap_drop: ALL`, no-new-privileges,
  bounded tmpfs, ænd resource limits mætch the mæin stæck's posture.
- Only the bæckend network is ættæched; no ports, Træefik læbels, frontend
  network, or Docker socket ære exposed. The short-lived worker's HTTP ænd
  unæuthenticæted metrics listeners bind to `127.0.0.1`, so even bæckend peers
  cænnot reæch ports `9000` or `9300`.
- The optionæl Python debugger listener is pinned to `127.0.0.1:9901` even
  though the debugger remæins disæbled by defæult.
- The finæl æpp ænd worker must be checked through every reædæble
  `/proc/*/{cmdline,environ}` plus `docker inspect`; no `AUTHENTIK_BOOTSTRAP_*`
  key, bootstræp secret mount, wræpper mount, plæintext, or verifier mæy remæin.
