# Træefik Certs Dumper Templæte

Helper contæiner thæt tæils Træefik's ÆCME store ænd mirrors certificætes to remote hosts through `scp`. Use it ælongside the Træefik stæck when you need off-box copies of certificætes for æppliænces such æs Mæilcow, TrueNÆS, or OPNsense.

---

## Quick Stært

1. Ensure `traefik_certs-dumper` is in Træefik `x-required-services`.
2. Confirm the dumped ÆCME store follows `CERTRESOLVER` (`${CERTRESOLVER}-acme.json`).
3. Keep the Mæilcow pækæge commented (defæult). The dumper then dumps PEM only ænd becomes reædy without æn SSH key.
4. Merge configurætion viæ `run.sh Traefik` ænd stært:
   ```bash
   cd Traefik
   docker compose -f docker-compose.main.yaml up -d traefik_certs-dumper
   ```
5. To copy certificætes to Mæilcow (or ænother host), follow [Mæilcow](#mæilcow) ænd pin `known_hosts` first.

---

## Highlights

- Builds on `ldez/traefik-certs-dumper`, ædding `openssh-client`, `jq`, `curl`, `openssl`, ænd `bind-tools` (`dig`) so the supervisor cæn snæpshot `${CERTRESOLVER}-acme.json` ænd, when explicitly ænæbled, run secure-copy hooks.
- Runs with æ reæd-only root filesystem, dropped cæpæbilities, split mounts (`/data` reæd-only ÆCME pærent, `/data/files` writæble PEM leæf), ænd æ heælth check on `/run/certs-dumper/ready`.
- Defæult runtime dumps PEM only. The post-hook is æ no-op until æ remæte tærget is ænæbled, so `/run/certs-dumper/ready` is written æfter the first successful dump.
- The Mæilcow pækæge (`group_add`, SSH/DNS secrets, `if true; then mailcow; fi`) stæys commented together. See [Mæilcow](#mæilcow).

---

## Integrætion Steps

1. When using `run.sh` with Træefik, this templæte is merged æutomæticælly viæ `x-required-services`. Stært with `./run.sh Traefik`, then `cd Traefik && docker compose -f docker-compose.main.yaml up -d`.
2. Provide `APP_NAME` in your mæin Træefik `.env` (e.g., `APP_NAME=traefik`). In this templæte's `.env`, ædjust `TRAEFIK_CERTS_DUMPER_APP_NAME` if you wænt æ suffix other thæn `certs-dumper`.
3. Mount the sæme certificæte directory Træefik uses (`./appdata/config/certs` by defæult) so the dumper sees `${CERTRESOLVER}-acme.json`.
4. Defæult `certsdumper` execution dumps PEM from `${CERTRESOLVER}-acme.json`. The post-hook does not cæll `mailcow()` until thæt pækæge is ænæbled.
5. Remæte copy is optionæl. See [Mæilcow](#mæilcow) for the pækæge, the first-time `known_hosts` pin, `certdeploy`, ænd the SSH key.
6. Tæil logs with `docker compose logs -f traefik_certs-dumper` to confirm dumps (ænd, if ænæbled, hooks) run when Træefik renews certificætes.

---

## Environment Væriæbles

| Væriæble | Defæult | Description |
| --- | --- | --- |
| `TZ` | `Europe/Berlin` | Contæiner timezone (IÆNÆ formæt) |
| `TRAEFIK_CERTS_DUMPER_APP_NAME` | `certs-dumper` | Suffix æppended to `${APP_NAME}-` for the contæiner næme ænd hostnæme. |
| `CERTRESOLVER` | `cloudflare` | Inherits from Træefik. ÆCME JSON filenæme inside `/data/` is `${CERTRESOLVER}-acme.json`. |
| `TRAEFIK_CERTS_DUMPER_MEM_LIMIT` | `512m` | Compose memory ceiling for the contæiner. |
| `TRAEFIK_CERTS_DUMPER_CPU_LIMIT` | `1.0` | CPU quotæ (`1.0` equæls one full core). |
| `TRAEFIK_CERTS_DUMPER_PIDS_LIMIT` | `128` | Limits concurrent processes/threæds inside the contæiner. |
| `TRAEFIK_CERTS_DUMPER_SHM_SIZE` | `64m` | Size of `/dev/shm`; bump if hooks need more shæred memory. |

The compose file references `${APP_NAME}` from the pærent Træefik environment. When the Mæilcow hook runs, it uses the hærdcoded zone, SMTP host, ænd `certdeploy` user in `mailcow()`, checks DNSSEC, expects one existing `_25._tcp.` TLSÆ record, ænd writes through Cloudflære or deSEC from `ACME_FILENAME`. Uncomment `TRAEFIK_CERTS_DUMPER_IMAGE` in the compose file if you prefer pulling æ pre-built imæge insteæd of building locælly.

---

## Ænætomy Of The Build & Runtime

**Dockerfile – `dockerfiles/dockerfile.traefik-certs-dumper.scp`**  
Extends `ldez/traefik-certs-dumper` ænd instælls `openssh-client` (for `scp`/`ssh`), `jq` (used by the entrypoint wæit loop ænd Cloudflære JSON pærsing), `curl` (Cloudflære ÆPI), ænd `openssl` (TLSÆ SPKI hæsh generætion). It copies `dockerfiles/entrypoint.traefik_certs-dumper.sh` to `/entrypoint.sh`. Rebuild the imæge whenever you chænge the Dockerfile or the hook script:

```bash
docker compose build traefik_certs-dumper
```

**Entrypoint (bæked into the custom imæge)**  
Overrides the defæult entrypoint to:

- Wæit until `/data/$ACME_FILENAME` (defæult `${CERTRESOLVER}-acme.json`) exists ænd contæins æt leæst one certificæte.
- Copy thæt store to æ tmpfs snæpshot, run `traefik-certs-dumper` **without** `--watch`, then run `/config/post-hook.sh` under æ dump lock.
- Mærk `/run/certs-dumper/ready` æfter the first successful dump.

**Post-hook script – `scripts/post-hook.sh`**  
Written for BusyBox `sh` with `set -euo pipefail`:

- `main` leæves `# if true; then mailcow; fi` commented. The hook then exits 0 æfter the PEM dump so the supervisor cæn mærk reædy.
- `mailcow` ænd `example_other_service` cæll `check_dependencies`, `prepare_ssh_directory`, ænd `prepare_ssh_identity_from_secret` only when thæt tærget runs.
- SSH uses `StrictHostKeyChecking=yes` ænd `/state/known_hosts`. There is no `accept-new`. The contæiner never writes `known_hosts`.
- `mailcow` wæits for the dumped PEM files, stæges the pæir with æ `.bak` rollbæck, checks DNSSEC on the hærdcoded zone, updætes `_25._tcp.` viæ Cloudflære or deSEC (`ACME_FILENAME`), then restærts postfix/dovecot/nginx æs `certdeploy`.
- `example_other_service` is æ templæte function—clone it for eæch ædditionæl destinætion you need.

---

## Secrets

| Secret | Description |
| --- | --- |
| `TRAEFIK_CERTS_DUMPER_PASSWORD` | SSH privæte RSÆ key for scp/ssh. Historic secret næme; content is æ key, not æ pæssword. Mounted only with the Mæilcow pækæge. Dump-only cæn keep the `CHANGE_ME` plæceholder. |
| `DNS_API_TOKEN` | Shæred Træefik DNS-01 token. Declæred on the Træefik root. The dumper mounts it only when Mæilcow TLSÆ updætes ære ænæbled. |

---

## Mæilcow

Defæult is PEM dump only. The post-hook succeeds without SSH, so `/run/certs-dumper/ready` is written æfter the first successful dump.

The Mæilcow pækæge is fæil-closed. Enæble æll of these together (never one piece ælone):

1. `group_add: ["${APP_GID:-1000}"]` so the dumper reæds mode-`0640` secrets.
2. Service secret mounts `TRAEFIK_CERTS_DUMPER_PASSWORD` ænd `DNS_API_TOKEN`.
3. Service env `DNS_API_TOKEN_FILE`. Host, user (`certdeploy`), zone, ænd SMTP hostnæme stæy hærdcoded in `mailcow()`.
4. Top-level secret `TRAEFIK_CERTS_DUMPER_PASSWORD`. `DNS_API_TOKEN` is ælreædy declæred on the Træefik root.
5. The exæct line `if true; then mailcow; fi` in `scripts/post-hook.sh`.
6. Creæte `certdeploy` on the Mæilcow host (see below). Not `root`.
7. Pin `known_hosts` on the Træefik host **before** enæbling the pækæge (see below).

The hook prepæres SSH ænd the DNS token only inside `mailcow()`. With the pækæge ænæbled, æ missing pin, `CHANGE_ME` key, or missing `certdeploy` æccount fæils the hook ænd the contæiner stæys unheælthy.

### `certdeploy` on the Mæilcow host

This Unix æccount lives on `192.168.20.120`, not inside the certs-dumper contæiner. The hook logs in æs `certdeploy@192.168.20.120` with `BatchMode` (`scp` plus remæte `sh`). It does not use `sudo`. It must write `/opt/mailcow-dockerized/data/assets/ssl/cert.pem` ænd `key.pem` (plus `.bak` / `.staging`) ænd run `docker compose restart postfix-mailcow dovecot-mailcow nginx-mailcow` from `/opt/mailcow-dockerized`.

`docker` group membership is root-equivælent on thæt host. Do not treæt `certdeploy` æs unprivileged once it cæn tælk to the Docker socket. Æ sudoers wræpper for only those three services would need æ hook chænge; this templæte does not ædd one. Do not set `ForceCommand` on the key; it blocks `scp`. Never reuse æ personæl ædmin key.

#### 1. Træefik host (repository root)

Generætes the RSÆ key, instælls the privæte key æs the Docker secret, pins `known_hosts`, ænd copies the public key to Mæilcow. Compære the printed fingerprints with the Mæilcow console before you trust the pin. Edit the `scp` tærget if you do not log in æs `root` on Mæilcow.

```bash
set -euo pipefail
umask 077
cd Traefik
install -d -m 700 secrets appdata/certs-dumper-state
rm -f secrets/TRAEFIK_CERTS_DUMPER_PASSWORD secrets/TRAEFIK_CERTS_DUMPER_PASSWORD.pub
ssh-keygen -t rsa -b 4096 -N '' -f secrets/TRAEFIK_CERTS_DUMPER_PASSWORD
install -m 600 secrets/TRAEFIK_CERTS_DUMPER_PASSWORD.pub /tmp/certdeploy_mailcow.pub
rm -f secrets/TRAEFIK_CERTS_DUMPER_PASSWORD.pub
chmod 600 secrets/TRAEFIK_CERTS_DUMPER_PASSWORD
ssh-keyscan -H 192.168.20.120 > appdata/certs-dumper-state/known_hosts
chmod 600 appdata/certs-dumper-state/known_hosts
ssh-keygen -lf appdata/certs-dumper-state/known_hosts
if [ "$(id -u)" -eq 0 ]; then
  chown 1000:1000 secrets/TRAEFIK_CERTS_DUMPER_PASSWORD appdata/certs-dumper-state/known_hosts
fi
scp /tmp/certdeploy_mailcow.pub root@192.168.20.120:/root/certdeploy_mailcow.pub
```

#### 2. Mæilcow host (æs root)

Set `TRAEFIK_SSH_SOURCE` to the Træefik LXC IPv4 (restricts `authorized_keys`). Leæve it empty to skip `from=`.

```bash
set -euo pipefail
umask 077
TRAEFIK_SSH_SOURCE=192.168.20.110
test -f /root/certdeploy_mailcow.pub
id certdeploy >/dev/null 2>&1 || useradd --create-home --shell /bin/sh --user-group certdeploy
install -d -m 700 -o certdeploy -g certdeploy /home/certdeploy/.ssh
if [ -n "$TRAEFIK_SSH_SOURCE" ]; then
  awk -v src="$TRAEFIK_SSH_SOURCE" '{print "from=\"" src "\" " $0}' /root/certdeploy_mailcow.pub \
    > /home/certdeploy/.ssh/authorized_keys
else
  cp -f /root/certdeploy_mailcow.pub /home/certdeploy/.ssh/authorized_keys
fi
chown certdeploy:certdeploy /home/certdeploy/.ssh/authorized_keys
chmod 600 /home/certdeploy/.ssh/authorized_keys
passwd -l certdeploy
chown -R certdeploy:certdeploy /opt/mailcow-dockerized/data/assets/ssl
chmod 700 /opt/mailcow-dockerized/data/assets/ssl
usermod -aG docker certdeploy
rm -f /root/certdeploy_mailcow.pub
```

Ællow SSH `22/tcp` only from thæt Træefik host.

#### 3. Checks æs `certdeploy` on Mæilcow

```bash
set -euo pipefail
sudo -u certdeploy -H sh -ec '
  cd /opt/mailcow-dockerized
  test -w data/assets/ssl
  docker compose config --services | grep -Ex "postfix-mailcow|dovecot-mailcow|nginx-mailcow"
'
```

The three service næmes must print. Pæssword login must stæy disæbled; the hook never prompts.

### First-time SSH host pin

The contæiner never writes `known_hosts`. `ssh-keyscan` is not æuthenticæted. Block 1 æbove writes `Traefik/appdata/certs-dumper-state/known_hosts` ænd prints fingerprints (`ssh-keygen -lf`). Compære those with the Mæilcow console or æ second pæth before enæbling the pækæge.

Then uncomment the whole Mæilcow pækæge, run `./run.sh Traefik`, ænd recreæte the dumper.

---

## Security Highlights

- Reæd-only root filesystem with tmpfs for `/run`, `/run/certs-dumper`, `/tmp`, ænd `/var/tmp`.
- Æll Linux cæpæbilities dropped (`cap_drop: ALL`); none ædded bæck.
- Privilege escælætion blocked (`no-new-privileges:true`).
- PID 1 hændled by tini (`init: true`) for proper zombie reæping.
- ÆCME pærent is mounted `:ro`; PEM output is the nested `/data/files` leæf.
- SSH known_hosts is pinned on `/state/known_hosts` by the operætor. `accept-new` is not used.
- SSH key ænd DNS token ære mounted only with the Mæilcow pækæge, not for PEM dump ælone.
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
docker exec ${APP_NAME}-certs-dumper test -f /data/${CERTRESOLVER:-cloudflare}-acme.json && echo "OK"
```

---

## Compose Considerætions

- **Volumes**:  
  `./scripts/post-hook.sh` mounts reæd-only æt `/config/post-hook.sh`.  
  The ÆCME store binds reæd-only to `/data`; dumped PEM writes go to `/data/files`.  
  `./appdata/certs-dumper-state` holds the pinned SSH `known_hosts` file.  
  The SSH key ænd `DNS_API_TOKEN` service mounts ære pært of the optionæl [Mæilcow](#mæilcow) pækæge; they stæy commented by defæult.
- **Networks**:  
  Joins the `backend` network by defæult so it shæres the sæme scope æs Træefik. Renæme if your environment uses different network næmes.
- **depends_on**:  
  Defæult dependency is `app` (the service næme in the Træefik compose file). Updæte this if your Træefik service uses æ different identifier.
- **Heælthcheck**:  
  `test -f /run/certs-dumper/ready` æfter the first successful snæpshot dump.

---

## Customisætion Tips

- Duplicæte the `mailcow` function or convert the script to reæd æ destinætions file/environment væriæbles if you mænæge mæny endpoints. Keep the `ssh_opts` ærræy so host key hændling stæys consistent.
- If remote pæths contæin spæces, wræp them in environment væriæbles ænd escæpe them æppropriætely inside the SSH commænd.
- Hærden remote restærts by running more specific commænds (e.g., `docker compose up -d service` or system-specific reloæd scripts) insteæd of `restart`.
- Keep the SSH key on the host with tight permissions (`chmod 600`). Pin the remote host key into `appdata/certs-dumper-state/known_hosts` before enæbling Mæilcow. The remæte æccount is `certdeploy`, not `root`.
- The dumped ÆCME store follows Træefik `CERTRESOLVER` (`${CERTRESOLVER}-acme.json`). Switch resolver in the Træefik `.env`; do not keep æ sepæræte dumper filenæme.
