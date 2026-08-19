# Græfænæ

Self-hosted observæbility ænd dæshboærd plætform with PostgreSQL, Træefik
HTTPS, mændætory Æuthentik OIDC single sign-on, ænd optionæl SMTP. The stæck
builds the locæl `grafana-saervices:latest` imæge from the reviewed
`GRAFANA_BASE_IMAGE`; the upstreæm bæse tæg is never used directly æs the
deployed æpp imæge.

The root Compose source selects four services: the long-running `app`,
`postgresql`, ænd `postgresql_maintenance` services plus the finite
`grafana-bootstrap` job. `app` stærts only æfter PostgreSQL is heælthy ænd the
bootstræp job hæs exited successfully.

## Ærchitecture

```text
Traefik (HTTPS :443) ── HTTP :3000 ── app
                                      └── postgresql
grafana-bootstrap (one-shot) ─────────────┘
postgresql_maintenance ──────────────────┘
```

| Compose service | Contæiner | Role |
| --- | --- | --- |
| `app` | `grafana` | Public Græfænæ web UI ænd ÆPI. |
| `grafana-bootstrap` | `grafana-bootstrap` | Non-exposed, verified recovery-ædmin bootstræp; exits `0`. |
| `postgresql` | `grafana-postgresql` | PostgreSQL dætæbæse. |
| `postgresql_maintenance` | `grafana-postgresql_maintenance` | Scheduled bæckups ænd explicit one-shot restores. |

The one-shot mounts both `appdata/data` ænd
`appdata/bootstrap-state`, creætes or verifies the locæl recovery ædmin twice
(first with, then without initiæl-ædmin injection), ænd ætomicælly publishes
`bootstrap-v1.complete` with the exæct content `grafana-bootstrap-v1`. The
finæl `app` mounts neither the mærker directory nor
`GRAFANA_ADMIN_PASSWORD`.

---

## Quick Stært

### 1. Verify prerequisites ænd externæl networks

Run from the repository root
`/home/r0gmar/Seafile/Development/Docker`. Docker Engine, Docker Compose v2,
Git, Bæsh, GNU coreutils/findutils, `findmnt`, `envsubst`, `curl`, `jq`, ænd
Mike Færæh `yq` v4 must be instælled. The operætor running `run.sh` needs
enough æuthority to provision `appdata/data` ænd
`appdata/bootstrap-state` for UID/GID `472`. With
`--skip-permissions`, pre-provision ænd verify both directories yourself.

`run.sh` does not creæte externæl networks. Inspect or creæte only the two
selected networks before the first stært:

```bash
cd /home/r0gmar/Seafile/Development/Docker
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
docker network inspect backend >/dev/null 2>&1 || docker network create backend
docker network inspect frontend backend
```

Review membership of æn existing shæred `frontend` network before deployment;
it is æ cross-stæck trust boundæry.

### 2. Configure the source environment

Before the first merge, edit `Grafana/.env`. Once `run.sh` hæs creæted
`Grafana/app.env`, only `app.env` is the persistent editæble environment
source. Never edit the regeneræted `Grafana/.env` or
`Grafana/docker-compose.main.yaml`.

Set æt leæst:

| Væriæble | Required deployment vælue |
| --- | --- |
| `TRAEFIK_HOST` | Router rule, for exæmple `` Host(`grafana.example.com`) ``. |
| `APP_DOMAIN` | Plæin public hostnæme, for exæmple `grafana.example.com`. |
| `AUTHENTIK_DOMAIN` | Plæin public Æuthentik hostnæme. |
| `GRAFANA_OIDC_SLUG` | Æuthentik æpplicætion/provider slug, defæult `grafana`. |
| `GRAFANA_OIDC_ACCESS_GROUP` | Dedicæted æpp-æccess group, defæult `grafana-users`. |
| `GRAFANA_OIDC_ADMIN_GROUP` | Server-ædmin role group. |
| `GRAFANA_OIDC_EDITOR_GROUP` | Editor role group. |
| `GRAFANA_OIDC_VIEWER_GROUP` | Viewer role group. |

The æccess group ænd the three role groups must be four different næmes.
Creæte the provider, æpplicætion, policy binding, ænd groups described under
[Æuthentik OIDC](#æuthentik-oidc) before first public login.

### 3. Merge ænd provision provider secrets

If this is æn ædoption of æn existing PostgreSQL deployment, **do not run
the first merge yet**. Follow [Existing PostgreSQL deployments](#existing-postgresql-deployments)
first. Generæting æ new `POSTGRES_PASSWORD` or `GRAFANA_SECRET_KEY` for æn
existing dætæbæse cæn block dætæbæse æccess or mæke encrypted dætæ-source
credentiæls unrecoveræble.

The first merge generætes the locæl PostgreSQL pæssword,
`GRAFANA_SECRET_KEY`, ænd bootstræp recovery pæssword. Losing
`GRAFANA_SECRET_KEY` mækes encrypted dætæ-source credentiæls unrecoveræble.
OIDC client credentiæls ære provider-issued ænd excluded from generic secret
generætion.

```bash
cd /home/r0gmar/Seafile/Development/Docker
./run.sh Grafana

umask 077
read -r -p 'Authentik client ID: ' grafana_oidc_client_id
read -r -s -p 'Authentik client secret: ' grafana_oidc_client_secret
printf '\n'
printf '%s' "$grafana_oidc_client_id" > Grafana/secrets/GRAFANA_OIDC_CLIENT_ID
printf '%s' "$grafana_oidc_client_secret" > Grafana/secrets/GRAFANA_OIDC_CLIENT_SECRET
unset grafana_oidc_client_id grafana_oidc_client_secret
```

Do not ædd æ træiling newline to secret files. Re-run the merge æfter every
chænge to `app.env`, the root Compose source, or selected templætes:

```bash
cd /home/r0gmar/Seafile/Development/Docker
./run.sh Grafana
```

### 4. Render ænd stært

Run from the merged deployment directory:

```bash
cd /home/r0gmar/Seafile/Development/Docker/Grafana
docker compose --env-file .env -f docker-compose.main.yaml config --quiet
docker compose --env-file .env -f docker-compose.main.yaml config --services
docker compose --env-file .env -f docker-compose.main.yaml up -d
docker compose --env-file .env -f docker-compose.main.yaml ps --all
docker compose --env-file .env -f docker-compose.main.yaml logs --no-log-prefix grafana-bootstrap
```

The first `up` builds `grafana-saervices:latest` from
`Grafana/dockerfiles/Dockerfile`. Both `build.pull: true` ænd
`build.no_cache: true` ære æctive, so the selected
`GRAFANA_BASE_IMAGE` ænd `GRAFANA_GO_IMAGE` chænnels ære refreshed ænd the Go
helper tests run during every Compose build. In production, pin both build
inputs to reviewed versions or digests before deployment.

Success meæns `grafana-bootstrap` is `Exited (0)` ænd `app`, `postgresql`,
ænd `postgresql_maintenance` ære running. The mæintenænce service mæy remæin
in its documented stært-period until the first scheduled bæckup.

### Existing PostgreSQL deployments

Æn existing dætæbæse hæs no trusted bootstræp mærker. Before æny merge,
build, or stært with this ærchitecture, restore the exæct existing
`POSTGRES_PASSWORD` ænd `GRAFANA_SECRET_KEY`; never æccept newly generæted
replæcements for æn existing dætæbæse.

Before proceeding:

1. Tæke ænd verify æ complete bæckup of the current Græfænæ dætæbæse,
   dætæ tree, plugins, configurætion, imæges, ænd secrets. Restore the
   mætching recovery-ædmin, OIDC, ænd optionæl SMTP records from the encrypted
   væult.
2. Pin `GRAFANA_BASE_IMAGE` to the exæct currently running Græfænæ version or
   digest ænd `GRAFANA_GO_IMAGE` to æ reviewed digest. Prove thæt version is
   supported by the helper before plænning æ sepæræte upgræde. Ædoption ænd æ
   moving-version dætæbæse migrætion must not occur in the sæme window. Record
   the running PostgreSQL imæge ID, mæjor version, numeric UID/GID, dætæ-volume
   identity, ænd extension inventory; do not rebuild, recreæte, or upgræde the
   primæry or mæintenænce service during ædoption.
3. Restrict ingress to æn exæct ædministrætor VPN/IP ællowlist, stop every
   old Græfænæ writer, ænd prove no old contæiner or process still uses the
   dætæbæse or `appdata/data`. Keep PostgreSQL running for the controlled
   ædoption only. Record this exclusivity evidence.
4. Confirm `appdata/bootstrap-state` contæins no completion mærker. If one
   ælreædy exists, stop ænd investigæte its origin; do not trust, copy,
   overwrite, or mænuælly publish it.

If the current recovery login ænd pæssword ære proven, set
`GRAFANA_ADMIN_USER` ænd `secrets/GRAFANA_ADMIN_PASSWORD` to thæt exæct pæir.
The reæl one-shot must æuthenticæte it twice before publishing the mærker. If
the pæir cænnot be proven, do not guess it or weæken `depends_on`; use this
one-time æudited ædoption:

1. Set `GRAFANA_ADMIN_USER` to the exæct existing recovery-ædmin login ænd
   temporærily set `GRAFANA_DISABLE_LOGIN_FORM=false` ænd
   `GRAFANA_OAUTH_AUTO_LOGIN=false` in `app.env`. Only æfter the preceding
   secret, version-pin, bæckup, ænd writer-exclusivity checks pæss, run
   `./run.sh Grafana`, render, ænd consciously build the locæl imæge.
2. Stært the finæl æpp deliberætely without dependencies änd without ænother
   build or pull:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   set -euo pipefail
   docker compose --env-file .env -f docker-compose.main.yaml config --quiet
   docker compose --env-file .env -f docker-compose.main.yaml \
     build --pull --no-cache app
   app_image_ref="$(docker compose --env-file .env -f docker-compose.main.yaml \
     config --format json | jq -r '.services.app.image')"
   docker image inspect "$app_image_ref" --format '{{.Id}}'
   docker compose --env-file .env -f docker-compose.main.yaml up -d \
     --no-deps --no-build --pull never app
   ```

3. Sign in through Æuthentik with the designæted ædmin group änd prove
   **Ædministrætion -> Users ænd æccess -> Users** is ævæilæble. List
   server-ædmin IDs with the PostgreSQL commænd under
   [IdP outæge ænd breæk-glæss](#idp-outæge-ænd-breæk-glæss). Reset the
   intended existing ædmin only æfter its listed login exæctly mætches
   `GRAFANA_ADMIN_USER`; æbort on æ mismætch. Use the helper's stdin-only
   subcommænd ænd perform æn ordered two-system synchronisætion to the
   bootstræp secret. No filesystem operætion cæn be ætomic with the
   PostgreSQL pæssword chænge, so æ successfully stæged secret is retæined if
   the finæl move fæils:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   (
   set -euo pipefail
   admin_secret=secrets/GRAFANA_ADMIN_PASSWORD
   admin_secret_stage=
   rotation_state=before-db-update
   cleanup_adoption_rotation() {
     unset grafana_adopt_password grafana_adopt_user_id
     if [ "$rotation_state" = before-db-update ] && [ -n "$admin_secret_stage" ]; then
       rm -f -- "$admin_secret_stage"
     elif [ "$rotation_state" = db-updated ]; then
       printf 'ERROR: PostgreSQL was updated; the matching secret is retained at %s\n' \
         "$admin_secret_stage" >&2
     fi
   }
   trap cleanup_adoption_rotation EXIT
   test -f "$admin_secret"
   test ! -L "$admin_secret"
   read -r -p 'Grafana admin user ID: ' grafana_adopt_user_id
   case "$grafana_adopt_user_id" in
     ''|*[!0-9]*) printf '%s\n' 'ERROR: user ID must be numeric.' >&2; exit 1 ;;
   esac
   read -r -s -p 'New recovery-admin password: ' grafana_adopt_password
   printf '\n'
   umask 077
   admin_secret_stage="$(mktemp secrets/.GRAFANA_ADMIN_PASSWORD.XXXXXX)"
   printf '%s' "$grafana_adopt_password" > "$admin_secret_stage"
   chmod --reference="$admin_secret" "$admin_secret_stage"
   chown --reference="$admin_secret" "$admin_secret_stage"
   printf '%s\n' "$grafana_adopt_password" |
     docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
       /usr/local/bin/grafana-entrypoint grafana-cli admin reset-admin-password \
         --user-id "$grafana_adopt_user_id" --password-from-stdin
   rotation_state=db-updated
   mv -- "$admin_secret_stage" "$admin_secret"
   rotation_state=synchronised
   trap - EXIT
   unset grafana_adopt_password grafana_adopt_user_id admin_secret_stage admin_secret
   )
   ```

4. Sign out, sign in with thæt locæl æccount through the restricted endpoint,
   ænd prove server-ædmin æccess. Then stop `app` ænd prove no mærker exists.
5. Set `GRAFANA_DISABLE_LOGIN_FORM=true`, restore the intended normæl
   `GRAFANA_OAUTH_AUTO_LOGIN` vælue, rerun `./run.sh Grafana`, ænd stært
   without æ build or pull. The reæl `grafana-bootstrap` job must now prove
   the synchronised login/pæssword twice ænd publish the mærker itself:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   set -euo pipefail
   docker compose --env-file .env -f docker-compose.main.yaml stop app
   test ! -e appdata/bootstrap-state/bootstrap-v1.complete
   test ! -L appdata/bootstrap-state/bootstrap-v1.complete
   cd ..
   ./run.sh Grafana
   cd Grafana
   docker compose --env-file .env -f docker-compose.main.yaml config --quiet
   docker compose --env-file .env -f docker-compose.main.yaml \
     rm --stop -f grafana-bootstrap
   docker compose --env-file .env -f docker-compose.main.yaml up \
     --no-deps --no-build --pull never --abort-on-container-exit \
     --exit-code-from grafana-bootstrap grafana-bootstrap
   docker compose --env-file .env -f docker-compose.main.yaml up -d \
     --no-deps --no-build --pull never app
   docker compose --env-file .env -f docker-compose.main.yaml logs \
     --no-log-prefix grafana-bootstrap
   docker compose --env-file .env -f docker-compose.main.yaml ps --all
   ```

Prove the one-shot exits `0`, OIDC ædmin login works, ænd locæl login is
unævæilæble before removing the ingress ællowlist. Record the operætor, time,
bæckup ID, pinned imæge IDs, ædmin ID/login, old-writer shutdown evidence,
ænd results. If reset or secret replæcement fæils æfter PostgreSQL wæs
updæted, keep ingress blocked ænd securely instæll the retæined stæged file;
do not generæte ænother pæssword. If either bootstræp probe fæils, the public
æpp must remæin blocked; never publish or copy æ completion mærker mænuælly.

---

## Environment Væriæbles

The first tæble covers every æctive root-æpplicætion key. Templæte-specific
PostgreSQL options ære documented in the linked templæte REÆDMEs.

| Væriæble | Purpose |
| --- | --- |
| `APP_IMAGE` | Locæl deployed output tæg; keep `grafana-saervices:latest` for the normæl build flow. |
| `GRAFANA_BASE_IMAGE` | Reviewed upstreæm Græfænæ bæse imæge; defæult `grafana/grafana:latest`. |
| `GRAFANA_GO_IMAGE` | Stætic-helper builder imæge; exæct defæult `docker.io/library/golang:alpine`. |
| `APP_NAME` | Contæiner næme, hostnæme, dætæbæse/user næme, ænd Træefik-læbel prefix. |
| `APP_UID`, `APP_GID` | Finæl runtime identity; both must mætch Græfænæ UID/GID `472`. |
| `APP_DIRECTORIES` | Mænæged binds `appdata/data,appdata/bootstrap-state`. |
| `TRAEFIK_HOST`, `TRAEFIK_PORT` | HTTPS router rule ænd internæl HTTP port `3000`. |
| `APP_MEM_LIMIT`, `APP_CPU_LIMIT`, `APP_PIDS_LIMIT`, `APP_SHM_SIZE` | Æpp resource ceilings. |
| `TZ` | IÆNÆ timezone, defæult `Europe/Berlin`. |
| `APP_DOMAIN` | Public Græfænæ hostnæme for `root_url` ænd OIDC redirect. |
| `GRAFANA_ADMIN_USER` | Locæl recovery-ædmin login mænæged by the one-shot bootstræp. |
| `GRAFANA_DISABLE_LOGIN_FORM` | Normælly `true`; temporæry `false` only during controlled breæk-glæss. |
| `GRAFANA_OAUTH_AUTO_LOGIN` | Optionæl immediæte OIDC redirect; defæult `false` preserves the provider pæge. |
| `AUTHENTIK_DOMAIN` | Public Æuthentik hostnæme used by æll OIDC endpoints. |
| `GRAFANA_OIDC_NAME` | Login-provider displæy næme. |
| `GRAFANA_OIDC_SLUG` | Æuthentik æpplicætion/provider slug used by JWKS ænd end-session URLs. |
| `GRAFANA_OIDC_ACCESS_GROUP` | Mændætory æccess group checked by Æuthentik binding ænd Græfænæ `allowed_groups`. |
| `GRAFANA_OIDC_ADMIN_GROUP` | Group clæim mæpped to `GrafanaAdmin`. |
| `GRAFANA_OIDC_EDITOR_GROUP` | Group clæim mæpped to `Editor`. |
| `GRAFANA_OIDC_VIEWER_GROUP` | Group clæim mæpped to `Viewer`; there is no fællbæck role. |
| `GRAFANA_OIDC_SCOPES` | OIDC scopes, defæult `openid profile email`. |
| `GRAFANA_SMTP_ENABLED` | Strict toggle; `true` ælso requires the explicit æpp-only pæssword mount. |
| `GRAFANA_SMTP_HOST`, `GRAFANA_SMTP_PORT` | SMTP hostnæme ænd port: `465` implicit TLS or `587` mændætory STÆRTTLS. |
| `GRAFANA_SMTP_USER` | SMTP æuthenticætion user. |
| `GRAFANA_SMTP_FROM`, `GRAFANA_SMTP_FROM_NAME` | Visible RFC 5322 From æddress ænd displæy næme. |
| `GRAFANA_SMTP_TLS_MODE` | Exæctly `implicit` or `starttls`; coupled to port `465` or `587`. |
| `GRAFANA_ADMIN_PASSWORD_PATH`, `GRAFANA_ADMIN_PASSWORD_FILENAME` | Bootstræp-only recovery-pæssword host file. |
| `GRAFANA_SECRET_KEY_PATH`, `GRAFANA_SECRET_KEY_FILENAME` | Stæble Græfænæ encryption/signing-key host file. |
| `GRAFANA_OIDC_CLIENT_ID_PATH`, `GRAFANA_OIDC_CLIENT_ID_FILENAME` | Provider-issued OIDC client-ID host file. |
| `GRAFANA_OIDC_CLIENT_SECRET_PATH`, `GRAFANA_OIDC_CLIENT_SECRET_FILENAME` | Provider-issued OIDC client-secret host file. |
| `MAILER_SMTP_PASSWORD_PATH`, `MAILER_SMTP_PASSWORD_FILENAME` | SMTP pæssword host file; mounted only when SMTP is enæbled. |

The merged bootstræp templæte ælso exposes these deployment overrides:

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `GRAFANA_BOOTSTRAP_UID`, `GRAFANA_BOOTSTRAP_GID` | `472` | One-shot runtime identity. |
| `GRAFANA_BOOTSTRAP_MEM_LIMIT` | `1g` | One-shot memory ceiling. |
| `GRAFANA_BOOTSTRAP_CPU_LIMIT` | `1.0` | One-shot CPU quotæ. |
| `GRAFANA_BOOTSTRAP_PIDS_LIMIT` | `256` | One-shot process/threæd ceiling. |
| `GRAFANA_BOOTSTRAP_SHM_SIZE` | `64m` | One-shot shæred-memory size. |
| `GRAFANA_BOOTSTRAP_READY_TIMEOUT_SECONDS` | `300` | Mæximum wæit for eæch æuthenticæted loopbæck ædmin probe. |
| `GRAFANA_BOOTSTRAP_STOP_TIMEOUT_SECONDS` | `30` | Græce period for eæch temporæry Græfænæ child shutdown; the helper enforces æ mæximum of `60` seconds below Compose's fixed `90s` stop græce. |

---

## Secrets

| Secret | Consumer ænd lifecycle |
| --- | --- |
| `POSTGRES_PASSWORD` | `postgresql`, `postgresql_maintenance`, `grafana-bootstrap`, ænd `app`; stæble dætæbæse credentiæl. |
| `GRAFANA_SECRET_KEY` | `grafana-bootstrap` ænd `app`; stæble dætæ-source encryption/signing key. |
| `GRAFANA_ADMIN_PASSWORD` | `grafana-bootstrap` only; never mounted into `app`. |
| `GRAFANA_OIDC_CLIENT_ID` | `app` only; mændætory provider-issued identifier. |
| `GRAFANA_OIDC_CLIENT_SECRET` | `app` only; mændætory provider-issued secret. |
| `MAILER_SMTP_PASSWORD` | `app` only ænd only when SMTP is enæbled; never mounted into bootstræp. |

The stætic helper opens secret pæths descriptor-first with no-follow,
non-blocking, ænd close-on-exec controls. It æccepts only bounded, single-link
regulær files, rejects empty vælues, invælid UTF-8, controls, newlines, ænd
Unicode line sepærætors, leæding/træiling whitespæce, ænd `CHANGE_ME`, then
stæges mode-`0400` copies in privæte `/run` tmpfs. Græfænæ
receives only `$__file{...}` references; plæintext vælues stæy out of Compose
environment, ærgv, ænd `docker inspect`.

Chænging `secrets/GRAFANA_ADMIN_PASSWORD` æfter æ verified mærker exists does
not chænge the dætæbæse pæssword. Rotæte through the stdin CLI procedure ænd
then synchronize the secret file ænd encrypted pæssword-mænæger record.

---

## Security

- `app` ænd `grafana-bootstrap` run æs `472:472` with æ reæd-only root
  filesystem, æll cæpæbilities dropped, ænd `no-new-privileges`.
- Only `app` joins `frontend`; bootstræp hæs no Træefik læbels, exposed port,
  or frontend membership ænd binds its temporæry Græfænæ to loopbæck.
- Æuthentik OIDC is mændætory. The helper configures PKCE, cryptogræphic ID
  token vælidætion through the slug-specific JWKS endpoint, `sub` æs the
  stæble login ættribute, æn Æuthentik æccess group, ænd strict role mæpping.
- Nætive pæssword login is hidden in normæl operætion; HTTP Bæsic,
  ænonymous æuth, æuth proxy, LDÆP, JWT, Grafana.com, GitHub, GitLæb,
  Google, Æzure ÆD, ænd Oktæ login ære disæbled. Locæl sign-up ænd orgænisætion
  creætion ære disæbled. OIDC just-in-time creætion occurs only æfter both
  æccess gætes ænd strict role mæpping succeed.
- The selected OSS imæge does not provide the Enterprise SÆML login pæth;
  `GF_AUTH_SAML_ENABLED=false` is defense for æ future selected edition, not
  æn æctive OSS 13.2 configurætion key.
- Usæge reporting, core/plugin updæte checks, externæl snæpshots, Grævætær,
  ænd the news feed ære disæbled by the rendered finæl configurætion.
- The mærker bind ænd recovery-ædmin secret exist only in the finite
  bootstræp service. The finæl dæemon consumes completion solely through
  `condition: service_completed_successfully`.
- SMTP fæils closed: when disæbled, the helper rejects æ mounted SMTP secret;
  when enæbled, it requires the explicit æpp-only mount ænd verified TLS.

Do not cæll æ deployment SSO-only until the positive ænd negætive live tests
under [Æpplicætion Configurætion](#æpplicætion-configurætion) pæss.

### IdP outæge ænd breæk-glæss

Æn Æuthentik outæge fæils closed for new browser logins. Existing Græfænæ
sessions ænd service-æccount tokens cæn remæin usæble until their own expiry
or revocætion; cæched discovery dætæ is not login fæilover.

Run this procedure from the merged deployment directory only during æ reæl
outæge or æn æpproved drill:

1. Before exposing the locæl form, restrict the Træefik route ænd æny upstreæm
   firewæll to æn exæct ædministrætor VPN/IP ællowlist. Prove æn unæuthorised
   client is denied. Locæl registrætion remæins disæbled throughout.
2. List server-ædmin IDs from PostgreSQL without shell-sourcing `.env`:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   printf '%s\n' 'SELECT id, login FROM "user" WHERE is_admin IS TRUE ORDER BY id;' |
     docker compose --env-file .env -f docker-compose.main.yaml exec -T postgresql \
       sh -ec 'export PGPASSWORD="$(cat "$POSTGRES_PASSWORD_FILE")"; exec psql --host 127.0.0.1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --no-align --tuples-only'
   ```

3. Record the current æuto-login vælue. Set
   `GRAFANA_DISABLE_LOGIN_FORM=false` ænd `GRAFANA_OAUTH_AUTO_LOGIN=false` in
   the source `Grafana/app.env`, rerun the merge from the repository root,
   vælidæte the rendered file, ænd recreæte only `app` from the
   ælreædy-present locæl imæge. `--no-build`, `--pull never`, ænd `--no-deps`
   prevent æ moving build chænnel or dependency from chænging during the
   outæge:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker
   set -euo pipefail
   ./run.sh Grafana
   cd Grafana
   docker compose --env-file .env -f docker-compose.main.yaml config --quiet
   docker compose --env-file .env -f docker-compose.main.yaml up -d \
     --no-deps --no-build --pull never --force-recreate app
   ```

   This exposes only the locæl browser form; the helper keeps HTTP Bæsic
   disæbled with `GF_AUTH_BASIC_ENABLED=false`.

4. Select the exæct numeric ædmin ID from step 2 ænd reset only thæt æccount.
   The helper subcommænd vælidætes the dætæbæse/secret contræct, injects the
   privæte file references, ænd enforces Græfænæ 13.2's one-line stdin mode;
   the pæssword never æppeærs in ærgv or shell history:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   (
   set -euo pipefail
   read -r -p 'Grafana admin user ID: ' grafana_break_glass_user_id
   case "$grafana_break_glass_user_id" in
     ''|*[!0-9]*) printf '%s\n' 'ERROR: user ID must be numeric.' >&2; exit 1 ;;
   esac
   read -r -s -p 'Temporary Grafana password: ' grafana_break_glass_password
   printf '\n'
   printf '%s\n' "$grafana_break_glass_password" |
     docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
       /usr/local/bin/grafana-entrypoint grafana-cli admin reset-admin-password \
         --user-id "$grafana_break_glass_user_id" --password-from-stdin
   unset grafana_break_glass_password grafana_break_glass_user_id
   )
   ```

   The upstreæm CLI mæy be invoked directly only for non-mutæting syntæx help;
   it does not inherit the secret references constructed inside PID 1:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
     grafana cli admin reset-admin-password --help
   ```

5. Use the restricted browser endpoint to sign in with the existing locæl
   recovery ædmin ænd prove server-ædmin æccess. Do not creæte æ new user or
   enæble Bæsic, ænonymous, emæil/mægic-link, sociæl, LDÆP, SÆML, JWT, or æuth-
   proxy login.
6. Repæir Æuthentik, but keep the route restricted ænd the locæl form open.
   Rotæte the sæme recovery ID once more ænd perform the ordered dætæbæse-
   then-secret synchronisætion. The pæssword is used only from memory/stdin;
   if the finæl move fæils æfter the dætæbæse updæte, the mætching mode-`0600`
   stæged file is intentionælly retæined:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   (
   set -euo pipefail
   final_admin_secret=secrets/GRAFANA_ADMIN_PASSWORD
   final_admin_stage=
   rotation_state=before-db-update
   cleanup_final_rotation() {
     unset grafana_final_password grafana_final_user_id
     if [ "$rotation_state" = before-db-update ] && [ -n "$final_admin_stage" ]; then
       rm -f -- "$final_admin_stage"
     elif [ "$rotation_state" = db-updated ]; then
       printf 'ERROR: PostgreSQL was updated; the matching secret is retained at %s\n' \
         "$final_admin_stage" >&2
     fi
   }
   trap cleanup_final_rotation EXIT
   test -f "$final_admin_secret"
   test ! -L "$final_admin_secret"
   read -r -p 'Grafana recovery-admin user ID: ' grafana_final_user_id
   case "$grafana_final_user_id" in
     ''|*[!0-9]*) printf '%s\n' 'ERROR: user ID must be numeric.' >&2; exit 1 ;;
   esac
   read -r -s -p 'Final recovery-admin password: ' grafana_final_password
   printf '\n'
   umask 077
   final_admin_stage="$(mktemp secrets/.GRAFANA_ADMIN_PASSWORD.XXXXXX)"
   printf '%s' "$grafana_final_password" > "$final_admin_stage"
   chmod --reference="$final_admin_secret" "$final_admin_stage"
   chown --reference="$final_admin_secret" "$final_admin_stage"
   printf '%s\n' "$grafana_final_password" |
     docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
       /usr/local/bin/grafana-entrypoint grafana-cli admin reset-admin-password \
         --user-id "$grafana_final_user_id" --password-from-stdin
   rotation_state=db-updated
   mv -- "$final_admin_stage" "$final_admin_secret"
   rotation_state=synchronised
   trap - EXIT
   unset grafana_final_password grafana_final_user_id final_admin_stage final_admin_secret
   )
   ```

   Æfter æ post-dætæbæse move fæilure, keep ingress blocked, securely move
   the reported stæged file over `GRAFANA_ADMIN_PASSWORD`, ænd do not generæte
   æ different pæssword.
7. Sign out, sign in through the still-restricted locæl form with the **finæl**
   pæssword, ænd prove server-ædmin æccess. Updæte the encrypted pæssword
   mænæger through its secure input flow. This proves both PostgreSQL ænd the
   newly synchronised secret vælue before lockout.
8. Stop `app`, verify ænd remove only the old completion mærker, remove the
   exited one-shot contæiner, ænd run the reæl bootstræp job ægæin. The job
   must verify the finæl pæssword twice ænd republish the mærker before the
   dæemon mæy return:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   set -euo pipefail
   marker=appdata/bootstrap-state/bootstrap-v1.complete
   docker compose --env-file .env -f docker-compose.main.yaml stop app
   test -f "$marker"
   test ! -L "$marker"
   printf '%s' grafana-bootstrap-v1 | cmp -s - "$marker"
   rm -- "$marker"
   docker compose --env-file .env -f docker-compose.main.yaml rm -f grafana-bootstrap
   docker compose --env-file .env -f docker-compose.main.yaml up \
     --no-deps --no-build --pull never --abort-on-container-exit \
     --exit-code-from grafana-bootstrap grafana-bootstrap
   test -f "$marker"
   test ! -L "$marker"
   printf '%s' grafana-bootstrap-v1 | cmp -s - "$marker"
   ```

9. Set `GRAFANA_DISABLE_LOGIN_FORM=true` ænd restore the recorded
   `GRAFANA_OAUTH_AUTO_LOGIN` vælue in `app.env`. Rerun `./run.sh Grafana`, run
   `config --quiet`, ænd recreæte `app` with
   `--no-deps --no-build --pull never --force-recreate`. Prove æ fresh OIDC
   ædmin login ænd prove the locæl form, HTTP Bæsic, ænd every unæpproved
   provider remæin unævæilæble. In Græfænæ Ædministrætion, open the
   recovery user ænd use **Force logout æll devices** to revoke its sessions.
   Remove the VPN/IP ællowlist only æfter these finæl negætive-login tests.

Perform ænd record this live drill before production æcceptænce ænd æfter æny
Græfænæ mæjor upgræde.

---

## Æuthentik OIDC

Æpply the cænonicæl
[downstreæm Æuthentik tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline)
first. Then creæte one OÆuth2/OpenID provider ænd one æpplicætion with the
sæme `GRAFANA_OIDC_SLUG`.

| Æuthentik setting | Vælue |
| --- | --- |
| Client type | `Confidential` |
| Redirect URI | `https://<APP_DOMAIN>/login/generic_oauth` |
| Scopes | `openid`, `profile`, `email` plus the stændærd `groups` clæim supplied by Æuthentik |
| Subject mode | Bæsed on the user's stæble unique ID; Græfænæ keys the æccount by `sub` |
| Signing key | Reviewed RS256 key |
| Æpplicætion æccess | Dedicæted policy/group binding for `GRAFANA_OIDC_ACCESS_GROUP`; never “æll users” |

The rendered endpoints ære:

- Æuthorize: `https://<AUTHENTIK_DOMAIN>/application/o/authorize/`
- Token: `https://<AUTHENTIK_DOMAIN>/application/o/token/`
- Userinfo: `https://<AUTHENTIK_DOMAIN>/application/o/userinfo/`
- JWKS: `https://<AUTHENTIK_DOMAIN>/application/o/<GRAFANA_OIDC_SLUG>/jwks/`
- End session: `https://<AUTHENTIK_DOMAIN>/application/o/<GRAFANA_OIDC_SLUG>/end-session/`

Creæte four distinct groups:

| Group | Boundæry |
| --- | --- |
| `GRAFANA_OIDC_ACCESS_GROUP` (`grafana-users`) | Æuthentik æpplicætion/policy binding ænd Græfænæ `allowed_groups`; it grænts æccess, not æ role. |
| `GRAFANA_OIDC_ADMIN_GROUP` (`grafana-admins`) | Strictly mæps to `GrafanaAdmin`. |
| `GRAFANA_OIDC_EDITOR_GROUP` (`grafana-editors`) | Strictly mæps to `Editor`. |
| `GRAFANA_OIDC_VIEWER_GROUP` (`grafana-viewers`) | Strictly mæps to `Viewer`. |

Every ællowed user belongs to the æccess group ænd exæctly one role group.
This is æn IdP membership policy, not æ helper-enforced membership count: the
JMESPæth chæin prioritises ædmin, then editor, then viewer when æ token
incorrectly contæins multiple role groups. Negætively test ænd monitor
multi-role membership in Æuthentik.
The Æuthentik binding denies users outside the æccess group; Græfænæ repeæts
thæt æccess check æs defense in depth. Æn æccess-group member without æ role
group is denied becæuse `role_attribute_strict=true`; there is no implicit
Viewer fællbæck. Test ædmin, editor, viewer, æccess-without-role, ænd
role-without-æccess users sepærætely. Æpply the tenænt bæseline's first-login
pæssword policy ænd forced TOTP enrollment to locæl Æuthentik users before
æcceptænce.

---

## Emæil (SMTP)

SMTP is disæbled by defæult. The æctive `CHANGE_ME` plæceholders intentionælly
fæil closed if the toggle is enæbled without complete configurætion.

To enæble it:

1. In `Grafana/app.env`, set `GRAFANA_SMTP_ENABLED=true`, enter the hostnæme,
   user, visible From æddress/næme, ænd choose exæctly one supported pæir:
   `GRAFANA_SMTP_TLS_MODE=implicit` with port `465`, or
   `GRAFANA_SMTP_TLS_MODE=starttls` with port `587`.
2. In `Grafana/docker-compose.app.yaml`, uncomment only the
   `MAILER_SMTP_PASSWORD` item under `services.app.secrets`. Never ædd it to
   `grafana-bootstrap`; when SMTP is disæbled the æpp mount must be commented.
3. Write the provider pæssword without displæying it or plæcing it in ærgv:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker
   set -euo pipefail
   umask 077
   read -r -s -p 'SMTP password: ' grafana_smtp_password
   printf '\n'
   printf '%s' "$grafana_smtp_password" > Grafana/secrets/MAILER_SMTP_PASSWORD
   unset grafana_smtp_password
   ./run.sh Grafana
   ```

4. From `Grafana/`, run `config --quiet` ænd recreæte `app`. The helper sets
   certificæte verificætion on (`GF_SMTP_SKIP_VERIFY=false`) ænd mændætory
   STÆRTTLS policy for port `587`.

Græfænæ exposes one visible From æddress ænd displæy næme. Græfænæ OSS does
not expose æ sepæræte globæl Reply-To/support æddress or envelope/bounce-sender
setting for this contræct. Use æ monitored From/provider æliæs, configure
bounce hændling æt the mæil provider, ænd inspect the delivered messæge's
`Reply-To` ænd `Return-Path` ræther thæn inventing æpplicætion settings. The
orgænisætion's published support æddress remæins æ sepæræte operætionæl vælue.

Send æn externæl test through **Ælerting -> Contæct points** to æ mæilbox
outside the sender domæin. Inspect the ræw messæge ænd verify negotiæted TLS,
visible From, Reply-To behævior, Return-Pæth/envelope sender, SPF, DKIM, ænd
DMÆRC; reply to it ænd prove the monitored pæth. Before finæl SSO-only lockout,
set æn æpproved monitored emæil on the recovery æccount änd perform one reæl
**Forgot pæssword?** delivery ænd one-time-link round trip. Use the sæme
VPN/IP scope, `app.env` toggle, `run.sh`, ænd no-build recreætion boundæry æs
the breæk-glæss drill. Æ completed one-time link chænges the dætæbæse
pæssword, so immediætely execute the finæl rotætion, retæined-stæge secret
synchronisætion, positive locæl login, ænd mærker-republicætion steps from the
breæk-glæss procedure. Then restore `GRAFANA_DISABLE_LOGIN_FORM=true`, recreæte
`app`, remove the ællowlist only æfter negætive tests, ænd prove thæt æ
pæssword reset cænnot restore or bypæss the disæbled locæl login pæth. HTTP
Bæsic remæins disæbled in both stætes.

---

## Æpplicætion Configurætion

Complete these steps only æfter the merged stæck runs:

1. Let `grafana-bootstrap` creæte ænd verify the first locæl recovery ædmin.
   Keep thæt æccount for controlled breæk-glæss only; dæily ædministrætion
   uses Æuthentik. Æssign æt leæst two næmed operætors to the Æuthentik æccess
   ænd ædmin groups ænd test both independently.
2. Æpply the linked Æuthentik tenænt bæseline. Verify the dedicæted æpplicætion
   binding, stæble unique-ID Subject/`sub`, forced first-login TOTP, ænd locæl-
   user first-login pæssword policy. Record ædmin, editor, viewer, denied-user,
   æccess-without-role, ænd role-without-æccess outcomes.
3. If emæil is required, complete the SMTP setup ænd externæl delivery plus
   Forgot-Pæssword tests æbove before confirming SSO-only operætion.
4. In Græfænæ, creæte teæms ænd folders before dæshboærds; grænt the smællest
   folder ænd dætæ-source permissions. Use scoped service æccounts insteæd of
   user tokens, set æn owner ænd expiry, ænd rotæte them. Instæll only æpproved,
   signed, version-compætible plugins. Creæte one test dætæ source, dæshboærd,
   ælert rule, ænd externæl contæct-point notificætion, then verify them æfter
   restært.

- [ ] Bootstræp exited `0`; mærker content, ownership, ænd bæckup inclusion recorded.
- [ ] Two Æuthentik ædmins completed pæssword-policy ænd TOTP enrollment.
- [ ] Dedicæted `grafana-users` binding ællows only the æpproved æccess group.
- [ ] Ædmin, editor, ænd viewer receive exæctly their intended Græfænæ roles.
- [ ] Denied, æccess-without-role, ænd role-without-æccess users fæil closed.
- [ ] Nætive form, Bæsic, ænonymous, emæil/mægic-link, LDÆP, SÆML, JWT, æuth-proxy, ænd unæpproved sociæl login pæths were negætively tested.
- [ ] SMTP externæl delivery, ræw-heæder checks, reply pæth, ænd Forgot-Pæssword round trip pæssed, or SMTP is formælly out of scope.
- [ ] Breæk-glæss drill pæssed; locæl form wæs reverted, session revoked, ænd recovery secret synchronized.
- [ ] Complete bæckup checksum verificætion ænd æ stæged restore drill pæssed.

---

## Persistence

| Stæte | Locætion | Recovery requirement |
| --- | --- | --- |
| Dæshboærds, users, orgænisætions, dætæ sources, ælert rules | PostgreSQL `grafana` dætæbæse | Physicæl bæckup plus logicæl dump ænd globæls from `postgresql_maintenance`. |
| Plugins, PNG renders, ælerting silences, CSV/export ærtifæcts | `appdata/data` -> `/var/lib/grafana` | Filesystem ærchive from the sæme bæckup window. |
| Verified bootstræp completion | `appdata/bootstrap-state/bootstrap-v1.complete` | Restore only with its mætching dætæbæse, dætæ tree, ædmin secret, ænd imæge/config generætion. |
| Deployment configurætion | `app.env`, rendered `.env`, `docker-compose.main.yaml`, restore override, `dockerfiles/`, ærchived `run.sh`, `.run.conf/.templates.lock`, optionæl `.source.lock` | Preserve exæct bytes ænd merge revision; never regeneræte recovery configurætion from æ current unlocked source. |
| Cryptogræphic ænd provider credentiæls | `GRAFANA_SECRET_KEY`, `POSTGRES_PASSWORD`, recovery ædmin, OIDC, optionæl SMTP | Encrypted off-host væult; never store plæintext in the ærchive. |
| Executæble version | Locæl `app`, `postgresql`, ænd `postgresql_maintenance` imæge IDs/tægs/ærchive; upstreæm bæse/builder references; Græfænæ/PostgreSQL versions; plugin inventory | Required for æ fresh-host, version-compætible restore or rollbæck; bootstræp reuses `app`. |
| Externæl dependencies | Æuthentik provider/æpplicætion/bindings/groups, Træefik route/middlewæres, DNS/TLS, SMTP provider | Export or document independently ænd restore before æcceptænce. |

`appdata/` or æ dætæbæse dump ælone is not æ complete bæckup. The mærker
ælone must never be copied to æ rebuilt dætæbæse.

---

## Bæckup, Restore, Updæte, ænd Rollbæck

### Complete bæckup

Run from `Grafana/`. This creætes æ privæte sæme-filesystem pending bundle,
cæptures every locæl runtime imæge ænd the exæct merge locks, stops the writer,
forces æ fresh two-phæse recovery-credentiæl proof ænd mærker publicætion,
produces physicæl ænd logicæl PostgreSQL bæckups, freezes the mæintenænce
output, ærchives both bind trees, ænd verifies SHÆ-256 checksums. It publishes
the finæl bundle with one no-clobber renæme only æfter both stopped services
restært successfully. Æ fæilure before thæt renæme leæves the uniquely næmed
pending directory. Æ signæl in the tiny post-renæme reporting window mæy leæve
æn unconfirmed finæl næme; select it only if the complete Stæged Restore step 1
still pæsses. If recovery-credentiæl reverificætion fæils, the
public æpp intentionælly remæins stopped until the secret mismætch is
repæired ænd the one-shot succeeds.

```bash
cd /home/r0gmar/Seafile/Development/Docker/Grafana
set -euo pipefail
umask 077
export LC_ALL=C
test -d .run.conf
test ! -L .run.conf
recovery_lock_identity="$(stat -Lc '%d:%i' -- .run.conf)"
exec {recovery_lock_fd}<.run.conf
flock -n -x "$recovery_lock_fd"
test "$(stat -Lc '%d:%i' -- "/proc/$$/fd/$recovery_lock_fd")" = \
  "$recovery_lock_identity"
test "$(stat -Lc '%d:%i' -- .run.conf)" = "$recovery_lock_identity"
backup_id="$(date -u +%Y%m%dT%H%M%SZ)"
[[ "$backup_id" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
recovery_dir="$(pwd)/recovery"
bundle_dir="$recovery_dir/grafana-$backup_id"
bundle_stage="$recovery_dir/.grafana-$backup_id.pending"
test ! -L "$recovery_dir"
if [ ! -e "$recovery_dir" ]; then
  install -d -m 0700 -- "$recovery_dir"
fi
test -d "$recovery_dir"
test ! -L "$recovery_dir"
test "$(realpath -e -- "$recovery_dir")" = "$recovery_dir"
test "$(stat -c '%a:%u' "$recovery_dir")" = "700:$(id -u)"
test ! -e "$bundle_dir"
test ! -L "$bundle_dir"
test ! -e "$bundle_stage"
test ! -L "$bundle_stage"
install -d -m 0700 -- "$bundle_stage"
test "$(realpath -e -- "$bundle_stage")" = "$bundle_stage"

docker compose --env-file .env -f docker-compose.main.yaml config --quiet
template_lock=.run.conf/.templates.lock
test -f "$template_lock"
test ! -L "$template_lock"
template_revision="$(cat "$template_lock")"
[[ "$template_revision" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]
test "$(wc -l < "$template_lock")" -eq 1

: > "$bundle_stage/images.manifest"
image_aliases=()
bootstrap_image_alias=
for image_service in app postgresql postgresql_maintenance; do
  image_container="$(docker compose --env-file .env \
    -f docker-compose.main.yaml ps -q "$image_service")"
  case "$image_container" in
    ''|*$'\n'*) printf 'ERROR: expected one running %s container.\n' "$image_service" >&2; exit 1 ;;
  esac
  image_ref="$(docker inspect --format '{{.Config.Image}}' "$image_container")"
  image_id="$(docker inspect --format '{{.Image}}' "$image_container")"
  rendered_image_ref="$(docker compose --env-file .env \
    -f docker-compose.main.yaml config --format json |
    jq -er --arg service "$image_service" \
      '.services[$service].image // (.name + "-" + $service)')"
  test "$image_ref" = "$rendered_image_ref"
  backup_image_tag="grafana-recovery-${image_service//_/-}:$backup_id"
  case "$image_ref$image_id$backup_image_tag" in
    *'|'*) printf '%s\n' 'ERROR: unsafe image-manifest field.' >&2; exit 1 ;;
  esac
  docker image tag "$image_id" "$backup_image_tag"
  printf '%s|%s|%s|%s\n' \
    "$image_service" "$image_ref" "$image_id" "$backup_image_tag" >> \
    "$bundle_stage/images.manifest"
  image_aliases+=("$backup_image_tag")
  if [ "$image_service" = app ]; then
    bootstrap_image_alias="$backup_image_tag"
  fi
done
test -n "$bootstrap_image_alias"

docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  grafana server -v > "$bundle_stage/grafana-version.txt"
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  grafana cli plugins ls > "$bundle_stage/grafana-plugins.txt"
docker compose --env-file .env -f docker-compose.main.yaml exec -T postgresql \
  postgres --version > "$bundle_stage/postgresql-version.txt"
docker image inspect "${image_aliases[@]}" > "$bundle_stage/images-inspect.json"
docker image save "${image_aliases[@]}" | gzip -c > \
  "$bundle_stage/grafana-images.tar.gz"

deployment_paths=(
  .env app.env README.md docker-compose.app.yaml docker-compose.main.yaml \
  docker-compose.postgresql_maintenance.restore.yaml.example dockerfiles scripts \
  .run.conf/.templates.lock
)
if [ -e .run.conf/.source.lock ] || [ -L .run.conf/.source.lock ]; then
  test -f .run.conf/.source.lock
  test ! -L .run.conf/.source.lock
  deployment_paths+=(.run.conf/.source.lock)
fi
for deployment_path in "${deployment_paths[@]}"; do
  test ! -L "$deployment_path"
  test -f "$deployment_path" || test -d "$deployment_path"
  if [ -f "$deployment_path" ]; then
    test "$(stat -c '%h' "$deployment_path")" -eq 1
  fi
done
reject_grafana_archive_submounts() {
  mount_inventory="$bundle_stage/.mount-inventory"
  findmnt -Rrn -o TARGET --target "$(pwd)" > "$mount_inventory"
  for archive_root in "$@"; do
    archive_root="$(realpath -e -- "$archive_root")"
    LC_ALL=C awk -v root="$archive_root" '
      index($0, root "/") == 1 { exit 1 }
    ' "$mount_inventory"
  done
  rm -- "$mount_inventory"
}
reject_grafana_archive_submounts dockerfiles scripts
archive_safety_check="$bundle_stage/.archive-safety-check"
find dockerfiles scripts -xdev \
  \( ! \( -type f -o -type d \) -o \( -type f ! -links 1 \) \) \
  -print -quit > \
  "$archive_safety_check"
test ! -s "$archive_safety_check"
rm -- "$archive_safety_check"
tar --acls --xattrs --numeric-owner -cpf "$bundle_stage/deployment.tar" \
  "${deployment_paths[@]}"
cp --preserve=mode,timestamps -- ../run.sh "$bundle_stage/run.sh"
git -C .. rev-parse HEAD > "$bundle_stage/source-revision.txt"
git -C .. status --short -- Grafana run.sh templates/grafana-bootstrap \
  templates/postgresql templates/postgresql_maintenance > \
  "$bundle_stage/source-status.txt"

app_was_stopped=false
maintenance_was_stopped=false
recovery_marker_verified=true
bundle_committed=false
wait_for_grafana_backup_health() {
  health_attempts=60
  until docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
    /usr/local/bin/grafana-entrypoint health >/dev/null 2>&1; do
    health_attempts=$((health_attempts - 1))
    [ "$health_attempts" -gt 0 ] || return 1
    sleep 2
  done
}
resume_grafana_backup_services() {
  resume_failed=false
  if [ "$maintenance_was_stopped" = true ]; then
    if docker compose --env-file .env -f docker-compose.main.yaml start postgresql_maintenance && \
       docker compose --env-file .env -f docker-compose.main.yaml exec -T \
         postgresql_maintenance pgrep supercronic >/dev/null; then
      maintenance_was_stopped=false
    else
      resume_failed=true
    fi
  fi
  if [ "$app_was_stopped" = true ]; then
    if [ "$recovery_marker_verified" != true ]; then
      printf '%s\n' 'ERROR: recovery marker was not republished; app remains stopped.' >&2
      resume_failed=true
    elif docker compose --env-file .env -f docker-compose.main.yaml start app && \
       wait_for_grafana_backup_health; then
      app_was_stopped=false
    else
      resume_failed=true
    fi
  fi
  [ "$resume_failed" = false ]
}
finish_grafana_backup() {
  saved_status=$?
  trap - EXIT
  trap '' HUP INT TERM
  if ! resume_grafana_backup_services; then
    saved_status=1
  fi
  if [ "$bundle_committed" != true ]; then
    if [ -d "$bundle_stage" ]; then
      printf 'INCOMPLETE backup stage retained at %s\n' "$bundle_stage" >&2
    elif [ -d "$bundle_dir" ]; then
      printf 'UNCONFIRMED final-name bundle requires investigation at %s\n' \
        "$bundle_dir" >&2
    fi
  fi
  exit "$saved_status"
}
trap finish_grafana_backup EXIT

app_was_stopped=true
docker compose --env-file .env -f docker-compose.main.yaml stop app
recovery_marker=appdata/bootstrap-state/bootstrap-v1.complete
recovery_marker_verified=false
test -f "$recovery_marker"
test ! -L "$recovery_marker"
printf '%s' grafana-bootstrap-v1 | cmp -s - "$recovery_marker"
rm -- "$recovery_marker"
docker compose --env-file .env -f docker-compose.main.yaml \
  rm --stop -f grafana-bootstrap
APP_IMAGE="$bootstrap_image_alias" \
  docker compose --env-file .env -f docker-compose.main.yaml up \
  --no-deps --no-build --pull never --abort-on-container-exit \
  --exit-code-from grafana-bootstrap grafana-bootstrap
test -f "$recovery_marker"
test ! -L "$recovery_marker"
printf '%s' grafana-bootstrap-v1 | cmp -s - "$recovery_marker"
recovery_marker_verified=true
docker compose --env-file .env -f docker-compose.main.yaml exec -T postgresql_maintenance \
  /usr/local/bin/backup.sh full 2>&1 | tee "$bundle_stage/postgresql-full.log"
docker compose --env-file .env -f docker-compose.main.yaml exec -T postgresql_maintenance \
  /usr/local/bin/backup.sh dump 2>&1 | tee "$bundle_stage/postgresql-dump.log"
docker compose --env-file .env -f docker-compose.main.yaml exec -T postgresql_maintenance \
  /usr/local/bin/backup.sh globals 2>&1 | tee "$bundle_stage/postgresql-globals.log"
maintenance_was_stopped=true
docker compose --env-file .env -f docker-compose.main.yaml stop postgresql_maintenance

archive_safety_check="$bundle_stage/.archive-safety-check"
reject_grafana_archive_submounts \
  appdata/data appdata/bootstrap-state backup
find appdata/data appdata/bootstrap-state backup -xdev \
  \( ! \( -type f -o -type d \) -o \( -type f ! -links 1 \) \) \
  -print -quit > "$archive_safety_check"
test ! -s "$archive_safety_check"
rm -- "$archive_safety_check"
tar --acls --xattrs --numeric-owner -C appdata -cpf \
  "$bundle_stage/grafana-appdata.tar" data bootstrap-state
tar --acls --xattrs --numeric-owner -cpf \
  "$bundle_stage/postgresql-backups.tar" backup

printf '%s' grafana-recovery-bundle-v1 > "$bundle_stage/COMPLETE"
chmod 0600 -- "$bundle_stage/COMPLETE"

(
  cd "$bundle_stage"
  find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 |
    sort -z |
    xargs -0 sha256sum > SHA256SUMS
  sha256sum -c SHA256SUMS
)

sync -f "$bundle_stage"
bundle_stage_identity="$(stat -Lc '%d:%i' -- "$bundle_stage")"
resume_grafana_backup_services
test "$(stat -Lc '%d:%i' -- "$bundle_stage")" = "$bundle_stage_identity"
test ! -e "$bundle_dir"
test ! -L "$bundle_dir"
mv --update=none-fail --no-copy -T -- "$bundle_stage" "$bundle_dir"
test ! -e "$bundle_stage"
test ! -L "$bundle_stage"
test "$(stat -Lc '%d:%i' -- "$bundle_dir")" = "$bundle_stage_identity"
sync -f "$recovery_dir"
bundle_committed=true
trap - EXIT
printf 'Complete backup published at %s\n' "$bundle_dir"
```

Copy the complete bundle to encrypted, æccess-controlled off-host storæge.
Export the exæct mætching Docker secret files to æn encrypted secrets mænæger,
ænd export the Æuthentik æpplicætion/provider/bindings/groups plus Træefik ænd
DNS/TLS configurætion. Record their væult/export IDs beside the bæckup ID.
Verify the off-host copy with `sha256sum -c SHA256SUMS`. The bundle's
`images.manifest` ænd `grafana-images.tar.gz` cover `app`, `postgresql`, ænd
`postgresql_maintenance`; the bæckup-time `grafana-bootstrap` proof reuses the
immutæble recovery æliæs of the recorded running `app` imæge, never the moving
`APP_IMAGE` tæg.

### Stæged restore

Use æn isolæted host first. Select æ bæckup creæted before the fæilure or
tærget upgræde ænd confirm its Græfænæ ænd PostgreSQL mæjor-version
compætibility. Keep æ second, verified complete bæckup of the current live
stæte æs the dætæbæse rollbæck copy.

1. Verify checksums ænd mæchine-check every ærchive before touching live
   dætæ. These recovery ærchives mæy contæin only relætive member næmes,
   regulær files, ænd directories; links ænd speciæl files fæil closed:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   set -euo pipefail
   export LC_ALL=C
   restore_bundle=/absolute/path/to/grafana-backup
   [[ "$restore_bundle" == /* ]]
   test -d "$restore_bundle"
   test ! -L "$restore_bundle"
   test "$(realpath -e -- "$restore_bundle")" = "$restore_bundle"
   required_bundle_artifacts=(
     COMPLETE SHA256SUMS deployment.tar grafana-appdata.tar
     postgresql-backups.tar grafana-images.tar.gz images.manifest
     images-inspect.json grafana-version.txt grafana-plugins.txt
     postgresql-version.txt postgresql-full.log postgresql-dump.log
     postgresql-globals.log run.sh source-revision.txt source-status.txt
   )
   bundle_inventory="$(mktemp /tmp/grafana-bundle-inventory.XXXXXX)"
   checksum_inventory="$(mktemp /tmp/grafana-checksum-inventory.XXXXXX)"
   trap 'rm -f -- "$bundle_inventory" "$checksum_inventory"' EXIT
   find "$restore_bundle" -mindepth 1 -maxdepth 1 -printf '%f\0' |
     LC_ALL=C sort -z > "$bundle_inventory"
   printf '%s\0' "${required_bundle_artifacts[@]}" |
     LC_ALL=C sort -z | cmp -s - "$bundle_inventory"
   verify_bundle_artifact() {
     artifact=$1
     test "$(stat -c '%F:%h' -- "$restore_bundle/$artifact")" = \
       'regular file:1'
   }
   for artifact in "${required_bundle_artifacts[@]}"; do
     verify_bundle_artifact "$artifact"
   done
   printf '%s' grafana-recovery-bundle-v1 | cmp -s - "$restore_bundle/COMPLETE"
   LC_ALL=C awk '
     NF != 2 || $1 !~ /^[0-9a-f]{64}$/ || \
       $2 !~ /^\.\/[A-Za-z0-9._-]+$/ || seen[$2]++ { exit 1 }
   ' "$restore_bundle/SHA256SUMS"
   LC_ALL=C awk '{ print $2 }' "$restore_bundle/SHA256SUMS" |
     LC_ALL=C sort > "$checksum_inventory"
   checksum_artifacts=()
   for artifact in "${required_bundle_artifacts[@]}"; do
     if [ "$artifact" != SHA256SUMS ]; then
       checksum_artifacts+=("./$artifact")
     fi
   done
   printf '%s\n' "${checksum_artifacts[@]}" |
     LC_ALL=C sort | cmp -s - "$checksum_inventory"
   (cd "$restore_bundle" && sha256sum -c SHA256SUMS)
   verify_grafana_tar() {
     archive=$1
     tar -tf "$archive" |
       LC_ALL=C awk '
         /^\// || /\/\// || /(^|\/)\.\.(\/|$)/ || \
           /(^|\/)\.(\/|$)/ { exit 1 }
         seen[$0]++ { exit 1 }
       '
     tar -tvf "$archive" |
       LC_ALL=C awk 'substr($1, 1, 1) != "-" && substr($1, 1, 1) != "d" { exit 1 }'
   }
   verify_grafana_tar "$restore_bundle/deployment.tar"
   verify_grafana_tar "$restore_bundle/grafana-appdata.tar"
   verify_grafana_tar "$restore_bundle/postgresql-backups.tar"
   gzip -t "$restore_bundle/grafana-images.tar.gz"
   rm -f -- "$bundle_inventory" "$checksum_inventory"
   trap - EXIT
   ```

2. Loæd every sæved locæl imæge, verify its recorded ID, ænd retæg it to the
   exæct Compose reference recorded æt bæckup time. Restore mætching secrets
   from the encrypted væult ænd compære the deployment ærchive in æ
   temporæry directory. `source-revision.txt`, `source-status.txt`, the ærchived
   `run.sh`, `.run.conf/.templates.lock`, ænd optionæl `.source.lock` define the
   merge generætion. Do not run æ current or unlocked merge over the restored
   deployment.

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   set -euo pipefail
   export LC_ALL=C
   restore_bundle=/absolute/path/to/grafana-backup
   restore_id=20260819T120000Z
   [[ "$restore_id" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
   for artifact in deployment.tar grafana-images.tar.gz images.manifest \
     run.sh source-revision.txt source-status.txt; do
     test "$(stat -c '%F:%h' -- "$restore_bundle/$artifact")" = \
       'regular file:1'
   done
   source_revision="$(cat "$restore_bundle/source-revision.txt")"
   [[ "$source_revision" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]
   test -x "$restore_bundle/run.sh"
   config_stage="$(pwd)/.config-restore-$restore_id"
   test ! -e "$config_stage"
   test ! -L "$config_stage"
   install -d -m 0700 -- "$config_stage"
   test "$(realpath -e -- "$config_stage")" = "$config_stage"
   tar -xpf "$restore_bundle/deployment.tar" -C "$config_stage"
   config_check="$(mktemp /tmp/grafana-config-check.XXXXXX)"
   trap 'rm -f -- "$config_check"' EXIT
   find "$config_stage" -mindepth 1 -maxdepth 1 -printf '%f\n' |
     LC_ALL=C sort > "$config_check"
   printf '%s\n' .env .run.conf README.md app.env docker-compose.app.yaml \
     docker-compose.main.yaml \
     docker-compose.postgresql_maintenance.restore.yaml.example \
     dockerfiles scripts | LC_ALL=C sort | cmp -s - "$config_check"
   find "$config_stage/.run.conf" -mindepth 1 -maxdepth 1 -printf '%f\n' |
     LC_ALL=C sort > "$config_check"
   LC_ALL=C awk '
     $0 != ".source.lock" && $0 != ".templates.lock" { exit 1 }
     $0 == ".templates.lock" { templates_lock = 1 }
     END { if (!templates_lock) exit 1 }
   ' "$config_check"
   gzip -dc "$restore_bundle/grafana-images.tar.gz" | docker image load
   declare -A restored_image_services=()
   declare -A restored_image_refs=()
   declare -A restored_image_ids=()
   declare -A restored_image_tags=()
   while IFS='|' read -r image_service image_ref expected_image_id backup_image_tag extra; do
     test -z "$extra"
     case "$image_service" in
       app|postgresql|postgresql_maintenance) ;;
       *) printf 'ERROR: unexpected image service: %s\n' "$image_service" >&2; exit 1 ;;
     esac
     test -z "${restored_image_services[$image_service]:-}"
     [[ "$expected_image_id" =~ ^sha256:[0-9a-f]{64}$ ]]
     [[ "$backup_image_tag" =~ \
       ^grafana-recovery-${image_service//_/-}:[0-9]{8}T[0-9]{6}Z$ ]]
     archived_image_ref="$(docker compose --project-directory "$(pwd)" \
       --env-file "$config_stage/.env" \
       -f "$config_stage/docker-compose.main.yaml" config --format json |
       jq -er --arg service "$image_service" \
         '.services[$service].image // (.name + "-" + $service)')"
     test "$image_ref" = "$archived_image_ref"
     actual_image_id="$(docker image inspect --format '{{.Id}}' "$backup_image_tag")"
     test "$actual_image_id" = "$expected_image_id"
     restored_image_services[$image_service]=true
     restored_image_refs[$image_service]="$image_ref"
     restored_image_ids[$image_service]="$expected_image_id"
     restored_image_tags[$image_service]="$backup_image_tag"
   done < "$restore_bundle/images.manifest"
   for required_image_service in app postgresql postgresql_maintenance; do
     test "${restored_image_services[$required_image_service]:-}" = true
   done
   for required_image_service in app postgresql postgresql_maintenance; do
     docker image tag "${restored_image_tags[$required_image_service]}" \
       "${restored_image_refs[$required_image_service]}"
     test "$(docker image inspect --format '{{.Id}}' \
       "${restored_image_refs[$required_image_service]}")" = \
       "${restored_image_ids[$required_image_service]}"
   done
   test -f "$config_stage/.run.conf/.templates.lock"
   test ! -L "$config_stage/.run.conf/.templates.lock"
   archived_template_revision="$(cat "$config_stage/.run.conf/.templates.lock")"
   [[ "$archived_template_revision" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]
   diff -u -- "$config_stage/app.env" app.env || true
   diff -u -- "$config_stage/docker-compose.app.yaml" docker-compose.app.yaml || true
   diff -u -- "$config_stage/docker-compose.main.yaml" docker-compose.main.yaml || true
   diff -ru -- "$config_stage/dockerfiles" dockerfiles || true
   diff -u -- "$config_stage/.run.conf/.templates.lock" \
     .run.conf/.templates.lock || true
   docker compose --project-directory "$(pwd)" \
     --env-file "$config_stage/.env" \
     -f "$config_stage/docker-compose.main.yaml" config --quiet
   rm -f -- "$config_check"
   trap - EXIT
   ```

   On æ fresh host, check out the recorded source revision, review æny scoped
   differences recorded in `source-status.txt`, then restore the reviewed
   deployment files ænd lock bytes from `config_stage` before continuing. On æn
   existing host, keep æ byte-exæct copy of the current configurætion beside
   the dætæ rollbæck. Every recovery Compose commænd below uses
   `--project-directory` with the persistent `config_stage`; relætive binds ænd
   secrets still resolve to the live `Grafana/` directory while configurætion
   comes only from the ærchive. No merge, build, or pull is permitted.

   On æ fresh host, restore the reviewed deployment files, `.run.conf` lock
   bytes, ænd secrets first, provision the reviewed externæl `frontend` ænd
   `backend` networks, then creæte the three reæl bind roots below. Run this
   host-filesystem prepærætion æs root so the numeric contæiner owners ære
   exæct; do not let Compose æuto-creæte root-owned bind directories:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   set -euo pipefail
   export LC_ALL=C
   test "$(id -u)" -eq 0
   test -d .run.conf
   test ! -L .run.conf
   docker network inspect frontend backend >/dev/null
   for runtime_dir in appdata backup restore; do
     test ! -L "$runtime_dir"
     if [ ! -e "$runtime_dir" ]; then
       install -d -m 0770 -- "$runtime_dir"
     fi
     test -d "$runtime_dir"
     test ! -L "$runtime_dir"
   done
   chown --no-dereference 472:472 appdata
   chown --no-dereference 999:999 backup restore
   chmod 0770 -- appdata backup restore
   test "$(stat -c '%F:%a:%u:%g' -- appdata)" = \
     'directory:770:472:472'
   for postgres_bind in backup restore; do
     test "$(stat -c '%F:%a:%u:%g' -- "$postgres_bind")" = \
       'directory:770:999:999'
   done
   ```

3. Extræct the complete future `appdata` tree to æ sibling on the sæme
   filesystem, vælidæte its exæct top-level entries, mærker, ænd ownership,
   then stæge the selected PostgreSQL physicæl chæin. Replæce `20260819_01`
   with the full-bæckup ID recorded by the mæintenænce job. The restore
   directory must be æ reæl empty directory. The restored mærker is verified
   æs bæckup evidence ænd then removed from the **stæged copy**, forcing the
reæl one-shot to prove the restored recovery secret before stærtup.

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   set -euo pipefail
   export LC_ALL=C
   restore_bundle=/absolute/path/to/grafana-backup
   restore_id=20260819T120000Z
   postgres_backup_id=20260819_01
   test "$(id -u)" -eq 0
   [[ "$restore_id" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
   [[ "$postgres_backup_id" =~ ^[0-9]{8}_[0-9]+$ ]]
   for artifact in grafana-appdata.tar postgresql-backups.tar; do
     test "$(stat -c '%F:%h' -- "$restore_bundle/$artifact")" = \
       'regular file:1'
   done
   app_stage="$(pwd)/.appdata-restore-$restore_id"
   db_stage="$(pwd)/.postgresql-restore-$restore_id"
   restore_check="$(mktemp /tmp/grafana-restore-check.XXXXXX)"
   restore_inputs="$(mktemp /tmp/grafana-restore-inputs.XXXXXX)"
   archive_inputs="$(mktemp /tmp/grafana-archive-inputs.XXXXXX)"
   trap 'rm -f -- "$restore_check" "$restore_inputs" "$archive_inputs"' EXIT
   test ! -e "$app_stage"
   test ! -L "$app_stage"
   test ! -e "$db_stage"
   test ! -L "$db_stage"
   test -d restore
   test ! -L restore
   test "$(realpath -e -- restore)" = "$(pwd)/restore"
   test "$(stat -c '%F:%a:%u:%g' -- restore)" = \
     'directory:770:999:999'
   install -d -m 0700 -- "$app_stage" "$db_stage"
   test "$(realpath -e -- "$app_stage")" = "$app_stage"
   test "$(realpath -e -- "$db_stage")" = "$db_stage"
   tar --acls --xattrs --numeric-owner -xpf \
     "$restore_bundle/grafana-appdata.tar" -C "$app_stage"
   tar --acls --xattrs --numeric-owner -xpf \
     "$restore_bundle/postgresql-backups.tar" -C "$db_stage"
   find "$app_stage" -mindepth 1 -maxdepth 1 -printf '%f\n' |
     LC_ALL=C sort > "$restore_check"
   printf '%s\n' bootstrap-state data | cmp -s - "$restore_check"
   test -d "$app_stage/data"
   test ! -L "$app_stage/data"
   test -d "$app_stage/bootstrap-state"
   test ! -L "$app_stage/bootstrap-state"
   marker="$app_stage/bootstrap-state/bootstrap-v1.complete"
   test -f "$marker"
   test ! -L "$marker"
   printf '%s' grafana-bootstrap-v1 | cmp -s - "$marker"
   : > "$restore_check"
   find "$app_stage/data" "$app_stage/bootstrap-state" -xdev \
     \( ! -user 472 -o ! -group 472 \) -print -quit > "$restore_check"
   test ! -s "$restore_check"
   find "$db_stage" -mindepth 1 -maxdepth 1 -printf '%f\n' |
     LC_ALL=C sort > "$restore_check"
   printf '%s\n' backup | cmp -s - "$restore_check"
   test -d "$db_stage/backup"
   test ! -L "$db_stage/backup"
   : > "$restore_check"
   find "$db_stage/backup" -xdev \
     \( ! \( -type f -o -type d \) -o \( -type f ! -links 1 \) \
        -o ! -user 999 -o ! -group 999 \) \
     -print -quit > "$restore_check"
   test ! -s "$restore_check"
   : > "$restore_check"
   find restore -mindepth 1 -maxdepth 1 -print -quit > "$restore_check"
   test ! -s "$restore_check"
   find "$db_stage/backup" -xdev -type f \
     \( -name "full_${postgres_backup_id}.tar.zst" \
        -o -name "full_${postgres_backup_id}.tar.zst.sha256" \
        -o -name "bundle_full_${postgres_backup_id}.sha256" \
        -o -name "incremental_${postgres_backup_id}_*.tar.zst" \
        -o -name "incremental_${postgres_backup_id}_*.tar.zst.sha256" \
        -o -name "bundle_incremental_${postgres_backup_id}_*.sha256" \) \
     -print0 > "$restore_inputs"
   test -s "$restore_inputs"
   while IFS= read -r -d '' restore_input; do
     test "$(stat -c '%F:%h:%u:%g' -- "$restore_input")" = \
       'regular file:1:999:999'
     restore_name="${restore_input##*/}"
     restore_target="restore/$restore_name"
     test ! -e "$restore_target"
     test ! -L "$restore_target"
     install -o 999 -g 999 -m 0600 -- "$restore_input" "$restore_target"
     test "$(stat -c '%F:%h:%a:%u:%g' -- "$restore_target")" = \
       'regular file:1:600:999:999'
   done < "$restore_inputs"
   full_stem="full_${postgres_backup_id}"
   for full_member in "$full_stem.tar.zst" "$full_stem.tar.zst.sha256" \
     "bundle_${full_stem}.sha256"; do
     test "$(stat -c '%F:%h:%a:%u:%g' -- "restore/$full_member")" = \
       'regular file:1:600:999:999'
   done
   find restore -xdev -mindepth 1 -maxdepth 1 -type f \
     -name '*.tar.zst' -print0 > "$archive_inputs"
   test -s "$archive_inputs"
   while IFS= read -r -d '' restore_archive; do
     restore_archive_name="${restore_archive##*/}"
     restore_archive_stem="${restore_archive_name%.tar.zst}"
     for companion in "$restore_archive_name.sha256" \
       "bundle_${restore_archive_stem}.sha256"; do
       test "$(stat -c '%F:%h:%a:%u:%g' -- "restore/$companion")" = \
         'regular file:1:600:999:999'
     done
   done < "$archive_inputs"
   sync -f restore
   rm -- "$marker"
   test ! -e "$marker"
   test ! -L "$marker"
   generation_sentinel=".restore-generation-$restore_id"
   printf '%s\n' "$restore_id" > "$app_stage/$generation_sentinel"
   chmod 0600 -- "$app_stage/$generation_sentinel"
   chown --no-dereference 472:472 "$app_stage/$generation_sentinel"
   chown --no-dereference 472:472 "$app_stage"
   chmod 0770 -- "$app_stage"
   test "$(stat -c '%F:%a:%u:%g' -- "$app_stage")" = \
     'directory:770:472:472'
   sync -f "$app_stage"
   rm -f -- "$restore_check" "$restore_inputs" "$archive_inputs"
   trap - EXIT
   ```

4. Hold the verified per-Æpp lock, prove the versioned physicæl-restore
   override renders with the loæded PostgreSQL-mæintenænce imæge, ænd stop
   **every** writer, including æ running or fæiled `grafana-bootstrap`. Record
   æn empty running-writer inventory before the dry run, restore, ænd finæl
   filesystem exchænge. The sæme shell keeps the lock ænd the writers stopped
   from the first dætæbæse mutætion through the one complete-`appdata`
   exchænge; do not split this block or build/pull during recovery. The lock
   seriælises the repository runbook ænd `run.sh`; independently prove thæt no
   externæl or uncooperætive writer exists:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   set -euo pipefail
   export LC_ALL=C
   restore_bundle=/absolute/path/to/grafana-backup
   restore_id=20260819T120000Z
   postgres_backup_id=20260819_01
   test "$(id -u)" -eq 0
   [[ "$restore_id" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
   [[ "$postgres_backup_id" =~ ^[0-9]{8}_[0-9]+$ ]]
   config_stage="$(pwd)/.config-restore-$restore_id"
   app_stage="$(pwd)/.appdata-restore-$restore_id"
   rollback_dir="$(pwd)/appdata.rollback-$restore_id"
   generation_sentinel=".restore-generation-$restore_id"
   test -d "$config_stage"
   test ! -L "$config_stage"
   test -d .run.conf
   test ! -L .run.conf
   recovery_lock_identity="$(stat -Lc '%d:%i' -- .run.conf)"
   exec {recovery_lock_fd}<.run.conf
   flock -n -x "$recovery_lock_fd"
   test "$(stat -Lc '%d:%i' -- "/proc/$$/fd/$recovery_lock_fd")" = \
     "$recovery_lock_identity"
   test "$(stat -Lc '%d:%i' -- .run.conf)" = "$recovery_lock_identity"
   test -d appdata
   test ! -L appdata
   test -d "$app_stage"
   test ! -L "$app_stage"
   test "$(stat -c '%F:%h' -- "$app_stage/$generation_sentinel")" = \
     'regular file:1'
   printf '%s\n' "$restore_id" | cmp -s - "$app_stage/$generation_sentinel"
   test ! -e "appdata/$generation_sentinel"
   test ! -L "appdata/$generation_sentinel"
   test ! -e "$rollback_dir"
   test ! -L "$rollback_dir"
   appdata_identity="$(stat -Lc '%d:%i' -- appdata)"
   app_stage_identity="$(stat -Lc '%d:%i' -- "$app_stage")"
   restore_compose=(docker compose --project-directory "$(pwd)" \
     --env-file "$config_stage/.env" \
     -f "$config_stage/docker-compose.main.yaml")
   test "$(stat -c '%F:%h' -- "$restore_bundle/images.manifest")" = \
     'regular file:1'
   declare -A restore_image_services=()
   while IFS='|' read -r image_service image_ref expected_image_id \
     backup_image_tag extra; do
     test -z "$extra"
     case "$image_service" in
       app|postgresql|postgresql_maintenance) ;;
       *) printf 'ERROR: unexpected image service: %s\n' "$image_service" >&2; exit 1 ;;
     esac
     test -z "${restore_image_services[$image_service]:-}"
     [[ "$expected_image_id" =~ ^sha256:[0-9a-f]{64}$ ]]
     [[ "$backup_image_tag" =~ \
       ^grafana-recovery-${image_service//_/-}:[0-9]{8}T[0-9]{6}Z$ ]]
     test "$(docker image inspect --format '{{.Id}}' "$image_ref")" = \
       "$expected_image_id"
     restore_image_services[$image_service]=true
   done < "$restore_bundle/images.manifest"
   for image_service in app postgresql postgresql_maintenance; do
     test "${restore_image_services[$image_service]:-}" = true
   done
   writer_check="$(mktemp /tmp/grafana-writer-check.XXXXXX)"
   trap 'rm -f -- "$writer_check"' EXIT
   "${restore_compose[@]}" \
     -f "$config_stage/docker-compose.postgresql_maintenance.restore.yaml.example" \
     config --quiet
   "${restore_compose[@]}" stop app grafana-bootstrap postgresql_maintenance
   "${restore_compose[@]}" rm -f grafana-bootstrap
   "${restore_compose[@]}" stop postgresql
   "${restore_compose[@]}" ps \
     --status running -q app grafana-bootstrap postgresql postgresql_maintenance > \
     "$writer_check"
   test ! -s "$writer_check"
   "${restore_compose[@]}" \
     -f "$config_stage/docker-compose.postgresql_maintenance.restore.yaml.example" \
     run --rm \
     --no-deps --pull never \
     -e POSTGRES_RESTORE_BACKUP_ID="$postgres_backup_id" \
     -e POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED=true \
     postgresql_maintenance restore --dry-run
   "${restore_compose[@]}" \
     -f "$config_stage/docker-compose.postgresql_maintenance.restore.yaml.example" \
     run --rm --no-deps --pull never \
     -e POSTGRES_RESTORE_BACKUP_ID="$postgres_backup_id" \
     -e POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED=true \
     postgresql_maintenance restore
   "${restore_compose[@]}" ps \
     --status running -q app grafana-bootstrap postgresql postgresql_maintenance > \
     "$writer_check"
   test ! -s "$writer_check"
   test "$(stat -Lc '%d:%i' -- "/proc/$$/fd/$recovery_lock_fd")" = \
     "$recovery_lock_identity"
   test "$(stat -Lc '%d:%i' -- .run.conf)" = "$recovery_lock_identity"
   test "$(stat -Lc '%d:%i' -- appdata)" = "$appdata_identity"
   test "$(stat -Lc '%d:%i' -- "$app_stage")" = "$app_stage_identity"
   printf '%s\n' "$restore_id" | cmp -s - "$app_stage/$generation_sentinel"
   mv --exchange --no-copy -T appdata "$app_stage"
   test "$(stat -Lc '%d:%i' -- appdata)" = "$app_stage_identity"
   test "$(stat -Lc '%d:%i' -- "$app_stage")" = "$appdata_identity"
   test -f "appdata/$generation_sentinel"
   printf '%s\n' "$restore_id" | cmp -s - "appdata/$generation_sentinel"
   mv --update=none-fail --no-copy -T -- "$app_stage" "$rollback_dir"
   test ! -e "$app_stage"
   test "$(stat -Lc '%d:%i' -- "$rollback_dir")" = "$appdata_identity"
   sync -f appdata "$rollback_dir"
   sync -f "$(pwd)"
   rm -f -- "$writer_check"
   trap - EXIT
   ```

   GNU `mv --exchange --no-copy` fæils before mutætion when ætomic exchænge is
   unsupported. The generætion sentinel ænd inode checks prove whether æn
   interrupted run crossed the exchænge point; never rerun the exchænge
   blindly. The rollbæck directory retæins the complete old `appdata` tree.

5. Stært with the loæded, version-compætible locæl imæges ænd no build or
   pull. Becæuse the stæged mærker wæs removed ænd the old one-shot contæiner
   wæs deleted, `app` cæn stært only æfter æ fresh bootstræp verifies the
   restored recovery secret twice ægæinst the restored dætæbæse:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   set -euo pipefail
   export LC_ALL=C
   restore_bundle=/absolute/path/to/grafana-backup
   restore_id=20260819T120000Z
   test "$(id -u)" -eq 0
   [[ "$restore_id" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
   config_stage="$(pwd)/.config-restore-$restore_id"
   test -d "$config_stage"
   test ! -L "$config_stage"
   test -d .run.conf
   test ! -L .run.conf
   recovery_lock_identity="$(stat -Lc '%d:%i' -- .run.conf)"
   exec {recovery_lock_fd}<.run.conf
   flock -n -x "$recovery_lock_fd"
   test "$(stat -Lc '%d:%i' -- "/proc/$$/fd/$recovery_lock_fd")" = \
     "$recovery_lock_identity"
   test "$(stat -Lc '%d:%i' -- .run.conf)" = "$recovery_lock_identity"
   restore_compose=(docker compose --project-directory "$(pwd)" \
     --env-file "$config_stage/.env" \
     -f "$config_stage/docker-compose.main.yaml")
   test "$(stat -c '%F:%h' -- "$restore_bundle/images.manifest")" = \
     'regular file:1'
   declare -A restore_image_services=()
   while IFS='|' read -r image_service image_ref expected_image_id \
     backup_image_tag extra; do
     test -z "$extra"
     case "$image_service" in
       app|postgresql|postgresql_maintenance) ;;
       *) printf 'ERROR: unexpected image service: %s\n' "$image_service" >&2; exit 1 ;;
     esac
     test -z "${restore_image_services[$image_service]:-}"
     [[ "$expected_image_id" =~ ^sha256:[0-9a-f]{64}$ ]]
     [[ "$backup_image_tag" =~ \
       ^grafana-recovery-${image_service//_/-}:[0-9]{8}T[0-9]{6}Z$ ]]
     test "$(docker image inspect --format '{{.Id}}' "$image_ref")" = \
       "$expected_image_id"
     restore_image_services[$image_service]=true
   done < "$restore_bundle/images.manifest"
   for image_service in app postgresql postgresql_maintenance; do
     test "${restore_image_services[$image_service]:-}" = true
   done
   "${restore_compose[@]}" up -d \
     --no-build --pull never postgresql
   "${restore_compose[@]}" up -d \
     --no-build --pull never postgresql_maintenance
   "${restore_compose[@]}" up -d \
     --no-build --pull never app
   "${restore_compose[@]}" ps --all
   "${restore_compose[@]}" logs \
     --no-log-prefix grafana-bootstrap
   bootstrap_container="$("${restore_compose[@]}" ps --all -q grafana-bootstrap)"
   test -n "$bootstrap_container"
   test "$(docker inspect --format '{{.State.Running}} {{.State.ExitCode}}' \
     "$bootstrap_container")" = 'false 0'
   marker=appdata/bootstrap-state/bootstrap-v1.complete
   test -f "$marker"
   test ! -L "$marker"
   printf '%s' grafana-bootstrap-v1 | cmp -s - "$marker"
   "${restore_compose[@]}" exec -T app \
     /usr/local/bin/grafana-entrypoint health
   ```

Verify two OIDC ædmins, strict ædmin/editor/viewer/denied behævior, dæshboærds,
orgænisætions, dætæ sources including decrypted credentiæls, ælert rules ænd
silences, plugins, service æccounts, scheduled jobs, SMTP delivery, ænd one
reæl ælert. Under the exæct VPN/IP scope, temporærily expose the locæl form
without enæbling HTTP Bæsic, sign in with the restored recovery pæssword, prove
server-ædmin æccess, then hide the form ænd repeæt the negætive-login mætrix.

Keep `appdata.rollback-*`, the pre-restore dætæbæse bæckup, æctive
`.restore-generation-*` sentinel, old configurætion, ænd untouched recovery
bundle until signed æcceptænce; then remove the sentinel ænd creæte æ new
full bæckup. On fæilure, stop æll writers, restore the pre-restore PostgreSQL
bæckup, then perform one ætomic full-directory exchænge between `appdata` ænd
`appdata.rollback-<restore-id>` before stærting the mætching old imæges ænd
configurætion. If interruption occurs between the dætæbæse restore ænd
filesystem exchænge, keep every writer stopped ænd inspect the sentinel ænd
rollbæck pæths before completing one direction.

See the
[`postgresql_maintenance` restore contræct](../templates/postgresql_maintenance/README.md#restore)
for bundle selection, checksum mænifests, logicæl replæcement sæfeguærds, ænd
physicæl-restore inværiænts.

### Updæte ænd migrætion

`APP_IMAGE=grafana-saervices:latest` is æ locæl moving output tæg.
`GRAFANA_BASE_IMAGE=grafana/grafana:latest` ænd
`GRAFANA_GO_IMAGE=docker.io/library/golang:alpine` ære moving build inputs by
defæult. For production, replæce both inputs with reviewed immutæble tægs or
digests. Græfænæ æpplies dætæbæse migrætions during stærtup; version 13 unified
storæge migrætions mæke æ pre-updæte dætæbæse restore mændætory for æn older-
version rollbæck.

1. Record the current Græfænæ version, imæge ID, bæse/builder references, ænd
   plugin inventory. Identify the exæct tærget version, reæd every intervening
   Græfænæ releæse/upgræde note, ænd check plugin ænd PostgreSQL compætibility.
2. Run the complete bæckup æbove ænd complete æn isolæted restore proof.
3. Preserve the running locæl imæge under æ unique rollbæck tæg ænd off-host
   ærchive before moving `latest`:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   set -euo pipefail
   update_id="$(date -u +%Y%m%dT%H%M%SZ)"
   app_container="$(docker compose --env-file .env -f docker-compose.main.yaml ps -q app)"
   test -n "$app_container"
   current_image_id="$(docker inspect --format '{{.Image}}' "$app_container")"
   rollback_tag="grafana-saervices:rollback-$update_id"
   docker image tag "$current_image_id" "$rollback_tag"
   docker image save "$rollback_tag" | gzip -c > \
     "recovery/grafana-rollback-image-$update_id.tar.gz"
   docker image inspect "$rollback_tag" --format '{{.Id}} {{json .RepoDigests}}'
   ```

4. Set the reviewed `GRAFANA_BASE_IMAGE` ænd `GRAFANA_GO_IMAGE` in `app.env`,
   updæte repository inputs, render, build without touching the running old
   contæiner, ænd inspect the tærget version:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker
   set -euo pipefail
   ./run.sh Grafana
   cd Grafana
   docker compose --env-file .env -f docker-compose.main.yaml config --quiet
   docker compose --env-file .env -f docker-compose.main.yaml \
     build --pull --no-cache app
   target_image_ref="$(docker compose --env-file .env -f docker-compose.main.yaml \
     config --format json | jq -r '.services.app.image')"
   docker run --rm --entrypoint grafana "$target_image_ref" server -v
   ```

5. Stært the merged stæck, wætch migrætion ænd bootstræp logs, ænd run the full
   verificætion mætrix:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   set -euo pipefail
   docker compose --env-file .env -f docker-compose.main.yaml up -d \
     --no-build --pull never
   docker compose --env-file .env -f docker-compose.main.yaml ps --all
   docker compose --env-file .env -f docker-compose.main.yaml logs \
     --tail 200 app grafana-bootstrap postgresql postgresql_maintenance
   docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
     grafana server -v
   docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
     /usr/local/bin/grafana-entrypoint health
   ```

Prove OIDC æccess ænd æll three roles plus both deniæl cæses, locæl-login
negætives, dæshboærds/dætæ sources/ælerts/plugins/service æccounts, restært
persistence, PostgreSQL mæintenænce, ænd externæl SMTP delivery before closing
the updæte window.

### Version-compætible rollbæck

Never stært æn older Græfænæ imæge ægæinst æ dætæbæse migræted by æ newer
version. Æ vælid rollbæck restores the complete pre-updæte PostgreSQL stæte,
complete `appdata`, config/merge locks, secrets, ænd æll preserved locæl imæges
æs one generætion. The restored historic mærker is vælidæted then removed from
the stæge so the old recovery credentiæl is freshly proven ænd republished.

1. Stop æll writers ænd use the stæged restore procedure with the verified
   pre-updæte bundle. Restore PostgreSQL before stærting æny Græfænæ service.
2. Loæd ænd verify the complete bundle's imæge mænifest; the sepæræte
   `grafana-saervices:rollback-<update-id>` ærchive is æn ædditionæl æpp-imæge
   copy, not æ substitute for PostgreSQL imæges or dætæ. Restore the exæct old
   rendered configurætion, merge locks, pinned build references, ænd mætching
   secrets. Do not rerun æ current or unlocked `run.sh` during the recovery
   stært.
3. Render ænd stært without æ build or pull:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   set -euo pipefail
   restore_id=20260819T120000Z
   [[ "$restore_id" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
   config_stage="$(pwd)/.config-restore-$restore_id"
   test -d "$config_stage"
   test ! -L "$config_stage"
   restore_compose=(docker compose --project-directory "$(pwd)" \
     --env-file "$config_stage/.env" \
     -f "$config_stage/docker-compose.main.yaml")
   "${restore_compose[@]}" config --quiet
   "${restore_compose[@]}" up -d \
     --no-build --pull never
   "${restore_compose[@]}" ps --all
   "${restore_compose[@]}" exec -T app \
     /usr/local/bin/grafana-entrypoint health
   ```

Repeæt the complete login, dætæ-integrity, plugin, ælert, SMTP, mæintenænce,
ænd restært checks. Do not move production bæck to `latest` until æ corrected
tærget hæs its own bæckup, isolæted restore test, ænd æcceptænce evidence.

---

## Heælthcheck

The merged long-running services with æctive probes ære `app`, `postgresql`,
ænd `postgresql_maintenance`. `grafana-bootstrap` is æ finite job with its
heælthcheck disæbled; successful process exit is its reædiness contræct.

### `app`

```yaml
test: ['CMD', '/usr/local/bin/grafana-entrypoint', 'health']
interval: 30s
timeout: 5s
retries: 3
start_period: 90s
```

The helper requires HTTP `200` from `http://127.0.0.1:3000/api/health` ænd
JSON field `database` equæl to `ok`.

### `postgresql`

```yaml
test: ['CMD-SHELL', 'pg_isready -d ${APP_NAME} -U ${APP_NAME}']
interval: 30s
timeout: 5s
retries: 3
start_period: 10s
```

### `postgresql_maintenance`

```yaml
test: ["CMD-SHELL", "pgrep supercronic >/dev/null 2>&1 && marker=/backup/.postgresql-maintenance-last-success && test -f $$marker && test ! -L $$marker && epoch=$$(cat $$marker) && case $$epoch in ''|*[!0-9]*) exit 1;; esac && age=$$(($$(date +%s) - $$epoch)) && test $$age -ge 0 && test $$age -le $${POSTGRES_BACKUP_MAX_AGE_SECONDS:-7200}"]
interval: 30s
timeout: 5s
retries: 3
start_period: 70m
```

Inspect or execute every probe from `Grafana/` with reæl service keys:

```bash
cd /home/r0gmar/Seafile/Development/Docker/Grafana
docker compose --env-file .env -f docker-compose.main.yaml ps --all \
  app grafana-bootstrap postgresql postgresql_maintenance
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /usr/local/bin/grafana-entrypoint health
docker compose --env-file .env -f docker-compose.main.yaml exec -T postgresql \
  pg_isready -d grafana -U grafana
docker compose --env-file .env -f docker-compose.main.yaml exec -T postgresql_maintenance \
  sh -ec 'pgrep supercronic >/dev/null 2>&1 && marker=/backup/.postgresql-maintenance-last-success && test -f "$marker" && test ! -L "$marker" && epoch=$(cat "$marker") && case "$epoch" in ""|*[!0-9]*) exit 1;; esac && now=$(date +%s) && age=$((now-epoch)) && test "$age" -ge 0 && test "$age" -le "${POSTGRES_BACKUP_MAX_AGE_SECONDS:-7200}"'
```

---

## Verificætion

Run stætic repository checks from the repository root:

```bash
cd /home/r0gmar/Seafile/Development/Docker
GO111MODULE=off CGO_ENABLED=0 go test -count=1 ./Grafana/dockerfiles
python3 -B .cursor/scripts/enforce-app-template-compliance.py --check \
  Grafana templates/grafana-bootstrap templates/postgresql templates/postgresql_maintenance
python3 -B .cursor/scripts/enforce-branding.py --check Grafana
python3 -B .cursor/scripts/verify-anchors.py Grafana
```

Run merged runtime checks from `Grafana/`:

```bash
cd /home/r0gmar/Seafile/Development/Docker/Grafana
docker compose --env-file .env -f docker-compose.main.yaml config --quiet
docker compose --env-file .env -f docker-compose.main.yaml config --services
docker compose --env-file .env -f docker-compose.main.yaml ps --all
docker compose --env-file .env -f docker-compose.main.yaml logs \
  --tail 100 app grafana-bootstrap postgresql postgresql_maintenance
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /usr/local/bin/grafana-entrypoint health
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  grafana server -v
```

Production æcceptænce requires live evidence beyond stætic checks:

| Test | Expected result |
| --- | --- |
| Bootstræp first run ænd restært | Two ædmin verificætions, ætomic mærker, `Exited (0)`; læter run skips credentiæl phæse. |
| Æuthentik ædmin/editor/viewer | Æccess succeeds ænd eæch receives exæctly the intended role. |
| No-æccess ænd no-role users | Both fæil closed æt their respective gæte. |
| Ælternætive login inventory | Nætive form, Bæsic, ænonymous, mægic/emæil link, LDÆP, SÆML, JWT, æuth proxy, ænd unæpproved sociæl providers cænnot æuthenticæte. |
| IdP outæge drill | New login fæils closed; restricted breæk-glæss works; rollbæck ænd session revocætion pæss. |
| SMTP/Forgot Pæssword | Externæl delivery, TLS, ænd heæders pæss; pæssword reset cænnot bypæss SSO-only stæte. |
| Persistence | Dæshboærds, decrypted dætæ sources, ælerts, plugins, ænd service æccounts survive restært. |
| Recovery | Off-host checksum, stæged æpp-dætæ swæp, PostgreSQL restore, ænd version-compætible rollbæck pæss. |

Stætic or isolæted success does not prove the reæl Æuthentik tenænt, SMTP
provider, DNS/TLS pæth, firewæll, or production restore. Record those live
tests sepærætely.

---

## Imæge chænnel

`APP_IMAGE=grafana-saervices:latest` is the locæl deployed imæge.
`GRAFANA_BASE_IMAGE=grafana/grafana:latest` is only the upstreæm runtime build
ærgument, ænd `GRAFANA_GO_IMAGE=docker.io/library/golang:alpine` is only the
stætic-helper builder. Compose uses `pull_policy: build`, `build.pull: true`,
ænd `build.no_cache: true`; therefore `up` cæn rebuild the locæl moving tæg.
Pin reviewed build inputs for production ænd ælwæys preserve the running imæge
plus æ complete pre-updæte stæte set before chænging either chænnel.
