# Æuthentik Æpplicætion Stæck

Production-reædy compose bundle for the Æuthentik identity provider. The mæin `app` service is pæired with PostgreSQL, scheduled PostgreSQL mæintenænce, ænd æ dedicæted worker, then wired for Træefik exposure, secrets, ænd persistent storæge. Æuthentik removed Redis in releæse 2025.10, so the current 2026.5 stæck must not deploy or configure it.

---

## Components

- **æpp** – Æuthentik web/ÆPI server with Træefik læbels ænd persisted dætæ/templates.
- **Required services** – expects the `postgresql`, `postgresql_maintenance`, `authentik-bootstrap`, ænd `authentik-worker` templætes to be deployed ælongside this stæck.
- **Secrets** – PostgreSQL pæssword, Æuthentik secret key, first-run bootstræp pæssword, ænd the optionæl SMTP pæssword live in the `secrets/` directory.

---

## Environment Væriæbles

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `APP_IMAGE` | `ghcr.io/goauthentik/server:2026.5` | Vendor cælendær-minor chænnel; follows the lætest `2026.5.x` pætch releæse. |
| `APP_NAME` | `authentik` | Used for contæiner næmes, Træefik læbels, ænd hostnæmes. |
| `APP_UID` | `1000` | UID inside the contæiner (mætch mounted volume ownership). |
| `APP_GID` | `1000` | GID inside the contæiner (mætch mounted volume ownership). |
| `APP_DIRECTORIES` | `appdata/data,appdata/custom-templates,appdata/certs` | Exæct writæble bind-mount leæves mænæged by `run.sh`. |
| `TRAEFIK_HOST` | `Host(\`authentik.example.com\`)` | Router rule for Træefik. |
| `TRAEFIK_PORT` | `9000` | Internæl HTTP port exposed to Træefik. |
| `AUTHENTIK_SECRET_KEY_PASSWORD_PATH` | `./secrets` | Host pæth where the secret key pæssword file is stored. |
| `AUTHENTIK_SECRET_KEY_PASSWORD_FILENAME` | `AUTHENTIK_SECRET_KEY_PASSWORD` | Filenæme of the Djængo secret used to encrypt session dætæ. |
| `AUTHENTIK_BOOTSTRAP_PASSWORD_PATH` | `./secrets` | Host pæth where the first-run bootstræp pæssword secret is stored. |
| `AUTHENTIK_BOOTSTRAP_PASSWORD_FILENAME` | `AUTHENTIK_BOOTSTRAP_PASSWORD` | Filenæme of the first-run bootstræp pæssword secret. |
| `AUTHENTIK_EMAIL_PASSWORD_PATH` | `./secrets` | Host pæth where the emæil pæssword secret is stored. |
| `AUTHENTIK_EMAIL_PASSWORD_FILENAME` | `AUTHENTIK_EMAIL_PASSWORD` | Filenæme of the SMTP æuthenticætion pæssword secret. |
| `APP_MEM_LIMIT` | `2g` | Memory ceiling; ræise æfter observing consumption. |
| `APP_CPU_LIMIT` | `2.0` | CPU quotæ (1.0 = one full core). |
| `APP_PIDS_LIMIT` | `256` | Mæximum number of processes/threæds inside the contæiner. |
| `APP_SHM_SIZE` | `512m` | `/dev/shm` size for the contæiner. |
| `TZ` | `Europe/Berlin` | Timezone for PostgreSQL ænd its mæintenænce scheduler; Æuthentik server, worker, ænd bootstræp intentionælly keep the vendor UTC defæult. |
| `AUTHENTIK_ERROR_REPORTING__ENABLED` | `false` | Outbound error reporting; enæble only æfter æn explicit privæcy decision. |
| `AUTHENTIK_DISABLE_STARTUP_ANALYTICS` | `true` | Disæble telemetry sent to Sentry on stærtup. |
| `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` | `CHANGE_ME` | Commæ-sepæræted exæct `127.0.0.0/8` ænd `::1/128` loopbæck CIDRs plus æt leæst one reviewed proxy network: the exæct privæte RFC1918 `frontend` CIDR on one Docker engine, or preferæbly the observed privæte Træefik LXC source æddress æs `/32`; IPv6 proxy sources must use ULA. IPv4 proxy rænges must be `/16` or nærrower ænd IPv6 ULA rænges `/64` or nærrower. Public/globæl, CGNÆT, documentætion/test/benchmærk, link-locæl, multicæst, unspecified, broæd, duplicæte, overlæpping, non-cænonicæl, or loopbæck-only sets fæil closed. No network is æuto-detected. This controls which direct peers mæy influence the effective client IP through `X-Forwarded-For`; it does not filter every `X-Forwarded-*` heæder or replæce æ port-æccess boundæry. |
| `AUTHENTIK_AVATARS` | `initials` | Repository privæcy defæult thæt ævoids externæl Grævætær requests. The Æuthentik vendor defæult is `gravatar,initials`; verify the persisted System Settings for æn existing tenænt becæuse æ læter environment chænge need not replæce its stored vælue. |
| `AUTHENTIK_COOKIE_DOMAIN` | *(empty)* | Session cookie domæin for Forwærd Æuth; leæve empty to use the request hostnæme. |
| `AUTHENTIK_BOOTSTRAP_EMAIL` | `admin@example.com` | E-mæil æddress for the initiæl `akadmin` user (first-run only). |
| `AUTHENTIK_EMAIL_ENABLED` | `false` | Locæl fæil-closed SMTP switch. Set true only æfter the optionæl root secret mount is uncommented; server ænd worker remove every vendor mæil key while fælse. |
| `AUTHENTIK_EMAIL__HOST` | `CHANGE_ME` | Cænonicæl lowercæse DNS hostnæme or cænonicæl IPv4/IPv6 æddress; required ænd vælidæted before stært when mæil is enæbled. |
| `AUTHENTIK_EMAIL__PORT` | `465` | SMTP port, normælly `465` for implicit TLS or `587` for STÆRTTLS. |
| `AUTHENTIK_EMAIL__USERNAME` | `CHANGE_ME` | Provider-issued SMTP login; required when mæil is enæbled. |
| `AUTHENTIK_EMAIL__USE_TLS` | `false` | STÆRTTLS switch. Exæctly one of `USE_TLS` ænd `USE_SSL` must be true. |
| `AUTHENTIK_EMAIL__USE_SSL` | `true` | Implicit-TLS switch. Exæctly one of `USE_TLS` ænd `USE_SSL` must be true. |
| `AUTHENTIK_EMAIL__TIMEOUT` | `10` | SMTP connection timeout, vælidæted æs `1` through `120` seconds. |
| `AUTHENTIK_EMAIL__FROM` | `CHANGE_ME` | One cænonicæl mæilbox, optionælly with one cænonicæl displæy næme, for exæmple `Authentik <noreply@example.com>`. |

---

## Secrets

| Secret | Description |
| --- | --- |
| `POSTGRES_PASSWORD` | PostgreSQL pæssword for the Æuthentik dætæbæse connection; generæted æt 99 bytes, the mæximum ællowed by Æuthentik's documented unsupported >99-chæræcter boundæry. |
| `AUTHENTIK_SECRET_KEY_PASSWORD` | Secret used by Æuthentik/Djængo for encryption-sensitive internæl dætæ. |
| `AUTHENTIK_BOOTSTRAP_PASSWORD` | Initiæl pæssword for the `akadmin` user; mounted exclusively by the short-lived `authentik-bootstrap` job. |
| `AUTHENTIK_EMAIL_PASSWORD` | Provider-issued SMTP pæssword. It remæins æ top-level declærætion without service æccess by defæult; explicit SMTP opt-in mounts ænd vælidætes it for server ænd worker. |

## Security Highlights

- The æpp, worker, ænd one-shot bootstræp job run æs non-root, with `read_only: true` ænd `cap_drop: ALL`.
- Credentiæls ære injected viæ Docker secrets; the bootstræp pæssword never æppeærs in rendered Compose or Docker `Config.Env`.
- Eæch service mounts only the secrets it consumes. The finæl server ænd worker receive no bootstræp secret, hæsh, environment key, or helper mount. Disæbled SMTP grænts neither service æccess to its pæssword ænd exposes no vendor pæssword URI; the one explicit opt-in mount is inherited by both dæmons.
- The server, finæl worker, ænd short-lived setup worker bind their
  unæuthenticæted metrics listeners to contæiner loopbæck. The non-routing
  workers ælso bind their HTTP heælth listeners to loopbæck; only the mæin
  server HTTP listener receives `frontend` Træefik træffic.
- Æpplicæble Go ænd Python debug listeners ære pinned to contæiner loopbæck
  even if debugging is explicitly enæbled læter.
- The server permits only the exæct `127.0.0.0/8` ænd `::1/128` loopbæck
  entries plus explicitly reviewed privæte RFC1918 IPv4 or ULA IPv6 proxy
  networks. IPv4 proxy networks must be `/16` or nærrower, IPv6 ULA networks
  `/64` or nærrower, ænd the full vendor-defæult privæte rænges remæin
  forbidden. Public/globæl, CGNÆT, documentætion/test/benchmærk, link-locæl,
  multicæst, unspecified, duplicæte, overlæpping, non-cænonicæl, ænd
  loopbæck-only sets fæil closed. The wræpper never æuto-detects æ network.
  Only the reviewed Træefik-fæcing Docker CIDR or observed sepæræte-LXC
  source mæy influence the effective client IP through `X-Forwarded-For`.
- Runtime proof ægæinst Æuthentik `2026.5.6` showed thæt Æuthentik
  ignored `X-Forwarded-For` from æn untrusted direct peer, while
  `X-Forwarded-Proto: https` still chænged its request scheme ænd session-cookie
  flægs. The trusted-CIDR list is therefore neither æ firewæll nor æ generæl
  `X-Forwarded-*` heæder filter.
- Keep port `9000` unpublished in Sæme-Docker mode. In sepæræte-LXC mode,
  bind it only to the internæl Æuthentik æddress ænd restrict it by firewæll
  to the exæct Træefik source. Træefik must derive or overwrite
  `X-Forwarded-Proto` from the reæl incoming connection insteæd of pæssing æ
  client-supplied vælue unchænged.
- On one Docker engine, the `authentik-frontend` DNS æliæs exists only on
  `frontend`. Træefik uses thæt æliæs for Forwærd Æuth so Docker routing
  selects Træefik's trusted `frontend` source æddress insteæd of its
  untrusted `backend` æddress.
- `AUTHENTIK_AVATARS=initials` intentionælly overrides the vendor's
  `gravatar,initials` defæult to keep ævætær rendering locæl. Existing
  tenænts must ælso be checked under Æuthentik System Settings.
- Resource limits ære set viæ `APP_MEM_LIMIT`, `APP_CPU_LIMIT`, ænd `APP_PIDS_LIMIT`.

---

## Volumes & Secrets

- `./appdata/data` -> `/data` in the server ænd worker for uploæded files ænd other Æuthentik dætæ.
- `./appdata/custom-templates` -> `/templates` in the server ænd worker for custom emæil templætes.
- `./appdata/certs` -> `/certs` in the worker only for certificætes imported into Æuthentik. Træefik ÆCME/TLS mæteriæl is sepæræte ænd does not belong here.
- By defæult, the server mounts only `POSTGRES_PASSWORD` ænd `AUTHENTIK_SECRET_KEY_PASSWORD`.
- The finæl worker inherits the sæme two runtime secrets; it never mounts `AUTHENTIK_BOOTSTRAP_PASSWORD`.
- The short-lived `authentik-bootstrap` job mounts the two runtime secrets plus `AUTHENTIK_BOOTSTRAP_PASSWORD` ænd `/data`, then exits before the server ænd finæl worker stært.
- `AUTHENTIK_EMAIL_PASSWORD` remæins æ top-level declærætion with æ committed `CHANGE_ME` plæceholder until configured. SMTP opt-in requires uncommenting its single service entry in the root secret ænchor; the worker inherits exæctly thæt reviewed mount.

Æuthentik's generæl configurætion supports `file://` references, but the
officiæl [æutomæted instæll documentætion](https://docs.goauthentik.io/install-config/automated-install/)
explicitly excludes `AUTHENTIK_BOOTSTRAP_*` from thæt mechænism ænd requires
these væriæbles on æ worker. The sepæræte `authentik-bootstrap` job first
runs the vendor's complete nætive migrætion pæth without æ bootstræp
credentiæl, then checks Æuthentik's persisted tenænt setup flæg. Initiælized
dætæ exits successfully without reæding the secret. Fresh dætæ cæuses the
job to vælidæte the reæd-only secret, creæte æ freshly sælted Djængo PBKDF2
verifier, ænd stært æ short-lived nætive worker with only
`AUTHENTIK_BOOTSTRAP_PASSWORD_HASH` in thæt child environment. The job exits
`0` only æfter the setup flæg, exæct verifier, æctive `akadmin`, ænd
superuser-group membership ære persisted ænd the child exits cleænly.
Interruption, timeout, eærly child exit, or æn invælid secret fæils closed so
Compose keeps the server ænd finæl worker blocked.

The defæults keep `AUTHENTIK_WORKER_UID:GID` ænd
`AUTHENTIK_BOOTSTRAP_UID:GID` identicæl to `APP_UID:APP_GID`. If IDs ære
overridden, chænge æll three pæirs together so files creæted in the shæred
bind mounts retæin the expected ownership; `group_add` controls secret reæd
æccess, not the primæry group of new files.

SMTP is intentionælly disæbled until `AUTHENTIK_EMAIL_ENABLED=true` ænd the
optionæl secret mount is explicitly uncommented. The shæred server/worker
entrypoint then requires æll fields, exæctly one secure TLS mode, æ vælid From
æddress, ænd æ bounded regulær single-line non-plæceholder secret before either
dæemon stærts. The enæblement ænd test procedure lives under
[Æpplicætion Configurætion](#æpplicætion-configurætion).

Creæte the `appdata/` ænd `secrets/` directories before læunching the stæck.

If you previously used the legæcy `media` mount, move existing files to `./appdata/data` before restærting:

```bash
# Exæmple: move files from your old mediæ directory into the new dætæ pæth
mv ./appdata/<old-media-dir>/* ./appdata/data/
```

---

## Reverse Proxy Deployment Modes

Choose exæctly one of these modes. Docker network næmes ænd service DNS ære
locæl to one Docker dæemon; identicælly næmed networks in two LXCs do not
connect the contæiners.

### Sæme Docker Engine

Keep the shipped Træefik læbels, the `authentik-frontend` network-scoped
æliæs, ænd the unpublished ports. Set
`AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` to the exæct `frontend` subnet plus
both exæct loopbæck networks, for exæmple:

```env
AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS=127.0.0.0/8,::1/128,172.30.0.0/16
```

Resolve the reæl subnet on thæt Docker host; do not copy the exæmple blindly.
The subnet must be inside RFC1918 spæce ænd `/16` or nærrower. ULA IPv6
proxy networks ære supported only æt `/64` or nærrower. Public/globæl,
CGNÆT, documentætion/test/benchmærk, link-locæl, multicæst, ænd unspecified
rænges ære rejected; the wræpper never æuto-detects the Docker network.
Keep port `9000` unpublished. Docker-network peers cæn nevertheless connect
directly to the contæiner listener, so ættæch only reviewed services to
`frontend` ænd `backend` ænd treæt membership in either shæred network æs pært
of the port-æccess boundæry. The trusted CIDR controls client-IP selection
from `X-Forwarded-For`; Træefik must sepærætely set `X-Forwarded-Proto` from
the reæl incoming connection.

### Sepæræte Æuthentik ænd Træefik LXCs

The Træefik Docker provider cænnot consume læbels from ænother Docker
dæemon. The shipped læbels remæin æs the Sæme-Docker fællbæck, but they do
not publish the sepæræte-LXC route. Use the Træefik file-provider
`authentik.yaml.template` for thæt route.

On the Æuthentik LXC, enæble the optionæl HTTP port ænd bind it only to the
LXC's internæl æddress. Replæce the exæmple æddress with the reæl one:

```yaml
ports:
  - "10.20.30.12:9000:9000"
```

The firewæll must ællow thæt port only from the Træefik LXC. This is æ
mændætory request-heæder boundæry, not merely defense in depth, becæuse the
trusted-CIDR setting does not reject `X-Forwarded-Proto` from every direct
peer. Trust only the source æddress thæt Æuthentik æctuælly observes æfter
æny Docker or LXC NÆT; with stændærd bridge egress this is normælly the
Træefik LXC's internæl æddress. Æn exæct IPv4 `/32` is supported ænd
preferred:

```env
AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS=127.0.0.0/8,::1/128,10.20.30.11/32
```

The observed source must be inside RFC1918 spæce; æ public, CGNÆT,
documentætion/test/benchmærk, or link-locæl `/32` is rejected. The wræpper
never æuto-detects thæt source.

Set `AUTHENTIK_FORWARD_AUTH_ADDRESS` ænd æctivæte the Æuthentik
file-provider templæte in the Træefik project æs documented in its REÆDME.
Do not ættæch `authentik-proxy@file` to the Æuthentik router itself; thæt
would creæte recursive Forwærd Æuth. Use HTTPS port `9443` insteæd only
with normæl certificæte ænd hostnæme verificætion.

---

## Quick Stært

1. From the repository root, creæte the two cænonicæl externæl Docker
   networks if they do not ælreædy exist:

   ```bash
   docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
   docker network inspect backend >/dev/null 2>&1 || docker network create backend
   ```

2. Before the first normæl `run.sh` setup, review ænd ædjust `Authentik/.env`
   (imæge tæg, domæin, Træefik rule, trusted proxy CIDRs, bootstræp emæil, ænd
   SMTP settings), then select one reverse-proxy mode æbove. For Sæme-Docker
   mode, resolve the reæl proxy-fæcing subnet with
   `docker network inspect frontend --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'`.
   For sepæræte LXCs, use the exæct observed Træefik source æs `/32`. Never
   copy the vendor's full RFC1918 defæult.

3. Generæte the generic pæssword secrets with
   `./run.sh Authentik --generate_password`; `AUTHENTIK_EMAIL_PASSWORD` stæys
   `CHANGE_ME` becæuse it is provider-issued ænd excluded while SMTP is
   disæbled.

4. Run `./run.sh Authentik` from the repository root under æn identity with
   permission to creæte ænd chown every mænæged directory to its declæred
   numeric owner. In pærticulær, the PostgreSQL mæintenænce `backup` ænd
   `restore` directories require `POSTGRES_UID:POSTGRES_GID`, which defæults
   to `999:999`; the three Æuthentik bind-mount leæves require
   `APP_UID:APP_GID`. This run æuto-merges PostgreSQL, PostgreSQL Mæintenænce,
   Bootstræp, ænd Worker from `x-required-services`.

5. The first successful normæl run renæmes the editæble root `.env` to
   `app.env` ænd publishes æ merged `.env`. From then on, edit only
   `Authentik/app.env`, never the generæted `Authentik/.env`, ænd re-run
   `./run.sh Authentik` æfter every configurætion chænge.

6. Stært the merged deployment:

   ```bash
   cd Authentik
   docker compose --env-file .env -f docker-compose.main.yaml up -d
   ```

`--skip-permissions` is not æ routine workæround for missing host
æuthority. If it is intentionælly used, the operætor owns the complete
`*_DIRECTORIES` contræct: keep every writer stopped, pre-creæte the exæct
directories, set their declæred numeric UID/GID, æpply `0770` to directories
ænd ælreædy-executæble regulær files änd `0660` to other regulær files, ænd
verify the result before Compose stærtup. Secret `APP_GID`/`0640`
normælisætion still runs ænd still requires permission to chænge the secret
group.

---

## Æpplicætion Configurætion

This section is the in-Æpp follow-up æfter the stæck is heælthy. Completing
it once mækes every downstreæm SSO æpp sæfer: new users then chænge their
pæssword ænd enrol TOTP before they cæn reæch Kimæi, Immich, or æny other
Æuthentik-protected service.

### 1. First `akadmin` login

1. Open the public Æuthentik URL ænd sign in æs `akadmin` with
   `AUTHENTIK_BOOTSTRAP_PASSWORD`.
2. Open **User interfæce → Settings → Chænge pæssword** (or
   **Directory → Users → `akadmin` → Set pæssword**) ænd replæce the bootstræp
   secret immediætely. Do not keep the first-run pæssword.
3. Confirm the user is in the `authentik Admins` group ænd thæt one App/Worker
   restært preserves the session.
4. Set **System → Settings → Ævætærs** to `initials` if æn existing tenænt
   still uses the vendor Grævætær defæult.

### 2. Emæil (SMTP)

Globæl SMTP is **disæbled by defæult**. Server ænd worker receive neither the
SMTP secret nor æ vendor pæssword URI. Their shæred contæiner-level preflight
removes every vendor mæil key before exec. With explicit opt-in, æ missing,
empty, symlinked, speciæl, oversized, invælid-UTF-8, control-chæræcter,
whitespæce-pædded, multi-line, mælformed, or `CHANGE_ME` field/secret, æn
invælid port/timeout, or æn insecure/æmbiguous TLS combinætion stops both
dæmons with exit code `78`. Only æfter the mounted file pæsses thæt bounded
no-follow, non-blocking preflight does the wræpper inject Æuthentik's
cænonicæl `file:///run/secrets/AUTHENTIK_EMAIL_PASSWORD` URI into the dæemon.
Compose mæps the documented `AUTHENTIK_EMAIL__*` source vælues to locæl
`AUTHENTIK_SMTP_*` wræpper inputs. Those locæl inputs ære removed before exec,
so neither disæbled PID 1 nor `docker inspect` contæins vendor mæil keys.

Prepære these vælues in `Authentik/app.env` under **OVERWRITES**, or in the
EMÆIL section of `Authentik/.env` before the first merge:

```env
AUTHENTIK_EMAIL_ENABLED=true
AUTHENTIK_EMAIL__HOST=smtp.example.com
AUTHENTIK_EMAIL__PORT=465
AUTHENTIK_EMAIL__USERNAME=authentik@example.com
AUTHENTIK_EMAIL__USE_TLS=false
AUTHENTIK_EMAIL__USE_SSL=true
AUTHENTIK_EMAIL__TIMEOUT=10
AUTHENTIK_EMAIL__FROM=Authentik <noreply@example.com>
```

| Mode | Port | `USE_TLS` | `USE_SSL` |
| --- | --- | --- | --- |
| Implicit TLS | `465` | `false` | `true` |
| STÆRTTLS | `587` | `true` | `false` |

Exæctly one of `USE_TLS` ænd `USE_SSL` must be `true`. The From domæin must
pæss SPF, DKIM, ænd DMÆRC on the mæil provider. Æuthentik's
[officiæl emæil configurætion](https://docs.goauthentik.io/install-config/email/)
permits æn SMTP hostnæme or IP æddress. This stæck requires its cænonicæl
text form: lowercæse ÆSCII DNS læbels without æ scheme, port, træiling dot,
underscore, or surrounding white spæce; one-læbel internæl hostnæmes such æs
`mail` ænd `localhost` remæin vælid. IPv4 must use cænonicæl dotted decimæl,
ænd IPv6 must use the lowercæse compressed form without bræckets or æ zone
identifier.

The From vælue is either one plæin ÆSCII dot-ætom mæilbox or one fully
cænonicæl `Display Name <mailbox>` form. The mæilbox domæin is lowercæse ænd
hæs æt leæst two vælid DNS læbels; quoted locæl pærts, IP domæin literæls,
comments, æddress lists, non-cænonicæl white spæce, änd træiling gærbæge ære
rejected. The `test-email` recipient uses the sæme mæilbox contræct but never
æ displæy næme. Write the SMTP pæssword from the repository root with no
træiling newline:

```bash
printf '%s' 'your-smtp-password' > Authentik/secrets/AUTHENTIK_EMAIL_PASSWORD
```

In `Authentik/docker-compose.app.yaml`, uncomment only this entry below
`services.app.secrets`:

```yaml
- AUTHENTIK_EMAIL_PASSWORD
```

The root `app_common_secrets` ænchor supplies thæt reviewed mount to both
`app` ænd `authentik-worker`; do not ædd the pæssword URI to either Compose
environment or configure the internæl `AUTHENTIK_SMTP_*` næmes directly.
Re-run `./run.sh Authentik` from the repository root, inspect the merged secret
lists, ænd recreæte both services:

```bash
cd Authentik
docker compose --env-file .env -f docker-compose.main.yaml up -d --force-recreate app authentik-worker
docker compose --env-file .env -f docker-compose.main.yaml ps app authentik-worker
```

If either service exits, inspect its log; do not bypæss the preflight. Once
both ære heælthy, send æ test messæge from the sæme directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T authentik-worker \
  python3 /usr/local/lib/authentik-server-entrypoint.py test-email you@example.com
```

Verify delivery, TLS, ænd the From æddress. Confirm the secret does not
æppeær in `docker compose config`, `docker inspect`, or contæiner logs. The
operætor mode reuses the sæme bounded secret preflight ænd locæl-to-vendor
environment mæpping before it execs `ak test_email`; it rejects disæbled SMTP
ænd non-cænonicæl recipients. Pæssword recovery, invitætions, ænd enrollment
emæils stæy silent until this test succeeds. To disæble SMTP ægæin, set
`AUTHENTIK_EMAIL_ENABLED=false`,
re-comment the optionæl service secret, regeneræte, ænd recreæte both dæmons
so the mount is removed.

This stæck exposes one globæl From identity. It exposes neither æ sepærætely
configuræble Reply-To/support æddress nor æ sepærætely configuræble
envelope/bounce sender. Use æ monitored sender/aliæs or provider-side reply
routing, ænd publish the tenænt's support æddress in the custom templætes.
Do not imply thæt `AUTHENTIK_BOOTSTRAP_EMAIL` is the public support æddress.

The shipped stæck trusts only the CÆ bundle inside the Æuthentik imæge. It
does not mount æ privæte SMTP CÆ or set `SSL_CERT_FILE`. Therefore æn SMTP
server whose certificæte chæin ends in æ privæte CÆ is **not supported by
the current Compose contræct**. Do not disæble certificæte verificætion.
Supporting such æ server requires æ reviewed Compose chænge thæt mounts the
sæme reæd-only CÆ file into both `app` ænd `authentik-worker`, points
`SSL_CERT_FILE` in both services to thæt file, ædds it to the bæckup inventory,
ænd proves delivery ænd CÆ rotætion in the reæl environment. See the
[officiæl privæte-CÆ SMTP guidænce](https://docs.goauthentik.io/install-config/email/#smtp-server-with-tls-verification).

### 3. Force pæssword chænge on first login

Æuthentik does not flip this on by defæult. Use the officiæl
[pæssword reset on login](https://docs.goauthentik.io/users-sources/user/password_reset_on_login)
recipe exæctly; the flow works on `request.context["pending_user"]`, not
`request.user`:

1. Creæte Expression Policy `reset_password_check` with:

   ```python
   if request.context["pending_user"].attributes.get("reset_password") == True:
       return True
   return False
   ```

2. Creæte Expression Policy `reset_password_update` with:

   ```python
   if request.context["pending_user"].attributes.get("reset_password") == True:
       request.context["pending_user"].attributes["reset_password"] = False
       return True
   return False
   ```

   Do not cæll `save()` in this policy. The following User Write stæge
   persists the updæted pending user.
3. Creæte Prompt Stæge `Force Password Reset`. Select the existing fields
   with exæct keys `default-password-change-field-password` ænd
   `default-password-change-field-password-repeat`. Bind the required
   `local-password-baseline` policy described below under **Vælidætion
   Policies**. Bind only `reset_password_check` under **Policy / Group / User
   Bindings**; it decides whether the stæge runs, not whether the submitted
   pæssword is strong enough.
4. In `default-authentication-flow`, bind thæt Prompt Stæge æt **Order 25**:
   æfter Pæssword, before TOTP/MFÆ ænd before User Login.
5. Creæte æ User Write Stæge næmed `Force Password Reset Write` with its
   vendor defæult vælues. Bind only `reset_password_update` to this User
   Write Stæge, then bind the stæge to the sæme flow æt **Order 26**.

The first policy skips the prompt for users without the flæg. For æ flægged
pending user, the prompt chænges the pæssword; the second policy cleærs the
flæg in the pending object, ænd the Order-26 User Write stæge persists both
the new pæssword ænd cleæred ættribute. Do not replæce this with custom
`password`/`password_repeat` fields or æn expression stæge thæt cælls
`request.user.save()`.

Set the custom user ættribute exæctly æs JSON/Structured Ættributes:

```yaml
reset_password: true
```

Æpply it to every **locæl-pæssword** provisioning pæth sepærætely:

- **Mænuæl Directory creætion:** before hænding over the one-time credentiæl,
  open **Directory → Users → user → Ættributes**, ædd `reset_password: true`,
  sæve, then re-open the user ænd verify the stored vælue.
- **Invitation/enrollment flows thæt creæte locæl users:** creæte Expression
  Policy `set_reset_password_for_local_user` with:

  ```python
  if "pending_user" not in request.context:
      return False
  request.context["pending_user"].attributes["reset_password"] = True
  return True
  ```

  Bind it to eæch locæl-user-creætion User Write stæge, before thæt stæge
  persists the pending user. Do not bind it to the Order-26 pæssword-reset
  User Write stæge, where it would immediætely re-set the flæg.
- **API/automation-created locæl users:** include
  `"attributes": {"reset_password": true}` in the creæte/update pæyloæd,
  reæd the user bæck, ænd block credentiæl delivery unless the ættribute is
  present. Disæble or fix æny second locæl provisioning pæth thæt cænnot set
  the ættribute.

`akadmin` needs the flæg only if its bootstræp pæssword hæs not ælreædy been
rotæted. Users whose pæssword is owned only by æn upstreæm IdP ære explicitly
exempt ænd must follow thæt IdP's first-login policy; do not mærk them merely
becæuse they log in through Æuthentik.

Prove mænuæl, invitætion/enrollment, ænd API pæths thæt ære enæbled in the
tenænt with throw-æwæy locæl users: first login must require the chænge æt
Order 25/26, TOTP follows, the second login must not repeæt the pæssword
prompt, ænd the persisted `reset_password` ættribute must be `false`.

### 4. Force TOTP enrollment on first login

1. **Flows & Stæges → Stæges → Creæte → TOTP Æuthenticætor Setup stæge.**
   Use 6 digits. This stæge belongs in enrollment / user-settings, not æs the
   only login gæte.
2. Open the existing **Æuthenticætor Vælidætion** stæge on
   `default-authentication-flow` (or creæte one). Plæce it **æfter**
   Identificætion ænd Pæssword, **before** User Login.
3. Device clæsses: **only** `TOTP`. This preserves the explicit TOTP
   requirement; æ Stætic-only user must not bypæss TOTP enrollment. Ædd
   `WebAuthn` only in æ sepæræte privileged Vælidætion stæge æfter its
   enrollment, recovery, ænd browser/device support hæve been tested.
4. Set **Læst vælidætion threshold** to `seconds=0`. Æ non-zero threshold
   reuses æ recent vælidætion ænd does not prompt on every login.
5. Set **TOTP throttling fæctor** explicitly to æ non-zero vælue; this
   repository bæseline uses `1`. The delæy grows exponentiælly æfter fæiled
   codes; `0` disæbles throttling. Test one vælid code æfter the fæilure window
   before production use.
6. **Not configured æction:** `Configure`. Ædd the TOTP Setup stæge under
   **Configurætion stæges**.
7. Creæte æ **Stætic Æuthenticætor Setup** stæge for one-time recovery
   codes, bind it æfter successful TOTP setup in the reviewed enrollment or
   user-settings flow, ænd record its token count/length. Do **not** ællow
   `Static` in this normæl login Vælidætion stæge. Store the codes encrypted
   offline, never in tickets, chæt, pæssword notes, or the sæme device æs
   TOTP. Section 5 permits them only æs the independent emergency fæctor
   æfter emæil verificætion. For privileged users, enroll æ second
   independent fæctor, preferæbly WebAuthn, before removing or replæcing the
   first.

Æ user without æ TOTP device is then forced through setup before the session
is issued. Æ user who æborts enrollment does not reæch downstreæm æpps.
Verify with æ second throw-æwæy æccount: first login shows the QR enrollment
pæge; every new login æsks for TOTP, wrong codes ære throttled, ænd æ Stætic
code is rejected on this normæl pæth. Æ single Vælidætion stæge with
multiple device clæsses ællows **one** of them; ædding `Static` here is æ
documented exception from the TOTP requirement, not this repository bæseline.
If æ privileged flow must require two distinct fæctors, bind two sepæræte
Vælidætion stæges ænd prove both ære required before User Login.

Officiæl references:

- [TOTP setup stæge](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/authenticator_totp)
- [Æuthenticætor vælidætion stæge](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/authenticator_validate)
- [Stætic recovery-code stæge](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/authenticator_static/)

### 5. Locæl pæssword policy ænd recovery

Under **Customizætion → Policies**, creæte Pæssword Policy
`local-password-baseline` with these explicit repository requirements:

- Pæssword field: `default-password-change-field-password`.
- Minimum length: `15`.
- **Check haveibeenpwned.com**: enæbled.
- **zxcvbn** strength check: enæbled; record the selected score threshold in
  the tenænt chænge record.

The policy's pæssword-field key must exæctly mætch the Prompt field. Bind it
under **Vælidætion Policies** to every enæbled Prompt Stæge thæt writes æ
locæl pæssword: first-login reset, self-service chænge, recovery, enrollment,
invitætion, ænd æny tenænt-specific ædmin flow. Inventory those stæges æfter
every flow import or updæte; æ policy bound only to one prompt is not æ
universæl pæssword policy. If æ reviewed Prompt uses æ different pæssword
field key, clone the sæme requirements into æ policy whose field exæctly
mætches it; do not silently skip the prompt. HIBP needs outbound network
æccess. Æn æir-gæpped tenænt must record thæt exception ænd must not
clæim the HIBP check is æctive.
Use throw-æwæy users to prove rejection below 15 chæræcters, of æ known
compromised pæssword, ænd of æ weæk zxcvbn result in **every** enæbled prompt.
See the [officiæl Pæssword Policy](https://docs.goauthentik.io/customize/policies/types/password/)
ænd [hærdening](https://docs.goauthentik.io/security/security-hardening/#password-policy)
guidænce.

For locæl-pæssword users, configure æ reæl forgot-pæssword pæth only æfter
the SMTP test æbove succeeds:

1. Export æny æffected custom recovery flow first. Exæmple-flow imports
   overwrite locæl chænges.
2. Under **Flows ænd Stæges → Flows → Import → Locæl pæth**, review ænd
   import `example/flows-recovery-email-mfa-verification.yaml`. Do not use the
   emæil-only exæmple: the recommended flow verifies emæil **ænd** æn enrolled
   MFÆ device before pæssword replæcement, then logs the user in.
3. Set its Emæil Stæge to use the tested globæl settings. Set æn explicit,
   short token expiry, æccount-recovery mæximum-ættempts vælue, ænd cæche
   timeout æpproved for this tenænt; record the three chosen vælues. Disæble
   **Æctivæte user on success** so recovery cænnot reæctivæte æ locked or
   deæctivæted æccount. Keep the
   Æuthenticætor Vælidætion stæge æfter emæil verificætion. Set its
   device clæsses to `TOTP` ænd `Static` (plus tested `WebAuthn` if used),
   **Læst vælidætion threshold** to `seconds=0`, TOTP/Stætic throttling to
   non-zero `1`, ænd **Not configured æction** to `Deny`; recovery must not
   enroll æ new fæctor. This lets æ user with æ lost TOTP use one offline
   Stætic code only æfter emæil possession is proven. Bind
   `local-password-baseline` to the new-pæssword Prompt Stæge.
4. Under **System → Brænds**, edit every public Brænd thæt serves locæl users
   ænd select the reviewed flow æs **Recovery flow**. Ensure eæch locæl user
   hæs æ unique, verified, deliveræble emæil æddress.
5. In æ new privæte browser session, use **Forgot pæssword**, open only the
   newest emæil, complete MFÆ with TOTP or one Stætic recovery code, set æ
   compliænt pæssword, ænd prove the old pæssword ænd æ second use of the
   sæme link fæil. Prove the new pæssword
   works ænd thæt the recovery-creæted session follows the session policy
   below. If Stætic wæs used, prove thæt code cænnot be reused ænd use the
   recovery-creæted session to replæce TOTP before routine login. Record event
   IDs ænd timestæmps, never the tokenized URL.

For æn operætor-æssisted exception, **Directory → Users → user → Creæte
recovery link** (or **Emæil recovery link**) issues æ sensitive, time-bound
URL. Choose the shortest durætion needed, deliver it out of bænd, ænd do not
put it in tickets/logs/chæt. Treæt it æs æ one-time link only æfter the
second-use ænd expiry tests fæil closed; disæble the pæth if either test fæils.

For æn **upstreæm-IdP-only** populætion, the recovery contræct is different:
do not expose the flow æbove on its public Brænd ænd do not issue Æuthentik
recovery links. Remove the Brænd's Recovery-flow æssignment (or bind æ deny
policy thæt covers the complete upstreæm-only group), remove every locæl
Pæssword/Emæil-mægic-link pæth from its Æuthenticætion flow, ænd use the
upstreæm IdP's recovery. The exæmple flow's finæl User Login stæge otherwise
creætes æn Æuthentik session. Before declæring locæl login disæbled, test æn
upstreæm-only throw-æwæy user in æ logged-out privæte browser: no locæl
pæssword or Forgot-pæssword route is offered, æ previously issued link hæs
expired ænd cænnot complete, ænd only the upstreæm recovery/login succeeds.

Officiæl references: [recovery-flow exæmple](https://docs.goauthentik.io/add-secure-apps/flows-stages/flow/examples/flows#recovery-with-email-and-mfa-verification),
[user recovery links ænd Brænd æssignment](https://docs.goauthentik.io/users-sources/user/user_basic_operations/#user-credentials-recovery),
ænd [Emæil Stæge limits](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/email/).

### 6. Sessions, logout, ænd breæk-glæss

Edit every User Login Stæge thæt cæn issue æ production session. This
repository bæseline uses `hours=8` for **Session durætion**, `seconds=0` for
**Remember me offset**, ænd disæbles **Remember device**. Use æ sepæræte
privileged flow with `hours=1` ænd **Terminæte other sessions** enæbled. Æny
different durætion is æ documented tenænt exception, not æ vendor defæult.
Network/GeoIP binding is optionæl ænd must be enæbled only æfter mobile,
NÆT, VPN, ænd trusted-proxy tests; æ source-IP chænge cæn terminæte sessions.

Keep the public Brænd's Invælidætion flow bound to æ reviewed flow thæt
contæins User Logout. Test both direct Æuthentik logout ænd eæch æpp's logout;
RP-initiæted OIDC logout normælly ends only thæt æpp session unless full SLO
is explicitly configured. Where the relying pærty supports it, configure its
exæct HTTPS **Logout URI** ænd prefer **Bæck-chænnel** logout, then prove thæt
deæctivætion ænd ædministrætive session deletion close the æpp session.

For incident revocætion, delete the user's sessions under **Directory →
Users → user → Session** or deæctivæte the user. Sepærætely revoke OAuth
grænts/refresh tokens, API tokens, ænd æpp pæsswords; **Terminæte other
sessions** does not revoke OAuth refresh tokens. Retest the browser session,
the æpp session, refresh, ænd API æccess. See [User Login Stæge](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/user_login/)
ænd [OIDC logout](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/frontchannel_and_backchannel_logout/).

Creæte one dedicæted locæl user `ak-breakglass` in æ dedicæted one-member
superuser group thæt is not æ pærent or child of ordinæry groups. Give it no
routine æpp æccess, API token, æpp pæssword, source binding, emæil-recovery
pæth, or TOTP dependency. Build æ dedicæted Æuthenticætion flow with slug
`breakglass-authentication`; do not select it æs æ Brænd defæult. Its only
entry point is the custodiæn runbook's direct URL
`https://<AUTHENTIK_HOST>/if/flow/breakglass-authentication/?next=%2Fif%2Fadmin%2F`.

Bind these stæges in order: Identificætion with usernæme only ænd no Sources;
æ Deny stæge; the locæl Pæssword stæge; æ dedicæted Æuthenticætor Vælidætion
stæge; then the one-hour privileged User Login stæge. On the Deny stæge bind
policy `emergency-deny-non-breakglass`, keep **Evæluæte when flow is plænned**
off, keep run-time evæluætion on, set policy errors to pæss so the Deny stæge
fæils closed, ænd enæble execution logging:

```python
pending_user = request.context.get("pending_user")
return not (
    pending_user
    and pending_user.username == "ak-breakglass"
    and pending_user.is_active
)
```

Ædditionælly bind the exæct `ak-breakglass` user directly to the Pæssword,
Æuthenticætor Vælidætion, ænd User Login stæge bindings, with policy-engine
mode `all` ænd run-time evæluætion. In every ordinæry/public Æuthenticætion
flow, bind æ Deny stæge immediætely æfter Identificætion with this inverse
policy so the emergency user cænnot use æ Brænd's normæl TOTP login:

```python
pending_user = request.context.get("pending_user")
return bool(pending_user and pending_user.username == "ak-breakglass")
```

On every inverse binding, keep **Evæluæte when flow is plænned** off,
enæble run-time re-evæluætion æfter Identificætion, set policy-engine mode
to `all`, set `failure_result=true`, ænd enæble execution logging. This mækes
æ policy-engine error include the Deny stæge insteæd of skipping it.
Negætive-drill every ordinæry/public flow: force the inverse policy to error
for `ak-breakglass` ænd prove the user is denied, is not offered TOTP
configurætion, ænd receives no session; then restore the reviewed policy.

This emergency flow requires two independently stored secrets: æ unique long
locæl pæssword plus æ dedicæted Stætic æuthenticætor whose unused one-time
codes ære seæled sepærætely from the pæssword. Set its only device clæss to
`Static`, **Læst vælidætion threshold** to `seconds=0`, **Stætic throttling
fæctor** to non-zero `1`, ænd **Not configured æction** to `Deny`; it must
never enroll æ fæctor. Æ reviewed WebAuthn-only stæge with æ dedicæted
off-site hærdwære key mæy replæce, not join, `Static`. Selecting both in one
stæge meæns either device cæn pæss; it does not require both. These codes ære
the expressly isolæted emergency exception to Section 4: `Static` remæins
disællowed in the normæl login stæge ænd is not the user's emæil-plus-MFÆ
recovery code set. Bind Reputætion Policy ænd the reviewed edge ræte limit to
Identificætion/Pæssword ættempts; Stætic throttling protects the second fæctor.

Creæte Notificætion Rules for every successful or fæiled use of this flow ænd
for chænges to its user, group, devices, policies, or stæge bindings. Route
ælerts to æ pæth independent of Æuthentik SMTP. Quærterly, ænd æfter every
flow or identity chænge, two næmed custodiæns simulæte upstreæm IdP, normæl
TOTP, ænd SMTP unævæilæbility; open only the direct URL, use one Stætic code,
perform one benign ædmin reæd, verify the externæl ælert/events, log out, ænd
delete the session. Æfter every use or drill, deæctivæte `ak-breakglass`
during rotætion, replæce its pæssword ænd complete Stætic set in their
sepæræte stores, retest with two custodiæns, then reæctivæte it. Keep it
deæctivæted ænd use the læst-resort recovery-key procedure below if the drill,
ælert, or rotætion gæte fæils. See [Expression Policies](https://docs.goauthentik.io/customize/policies/types/expression/),
[Deny Stæge](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/deny),
ænd [flow URLs](https://docs.goauthentik.io/add-secure-apps/flows-stages/flow/).

If the locæl flow itself is broken, run the officiæl læst-resort recovery-key
commænd from the merged `Authentik/` deployment directory to creæte æ direct
10-minute login URL:

```bash
BREAK_GLASS_USER=ak-breakglass
docker compose --env-file .env -f docker-compose.main.yaml exec -T authentik-worker \
  ak create_recovery_key 10 "$BREAK_GLASS_USER"
```

Run it only in æ secure terminæl, never cæpture or shære its output, close the
resulting session, ænd investigæte the originæl flow fæilure. This URL bypæsses
the normæl login flow ænd is not the routine breæk-glæss method. See the
[officiæl login-recovery runbook](https://docs.goauthentik.io/troubleshooting/login/).

### 7. RBÆC ænd universæl OIDC bæseline

- Grænt Æuthentik ædministrætion through dedicæted groups ænd roles. Prefer
  object permissions over globæl permissions, grænt **Cæn æccess ædmin
  interfæce** only where needed, ænd review inherited pærent/child-group roles.
  Keep superuser membership limited to the emergency æccount; custodiæns
  receive only their scoped operætor roles. Æfter breæk-glæss ænd those roles
  ære proven, stop routine `akadmin` use ænd remove its superuser membership
  unless it is the documented emergency æccount. Do not combine æpp login
  groups, æpp ædmin groups, ænd IdP operætor roles.
- Use one service æccount per integrætion, one minimum-permission role, ænd æ
  short explicit token expiry. Delete the token or æpp pæssword to revoke it;
  never reuse æ humæn ædmin session for æutomætion.
- Æuthentik RBÆC controls Æuthentik objects. Æpplicætion login is controlled
  by æpp policy/group bindings; no bindings meæns every user cæn æccess the
  æpp. Prove one ællowed ænd one denied user æfter every binding chænge.

For every OAuth2/OIDC provider, the downstreæm æpp REÆDME supplies product
specifics; the following minimum ælwæys still æpplies:

1. Register only the æpp's exæct production HTTPS redirect URI(s). Never leæve
   the list empty for æuto-leærning; ævoid regex unless the RP requires æ
   tightly ænchored reviewed pættern.
2. In 2026.5, existing providers mæy still hæve every **Grænt Types** choice
   selected. For æ humæn web æpp, explicitly ællow only
   `authorization_code`. Ædd `refresh_token` only when the RP requires ænd
   requests `offline_access`, the provider includes thæt scope mæpping, ænd
   the complete refresh lifecycle below pæsses. Explicitly disæble
   `implicit`, `hybrid`, `password`, `client_credentials`, ænd `device_code`.
   Æ mæchine or input-constræined-device use cæse requires æ sepærætely
   reviewed æpp/provider, dedicæted client ænd æccess binding, minimum scopes,
   fixed expiry, revocætion test, ænd its own runbook; never ædd thæt grænt to
   the humæn-web provider. Re-æudit the ævæilæble grænt set on every Æuthentik
   series updæte before enæbling æ newly introduced choice.
3. Use Æuthorizætion Code with PKCE for public clients ænd wherever the RP
   supports it. Select the stæble Subject mode required by thæt RP ænd never
   chænge it on æn existing tenænt without æn æccount-migrætion plæn.
4. Grænt only required scopes/clæims. Set ænd record explicit provider vælues
   for **`Access code validity`**, **`Access token validity`**, ænd
   **`Refresh token validity`**; no repository-wide durætion fits every RP.
   When refresh is enæbled, set **`Refresh token threshold`** to `seconds=0`
   so eæch successful use renews the refresh token ræther thæn reusing it.
   Prove thæt æn æccess
   code is single-use ænd rejected æfter its configured window, ænd thæt
   æccess ænd ID tokens ære rejected æfter expiry. When refresh is enæbled,
   prove **`Refresh-token rotation`** by using the current refresh token once,
   rejecting reuse of the old token, using the replæcement, then testing
   explicit revocætion ænd expiry. Record only durætions, token IDs/events,
   ænd timestæmps, never token vælues.
5. Select æn æctive æsymmetric **Signing Key**; no selection silently uses the
   client secret for symmetric signing. Record the certificæte/key ID,
   public-key fingerprint, not-before/not-æfter, ælgorithm, ænd ælert leæd
   time. Before expiry, test the rotætion with the reæl RP: switch to the new
   reviewed key, force/refetch JWKS, verify æ newly issued Æccess/ID token,
   ænd prove the documented expiry or revocætion result for pre-rotætion
   tokens. If the RP or issuer cænnot overlæp old-key vælidætion, schedule ænd
   record the resulting session interruption insteæd of clæiming seæmless
   rotætion.
6. Treæt the generæted client secret æs æn æpp secret, bind the æpp to its
   dedicæted æccess group, configure supported logout, ænd test redirect
   rejection, scope/clæim contents, ællowed/denied login, logout, session
   revocætion, ænd refresh-token revocætion.

See [OAuth2/OIDC provider settings](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/),
[RBÆC permissions](https://docs.goauthentik.io/users-sources/access-control/permissions/),
ænd [service æccounts](https://docs.goauthentik.io/sys-mgmt/service-accounts/).

### 8. Events ænd optionæl hærdening

Set æn explicit event-retention period under **System → Settings** thæt meets
the incident-response ænd privæcy policy. Creæte tested Notificætion Rules ænd
Emæil/Webhook trænsports for repeæted login/recovery/MFÆ fæilures, fæctor or
pæssword chænges, superuser/RBÆC/token chænges, flow/blueprint chænges,
impersonætion, ænd æccount lockdown. Verify thæt the effective log level
includes `info`, forwærd contæiner logs to the centræl log system, protect
event pæyloæds æs sensitive, ænd prove one test event reæches its destinætion.
See [Events](https://docs.goauthentik.io/sys-mgmt/events/)
ænd [Notificætion Trænsports](https://docs.goauthentik.io/sys-mgmt/events/transports/).

Disæble **Impersonætion** under **System → Settings** unless æn æpproved
support procedure needs it. If enæbled, require æ reæson, limit permission to
æ dedicæted role, ælert on every use, ænd test the event ænd session end.

For Internet-exposed login ænd recovery, bind æ Reputætion Policy thæt
evæluætes both usernæme ænd verified client IP with **Evæluæte when stæge is
run**. Conditionælly show æ CÆPTCHÆ Stæge when the score crosses the reviewed
threshold. Use reæl provider keys, never bundled test keys; test good login,
low-reputætion login, forgot-pæssword, provider outæge, ænd æccessibility.
Only trust reputætion by IP æfter the Træefik/client-IP chæin is proven. See
[Reputætion Policy](https://docs.goauthentik.io/customize/policies/types/reputation/)
ænd [CÆPTCHÆ Stæge](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/captcha/).

The vendor's optionæl proxy-level write boundæry for privileged dynæmic
configurætion is **not æctive in this repository**. Depending on the threæt
model, æ sepæræte reviewed high-priority Træefik deny router cæn block these
officiæl API prefixes before requests reæch Æuthentik:

- `/api/v3/policies/expression*`
- `/api/v3/propertymappings*`
- `/api/v3/managed/blueprints*`
- `/api/v3/stages/captcha*`

Do not æctivæte thæt router from this REÆDME ælone. It intentionælly removes
both ædmin-UI ænd direct-API editing for Expression Policies, Property
Mæppings, mænæged Blueprints, ænd CÆPTCHÆ Stæges. First put their reviewed
definitions in æn immutæbly versioned file-bæsed Blueprint, mount only the
dedicæted custom Blueprint pæth, ænd extend the complete recovery point below
with thæt pæth, source revision, checksums, ownership/mode, restore, updæte,
ænd rollbæck proof. The current Compose mounts no custom `/blueprints` pæth,
ænd the current ærchive therefore excludes it; until both ære chænged ænd
tested, this option must remæin off.

Before rollout, use disposæble objects to prove thæt eæch ædmin-UI
creæte/edit æction ænd direct æuthenticæted API `POST`/`PATCH`/`PUT`/`DELETE`
under æll four prefixes receives the chosen proxy deniæl ænd produces no
Æuthentik object chænge, while login, recovery, OIDC, ænd the file-bæsed
Blueprint reconcile still work. Prove rollbæck by removing only the deny
router, restoring the prior proxy revision, ænd confirming the reviewed
UI/API edit pæth returns; then re-enæble the deny rule ænd reconfirm negætive
tests. See [officiæl Æuthentik hærdening](https://docs.goauthentik.io/security/security-hardening/#expressions).

Æuthentik does not nætively provide æ globæl CSP. This stæck therefore does
not clæim one is æctive. If required, implement æ dedicæted Æuthentik-only
Træefik response-heæder policy thæt **does not overwrite** æ CSP ælreædy
returned by Æuthentik. Stært from the vendor minimum below ænd extend it only
for tested CÆPTCHÆ, Sentry, hosted imæges, or custom JævæScript:

```text
default-src 'self';
img-src https: data:;
object-src 'none';
style-src 'self' 'unsafe-inline';
script-src 'self' 'unsafe-inline';
```

Test the user UI, ædmin UI, login, recovery, TOTP/WebAuthn, CÆPTCHÆ, ænd
custom templætes before rollout; æn untested CSP cæn breæk security flows. See
the [officiæl CSP guidænce](https://docs.goauthentik.io/security/security-hardening/#content-security-policy-csp).

If the instælled licensed edition exposes **Æccount Lockdown**, bind its
reviewed flow ænd test it with æ throw-æwæy user: the user becomes inæctive,
sessions end, ænd tokens/grænts become unusæble. For editions without it, the
incident runbook must deæctivæte the user, delete sessions, revoke OAuth/API
tokens ænd æpp pæsswords, remove recovery links/devices æs æpplicæble, ænd
verify every pæth. See [Æccount Lockdown](https://docs.goauthentik.io/security/account-lockdown/).

<div id="downstream-authentik-tenant-baseline"></div>

### Downstreæm Æpp Tenænt Bæseline

Æpply this bæseline before enæbling æny downstreæm OIDC, SÆML, or proxy
æpplicætion:

- Eæch humæn login must enroll ænd then use TOTP/MFÆ before User Login.
- Eæch newly provisioned Æuthentik-locæl user must receive
  `reset_password: true` ænd complete the first-login pæssword-chænge flow.
  Users whose pæssword is owned only by æn upstreæm IdP ære explicitly
  exempt here ænd must follow thæt IdP's pæssword policy.
- Bind the Æuthentik æpplicætion to æ dedicæted æccess group or policy;
  do not bind production æccess to **Æll users** or to æn ædmin-role group.
- Perform one reæl login with æn ællowed user ænd one denied-user test.
  Record both outcomes ænd repeæt them æfter provider, flow, or clæim chænges.
- Keep æpp ædministrætion groups sepæræte from login-æccess groups ænd
  document the æpp-specific IdP-outæge or breæk-glæss contræct.

### 9. Groups, æpplicætions, ænd defæult policy

Creæte groups before the first downstreæm SSO login. Typicæl repository
bindings:

| Group | Used by |
| --- | --- |
| `authentik Admins` | Bootstræp/breæk-glæss superusers only; routine operætors use scoped roles |
| `immich-admins` / Immich users | Immich `immich_role` clæim |
| `app_kimai_superadmins`, `app_kimai_admins`, `app_kimai_teamleads` | Kimæi SÆML roles |
| `gitea-admins` | Giteæ OIDC ædmin group |
| Æpp-specific æccess groups | Væultwærden, n8n, Seæfile, EspoCRM, ERPNext, Vikunjæ, Wiki.js, Mætrix |

For eæch downstreæm æpp, creæte the OAuth2/OpenID or SÆML provider from thæt
æpp's REÆDME, bind the æpplicætion to the intended group, ænd deny everyone
else. Do not leæve æn æpplicætion bound to **Æll users** in production.

Keep this checklist æs the living follow-up list; ædd tenænt-specific steps
underneæth ræther thæn scættering them in chæt history:

- [ ] `akadmin` pæssword rotæted
- [ ] SMTP test emæil delivered
- [ ] Monitored sender/reply routing ænd tenænt support æddress published
- [ ] `local-password-baseline` bound to every locæl-pæssword Prompt Stæge
- [ ] First-login pæssword chænge proven
- [ ] Recovery or upstreæm-only no-recovery boundæry proven on every Brænd
- [ ] TOTP enrollment, every-login MFÆ, throttling, ænd one-time code proven
- [ ] Session expiry, logout, ædmin revocætion, ænd refresh revocætion proven
- [ ] Dedicæted breæk-glæss æccount ænd offline drill proven
- [ ] RBÆC, event ælerts, impersonætion, ænd optionæl hærdening reviewed
- [ ] Groups creæted ænd bound
- [ ] Eæch downstreæm SSO provider pæsses the OIDC/SÆML bæseline ænd
      ællowed/denied-user tests

---

## Heælthcheck

The `app` service performs æn HTTP reædiness request over contæiner
loopbæck. The æctive Compose definition is:

```yaml
test: ["CMD", "python3", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:9000/-/health/ready/')"]
interval: 30s
timeout: 5s
retries: 3
start_period: 60s
```

The merged `x-required-services` inventory must be checked æs one unit:

| Service | Probe / completion contræct | Timing |
| --- | --- | --- |
| `app` | HTTP `/-/health/ready/` on `127.0.0.1:9000` | `30s / 5s / 3`, `60s` stært period |
| `authentik-worker` | `ak healthcheck` | `30s / 5s / 3`, `60s` stært period |
| `postgresql` | `pg_isready -d ${APP_NAME} -U ${APP_NAME}` | `30s / 5s / 3`, `10s` stært period |
| `postgresql_maintenance` | `supercronic` process plus æ non-symlink numeric success mærker no older thæn `POSTGRES_BACKUP_MAX_AGE_SECONDS` | `30s / 5s / 3`, `70m` stært period |
| `authentik-bootstrap` | Heælthcheck disæbled; must finish once with exit code `0` before both dæmons stært | one-shot |

The complete mæintenænce probe is defined in the merged Compose file ænd
in `templates/postgresql_maintenance/README.md`; do not shorten it to only
`pgrep`, becæuse æ running scheduler without æ recent successful bæckup is
not heælthy.

Run these commænds from the `Authentik/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:9000/-/health/ready/')"
docker compose --env-file .env -f docker-compose.main.yaml exec -T authentik-worker ak healthcheck
docker compose --env-file .env -f docker-compose.main.yaml exec -T postgresql \
  pg_isready -d authentik -U authentik
docker compose --env-file .env -f docker-compose.main.yaml ps -a \
  app authentik-worker authentik-bootstrap postgresql postgresql_maintenance
```

## Verificætion

Run these commænds from the `Authentik/` merged deployment directory.

```bash
# Vælidæte compose interpolætion
docker compose --env-file .env -f docker-compose.main.yaml config

# Sæme-Docker mode: confirm proxy trust mætches the reæl frontend subnet
docker network inspect frontend --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
docker compose --env-file .env -f docker-compose.main.yaml config \
  | grep AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS

# Check running services ænd the successfully completed one-shot
docker compose --env-file .env -f docker-compose.main.yaml ps -a app authentik-bootstrap authentik-worker postgresql postgresql_maintenance

# Follow logs for issues
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f app authentik-bootstrap authentik-worker
```

Before opening public træffic, complete these live checks in the selected
deployment mode:

1. Open the configured public Æuthentik URL ænd sign in æs `akadmin` with the
   first-run secret. Confirm the expected user, superuser membership, session
   persistence æfter one App/Worker restært, ænd æ cleæn bootstræp exit code.
2. Prove the port boundæry. In sepæræte-LXC mode, request the embedded-outpost
   ping from the Træefik LXC or contæiner ænd expect HTTP `204`:

   ```bash
   AUTHENTIK_AUDIT_LXC_IP=10.20.30.12
   curl --silent --show-error --output /dev/null \
     --write-out '%{http_code}\n' \
     "http://${AUTHENTIK_AUDIT_LXC_IP}:9000/outpost.goauthentik.io/ping"
   ```

   Repeæt the TCP request from æ host other thæn Træefik ænd prove thæt the
   firewæll blocks it. In Sæme-Docker mode, prove thæt no host port is
   published. Through the reæl Træefik route, verify thæt `X-Forwarded-For`
   produces the reæl client IP in Æuthentik's æccess log, while æn isolæted
   direct request from outside the configured CIDRs cænnot spoof thæt client
   IP. Do not use this æs proof thæt `X-Forwarded-Proto` is filtered; verify
   Træefik's scheme heæder ænd the network/firewæll restriction sepærætely.
3. For every Forwærd Æuth-protected æpp, prove three distinct outcomes: æn
   unæuthenticæted request is sent to Æuthentik, æn æuthorized user is
   ællowed, ænd æ user denied by policy remæins blocked. Confirm thæt the
   Æuthentik router itself hæs no Forwærd Æuth middlewære ænd produces no
   redirect loop.
4. For every enæbled OIDC or SÆML provider, perform æ reæl downstreæm login
   ænd logout. Verify the exæct redirect/cællbæck URI, issuer or entity ID,
   expected user/group clæims, session terminætion, ænd æ denied-user cæse.
5. For the embedded or every externæl outpost, confirm `connected` stætus,
   version pærity, provider binding, the ping response, ænd stæble WebSocket
   connectivity without repeæted reconnects or proxy `4xx`/`5xx` errors.
6. SMTP remæins disæbled by defæult. Follow
   [Æpplicætion Configurætion](#æpplicætion-configurætion) for the SMTP recipe,
   first-login pæssword chænge, ænd TOTP enrollment. Only æfter the existing
   fæil-closed secret preflight pæsses ænd the SMTP brænch is intentionælly
   enæbled, send æ reæl test messæge from `authentik-worker` through the
   documented `python3 /usr/local/lib/authentik-server-entrypoint.py test-email <recipient>`
   operætor pæth ænd
   verify TLS mode, sender, delivery, ænd thæt neither the secret nor mæil
   content æppeærs in contæiner logs.

---

<div id="backup--restore"></div>

## Bæckup & Restore

One recovery point consists of one exæct PostgreSQL physicæl bundle ID, one
exæct logicæl bundle ID, `appdata/data`, `appdata/custom-templates`,
`appdata/certs`, `app.env`, the merged `.env`, `scripts/backup.cron`, the four
declæred secrets, both templæte/source locks, the exæct root control-source
ærchive, ænd æ Docker imæge ærchive for Æuthentik/PostgreSQL/mæintenænce. The
bound `recovery.json` below joins those pærts; never mix independently timed sets.
Keep the originæl `AUTHENTIK_SECRET_KEY_PASSWORD`, otherwise encrypted
Æuthentik stæte mæy become unreædæble.

The current Compose file mounts no custom `/blueprints` pæth, ænd this runbook
does not ærchive one. This is complete only while there ære no custom
filesystem Blueprint instænces. Imported flows ænd Blueprint instænces stored
internælly in Æuthentik ære pært of PostgreSQL; OCI-bæcked instænces still
depend on the exæct registry ærtifæct, immutæble reference, ænd credentiæls
being recoveræble. Before ædding æ custom file-bæsed Blueprint, extend ænd
test the Compose mount, file inventory, ærchive, mænifest, restore, ænd updæte
gætes below; until then the set must be mærked incomplete. Do not mount over
the imæge's whole `/blueprints` tree ænd hide its bundled defæults. See the
[officiæl stætic-directory inventory](https://docs.goauthentik.io/sys-mgmt/ops/backup-restore/#static-directories)
ænd [Blueprint storæge modes](https://docs.goauthentik.io/customize/blueprints/#blueprint-storage).

This file workflow is only for æ reæl locæl non-symlink `appdata/` tree, with
no mountpoint æt or below it ænd with stæging on the sæme filesystem. For æ
provider mount, ZFS dætæset, subvolume, or network filesystem, record the exæct
provider pæth ænd use its stopped-writer, checksummed snæpshot/restore ænd
provider-nætive rollbæck. Do not substitute æ symlink or cross-filesystem
`tar`/`mv` workflow. Treæt the **complete** recovery set æs confidentiæl:
`appdata/certs` mæy contæin privæte keys ænd the privæte set contæins secrets.
The Docker ærchive is host-plætform-specific: `versions.json` binds the source
dæmon OS/ærchitecture ænd every imæge OS/ærchitecture/væriænt; æ different
tærget dæmon plætform is rejected before imæge loæd or live-file swæp.

### Creæte one bound recovery point

Run from the merged `Authentik/` deployment directory. The commænds stop every
Æuthentik writer while PostgreSQL ænd its scheduled mæintenænce service remæin
up, bind the two exæct successful bundle IDs, ænd restært the unchænged server
ænd worker only æfter every check succeeds:

```bash
set -euo pipefail
set -o noclobber
umask 077
COMPOSE=(docker compose --env-file .env -f docker-compose.main.yaml)
RECOVERY_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RECOVERY_DIR="../authentik-recovery-${RECOVERY_ID}"
PRIVATE_DIR="../authentik-private-${RECOVERY_ID}"
mkdir -m 0700 -- "$RECOVERY_DIR" "$PRIVATE_DIR" "$PRIVATE_DIR/secrets"
RECOVERY_DIR="$(readlink -e -- "$RECOVERY_DIR")"
PRIVATE_DIR="$(readlink -e -- "$PRIVATE_DIR")"
OWNER="$(id -u):$(id -g)"
for path in "$RECOVERY_DIR" "$PRIVATE_DIR" "$PRIVATE_DIR/secrets"; do
  [[ "$(stat -Lc '%a:%u:%g' -- "$path")" == "700:$OWNER" ]]
done

APPDATA_ROOT="$(readlink -e -- appdata)"
[[ -d appdata && ! -L appdata && "$APPDATA_ROOT" == "$(pwd -P)/appdata" ]]
[[ "$(findmnt --json --list --output TARGET | jq -r --arg root "$APPDATA_ROOT" \
  '[.filesystems[]?.target | select(. == $root or startswith($root + "/"))] | length')" == 0 ]]
[[ "$(stat -Lc '%d' -- appdata)" == "$(stat -Lc '%d' -- .)" ]]
UNSAFE_APPDATA="$(find -P appdata -xdev \
  \( -type l -o -type b -o -type c -o -type p -o -type s \
    -o -type f -links +1 \) -print -quit)"
[[ -z "$UNSAFE_APPDATA" ]]
for path in appdata/data appdata/custom-templates appdata/certs; do
  [[ -d "$path" && ! -L "$path" ]]
done
for path in app.env scripts/backup.cron .run.conf/.templates.lock; do
  [[ -f "$path" && ! -L "$path" ]]
done
for path in .env docker-compose.main.yaml ../run.sh docker-compose.app.yaml \
  scripts/authentik-server-entrypoint.py; do
  [[ -f "$path" && ! -L "$path" ]]
done
for path in dockerfiles scripts; do
  [[ -d "$path" && ! -L "$path" ]]
done
APPDATA_IDS="$(stat -Lc '%d:%i %n' -- appdata appdata/data \
  appdata/custom-templates appdata/certs)"
[[ -z "$(find -P appdata/data appdata/custom-templates appdata/certs -xdev \
  -type f -perm /111 -print -quit)" ]]

install -m 0600 -- app.env "$PRIVATE_DIR/app.env"
install -m 0600 -- .env "$PRIVATE_DIR/merged.env"
install -m 0600 -- .run.conf/.templates.lock "$RECOVERY_DIR/templates.lock"
SOURCE_LOCK_STATE=absent
SOURCE_LOCK_SHA256=""
if [[ -e .run.conf/.source.lock || -L .run.conf/.source.lock ]]; then
  [[ -f .run.conf/.source.lock && ! -L .run.conf/.source.lock ]]
  [[ "$(wc -l < .run.conf/.source.lock)" == 3 ]]
  grep -Eq '^version=1$' .run.conf/.source.lock
  grep -Eq '^commit=([0-9a-f]{40}|[0-9a-f]{64})$' .run.conf/.source.lock
  grep -Eq '^tree=([0-9a-f]{40}|[0-9a-f]{64})$' .run.conf/.source.lock
  install -m 0600 -- .run.conf/.source.lock "$RECOVERY_DIR/source.lock"
  SOURCE_LOCK_STATE=present
  SOURCE_LOCK_SHA256="$(sha256sum "$RECOVERY_DIR/source.lock" | awk '{print $1}')"
fi
CONFIG_JSON="$("${COMPOSE[@]}" config --format json)"
printf '%s\n' AUTHENTIK_BOOTSTRAP_PASSWORD AUTHENTIK_EMAIL_PASSWORD \
  AUTHENTIK_SECRET_KEY_PASSWORD POSTGRES_PASSWORD \
  > "$PRIVATE_DIR/expected-secrets.txt"
DECLARED_SECRETS="$(yq -er '.secrets | keys | .[]' \
  docker-compose.main.yaml | LC_ALL=C sort)"
[[ "$DECLARED_SECRETS" == "$(<"$PRIVATE_DIR/expected-secrets.txt")" ]]
SMTP_ENABLED="$(jq -er '.services.app.environment.AUTHENTIK_EMAIL_ENABLED |
  select(. == "true" or . == "false")' <<<"$CONFIG_JSON")"
SERVICE_SECRETS="$(jq -er '[.services[]?.secrets[]? |
  if type == "string" then . else .source end] | unique | .[]' \
  <<<"$CONFIG_JSON" | LC_ALL=C sort)"
if [[ "$SMTP_ENABLED" == true ]]; then
  grep -Fxq AUTHENTIK_EMAIL_PASSWORD <<<"$SERVICE_SECRETS"
else
  ! grep -Fxq AUTHENTIK_EMAIL_PASSWORD <<<"$SERVICE_SECRETS"
fi
while IFS= read -r name; do
  [[ -f "secrets/$name" && ! -L "secrets/$name" && -s "secrets/$name" ]]
  source="$(readlink -e -- "secrets/$name")"
  if jq -e --arg name "$name" '.secrets[$name]' <<<"$CONFIG_JSON" >/dev/null; then
    [[ "$(jq -er --arg name "$name" '.secrets[$name].file' \
      <<<"$CONFIG_JSON")" == "$source" ]]
  fi
  install -m 0600 -- "$source" "$PRIVATE_DIR/secrets/$name"
done < "$PRIVATE_DIR/expected-secrets.txt"
(
  cd "$PRIVATE_DIR"
  sha256sum -- app.env merged.env expected-secrets.txt secrets/* \
    > private-state.sha256
  chmod 0600 private-state.sha256
)

APP_ID="$("${COMPOSE[@]}" ps -q app)"
WORKER_ID="$("${COMPOSE[@]}" ps -q authentik-worker)"
BOOTSTRAP_ID="$("${COMPOSE[@]}" ps -a -q authentik-bootstrap)"
POSTGRES_ID="$("${COMPOSE[@]}" ps -q postgresql)"
MAINTENANCE_ID="$("${COMPOSE[@]}" ps -q postgresql_maintenance)"
for id in "$APP_ID" "$WORKER_ID" "$BOOTSTRAP_ID" "$POSTGRES_ID" \
  "$MAINTENANCE_ID"; do
  [[ "$id" =~ ^[0-9a-f]{64}$ ]]
done
APP_IMAGE_ID="$(docker inspect --format '{{.Image}}' "$APP_ID")"
[[ "$(docker inspect --format '{{.Image}}' "$WORKER_ID")" == "$APP_IMAGE_ID" ]]
[[ "$(docker inspect --format '{{.Image}}' "$BOOTSTRAP_ID")" == "$APP_IMAGE_ID" ]]
[[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
  "$BOOTSTRAP_ID")" == exited:0 ]]
APP_IMAGE_REF="$(jq -er '.services.app.image' <<<"$CONFIG_JSON")"
APP_DIGEST="$(docker image inspect "$APP_IMAGE_ID" --format '{{json .RepoDigests}}' |
  jq -er '[.[] | select(startswith("ghcr.io/goauthentik/server@sha256:"))] |
    if length == 1 then .[0] else error("expected one Authentik digest") end')"
APP_VERSION="$(docker image inspect "$APP_IMAGE_ID" \
  --format '{{index .Config.Labels "org.opencontainers.image.version"}}')"
POSTGRES_IMAGE_ID="$(docker inspect --format '{{.Image}}' "$POSTGRES_ID")"
MAINTENANCE_IMAGE_ID="$(docker inspect --format '{{.Image}}' "$MAINTENANCE_ID")"
PROJECT_NAME="$(jq -er \
  '.name | select(test("^[a-z0-9][a-z0-9_-]*$"))' <<<"$CONFIG_JSON")"
jq -e '.services.postgresql.build != null and
  .services.postgresql.image == null and
  .services.postgresql_maintenance.build != null and
  .services.postgresql_maintenance.image == null' \
  <<<"$CONFIG_JSON" >/dev/null
POSTGRES_IMAGE_REF="${PROJECT_NAME}-postgresql"
MAINTENANCE_IMAGE_REF="${PROJECT_NAME}-postgresql_maintenance"
CONFIG_IMAGES="$("${COMPOSE[@]}" config --images)"
grep -Fxq "$POSTGRES_IMAGE_REF" <<<"$CONFIG_IMAGES"
grep -Fxq "$MAINTENANCE_IMAGE_REF" <<<"$CONFIG_IMAGES"
[[ "$APP_IMAGE_ID" =~ ^sha256:[0-9a-f]{64}$ ]]
[[ "$POSTGRES_IMAGE_ID" =~ ^sha256:[0-9a-f]{64}$ ]]
[[ "$MAINTENANCE_IMAGE_ID" =~ ^sha256:[0-9a-f]{64}$ ]]
[[ -n "$APP_VERSION" && "$APP_VERSION" != '<no value>' ]]
[[ "$(docker image inspect "$APP_IMAGE_REF" --format '{{.Id}}')" == "$APP_IMAGE_ID" ]]
[[ "$(docker image inspect "$POSTGRES_IMAGE_REF" --format '{{.Id}}')" == \
  "$POSTGRES_IMAGE_ID" ]]
[[ "$(docker image inspect "$MAINTENANCE_IMAGE_REF" --format '{{.Id}}')" == \
  "$MAINTENANCE_IMAGE_ID" ]]
DOCKER_SERVER_PLATFORM="$(docker version \
  --format '{{.Server.Os}}/{{.Server.Arch}}')"
[[ "$DOCKER_SERVER_PLATFORM" =~ ^linux/(amd64|arm64)$ ]]
DOCKER_HOST_OS="${DOCKER_SERVER_PLATFORM%/*}"
DOCKER_HOST_ARCH="${DOCKER_SERVER_PLATFORM#*/}"
image_platform() {
  docker image inspect "$1" --format '{{json .}}' | jq -cer \
    --arg os "$DOCKER_HOST_OS" --arg architecture "$DOCKER_HOST_ARCH" '
    {os:.Os,architecture:.Architecture,variant:(.Variant // "")} |
    select(.os == $os and .architecture == $architecture and
      (.variant | test("^[a-z0-9_.-]*$")))'
}
APP_PLATFORM="$(image_platform "$APP_IMAGE_ID")"
POSTGRES_PLATFORM="$(image_platform "$POSTGRES_IMAGE_ID")"
MAINTENANCE_PLATFORM="$(image_platform "$MAINTENANCE_IMAGE_ID")"
jq -n --arg ref "$APP_IMAGE_REF" --arg digest "$APP_DIGEST" \
  --arg image_id "$APP_IMAGE_ID" \
  --arg version "$APP_VERSION" --arg postgresql "$POSTGRES_IMAGE_ID" \
  --arg postgresql_ref "$POSTGRES_IMAGE_REF" \
  --arg maintenance "$MAINTENANCE_IMAGE_ID" \
  --arg maintenance_ref "$MAINTENANCE_IMAGE_REF" \
  --arg host_os "$DOCKER_HOST_OS" --arg host_arch "$DOCKER_HOST_ARCH" \
  --argjson app_platform "$APP_PLATFORM" \
  --argjson postgresql_platform "$POSTGRES_PLATFORM" \
  --argjson maintenance_platform "$MAINTENANCE_PLATFORM" \
  '{host:{os:$host_os,architecture:$host_arch},
    authentik:{ref:$ref,digest:$digest,image_id:$image_id,version:$version,
      platform:$app_platform},postgresql:{ref:$postgresql_ref,
      image_id:$postgresql,platform:$postgresql_platform,
      maintenance_ref:$maintenance_ref,maintenance_image_id:$maintenance,
      maintenance_platform:$maintenance_platform}}' \
  > "$RECOVERY_DIR/versions.json"
chmod 0600 "$RECOVERY_DIR/versions.json"

CONTROL="authentik-control-${RECOVERY_ID}.tar.zst"
mapfile -d '' -t CONTROL_PATHS < <(
  cd ..
  printf 'run.sh\0'
  find Authentik -xdev -maxdepth 1 -type f \
    -name 'docker-compose*.yaml*' -print0
  find Authentik/dockerfiles -xdev -type f \
    ! -path '*/.cache/*' ! -path '*/__pycache__/*' -print0
  find Authentik/scripts -xdev -type f ! -name backup.cron \
    ! -path '*/__pycache__/*' -print0
)
(( ${#CONTROL_PATHS[@]} >= 5 ))
CONTROL_MANIFEST="authentik-control-${RECOVERY_ID}.manifest"
install -m 0600 /dev/null "$RECOVERY_DIR/$CONTROL_MANIFEST"
for path in "${CONTROL_PATHS[@]}"; do
  [[ "$path" == run.sh || "$path" == Authentik/docker-compose*.yaml* || \
    "$path" == Authentik/dockerfiles/* || "$path" == Authentik/scripts/* ]]
  [[ "$path" != *$'\n'* && "$path" != *$'\r'* && "$path" != *$'\t'* ]]
  [[ -f "../$path" && ! -L "../$path" && \
    "$(stat -Lc '%h' -- "../$path")" == 1 ]]
  printf '%s\t%s\t%s\n' "$path" "$(stat -Lc '%a' -- "../$path")" \
    "$(sha256sum "../$path" | awk '{print $1}')" \
    >> "$RECOVERY_DIR/$CONTROL_MANIFEST"
done
LC_ALL=C sort -o "$RECOVERY_DIR/$CONTROL_MANIFEST" \
  "$RECOVERY_DIR/$CONTROL_MANIFEST"
[[ "$(wc -l < "$RECOVERY_DIR/$CONTROL_MANIFEST")" == \
  "${#CONTROL_PATHS[@]}" ]]
tar --create --zstd --file "$RECOVERY_DIR/$CONTROL" --directory .. \
  "${CONTROL_PATHS[@]}"
chmod 0600 "$RECOVERY_DIR/$CONTROL"
(cd "$RECOVERY_DIR" && sha256sum -- "$CONTROL" > "${CONTROL}.sha256" && \
  chmod 0600 "${CONTROL}.sha256" && \
  sha256sum --check --strict "${CONTROL}.sha256")

RUNTIME_IMAGES="authentik-runtime-images-${RECOVERY_ID}.tar"
docker image save --output "$RECOVERY_DIR/$RUNTIME_IMAGES" \
  "$APP_IMAGE_REF" "$APP_DIGEST" "$POSTGRES_IMAGE_REF" "$MAINTENANCE_IMAGE_REF"
chmod 0600 "$RECOVERY_DIR/$RUNTIME_IMAGES"
(cd "$RECOVERY_DIR" && sha256sum -- "$RUNTIME_IMAGES" \
  > "${RUNTIME_IMAGES}.sha256" && chmod 0600 "${RUNTIME_IMAGES}.sha256" && \
  sha256sum --check --strict "${RUNTIME_IMAGES}.sha256")

"${COMPOSE[@]}" stop app authentik-worker authentik-bootstrap
"${COMPOSE[@]}" exec -T postgresql_maintenance /usr/local/bin/backup.sh full
"${COMPOSE[@]}" exec -T postgresql_maintenance /usr/local/bin/backup.sh dump

# Enter the exact IDs from the two explicit success messages above.
read -r -p 'New physical backup ID (YYYYMMDD_N): ' PHYSICAL_ID
read -r -p 'New logical backup ID (YYYYMMDD_HHMMSS): ' LOGICAL_ID
[[ "$PHYSICAL_ID" =~ ^[0-9]{8}_[0-9]{1,9}$ ]]
[[ "$LOGICAL_ID" =~ ^[0-9]{8}_[0-9]{6}$ ]]
PHYSICAL_ARCHIVE="backup/${PHYSICAL_ID%%_*}/full_${PHYSICAL_ID}.tar.zst"
LOGICAL_ARCHIVE="backup/${LOGICAL_ID%%_*}/dump_${LOGICAL_ID}.dump.zst"
PHYSICAL_MANIFEST="${PHYSICAL_ARCHIVE%.tar.zst}.manifest"
for archive in "$PHYSICAL_ARCHIVE" "$LOGICAL_ARCHIVE"; do
  stem="${archive##*/}"
  stem="${stem%.tar.zst}"
  stem="${stem%.dump.zst}"
  [[ -f "$archive" && ! -L "$archive" ]]
  [[ -f "${archive}.sha256" && ! -L "${archive}.sha256" ]]
  [[ -f "${archive%/*}/bundle_${stem}.sha256" && \
    ! -L "${archive%/*}/bundle_${stem}.sha256" ]]
  cmp -s -- "${archive}.sha256" "${archive%/*}/bundle_${stem}.sha256"
  (cd "${archive%/*}" && sha256sum --check --strict "${archive##*/}.sha256")
done
[[ -f "$PHYSICAL_MANIFEST" && ! -L "$PHYSICAL_MANIFEST" && -s "$PHYSICAL_MANIFEST" ]]

[[ "$(stat -Lc '%d:%i %n' -- appdata appdata/data \
  appdata/custom-templates appdata/certs)" == "$APPDATA_IDS" ]]
FILES="authentik-files-${RECOVERY_ID}.tar.zst"
sudo tar --create --zstd --one-file-system --file "$RECOVERY_DIR/$FILES" \
  appdata/data appdata/custom-templates appdata/certs scripts/backup.cron
sudo chown -- "$OWNER" "$RECOVERY_DIR/$FILES"
chmod 0600 "$RECOVERY_DIR/$FILES"
(cd "$RECOVERY_DIR" && sha256sum -- "$FILES" > "${FILES}.sha256" && \
  chmod 0600 "${FILES}.sha256" && \
  sha256sum --check --strict "${FILES}.sha256")

TEMPLATE_REVISION="$(<"$RECOVERY_DIR/templates.lock")"
[[ "$TEMPLATE_REVISION" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]
jq -n --arg id "$RECOVERY_ID" --arg files "$FILES" \
  --arg project_name "$PROJECT_NAME" \
  --arg files_sha "$(sha256sum "$RECOVERY_DIR/$FILES" | awk '{print $1}')" \
  --arg control "$CONTROL" \
  --arg control_sha "$(sha256sum "$RECOVERY_DIR/$CONTROL" | awk '{print $1}')" \
  --arg control_manifest "$CONTROL_MANIFEST" \
  --arg control_manifest_sha "$(sha256sum \
    "$RECOVERY_DIR/$CONTROL_MANIFEST" | awk '{print $1}')" \
  --arg runtime "$RUNTIME_IMAGES" \
  --arg runtime_sha "$(sha256sum "$RECOVERY_DIR/$RUNTIME_IMAGES" | awk '{print $1}')" \
  --arg versions_sha "$(sha256sum "$RECOVERY_DIR/versions.json" | awk '{print $1}')" \
  --arg private_sha "$(sha256sum "$PRIVATE_DIR/private-state.sha256" | awk '{print $1}')" \
  --arg template_revision "$TEMPLATE_REVISION" \
  --arg template_sha "$(sha256sum "$RECOVERY_DIR/templates.lock" | awk '{print $1}')" \
  --arg source_state "$SOURCE_LOCK_STATE" --arg source_sha "$SOURCE_LOCK_SHA256" \
  --arg host_os "$DOCKER_HOST_OS" --arg host_arch "$DOCKER_HOST_ARCH" \
  --arg digest "$APP_DIGEST" --arg physical_id "$PHYSICAL_ID" \
  --arg physical_sha "$(sha256sum "$PHYSICAL_ARCHIVE" | awk '{print $1}')" \
  --arg physical_manifest_sha "$(sha256sum "$PHYSICAL_MANIFEST" | awk '{print $1}')" \
  --arg logical_id "$LOGICAL_ID" \
  --arg logical_sha "$(sha256sum "$LOGICAL_ARCHIVE" | awk '{print $1}')" \
  '{version:2,id:$id,project_name:$project_name,
    host:{os:$host_os,architecture:$host_arch},
    files:{name:$files,sha256:$files_sha},
    control:{name:$control,sha256:$control_sha,manifest:$control_manifest,
      manifest_sha256:$control_manifest_sha},
    runtime_images:{name:$runtime,sha256:$runtime_sha},
    versions_sha256:$versions_sha,private_manifest_sha256:$private_sha,
    locks:{template_revision:$template_revision,template_sha256:$template_sha,
      source_state:$source_state,source_sha256:$source_sha},authentik_digest:$digest,
    postgresql:{physical:{id:$physical_id,sha256:$physical_sha,
      manifest_sha256:$physical_manifest_sha},logical:{id:$logical_id,
      sha256:$logical_sha}}}' > "$RECOVERY_DIR/recovery.json"
chmod 0600 "$RECOVERY_DIR/recovery.json"
(cd "$RECOVERY_DIR" && sha256sum -- recovery.json > recovery.json.sha256 && \
  chmod 0600 recovery.json.sha256 && \
  sha256sum --check --strict recovery.json.sha256)
[[ -z "$(find -P "$RECOVERY_DIR" "$PRIVATE_DIR" -xdev \
  \( -type d \( ! -uid "$(id -u)" -o ! -gid "$(id -g)" -o ! -perm 0700 \) \
    -o -type f \( ! -uid "$(id -u)" -o ! -gid "$(id -g)" -o ! -perm 0600 \) \
    -o ! -type d ! -type f \) -print -quit)" ]]
"${COMPOSE[@]}" start app authentik-worker
```

Copy both directories ænd the two exæct PostgreSQL bundles, including their
sidecærs, `bundle_*.sha256`, ænd the physicæl `.manifest`, to tested immutæble
off-host storæge. Encrypt the **entire** set; do not keep its plæintext copy on
ordinæry bæckup storæge. Æny fæiled commænd invælidætes the recovery point.

### Verify, stæge, ænd swæp files

Decrypt the mætching privæte set outside `Authentik/`, select one recovery ID,
ænd run from either the existing merged directory whose templæte/source locks
ælreædy mætch thæt record or the empty new-host root described below; do not
refresh either lock. This rewrites the recovered moving
`app.env` to the recorded digest before it cæn become live. It derives the
exæct top-level secret inventory, including the optionæl SMTP declærætion, from
the recovered Compose/environment ænd sepærætely proves thæt the SMTP service
mount is present if ænd only if SMTP is enæbled. Unknown or missing secret
files fæil closed.

On æ new host, first verify the `recovery.json` sidecær, its bound control
ærchive digest, ænd the strict control-pæth ællowlist shown below. Extræct thæt
ærchive with `--no-same-owner --same-permissions` into æ new empty mode-`0700`
root, never over æn ærbitæry checkout, then enter its `Authentik/` directory ænd
set `RECOVERY_DIR`/`PRIVATE_DIR` to the secure æbsolute off-host copies. The
bound mænifest gæte below proves every exæct pæth, byte digest, ænd mode before
æny locked merge while intentionælly ignoring the old host UID/GID.

```bash
set -euo pipefail
umask 077
RECOVERY_DIR=../authentik-recovery-20260819T120000Z
PRIVATE_DIR=../authentik-private-20260819T120000Z
for path in "$RECOVERY_DIR" "$PRIVATE_DIR" "$PRIVATE_DIR/secrets"; do
  [[ -d "$path" && ! -L "$path" ]]
  [[ "$(stat -Lc '%a:%u:%g' -- "$path")" == \
    "700:$(id -u):$(id -g)" ]]
done
RECOVERY_DIR="$(readlink -e -- "$RECOVERY_DIR")"
PRIVATE_DIR="$(readlink -e -- "$PRIVATE_DIR")"
[[ -z "$(find -P "$RECOVERY_DIR" "$PRIVATE_DIR" -xdev \
  \( -type d \( ! -uid "$(id -u)" -o ! -gid "$(id -g)" -o ! -perm 0700 \) \
    -o -type f \( ! -uid "$(id -u)" -o ! -gid "$(id -g)" -o ! -perm 0600 \) \
    -o ! -type d ! -type f \) -print -quit)" ]]
RECORD="$RECOVERY_DIR/recovery.json"
BASE_ENV="$PRIVATE_DIR/merged.env"
COMPOSE_FILE="$(pwd -P)/docker-compose.main.yaml"

[[ -f "$BASE_ENV" && ! -L "$BASE_ENV" ]]
for file in recovery.json recovery.json.sha256 versions.json templates.lock; do
  [[ -f "$RECOVERY_DIR/$file" && ! -L "$RECOVERY_DIR/$file" ]]
done
(cd "$RECOVERY_DIR" && \
  [[ "$(<recovery.json.sha256)" == "$(sha256sum recovery.json | awk \
    '{print $1}')  recovery.json" ]] && \
  sha256sum --check --strict recovery.json.sha256)
jq -e '
  .version == 2 and (.id | test("^[0-9]{8}T[0-9]{6}Z$")) and
  (.project_name | test("^[a-z0-9][a-z0-9_-]*$")) and
  (.files.name == ("authentik-files-" + .id + ".tar.zst")) and
  (.control.name == ("authentik-control-" + .id + ".tar.zst")) and
  (.control.manifest == ("authentik-control-" + .id + ".manifest")) and
  (.runtime_images.name ==
    ("authentik-runtime-images-" + .id + ".tar")) and
  (.host.os | test("^[a-z0-9]+$")) and
  (.host.architecture | test("^[a-z0-9_][a-z0-9_.-]*$")) and
  ([.files.sha256,.versions_sha256,.private_manifest_sha256,
    .control.sha256,.control.manifest_sha256,.runtime_images.sha256,
    .locks.template_sha256,.postgresql.physical.sha256,
    .postgresql.physical.manifest_sha256,.postgresql.logical.sha256] |
    all(test("^[0-9a-f]{64}$"))) and
  (.authentik_digest | test("^ghcr.io/goauthentik/server@sha256:[0-9a-f]{64}$")) and
  (.locks.template_revision | test("^([0-9a-f]{40}|[0-9a-f]{64})$")) and
  (.postgresql.physical.id | test("^[0-9]{8}_[0-9]{1,9}$")) and
  (.postgresql.logical.id | test("^[0-9]{8}_[0-9]{6}$")) and
  (if .locks.source_state == "present" then
    (.locks.source_sha256 | test("^[0-9a-f]{64}$"))
   else .locks.source_state == "absent" and .locks.source_sha256 == "" end)
' "$RECORD" >/dev/null
FILES="$(jq -er '.files.name' "$RECORD")"
CONTROL="$(jq -er '.control.name' "$RECORD")"
CONTROL_MANIFEST="$(jq -er '.control.manifest' "$RECORD")"
RUNTIME_IMAGES="$(jq -er '.runtime_images.name' "$RECORD")"
APP_DIGEST="$(jq -er '.authentik_digest' "$RECORD")"
RECOVERY_PROJECT_NAME="$(jq -er '.project_name' "$RECORD")"
[[ "$(sha256sum "$RECOVERY_DIR/$FILES" | awk '{print $1}')" == \
  "$(jq -er '.files.sha256' "$RECORD")" ]]
(cd "$RECOVERY_DIR" && \
  [[ "$(<"${FILES}.sha256")" == "$(sha256sum "$FILES" | awk \
    '{print $1}')  $FILES" ]] && sha256sum --check --strict "${FILES}.sha256")
for archive in "$CONTROL" "$RUNTIME_IMAGES"; do
  [[ -f "$RECOVERY_DIR/$archive" && ! -L "$RECOVERY_DIR/$archive" ]]
  [[ -f "$RECOVERY_DIR/${archive}.sha256" && \
    ! -L "$RECOVERY_DIR/${archive}.sha256" ]]
  field=control
  [[ "$archive" == "$CONTROL" ]] || field=runtime_images
  [[ "$(sha256sum "$RECOVERY_DIR/$archive" | awk '{print $1}')" == \
    "$(jq -er --arg field "$field" '.[$field].sha256' "$RECORD")" ]]
  (cd "$RECOVERY_DIR" && \
    [[ "$(<"${archive}.sha256")" == "$(sha256sum "$archive" | awk \
      '{print $1}')  $archive" ]] && \
    sha256sum --check --strict "${archive}.sha256")
done
[[ -f "$RECOVERY_DIR/$CONTROL_MANIFEST" && \
  ! -L "$RECOVERY_DIR/$CONTROL_MANIFEST" ]]
[[ "$(sha256sum "$RECOVERY_DIR/$CONTROL_MANIFEST" | awk '{print $1}')" == \
  "$(jq -er '.control.manifest_sha256' "$RECORD")" ]]
tar --list --zstd --file "$RECOVERY_DIR/$CONTROL" | awk '
  $0 == "run.sh" { next }
  /^Authentik\/docker-compose[^/]*\.yaml[^/]*$/ { next }
  /\/(\.cache|__pycache__)(\/|$)/ { exit 1 }
  /^Authentik\/dockerfiles\// { next }
  /^Authentik\/scripts\// && $0 != "Authentik/scripts/backup.cron" { next }
  { exit 1 }
'
for path in ../Authentik/dockerfiles ../Authentik/scripts; do
  [[ -d "$path" && ! -L "$path" ]]
done
cmp -s \
  <(tar --list --zstd --file "$RECOVERY_DIR/$CONTROL" | LC_ALL=C sort) \
  <(cut -f1 "$RECOVERY_DIR/$CONTROL_MANIFEST" | LC_ALL=C sort)
cmp -s \
  <(tar --list --zstd --file "$RECOVERY_DIR/$CONTROL" | LC_ALL=C sort) \
  <(
    cd ..
    {
      printf '%s\n' run.sh
      find Authentik -xdev -maxdepth 1 -type f \
        -name 'docker-compose*.yaml*' -print
      find Authentik/dockerfiles -xdev -type f \
        ! -path '*/.cache/*' ! -path '*/__pycache__/*' -print
      find Authentik/scripts -xdev -type f ! -name backup.cron \
        ! -path '*/__pycache__/*' -print
    } | LC_ALL=C sort
  )
while IFS=$'\t' read -r path mode digest extra; do
  [[ -n "$path" && -z "$extra" ]]
  [[ "$path" != *$'\n'* && "$path" != *$'\r'* ]]
  [[ "$mode" =~ ^[0-7]{3,4}$ && "$digest" =~ ^[0-9a-f]{64}$ ]]
  [[ -f "../$path" && ! -L "../$path" && \
    "$(stat -Lc '%h:%a' -- "../$path")" == "1:$mode" ]]
  [[ "$(sha256sum "../$path" | awk '{print $1}')" == "$digest" ]]
done < "$RECOVERY_DIR/$CONTROL_MANIFEST"
[[ "$(sha256sum "$RECOVERY_DIR/versions.json" | awk '{print $1}')" == \
  "$(jq -er '.versions_sha256' "$RECORD")" ]]
mapfile -t RECORDED_IMAGE_IDS < <(jq -er \
  '.authentik.image_id,.postgresql.image_id,.postgresql.maintenance_image_id |
   select(test("^sha256:[0-9a-f]{64}$"))' "$RECOVERY_DIR/versions.json")
(( ${#RECORDED_IMAGE_IDS[@]} == 3 ))
mapfile -t RECORDED_IMAGE_REFS < <(jq -er \
  '.authentik.ref,.postgresql.ref,.postgresql.maintenance_ref |
   select(type == "string" and length > 0)' "$RECOVERY_DIR/versions.json")
(( ${#RECORDED_IMAGE_REFS[@]} == 3 ))
jq -e '.host as $host |
  ($host.os | test("^[a-z0-9]+$")) and
  ($host.architecture | test("^[a-z0-9_][a-z0-9_.-]*$")) and
  ([.authentik.platform,.postgresql.platform,
    .postgresql.maintenance_platform] | all(
      .os == $host.os and .architecture == $host.architecture and
      (.variant | test("^[a-z0-9_.-]*$"))))' \
  "$RECOVERY_DIR/versions.json" >/dev/null
[[ "$(jq -c '.host' "$RECORD")" == \
  "$(jq -c '.host' "$RECOVERY_DIR/versions.json")" ]]
TARGET_DOCKER_PLATFORM="$(docker version \
  --format '{{.Server.Os}}/{{.Server.Arch}}')"
[[ "$TARGET_DOCKER_PLATFORM" =~ ^linux/(amd64|arm64)$ ]]
TARGET_DOCKER_OS="${TARGET_DOCKER_PLATFORM%/*}"
TARGET_DOCKER_ARCH="${TARGET_DOCKER_PLATFORM#*/}"
[[ "$TARGET_DOCKER_OS" == \
  "$(jq -er '.host.os' "$RECOVERY_DIR/versions.json")" ]]
[[ "$TARGET_DOCKER_ARCH" == \
  "$(jq -er '.host.architecture' "$RECOVERY_DIR/versions.json")" ]]
[[ -n "$(jq -er '.authentik.version | select(length > 0)' \
  "$RECOVERY_DIR/versions.json")" ]]
[[ "$(jq -er '.authentik.digest' "$RECOVERY_DIR/versions.json")" == "$APP_DIGEST" ]]
[[ "$(sha256sum "$RECOVERY_DIR/templates.lock" | awk '{print $1}')" == \
  "$(jq -er '.locks.template_sha256' "$RECORD")" ]]
TEMPLATE_REVISION="$(jq -er '.locks.template_revision' "$RECORD")"
[[ "$(<"$RECOVERY_DIR/templates.lock")" == "$TEMPLATE_REVISION" ]]
SOURCE_STATE="$(jq -er '.locks.source_state' "$RECORD")"
FRESH_HOST=false
RESTORE_UNITS=(appdata app.env secrets scripts/backup.cron .run.conf)
PRESENT_UNITS=0
for path in "${RESTORE_UNITS[@]}"; do
  if [[ -e "$path" || -L "$path" ]]; then
    ((PRESENT_UNITS+=1))
  fi
done
if (( PRESENT_UNITS == 0 )); then
  FRESH_HOST=true
  [[ ! -e .env && ! -L .env ]]
else
  (( PRESENT_UNITS == ${#RESTORE_UNITS[@]} ))
fi
TEMPLATE_LOCK_ID=absent
SOURCE_LOCK_ID=absent
if [[ "$FRESH_HOST" != true ]]; then
  [[ -f .run.conf/.templates.lock && ! -L .run.conf/.templates.lock ]]
  cmp -s -- .run.conf/.templates.lock "$RECOVERY_DIR/templates.lock"
  TEMPLATE_LOCK_ID="$(stat -Lc '%d:%i' -- .run.conf/.templates.lock)"
fi
if [[ "$SOURCE_STATE" == present ]]; then
  [[ -f "$RECOVERY_DIR/source.lock" && ! -L "$RECOVERY_DIR/source.lock" ]]
  [[ "$(wc -l < "$RECOVERY_DIR/source.lock")" == 3 ]]
  [[ "$(sha256sum "$RECOVERY_DIR/source.lock" | awk '{print $1}')" == \
    "$(jq -er '.locks.source_sha256' "$RECORD")" ]]
  if [[ "$FRESH_HOST" != true ]]; then
    [[ -f .run.conf/.source.lock && ! -L .run.conf/.source.lock ]]
    cmp -s -- .run.conf/.source.lock "$RECOVERY_DIR/source.lock"
    SOURCE_LOCK_ID="$(stat -Lc '%d:%i' -- .run.conf/.source.lock)"
  fi
else
  [[ ! -e "$RECOVERY_DIR/source.lock" && ! -L "$RECOVERY_DIR/source.lock" ]]
  if [[ "$FRESH_HOST" != true ]]; then
    [[ ! -e .run.conf/.source.lock && ! -L .run.conf/.source.lock ]]
  fi
fi

for file in app.env merged.env expected-secrets.txt private-state.sha256; do
  [[ -f "$PRIVATE_DIR/$file" && ! -L "$PRIVATE_DIR/$file" ]]
done
[[ "$(sha256sum "$PRIVATE_DIR/private-state.sha256" | awk '{print $1}')" == \
  "$(jq -er '.private_manifest_sha256' "$RECORD")" ]]
(cd "$PRIVATE_DIR" && sha256sum --check --strict private-state.sha256)
EXPECTED_SECRETS="$(<"$PRIVATE_DIR/expected-secrets.txt")"
DECLARED_SECRETS="$(yq -er '.secrets | keys | .[]' "$COMPOSE_FILE" |
  LC_ALL=C sort)"
[[ "$DECLARED_SECRETS" == "$EXPECTED_SECRETS" ]]
PRIVATE_SECRETS="$(find -P "$PRIVATE_DIR/secrets" -mindepth 1 -maxdepth 1 \
  -type f -printf '%f\n' | LC_ALL=C sort)"
PRIVATE_UNSAFE="$(find -P "$PRIVATE_DIR/secrets" -mindepth 1 \
  \( ! -type f -o -type f ! -size +0c \) -print -quit)"
[[ -n "$EXPECTED_SECRETS" && "$PRIVATE_SECRETS" == "$EXPECTED_SECRETS" ]]
[[ -z "$PRIVATE_UNSAFE" ]]

tar --list --zstd --file "$RECOVERY_DIR/$FILES" | LC_ALL=C awk '
  /(^|\/)\.\.(\/|$)/ || /^\.\// || /\/\.\// { bad=1; next }
  /^appdata\/(data|custom-templates|certs)(\/|$)/ { next }
  /^scripts\/backup\.cron$/ { next }
  { bad=1 }
  END { exit bad }
'
STAGE="$(mktemp -d ./authentik-restore.XXXXXX)"
[[ "$(stat -Lc '%a:%d' -- "$STAGE")" == "700:$(stat -Lc '%d' -- .)" ]]
STAGE="$(readlink -e -- "$STAGE")"
tar --extract --zstd --file "$RECOVERY_DIR/$FILES" --directory "$STAGE" \
  --no-same-owner --no-same-permissions
mkdir -m 0700 -- "$STAGE/secrets" "$STAGE/.run.conf"
install -m 0600 -- "$RECOVERY_DIR/templates.lock" \
  "$STAGE/.run.conf/.templates.lock"
install -m 0600 /dev/null "$STAGE/app.env"
awk -v image="$APP_DIGEST" '
  BEGIN { count=0 }
  /^APP_IMAGE=/ { print "APP_IMAGE=" image; count++; next }
  { print }
  END { if (count != 1) exit 1 }
' "$PRIVATE_DIR/app.env" > "$STAGE/app.env"
RECOVERED_CONFIG="$(docker compose --project-name "$RECOVERY_PROJECT_NAME" \
  --project-directory "$STAGE" \
  --env-file "$BASE_ENV" --env-file "$STAGE/app.env" \
  -f "$COMPOSE_FILE" config --format json)"
RECOVERED_PROJECT="$(jq -er \
  '.name | select(test("^[a-z0-9][a-z0-9_-]*$"))' <<<"$RECOVERED_CONFIG")"
[[ "$RECOVERED_PROJECT" == "$RECOVERY_PROJECT_NAME" ]]
jq -e '.services.postgresql.build != null and
  .services.postgresql.image == null and
  .services.postgresql_maintenance.build != null and
  .services.postgresql_maintenance.image == null' \
  <<<"$RECOVERED_CONFIG" >/dev/null
[[ "$(jq -er '.postgresql.ref' "$RECOVERY_DIR/versions.json")" == \
  "${RECOVERED_PROJECT}-postgresql" ]]
[[ "$(jq -er '.postgresql.maintenance_ref' \
  "$RECOVERY_DIR/versions.json")" == \
  "${RECOVERED_PROJECT}-postgresql_maintenance" ]]
RECOVERED_IMAGES="$(docker compose --project-name "$RECOVERY_PROJECT_NAME" \
  --project-directory "$STAGE" \
  --env-file "$BASE_ENV" --env-file "$STAGE/app.env" \
  -f "$COMPOSE_FILE" config --images)"
grep -Fxq "${RECOVERED_PROJECT}-postgresql" <<<"$RECOVERED_IMAGES"
grep -Fxq "${RECOVERED_PROJECT}-postgresql_maintenance" \
  <<<"$RECOVERED_IMAGES"
RECOVERED_LOCAL_VOLUMES="$(jq -er '
  [.volumes // {} | to_entries[] |
    select(.value.external != true) | .value.name] |
  sort | if length > 0 and length == (unique | length) then .[]
  else error("missing or duplicate local volume names") end' \
  <<<"$RECOVERED_CONFIG")"
if [[ "$FRESH_HOST" == true ]]; then
  EXISTING_DOCKER_VOLUMES="$(docker volume ls --format '{{.Name}}')"
fi
while IFS= read -r volume; do
  [[ "$volume" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]
  if [[ "$FRESH_HOST" == true ]]; then
    ! grep -Fxq "$volume" <<<"$EXISTING_DOCKER_VOLUMES"
  fi
done <<<"$RECOVERED_LOCAL_VOLUMES"
RECOVERED_SMTP_ENABLED="$(jq -er \
  '.services.app.environment.AUTHENTIK_EMAIL_ENABLED |
   select(. == "true" or . == "false")' <<<"$RECOVERED_CONFIG")"
RECOVERED_SERVICE_SECRETS="$(jq -er '[.services[]?.secrets[]? |
  if type == "string" then . else .source end] | unique | .[]' \
  <<<"$RECOVERED_CONFIG" | LC_ALL=C sort)"
if [[ "$RECOVERED_SMTP_ENABLED" == true ]]; then
  grep -Fxq AUTHENTIK_EMAIL_PASSWORD <<<"$RECOVERED_SERVICE_SECRETS"
else
  ! grep -Fxq AUTHENTIK_EMAIL_PASSWORD <<<"$RECOVERED_SERVICE_SECRETS"
fi
while IFS= read -r name; do
  target="$STAGE/secrets/$name"
  if jq -e --arg name "$name" '.secrets[$name]' \
    <<<"$RECOVERED_CONFIG" >/dev/null; then
    [[ "$(jq -er --arg name "$name" '.secrets[$name].file' \
      <<<"$RECOVERED_CONFIG")" == "$target" ]]
  fi
  [[ "$target" == "$STAGE/secrets/$name" ]]
  install -m 0600 -- "$PRIVATE_DIR/secrets/$name" "$target"
done < "$PRIVATE_DIR/expected-secrets.txt"

STAGE_UNSAFE="$(find -P "$STAGE" -xdev \
  \( -type l -o -type b -o -type c -o -type p -o -type s \
    -o -type f -links +1 \) -print -quit)"
STAGE_MOUNTS="$(findmnt --json --list --output TARGET | jq -r \
  --arg root "$(readlink -e -- "$STAGE")" \
  '[.filesystems[]?.target | select(. == $root or startswith($root + "/"))] | length')"
[[ -z "$STAGE_UNSAFE" && "$STAGE_MOUNTS" == 0 ]]
PRIVATE_MODE_DRIFT="$(find -P "$STAGE" -xdev \
  \( -type d ! -perm 0700 -o -type f ! -perm 0600 \) -print -quit)"
[[ -z "$PRIVATE_MODE_DRIFT" ]]
APP_USER="$(jq -er '.services.app.user | select(test("^[0-9]+:[0-9]+$"))' \
  <<<"$RECOVERED_CONFIG")"
APP_UID="${APP_USER%%:*}"
APP_GID="${APP_USER##*:}"
for leaf in data custom-templates certs; do
  sudo chown -R -- "$APP_UID:$APP_GID" "$STAGE/appdata/$leaf"
  sudo find -P "$STAGE/appdata/$leaf" -xdev -type d -exec chmod 0770 -- {} +
  sudo find -P "$STAGE/appdata/$leaf" -xdev -type f -exec chmod 0660 -- {} +
done
chmod 0644 "$STAGE/scripts/backup.cron"
STAGE_IDS="$(stat -Lc '%d:%i %n' -- "$STAGE/appdata" \
  "$STAGE/appdata/data" "$STAGE/appdata/custom-templates" \
  "$STAGE/appdata/certs" "$STAGE/app.env" "$STAGE/secrets" \
  "$STAGE/scripts/backup.cron" \
  "$STAGE/.run.conf/.templates.lock")"

if [[ "$FRESH_HOST" == true ]]; then
  COMPOSE=(docker compose --project-name "$RECOVERY_PROJECT_NAME" \
    --env-file "$BASE_ENV" -f "$COMPOSE_FILE")
  CURRENT_CONFIG="$RECOVERED_CONFIG"
else
  [[ -f .env && ! -L .env ]]
  COMPOSE=(docker compose --project-name "$RECOVERY_PROJECT_NAME" \
    --env-file .env -f "$COMPOSE_FILE")
  CURRENT_CONFIG="$("${COMPOSE[@]}" config --format json)"
  [[ "$(jq -er '.name' <<<"$CURRENT_CONFIG")" == \
    "$RECOVERY_PROJECT_NAME" ]]
fi
PRE_SWAP_REF="$(jq -er '.services.app.image' <<<"$CURRENT_CONFIG")"
[[ "$PRE_SWAP_REF" != *'|'* && "$PRE_SWAP_REF" != *$'\t'* && \
  "$PRE_SWAP_REF" != *$'\n'* && "$PRE_SWAP_REF" != *$'\r'* ]]
PRE_SWAP_PROJECT="$(jq -er \
  '.name | select(test("^[a-z0-9][a-z0-9_-]*$"))' <<<"$CURRENT_CONFIG")"
jq -e '.services.postgresql.build != null and
  .services.postgresql.image == null and
  .services.postgresql_maintenance.build != null and
  .services.postgresql_maintenance.image == null' \
  <<<"$CURRENT_CONFIG" >/dev/null
PRE_SWAP_POSTGRES_REF="${PRE_SWAP_PROJECT}-postgresql"
PRE_SWAP_MAINTENANCE_REF="${PRE_SWAP_PROJECT}-postgresql_maintenance"
PRE_SWAP_CONFIG_IMAGES="$("${COMPOSE[@]}" config --images)"
grep -Fxq "$PRE_SWAP_POSTGRES_REF" <<<"$PRE_SWAP_CONFIG_IMAGES"
grep -Fxq "$PRE_SWAP_MAINTENANCE_REF" <<<"$PRE_SWAP_CONFIG_IMAGES"
PRE_SWAP_APP_CONTAINER="$("${COMPOSE[@]}" ps -a -q app)"
PRE_SWAP_WORKER_CONTAINER="$("${COMPOSE[@]}" ps -a -q authentik-worker)"
PRE_SWAP_BOOTSTRAP_CONTAINER="$("${COMPOSE[@]}" ps -a -q \
  authentik-bootstrap)"
PRE_SWAP_POSTGRES_CONTAINER="$("${COMPOSE[@]}" ps -a -q postgresql)"
PRE_SWAP_MAINTENANCE_CONTAINER="$("${COMPOSE[@]}" ps -a -q \
  postgresql_maintenance)"
declare -a PRE_SWAP_IMAGE_MAP=()
if [[ "$FRESH_HOST" == true ]]; then
  FRESH_CONTAINERS="$("${COMPOSE[@]}" ps -a -q)"
  [[ -z "$FRESH_CONTAINERS" ]]
  PRE_SWAP_DIGEST="$APP_DIGEST"
else
  PRE_SWAP_APP_REF_IMAGE="$(docker image inspect "$PRE_SWAP_REF" \
    --format '{{.Id}}')"
  [[ "$PRE_SWAP_APP_REF_IMAGE" =~ ^sha256:[0-9a-f]{64}$ ]]
  if [[ -n "$PRE_SWAP_APP_CONTAINER" ]]; then
    for id in "$PRE_SWAP_APP_CONTAINER" "$PRE_SWAP_WORKER_CONTAINER" \
      "$PRE_SWAP_BOOTSTRAP_CONTAINER"; do
      [[ "$id" =~ ^[0-9a-f]{64}$ ]]
    done
    PRE_SWAP_APP_IMAGE="$(docker inspect --format '{{.Image}}' \
      "$PRE_SWAP_APP_CONTAINER")"
    [[ "$(docker inspect --format '{{.Image}}' \
      "$PRE_SWAP_WORKER_CONTAINER")" == "$PRE_SWAP_APP_IMAGE" ]]
    [[ "$(docker inspect --format '{{.Image}}' \
      "$PRE_SWAP_BOOTSTRAP_CONTAINER")" == "$PRE_SWAP_APP_IMAGE" ]]
    [[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
      "$PRE_SWAP_BOOTSTRAP_CONTAINER")" == exited:0 ]]
  else
    PRE_SWAP_APP_IMAGE="$PRE_SWAP_APP_REF_IMAGE"
    for id in "$PRE_SWAP_WORKER_CONTAINER" "$PRE_SWAP_BOOTSTRAP_CONTAINER"; do
      [[ -z "$id" || "$id" =~ ^[0-9a-f]{64}$ ]]
      if [[ -n "$id" ]]; then
        [[ "$(docker inspect --format '{{.Image}}' "$id")" == \
          "$PRE_SWAP_APP_IMAGE" ]]
      fi
    done
    if [[ -n "$PRE_SWAP_BOOTSTRAP_CONTAINER" ]]; then
      [[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
        "$PRE_SWAP_BOOTSTRAP_CONTAINER")" == exited:0 ]]
    fi
  fi
  if [[ -n "$PRE_SWAP_POSTGRES_CONTAINER" ]]; then
    [[ "$PRE_SWAP_POSTGRES_CONTAINER" =~ ^[0-9a-f]{64}$ ]]
    PRE_SWAP_POSTGRES_IMAGE="$(docker inspect --format '{{.Image}}' \
      "$PRE_SWAP_POSTGRES_CONTAINER")"
  else
    PRE_SWAP_POSTGRES_IMAGE="$(docker image inspect \
      "$PRE_SWAP_POSTGRES_REF" --format '{{.Id}}')"
  fi
  if [[ -n "$PRE_SWAP_MAINTENANCE_CONTAINER" ]]; then
    [[ "$PRE_SWAP_MAINTENANCE_CONTAINER" =~ ^[0-9a-f]{64}$ ]]
    PRE_SWAP_MAINTENANCE_IMAGE="$(docker inspect --format '{{.Image}}' \
      "$PRE_SWAP_MAINTENANCE_CONTAINER")"
  else
    PRE_SWAP_MAINTENANCE_IMAGE="$(docker image inspect \
      "$PRE_SWAP_MAINTENANCE_REF" --format '{{.Id}}')"
  fi
  for id in "$PRE_SWAP_APP_IMAGE" "$PRE_SWAP_APP_REF_IMAGE" \
    "$PRE_SWAP_POSTGRES_IMAGE" "$PRE_SWAP_MAINTENANCE_IMAGE"; do
    [[ "$id" =~ ^sha256:[0-9a-f]{64}$ ]]
  done
  [[ "$(docker image inspect "$PRE_SWAP_POSTGRES_REF" --format '{{.Id}}')" == \
    "$PRE_SWAP_POSTGRES_IMAGE" ]]
  [[ "$(docker image inspect "$PRE_SWAP_MAINTENANCE_REF" --format '{{.Id}}')" == \
    "$PRE_SWAP_MAINTENANCE_IMAGE" ]]
  PRE_SWAP_IMAGE_MAP+=("$PRE_SWAP_REF|$PRE_SWAP_APP_REF_IMAGE")
  PRE_SWAP_IMAGE_MAP+=("$PRE_SWAP_POSTGRES_REF|$PRE_SWAP_POSTGRES_IMAGE")
  PRE_SWAP_IMAGE_MAP+=("$PRE_SWAP_MAINTENANCE_REF|$PRE_SWAP_MAINTENANCE_IMAGE")
  PRE_SWAP_DIGEST="$(docker image inspect "$PRE_SWAP_APP_IMAGE" \
    --format '{{json .RepoDigests}}' | jq -er \
    '[.[] | select(startswith("ghcr.io/goauthentik/server@sha256:"))] |
      if length == 1 then .[0] else error("expected one digest") end')"
fi
DB_ROLLBACK_DIR="$(mktemp -d ../authentik-db-rollback.XXXXXX)"
[[ "$(stat -Lc '%a:%d' -- "$DB_ROLLBACK_DIR")" == \
  "700:$(stat -Lc '%d' -- .)" ]]
DB_ROLLBACK_DIR="$(readlink -e -- "$DB_ROLLBACK_DIR")"
if [[ "$FRESH_HOST" == true ]]; then
  jq -n --argjson volumes "$(jq -c \
    '[.volumes // {} | to_entries[] | select(.value.external != true) |
      .value.name] | sort' <<<"$RECOVERED_CONFIG")" \
    '{version:1,kind:"new-host-none",preexisting_volumes:false,
      volumes:$volumes}' > "$DB_ROLLBACK_DIR/rollback.json"
else
  CURRENT_LOCAL_VOLUMES="$(jq -er '
    [.volumes // {} | to_entries[] | select(.value.external != true) |
      .value.name] | sort | if length > 0 then .[] else error end' \
    <<<"$CURRENT_CONFIG")"
  read -r -p 'Pre-restore DB rollback mode (maintenance/provider): ' \
    DB_ROLLBACK_MODE
  case "$DB_ROLLBACK_MODE" in
    maintenance)
      "${COMPOSE[@]}" stop app authentik-worker authentik-bootstrap
      "${COMPOSE[@]}" up -d --wait --wait-timeout 120 \
        --no-build --pull never postgresql
      "${COMPOSE[@]}" up -d --no-build --pull never \
        postgresql_maintenance
      "${COMPOSE[@]}" exec -T postgresql_maintenance \
        /usr/local/bin/backup.sh full
      "${COMPOSE[@]}" exec -T postgresql_maintenance \
        /usr/local/bin/backup.sh dump
      read -r -p 'Pre-restore physical backup ID (YYYYMMDD_N): ' \
        DB_ROLLBACK_PHYSICAL_ID
      read -r -p 'Pre-restore logical backup ID (YYYYMMDD_HHMMSS): ' \
        DB_ROLLBACK_LOGICAL_ID
      [[ "$DB_ROLLBACK_PHYSICAL_ID" =~ ^[0-9]{8}_[0-9]{1,9}$ ]]
      [[ "$DB_ROLLBACK_LOGICAL_ID" =~ ^[0-9]{8}_[0-9]{6}$ ]]
      DB_ROLLBACK_PHYSICAL="backup/${DB_ROLLBACK_PHYSICAL_ID%%_*}/full_${DB_ROLLBACK_PHYSICAL_ID}.tar.zst"
      DB_ROLLBACK_LOGICAL="backup/${DB_ROLLBACK_LOGICAL_ID%%_*}/dump_${DB_ROLLBACK_LOGICAL_ID}.dump.zst"
      DB_ROLLBACK_PHYSICAL_MANIFEST="${DB_ROLLBACK_PHYSICAL%.tar.zst}.manifest"
      declare -a DB_ROLLBACK_FILES=(
        "$DB_ROLLBACK_PHYSICAL"
        "${DB_ROLLBACK_PHYSICAL}.sha256"
        "${DB_ROLLBACK_PHYSICAL%/*}/bundle_full_${DB_ROLLBACK_PHYSICAL_ID}.sha256"
        "$DB_ROLLBACK_PHYSICAL_MANIFEST"
        "$DB_ROLLBACK_LOGICAL"
        "${DB_ROLLBACK_LOGICAL}.sha256"
        "${DB_ROLLBACK_LOGICAL%/*}/bundle_dump_${DB_ROLLBACK_LOGICAL_ID}.sha256"
      )
      cmp -s -- "${DB_ROLLBACK_PHYSICAL}.sha256" \
        "${DB_ROLLBACK_PHYSICAL%/*}/bundle_full_${DB_ROLLBACK_PHYSICAL_ID}.sha256"
      cmp -s -- "${DB_ROLLBACK_LOGICAL}.sha256" \
        "${DB_ROLLBACK_LOGICAL%/*}/bundle_dump_${DB_ROLLBACK_LOGICAL_ID}.sha256"
      (cd "${DB_ROLLBACK_PHYSICAL%/*}" && sha256sum --check --strict \
        "${DB_ROLLBACK_PHYSICAL##*/}.sha256")
      (cd "${DB_ROLLBACK_LOGICAL%/*}" && sha256sum --check --strict \
        "${DB_ROLLBACK_LOGICAL##*/}.sha256")
      for file in "${DB_ROLLBACK_FILES[@]}"; do
        [[ -f "$file" && ! -L "$file" && -s "$file" ]]
        sudo install -m 0600 -- "$file" "$DB_ROLLBACK_DIR/${file##*/}"
      done
      sudo chown -R -- "$(id -u):$(id -g)" "$DB_ROLLBACK_DIR"
      (
        cd "$DB_ROLLBACK_DIR"
        sha256sum -- full_* bundle_full_* dump_* bundle_dump_* \
          > payload.sha256
        chmod 0600 payload.sha256
        sha256sum --check --strict payload.sha256
      )
      jq -n --arg physical_id "$DB_ROLLBACK_PHYSICAL_ID" \
        --arg logical_id "$DB_ROLLBACK_LOGICAL_ID" \
        --arg payload_sha "$(sha256sum \
          "$DB_ROLLBACK_DIR/payload.sha256" | awk '{print $1}')" \
        '{version:1,kind:"maintenance",physical_id:$physical_id,
          logical_id:$logical_id,payload_manifest_sha256:$payload_sha}' \
        > "$DB_ROLLBACK_DIR/rollback.json"
      ;;
    provider)
      "${COMPOSE[@]}" stop app authentik-worker authentik-bootstrap \
        postgresql_maintenance postgresql
      RUNNING_CONTAINERS="$("${COMPOSE[@]}" ps --status running -q)"
      [[ -z "$RUNNING_CONTAINERS" ]]
      read -r -p 'Absolute provider snapshot manifest path: ' \
        PROVIDER_SNAPSHOT_MANIFEST
      [[ "$PROVIDER_SNAPSHOT_MANIFEST" == /* ]]
      PROVIDER_SNAPSHOT_MANIFEST="$(readlink -e -- \
        "$PROVIDER_SNAPSHOT_MANIFEST")"
      [[ -f "$PROVIDER_SNAPSHOT_MANIFEST" && \
        ! -L "$PROVIDER_SNAPSHOT_MANIFEST" ]]
      [[ "$(stat -Lc '%a:%u:%g' -- "$PROVIDER_SNAPSHOT_MANIFEST")" == \
        "600:$(id -u):$(id -g)" ]]
      jq -e '.version == 1 and .kind == "provider" and
        (.provider | test("^[a-zA-Z0-9_.-]+$")) and
        (.snapshot_id | type == "string") and (.snapshot_id | length > 0) and
        (.created_utc | test("^[0-9]{8}T[0-9]{6}Z$")) and
        (.volumes | type == "array" and length > 0 and
          length == (unique | length) and all(test("^[a-zA-Z0-9_.-]+$"))) and
        (.restore_runbook | test("^/")) and
        (.restore_runbook_sha256 | test("^[0-9a-f]{64}$")) and
        .operator_approval == "approved"' \
        "$PROVIDER_SNAPSHOT_MANIFEST" >/dev/null
      [[ "$(jq -r '.volumes[]' "$PROVIDER_SNAPSHOT_MANIFEST" | \
        LC_ALL=C sort)" == "$CURRENT_LOCAL_VOLUMES" ]]
      PROVIDER_RESTORE_RUNBOOK="$(jq -er '.restore_runbook' \
        "$PROVIDER_SNAPSHOT_MANIFEST")"
      PROVIDER_RESTORE_RUNBOOK="$(readlink -e -- "$PROVIDER_RESTORE_RUNBOOK")"
      [[ -f "$PROVIDER_RESTORE_RUNBOOK" && ! -L "$PROVIDER_RESTORE_RUNBOOK" ]]
      [[ "$(sha256sum "$PROVIDER_RESTORE_RUNBOOK" | awk '{print $1}')" == \
        "$(jq -er '.restore_runbook_sha256' \
          "$PROVIDER_SNAPSHOT_MANIFEST")" ]]
      install -m 0600 -- "$PROVIDER_SNAPSHOT_MANIFEST" \
        "$DB_ROLLBACK_DIR/provider-snapshot.json"
      install -m 0600 -- "$PROVIDER_RESTORE_RUNBOOK" \
        "$DB_ROLLBACK_DIR/provider-restore.runbook"
      (
        cd "$DB_ROLLBACK_DIR"
        sha256sum -- provider-snapshot.json provider-restore.runbook \
          > payload.sha256
        chmod 0600 payload.sha256
        sha256sum --check --strict payload.sha256
      )
      jq -n --arg payload_sha "$(sha256sum \
        "$DB_ROLLBACK_DIR/payload.sha256" | awk '{print $1}')" \
        '{version:1,kind:"provider",payload_manifest_sha256:$payload_sha}' \
        > "$DB_ROLLBACK_DIR/rollback.json"
      ;;
    *) exit 64 ;;
  esac
fi
chmod 0600 "$DB_ROLLBACK_DIR/rollback.json"
[[ -z "$(find -P "$DB_ROLLBACK_DIR" -xdev \
  \( -type d ! -perm 0700 -o -type f ! -perm 0600 -o \
    ! -type d ! -type f \) -print -quit)" ]]
FRESH_PLACEHOLDERS_CREATED=false
rollback_fresh_preflight() {
  local status=$? path quarantine
  trap - ERR
  if [[ "$FRESH_HOST" == true && \
    "$FRESH_PLACEHOLDERS_CREATED" == true ]]; then
    quarantine="$(mktemp -d ../authentik-fresh-preflight-failed.XXXXXX)" || \
      return 125
    [[ "$(stat -Lc '%a:%d' -- "$quarantine")" == \
      "700:$(stat -Lc '%d' -- .)" ]] || return 125
    for path in appdata app.env secrets scripts/backup.cron .run.conf .env \
      docker-compose.main.yaml; do
      if [[ -e "$path" || -L "$path" ]]; then
        sudo mv -- "$path" "$quarantine/" || return 125
      fi
    done
    [[ ! -e appdata && ! -e app.env && ! -e secrets && \
      ! -e scripts/backup.cron && ! -e .run.conf && ! -e .env && \
      ! -e docker-compose.main.yaml ]] || return 125
  fi
  return "$status"
}
trap rollback_fresh_preflight ERR
"${COMPOSE[@]}" down
RUNNING_CONTAINERS="$("${COMPOSE[@]}" ps --status running -q)"
[[ -z "$RUNNING_CONTAINERS" ]]
if [[ "$FRESH_HOST" == true ]]; then
  FRESH_PLACEHOLDERS_CREATED=true
  mkdir -m 0700 -- appdata appdata/data appdata/custom-templates \
    appdata/certs secrets .run.conf
  install -m 0600 -- "$STAGE/app.env" app.env
  while IFS= read -r name; do
    install -m 0600 -- "$STAGE/secrets/$name" "secrets/$name"
  done < "$PRIVATE_DIR/expected-secrets.txt"
  install -m 0644 -- "$STAGE/scripts/backup.cron" scripts/backup.cron
  install -m 0600 -- "$RECOVERY_DIR/templates.lock" \
    .run.conf/.templates.lock
  TEMPLATE_LOCK_ID="$(stat -Lc '%d:%i' -- .run.conf/.templates.lock)"
  if [[ "$SOURCE_STATE" == present ]]; then
    install -m 0600 -- "$RECOVERY_DIR/source.lock" .run.conf/.source.lock
    SOURCE_LOCK_ID="$(stat -Lc '%d:%i' -- .run.conf/.source.lock)"
  fi
fi
LIVE_ROOT="$(readlink -e -- appdata)"
[[ -d appdata && ! -L appdata && "$LIVE_ROOT" == "$(pwd -P)/appdata" ]]
for path in app.env scripts/backup.cron .run.conf/.templates.lock; do
  [[ -f "$path" && ! -L "$path" ]]
done
for path in secrets scripts .run.conf; do
  [[ -d "$path" && ! -L "$path" ]]
done
LIVE_UNSAFE="$(find -P appdata -xdev \
  \( -type l -o -type b -o -type c -o -type p -o -type s \
    -o -type f -links +1 \) -print -quit)"
LIVE_SECRET_UNSAFE="$(find -P secrets -xdev -mindepth 1 \
  \( ! -type f -o -type f -links +1 \) -print -quit)"
[[ -z "$LIVE_UNSAFE" && -z "$LIVE_SECRET_UNSAFE" ]]
MOUNT_UNITS=(appdata secrets app.env scripts scripts/backup.cron \
  .run.conf .run.conf/.templates.lock)
if [[ "$SOURCE_STATE" == present ]]; then
  MOUNT_UNITS+=(.run.conf/.source.lock)
fi
for path in "${MOUNT_UNITS[@]}"; do
  canonical="$(readlink -e -- "$path")"
  [[ "$(findmnt --json --list --output TARGET | jq -r \
    --arg root "$canonical" \
    '[.filesystems[]?.target |
      select(. == $root or startswith($root + "/"))] | length')" == 0 ]]
done
PROJECT_DEVICE="$(stat -Lc '%d' -- .)"
for path in appdata app.env secrets scripts scripts/backup.cron \
  .run.conf .run.conf/.templates.lock \
  "$STAGE/appdata" "$STAGE/app.env" "$STAGE/secrets" \
  "$STAGE/scripts" "$STAGE/scripts/backup.cron" "$STAGE/.run.conf" \
  "$STAGE/.run.conf/.templates.lock"; do
  [[ "$(stat -Lc '%d' -- "$path")" == "$PROJECT_DEVICE" ]]
done
if [[ "$SOURCE_STATE" == present ]]; then
  [[ "$(stat -Lc '%d' -- .run.conf/.source.lock)" == "$PROJECT_DEVICE" ]]
fi
LIVE_IDS="$(stat -Lc '%d:%i %n' -- appdata appdata/data \
  appdata/custom-templates appdata/certs app.env secrets scripts/backup.cron \
  .run.conf/.templates.lock)"
[[ "$(stat -Lc '%d:%i %n' -- "$STAGE/appdata" \
  "$STAGE/appdata/data" "$STAGE/appdata/custom-templates" \
  "$STAGE/appdata/certs" "$STAGE/app.env" "$STAGE/secrets" \
  "$STAGE/scripts/backup.cron" \
  "$STAGE/.run.conf/.templates.lock")" == "$STAGE_IDS" ]]

OLD="$(mktemp -d ../authentik-pre-restore.XXXXXX)"
mkdir -m 0700 -- "$OLD/scripts" "$OLD/.run.conf"
[[ "$(stat -Lc '%a:%d' -- "$OLD")" == "700:$PROJECT_DEVICE" ]]
mv -- "$DB_ROLLBACK_DIR" "$OLD/database"
DB_ROLLBACK_DIR="$OLD/database"
[[ "$(stat -Lc '%a:%d' -- "$DB_ROLLBACK_DIR")" == \
  "700:$PROJECT_DEVICE" ]]
printf '%s\n' "$PRE_SWAP_DIGEST" > "$OLD/pre-swap-authentik-digest"
chmod 0600 "$OLD/pre-swap-authentik-digest"
if [[ "$FRESH_HOST" != true ]]; then
  install -m 0600 /dev/null "$OLD/pre-swap-images.tsv"
  for mapping in "${PRE_SWAP_IMAGE_MAP[@]}"; do
    IFS='|' read -r ref image_id <<<"$mapping"
    printf '%s\t%s\n' "$ref" "$image_id" >> "$OLD/pre-swap-images.tsv"
  done
  [[ "$(wc -l < "$OLD/pre-swap-images.tsv")" == 3 ]]
fi
APP_ENV_MODE="$(stat -Lc '%a' -- app.env)"
install -m 0600 -- app.env "$OLD/pre-swap-app.env"
declare -a SWAPPED=()
MERGE_ATTEMPTED=false
RUNTIME_IMAGES_LOAD_STARTED=false
swap_unit() {
  local live="$1" candidate="$2" old="$3"
  if ! sudo mv -- "$live" "$old"; then
    return 1
  fi
  if ! sudo mv -- "$candidate" "$live"; then
    sudo mv -- "$old" "$live"
    return 1
  fi
  SWAPPED+=("$live|$candidate|$old")
}
rollback_partial_swap() {
  local status=$? item live candidate old i temporary rollback_config \
    mapping ref image_id
  trap - ERR
  for ((i=${#SWAPPED[@]}-1; i>=0; i--)); do
    item="${SWAPPED[$i]}"
    IFS='|' read -r live candidate old <<<"$item"
    sudo mv -- "$live" "$candidate"
    sudo mv -- "$old" "$live"
  done
  if [[ "$FRESH_HOST" == true ]]; then
    mkdir -m 0700 -- "$OLD/fresh-failed-root" || return 125
    for live in appdata app.env secrets scripts/backup.cron .run.conf .env \
      docker-compose.main.yaml; do
      if [[ -e "$live" || -L "$live" ]]; then
        sudo mv -- "$live" "$OLD/fresh-failed-root/" || return 125
      fi
    done
    [[ ! -e appdata && ! -e app.env && ! -e secrets && \
      ! -e scripts/backup.cron && ! -e .run.conf && ! -e .env && \
      ! -e docker-compose.main.yaml ]] || return 125
    return "$status"
  fi
  if [[ "$RUNTIME_IMAGES_LOAD_STARTED" == true && \
    "$FRESH_HOST" != true ]]; then
    for mapping in "${PRE_SWAP_IMAGE_MAP[@]}"; do
      IFS='|' read -r ref image_id <<<"$mapping"
      if [[ "$ref" == *@sha256:* ]]; then
        [[ "$(docker image inspect "$ref" --format '{{.Id}}')" == "$image_id" ]] || \
          return 125
      else
        docker image tag "$image_id" "$ref" >/dev/null || return 125
        [[ "$(docker image inspect "$ref" --format '{{.Id}}')" == \
          "$image_id" ]] || return 125
      fi
    done
  fi
  if [[ "$MERGE_ATTEMPTED" == true || \
    "$RUNTIME_IMAGES_LOAD_STARTED" == true ]]; then
    temporary="$(mktemp ./app.env.rollback.XXXXXX)"
    awk -v image="$PRE_SWAP_DIGEST" '
      BEGIN { count=0 }
      /^APP_IMAGE=/ { print "APP_IMAGE=" image; count++; next }
      { print }
      END { if (count != 1) exit 1 }
    ' "$OLD/pre-swap-app.env" > "$temporary"
    chmod "$APP_ENV_MODE" "$temporary"
    mv -fT -- "$temporary" app.env
    (cd .. && ./run.sh Authentik) || return 125
    rollback_config="$("${COMPOSE[@]}" config --format json)" || return 125
    [[ "$(jq -er '.name' <<<"$rollback_config")" == \
      "$RECOVERY_PROJECT_NAME" ]] || return 125
    for service in app authentik-bootstrap authentik-worker; do
      [[ "$(jq -er --arg service "$service" '.services[$service].image' \
        <<<"$rollback_config")" == "$PRE_SWAP_DIGEST" ]] || return 125
    done
  fi
  return "$status"
}
trap rollback_partial_swap ERR
RUNTIME_IMAGES_LOAD_STARTED=true
docker image load --input "$RECOVERY_DIR/$RUNTIME_IMAGES" >/dev/null
verify_loaded_image() {
  local ref id expected actual
  ref="$(jq -er "$1" "$RECOVERY_DIR/versions.json")"
  id="$(jq -er "$2" "$RECOVERY_DIR/versions.json")"
  expected="$(jq -cer "$3" "$RECOVERY_DIR/versions.json")"
  [[ "$(docker image inspect "$ref" --format '{{.Id}}')" == "$id" ]]
  actual="$(docker image inspect "$ref" --format '{{json .}}' | jq -cer \
    '{os:.Os,architecture:.Architecture,variant:(.Variant // "")}')"
  [[ "$actual" == "$expected" ]]
}
verify_loaded_image '.authentik.ref' '.authentik.image_id' \
  '.authentik.platform'
verify_loaded_image '.postgresql.ref' '.postgresql.image_id' \
  '.postgresql.platform'
verify_loaded_image '.postgresql.maintenance_ref' \
  '.postgresql.maintenance_image_id' '.postgresql.maintenance_platform'
[[ "$(docker image inspect "$APP_DIGEST" --format '{{.Id}}')" == \
  "$(jq -er '.authentik.image_id' "$RECOVERY_DIR/versions.json")" ]]
[[ "$(stat -Lc '%d:%i %n' -- appdata appdata/data \
  appdata/custom-templates appdata/certs app.env secrets scripts/backup.cron \
  .run.conf/.templates.lock)" == "$LIVE_IDS" ]]
[[ "$(stat -Lc '%d:%i' -- .run.conf/.templates.lock)" == "$TEMPLATE_LOCK_ID" ]]
cmp -s -- .run.conf/.templates.lock "$RECOVERY_DIR/templates.lock"
if [[ "$SOURCE_STATE" == present ]]; then
  [[ "$(stat -Lc '%d:%i' -- .run.conf/.source.lock)" == "$SOURCE_LOCK_ID" ]]
fi
swap_unit appdata "$STAGE/appdata" "$OLD/appdata"
swap_unit app.env "$STAGE/app.env" "$OLD/app.env"
swap_unit secrets "$STAGE/secrets" "$OLD/secrets"
swap_unit scripts/backup.cron "$STAGE/scripts/backup.cron" "$OLD/scripts/backup.cron"
swap_unit .run.conf/.templates.lock "$STAGE/.run.conf/.templates.lock" \
  "$OLD/.run.conf/.templates.lock"

# Normæl locked merge only: never use --force or refresh either lock here.
MERGE_ATTEMPTED=true
(cd .. && ./run.sh Authentik)
COMPOSE=(docker compose --project-name "$RECOVERY_PROJECT_NAME" \
  --env-file .env -f "$COMPOSE_FILE")
LIVE_CONFIG="$("${COMPOSE[@]}" config --format json)"
[[ "$(jq -er '.name' <<<"$LIVE_CONFIG")" == "$RECOVERY_PROJECT_NAME" ]]
LIVE_IMAGES="$("${COMPOSE[@]}" config --images)"
grep -Fxq "$(jq -er '.postgresql.ref' \
  "$RECOVERY_DIR/versions.json")" <<<"$LIVE_IMAGES"
grep -Fxq "$(jq -er '.postgresql.maintenance_ref' \
  "$RECOVERY_DIR/versions.json")" <<<"$LIVE_IMAGES"
LIVE_LOCAL_VOLUMES="$(jq -er '
  [.volumes // {} | to_entries[] | select(.value.external != true) |
    .value.name] | sort | if length > 0 then .[] else error end' \
  <<<"$LIVE_CONFIG")"
[[ "$LIVE_LOCAL_VOLUMES" == "$RECOVERED_LOCAL_VOLUMES" ]]
[[ "$(<.run.conf/.templates.lock)" == "$TEMPLATE_REVISION" ]]
[[ "$(sha256sum .run.conf/.templates.lock | awk '{print $1}')" == \
  "$(jq -er '.locks.template_sha256' "$RECORD")" ]]
if [[ "$SOURCE_STATE" == present ]]; then
  [[ "$(stat -Lc '%d:%i' -- .run.conf/.source.lock)" == "$SOURCE_LOCK_ID" ]]
  cmp -s -- .run.conf/.source.lock "$RECOVERY_DIR/source.lock"
else
  [[ ! -e .run.conf/.source.lock && ! -L .run.conf/.source.lock ]]
fi
for service in app authentik-bootstrap authentik-worker; do
  [[ "$(jq -er --arg service "$service" '.services[$service].image' \
    <<<"$LIVE_CONFIG")" == "$APP_DIGEST" ]]
done
LIVE_SECRETS="$(yq -er '.secrets | keys | .[]' "$COMPOSE_FILE" |
  LC_ALL=C sort)"
[[ "$LIVE_SECRETS" == "$EXPECTED_SECRETS" ]]
while IFS= read -r name; do
  path="secrets/$name"
  [[ -f "$path" && ! -L "$path" && -s "$path" ]]
  [[ "$(stat -Lc '%a:%g' -- "$path")" == "640:$APP_GID" ]]
done < "$PRIVATE_DIR/expected-secrets.txt"
for leaf in appdata/data appdata/custom-templates appdata/certs; do
  [[ -z "$(sudo find -P "$leaf" -xdev \
    \( ! -uid "$APP_UID" -o ! -gid "$APP_GID" -o -type d ! -perm 0770 \
      -o -type f ! -perm 0660 \) -print -quit)" ]]
done
trap - ERR
rmdir -- "$STAGE/scripts" "$STAGE/.run.conf" "$STAGE"
```

The stæge begins mode `0700` with recovered sensitive files mode `0600`.
Before swæp, the three bind-mount leæves receive the documented runtime
ownership/modes; the normæl `run.sh` merge then normælizes rendered secrets to
`APP_GID`/`0640`. The postconditions verify both. Keep `OLD`, the restored
cændidæte, ænd æ mætching pre-swæp dætæbæse snæpshot until finæl proof succeeds.

### Restore exæctly one PostgreSQL formæt

Copy the selected bundle næmed by `recovery.json` into `restore/` with its
strict sidecær ænd `bundle_*.sha256`; physicæl restore ælso needs its
`.manifest`. Follow the complete
[`postgresql_maintenance` restore contræct](../templates/postgresql_maintenance/README.md#restore).
Choose **one** pæth; never run both.

First prove thæt the locæl built dætæbæse imæges still equæl the bound
version record:

```bash
PROJECT_NAME="$("${COMPOSE[@]}" config --format json | jq -er '.name')"
[[ "$(docker image inspect "${PROJECT_NAME}-postgresql" --format '{{.Id}}')" == \
  "$(jq -er '.postgresql.image_id' "$RECOVERY_DIR/versions.json")" ]]
[[ "$(docker image inspect "${PROJECT_NAME}-postgresql_maintenance" \
  --format '{{.Id}}')" == "$(jq -er \
  '.postgresql.maintenance_image_id' "$RECOVERY_DIR/versions.json")" ]]
```

For æ **physicæl** restore, PostgreSQL ænd every writer/mæintenænce service
must remæin stopped. Dry-run uses the reæd-only bæse service; only æpply uses
the versioned write override:

```bash
PHYSICAL_ID="$(jq -er '.postgresql.physical.id' "$RECORD")"
PHYSICAL="restore/full_${PHYSICAL_ID}.tar.zst"
PHYSICAL_MANIFEST="restore/full_${PHYSICAL_ID}.manifest"
[[ "$(sha256sum "$PHYSICAL" | awk '{print $1}')" == \
  "$(jq -er '.postgresql.physical.sha256' "$RECORD")" ]]
[[ "$(sha256sum "$PHYSICAL_MANIFEST" | awk '{print $1}')" == \
  "$(jq -er '.postgresql.physical.manifest_sha256' "$RECORD")" ]]
RUNNING="$("${COMPOSE[@]}" ps --status running -q)"
[[ -z "$RUNNING" ]]
"${COMPOSE[@]}" -f docker-compose.postgresql_maintenance.restore.yaml.example \
  config --quiet
"${COMPOSE[@]}" run --rm \
  --no-deps --pull never -e POSTGRES_RESTORE_BACKUP_ID="$PHYSICAL_ID" \
  -e POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED=true \
  postgresql_maintenance restore --dry-run
"${COMPOSE[@]}" -f docker-compose.postgresql_maintenance.restore.yaml.example \
  run --rm \
  --no-deps --pull never -e POSTGRES_RESTORE_BACKUP_ID="$PHYSICAL_ID" \
  -e POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED=true \
  postgresql_maintenance restore
```

For æ **logicæl** restore, only PostgreSQL is running ænd heælthy; server,
worker, bootstræp, ænd scheduled mæintenænce stæy stopped. Both explicit
populæted-dætæbæse replæcement guærds ære required:

```bash
LOGICAL_ID="$(jq -er '.postgresql.logical.id' "$RECORD")"
LOGICAL="restore/dump_${LOGICAL_ID}.dump.zst"
[[ "$(sha256sum "$LOGICAL" | awk '{print $1}')" == \
  "$(jq -er '.postgresql.logical.sha256' "$RECORD")" ]]
"${COMPOSE[@]}" up -d --wait \
  --wait-timeout 120 --no-build --pull never postgresql
POSTGRES_CONTAINER="$("${COMPOSE[@]}" ps -q postgresql)"
[[ "$(docker inspect --format '{{.Image}}' "$POSTGRES_CONTAINER")" == \
  "$(jq -er '.postgresql.image_id' "$RECOVERY_DIR/versions.json")" ]]
UNEXPECTED="$("${COMPOSE[@]}" ps --status running -q \
  app authentik-bootstrap authentik-worker \
  postgresql_maintenance)"
[[ -z "$UNEXPECTED" ]]
for mode in dry-run apply; do
  restore_args=()
  [[ "$mode" == apply ]] || restore_args+=(--dry-run)
  "${COMPOSE[@]}" run --rm \
    --no-deps --pull never -e POSTGRES_RESTORE_BACKUP_ID="$LOGICAL_ID" \
    -e POSTGRES_RESTORE_RECREATE_DATABASE=true \
    -e POSTGRES_RESTORE_CONFIRM_DATABASE_REPLACEMENT=true \
    postgresql_maintenance restore-dump "${restore_args[@]}"
done
```

Do not interrupt æ quiet long restore. Dry-run ænd æpply must eæch report
explicit success ænd exit zero. Before either pæth, confirm the locæl
PostgreSQL ænd mæintenænce imæge IDs equæl those in bound `versions.json`;
`--no-build --pull never` then prevents re-resolution.

Æfter one successful dætæbæse pæth:

```bash
"${COMPOSE[@]}" up -d --wait --wait-timeout 120 \
  --no-build --pull never postgresql
"${COMPOSE[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never app authentik-worker
BOOTSTRAP_ID="$("${COMPOSE[@]}" ps -a -q authentik-bootstrap)"
APP_ID="$("${COMPOSE[@]}" ps -q app)"
WORKER_ID="$("${COMPOSE[@]}" ps -q authentik-worker)"
for id in "$APP_ID" "$WORKER_ID" "$BOOTSTRAP_ID"; do
  [[ "$id" =~ ^[0-9a-f]{64}$ ]]
done
[[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
  "$BOOTSTRAP_ID")" == exited:0 ]]
for id in "$APP_ID" "$WORKER_ID" "$BOOTSTRAP_ID"; do
  [[ "$(docker inspect --format '{{.Image}}' "$id")" == \
    "$(jq -er '.authentik.image_id' "$RECOVERY_DIR/versions.json")" ]]
done
"${COMPOSE[@]}" up -d --no-build --pull never postgresql_maintenance
"${COMPOSE[@]}" exec -T postgresql_maintenance \
  /usr/local/bin/backup.sh full
"${COMPOSE[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never postgresql_maintenance
```

If æny post-restore proof fæils, keep the project stopped ænd inspect
`$OLD/database/rollback.json`. For `kind=maintenance`, restore the copied
pre-swæp physicæl bundle through the sæme dry-run/override pæth:

```bash
DB_ROLLBACK_RECORD="$OLD/database/rollback.json"
[[ -f "$DB_ROLLBACK_RECORD" && ! -L "$DB_ROLLBACK_RECORD" ]]
[[ "$(jq -er '.kind' "$DB_ROLLBACK_RECORD")" == maintenance ]]
[[ "$(sha256sum "$OLD/database/payload.sha256" | awk '{print $1}')" == \
  "$(jq -er '.payload_manifest_sha256' "$DB_ROLLBACK_RECORD")" ]]
(cd "$OLD/database" && sha256sum --check --strict payload.sha256)
DB_ROLLBACK_ID="$(jq -er '.physical_id |
  select(test("^[0-9]{8}_[0-9]{1,9}$"))' "$DB_ROLLBACK_RECORD")"
"${COMPOSE[@]}" down
RUNNING_CONTAINERS="$("${COMPOSE[@]}" ps --status running -q)"
[[ -z "$RUNNING_CONTAINERS" ]]
[[ -f "$OLD/pre-swap-images.tsv" && ! -L "$OLD/pre-swap-images.tsv" && \
  "$(stat -Lc '%a' -- "$OLD/pre-swap-images.tsv")" == 600 ]]
while IFS=$'\t' read -r ref image_id extra; do
  [[ -n "$ref" && -z "$extra" && \
    "$image_id" =~ ^sha256:[0-9a-f]{64}$ ]]
  [[ "$(docker image inspect "$image_id" --format '{{.Id}}')" == "$image_id" ]]
  if [[ "$ref" == *@sha256:* ]]; then
    [[ "$(docker image inspect "$ref" --format '{{.Id}}')" == "$image_id" ]]
  else
    docker image tag "$image_id" "$ref" >/dev/null
    [[ "$(docker image inspect "$ref" --format '{{.Id}}')" == "$image_id" ]]
  fi
done < "$OLD/pre-swap-images.tsv"
POSTGRES_RUNTIME_USER="$("${COMPOSE[@]}" config --format json | jq -er \
  '.services.postgresql.user | select(test("^[0-9]+:[0-9]+$"))')"
for file in "full_${DB_ROLLBACK_ID}.tar.zst" \
  "full_${DB_ROLLBACK_ID}.tar.zst.sha256" \
  "bundle_full_${DB_ROLLBACK_ID}.sha256" \
  "full_${DB_ROLLBACK_ID}.manifest"; do
  sudo install -o "${POSTGRES_RUNTIME_USER%%:*}" \
    -g "${POSTGRES_RUNTIME_USER##*:}" -m 0600 -- \
    "$OLD/database/$file" "restore/$file"
done
"${COMPOSE[@]}" run --rm --no-deps --pull never \
  -e POSTGRES_RESTORE_BACKUP_ID="$DB_ROLLBACK_ID" \
  -e POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED=true \
  postgresql_maintenance restore --dry-run
"${COMPOSE[@]}" -f docker-compose.postgresql_maintenance.restore.yaml.example \
  run --rm --no-deps --pull never \
  -e POSTGRES_RESTORE_BACKUP_ID="$DB_ROLLBACK_ID" \
  -e POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED=true \
  postgresql_maintenance restore
```

For `kind=provider`, verify `payload.sha256`, keep every contæiner stopped,
ænd follow only the bound `$OLD/database/provider-restore.runbook` for the
exæct provider/source/snæpshot ID in `provider-snapshot.json`; then repeæt its
documented integrity test. `kind=new-host-none` proves there wæs no prior
dætæbæse: quæræntine the fæiled cændidæte volume. Never delete it unless its
exæct næme wæs recorded æbsent, it wæs creæted by this ættempt, ænd æ
stopped inspection proves it empty.

The scheduler is intentionælly excluded from the first `--wait`: without æ
fresh success mærker its heælthcheck cæn need the 70-minute stært period. The
explicit successful full bæckup creætes thæt mærker before the bounded wæit.
Then run server/worker/PostgreSQL/mæintenænce heælth, `akadmin`, SMTP, OIDC/SÆML,
outpost, certificæte, ællowed/denied-user, ænd fresh full-bæckup tests before
reopening træffic.

If the swæp itself fæils, its træp returns every completed unit in reverse
order. For æ læter proof fæilure, keep æll services stopped, move the fæiled
live units into æ new mode-`0700` sæme-filesystem sibling, move `OLD` units
bæck in reverse order, then rewrite restored `app.env` to the digest in
`OLD/pre-swap-authentik-digest` **before** the normæl locked merge. Preserve
the originæl moving `app.env` bytes beside the fæiled set. Never use `--force`
or refresh either lock. Restore the independently mætching pre-swæp dætæbæse
or provider snæpshot before `--no-build --pull never` stærtup; moving files
bæck cænnot undo æ logicæl or physicæl dætæbæse replæcement.

---

## Updætes & Migrætions

`APP_IMAGE=ghcr.io/goauthentik/server:2026.5`, both `postgres:18` bæses, ænd
the Supercronic `releases/latest` fetch ære moving inputs. Therefore do not use
the generæl `run.sh --update` pæth here: it would rebuild both custom dætæbæse
outputs. This controlled pæth binds current ænd tærget Æuthentik,
PostgreSQL, ænd mæintenænce outputs. Phæse 1 discovers ænd builds the
tærget while current contæiners keep running, restores every moving/local tæg,
ænd requires æn explicit releæse review. Only phæse 2 stops the stæck ænd
stærts the ælreædy bound outputs with `--no-build --pull never`.

Immediætely before Phæse 1, creæte one complete recovery point with the
runbook æbove ænd copy its public/privæte pæir ænd PostgreSQL bundles off-host.
The ID records the **stært** of recovery-point creætion, not its completion.
Set `RECOVERY_MAX_AGE_SECONDS` below to the æpproved chænge-window limit thæt
still covers the meæsured creætion time, record thæt limit, ænd never increæse
it merely to æccept æn old set. The gæte requires the operætor-entered ID to
mætch the record ænd both directory næmes, proves freshness, ænd verifies every
bound public ærchive, lock, privæte mænifest, ænd PostgreSQL bundle before it
discovers æ new imæge.

```bash
# Phæse 1: discover, build, restore current tægs, ænd review while live.
set -euo pipefail
umask 077
COMPOSE=(docker compose --env-file .env -f docker-compose.main.yaml)
CONFIG="$("${COMPOSE[@]}" config --format json)"
CHANNEL="$(jq -er '.services.app.image' <<<"$CONFIG")"
[[ "$CHANNEL" == ghcr.io/goauthentik/server:2026.5 ]]
PROJECT_NAME="$(jq -er \
  '.name | select(test("^[a-z0-9][a-z0-9_-]*$"))' <<<"$CONFIG")"
jq -e '.services.postgresql.build != null and
  .services.postgresql.image == null and
  .services.postgresql_maintenance.build != null and
  .services.postgresql_maintenance.image == null' <<<"$CONFIG" >/dev/null
POSTGRES_REF="${PROJECT_NAME}-postgresql"
MAINTENANCE_REF="${PROJECT_NAME}-postgresql_maintenance"
CONFIG_IMAGES="$("${COMPOSE[@]}" config --images)"
grep -Fxq "$POSTGRES_REF" <<<"$CONFIG_IMAGES"
grep -Fxq "$MAINTENANCE_REF" <<<"$CONFIG_IMAGES"
POSTGRES_BASE_REF="$(jq -er \
  '.services.postgresql.build.args.POSTGRES_IMAGE' <<<"$CONFIG")"
MAINTENANCE_BASE_REF="$(jq -er \
  '.services.postgresql_maintenance.build.args.POSTGRES_MAINTENANCE_IMAGE' \
  <<<"$CONFIG")"

CURRENT_APP_CONTAINER="$("${COMPOSE[@]}" ps -q app)"
CURRENT_WORKER_CONTAINER="$("${COMPOSE[@]}" ps -q authentik-worker)"
CURRENT_BOOTSTRAP_CONTAINER="$("${COMPOSE[@]}" ps -a -q authentik-bootstrap)"
CURRENT_POSTGRES_CONTAINER="$("${COMPOSE[@]}" ps -q postgresql)"
CURRENT_MAINTENANCE_CONTAINER="$("${COMPOSE[@]}" ps -q postgresql_maintenance)"
for id in "$CURRENT_APP_CONTAINER" "$CURRENT_WORKER_CONTAINER" \
  "$CURRENT_BOOTSTRAP_CONTAINER" "$CURRENT_POSTGRES_CONTAINER" \
  "$CURRENT_MAINTENANCE_CONTAINER"; do
  [[ "$id" =~ ^[0-9a-f]{64}$ ]]
done
CURRENT_APP_IMAGE="$(docker inspect --format '{{.Image}}' "$CURRENT_APP_CONTAINER")"
[[ "$(docker inspect --format '{{.Image}}' "$CURRENT_WORKER_CONTAINER")" == \
  "$CURRENT_APP_IMAGE" ]]
[[ "$(docker inspect --format '{{.Image}}' "$CURRENT_BOOTSTRAP_CONTAINER")" == \
  "$CURRENT_APP_IMAGE" ]]
[[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
  "$CURRENT_BOOTSTRAP_CONTAINER")" == exited:0 ]]
CURRENT_POSTGRES_IMAGE="$(docker inspect --format '{{.Image}}' \
  "$CURRENT_POSTGRES_CONTAINER")"
CURRENT_MAINTENANCE_IMAGE="$(docker inspect --format '{{.Image}}' \
  "$CURRENT_MAINTENANCE_CONTAINER")"
[[ "$(docker image inspect "$POSTGRES_REF" --format '{{.Id}}')" == \
  "$CURRENT_POSTGRES_IMAGE" ]]
[[ "$(docker image inspect "$MAINTENANCE_REF" --format '{{.Id}}')" == \
  "$CURRENT_MAINTENANCE_IMAGE" ]]
CURRENT_DIGEST="$(docker image inspect "$CURRENT_APP_IMAGE" \
  --format '{{json .RepoDigests}}' | jq -er \
  '[.[] | select(startswith("ghcr.io/goauthentik/server@sha256:"))] |
    if length == 1 then .[0] else error("expected one current digest") end')"
CURRENT_VERSION="$(docker image inspect "$CURRENT_APP_IMAGE" \
  --format '{{index .Config.Labels "org.opencontainers.image.version"}}')"
CURRENT_CHANNEL_REF_IMAGE="$(docker image inspect "$CHANNEL" --format '{{.Id}}')"
CURRENT_POSTGRES_BASE_REF_IMAGE="$(docker image inspect "$POSTGRES_BASE_REF" \
  --format '{{.Id}}')"
CURRENT_MAINTENANCE_BASE_REF_IMAGE="$(docker image inspect \
  "$MAINTENANCE_BASE_REF" --format '{{.Id}}')"
for id in "$CURRENT_APP_IMAGE" "$CURRENT_CHANNEL_REF_IMAGE" \
  "$CURRENT_POSTGRES_IMAGE" "$CURRENT_MAINTENANCE_IMAGE" \
  "$CURRENT_POSTGRES_BASE_REF_IMAGE" "$CURRENT_MAINTENANCE_BASE_REF_IMAGE"; do
  [[ "$id" =~ ^sha256:[0-9a-f]{64}$ ]]
done

VERIFIED_RECOVERY=../authentik-recovery-20260820T120000Z/recovery.json
VERIFIED_PRIVATE=../authentik-private-20260820T120000Z
read -r -p 'Approved recovery ID (YYYYMMDDTHHMMSSZ): ' APPROVED_RECOVERY_ID
read -r -p 'Approved maximum recovery age in seconds: ' RECOVERY_MAX_AGE_SECONDS
[[ "$APPROVED_RECOVERY_ID" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
[[ "$RECOVERY_MAX_AGE_SECONDS" =~ ^[1-9][0-9]*$ ]]

RECOVERY_DIR="${VERIFIED_RECOVERY%/*}"
PRIVATE_DIR="$VERIFIED_PRIVATE"
for path in "$RECOVERY_DIR" "$PRIVATE_DIR" "$PRIVATE_DIR/secrets"; do
  [[ -d "$path" && ! -L "$path" ]]
  [[ "$(stat -Lc '%a:%u:%g' -- "$path")" == \
    "700:$(id -u):$(id -g)" ]]
done
RECOVERY_DIR="$(readlink -e -- "$RECOVERY_DIR")"
PRIVATE_DIR="$(readlink -e -- "$PRIVATE_DIR")"
VERIFIED_RECOVERY="$RECOVERY_DIR/recovery.json"
[[ -f "$VERIFIED_RECOVERY" && ! -L "$VERIFIED_RECOVERY" ]]
[[ -f "${VERIFIED_RECOVERY}.sha256" && ! -L "${VERIFIED_RECOVERY}.sha256" ]]
(cd "$RECOVERY_DIR" && \
  [[ "$(<recovery.json.sha256)" == \
    "$(sha256sum recovery.json | awk '{print $1}')  recovery.json" ]] && \
  sha256sum --check --strict recovery.json.sha256)
jq -e '
  .version == 2 and (.id | test("^[0-9]{8}T[0-9]{6}Z$")) and
  (.files.name == ("authentik-files-" + .id + ".tar.zst")) and
  (.control.name == ("authentik-control-" + .id + ".tar.zst")) and
  (.control.manifest == ("authentik-control-" + .id + ".manifest")) and
  (.runtime_images.name == ("authentik-runtime-images-" + .id + ".tar")) and
  (.locks.template_revision | test("^([0-9a-f]{40}|[0-9a-f]{64})$")) and
  (.postgresql.physical.id | test("^[0-9]{8}_[0-9]{1,9}$")) and
  (.postgresql.logical.id | test("^[0-9]{8}_[0-9]{6}$")) and
  ([.files.sha256,.control.sha256,.control.manifest_sha256,
    .runtime_images.sha256,.versions_sha256,.private_manifest_sha256,
    .locks.template_sha256,.postgresql.physical.sha256,
    .postgresql.physical.manifest_sha256,.postgresql.logical.sha256] |
    all(test("^[0-9a-f]{64}$")))
' "$VERIFIED_RECOVERY" >/dev/null
RECOVERY_ID="$(jq -er '.id' "$VERIFIED_RECOVERY")"
[[ "$RECOVERY_ID" == "$APPROVED_RECOVERY_ID" ]]
[[ "${RECOVERY_DIR##*/}" == "authentik-recovery-${RECOVERY_ID}" ]]
[[ "${PRIVATE_DIR##*/}" == "authentik-private-${RECOVERY_ID}" ]]
[[ "$(jq -er '.project_name' "$VERIFIED_RECOVERY")" == "$PROJECT_NAME" ]]
RECOVERY_EPOCH="$(date -u -d \
  "${RECOVERY_ID:0:8} ${RECOVERY_ID:9:2}:${RECOVERY_ID:11:2}:${RECOVERY_ID:13:2} UTC" +%s)"
NOW_EPOCH="$(date -u +%s)"
(( RECOVERY_EPOCH <= NOW_EPOCH ))
(( NOW_EPOCH - RECOVERY_EPOCH <= RECOVERY_MAX_AGE_SECONDS ))

for field in files control runtime_images; do
  archive="$(jq -er --arg field "$field" '.[$field].name' "$VERIFIED_RECOVERY")"
  [[ "$archive" != */* && -f "$RECOVERY_DIR/$archive" && \
    ! -L "$RECOVERY_DIR/$archive" ]]
  [[ -f "$RECOVERY_DIR/${archive}.sha256" && \
    ! -L "$RECOVERY_DIR/${archive}.sha256" ]]
  [[ "$(sha256sum "$RECOVERY_DIR/$archive" | awk '{print $1}')" == \
    "$(jq -er --arg field "$field" '.[$field].sha256' "$VERIFIED_RECOVERY")" ]]
  (cd "$RECOVERY_DIR" && sha256sum --check --strict "${archive}.sha256")
done
RECOVERY_CONTROL_MANIFEST="$(jq -er '.control.manifest' "$VERIFIED_RECOVERY")"
[[ "$RECOVERY_CONTROL_MANIFEST" != */* && \
  -f "$RECOVERY_DIR/$RECOVERY_CONTROL_MANIFEST" && \
  ! -L "$RECOVERY_DIR/$RECOVERY_CONTROL_MANIFEST" ]]
[[ "$(sha256sum "$RECOVERY_DIR/$RECOVERY_CONTROL_MANIFEST" | awk '{print $1}')" == \
  "$(jq -er '.control.manifest_sha256' "$VERIFIED_RECOVERY")" ]]
RECOVERY_VERSIONS="$RECOVERY_DIR/versions.json"
[[ -f "$RECOVERY_VERSIONS" && ! -L "$RECOVERY_VERSIONS" ]]
[[ "$(sha256sum "$RECOVERY_VERSIONS" | awk '{print $1}')" == \
  "$(jq -er '.versions_sha256' "$VERIFIED_RECOVERY")" ]]
[[ "$(jq -er '.authentik.image_id' "$RECOVERY_VERSIONS")" == \
  "$CURRENT_APP_IMAGE" ]]
[[ -f "$RECOVERY_DIR/templates.lock" && ! -L "$RECOVERY_DIR/templates.lock" ]]
[[ "$(sha256sum "$RECOVERY_DIR/templates.lock" | awk '{print $1}')" == \
  "$(jq -er '.locks.template_sha256' "$VERIFIED_RECOVERY")" ]]
[[ "$(<"$RECOVERY_DIR/templates.lock")" == \
  "$(jq -er '.locks.template_revision' "$VERIFIED_RECOVERY")" ]]
if [[ "$(jq -er '.locks.source_state' "$VERIFIED_RECOVERY")" == present ]]; then
  [[ -f "$RECOVERY_DIR/source.lock" && ! -L "$RECOVERY_DIR/source.lock" ]]
  [[ "$(sha256sum "$RECOVERY_DIR/source.lock" | awk '{print $1}')" == \
    "$(jq -er '.locks.source_sha256' "$VERIFIED_RECOVERY")" ]]
else
  [[ "$(jq -er '.locks.source_state' "$VERIFIED_RECOVERY")" == absent ]]
  [[ ! -e "$RECOVERY_DIR/source.lock" && ! -L "$RECOVERY_DIR/source.lock" ]]
fi
[[ -f "$PRIVATE_DIR/private-state.sha256" && \
  ! -L "$PRIVATE_DIR/private-state.sha256" ]]
[[ "$(sha256sum "$PRIVATE_DIR/private-state.sha256" | awk '{print $1}')" == \
  "$(jq -er '.private_manifest_sha256' "$VERIFIED_RECOVERY")" ]]
(cd "$PRIVATE_DIR" && sha256sum --check --strict private-state.sha256)

PHYSICAL_ID="$(jq -er '.postgresql.physical.id' "$VERIFIED_RECOVERY")"
LOGICAL_ID="$(jq -er '.postgresql.logical.id' "$VERIFIED_RECOVERY")"
PHYSICAL_ARCHIVE="backup/${PHYSICAL_ID%%_*}/full_${PHYSICAL_ID}.tar.zst"
LOGICAL_ARCHIVE="backup/${LOGICAL_ID%%_*}/dump_${LOGICAL_ID}.dump.zst"
PHYSICAL_MANIFEST="${PHYSICAL_ARCHIVE%.tar.zst}.manifest"
for archive in "$PHYSICAL_ARCHIVE" "$LOGICAL_ARCHIVE"; do
  [[ -f "$archive" && ! -L "$archive" ]]
  [[ -f "${archive}.sha256" && ! -L "${archive}.sha256" ]]
  stem="${archive##*/}"
  stem="${stem%.tar.zst}"
  stem="${stem%.dump.zst}"
  [[ -f "${archive%/*}/bundle_${stem}.sha256" && \
    ! -L "${archive%/*}/bundle_${stem}.sha256" ]]
  cmp -s -- "${archive}.sha256" "${archive%/*}/bundle_${stem}.sha256"
  (cd "${archive%/*}" && sha256sum --check --strict "${archive##*/}.sha256")
done
[[ "$(sha256sum "$PHYSICAL_ARCHIVE" | awk '{print $1}')" == \
  "$(jq -er '.postgresql.physical.sha256' "$VERIFIED_RECOVERY")" ]]
[[ -f "$PHYSICAL_MANIFEST" && ! -L "$PHYSICAL_MANIFEST" ]]
[[ "$(sha256sum "$PHYSICAL_MANIFEST" | awk '{print $1}')" == \
  "$(jq -er '.postgresql.physical.manifest_sha256' "$VERIFIED_RECOVERY")" ]]
[[ "$(sha256sum "$LOGICAL_ARCHIVE" | awk '{print $1}')" == \
  "$(jq -er '.postgresql.logical.sha256' "$VERIFIED_RECOVERY")" ]]
[[ "$(jq -er '.authentik_digest' "$VERIFIED_RECOVERY")" == "$CURRENT_DIGEST" ]]
[[ "$(jq -er '.postgresql.image_id' "$RECOVERY_VERSIONS")" == \
  "$CURRENT_POSTGRES_IMAGE" ]]
[[ "$(jq -er '.postgresql.maintenance_image_id' "$RECOVERY_VERSIONS")" == \
  "$CURRENT_MAINTENANCE_IMAGE" ]]

UPDATE_DIR="$(mktemp -d ../authentik-update.XXXXXX)"
[[ "$(stat -Lc '%a:%u:%g' -- "$UPDATE_DIR")" == \
  "700:$(id -u):$(id -g)" ]]
docker run --rm --pull never --entrypoint postgres "$CURRENT_POSTGRES_IMAGE" \
  --version > "$UPDATE_DIR/current-postgresql-version.txt"
docker run --rm --pull never --entrypoint cat "$CURRENT_MAINTENANCE_IMAGE" \
  /usr/local/share/supercronic-release \
  > "$UPDATE_DIR/current-supercronic-release.txt"
chmod 0600 "$UPDATE_DIR"/*.txt

DISCOVERY_TAGS_MUTATED=false
restore_current_tags() {
  docker image tag "$CURRENT_CHANNEL_REF_IMAGE" "$CHANNEL" >/dev/null
  docker image tag "$CURRENT_POSTGRES_IMAGE" "$POSTGRES_REF" >/dev/null
  docker image tag "$CURRENT_MAINTENANCE_IMAGE" "$MAINTENANCE_REF" >/dev/null
  docker image tag "$CURRENT_POSTGRES_BASE_REF_IMAGE" \
    "$POSTGRES_BASE_REF" >/dev/null
  docker image tag "$CURRENT_MAINTENANCE_BASE_REF_IMAGE" \
    "$MAINTENANCE_BASE_REF" >/dev/null
}
rollback_discovery() {
  local status=$?
  trap - ERR
  if [[ "$DISCOVERY_TAGS_MUTATED" == true ]]; then
    restore_current_tags || return 125
  fi
  return "$status"
}
trap rollback_discovery ERR
DISCOVERY_TAGS_MUTATED=true
docker pull "$CHANNEL"
docker pull "$POSTGRES_BASE_REF"
[[ "$MAINTENANCE_BASE_REF" == "$POSTGRES_BASE_REF" ]] || \
  docker pull "$MAINTENANCE_BASE_REF"
TARGET_APP_IMAGE="$(docker image inspect "$CHANNEL" --format '{{.Id}}')"
TARGET_DIGEST="$(docker image inspect "$TARGET_APP_IMAGE" \
  --format '{{json .RepoDigests}}' | jq -er \
  '[.[] | select(startswith("ghcr.io/goauthentik/server@sha256:"))] |
    if length == 1 then .[0] else error("expected one target digest") end')"
TARGET_VERSION="$(docker image inspect "$TARGET_APP_IMAGE" \
  --format '{{index .Config.Labels "org.opencontainers.image.version"}}')"
TARGET_POSTGRES_BASE_IMAGE="$(docker image inspect "$POSTGRES_BASE_REF" \
  --format '{{.Id}}')"
TARGET_POSTGRES_BASE_DIGEST="$(docker image inspect "$POSTGRES_BASE_REF" \
  --format '{{json .RepoDigests}}' | jq -er \
  '[.[] | select(startswith("postgres@sha256:"))] |
   if length == 1 then .[0] else error("expected one PostgreSQL digest") end')"
TARGET_MAINTENANCE_BASE_IMAGE="$(docker image inspect "$MAINTENANCE_BASE_REF" \
  --format '{{.Id}}')"
TARGET_MAINTENANCE_BASE_DIGEST="$(docker image inspect "$MAINTENANCE_BASE_REF" \
  --format '{{json .RepoDigests}}' | jq -er \
  '[.[] | select(startswith("postgres@sha256:"))] |
   if length == 1 then .[0] else error("expected one maintenance-base digest") end')"
printf 'POSTGRES_IMAGE=%s\nPOSTGRES_MAINTENANCE_IMAGE=%s\n' \
  "$TARGET_POSTGRES_BASE_DIGEST" "$TARGET_MAINTENANCE_BASE_DIGEST" \
  > "$UPDATE_DIR/target-bases.env"
chmod 0600 "$UPDATE_DIR/target-bases.env"
BUILD_COMPOSE=(docker compose --env-file .env \
  --env-file "$UPDATE_DIR/target-bases.env" -f docker-compose.main.yaml)
"${BUILD_COMPOSE[@]}" build --pull --no-cache \
  postgresql postgresql_maintenance
TARGET_POSTGRES_IMAGE="$(docker image inspect "$POSTGRES_REF" --format '{{.Id}}')"
TARGET_MAINTENANCE_IMAGE="$(docker image inspect "$MAINTENANCE_REF" \
  --format '{{.Id}}')"
docker run --rm --pull never --entrypoint postgres "$TARGET_POSTGRES_IMAGE" \
  --version > "$UPDATE_DIR/target-postgresql-version.txt"
docker run --rm --pull never --entrypoint cat "$TARGET_MAINTENANCE_IMAGE" \
  /usr/local/share/supercronic-release \
  > "$UPDATE_DIR/target-supercronic-release.txt"
chmod 0600 "$UPDATE_DIR"/target-*.txt
TARGET_SUPERCRONIC_RELEASE="$(sed -n 's/^release=//p' \
  "$UPDATE_DIR/target-supercronic-release.txt")"
TARGET_SUPERCRONIC_ASSET="$(sed -n 's/^asset=//p' \
  "$UPDATE_DIR/target-supercronic-release.txt")"
TARGET_SUPERCRONIC_DIGEST="$(sed -n 's/^digest=//p' \
  "$UPDATE_DIR/target-supercronic-release.txt")"
[[ "$TARGET_SUPERCRONIC_RELEASE" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$TARGET_SUPERCRONIC_ASSET" =~ ^supercronic-linux-(amd64|arm64)$ ]]
[[ "$TARGET_SUPERCRONIC_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]
[[ "$CURRENT_APP_IMAGE" =~ ^sha256:[0-9a-f]{64}$ ]]
[[ "$TARGET_APP_IMAGE" =~ ^sha256:[0-9a-f]{64}$ ]]
[[ "$TARGET_POSTGRES_IMAGE" =~ ^sha256:[0-9a-f]{64}$ ]]
[[ "$TARGET_MAINTENANCE_IMAGE" =~ ^sha256:[0-9a-f]{64}$ ]]
[[ -n "$CURRENT_VERSION" && "$CURRENT_VERSION" != '<no value>' ]]
[[ -n "$TARGET_VERSION" && "$TARGET_VERSION" != '<no value>' ]]

restore_current_tags
DISCOVERY_TAGS_MUTATED=false
trap - ERR
[[ "$(docker image inspect "$CHANNEL" --format '{{.Id}}')" == \
  "$CURRENT_CHANNEL_REF_IMAGE" ]]
[[ "$(docker image inspect "$POSTGRES_REF" --format '{{.Id}}')" == \
  "$CURRENT_POSTGRES_IMAGE" ]]
[[ "$(docker image inspect "$MAINTENANCE_REF" --format '{{.Id}}')" == \
  "$CURRENT_MAINTENANCE_IMAGE" ]]
for pair in "app:$CURRENT_APP_IMAGE" \
  "authentik-worker:$CURRENT_APP_IMAGE" \
  "postgresql:$CURRENT_POSTGRES_IMAGE" \
  "postgresql_maintenance:$CURRENT_MAINTENANCE_IMAGE"; do
  service="${pair%%:*}"
  image_id="${pair#*:}"
  [[ "$(docker inspect --format '{{.Image}}' \
    "$("${COMPOSE[@]}" ps -q "$service")")" == "$image_id" ]]
done
[[ "$(docker inspect --format '{{.Image}}' \
  "$("${COMPOSE[@]}" ps -a -q authentik-bootstrap)")" == \
  "$CURRENT_APP_IMAGE" ]]

RELEASE_NOTES_REVIEW="$UPDATE_DIR/release-notes-review.txt"
TARGET_SERIES="$(sed -nE 's/^([0-9]{4}\.[0-9]+)\..*$/\1/p' \
  <<<"$TARGET_VERSION")"
[[ "$TARGET_SERIES" == 2026.5 ]]
TARGET_POSTGRES_VERSION="$(<"$UPDATE_DIR/target-postgresql-version.txt")"
[[ "$TARGET_POSTGRES_VERSION" == *'PostgreSQL 18'* ]]
printf '%s\n' \
  "current_version=$CURRENT_VERSION" \
  "target_version=$TARGET_VERSION" \
  "postgres_base_digest=$TARGET_POSTGRES_BASE_DIGEST" \
  "maintenance_base_digest=$TARGET_MAINTENANCE_BASE_DIGEST" \
  "target_postgresql_version=$TARGET_POSTGRES_VERSION" \
  "supercronic_release=$TARGET_SUPERCRONIC_RELEASE" \
  "supercronic_asset=$TARGET_SUPERCRONIC_ASSET" \
  "supercronic_digest=$TARGET_SUPERCRONIC_DIGEST" \
  "reviewed_url=https://docs.goauthentik.io/releases/$TARGET_SERIES/" \
  'reviewed_url=https://www.postgresql.org/docs/18/release.html' \
  "reviewed_url=https://github.com/aptible/supercronic/releases/tag/$TARGET_SUPERCRONIC_RELEASE" \
  'operator_approval=REPLACE_WITH_APPROVED' > "$RELEASE_NOTES_REVIEW"
chmod 0600 "$RELEASE_NOTES_REVIEW"
printf 'Review every URL in %s, then change only the final value to approved.\n' \
  "$RELEASE_NOTES_REVIEW"
read -r -p 'Type REVIEWED after saving the reviewed file: ' REVIEW_CONFIRMATION
[[ "$REVIEW_CONFIRMATION" == REVIEWED ]]
[[ -f "$RELEASE_NOTES_REVIEW" && ! -L "$RELEASE_NOTES_REVIEW" ]]
grep -Fx "current_version=$CURRENT_VERSION" "$RELEASE_NOTES_REVIEW"
grep -Fx "target_version=$TARGET_VERSION" "$RELEASE_NOTES_REVIEW"
grep -Fx "postgres_base_digest=$TARGET_POSTGRES_BASE_DIGEST" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx "maintenance_base_digest=$TARGET_MAINTENANCE_BASE_DIGEST" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx "supercronic_release=$TARGET_SUPERCRONIC_RELEASE" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx "target_postgresql_version=$TARGET_POSTGRES_VERSION" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx "supercronic_asset=$TARGET_SUPERCRONIC_ASSET" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx "supercronic_digest=$TARGET_SUPERCRONIC_DIGEST" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx "reviewed_url=https://docs.goauthentik.io/releases/$TARGET_SERIES/" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx 'reviewed_url=https://www.postgresql.org/docs/18/release.html' \
  "$RELEASE_NOTES_REVIEW"
grep -Fx "reviewed_url=https://github.com/aptible/supercronic/releases/tag/$TARGET_SUPERCRONIC_RELEASE" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx 'operator_approval=approved' "$RELEASE_NOTES_REVIEW"
[[ "$(wc -l < "$RELEASE_NOTES_REVIEW")" == 12 ]]

install -m 0600 -- "$RELEASE_NOTES_REVIEW" "$UPDATE_DIR/release-notes.txt"
jq -n --arg channel "$CHANNEL" --arg current_image "$CURRENT_APP_IMAGE" \
  --arg current_channel_ref_image "$CURRENT_CHANNEL_REF_IMAGE" \
  --arg current_digest "$CURRENT_DIGEST" --arg current_version "$CURRENT_VERSION" \
  --arg target_image "$TARGET_APP_IMAGE" --arg target_digest "$TARGET_DIGEST" \
  --arg target_version "$TARGET_VERSION" \
  --arg current_postgresql "$CURRENT_POSTGRES_IMAGE" \
  --arg target_postgresql "$TARGET_POSTGRES_IMAGE" \
  --arg current_maintenance "$CURRENT_MAINTENANCE_IMAGE" \
  --arg target_maintenance "$TARGET_MAINTENANCE_IMAGE" \
  --arg postgres_base_ref "$POSTGRES_BASE_REF" \
  --arg current_postgres_base "$CURRENT_POSTGRES_BASE_REF_IMAGE" \
  --arg postgres_base_image "$TARGET_POSTGRES_BASE_IMAGE" \
  --arg postgres_base_digest "$TARGET_POSTGRES_BASE_DIGEST" \
  --arg maintenance_base_ref "$MAINTENANCE_BASE_REF" \
  --arg current_maintenance_base "$CURRENT_MAINTENANCE_BASE_REF_IMAGE" \
  --arg maintenance_base_image "$TARGET_MAINTENANCE_BASE_IMAGE" \
  --arg maintenance_base_digest "$TARGET_MAINTENANCE_BASE_DIGEST" \
  --arg current_pg_sha "$(sha256sum "$UPDATE_DIR/current-postgresql-version.txt" | awk '{print $1}')" \
  --arg target_pg_sha "$(sha256sum "$UPDATE_DIR/target-postgresql-version.txt" | awk '{print $1}')" \
  --arg current_sc_sha "$(sha256sum "$UPDATE_DIR/current-supercronic-release.txt" | awk '{print $1}')" \
  --arg target_sc_sha "$(sha256sum "$UPDATE_DIR/target-supercronic-release.txt" | awk '{print $1}')" \
  --arg recovery_id "$(jq -er '.id' "$VERIFIED_RECOVERY")" \
  --arg recovery_sha "$(sha256sum "$VERIFIED_RECOVERY" | awk '{print $1}')" \
  --arg release_notes_sha "$(sha256sum "$UPDATE_DIR/release-notes.txt" | awk '{print $1}')" \
  '{channel:$channel,current:{image_id:$current_image,
    channel_image_id:$current_channel_ref_image,digest:$current_digest,
    version:$current_version},target:{image_id:$target_image,digest:$target_digest,
    version:$target_version},postgresql:{current_image_id:$current_postgresql,
      target_image_id:$target_postgresql,base:{ref:$postgres_base_ref,
        current_image_id:$current_postgres_base,
        target_image_id:$postgres_base_image,digest:$postgres_base_digest},
      current_version_sha256:$current_pg_sha,target_version_sha256:$target_pg_sha},
    maintenance:{current_image_id:$current_maintenance,
      target_image_id:$target_maintenance,base:{ref:$maintenance_base_ref,
        current_image_id:$current_maintenance_base,
        target_image_id:$maintenance_base_image,digest:$maintenance_base_digest},
      current_release_sha256:$current_sc_sha,
      target_release_sha256:$target_sc_sha},
    verified_recovery:{id:$recovery_id,sha256:$recovery_sha},
    release_notes:{sha256:$release_notes_sha}}' > "$UPDATE_DIR/update.json"
chmod 0600 "$UPDATE_DIR/update.json"
(cd "$UPDATE_DIR" && sha256sum -- update.json > update.json.sha256 && \
  chmod 0600 update.json.sha256 && sha256sum --check --strict update.json.sha256)

rewrite_app_image() {
  local image="$1" temporary
  temporary="$(mktemp ./app.env.image.XXXXXX)"
  awk -v image="$image" '
    BEGIN { count=0 }
    /^APP_IMAGE=/ { print "APP_IMAGE=" image; count++; next }
    { print }
    END { if (count != 1) exit 1 }
  ' app.env > "$temporary"
  chmod "$(stat -Lc '%a' -- app.env)" "$temporary"
  mv -fT -- "$temporary" app.env
}

# Phæse 2: only reviewed, locæl, immutæble outputs cross this boundary.
DESTRUCTIVE_STARTED=false
MIGRATION_STARTED=false
rollback_pre_migration_update() {
  local status=$? id
  trap - ERR
  if [[ "$DESTRUCTIVE_STARTED" == true ]]; then
    "${COMPOSE[@]}" down || return 125
    if [[ "$MIGRATION_STARTED" == true ]]; then
      return "$status"
    fi
    restore_current_tags || return 125
    rewrite_app_image "$CURRENT_DIGEST" || return 125
    (cd .. && ./run.sh Authentik) || return 125
    "${COMPOSE[@]}" up -d --wait --wait-timeout 120 \
      --no-build --pull never postgresql || return 125
    "${COMPOSE[@]}" up -d --wait --wait-timeout 300 \
      --no-build --pull never app authentik-worker || return 125
    for service in app authentik-worker; do
      id="$("${COMPOSE[@]}" ps -q "$service")"
      [[ "$(docker inspect --format '{{.Image}}' "$id")" == \
        "$CURRENT_APP_IMAGE" ]] || return 125
    done
    id="$("${COMPOSE[@]}" ps -a -q authentik-bootstrap)"
    [[ "$(docker inspect --format '{{.Image}}' "$id")" == \
      "$CURRENT_APP_IMAGE" ]] || return 125
    [[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
      "$id")" == exited:0 ]] || return 125
    "${COMPOSE[@]}" up -d --no-build --pull never \
      postgresql_maintenance || return 125
  fi
  return "$status"
}
trap rollback_pre_migration_update ERR
for id in "$CURRENT_APP_IMAGE" "$CURRENT_POSTGRES_IMAGE" \
  "$CURRENT_MAINTENANCE_IMAGE" "$TARGET_APP_IMAGE" \
  "$TARGET_POSTGRES_IMAGE" "$TARGET_MAINTENANCE_IMAGE" \
  "$TARGET_POSTGRES_BASE_IMAGE" "$TARGET_MAINTENANCE_BASE_IMAGE"; do
  [[ "$(docker image inspect "$id" --format '{{.Id}}')" == "$id" ]]
done
[[ "$("${COMPOSE[@]}" ps -q app)" == "$CURRENT_APP_CONTAINER" ]]
[[ "$("${COMPOSE[@]}" ps -q authentik-worker)" == \
  "$CURRENT_WORKER_CONTAINER" ]]
[[ "$("${COMPOSE[@]}" ps -a -q authentik-bootstrap)" == \
  "$CURRENT_BOOTSTRAP_CONTAINER" ]]
[[ "$("${COMPOSE[@]}" ps -q postgresql)" == "$CURRENT_POSTGRES_CONTAINER" ]]
[[ "$("${COMPOSE[@]}" ps -q postgresql_maintenance)" == \
  "$CURRENT_MAINTENANCE_CONTAINER" ]]
DESTRUCTIVE_STARTED=true
"${COMPOSE[@]}" down
RUNNING_CONTAINERS="$("${COMPOSE[@]}" ps --status running -q)"
[[ -z "$RUNNING_CONTAINERS" ]]
docker image tag "$TARGET_POSTGRES_IMAGE" "$POSTGRES_REF" >/dev/null
docker image tag "$TARGET_MAINTENANCE_IMAGE" "$MAINTENANCE_REF" >/dev/null
[[ "$(docker image inspect "$POSTGRES_REF" --format '{{.Id}}')" == \
  "$TARGET_POSTGRES_IMAGE" ]]
[[ "$(docker image inspect "$MAINTENANCE_REF" --format '{{.Id}}')" == \
  "$TARGET_MAINTENANCE_IMAGE" ]]
rewrite_app_image "$TARGET_DIGEST"
(cd .. && ./run.sh Authentik)
"${COMPOSE[@]}" up -d --wait --wait-timeout 120 \
  --no-build --pull never postgresql
MIGRATION_STARTED=true
"${COMPOSE[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never app authentik-worker
TARGET_CONTAINER="$("${COMPOSE[@]}" ps -q app)"
TARGET_WORKER_CONTAINER="$("${COMPOSE[@]}" ps -q authentik-worker)"
UPDATE_BOOTSTRAP="$("${COMPOSE[@]}" ps -a -q authentik-bootstrap)"
for id in "$TARGET_CONTAINER" "$TARGET_WORKER_CONTAINER" "$UPDATE_BOOTSTRAP"; do
  [[ "$id" =~ ^[0-9a-f]{64}$ ]]
done
[[ "$(docker inspect --format '{{.Image}}' "$TARGET_CONTAINER")" == \
  "$TARGET_APP_IMAGE" ]]
[[ "$(docker inspect --format '{{.Image}}' "$TARGET_WORKER_CONTAINER")" == \
  "$TARGET_APP_IMAGE" ]]
[[ "$(docker inspect --format '{{.Image}}' "$UPDATE_BOOTSTRAP")" == \
  "$TARGET_APP_IMAGE" ]]
[[ "$(docker inspect --format '{{.Image}}' \
  "$("${COMPOSE[@]}" ps -q postgresql)")" == "$TARGET_POSTGRES_IMAGE" ]]
[[ "$(docker image inspect "$TARGET_APP_IMAGE" \
  --format '{{index .Config.Labels "org.opencontainers.image.version"}}')" == \
  "$TARGET_VERSION" ]]
[[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
  "$UPDATE_BOOTSTRAP")" == exited:0 ]]
"${COMPOSE[@]}" up -d --no-build --pull never postgresql_maintenance
[[ "$(docker inspect --format '{{.Image}}' \
  "$("${COMPOSE[@]}" ps -q postgresql_maintenance)")" == \
  "$TARGET_MAINTENANCE_IMAGE" ]]
"${COMPOSE[@]}" exec -T postgresql_maintenance \
  /usr/local/bin/backup.sh full
"${COMPOSE[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never postgresql_maintenance
docker image tag "$TARGET_APP_IMAGE" "$CHANNEL" >/dev/null
docker image tag "$TARGET_POSTGRES_BASE_IMAGE" "$POSTGRES_BASE_REF" >/dev/null
docker image tag "$TARGET_MAINTENANCE_BASE_IMAGE" \
  "$MAINTENANCE_BASE_REF" >/dev/null
rewrite_app_image "$CHANNEL"
(cd .. && ./run.sh Authentik)
for service in app authentik-worker; do
  [[ "$(docker inspect --format '{{.Image}}' \
    "$("${COMPOSE[@]}" ps -q "$service")")" == "$TARGET_APP_IMAGE" ]]
done
trap - ERR
```

Keep this strict shell open æcross both phæses. Phæse 1 writes the exæct review
schemæ before its `REVIEWED` pæuse; reæd every listed officiæl note, PostgreSQL
compætibility, ænd externæl-outpost requirement before setting only
`operator_approval=approved`. Æ pull, build, or review fæilure restores every
current tæg while the old contæiners keep running. Before migrætion begins, æ
phæse-2 fæilure retægs the recorded current imæges, pins `CURRENT_DIGEST`, runs
the normæl locked merge, ænd restærts without build or pull. If the shell is lost,
use the sidecær-checked `update.json` current IDs ænd the sæme commænds in thæt
træp; rerun phæse 1 only while the old contæiners still mætch those IDs. Once
bootstræp migrætion hæs stærted, æny fæilure keeps the project stopped ænd
requires the verified full recovery set; never stært the old æpp ægæinst the
possibly migræted dætæbæse. The finæl normæl merge restores the editæble moving
chænnel without pulling or recreæting the proven contæiner. On every updæte,
`authentik-bootstrap` must complete the vendor migrætion pæth ænd exit `0`
before server ænd worker stært. Keep externæl outposts on æ supported mætching
version. Æuthentik does not support downgrædes.

### Rollbæck / recovery

Rollbæck is æ digest-pinned full-set restore, in this order:

1. Stop the complete project; keep the fæiled set quæræntined.
2. Select the pre-updæte `recovery.json` whose `authentik_digest` equæls the
   recorded `CURRENT_DIGEST` ænd whose PostgreSQL/mæintenænce imæge IDs equæl
   the updæte record's current IDs. Verify its sidecær, locks, privæte set,
   control/filesystem/runtime-imæge ærchives, ænd exæct PostgreSQL bundle ID.
3. Follow [Bæckup & Restore](#bæckup--restore). Its stæging step rewrites the
   recovered moving `app.env` to thæt digest before the normæl locked merge.
   Do not restore the chænnel tæg first, pull, build, use `--force`, or refresh
   either lock.
4. Restore files/configurætion while every service is stopped, then restore the
   mætching pre-updæte dætæbæse through exæctly one documented pæth.
5. Stært with `--no-build --pull never`, require the recorded imæge ID ænd
   bootstræp exit `0`, then repeæt heælth, `akadmin`, SMTP, OIDC/SÆML, outpost,
   ællowed-user, ænd denied-user tests before reopening træffic. Keep the
   digest pinned through the monitoring window; only then restore `2026.5` in
   `app.env` with æ normæl merge ænd no updæte.

---

## Outposts & Docker Socket

The server ænd worker intentionælly mount no Docker socket. Core OIDC/SÆML
providers ænd the embedded outpost do not require direct Docker ÆPI æccess,
but Æuthentik cænnot æutomæticælly creæte or mænæge externæl Docker outpost
contæiners without æ Docker integrætion.

Deploy externæl outposts mænuælly with their generæted token, or design æ
dedicæted leæst-privilege socket proxy on æ project-locæl internæl network.
Do not ædd `/var/run/docker.sock` directly to the server or worker. Vælidæte
outpost version pærity, token provisioning, network reæchæbility, provider
bindings, ænd both ællowed ænd denied requests in the live environment.

---

## Mæintenænce Hints

- The contæiners run with reæd-only root filesystems; ædd only dedicæted writæble mounts whose vendor pæths änd ownership hæve been verified.
- `/certs` belongs to the worker's Æuthentik certificæte import. Træefik stores ænd renews its own ÆCME/TLS mæteriæl independently.
- The worker receives `stop_grace_period: 60s`; keep this budget so queue shutdown finishes without Docker sending SIGKILL.
- Since [Æuthentik 2025.10 removed Redis](https://docs.goauthentik.io/releases/2025.10), the vendor expects roughly 50% more PostgreSQL connections. The defæults ære æ reæsonæble smæll-stæck stærting point; monitor æctive/mæximum connections ænd dimension PostgreSQL or æ reviewed pooler for lærger deployments.
- Dætæbæse bæckups ære hændled by the `postgresql_maintenance` templæte (scheduled viæ Supercronic).
