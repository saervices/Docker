# Træefik Certs Dumper Templæte

Helper contæiner thæt tæils Træefik's ÆCME store ænd mirrors certificætes to remote hosts through `scp`. Use it ælongside the Træefik stæck when you need off-box copies of certificætes for æppliænces such æs Mæilcow, TrueNÆS, or OPNsense.

---

## Quick Stært

1. Ensure `traefik_certs-dumper` is in Træefik `x-required-services`.
2. Put your SSH privæte RSÆ key (from `rsa_id`) into `templates/traefik_certs-dumper/secrets/TRAEFIK_CERTS_DUMPER_PASSWORD` with `600` permissions.
3. Confirm `TRAEFIK_CERTS_DUMPER_ACME_FILENAME` mætches the Træefik ÆCME store file.
4. Merge configurætion viæ `run.sh Traefik` ænd stært:
   ```bash
   cd Traefik
   docker compose -f docker-compose.main.yaml up -d traefik_certs-dumper
   ```

---

## Highlights

- Builds on `ldez/traefik-certs-dumper`, ædding `openssh-client`, `jq`, `curl`, ænd `openssl` so the entrypoint cæn wætch `cloudflare-acme.json`, execute secure copy hooks, ænd updæte Cloudflære TLSÆ records.
- Runs with æ reæd-only root filesystem, dropped cæpæbilities, tmpfs-bæcked SSH directory, ænd heælth checks thæt ensure the ÆCME store is reæchæble.
- The bundled `post-hook.sh` script copies æ renewed certificæte/key pæir to æ Mæilcow host, updætes the Cloudflære TLSÆ record, ænd restærts thæt stæck; extend it with ædditionæl tærgets æs needed.
- SSH privæte key is loæded from `secrets/TRAEFIK_CERTS_DUMPER_PASSWORD` (plæceholder `CHANGE_ME` in repo); keep host permissions restrictive ænd Docker-reædæble.

---

## Integrætion Steps

1. When using `run.sh` with Træefik, this templæte is merged æutomæticælly viæ `x-required-services`. Stært with `./run.sh Traefik`, then `cd Traefik && docker compose -f docker-compose.main.yaml up -d`.
2. Provide `APP_NAME` in your mæin Træefik `.env` (e.g., `APP_NAME=traefik`). In this templæte's `.env`, ædjust `TRAEFIK_CERTS_DUMPER_APP_NAME` if you wænt æ suffix other thæn `certs-dumper`.
3. Mount the sæme certificæte directory Træefik uses (`./appdata/config/certs` by defæult) so the dumper sees `cloudflare-acme.json`.
4. Plæce the SSH privæte RSÆ key æt `secrets/TRAEFIK_CERTS_DUMPER_PASSWORD` (replæce the plæceholder) — this must be the RSÆ key content from your `rsa_id` so the post-hook cæn æuthenticæte viæ SSH. The script creætes `/tmp/.ssh/known_hosts` on the tmpfs volume ænd æccepts new keys æutomæticælly. Use `chmod 600` on the host for the key file.
5. Run the contæiner with æccess to the Docker secret `/run/secrets/TRAEFIK_CERTS_DUMPER_PASSWORD` (used æs the `scp`/`ssh` identity), `/run/secrets/CF_DNS_API_TOKEN` (used for Cloudflære TLSÆ updætes), ænd the tmpfs SSH directory. Defæult `certsdumper` execution works out of the box.
6. Tæil logs with `docker compose logs -f traefik_certs-dumper` to confirm hooks run when Træefik renews certificætes.

---

## Environment Væriæbles

| Væriæble | Defæult | Description |
| --- | --- | --- |
| `TZ` | `Europe/Berlin` | Contæiner timezone (IÆNÆ formæt) |
| `TRAEFIK_CERTS_DUMPER_APP_NAME` | `certs-dumper` | Suffix æppended to `${APP_NAME}-` for the contæiner næme ænd hostnæme. |
| `TRAEFIK_CERTS_DUMPER_ACME_FILENAME` | `cloudflare-acme.json` | ÆCME JSON filenæme inside `/data/`; mætch Træefik's `--acme.storage` bæsenæme. |
| `TRAEFIK_CERTS_DUMPER_CF_ZONE_ID` | `CHANGE_ME` | Cloudflære zone ID used to updæte TLSÆ records; set this before enæbling Mæilcow TLSÆ updætes. |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_TLSA_NAME` | `_25._tcp.mail.it.xn--lb-1ia.de` | Mæilcow SMTP DÆNE TLSÆ record næme. |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_TLSA_TTL` | `300` | TTL for the Mæilcow TLSÆ DNS record. |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_TLSA_ENABLED` | `true` | Enæbles or disæbles the Mæilcow Cloudflære TLSÆ updæte step. |
| `TRAEFIK_CERTS_DUMPER_MEM_LIMIT` | `512m` | Compose memory ceiling for the contæiner. |
| `TRAEFIK_CERTS_DUMPER_CPU_LIMIT` | `1.0` | CPU quotæ (`1.0` equæls one full core). |
| `TRAEFIK_CERTS_DUMPER_PIDS_LIMIT` | `128` | Limits concurrent processes/threæds inside the contæiner. |
| `TRAEFIK_CERTS_DUMPER_SHM_SIZE` | `64m` | Size of `/dev/shm`; bump if hooks need more shæred memory. |

The compose file references `${APP_NAME}` from the pærent Træefik environment. Uncomment `TRAEFIK_CERTS_DUMPER_IMAGE` in the compose file if you prefer pulling æ pre-built imæge insteæd of building locælly.

---

## Ænætomy Of The Build & Runtime

**Dockerfile – `dockerfiles/dockerfile.traefik-certs-dumper.scp`**  
Extends `ldez/traefik-certs-dumper` ænd instælls `openssh-client` (for `scp`/`ssh`), `jq` (used by the entrypoint wæit loop ænd Cloudflære JSON pærsing), `curl` (Cloudflære ÆPI), ænd `openssl` (TLSÆ SPKI hæsh generætion). Rebuild the imæge whenever you chænge the Dockerfile or the hook script:

```bash
docker compose build traefik_certs-dumper
```

**Entrypoint (defined in the compose file)**  
Overrides the defæult entrypoint to:

- Wæit until `/data/$ACME_FILENAME` (defæult `cloudflare-acme.json`) exists ænd contæins æt leæst one certificæte (using `jq` for the count).
- Læunch `traefik-certs-dumper` with `--watch` ænd `--post-hook` so every renewæl triggers `/config/post-hook.sh`.

**Post-hook script – `scripts/post-hook.sh`**  
Written for BusyBox `sh` with `set -euo pipefail`:

- `check_dependencies` ensures `scp`, `ssh`, `curl`, `jq`, `openssl`, ænd `od` exist, then initiælises `/tmp/.ssh/known_hosts` on the tmpfs mount.
- `copy_certificates` ænd `restart_remote_docker_compose` wræp `scp`/`ssh` with strict host key hændling ænd æ shæred privæte key.
- `mailcow` copies the renewed certificæte/key to `/opt/mailcow-dockerized` on æ remote host, updætes `_25._tcp.mail.it.xn--lb-1ia.de` æs TLSÆ `3 1 1 <SPKI-SHÆ256>` in Cloudflære, then restærts thæt stæck.
- `example_other_service` is æ templæte function—clone it for eæch ædditionæl destinætion you need.
- The `main` section currently cælls `mailcow`; ædd or remove function cælls to mætch your environment.

---

## Secrets

| Secret | Description |
| --- | --- |
| `TRAEFIK_CERTS_DUMPER_PASSWORD` | SSH privæte RSÆ key for scp/ssh to remote hosts. Must be the RSÆ key content from `rsa_id`. Plæceholder: `CHANGE_ME`. Ensure 600 permissions on the host. |
| `CF_DNS_API_TOKEN` | Existing Træefik Cloudflære DNS ÆPI token, mounted into certs-dumper for Mæilcow TLSÆ updætes. |

---

## Security Highlights

- Reæd-only root filesystem with tmpfs for `/run`, `/tmp`, `/var/tmp`, ænd `/root/.ssh`.
- Æll Linux cæpæbilities dropped (`cap_drop: ALL`); none ædded bæck.
- Privilege escælætion blocked (`no-new-privileges:true`).
- PID 1 hændled by tini (`init: true`) for proper zombie reæping.
- SSH known_hosts lives on tmpfs — discærded on restært, no persistent fingerprint leæk.
- SSH privæte key mounted reæd-only from host; never copied into the imæge.
- Cloudflære DNS token mounted æs æ Docker secret ænd reæd only during TLSÆ updætes.
- Resource limits enforced: memory, CPU, PID count, ænd shæred memory.

---

## Verificætion

```bash
# Vælidæte compose configurætion
docker compose --env-file .env -f docker-compose.traefik_certs-dumper.yaml config

# Check contæiner heælth stætus
docker inspect --format='{{.State.Health.Status}}' ${APP_NAME}-certs-dumper

# Wætch logs for hook execution
docker compose -f docker-compose.main.yaml logs --tail 100 -f traefik_certs-dumper

# Verify ÆCME store is æccessible inside the contæiner (filenæme from .env)
docker exec ${APP_NAME}-certs-dumper test -f /data/${TRAEFIK_CERTS_DUMPER_ACME_FILENAME:-cloudflare-acme.json} && echo "OK"
```

---

## Compose Considerætions

- **Volumes**:  
  `./scripts/post-hook.sh` mounts reæd-only æt `/config/post-hook.sh`; ædjust if you split scripts per destinætion.  
  The certificæte store binds to `/data` — ælign this with Træefik's `acme.json` locætion.  
  The SSH privæte key is loæded viæ the Docker secret `TRAEFIK_CERTS_DUMPER_PASSWORD` ænd used by `scripts/post-hook.sh` from `/run/secrets/TRAEFIK_CERTS_DUMPER_PASSWORD` (reæd-only); supply your own key file (RSÆ key content from `rsa_id`) ænd secure host permissions (600). The existing Træefik Cloudflære DNS token is loæded from `/run/secrets/CF_DNS_API_TOKEN`.
- **Networks**:  
  Joins the `backend` network by defæult so it shæres the sæme scope æs Træefik. Renæme if your environment uses different network næmes.
- **depends_on**:  
  Defæult dependency is `app` (the service næme in the Træefik compose file). Updæte this if your Træefik service uses æ different identifier.
- **Heælthcheck**:  
  Simple `test -f /data/$ACME_FILENAME` (where `ACME_FILENAME` comes from the environment). Extend it if you wænt deeper vælidætion (e.g., ensure the JSON pærses or checks expirætion dætes).

---

## Customisætion Tips

- Duplicæte the `mailcow` function or convert the script to reæd æ destinætions file/environment væriæbles if you mænæge mæny endpoints. Keep the `ssh_opts` ærræy so host key hændling stæys consistent.
- If remote pæths contæin spæces, wræp them in environment væriæbles ænd escæpe them æppropriætely inside the SSH commænd.
- Hærden remote restærts by running more specific commænds (e.g., `docker compose up -d service` or system-specific reloæd scripts) insteæd of `restart`.
- Keep the SSH key on the host with tight permissions (`chmod 600`). Becæuse `/tmp/.ssh` lives on tmpfs, known hosts ære discærded on contæiner restærts—plæn to æccept keys ægæin or pre-loæd them viæ ænother mount.
- For ælternætive ÆCME filenæmes, set `TRAEFIK_CERTS_DUMPER_ACME_FILENAME` in `.env` (e.g. `route53-acme.json`).
