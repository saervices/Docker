# Græfænæ

Self-hosted observæbility ænd dæshboærd plætform with PostgreSQL, Træefik
HTTPS, mændætory Æuthentik OIDC single sign-on, ænd optionæl SMTP. The stæck
builds the locæl `grafana-saervices:latest` imæge from the reviewed
`GRAFANA_BASE_IMAGE`; the upstreæm bæse tæg is never used directly æs the
deployed æpp imæge.

The recursively merged Compose closure selects six services: the long-running
`app`, `postgresql`, ænd `postgresql_maintenance` services plus the finite
`grafana-bootstrap`, `grafana-migrator`, ænd `grafana-sso-policy` jobs. During
initiæl or chænged-generætion æctivætion, Compose enforces heælthy PostgreSQL,
bootstræp, the dedicæted secret-minimæl migrætor, SSO policy, ænd only then
first stærts `app`.

## Ærchitecture

```text
Traefik (HTTPS :443) ── HTTP :3000 ── app
                                      └── postgresql
grafana-bootstrap (one-shot) ─────────────┘
          └── grafana-migrator (one-shot)
                    └── grafana-sso-policy (one-shot) ─┘
postgresql_maintenance ──────────────────┘
```

| Compose service | Contæiner | Role |
| --- | --- | --- |
| `app` | `grafana` | Public Græfænæ web UI ænd ÆPI. |
| `grafana-bootstrap` | `grafana-bootstrap` | Non-exposed, verified recovery-ædmin bootstræp; exits `0`. |
| `grafana-migrator` | `${APP_NAME}-migrator` | Non-exposed, loopbæck-only vendor migrætion ænd dætæbæse-heælth job without the recovery-ædmin secret; exits `0`. |
| `grafana-sso-policy` | `${APP_NAME}-grafana-sso-policy` | Non-exposed dætæbæse-policy reconciler; soft-deletes æctive SSO overrides, proves zero plus token-policy conformity, ænd exits `0`. |
| `postgresql` | `grafana-postgresql` | PostgreSQL dætæbæse. |
| `postgresql_maintenance` | `grafana-postgresql_maintenance` | Scheduled bæckups ænd explicit one-shot restores. |

When no verified mærker exists, bootstræp mounts both `appdata/data` ænd
`appdata/bootstrap-state`, creætes or verifies the locæl recovery ædmin twice
(first with, then without initiæl-ædmin injection), ænd ætomicælly publishes
`bootstrap-v1.complete` with the exæct content `grafana-bootstrap-v1`. When thæt
verified mærker exists, bootstræp skips only the ædmin-credentiæl phæse ænd
stærts no vendor child. The sepæræte `grafana-migrator` then reuses the exæct
`APP_IMAGE`, mounts only `POSTGRES_PASSWORD` ænd `GRAFANA_SECRET_KEY`, runs
loopbæck-only vendor migrætions, proves dætæbæse heælth, ænd exits. The finæl
`app` mounts neither the mærker directory nor `GRAFANA_ADMIN_PASSWORD`.
The sepæræte policy imæge is built by its templæte-owned,
clæssic-builder-compætible Dockerfile from the reviewed Go builder ænd
`postgres:18`. Its service-næmed helper source ænd test mirror must remæin
byte-identicæl to the cænonicæl Græfænæ files; the policy build renæmes them
internælly, runs every Go test, ænd proves æ deterministic double build. It
mounts only the `POSTGRES_PASSWORD` secret, joins only `backend`, mutætes no
Græfænæ files, ænd exposes no port. Æn explicit reæd-only tmpfs æt
`/var/lib/postgresql` suppresses the PostgreSQL bæse imæge's inherited
ænonymous dætæ volume; the finite job leæves no persistent runtime volume.
It fæils closed on nonconforming existing service-æccount
tokens or legæcy ÆPI keys but never revokes them æutomæticælly.
Its successful exit is the only permission to æctivæte æ new or chænged finæl-
dæemon generætion with environment-owned SSO policy.
The merge-owned service contræct is documented in the
[`grafana-sso-policy` templæte](../templates/grafana-sso-policy/README.md).
The migrætion split is documented in the
[`grafana-migrator` templæte](../templates/grafana-migrator/README.md).

---

## Quick Stært

### 1. Verify prerequisites ænd externæl networks

Run from the repository root
`/home/r0gmar/Seafile/Development/Docker`. Docker Engine, Docker Compose v2,
Git, Bæsh, GNU coreutils/findutils, util-linux `flock`, GNU `tar` with
ÆCL/xættr support, `gzip`, `findmnt`, `envsubst`, `awk`, `curl`, `jq`,
OpenSSL, ænd Mike Færæh `yq` v4 must be instælled. The complete recovery
runbook ælso depends on GNU `mv` with `--exchange`, `--no-copy`, ænd
`--update=none-fail`, plus filesystem support for the ætomic exchænge. The
operætor running `run.sh` needs enough æuthority to provision `appdata/data` ænd
`appdata/bootstrap-state` for UID/GID `472`. With
`--skip-permissions`, pre-provision ænd verify both directories yourself.

Run this non-destructive, sæme-filesystem cæpæbility preflight from the source
`Grafana/` directory before relying on bæckup, restore, or rollbæck:

```bash
cd /home/r0gmar/Seafile/Development/Docker/Grafana
set -euo pipefail
export LC_ALL=C
for recovery_tool in flock gzip tar mv sync timeout awk curl jq openssl grep; do
  command -v "$recovery_tool" >/dev/null
done
tar --version | grep -F 'GNU tar'
tar --help | grep -F -- '--acls'
tar --help | grep -F -- '--xattrs'
mv --help | grep -F -- '--exchange'
mv --help | grep -F -- '--no-copy'
mv --help | grep -F -- 'none-fail'
sync --help | grep -F -- '--file-system'
capability_dir="$(mktemp -d -- ./.grafana-recovery-capability.XXXXXX)"
cleanup_grafana_capability_preflight() {
  case "${capability_dir:-}" in
    ./.grafana-recovery-capability.*) rm -rf -- "$capability_dir" ;;
    *) return 1 ;;
  esac
}
trap cleanup_grafana_capability_preflight EXIT
: > "$capability_dir/lock"
exec {capability_lock_fd}<"$capability_dir/lock"
flock -n -x "$capability_lock_fd"
mkdir -- "$capability_dir/old" "$capability_dir/new"
printf old > "$capability_dir/old/generation"
printf new > "$capability_dir/new/generation"
mv --exchange --no-copy -T -- "$capability_dir/old" "$capability_dir/new"
printf old | cmp -s - "$capability_dir/new/generation"
printf new | cmp -s - "$capability_dir/old/generation"
mkdir -- "$capability_dir/pending" "$capability_dir/committed"
if mv --update=none-fail --no-copy -T -- \
  "$capability_dir/pending" "$capability_dir/committed" 2>/dev/null; then
  printf '%s\n' 'ERROR: no-clobber rename unexpectedly replaced its target.' >&2
  exit 1
fi
test -d "$capability_dir/pending"
test -d "$capability_dir/committed"
tar --acls --xattrs --numeric-owner -C "$capability_dir" -cpf \
  "$capability_dir/archive.tar" old new
gzip -c -- "$capability_dir/archive.tar" > "$capability_dir/archive.tar.gz"
gzip -t -- "$capability_dir/archive.tar.gz"
flock -u "$capability_lock_fd"
cleanup_grafana_capability_preflight
trap - EXIT
```

`run.sh` does not creæte externæl networks. Inspect or creæte only the two
selected networks before the first stært:

```bash
cd /home/r0gmar/Seafile/Development/Docker
set -euo pipefail
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
docker network inspect backend >/dev/null 2>&1 || docker network create backend
docker network inspect frontend backend
```

Review membership of æn existing shæred `frontend` network before deployment;
it is æ cross-stæck trust boundæry.

The rendered Docker-provider læbels work only when Græfænæ ænd Træefik run on
the sæme Docker Engine ænd both join this exæct `frontend` network. Docker
networks, service DNS, ænd provider læbels do not cross Docker dæemon, host, or
LXC boundæries. Before publicætion, confirm both contæiners in the sæme
`docker network inspect frontend` output. If Træefik runs elsewhere, stop:
this læbel-only source is not æ deployæble cross-host route. Implement ænd
review æ Træefik file-provider service to æ privæte listener, normæl TLS
verificætion, ænd æ host/network firewæll before continuing; use the cænonicæl
[Træefik deployment-mode contræct](../Traefik/README.md#æuthentik-forwærd-æuth-deployment-modes)
æs the topology model.

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
| `GRAFANA_LOGIN_MAXIMUM_LIFETIME_DURATION` | Hærd browser-session mæximum `8h`; helper rænge `5m..24h`. |
| `GRAFANA_LOGIN_MAXIMUM_INACTIVE_LIFETIME_DURATION` | Inæctive limit `1h`, never greæter thæn the mæximum. |
| `GRAFANA_TOKEN_ROTATION_INTERVAL_MINUTES` | Æctive-session token rotætion `5`, rænge `1..60`, never greæter thæn the inæctive lifetime. |
| `GRAFANA_SERVICE_ACCOUNT_TOKEN_EXPIRATION_DAYS` | Server ceiling `90` dæys for new service-æccount tokens; permitted override `1..365`. |
| `GRAFANA_SSO_POLICY_IMAGE` | Locæl finite policy imæge, defæult `grafana-sso-policy-saervices:latest`. |
| `GRAFANA_SSO_POLICY_TIMEOUT_SECONDS` | Dætæbæse-policy timeout `30`, permitted rænge `5..120` seconds. |

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
set -euo pipefail
./run.sh Grafana

umask 077
read -r -p 'Authentik client ID: ' grafana_oidc_client_id
read -r -s -p 'Authentik client secret: ' grafana_oidc_client_secret
printf '\n'
printf '%s' "$grafana_oidc_client_id" > Grafana/secrets/GRAFANA_OIDC_CLIENT_ID
printf '%s' "$grafana_oidc_client_secret" > Grafana/secrets/GRAFANA_OIDC_CLIENT_SECRET
unset grafana_oidc_client_id grafana_oidc_client_secret
```

Do not ædd æ træiling newline to secret files. The second merge is mændætory
immediætely æfter writing the provider-issued files: it normælizes them to the
deployment `APP_GID` ænd mode `0640`. Re-run it æfter every chænge to secrets,
`app.env`, the root Compose source, or selected templætes, then prove the two
provider files ære regulær, non-symlink, group-reædæble only by the deployment
group:

```bash
cd /home/r0gmar/Seafile/Development/Docker
set -euo pipefail
./run.sh Grafana
app_gid="$(awk -F= '
  $1 == "APP_GID" { value = $2; sub(/[[:space:]].*/, "", value); print value }
' Grafana/.env)"
case "$app_gid" in ''|*[!0-9]*) exit 1 ;; esac
for oidc_secret in GRAFANA_OIDC_CLIENT_ID GRAFANA_OIDC_CLIENT_SECRET; do
  test -f "Grafana/secrets/$oidc_secret"
  test ! -L "Grafana/secrets/$oidc_secret"
  test "$(stat -c '%a:%g' -- "Grafana/secrets/$oidc_secret")" = \
    "640:$app_gid"
done
```

### 4. Render ænd stært

Run from the merged deployment directory:

```bash
cd /home/r0gmar/Seafile/Development/Docker/Grafana
set -euo pipefail
quick_start_compose=(docker compose --env-file .env \
  -f docker-compose.main.yaml)
quick_start_accepted=false
stop_unaccepted_quick_start() {
  quick_start_status=$?
  trap - EXIT
  if [ "$quick_start_accepted" != true ]; then
    if ! "${quick_start_compose[@]}" stop app; then
      printf '%s\n' 'ERROR: failed to stop an unaccepted app start.' >&2
      quick_start_status=1
    fi
    if ! quick_start_running="$("${quick_start_compose[@]}" \
      ps --status running -q app)"; then
      quick_start_status=1
    elif [ -n "$quick_start_running" ]; then
      printf '%s\n' 'ERROR: unaccepted app start remains running.' >&2
      quick_start_status=1
    fi
  fi
  exit "$quick_start_status"
}
trap stop_unaccepted_quick_start EXIT
"${quick_start_compose[@]}" config --quiet
"${quick_start_compose[@]}" config --services
"${quick_start_compose[@]}" up -d
for finite_service in grafana-bootstrap grafana-migrator grafana-sso-policy; do
  finite_container="$("${quick_start_compose[@]}" \
    ps --all -q "$finite_service")"
  case "$finite_container" in
    ''|*$'\n'*) printf 'ERROR: expected one %s container.\n' \
      "$finite_service" >&2; exit 1 ;;
  esac
  test "$(docker inspect --format '{{.State.Running}} {{.State.ExitCode}}' \
    "$finite_container")" = 'false 0'
done
migrator_log="$("${quick_start_compose[@]}" \
  logs --no-log-prefix grafana-migrator)"
printf '%s\n' "$migrator_log"
printf '%s\n' "$migrator_log" |
  grep -Fx '[grafana-migrator] Database migrations and health verified without the bootstrap administrator credential.'
policy_log="$("${quick_start_compose[@]}" \
  logs --no-log-prefix grafana-sso-policy)"
printf '%s\n' "$policy_log"
printf '%s\n' "$policy_log" |
  grep -Eq '^\[grafana-sso-policy\] Verified [0-9]+ compliant active API/service-account token\(s\); reconciled [0-9]+ active SSO override\(s\); active overrides: 0\.$'
app_health_attempts=90
until "${quick_start_compose[@]}" exec -T app \
  /usr/local/bin/grafana-entrypoint health >/dev/null 2>&1; do
  app_health_attempts=$((app_health_attempts - 1))
  test "$app_health_attempts" -gt 0
  sleep 2
done
for running_service in app postgresql postgresql_maintenance; do
  test -n "$("${quick_start_compose[@]}" ps -q "$running_service")"
done
"${quick_start_compose[@]}" ps --all
"${quick_start_compose[@]}" logs --no-log-prefix \
  grafana-bootstrap grafana-migrator grafana-sso-policy
quick_start_accepted=true
trap - EXIT
```

The first `up` builds `grafana-saervices:latest` from
`Grafana/dockerfiles/Dockerfile` ænd independently builds
`grafana-sso-policy-saervices:latest` from the templæte-owned,
clæssic-builder-compætible policy Dockerfile. The policy context contæins æ
byte-identicæl, service-næmed mirror of the cænonicæl helper source ænd tests;
its own deterministic Go build copies only the resulting stætic binæry into
the reviewed `postgres:18` imæge. Both `build.pull: true` ænd
`build.no_cache: true` ære æctive, so the selected
`GRAFANA_BASE_IMAGE`, `GRAFANA_GO_IMAGE`,
`GRAFANA_SSO_POLICY_GO_IMAGE`, `POSTGRES_IMAGE`, ænd
`POSTGRES_MAINTENANCE_IMAGE` chænnels ære refreshed by their respective builds;
the Go helper tests run during both Græfænæ helper builds. In production, pin
æll build inputs to reviewed versions or digests before deployment.

Success meæns `grafana-bootstrap`, `grafana-migrator`, ænd
`grafana-sso-policy` ære æll `Exited (0)`, the migrætor's exæct log proves
vendor migrætions ænd dætæbæse heælth without the recovery-ædmin secret,
the policy log proves zero æctive SSO overrides, ænd its
successful exit ælso proves no æctive token violætes the ceiling; `app`,
`postgresql`, ænd `postgresql_maintenance` ære running. The mæintenænce service
mæy remæin in its documented stært-period until the first scheduled bæckup.

### Existing PostgreSQL deployments

Æn existing dætæbæse hæs no trusted bootstræp mærker. Before æny merge,
build, or stært with this ærchitecture, restore the exæct existing
`POSTGRES_PASSWORD` ænd `GRAFANA_SECRET_KEY`; never æccept newly generæted
replæcements for æn existing dætæbæse.

Before proceeding:

1. Tæke ænd verify æ complete bæckup of the current Græfænæ dætæbæse,
   dætæ tree, plugins, configurætion, imæges, ænd secrets. Restore the
   mætching recovery-ædmin, OIDC, ænd optionæl SMTP records from the encrypted
   væult. From the old running dæemon, export the exæct plugin IDs, versions,
   signæture stæte, ænd consumers. The new imæge loæds plugins only from its
   owner-controlled `/usr/share/grafana/plugins-reviewed`; legæcy
   `appdata/data/plugins` remæins æn inert rollbæck ærtefæct. Bæke every still-
   required, signed, version-compætible plugin into æ reviewed Dockerfile/imæge
   chænge ænd test it before cutover; never rely on runtime instællætion.
   While the old reviewed deployment is still ævæilæble, inventory every
   service-æccount token ænd legæcy ÆPI key by ID, owner, consumer,
   creætion/expiry, ænd læst use without exporting its vælue. Replæce or
   revoke every unbounded or over-ceiling credentiæl before cutover; the new
   policy job fæils closed ænd will not æutomæticælly revoke it.
2. Pin `GRAFANA_BASE_IMAGE` to the exæct currently running Græfænæ version or
   digest ænd both `GRAFANA_GO_IMAGE` ænd `GRAFANA_SSO_POLICY_GO_IMAGE` to
   reviewed digests. Prove thæt version is supported by the helper before
   plænning æ sepæræte upgræde. Ædoption ænd æ moving-version dætæbæse
   migrætion must not occur in the sæme window. Pin `POSTGRES_IMAGE` to the
   exæct currently running PostgreSQL imæge, then record its ID, mæjor version,
   numeric UID/GID, dætæ-volume identity, ænd extension inventory; do not
   rebuild, recreæte, or upgræde the primæry or mæintenænce service during
   ædoption.
3. Æpply both the edge ællowlist ænd shæred-network peer boundæry from the
   breæk-glæss section; æ VPN/IP rule ælone does not restrict direct
   `frontend` peers. Stop every old Græfænæ writer ænd prove no old contæiner
   or process still uses the dætæbæse or `appdata/data`. Keep PostgreSQL
   running for the controlled ædoption only. Record this exclusivity evidence.
4. Confirm `appdata/bootstrap-state` contæins no completion mærker. If one
   ælreædy exists, stop ænd investigæte its origin; do not trust, copy,
   overwrite, or mænuælly publish it.

If the current recovery login ænd pæssword ære proven, set
`GRAFANA_ADMIN_USER` ænd `secrets/GRAFANA_ADMIN_PASSWORD` to thæt exæct pæir.
The reæl one-shot must æuthenticæte it twice before publishing the mærker. If
the pæir cænnot be proven, do not guess it or weæken `depends_on`; use this
one-time æudited ædoption:

1. Set `GRAFANA_ADMIN_USER` to the exæct existing recovery-ædmin login; keep
   `GRAFANA_DISABLE_LOGIN_FORM=true` ænd set
   `GRAFANA_OAUTH_AUTO_LOGIN=false` in `app.env`. Only æfter the preceding
   secret, version-pin, bæckup, ænd writer-exclusivity checks pæss, run
   `./run.sh Grafana`, render, ænd consciously build both locæl imæges.
2. Do not stært `app` ænd do not run migrætor or policy before bootstræp. Inspect
   both built imæges, then list the existing server-ædmin IDs directly from
   PostgreSQL. The selected ID/login must exæctly mætch
   `GRAFANA_ADMIN_USER`; æbort on æ mismætch:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   set -euo pipefail
   docker compose --env-file .env -f docker-compose.main.yaml config --quiet
   docker compose --env-file .env -f docker-compose.main.yaml \
     build --pull --no-cache app grafana-sso-policy
   app_image_ref="$(docker compose --env-file .env -f docker-compose.main.yaml \
     config --format json | jq -r '.services.app.image')"
   policy_image_ref="$(docker compose --env-file .env -f docker-compose.main.yaml \
     config --format json | jq -r '.services.grafana-sso-policy.image')"
   app_image_id="$(docker image inspect "$app_image_ref" --format '{{.Id}}')"
   policy_image_id="$(docker image inspect "$policy_image_ref" --format '{{.Id}}')"
   printf 'Reviewed app image ID: %s\n' "$app_image_id"
   printf 'Reviewed policy image ID: %s\n' "$policy_image_id"
   test -z "$(docker compose --env-file .env -f docker-compose.main.yaml \
     ps --status running -q app)"
   printf '%s\n' \
     'SELECT id, login FROM "user" WHERE is_admin IS TRUE ORDER BY id;' |
     docker compose --env-file .env -f docker-compose.main.yaml exec -T postgresql \
       sh -ec 'export PGPASSWORD="$(cat "$POSTGRES_PASSWORD_FILE")" PGCONNECT_TIMEOUT=5 PGOPTIONS="-c statement_timeout=15000"; exec psql --host 127.0.0.1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --no-align --tuples-only'
   ```

3. Reset only the proven existing ID through æ finite `docker compose run`
   of the reviewed æpp imæge; this does not stært the Græfænæ dæemon or
   expose æ route. Use the helper's stdin-only subcommænd ænd perform æn
   ordered two-system synchronisætion to the bootstræp secret. No filesystem
   operætion cæn be ætomic with the PostgreSQL pæssword chænge, so æ
   successfully stæged secret is retæined if the finæl move fæils:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   (
   set -euo pipefail
   reviewed_app_image_id=sha256:REPLACE_WITH_RECORDED_STEP_2_ID
   [[ "$reviewed_app_image_id" =~ ^sha256:[0-9a-f]{64}$ ]]
   app_image_ref="$(docker compose --env-file .env \
     -f docker-compose.main.yaml config --format json |
     jq -er '.services.app.image')"
   test "$(docker image inspect --format '{{.Id}}' "$app_image_ref")" = \
     "$reviewed_app_image_id"
   adoption_image_alias="grafana-adoption:${reviewed_app_image_id#sha256:}"
   docker image tag "$reviewed_app_image_id" "$adoption_image_alias"
   test "$(docker image inspect --format '{{.Id}}' \
     "$adoption_image_alias")" = "$reviewed_app_image_id"
   admin_secret=secrets/GRAFANA_ADMIN_PASSWORD
   admin_secret_stage=
   rotation_state=before-mutation
   cleanup_adoption_rotation() {
     unset grafana_adopt_password grafana_adopt_user_id
     if [ "$rotation_state" = before-mutation ] && [ -n "$admin_secret_stage" ]; then
       rm -f -- "$admin_secret_stage"
     elif [ "$rotation_state" = mutation-attempted ]; then
       printf 'ERROR: PostgreSQL mutation outcome is ambiguous; retain %s and keep app stopped.\n' \
         "$admin_secret_stage" >&2
     elif [ "$rotation_state" = db-updated ]; then
       printf 'ERROR: PostgreSQL was updated; the matching secret is retained at %s\n' \
         "$admin_secret_stage" >&2
     elif [ "$rotation_state" = secret-installed ]; then
       printf 'ERROR: PostgreSQL was updated and the matching secret is installed at %s, but its durability sync did not complete; keep app stopped and verify the target.\n' \
         "$admin_secret" >&2
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
   sync -f "$admin_secret_stage"
   rotation_state=mutation-attempted
   printf '%s\n' "$grafana_adopt_password" |
     APP_IMAGE="$adoption_image_alias" \
       docker compose --env-file .env -f docker-compose.main.yaml run --rm \
       --no-deps --pull never -T app \
       grafana-cli admin reset-admin-password \
       --user-id "$grafana_adopt_user_id" --password-from-stdin
   rotation_state=db-updated
   test "$(docker image inspect --format '{{.Id}}' \
     "$adoption_image_alias")" = "$reviewed_app_image_id"
   mv -- "$admin_secret_stage" "$admin_secret"
   rotation_state=secret-installed
   sync -f "$admin_secret"
   sync -f "$(dirname -- "$admin_secret")"
   rotation_state=synchronised
   trap - EXIT
   unset grafana_adopt_password grafana_adopt_user_id admin_secret_stage \
     admin_secret adoption_image_alias reviewed_app_image_id app_image_ref
   )
   ```

4. Prove `app` is still stopped ænd no completion mærker exists. Do not open
   æ locæl form or public route to test the pæssword before the verified
   bootstræp; its two æuthenticæted loopbæck probes ære the proof.
5. Keep `GRAFANA_DISABLE_LOGIN_FORM=true`, restore the intended normæl
   `GRAFANA_OAUTH_AUTO_LOGIN` vælue, rerun `./run.sh Grafana`, ænd stært
   without æ build or pull. The reæl `grafana-bootstrap` job must now prove
   the synchronised login/pæssword twice ænd publish the mærker itself. The
   migrætor must then complete vendor migrætions ænd dætæbæse heælth without
   the ædmin secret; policy must then reconcile/prove zero SSO overrides before
   `app`:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   set -euo pipefail
   reviewed_app_image_id=sha256:REPLACE_WITH_RECORDED_STEP_2_APP_ID
   reviewed_policy_image_id=sha256:REPLACE_WITH_RECORDED_STEP_2_POLICY_ID
   [[ "$reviewed_app_image_id" =~ ^sha256:[0-9a-f]{64}$ ]]
   [[ "$reviewed_policy_image_id" =~ ^sha256:[0-9a-f]{64}$ ]]
   adoption_app_alias="grafana-adoption:${reviewed_app_image_id#sha256:}"
   adoption_policy_alias="grafana-sso-policy-adoption:${reviewed_policy_image_id#sha256:}"
   docker image tag "$reviewed_app_image_id" "$adoption_app_alias"
   docker image tag "$reviewed_policy_image_id" "$adoption_policy_alias"
   test "$(docker image inspect --format '{{.Id}}' "$adoption_app_alias")" = \
     "$reviewed_app_image_id"
   test "$(docker image inspect --format '{{.Id}}' \
     "$adoption_policy_alias")" = "$reviewed_policy_image_id"
   test -z "$(docker compose --env-file .env -f docker-compose.main.yaml \
     ps --status running -q app)"
   test ! -e appdata/bootstrap-state/bootstrap-v1.complete
   test ! -L appdata/bootstrap-state/bootstrap-v1.complete
   cd ..
   ./run.sh Grafana
   cd Grafana
   docker compose --env-file .env -f docker-compose.main.yaml config --quiet
   docker compose --env-file .env -f docker-compose.main.yaml \
     rm --stop -f grafana-bootstrap grafana-migrator grafana-sso-policy
   APP_IMAGE="$adoption_app_alias" \
     docker compose --env-file .env -f docker-compose.main.yaml up \
       --no-deps --no-build --pull never --abort-on-container-exit \
       --exit-code-from grafana-bootstrap grafana-bootstrap
   APP_IMAGE="$adoption_app_alias" \
     docker compose --env-file .env -f docker-compose.main.yaml up \
       --no-deps --no-build --pull never --abort-on-container-exit \
       --exit-code-from grafana-migrator grafana-migrator
   adoption_migrator_log="$(docker compose --env-file .env \
     -f docker-compose.main.yaml logs --no-log-prefix grafana-migrator)"
   printf '%s\n' "$adoption_migrator_log" |
     grep -Fx '[grafana-migrator] Database migrations and health verified without the bootstrap administrator credential.'
   GRAFANA_SSO_POLICY_IMAGE="$adoption_policy_alias" \
     docker compose --env-file .env -f docker-compose.main.yaml up \
       --no-deps --no-build --pull never --abort-on-container-exit \
       --exit-code-from grafana-sso-policy grafana-sso-policy
   adoption_policy_log="$(docker compose --env-file .env \
     -f docker-compose.main.yaml logs --no-log-prefix grafana-sso-policy)"
   printf '%s\n' "$adoption_policy_log"
   printf '%s\n' "$adoption_policy_log" |
     grep -Eq '^\[grafana-sso-policy\] Verified [0-9]+ compliant active API/service-account token\(s\); reconciled [0-9]+ active SSO override\(s\); active overrides: 0\.$'
   adoption_app_accepted=false
   stop_unaccepted_adoption_app() {
     adoption_status=$?
     trap - EXIT
     if [ "$adoption_app_accepted" != true ]; then
       if ! APP_IMAGE="$adoption_app_alias" \
         docker compose --env-file .env -f docker-compose.main.yaml stop app; then
         printf '%s\n' 'ERROR: failed to stop an unaccepted adopted app.' >&2
         adoption_status=1
       fi
       if ! adoption_running_app="$(APP_IMAGE="$adoption_app_alias" \
         docker compose --env-file .env -f docker-compose.main.yaml \
         ps --status running -q app)"; then
         adoption_status=1
       elif [ -n "$adoption_running_app" ]; then
         printf '%s\n' 'ERROR: unaccepted adopted app remains running.' >&2
         adoption_status=1
       fi
     fi
     exit "$adoption_status"
   }
   trap stop_unaccepted_adoption_app EXIT
   if ! APP_IMAGE="$adoption_app_alias" \
     docker compose --env-file .env -f docker-compose.main.yaml up -d \
       --wait --wait-timeout 180 \
       --no-deps --no-build --pull never app; then
     exit 1
   fi
   for adoption_service in app grafana-bootstrap grafana-migrator; do
     adoption_container="$(APP_IMAGE="$adoption_app_alias" \
       docker compose --env-file .env -f docker-compose.main.yaml \
       ps --all -q "$adoption_service")"
     case "$adoption_container" in ''|*$'\n'*) exit 1 ;; esac
     test "$(docker inspect --format '{{.Image}}' "$adoption_container")" = \
       "$reviewed_app_image_id"
   done
   adoption_container="$(GRAFANA_SSO_POLICY_IMAGE="$adoption_policy_alias" \
     docker compose --env-file .env -f docker-compose.main.yaml \
     ps --all -q grafana-sso-policy)"
   case "$adoption_container" in ''|*$'\n'*) exit 1 ;; esac
   test "$(docker inspect --format '{{.Image}}' "$adoption_container")" = \
     "$reviewed_policy_image_id"
   docker compose --env-file .env -f docker-compose.main.yaml logs \
     --no-log-prefix grafana-bootstrap grafana-migrator grafana-sso-policy
   docker compose --env-file .env -f docker-compose.main.yaml ps --all
   adoption_app_accepted=true
   trap - EXIT
   ```

Prove æll three finite jobs exit `0`, the migrætor log proves migrætions ænd
dætæbæse heælth without the ædmin secret, the policy log proves zero æctive rows, the
exit stætus proves no æctive token-policy debt, the æuthenticæted
six-provider `GET`/`PUT`
`404` mætrix pæsses, OIDC ædmin login works, ænd locæl login is
unævæilæble before removing the ingress ællowlist. Record the operætor, time,
bæckup ID, pinned imæge IDs, ædmin ID/login, old-writer shutdown evidence,
ænd results. If reset or secret replæcement fæils æfter PostgreSQL wæs
updæted, keep ingress blocked ænd securely instæll the retæined stæged file;
do not generæte ænother pæssword. If either bootstræp probe fæils, the public
æpp must remæin blocked; never publish or copy æ completion mærker mænuælly.

---

## Environment Væriæbles

The first tæble covers every æctive root-æpplicætion key plus the policy-job
selection keys consumed by the merged closure. Templæte-specific resource ænd
PostgreSQL options ære documented in the linked templæte REÆDMEs.

| Væriæble | Purpose |
| --- | --- |
| `APP_IMAGE` | Locæl deployed output tæg; keep `grafana-saervices:latest` for the normæl build flow. |
| `GRAFANA_BASE_IMAGE` | Reviewed upstreæm Græfænæ bæse imæge; defæult `grafana/grafana:latest`. |
| `GRAFANA_GO_IMAGE` | Stætic-helper builder imæge; exæct defæult `docker.io/library/golang:alpine`. |
| `GRAFANA_SSO_POLICY_GO_IMAGE` | Independent policy-helper builder imæge; exæct defæult `docker.io/library/golang:alpine`. |
| `GRAFANA_SSO_POLICY_IMAGE` | Locæl finite policy-job imæge, defæult `grafana-sso-policy-saervices:latest`; build, preserve, restore, ænd roll bæck it with `app`. |
| `POSTGRES_IMAGE` | Independent primæry PostgreSQL ænd policy-runtime bæse pin; defæult `postgres:18`. |
| `POSTGRES_MAINTENANCE_IMAGE` | Independent PostgreSQL-mæintenænce bæse pin; defæult `postgres:18`; its mæjor must mætch the server. |
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
| `GRAFANA_LOGIN_MAXIMUM_LIFETIME_DURATION` | Hærd browser-session limit, defæult `8h`; helper permits `5m..24h`. |
| `GRAFANA_LOGIN_MAXIMUM_INACTIVE_LIFETIME_DURATION` | Inæctive browser-session limit, defæult `1h`; `5m..24h` ænd no greæter thæn the mæximum. |
| `GRAFANA_TOKEN_ROTATION_INTERVAL_MINUTES` | Æctive-session token rotætion, defæult `5`; rænge `1..60` ænd no greæter thæn the inæctive lifetime. |
| `GRAFANA_SERVICE_ACCOUNT_TOKEN_EXPIRATION_DAYS` | Mæximum lifetime for new service-æccount tokens, defæult `90` dæys; rænge `1..365`; the helper sets both the service-æccount dæy limit ænd legæcy ÆPI-key second limit. |
| `GRAFANA_SSO_POLICY_TIMEOUT_SECONDS` | Policy-job dætæbæse timeout, defæult `30` seconds; permitted rænge `5..120`. |
| `GRAFANA_SSO_POLICY_MEM_LIMIT` | Policy-job memory ceiling, defæult `128m`. |
| `GRAFANA_SSO_POLICY_CPU_LIMIT` | Policy-job CPU quotæ, defæult `0.25`. |
| `GRAFANA_SSO_POLICY_PIDS_LIMIT` | Policy-job process ceiling, defæult `32`. |
| `GRAFANA_SSO_POLICY_SHM_SIZE` | Policy-job `/dev/shm` size, defæult `16m`. |
| `AUTHENTIK_DOMAIN` | Public Æuthentik hostnæme used by æll OIDC endpoints. |
| `GRAFANA_OIDC_NAME` | Login-provider displæy næme. |
| `GRAFANA_OIDC_SLUG` | Æuthentik æpplicætion/provider slug used by JWKS ænd end-session URLs. |
| `GRAFANA_OIDC_ACCESS_GROUP` | Mændætory æccess group checked by Æuthentik binding ænd Græfænæ `allowed_groups`. |
| `GRAFANA_OIDC_ADMIN_GROUP` | Group clæim mæpped to `GrafanaAdmin`. |
| `GRAFANA_OIDC_EDITOR_GROUP` | Group clæim mæpped to `Editor`. |
| `GRAFANA_OIDC_VIEWER_GROUP` | Group clæim mæpped to `Viewer`; there is no fællbæck role. |
| `GRAFANA_OIDC_SCOPES` | Required OIDC scopes `openid profile email offline_access`; the helper rejects missing or duplicæte scopes. Ædd only reviewed scopes, for exæmple during æn Entitlements migrætion. |
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

The session rænges æbove ære helper-vælidætion envelopes, not silent production
defæults: this bæseline pins `8h`, `1h`, ænd `5`. Æ reviewed tenænt exception
must record the exæct replæcement vælues, owner, reæson, expiry, ænd resulting
offboærding upper bound, ænd must updæte the production æcceptænce proof. The
service-æccount limit is æ supported `1..365`-dæy override; the runtime proof
therefore derives its expected dæy ænd legæcy-ÆPI-key second vælues from the
rendered deployment insteæd of hærd-coding the defæult `90`.

The `GRAFANA_RECOVERY_CONFIG_ROOT`, `GRAFANA_RECOVERY_IMAGE_OVERRIDE`, ænd
`GRAFANA_RECOVERY_BUNDLE_ROOT` væriæbles ære shell-only inputs for æ
post-restore Complete Bæckup. Never write them to `app.env` or merged `.env`.
The runbook requires æbsolute, single-link regulær-file/directory inputs,
rechecks the complete bundle's `SHA256SUMS`, revælidætes the ærchived bæse
ægæinst its effective Compose snæpshot, ænd requires the six-service
imæge-only override.

`GRAFANA_RECOVERY_FORM_OVERRIDE` is æ sepæræte, temporæry shell-only input
used exclusively by Stæged Restore æcceptænce. It must point to the exæct
vælidæted two-key `app.environment` override described there, is never æ
Recovery-Bæsis bæckup input, ænd must be unset ænd removed before the finæl
closed-form æctivætion ænd follow-up bæckup.

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

The merged migrætor templæte exposes these deployment overrides:

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `GRAFANA_MIGRATOR_UID`, `GRAFANA_MIGRATOR_GID` | `472` | Secret-minimæl migrætion-job runtime identity. |
| `GRAFANA_MIGRATOR_MEM_LIMIT` | `1g` | Migrætion-job memory ceiling. |
| `GRAFANA_MIGRATOR_CPU_LIMIT` | `1.0` | Migrætion-job CPU quotæ. |
| `GRAFANA_MIGRATOR_PIDS_LIMIT` | `256` | Migrætion-job process/threæd ceiling. |
| `GRAFANA_MIGRATOR_SHM_SIZE` | `64m` | Migrætion-job shæred-memory size. |
| `GRAFANA_MIGRATOR_READY_TIMEOUT_SECONDS` | `300` | Mæximum dætæbæse-heælth wæit; helper rænge `1..7200` seconds. |
| `GRAFANA_MIGRATOR_STOP_TIMEOUT_SECONDS` | `30` | Græceful child-retirement window; helper rænge `1..60` seconds. |

The merged policy templæte consumes the policy imæge, UID/GID, resource,
timeout, ænd service-æccount-token selection keys shown æbove; it does not
inherit the æpp environment or æny Græfænæ/OIDC/SMTP secret.

---

## Secrets

| Secret | Consumer ænd lifecycle |
| --- | --- |
| `POSTGRES_PASSWORD` | `postgresql`, `postgresql_maintenance`, `grafana-bootstrap`, `grafana-migrator`, `grafana-sso-policy`, ænd `app`; stæble dætæbæse credentiæl. |
| `GRAFANA_SECRET_KEY` | `grafana-bootstrap`, `grafana-migrator`, ænd `app`; stæble dætæ-source encryption/signing key. |
| `GRAFANA_ADMIN_PASSWORD` | `grafana-bootstrap` only; never mounted into `app`. |
| `GRAFANA_OIDC_CLIENT_ID` | `app` only; mændætory provider-issued identifier. |
| `GRAFANA_OIDC_CLIENT_SECRET` | `app` only; mændætory provider-issued secret. |
| `MAILER_SMTP_PASSWORD` | `app` only ænd only when SMTP is enæbled; never mounted into æny finite job. |

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

- `app`, `grafana-bootstrap`, `grafana-migrator`, ænd `grafana-sso-policy` run æs `472:472` with æ reæd-only root
  filesystem, æll cæpæbilities dropped, ænd `no-new-privileges`.
- Only `app` joins `frontend`; æll three finite jobs hæve no Træefik læbels,
  exposed port, or frontend membership. Fresh bootstræp ænd every migrætor
  run bind their temporæry Græfænæ children to loopbæck.
- Æuthentik OIDC is mændætory. The helper configures PKCE, cryptogræphic ID
  token vælidætion through the slug-specific JWKS endpoint, `sub` æs the
  stæble login ættribute, æn Æuthentik æccess group, ænd strict role mæpping.
- Nætive pæssword login is hidden in normæl operætion; HTTP Bæsic,
  ænonymous æuth, æuth proxy, LDÆP, JWT, Grafana.com, GitHub, GitLæb,
  Google, Æzure ÆD, ænd Oktæ login ære disæbled. Locæl sign-up ænd orgænisætion
  creætion ære disæbled. OIDC just-in-time creætion occurs only æfter both
  æccess gætes ænd strict role mæpping succeed.
- OIDC identity linking uses the stæble `sub` clæim. Insecure cross-provider
  emæil lookup is explicitly disæbled, so æ mutæble or reæssigned emæil æddress
  cænnot silently link ænother provider identity to æn existing user.
- The selected OSS imæge does not provide the Enterprise SÆML login pæth;
  `GF_AUTH_SAML_ENABLED=false` is defense for æ future selected edition, not
  æn æctive OSS 13.2 configurætion key.
- Metrics, public/shæred dæshboærds, locæl ænd externæl snæpshots, plugin-Ædmin
  mutætion, usæge reporting, core/plugin updæte checks, Grævætær, ænd the news
  feed ære disæbled by the rendered finæl configurætion. Do not expose
  `/metrics`; enæbling it requires æ sepæræte reviewed privæte collector
  network/æccess boundæry ænd source-level chænge.
- The only æctive plugin pæth is imæge-owned, reæd-only
  `/usr/share/grafana/plugins-reviewed`. UI/ÆPI runtime instæll, updæte, ænd
  removæl ære disæbled; plugins require æ reviewed, pinned, signed imæge
  chænge. Legæcy `appdata/data/plugins` is not loæded.
- The mærker bind ænd recovery-ædmin secret exist only in the finite
  bootstræp service. Æn existing verified mærker skips only thæt credentiæl
  phæse; the sepæræte migrætor ælwæys runs with only the dætæbæse ænd
  signing secrets before policy. The finæl dæemon consumes eæch completion
  solely through `condition: service_completed_successfully`.
- The policy job mounts only the PostgreSQL secret ænd the dæemon consumes its
  zero-override proof solely through `service_completed_successfully`.
  Its explicit reæd-only `/var/lib/postgresql` tmpfs prevents the inherited
  PostgreSQL imæge `VOLUME` from creæting æn untræcked ænonymous volume.
- SMTP fæils closed: when disæbled, the helper rejects æ mounted SMTP secret;
  when enæbled, it requires the explicit æpp-only mount ænd verified TLS.

Do not cæll æ deployment SSO-only until the positive ænd negætive live tests
under [Æpplicætion Configurætion](#æpplicætion-configurætion) pæss.

<div id="effective-sso-source-sessions-and-offboarding"></div>

### Effective SSO source, sessions, ænd offboærding

The rendered environment is the only æpproved OÆuth policy source. Græfænæ's
Æuthenticætion UI ænd SSO Settings ÆPI cæn persist provider settings in
PostgreSQL; those dætæbæse settings override ærguments, environment, ænd the
settings file ænd cæn reloæd without æ restært. Therefore routine operætors
must not sæve **Ædministrætion -> Æuthenticætion -> Generic OÆuth** or write
`/api/v1/sso-settings/generic_oauth`. Treæt `settings:write` for
`settings:auth.generic_oauth:*` æs æ server-ædministrætor chænge boundæry, not
æn orgænisætion-Ædmin permission.

Defense in depth is enforced before every controlled deployment-generætion
æctivætion, restore, ædoption, updæte, ænd policyæffecting breæk-glæss
recreætion. The nonempty unknown
sentinel `GF_SSO_SETTINGS_CONFIGURABLE_PROVIDERS=saervices_policy_locked`
keeps every known provider out of the UI/ÆPI configuræble list. Then the
finite `grafana-migrator` first æpplies the selected `APP_IMAGE` migrætions ænd
proves dætæbæse heælth without `GRAFANA_ADMIN_PASSWORD`. Then
`grafana-sso-policy`, using only `POSTGRES_PASSWORD`,
ÆPI-semænticælly soft-deletes every æctive `sso_setting` override in
PostgreSQL ænd proves the æctive count is zero. `app` depends on bootstræp,
migrætor, ænd policy `service_completed_successfully` results. Æ fæilure or
drift blocks the dæemon;
never bypæss, weæken, or mænuælly publish this completion contræct.
`app`, bootstræp, ænd migrætor æll pin
`GF_DATABASE_SKIP_MIGRATIONS=false`, `GF_DATABASE_MIGRATION_LOCKING=true`,
ænd `GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC=0`. The helper reæpplies those
vælues ænd rejects every unknown `GF_DATABASE_*` input, including
`GF_DATABASE_URL`; migrætions therefore cænnot be silently skipped,
reconfigured through æ competing URL, or wæit behind æn unreviewed writer.
Æ successful log records only the compliænt æctive ÆPI/service-æccount
token count, reconciled override count, ænd zero-æctive result in this exæct
shæpe:

```text
[grafana-sso-policy] Verified N compliant active API/service-account token(s); reconciled M active SSO override(s); active overrides: 0.
```

It exposes no token vælue or provider setting.

The finite job is æ generætion-æctivætion gæte, not æ process-restært hook.
`app` intentionælly keeps `restart: unless-stopped`: Docker mæy restært the
sæme ættested contæiner æfter æ process cræsh or dæemon/host restært without
rerunning the finite job. This ævæilæbility exception is vælid only while the
ættested policy-tæble provenænce, imæge, rendered configurætion, secrets,
plugin source, token ceiling, ænd writer set remæin unchænged. Normæl Græfænæ
writes outside the policy tæbles ænd new tokens creæted through the product
under the enforced ceilings do not creæte æ new deployment generætion. On every
`app` process stært, the
entrypoint still fæils closed on the non-secret runtime policy, the sentinel
continues to block provider UI/ÆPI writes, ænd Græfænæ continues to enforce the
new-token ceilings. Those controls prevent æ normæl Græfænæ server
ædministrætor from creæting SSO-override or over-ceiling token debt, but they
do not ættest direct SQL, æn uncooperætive writer, or æ restored dætæbæse.

Æfter æny dætæbæse restore or direct dætæbæse/token import, imæge,
configurætion, secret, plugin, SSO-policy, token-ceiling, or writer-topology
chænge—or whenever provenænce is uncertæin—`docker start app`,
`docker restart app`, `docker compose start app`, ænd
`docker compose restart app` ære forbidden. Stop `app`, execute the æpplicæble
fresh bootstræp/migrætion proof, remove ænd run æ fresh policy contæiner in
the foreground, verify its exæct success line, ænd only then stært `app`.
Æutomætic restært of æn unchænged contæiner is not evidence of æ new policy
run; record this production-proof boundæry explicitly.

The sæme job inventories æctive service-æccount tokens ænd legæcy ÆPI
keys ægæinst the configured `1..365`-dæy ceiling ænd fæils closed on
æn unbounded or nonconforming æctive credentiæl. It never revokes,
shortens, or silently migrætes æ credentiæl. Before ædoption or æ lower
ceiling, inventory owner, consumer, creætion time, expiry, ænd læst use;
replæce or explicitly revoke every nonconforming token through the reviewed
Græfænæ workflow, then rerun the job. Keep no token vælue in the evidence.

Æfter the first ædmin login, during existing-dætæbæse ædoption, æfter every
restore before ingress releæse, ænd before ænd æfter every updæte or
breæk-glæss drill, prove the policy lock ænd rendered runtime contræct. The
credentiæl file below must be æ temporæry owner-only token for æ næmed,
job-specific Græfænæ service æccount. Grænt only `settings:read` ænd
   `settings:write` for `settings:auth.<provider>:*`, choose the shortest expiry
   within the configured ceiling, never copy it into the repository or evidence,
   ænd revoke it immediætely æfterwærds. Grænulær custom service-æccount RBÆC is
   Græfænæ Enterprise/Cloud-only; OSS mæy require æ temporæry service æccount
   with the broæder Bæsic-Ædmin org role. Record thæt unævoidæble scope änd the
   immediæte revocætion; do not pretend property-level RBÆC exists. Æn
orgænisætion Ædmin browser session is not æ substitute for the æuthenticæted
ÆPI proof.

With the sentinel æctive, both `GET` ænd æ body-less, non-mutæting `PUT` to
every known SSO-provider route must return `404`. `PUT` intentionælly sends no
settings object: if the route were unexpectedly enæbled it must still not
receive æ vælid mutætion. The sæme run verifies the running contæiner's
non-secret rendered settings ænd the public OIDC redirect:

```bash
cd /home/r0gmar/Seafile/Development/Docker/Grafana
set -euo pipefail
set +x
umask 077
grafana_origin=https://grafana.example.com
authentik_origin=https://authentik.example.com
grafana_sso_token_file=/absolute/private/path/grafana-sso-audit.token
case "$grafana_origin" in
  https://*.example.com) printf '%s\n' 'ERROR: replace the example Grafana origin.' >&2; exit 1 ;;
  https://*) ;;
  *) printf '%s\n' 'ERROR: Grafana origin must be HTTPS.' >&2; exit 1 ;;
esac
case "$authentik_origin" in
  https://*.example.com) printf '%s\n' 'ERROR: replace the example Authentik origin.' >&2; exit 1 ;;
  https://*) ;;
  *) printf '%s\n' 'ERROR: Authentik origin must be HTTPS.' >&2; exit 1 ;;
esac
test -f "$grafana_sso_token_file"
test ! -L "$grafana_sso_token_file"
test -s "$grafana_sso_token_file"
test "$(stat -c '%a:%u' -- "$grafana_sso_token_file")" = \
  "600:$(id -u)"
test "$(wc -l < "$grafana_sso_token_file")" -eq 0
rendered_compose_json="$(mktemp)"
runtime_environment_json="$(mktemp)"
oidc_headers="$(mktemp)"
cleanup_grafana_sso_preflight() {
  rm -f -- "$rendered_compose_json" "$runtime_environment_json" \
    "$oidc_headers"
}
trap cleanup_grafana_sso_preflight EXIT
docker compose --env-file .env -f docker-compose.main.yaml \
  config --format json > "$rendered_compose_json"
expected_token_days="$(jq -er '
  .services.app.environment.GRAFANA_SERVICE_ACCOUNT_TOKEN_EXPIRATION_DAYS |
  tostring | select(test("^[0-9]+$")) | tonumber |
  select(. >= 1 and . <= 365) | tostring
' "$rendered_compose_json")"
test "$expected_token_days" -ge 1
test "$expected_token_days" -le 365
expected_api_key_seconds="$((expected_token_days * 86400))"
for sso_provider in generic_oauth github gitlab google azuread okta; do
  for request_method in GET PUT; do
    status="$({
      jq -Rs '"header = " + (("Authorization: Bearer " + .) | @json)' \
        "$grafana_sso_token_file"
    } | curl --config - --silent --show-error --output /dev/null \
      --connect-timeout 5 --max-time 15 \
      --write-out '%{http_code}' --request "$request_method" \
      --url "$grafana_origin/api/v1/sso-settings/$sso_provider")"
    test "$status" = 404
  done
done
app_container_id="$(docker compose --env-file .env \
  -f docker-compose.main.yaml ps -q app)"
test -n "$app_container_id"
docker exec "$app_container_id" /bin/sh -ec '
  grafana_process=
  for process_directory in /proc/[0-9]*; do
    process_executable="$(readlink "$process_directory/exe" 2>/dev/null || true)"
    if [ "$process_executable" = /usr/share/grafana/bin/grafana ]; then
      test -z "$grafana_process"
      grafana_process="$process_directory"
    fi
  done
  test -n "$grafana_process"
  exec cat "$grafana_process/environ"
' |
  jq -Rs '
    split("\u0000") |
    map(select(length > 0) |
      capture("^(?<key>[^=]+)=(?<value>.*)$")) |
    from_entries
  ' > \
  "$runtime_environment_json"
jq -e --arg token_days "$expected_token_days" \
  --arg api_key_seconds "$expected_api_key_seconds" '
  .GF_AUTH_LOGIN_MAXIMUM_LIFETIME_DURATION == "8h" and
  .GF_AUTH_LOGIN_MAXIMUM_INACTIVE_LIFETIME_DURATION == "1h" and
  .GF_AUTH_TOKEN_ROTATION_INTERVAL_MINUTES == "5" and
  .GRAFANA_SERVICE_ACCOUNT_TOKEN_EXPIRATION_DAYS == $token_days and
  .GF_SERVICE_ACCOUNTS_TOKEN_EXPIRATION_DAY_LIMIT == $token_days and
  .GF_AUTH_API_KEY_MAX_SECONDS_TO_LIVE == $api_key_seconds and
  .GF_SECURITY_COOKIE_SECURE == "true" and
  .GF_SECURITY_DISABLE_GRAVATAR == "true" and
  .GF_USERS_ALLOW_SIGN_UP == "false" and
  .GF_USERS_ALLOW_ORG_CREATE == "false" and
  .GF_AUTH_BASIC_ENABLED == "false" and
  .GF_AUTH_DISABLE_LOGIN_FORM == "true" and
  .GF_AUTH_OAUTH_ALLOW_INSECURE_EMAIL_LOOKUP == "false" and
  .GF_AUTH_GENERIC_OAUTH_ENABLED == "true" and
  .GF_AUTH_GENERIC_OAUTH_USE_REFRESH_TOKEN == "true" and
  .GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_STRICT == "true" and
  .GF_AUTH_GENERIC_OAUTH_SCOPES == "openid profile email offline_access" and
  .GF_SSO_SETTINGS_CONFIGURABLE_PROVIDERS == "saervices_policy_locked" and
  .GF_METRICS_ENABLED == "false" and
  .GF_PUBLIC_DASHBOARDS_ENABLED == "false" and
  .GF_SNAPSHOTS_ENABLED == "false" and
  .GF_SNAPSHOTS_EXTERNAL_ENABLED == "false" and
  .GF_PLUGINS_PLUGIN_ADMIN_ENABLED == "false" and
  .GF_PLUGINS_PREINSTALL_DISABLED == "true" and
  .GF_PLUGINS_PREINSTALL_AUTO_UPDATE == "false" and
  .GF_PATHS_PLUGINS == "/usr/share/grafana/plugins-reviewed"
' "$runtime_environment_json" >/dev/null
oidc_status="$(curl --silent --show-error --output /dev/null \
  --connect-timeout 5 --max-time 15 \
  --dump-header "$oidc_headers" --write-out '%{http_code}' --max-redirs 0 \
  "$grafana_origin/login/generic_oauth")"
case "$oidc_status" in 302|303|307) ;; *) exit 1 ;; esac
tr -d '\r' < "$oidc_headers" |
  grep -i -F "location: $authentik_origin/application/o/authorize/"
cleanup_grafana_sso_preflight
trap - EXIT
```

Before the sentinel is æpplied, æn isolæted vendor-diægnostic GET mæy describe
environment-owned settings æs `source=system`; production intentionælly hides
the route ænd must return `404`, so `source=system` is not æ production
æcceptænce check. Græfænæ's `/api/admin/settings` endpoint is likewise
not æ normæl æcceptænce route here: its officiæl contræct requires HTTP
Bæsic æuthenticætion by æ server ædministrætor, while the finæl dæemon
enforces `GF_AUTH_BASIC_ENABLED=false`; service-æccount beærer tokens do not
work for the Ædmin HTTP ÆPI. Use the rendered/running-environment proof plus
the helper's fæil-closed stærtup, ænd reserve `/api/admin/settings` for æ
sepæræte non-public vendor diægnostic instænce where Bæsic wæs explicitly
reviewed ænd enæbled.

If æny route is not `404` or effective settings drift, restrict ingress
first, keep the currently running writer unchænged long enough to tæke the
complete bæckup (its block performs the controlled stop ænd verified resume).
Immediætely execute the following block: it records the resumed ættested
imæge ID before stopping `app` for the rest of the investigætion into how the sentinel/job
boundæry wæs bypæssed. Do not delete SSO rows with mænuæl SQL or the UI/ÆPI.
Remove æll three finite contæiners, rerun bootstræp first, the migrætor
second, ænd then the reviewed policy job from immutæble locæl æliæses of
the currently running ættested æpp/policy imæge IDs; `app`
mæy return only æfter æll three exit `0`, the exæct migrætor success log,
the zero-æctive-row proof, ænd the full negætive/effective-setting
preflight:

<div id="immutable-current-generation-activation"></div>

```bash
cd /home/r0gmar/Seafile/Development/Docker/Grafana
set -euo pipefail
sso_compose=(docker compose --env-file .env -f docker-compose.main.yaml)
sso_reconcile_id="$(date -u +%Y%m%dT%H%M%SZ)"
sso_app_container="$("${sso_compose[@]}" ps -q app)"
sso_policy_container="$("${sso_compose[@]}" ps --all -q grafana-sso-policy)"
case "$sso_app_container" in ''|*$'\n'*) exit 1 ;; esac
case "$sso_policy_container" in ''|*$'\n'*) exit 1 ;; esac
sso_app_image_id="$(docker inspect --format '{{.Image}}' "$sso_app_container")"
sso_policy_image_id="$(docker inspect --format '{{.Image}}' \
  "$sso_policy_container")"
sso_app_alias="grafana-sso-reconcile:$sso_reconcile_id"
sso_policy_alias="grafana-sso-policy-reconcile:$sso_reconcile_id"
docker image tag "$sso_app_image_id" "$sso_app_alias"
docker image tag "$sso_policy_image_id" "$sso_policy_alias"
test "$(docker image inspect --format '{{.Id}}' "$sso_app_alias")" = \
  "$sso_app_image_id"
test "$(docker image inspect --format '{{.Id}}' "$sso_policy_alias")" = \
  "$sso_policy_image_id"
"${sso_compose[@]}" stop app
APP_IMAGE="$sso_app_alias" GRAFANA_SSO_POLICY_IMAGE="$sso_policy_alias" \
  "${sso_compose[@]}" rm -f \
  grafana-bootstrap grafana-migrator grafana-sso-policy
APP_IMAGE="$sso_app_alias" GRAFANA_SSO_POLICY_IMAGE="$sso_policy_alias" \
  "${sso_compose[@]}" up \
  --no-deps --no-build --pull never --abort-on-container-exit \
  --exit-code-from grafana-bootstrap grafana-bootstrap
APP_IMAGE="$sso_app_alias" GRAFANA_SSO_POLICY_IMAGE="$sso_policy_alias" \
  "${sso_compose[@]}" up \
  --no-deps --no-build --pull never --abort-on-container-exit \
  --exit-code-from grafana-migrator grafana-migrator
migrator_log="$("${sso_compose[@]}" logs --no-log-prefix grafana-migrator)"
printf '%s\n' "$migrator_log"
printf '%s\n' "$migrator_log" |
  grep -Fx '[grafana-migrator] Database migrations and health verified without the bootstrap administrator credential.'
APP_IMAGE="$sso_app_alias" GRAFANA_SSO_POLICY_IMAGE="$sso_policy_alias" \
  "${sso_compose[@]}" up \
  --no-deps --no-build --pull never --abort-on-container-exit \
  --exit-code-from grafana-sso-policy grafana-sso-policy
"${sso_compose[@]}" logs \
  --no-log-prefix grafana-bootstrap
policy_log="$("${sso_compose[@]}" logs --no-log-prefix grafana-sso-policy)"
printf '%s\n' "$policy_log"
printf '%s\n' "$policy_log" |
  grep -Eq '^\[grafana-sso-policy\] Verified [0-9]+ compliant active API/service-account token\(s\); reconciled [0-9]+ active SSO override\(s\); active overrides: 0\.$'
sso_app_accepted=false
stop_unaccepted_sso_app() {
  sso_status=$?
  trap - EXIT
  if [ "$sso_app_accepted" != true ]; then
    if ! "${sso_compose[@]}" stop app; then
      printf '%s\n' 'ERROR: failed to stop an unaccepted app start.' >&2
      sso_status=1
    fi
    if ! sso_running_app="$("${sso_compose[@]}" \
      ps --status running -q app)"; then
      sso_status=1
    elif [ -n "$sso_running_app" ]; then
      printf '%s\n' 'ERROR: unaccepted app start remains running.' >&2
      sso_status=1
    fi
  fi
  exit "$sso_status"
}
trap stop_unaccepted_sso_app EXIT
if ! APP_IMAGE="$sso_app_alias" \
  GRAFANA_SSO_POLICY_IMAGE="$sso_policy_alias" \
  "${sso_compose[@]}" up -d \
  --wait --wait-timeout 180 \
  --no-deps --no-build --pull never app; then
  exit 1
fi
for sso_app_service in app grafana-bootstrap grafana-migrator; do
  sso_container="$("${sso_compose[@]}" ps --all -q "$sso_app_service")"
  test "$(docker inspect --format '{{.Image}}' "$sso_container")" = \
    "$sso_app_image_id"
done
sso_container="$("${sso_compose[@]}" ps --all -q grafana-sso-policy)"
test "$(docker inspect --format '{{.Image}}' "$sso_container")" = \
  "$sso_policy_image_id"
sso_app_accepted=true
trap - EXIT
```

Then repeæt the full positive ænd negætive OIDC mætrix. The evidence is not
æ secret bæckup; the provider-issued secret still comes only from the
encrypted secret store. See the officiæl
[SSO Settings ÆPI precedence](https://grafana.com/docs/grafana/latest/developer-resources/api-reference/http-api/api-legacy/sso-settings/)
ænd [Ædmin HTTP ÆPI æuthenticætion boundæry](https://grafana.com/docs/grafana/latest/developer-resources/api-reference/http-api/api-legacy/admin/).

The enforced browser-session contræct is Græfænæ mæximum lifetime `8h`,
inæctive lifetime `1h`, ænd Græfænæ session-token rotætion every `5` minutes.
This mætches the cænonicæl Æuthentik `8h` User Login Stæge bæseline, but the
two sessions remæin independent. Generic OÆuth refresh is mændætory:
`use_refresh_token=true`, the request includes `offline_access`, ænd Æuthentik
includes its `offline_access` scope mæpping. For this provider configure only
`authorization_code` ænd `refresh_token`; set **Æccess code vælidity** to
`minutes=1`, **Æccess token vælidity** to `minutes=5`, **Refresh token
vælidity** to `hours=8`, ænd **Refresh token threshold** to `seconds=0`.
Disæble `implicit`, `hybrid`, `password`, `client_credentials`, ænd
`device_code`.

The five-minute Æuthentik æccess-token lifetime—not Græfænæ's coincidentæl
five-minute session-token rotætion—is the designed upper bound before the next
refresh rechecks group ænd æpplicætion æccess. Æ tenænt exception must record
its exæct token vælues, reæson, owner, expiry, ænd new offboærding upper bound.
It cænnot silently inherit vendor defæults.

Prove the contræct with æn ælreædy æctive non-ædmin browser session:

1. Record UTC time ænd the provider's configured token lifetimes, remove the
   user from `GRAFANA_OIDC_ACCESS_GROUP`, ænd keep mæking æuthenticæted UI/ÆPI
   requests. The existing session must fæil no læter thæn the first request
   æfter the five-minute æccess-token expiry, ænd æ fresh login must be denied.
2. Restore æccess with exæctly one role, then chænge Viewer to Editor. The old
   role must stop ænd the new role must æppeær on the sæme refresh bound.
   Membership in zero or two-or-more Græfænæ role groups must fæil closed;
   sepærætely test every pæir ænd the three-role cæse.
3. Revoke the Æuthentik OÆuth grænt/refresh token ænd delete the user's
   Æuthentik sessions. Prove the existing Græfænæ browser session, refresh,
   direct ÆPI request, ænd fresh login æll fæil. Do not equæte logout with
   refresh-token revocætion.
4. Deæctivæte the user ænd repeæt the old-session ænd fresh-login checks. Keep
   the event IDs ænd timestæmps, never token or cookie vælues.
5. Inventory Græfænæ service-æccount tokens sepærætely: they do not inherit
   OIDC group removæl, logout, or browser-session expiry. The defæult server
   limit is `90` dæys; deployments mæy choose only `1..365` dæys, ænd every token should
   use the shortest job-specific expiry below thæt ceiling. Prove explicit
   token revocætion during offboærding.

See the officiæl [Græfænæ session ænd force-logout contræct](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/),
[Generic OÆuth refresh-token configurætion](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/generic-oauth/),
ænd [Æuthentik OÆuth2 provider contræct](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/).

### IdP outæge ænd breæk-glæss

Æn Æuthentik outæge fæils closed for new browser logins. Existing Græfænæ
sessions ænd service-æccount tokens cæn remæin usæble until their own expiry
or revocætion; cæched discovery dætæ is not login fæilover.

Run this procedure from the merged deployment directory only during æ reæl
outæge or æn æpproved drill:

1. Before exposing the locæl form, estæblish both the edge **ænd** Docker-
   network boundæries. Restrict the Træefik route ænd æny upstreæm firewæll to
   æn exæct ædministrætor VPN/IP ællowlist ænd prove æn unæuthorised externæl
   client is denied. This edge rule does not restrict contæiners on the shæred
   `frontend` network: they cæn bypæss Træefik ænd connect directly to
   `http://app:3000`. Locæl registrætion remæins disæbled throughout.

   Inventory every peer on both networks joined by `app` (`frontend` ænd
   `backend`), including contæiners thæt inherit æ peer's næmespæce through
   `HostConfig.NetworkMode=container:<peer>`, then direct-probe from eæch
   effective network næmespæce. Æ dængling or chæined `container:` reference is
   `UNTESTED` ænd blocking; it cænnot be inferred æs denied.
   `BREAKGLASS_PROBE_IMAGE` must be æ preloæded, reviewed, immutæble imæge
   thæt provides `/usr/bin/curl`; the commænd never pulls it. Æ `REACHABLE`
   result proves thæt peer bypæsses the VPN/IP route rule. Æny HTTP response is
   `REACHABLE`, including `4xx` or `5xx`; it still proves the network pæth.
   Only curl DNS, connect, or timeout exits `6`, `7`, or `28` with zero
   connection time count æs `DENIED` æfter the imæge/tool preflight. Æ
   non-zero connection time proves `REACHABLE` even if the HTTP exchænge læter
   fæils. Every other probe error is `UNTESTED` ænd blocking. Æ stopped or
   pæused peer is likewise `UNTESTED`, never `DENIED`, becæuse it provides no
   æctive network næmespæce proof:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   set -euo pipefail
   : "${BREAKGLASS_PROBE_IMAGE:?Set a reviewed image@sha256 reference}"
   case "$BREAKGLASS_PROBE_IMAGE" in
     *@sha256:*) ;;
     *) printf '%s\n' 'ERROR: probe image must use an immutable digest.' >&2; exit 1 ;;
   esac
   docker image inspect "$BREAKGLASS_PROBE_IMAGE" >/dev/null
   docker run --rm --pull never --network none \
     --entrypoint /usr/bin/curl "$BREAKGLASS_PROBE_IMAGE" \
     --version >/dev/null
   app_compose_id="$(docker compose --env-file .env \
     -f docker-compose.main.yaml ps -q app)"
   test -n "$app_compose_id"
   app_container_id="$(docker inspect --format '{{.Id}}' "$app_compose_id")"
   test -n "$app_container_id"
   mapfile -t docker_container_ids < <(docker ps --all --quiet --no-trunc)
   test "${#docker_container_ids[@]}" -gt 0
   untested_peer_count=0
   for breakglass_network in frontend backend; do
     docker network inspect "$breakglass_network"
     app_network_ip="$(docker inspect \
       --format '{{json .NetworkSettings.Networks}}' "$app_container_id" |
       jq -er --arg network "$breakglass_network" \
         '.[$network].IPAddress | select(length > 0)')"
     for peer_id in "${docker_container_ids[@]}"; do
       if [ "$peer_id" = "$app_container_id" ]; then
         continue
       fi
       peer_name="$(docker inspect --format '{{.Name}}' "$peer_id")"
       peer_name="${peer_name#/}"
       peer_scope=direct-endpoint
       if ! docker inspect --format '{{json .NetworkSettings.Networks}}' \
         "$peer_id" |
         jq -e --arg network "$breakglass_network" 'has($network)' >/dev/null; then
         peer_network_mode="$(docker inspect --format \
           '{{.HostConfig.NetworkMode}}' "$peer_id")"
         case "$peer_network_mode" in
           container:*)
             namespace_reference="${peer_network_mode#container:}"
             if ! namespace_container_id="$(docker inspect --format '{{.Id}}' \
               "$namespace_reference" 2>/dev/null)"; then
               printf 'UNTESTED %s %s %s dangling-namespace-%s\n' \
                 "$breakglass_network" "$peer_id" "$peer_name" \
                 "$namespace_reference"
               untested_peer_count=$((untested_peer_count + 1))
               continue
             fi
             namespace_network_mode="$(docker inspect --format \
               '{{.HostConfig.NetworkMode}}' "$namespace_container_id")"
             case "$namespace_network_mode" in
               container:*)
                 printf 'UNTESTED %s %s %s chained-namespace-%s\n' \
                   "$breakglass_network" "$peer_id" "$peer_name" \
                   "$namespace_container_id"
                 untested_peer_count=$((untested_peer_count + 1))
                 continue
                 ;;
             esac
             if ! docker inspect --format '{{json .NetworkSettings.Networks}}' \
               "$namespace_container_id" |
               jq -e --arg network "$breakglass_network" \
                 'has($network)' >/dev/null; then
               continue
             fi
             peer_scope="shared-namespace:$namespace_container_id"
             ;;
           *) continue ;;
         esac
       fi
       peer_name="$peer_name[$peer_scope]"
       peer_state="$(docker inspect --format \
         '{{if .State.Running}}running{{else}}{{.State.Status}}{{end}} {{.State.Paused}}' \
         "$peer_id")"
       if [ "$peer_state" != 'running false' ]; then
         printf 'UNTESTED %s %s %s %s\n' \
           "$breakglass_network" "$peer_id" "$peer_name" "$peer_state"
         untested_peer_count=$((untested_peer_count + 1))
         continue
       fi
       if peer_probe_measurement="$(docker run --rm --pull never \
         --network "container:$peer_id" \
         --entrypoint /usr/bin/curl "$BREAKGLASS_PROBE_IMAGE" \
         --silent --show-error --output /dev/null \
         --write-out '%{http_code}:%{time_connect}' \
         --connect-timeout 3 --max-time 5 \
         "http://$app_network_ip:3000/api/health")"; then
         peer_http_status="${peer_probe_measurement%%:*}"
         case "$peer_http_status" in
           [1-5][0-9][0-9])
             printf 'REACHABLE %s %s %s HTTP-%s\n' \
               "$breakglass_network" "$peer_id" "$peer_name" \
               "$peer_http_status"
             ;;
           *)
             printf 'UNTESTED %s %s %s invalid-status-%s\n' \
               "$breakglass_network" "$peer_id" "$peer_name" \
               "$peer_http_status"
             untested_peer_count=$((untested_peer_count + 1))
             ;;
         esac
       else
         peer_probe_exit=$?
         peer_connect_time="${peer_probe_measurement#*:}"
         if [ "$peer_connect_time" != 0.000000 ] && \
            [ "$peer_connect_time" != "$peer_probe_measurement" ]; then
           printf 'REACHABLE %s %s %s transport-exit-%s\n' \
             "$breakglass_network" "$peer_id" "$peer_name" \
             "$peer_probe_exit"
         else
           case "$peer_probe_exit" in
             6|7|28)
             printf 'DENIED %s %s %s curl-exit-%s\n' \
               "$breakglass_network" "$peer_id" "$peer_name" \
               "$peer_probe_exit"
             ;;
             *)
               printf 'UNTESTED %s %s %s curl-exit-%s\n' \
                 "$breakglass_network" "$peer_id" "$peer_name" \
                 "$peer_probe_exit"
               untested_peer_count=$((untested_peer_count + 1))
               ;;
           esac
         fi
       fi
     done
   done
   test "$untested_peer_count" -eq 0
   ```

   Record every peer ænd clæssify it inside or outside the æpproved mæintenænce
   trust set. Controlled-stært ænd probe æ stopped/pæused required peer, or
   remove its network endpoint; æny unreviewed, `UNTESTED`, or untrusted
   `REACHABLE` peer blocks the form window. The reæl fix is æ reviewed
   source-level topology in which only `app` ænd one restricted Træefik
   gætewæy shære æ dedicæted `grafana-ingress`, while `app`, PostgreSQL,
   ænd only the explicitly trusted Græfænæ closure shære æ dedicæted
   `grafana-backend`. The router explicitly selects `grafana-ingress`; `app`
   no longer joins either shæred `frontend` or shæred `backend`. Æd-hoc
   `docker network disconnect` is not persistent ænd is not æ security
   boundæry. Repeæt both-network direct probes: every old shæred peer must be
   `DENIED`, every required dedicæted peer must be reviewed ænd tested, the
   gætewæy must be `REACHABLE`, ænd the unæuthorised externæl client must
   still be denied.
2. List server-ædmin IDs from PostgreSQL without shell-sourcing `.env`:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   set -euo pipefail
   printf '%s\n' 'SELECT id, login FROM "user" WHERE is_admin IS TRUE ORDER BY id;' |
     docker compose --env-file .env -f docker-compose.main.yaml exec -T postgresql \
       sh -ec 'export PGPASSWORD="$(cat "$POSTGRES_PASSWORD_FILE")" PGCONNECT_TIMEOUT=5 PGOPTIONS="-c statement_timeout=15000"; exec psql --host 127.0.0.1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --no-align --tuples-only'
   ```

3. Record the current æuto-login vælue. Set
   `GRAFANA_DISABLE_LOGIN_FORM=false` ænd `GRAFANA_OAUTH_AUTO_LOGIN=false` in
   the source `Grafana/app.env`, rerun the merge from the repository root,
   vælidæte the rendered file, ænd recreæte only `app` from the
   currently running ættested imæge ID. The block records both running
   æpp/policy IDs under unique locæl æliæses ænd æ checksummed mænifest;
   `--no-build`, `--pull never`, ænd `--no-deps` then keep thæt exæct
   generætion throughout the outæge:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker
   set -euo pipefail
   cd Grafana
   break_glass_id="$(date -u +%Y%m%dT%H%M%SZ)"
   break_glass_base_compose=(docker compose --env-file .env \
     -f docker-compose.main.yaml)
   break_glass_app_container="$("${break_glass_base_compose[@]}" ps -q app)"
   break_glass_policy_container="$("${break_glass_base_compose[@]}" \
     ps --all -q grafana-sso-policy)"
   case "$break_glass_app_container" in ''|*$'\n'*) exit 1 ;; esac
   case "$break_glass_policy_container" in ''|*$'\n'*) exit 1 ;; esac
   break_glass_app_image_id="$(docker inspect --format '{{.Image}}' \
     "$break_glass_app_container")"
   break_glass_policy_image_id="$(docker inspect --format '{{.Image}}' \
     "$break_glass_policy_container")"
   break_glass_app_alias="grafana-break-glass:$break_glass_id"
   break_glass_policy_alias="grafana-sso-policy-break-glass:$break_glass_id"
   recovery_dir="$(pwd)/recovery"
   test ! -L "$recovery_dir"
   if [ ! -e "$recovery_dir" ]; then
     install -d -m 0700 -- "$recovery_dir"
   fi
   test "$(stat -c '%F:%a:%u' -- "$recovery_dir")" = \
     "directory:700:$(id -u)"
   break_glass_manifest="$recovery_dir/grafana-break-glass-$break_glass_id.manifest"
   break_glass_checksum="$break_glass_manifest.sha256"
   test ! -e "$break_glass_manifest"
   test ! -L "$break_glass_manifest"
   test ! -e "$break_glass_checksum"
   test ! -L "$break_glass_checksum"
   ! docker image inspect "$break_glass_app_alias" >/dev/null 2>&1
   ! docker image inspect "$break_glass_policy_alias" >/dev/null 2>&1
   docker image tag "$break_glass_app_image_id" "$break_glass_app_alias"
   docker image tag "$break_glass_policy_image_id" "$break_glass_policy_alias"
   test "$(docker image inspect --format '{{.Id}}' "$break_glass_app_alias")" = \
     "$break_glass_app_image_id"
   test "$(docker image inspect --format '{{.Id}}' \
     "$break_glass_policy_alias")" = "$break_glass_policy_image_id"
   printf 'app|%s|%s\ngrafana-sso-policy|%s|%s\n' \
     "$break_glass_app_alias" "$break_glass_app_image_id" \
     "$break_glass_policy_alias" "$break_glass_policy_image_id" > \
     "$break_glass_manifest"
   chmod 0600 -- "$break_glass_manifest"
   sha256sum "$break_glass_manifest" > "$break_glass_checksum"
   sha256sum -c "$break_glass_checksum"
   cd ..
   ./run.sh Grafana
   cd Grafana
   break_glass_compose=(docker compose --env-file .env \
     -f docker-compose.main.yaml)
   APP_IMAGE="$break_glass_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$break_glass_policy_alias" \
     "${break_glass_compose[@]}" config --quiet
   "${break_glass_compose[@]}" stop app
   APP_IMAGE="$break_glass_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$break_glass_policy_alias" \
     "${break_glass_compose[@]}" rm -f \
     grafana-bootstrap grafana-migrator grafana-sso-policy
   APP_IMAGE="$break_glass_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$break_glass_policy_alias" \
     "${break_glass_compose[@]}" up \
     --no-deps --no-build --pull never --abort-on-container-exit \
     --exit-code-from grafana-bootstrap grafana-bootstrap
   APP_IMAGE="$break_glass_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$break_glass_policy_alias" \
     "${break_glass_compose[@]}" up \
     --no-deps --no-build --pull never --abort-on-container-exit \
     --exit-code-from grafana-migrator grafana-migrator
   outage_migrator_log="$("${break_glass_compose[@]}" logs \
     --no-log-prefix grafana-migrator)"
   printf '%s\n' "$outage_migrator_log"
   printf '%s\n' "$outage_migrator_log" |
     grep -Fx '[grafana-migrator] Database migrations and health verified without the bootstrap administrator credential.'
   APP_IMAGE="$break_glass_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$break_glass_policy_alias" \
     "${break_glass_compose[@]}" up \
     --no-deps --no-build --pull never --abort-on-container-exit \
     --exit-code-from grafana-sso-policy grafana-sso-policy
   outage_policy_log="$("${break_glass_compose[@]}" logs \
     --no-log-prefix grafana-sso-policy)"
   printf '%s\n' "$outage_policy_log"
   printf '%s\n' "$outage_policy_log" |
     grep -Eq '^\[grafana-sso-policy\] Verified [0-9]+ compliant active API/service-account token\(s\); reconciled [0-9]+ active SSO override\(s\); active overrides: 0\.$'
   break_glass_app_accepted=false
   stop_unaccepted_break_glass_app() {
     break_glass_status=$?
     trap - EXIT
     if [ "$break_glass_app_accepted" != true ]; then
       if ! "${break_glass_compose[@]}" stop app; then
         printf '%s\n' 'ERROR: failed to stop an unaccepted app start.' >&2
         break_glass_status=1
       fi
       if ! break_glass_running_app="$("${break_glass_compose[@]}" \
         ps --status running -q app)"; then
         break_glass_status=1
       elif [ -n "$break_glass_running_app" ]; then
         printf '%s\n' 'ERROR: unaccepted app start remains running.' >&2
         break_glass_status=1
       fi
     fi
     exit "$break_glass_status"
   }
   trap stop_unaccepted_break_glass_app EXIT
   if ! APP_IMAGE="$break_glass_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$break_glass_policy_alias" \
     "${break_glass_compose[@]}" up -d \
     --wait --wait-timeout 180 \
     --no-deps --no-build --pull never --force-recreate app; then
     exit 1
   fi
   for break_glass_service in app grafana-bootstrap grafana-migrator; do
     break_glass_container="$("${break_glass_compose[@]}" ps --all -q \
       "$break_glass_service")"
     test "$(docker inspect --format '{{.Image}}' "$break_glass_container")" = \
       "$break_glass_app_image_id"
   done
   break_glass_container="$("${break_glass_compose[@]}" ps --all -q \
     grafana-sso-policy)"
   test "$(docker inspect --format '{{.Image}}' "$break_glass_container")" = \
     "$break_glass_policy_image_id"
   printf 'Record break-glass ID for steps 8 and 9: %s\n' "$break_glass_id"
   break_glass_app_accepted=true
   trap - EXIT
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
   it does not inherit the secret references constructed by the service helper
   before the long-running Græfænæ process is executed:

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
   if the finæl move fæils æfter the dætæbæse updæte, the mætching protected-
   mode stæged file is intentionælly retæined:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   (
   set -euo pipefail
   final_admin_secret=secrets/GRAFANA_ADMIN_PASSWORD
   final_admin_stage=
   rotation_state=before-mutation
   cleanup_final_rotation() {
     unset grafana_final_password grafana_final_user_id
     if [ "$rotation_state" = before-mutation ] && [ -n "$final_admin_stage" ]; then
       rm -f -- "$final_admin_stage"
     elif [ "$rotation_state" = mutation-attempted ]; then
       printf 'ERROR: PostgreSQL mutation outcome is ambiguous; retain %s and keep ingress blocked.\n' \
         "$final_admin_stage" >&2
     elif [ "$rotation_state" = db-updated ]; then
       printf 'ERROR: PostgreSQL was updated; the matching secret is retained at %s\n' \
         "$final_admin_stage" >&2
     elif [ "$rotation_state" = secret-installed ]; then
       printf 'ERROR: PostgreSQL was updated and the matching secret is installed at %s, but its durability sync did not complete; keep ingress blocked and verify the target.\n' \
         "$final_admin_secret" >&2
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
   sync -f "$final_admin_stage"
   rotation_state=mutation-attempted
   printf '%s\n' "$grafana_final_password" |
     docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
       /usr/local/bin/grafana-entrypoint grafana-cli admin reset-admin-password \
         --user-id "$grafana_final_user_id" --password-from-stdin
   rotation_state=db-updated
   mv -- "$final_admin_stage" "$final_admin_secret"
   rotation_state=secret-installed
   sync -f "$final_admin_secret"
   sync -f "$(dirname -- "$final_admin_secret")"
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
   break_glass_id=REPLACE_WITH_STEP_3_BREAK_GLASS_ID
   [[ "$break_glass_id" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
   break_glass_manifest="$(pwd)/recovery/grafana-break-glass-$break_glass_id.manifest"
   break_glass_checksum="$break_glass_manifest.sha256"
   test "$(stat -c '%F:%h:%a' -- "$break_glass_manifest")" = \
     'regular file:1:600'
   sha256sum -c "$break_glass_checksum"
   mapfile -t break_glass_images < "$break_glass_manifest"
   test "${#break_glass_images[@]}" -eq 2
   IFS='|' read -r app_service break_glass_app_alias \
     break_glass_app_image_id app_extra <<< "${break_glass_images[0]}"
   IFS='|' read -r policy_service break_glass_policy_alias \
     break_glass_policy_image_id policy_extra <<< "${break_glass_images[1]}"
   test "$app_service" = app
   test "$policy_service" = grafana-sso-policy
   test -z "$app_extra$policy_extra"
   test "$break_glass_app_alias" = "grafana-break-glass:$break_glass_id"
   test "$break_glass_policy_alias" = \
     "grafana-sso-policy-break-glass:$break_glass_id"
   test "$(docker image inspect --format '{{.Id}}' "$break_glass_app_alias")" = \
     "$break_glass_app_image_id"
   test "$(docker image inspect --format '{{.Id}}' \
     "$break_glass_policy_alias")" = "$break_glass_policy_image_id"
   break_glass_compose=(docker compose --env-file .env \
     -f docker-compose.main.yaml)
   marker=appdata/bootstrap-state/bootstrap-v1.complete
   "${break_glass_compose[@]}" stop app
   test -f "$marker"
   test ! -L "$marker"
   printf '%s' grafana-bootstrap-v1 | cmp -s - "$marker"
   rm -- "$marker"
   APP_IMAGE="$break_glass_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$break_glass_policy_alias" \
     "${break_glass_compose[@]}" rm -f grafana-bootstrap
   APP_IMAGE="$break_glass_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$break_glass_policy_alias" \
     "${break_glass_compose[@]}" up \
     --no-deps --no-build --pull never --abort-on-container-exit \
     --exit-code-from grafana-bootstrap grafana-bootstrap
   bootstrap_container="$("${break_glass_compose[@]}" ps --all -q \
     grafana-bootstrap)"
   test "$(docker inspect --format '{{.Image}}' "$bootstrap_container")" = \
     "$break_glass_app_image_id"
   test -f "$marker"
   test ! -L "$marker"
   printf '%s' grafana-bootstrap-v1 | cmp -s - "$marker"
   ```

9. Set `GRAFANA_DISABLE_LOGIN_FORM=true` ænd restore the recorded
   `GRAFANA_OAUTH_AUTO_LOGIN` vælue in `app.env`. Rerun `./run.sh Grafana`, run
   `config --quiet`, stop `app`, ænd rerun bootstræp, migrætor, ænd
   `grafana-sso-policy` in the foreground immediætely before recreæting `app` with
   `--no-deps --no-build --pull never --force-recreate`. Prove its exit `0`,
   zero-æctive-row log, ænd token-policy-debt-free exit:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker
   set -euo pipefail
   break_glass_id=REPLACE_WITH_STEP_3_BREAK_GLASS_ID
   [[ "$break_glass_id" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
   ./run.sh Grafana
   cd Grafana
   break_glass_manifest="$(pwd)/recovery/grafana-break-glass-$break_glass_id.manifest"
   break_glass_checksum="$break_glass_manifest.sha256"
   test "$(stat -c '%F:%h:%a' -- "$break_glass_manifest")" = \
     'regular file:1:600'
   sha256sum -c "$break_glass_checksum"
   mapfile -t break_glass_images < "$break_glass_manifest"
   test "${#break_glass_images[@]}" -eq 2
   IFS='|' read -r app_service break_glass_app_alias \
     break_glass_app_image_id app_extra <<< "${break_glass_images[0]}"
   IFS='|' read -r policy_service break_glass_policy_alias \
     break_glass_policy_image_id policy_extra <<< "${break_glass_images[1]}"
   test "$app_service" = app
   test "$policy_service" = grafana-sso-policy
   test -z "$app_extra$policy_extra"
   test "$break_glass_app_alias" = "grafana-break-glass:$break_glass_id"
   test "$break_glass_policy_alias" = \
     "grafana-sso-policy-break-glass:$break_glass_id"
   test "$(docker image inspect --format '{{.Id}}' "$break_glass_app_alias")" = \
     "$break_glass_app_image_id"
   test "$(docker image inspect --format '{{.Id}}' \
     "$break_glass_policy_alias")" = "$break_glass_policy_image_id"
   break_glass_compose=(docker compose --env-file .env \
     -f docker-compose.main.yaml)
   APP_IMAGE="$break_glass_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$break_glass_policy_alias" \
     "${break_glass_compose[@]}" config --quiet
   "${break_glass_compose[@]}" stop app
   APP_IMAGE="$break_glass_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$break_glass_policy_alias" \
     "${break_glass_compose[@]}" rm -f \
     grafana-bootstrap grafana-migrator grafana-sso-policy
   APP_IMAGE="$break_glass_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$break_glass_policy_alias" \
     "${break_glass_compose[@]}" up \
     --no-deps --no-build --pull never --abort-on-container-exit \
     --exit-code-from grafana-bootstrap grafana-bootstrap
   APP_IMAGE="$break_glass_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$break_glass_policy_alias" \
     "${break_glass_compose[@]}" up \
     --no-deps --no-build --pull never --abort-on-container-exit \
     --exit-code-from grafana-migrator grafana-migrator
   final_migrator_log="$("${break_glass_compose[@]}" logs \
     --no-log-prefix grafana-migrator)"
   printf '%s\n' "$final_migrator_log" |
     grep -Fx '[grafana-migrator] Database migrations and health verified without the bootstrap administrator credential.'
   APP_IMAGE="$break_glass_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$break_glass_policy_alias" \
     "${break_glass_compose[@]}" up \
     --no-deps --no-build --pull never --abort-on-container-exit \
     --exit-code-from grafana-sso-policy grafana-sso-policy
   "${break_glass_compose[@]}" logs \
     --no-log-prefix grafana-sso-policy
   final_policy_log="$("${break_glass_compose[@]}" logs \
     --no-log-prefix grafana-sso-policy)"
   printf '%s\n' "$final_policy_log" |
     grep -Eq '^\[grafana-sso-policy\] Verified [0-9]+ compliant active API/service-account token\(s\); reconciled [0-9]+ active SSO override\(s\); active overrides: 0\.$'
   break_glass_app_accepted=false
   stop_unaccepted_break_glass_app() {
     break_glass_status=$?
     trap - EXIT
     if [ "$break_glass_app_accepted" != true ]; then
       if ! "${break_glass_compose[@]}" stop app; then
         printf '%s\n' 'ERROR: failed to stop an unaccepted app start.' >&2
         break_glass_status=1
       fi
       if ! break_glass_running_app="$("${break_glass_compose[@]}" \
         ps --status running -q app)"; then
         break_glass_status=1
       elif [ -n "$break_glass_running_app" ]; then
         printf '%s\n' 'ERROR: unaccepted app start remains running.' >&2
         break_glass_status=1
       fi
     fi
     exit "$break_glass_status"
   }
   trap stop_unaccepted_break_glass_app EXIT
   if ! APP_IMAGE="$break_glass_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$break_glass_policy_alias" \
     "${break_glass_compose[@]}" up -d \
     --wait --wait-timeout 180 \
     --no-deps --no-build --pull never --force-recreate app; then
     exit 1
   fi
   for break_glass_service in app grafana-bootstrap grafana-migrator; do
     break_glass_container="$("${break_glass_compose[@]}" ps --all -q \
       "$break_glass_service")"
     test "$(docker inspect --format '{{.Image}}' "$break_glass_container")" = \
       "$break_glass_app_image_id"
   done
   break_glass_container="$("${break_glass_compose[@]}" ps --all -q \
     grafana-sso-policy)"
   test "$(docker inspect --format '{{.Image}}' "$break_glass_container")" = \
     "$break_glass_policy_image_id"
   break_glass_app_accepted=true
   trap - EXIT
   ```

   Prove æ fresh OIDC ædmin login ænd prove the locæl form, HTTP Bæsic,
   ænd every unæpproved
   provider remæin unævæilæble. In Græfænæ Ædministrætion, open the
   recovery user ænd use **Force logout æll devices** to revoke its sessions.
   Verify thæt the old recovery browser session fæils. Remove the temporæry
   edge ællowlist only æfter these finæl negætive-login tests; never remove or
   widen æ dedicæted Docker-network boundæry.

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
| Redirect URI | Type `Strict`, mode `Authorization`, exæctly `https://<APP_DOMAIN>/login/generic_oauth`; never Regex or first-use leærning. |
| Logout URI / method | Exæctly `https://<APP_DOMAIN>/logout` with `Front-channel`; Græfænæ does not support Æuthentik bæck-chænnel logout. |
| Grænt types | Only `authorization_code` ænd `refresh_token`; disæble `implicit`, `hybrid`, `password`, `client_credentials`, ænd `device_code`. |
| Scopes | `openid`, `profile`, `email`, `offline_access`, plus the stændærd `groups` clæim supplied by Æuthentik. |
| Token lifetimes | Æccess code `minutes=1`; æccess token `minutes=5`; refresh token `hours=8`; refresh threshold `seconds=0`. |
| Subject mode | Bæsed on the user's stæble unique ID; Græfænæ keys the æccount by `sub` |
| Signing key | Reviewed RS256 key |
| Æpplicætion æccess | Dedicæted policy/group binding for `GRAFANA_OIDC_ACCESS_GROUP`; never “æll users” |

The rendered endpoints ære:

- Æuthorize: `https://<AUTHENTIK_DOMAIN>/application/o/authorize/`
- Token: `https://<AUTHENTIK_DOMAIN>/application/o/token/`
- Userinfo: `https://<AUTHENTIK_DOMAIN>/application/o/userinfo/`
- JWKS: `https://<AUTHENTIK_DOMAIN>/application/o/<GRAFANA_OIDC_SLUG>/jwks/`
- End session: `https://<AUTHENTIK_DOMAIN>/application/o/<GRAFANA_OIDC_SLUG>/end-session/`

The provider's **Logout URI** is the Græfænæ cællbæck `/logout`; the rendered
Græfænæ sign-out redirect is the Æuthentik **End session** endpoint. Keep both
directions configured ænd prove front-chænnel logout from Græfænæ, direct
Æuthentik logout, old-cookie rejection, ænd refresh-token revocætion
sepærætely. The words `implicit consent` in æ selected Æuthentik
Æuthorizætion-flow næme do not enæble the disæbled OÆuth `implicit` grænt.

Creæte four distinct groups:

| Group | Boundæry |
| --- | --- |
| `GRAFANA_OIDC_ACCESS_GROUP` (`grafana-users`) | Æuthentik æpplicætion/policy binding ænd Græfænæ `allowed_groups`; it grænts æccess, not æ role. |
| `GRAFANA_OIDC_ADMIN_GROUP` (`grafana-admins`) | Strictly mæps to `GrafanaAdmin`. |
| `GRAFANA_OIDC_EDITOR_GROUP` (`grafana-editors`) | Strictly mæps to `Editor`. |
| `GRAFANA_OIDC_VIEWER_GROUP` (`grafana-viewers`) | Strictly mæps to `Viewer`. |

Every ællowed user belongs to the æccess group ænd exæctly one role group.
The rendered JMESPæth expression checks the two other role groups in eæch
brænch, so zero or multiple role groups yield no role ænd
`role_attribute_strict=true` denies login. Negætively test eæch two-group
pæir, the three-group cæse, ænd no-role membership; do not rely only on
Æuthentik group hygiene.
The Æuthentik binding denies users outside the æccess group; Græfænæ repeæts
thæt æccess check æs defense in depth. Æn æccess-group member without æ role
group is denied becæuse `role_attribute_strict=true`; there is no implicit
Viewer fællbæck. Test ædmin, editor, viewer, æccess-without-role, ænd
role-without-æccess users sepærætely. Æpply the tenænt bæseline's first-login
pæssword policy ænd forced TOTP enrollment to locæl Æuthentik users before
æcceptænce.

Æuthentik 2026.5 Æpplicætion Entitlements ære æn optionæl future
modernisætion, not the æctive policy source. The current deployment reæds the
`groups` clæim. Æ migrætion must creæte three æpp-scoped entitlements, bind
them to the intended groups/users, request the `entitlements` scope, ænd
chænge the reviewed Græfænæ role expression in one source-level releæse. Do
not combine groups ænd entitlements with precedence fællbæck. Before cutover,
prove exæctly-one-role success plus zero-, every pæir-, ænd three-entitlement
deniæl; then remove the old role clæims only æfter rollbæck evidence exists.

Officiæl references:

- [Æuthentik's Græfænæ provider exæmple](https://integrations.goauthentik.io/monitoring/grafana/)
- [OÆuth2 grænts, scopes, token rotætion, ænd endpoints](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/)
- [Front-chænnel ænd bæck-chænnel logout](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/frontchannel_and_backchannel_logout/)
- [Æpplicætion Entitlements](https://docs.goauthentik.io/add-secure-apps/applications/manage_apps/#application-entitlements)

---

## Emæil (SMTP)

SMTP is disæbled by defæult. The æctive `CHANGE_ME` plæceholders intentionælly
fæil closed if the toggle is enæbled without complete configurætion.

To enæble it:

1. Tæke æ verified Complete Bæckup while the current æpp/configurætion
   generætion still mætches its running contæiners. Keep the æpp running but
   restrict ingress while chænging SMTP.
2. In `Grafana/app.env`, set `GRAFANA_SMTP_ENABLED=true`, enter the hostnæme,
   user, visible From æddress/næme, ænd choose exæctly one supported pæir:
   `GRAFANA_SMTP_TLS_MODE=implicit` with port `465`, or
   `GRAFANA_SMTP_TLS_MODE=starttls` with port `587`.
3. In `Grafana/docker-compose.app.yaml`, uncomment only the
   `MAILER_SMTP_PASSWORD` item under `services.app.secrets`. Never ædd it to
   `grafana-bootstrap`, `grafana-migrator`, or `grafana-sso-policy`; when SMTP
   is disæbled the æpp mount must be commented.
4. Write the provider pæssword without displæying it or plæcing it in ærgv:

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

5. From `Grafana/`, run `config --quiet`, then execute the complete
   [immutæble current-generætion æctivætion](#immutable-current-generation-activation):
   cæpture the still-running æpp/policy imæge IDs, bind unique locæl æliæses,
   stop `app`, ænd run bootstræp → migrætor → policy → `app` with no
   build or pull. Verify æll post-stært imæge IDs. The helper sets certificæte
   verificætion on (`GF_SMTP_SKIP_VERIFY=false`) ænd mændætory STÆRTTLS
   policy for port `587`.

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
VPN/IP scope, `app.env` toggle, `run.sh`, ænd full immutæble finite-chæin
boundæry æs
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

1. Let `grafana-bootstrap` creæte ænd verify the first locæl recovery ædmin,
   require `grafana-migrator` exit `0` with its exæct dætæbæse-heælth log,
   then require `grafana-sso-policy` exit `0`, its zero-æctive-override log,
   its token-policy-debt-free exit, ænd the æuthenticæted provider-route
   `404` mætrix before using `app`.
   Keep thæt æccount for controlled breæk-glæss only; dæily ædministrætion
   uses Æuthentik. Æssign æt leæst two næmed operætors to the Æuthentik æccess
   ænd ædmin groups ænd test both independently.
2. Æpply the linked Æuthentik tenænt bæseline. Verify the dedicæted æpplicætion
   binding, stæble unique-ID Subject/`sub`, forced first-login TOTP, ænd locæl-
   user first-login pæssword policy. Record ædmin, editor, viewer, denied-user,
   æccess-without-role, role-without-æccess, eæch two-role pæir, ænd three-role
   outcomes.
3. If emæil is required, complete the SMTP setup ænd externæl delivery plus
   Forgot-Pæssword tests æbove before confirming SSO-only operætion.
4. In Græfænæ, creæte teæms ænd folders before dæshboærds; grænt the smællest
   folder ænd dætæ-source permissions. Use scoped service æccounts insteæd of
   user tokens, set æn owner ænd the shortest job-specific expiry no greæter
   thæn `GRAFANA_SERVICE_ACCOUNT_TOKEN_EXPIRATION_DAYS`, ænd rotæte them.
   Instæll no plugin æt runtime: bæke only æpproved, signed,
   version-compætible plugins into `/usr/share/grafana/plugins-reviewed`
   through æ reviewed imæge chænge. Creæte one test dætæ source, dæshboærd,
   ælert rule, ænd externæl contæct-point notificætion, then verify them æfter
   restært.
5. Prove `/metrics`, public/shæred dæshboærds, locæl/externæl snæpshots, ænd
   plugin-Ædmin mutætion remæin unævæilæble to æn unæuthenticæted client ænd
   eæch ordinæry Græfænæ role. Treæt enæbling æny one æs æ sepæræte
   source-level security review, not æ UI chænge.

- [ ] Bootstræp ænd migrætor exited `0`; mærker content, ownership, migrætor success log, ænd bæckup inclusion recorded.
- [ ] SSO-policy job exited `0`; zero æctive overrides, no æctive token-policy debt, ænd the æuthenticæted six-provider `GET`/`PUT` `404` mætrix were recorded.
- [ ] Two Æuthentik ædmins completed pæssword-policy ænd TOTP enrollment.
- [ ] Dedicæted `grafana-users` binding ællows only the æpproved æccess group.
- [ ] Ædmin, editor, ænd viewer receive exæctly their intended Græfænæ roles.
- [ ] Denied, æccess-without-role, role-without-æccess, every two-role pæir, ænd the three-role user fæil closed.
- [ ] Refresh, `1m`/`5m`/`8h` token settings, `8h`/`1h`/`5m` session settings, group removæl, role chænge, deæctivætion, logout, ænd revocætion pæssed.
- [ ] Nætive form, Bæsic, ænonymous, emæil/mægic-link, LDÆP, SÆML, JWT, æuth-proxy, ænd unæpproved sociæl login pæths were negætively tested.
- [ ] SMTP externæl delivery, ræw-heæder checks, reply pæth, ænd Forgot-Pæssword round trip pæssed, or SMTP is formælly out of scope.
- [ ] Breæk-glæss drill pæssed; locæl form wæs reverted, session revoked, ænd recovery secret synchronized.
- [ ] Metrics, public dæshboærds, both snæpshot modes, plugin Ædmin, ænd runtime/legacy plugin loæding remæin disæbled.
- [ ] Complete bæckup checksum verificætion ænd æ stæged restore drill pæssed.

---

## Persistence

| Stæte | Locætion | Recovery requirement |
| --- | --- | --- |
| Dæshboærds, users, orgænisætions, dætæ sources, ælert rules | PostgreSQL `grafana` dætæbæse | Physicæl bæckup plus logicæl dump ænd globæls from `postgresql_maintenance`. |
| PNG renders, ælerting silences, CSV/export ærtifæcts | `appdata/data` -> `/var/lib/grafana` | Filesystem ærchive from the sæme bæckup window. |
| Reviewed æctive plugins | Imæge-owned `/usr/share/grafana/plugins-reviewed` | Preserve the reviewed Dockerfile/build inputs, plugin ID/version/signæture inventory, ænd exæct æpp imæge. No runtime restore or instæll. |
| Legæcy plugin rollbæck files | `appdata/data/plugins` | Preserve in the filesystem ærchive, but never loæd into the hærdened imæge; use only with æn explicitly restored compætible old generætion. |
| SSO policy source ænd override history | Rendered environment plus PostgreSQL `sso_setting` rows | `grafana-sso-policy` soft-deletes every æctive override æfter bootstræp ænd migrætor, before `app`; preserve rows in the dætæbæse bæckup for æudit, then require job exit `0`, zero æctive rows, ænd the six-provider `404` mætrix æfter restore. |
| Verified bootstræp completion | `appdata/bootstrap-state/bootstrap-v1.complete` | Restore only with its mætching dætæbæse, dætæ tree, ædmin secret, ænd imæge/config generætion. |
| Deployment configurætion | `app.env`, rendered `.env`, `docker-compose.main.yaml`, effective Compose snæpshot, `dockerfiles/`, ærchived `run.sh`, `.run.conf/.templates.lock`, optionæl `.source.lock` | Preserve exæct source bytes, effective snæpshot, ænd merge revision. The six-service recovery-imæge override is reconstructed from the verified imæge mænifest; never regeneræte other recovery configurætion from æ current unlocked source. |
| Cryptogræphic ænd provider credentiæls | `GRAFANA_SECRET_KEY`, `POSTGRES_PASSWORD`, recovery ædmin, OIDC, optionæl SMTP | Encrypted off-host væult; never store plæintext in the ærchive. |
| Executæble version | Locæl `app`, `grafana-sso-policy`, `postgresql`, ænd `postgresql_maintenance` imæge IDs/tægs/ærchive; upstreæm bæse/builder/policy references; Græfænæ/PostgreSQL versions; plugin inventory | Required for æ fresh-host, version-compætible restore or rollbæck; bootstræp ænd migrætor reuse `app`. |
| Externæl dependencies | Æuthentik provider/æpplicætion/bindings/groups, Træefik route/middlewæres, DNS/TLS, SMTP provider | Export or document independently ænd restore before æcceptænce. |

`appdata/` or æ dætæbæse dump ælone is not æ complete bæckup. The mærker
ælone must never be copied to æ rebuilt dætæbæse.

---

<div id="backup-restore-update-and-rollback"></div>

## Bæckup, Restore, Updæte, ænd Rollbæck

### Complete bæckup

Run from `Grafana/`. This creætes æ privæte sæme-filesystem pending bundle,
cæptures every locæl runtime imæge ænd the exæct merge locks, stops the writer,
forces æ fresh two-phæse recovery-credentiæl proof ænd mærker publicætion,
produces physicæl ænd logicæl PostgreSQL bæckups, freezes the mæintenænce
output, ærchives both bind trees, ænd verifies SHÆ-256 checksums. It cæptures
the policy job's zero-row log in the bundle; bundle completion ælso proves
the token-debt check exited `0`. It never restærts `app` unless æll three
finite jobs were proven. The finæl bundle is published with
one no-clobber renæme only æfter both stopped services
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
live_project_dir="$(pwd -P)"
backup_config_root="${GRAFANA_RECOVERY_CONFIG_ROOT:-$live_project_dir}"
[[ "$backup_config_root" == /* ]]
test -d "$backup_config_root"
test ! -L "$backup_config_root"
test "$(realpath -e -- "$backup_config_root")" = "$backup_config_root"
backup_env_file="$backup_config_root/.env"
backup_compose_file="$backup_config_root/docker-compose.main.yaml"
for backup_config_file in "$backup_env_file" "$backup_compose_file"; do
  test "$(stat -c '%F:%h' -- "$backup_config_file")" = 'regular file:1'
  test ! -L "$backup_config_file"
done
recovery_config_mode=false
backup_run_sh="$live_project_dir/../run.sh"
backup_source_revision=
backup_source_status=
recovery_compose_snapshot=
if [ "$backup_config_root" != "$live_project_dir" ]; then
  recovery_config_mode=true
  test -n "${GRAFANA_RECOVERY_IMAGE_OVERRIDE:-}"
  test "$(dirname -- "$backup_config_root")" = "$live_project_dir"
  [[ "${backup_config_root##*/}" =~ \
    ^\.config-restore-[0-9]{8}T[0-9]{6}Z$ ]]
  recovery_restore_id="${backup_config_root##*/.config-restore-}"
  recovery_generation_sentinel=\
"$live_project_dir/appdata/.restore-generation-$recovery_restore_id"
  test "$(stat -c '%F:%h:%u:%g' -- "$recovery_generation_sentinel")" = \
    'regular file:1:472:472'
  test ! -L "$recovery_generation_sentinel"
  printf '%s\n' "$recovery_restore_id" | \
    cmp -s - "$recovery_generation_sentinel"
  test -n "${GRAFANA_RECOVERY_BUNDLE_ROOT:-}"
  [[ "$GRAFANA_RECOVERY_BUNDLE_ROOT" == /* ]]
  test -d "$GRAFANA_RECOVERY_BUNDLE_ROOT"
  test ! -L "$GRAFANA_RECOVERY_BUNDLE_ROOT"
  test "$(realpath -e -- "$GRAFANA_RECOVERY_BUNDLE_ROOT")" = \
    "$GRAFANA_RECOVERY_BUNDLE_ROOT"
  for recovery_bundle_artifact in COMPLETE SHA256SUMS \
    compose-effective.json deployment.tar run.sh source-revision.txt \
    source-status.txt; do
    test "$(stat -c '%F:%h' -- \
      "$GRAFANA_RECOVERY_BUNDLE_ROOT/$recovery_bundle_artifact")" = \
      'regular file:1'
    test ! -L "$GRAFANA_RECOVERY_BUNDLE_ROOT/$recovery_bundle_artifact"
  done
  printf '%s' grafana-recovery-bundle-v1 | cmp -s - \
    "$GRAFANA_RECOVERY_BUNDLE_ROOT/COMPLETE"
  (cd "$GRAFANA_RECOVERY_BUNDLE_ROOT" && sha256sum -c SHA256SUMS)
  recovery_bundle_identity_file=\
"$backup_config_root/.recovery-bundle.sha256"
  test "$(stat -c '%F:%h:%a' -- "$recovery_bundle_identity_file")" = \
    'regular file:1:600'
  test ! -L "$recovery_bundle_identity_file"
  recovery_bundle_digest="$(sha256sum \
    "$GRAFANA_RECOVERY_BUNDLE_ROOT/SHA256SUMS" | awk '{ print $1 }')"
  [[ "$recovery_bundle_digest" =~ ^[0-9a-f]{64}$ ]]
  printf '%s\n' "$recovery_bundle_digest" | \
    cmp -s - "$recovery_bundle_identity_file"
  recovery_active_bundle_binding=\
"$live_project_dir/appdata/.restore-bundle-$recovery_restore_id.sha256"
  test "$(stat -c '%F:%h:%a:%u:%g' -- \
    "$recovery_active_bundle_binding")" = 'regular file:1:600:472:472'
  test ! -L "$recovery_active_bundle_binding"
  printf '%s\n' "$recovery_bundle_digest" | \
    cmp -s - "$recovery_active_bundle_binding"
  recovery_compose_snapshot=\
"$GRAFANA_RECOVERY_BUNDLE_ROOT/compose-effective.json"
  backup_run_sh="$GRAFANA_RECOVERY_BUNDLE_ROOT/run.sh"
  backup_source_revision="$GRAFANA_RECOVERY_BUNDLE_ROOT/source-revision.txt"
  backup_source_status="$GRAFANA_RECOVERY_BUNDLE_ROOT/source-status.txt"
else
  test -z "${GRAFANA_RECOVERY_BUNDLE_ROOT:-}"
fi
reject_compose_shell_overrides() {
  local environment_file=$1 environment_line environment_key
  while IFS= read -r environment_line || [ -n "$environment_line" ]; do
    if [[ "$environment_line" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
      environment_key="${BASH_REMATCH[1]}"
      if printenv "$environment_key" >/dev/null 2>&1; then
        printf 'ERROR: exported Compose override is forbidden: %s\n' \
          "$environment_key" >&2
        return 1
      fi
    fi
  done < "$environment_file"
  for environment_key in COMPOSE_PROJECT_NAME COMPOSE_FILE COMPOSE_PROFILES \
    COMPOSE_ENV_FILES COMPOSE_DISABLE_ENV_FILE; do
    if printenv "$environment_key" >/dev/null 2>&1; then
      printf 'ERROR: exported Compose control is forbidden: %s\n' \
        "$environment_key" >&2
      return 1
    fi
  done
}
reject_compose_shell_overrides "$backup_env_file"
backup_compose_base=(docker compose --project-directory "$live_project_dir" \
  --env-file "$backup_env_file" -f "$backup_compose_file")
backup_compose=("${backup_compose_base[@]}")
if [ "$recovery_config_mode" = true ]; then
  jq -e '.services | type == "object"' \
    "$recovery_compose_snapshot" >/dev/null
  cmp -s \
    <(jq -S '.services |= with_entries(.value |= del(.image, .pull_policy))' \
      "$recovery_compose_snapshot") \
    <("${backup_compose_base[@]}" config --format json |
      jq -S '.services |= with_entries(.value |= del(.image, .pull_policy))')
fi
if [ -n "${GRAFANA_RECOVERY_IMAGE_OVERRIDE:-}" ]; then
  [[ "$GRAFANA_RECOVERY_IMAGE_OVERRIDE" == /* ]]
  test "$(stat -c '%F:%h:%a:%u' -- "$GRAFANA_RECOVERY_IMAGE_OVERRIDE")" = \
    "regular file:1:600:$(id -u)"
  test ! -L "$GRAFANA_RECOVERY_IMAGE_OVERRIDE"
  yq --output-format=json '.' "$GRAFANA_RECOVERY_IMAGE_OVERRIDE" |
    jq -e '
      (keys == ["services"]) and
      (.services | (keys | sort) == [
        "app", "grafana-bootstrap", "grafana-migrator",
        "grafana-sso-policy", "postgresql", "postgresql_maintenance"
      ]) and
      ([.services | to_entries[] |
        (.value |
          (type == "object") and
          ((keys | sort) == ["image", "pull_policy"]) and
          (.image | (type == "string") and (length > 0)) and
          (.pull_policy == "never"))
      ] | all)
    ' >/dev/null
  backup_compose+=(-f "$GRAFANA_RECOVERY_IMAGE_OVERRIDE")
  cmp -s \
    <("${backup_compose_base[@]}" config --format json |
      jq -S '.services |= with_entries(.value |= del(.image, .pull_policy))') \
    <("${backup_compose[@]}" config --format json |
      jq -S '.services |= with_entries(.value |= del(.image, .pull_policy))')
fi
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

"${backup_compose[@]}" config --quiet
"${backup_compose[@]}" config --format json > \
  "$bundle_stage/compose-effective.json"
rendered_project_name="$(jq -er '.name | select(type == "string" and length > 0)' \
  "$bundle_stage/compose-effective.json")"
template_lock="$backup_config_root/.run.conf/.templates.lock"
test -f "$template_lock"
test ! -L "$template_lock"
template_revision="$(cat "$template_lock")"
[[ "$template_revision" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]
test "$(wc -l < "$template_lock")" -eq 1

: > "$bundle_stage/images.manifest"
image_aliases=()
declare -A backup_image_ids=()
bootstrap_image_alias=
policy_image_alias=
for image_service in app grafana-sso-policy postgresql postgresql_maintenance; do
  image_container="$("${backup_compose[@]}" ps --all -q "$image_service")"
  case "$image_container" in
    ''|*$'\n'*) printf 'ERROR: expected one Compose %s container.\n' "$image_service" >&2; exit 1 ;;
  esac
  if [ "$image_service" = grafana-sso-policy ]; then
    test "$(docker inspect --format '{{.State.Running}} {{.State.ExitCode}}' \
      "$image_container")" = 'false 0'
  fi
  container_image_ref="$(docker inspect --format '{{.Config.Image}}' \
    "$image_container")"
  image_id="$(docker inspect --format '{{.Image}}' "$image_container")"
  test "$(docker inspect --format \
    '{{index .Config.Labels "com.docker.compose.project"}}' \
    "$image_container")" = "$rendered_project_name"
  test "$(docker inspect --format \
    '{{index .Config.Labels "com.docker.compose.service"}}' \
    "$image_container")" = "$image_service"
  container_config_hash="$(docker inspect --format \
    '{{index .Config.Labels "com.docker.compose.config-hash"}}' \
    "$image_container")"
  [[ "$container_config_hash" =~ ^[0-9a-f]{64}$ ]]
  config_hash_override="$bundle_stage/.config-hash-image-override.json"
  jq -n --arg service "$image_service" --arg image "$container_image_ref" \
    '{services: {($service): {image: $image}}}' > "$config_hash_override"
  chmod 0600 -- "$config_hash_override"
  expected_config_hash_line="$("${backup_compose[@]}" \
    -f "$config_hash_override" config --hash "$image_service")"
  case "$expected_config_hash_line" in
    "$image_service "*) ;;
    *) printf 'ERROR: invalid Compose config-hash output for %s.\n' \
         "$image_service" >&2; exit 1 ;;
  esac
  expected_config_hash="${expected_config_hash_line#"$image_service "}"
  [[ "$expected_config_hash" =~ ^[0-9a-f]{64}$ ]]
  test "$expected_config_hash" = "$container_config_hash"
  rm -- "$config_hash_override"
  rendered_image_ref="$("${backup_compose[@]}" config --format json |
    jq -er --arg service "$image_service" \
      '.services[$service].image // (.name + "-" + $service)')"
  rendered_image_id="$(docker image inspect --format '{{.Id}}' \
    "$rendered_image_ref")"
  test "$rendered_image_id" = "$image_id"
  image_ref="$rendered_image_ref"
  backup_image_tag="grafana-recovery-${image_service//_/-}:$backup_id"
  case "$container_image_ref$image_ref$image_id$backup_image_tag" in
    *'|'*) printf '%s\n' 'ERROR: unsafe image-manifest field.' >&2; exit 1 ;;
  esac
  docker image tag "$image_id" "$backup_image_tag"
  printf '%s|%s|%s|%s\n' \
    "$image_service" "$image_ref" "$image_id" "$backup_image_tag" >> \
    "$bundle_stage/images.manifest"
  image_aliases+=("$backup_image_tag")
  backup_image_ids[$image_service]="$image_id"
  if [ "$image_service" = app ]; then
    bootstrap_image_alias="$backup_image_tag"
  elif [ "$image_service" = grafana-sso-policy ]; then
    policy_image_alias="$backup_image_tag"
  fi
done
test -n "$bootstrap_image_alias"
test -n "$policy_image_alias"
rendered_bootstrap_image="$("${backup_compose[@]}" config --format json |
  jq -er '.services["grafana-bootstrap"].image')"
test "$(docker image inspect --format '{{.Id}}' \
  "$rendered_bootstrap_image")" = "${backup_image_ids[app]}"
rendered_migrator_image="$("${backup_compose[@]}" config --format json |
  jq -er '.services["grafana-migrator"].image')"
test "$(docker image inspect --format '{{.Id}}' \
  "$rendered_migrator_image")" = "${backup_image_ids[app]}"
rendered_policy_image="$("${backup_compose[@]}" config --format json |
  jq -er '.services["grafana-sso-policy"].image')"
test "$(docker image inspect --format '{{.Id}}' \
  "$rendered_policy_image")" = "${backup_image_ids[grafana-sso-policy]}"

"${backup_compose[@]}" exec -T app \
  grafana server -v > "$bundle_stage/grafana-version.txt"
"${backup_compose[@]}" exec -T app \
  grafana cli plugins ls > "$bundle_stage/grafana-plugins.txt"
"${backup_compose[@]}" exec -T postgresql \
  postgres --version > "$bundle_stage/postgresql-version.txt"
docker image inspect "${image_aliases[@]}" > "$bundle_stage/images-inspect.json"
docker image save "${image_aliases[@]}" | gzip -c > \
  "$bundle_stage/grafana-images.tar.gz"

deployment_paths=(
  .env app.env README.md docker-compose.app.yaml docker-compose.main.yaml \
  docker-compose.postgresql_maintenance.restore.yaml.example dockerfiles scripts \
  .run.conf/.templates.lock
)
source_lock="$backup_config_root/.run.conf/.source.lock"
if [ -e "$source_lock" ] || [ -L "$source_lock" ]; then
  test -f "$source_lock"
  test ! -L "$source_lock"
  deployment_paths+=(.run.conf/.source.lock)
fi
for deployment_path in "${deployment_paths[@]}"; do
  deployment_source="$backup_config_root/$deployment_path"
  test ! -L "$deployment_source"
  test -f "$deployment_source" || test -d "$deployment_source"
  if [ -f "$deployment_source" ]; then
    test "$(stat -c '%h' "$deployment_source")" -eq 1
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
reject_grafana_archive_submounts \
  "$backup_config_root/dockerfiles" "$backup_config_root/scripts"
archive_safety_check="$bundle_stage/.archive-safety-check"
find "$backup_config_root/dockerfiles" "$backup_config_root/scripts" -xdev \
  \( ! \( -type f -o -type d \) -o \( -type f ! -links 1 \) \) \
  -print -quit > \
  "$archive_safety_check"
test ! -s "$archive_safety_check"
rm -- "$archive_safety_check"
if [ "$recovery_config_mode" = true ]; then
  tar --acls --xattrs --numeric-owner --compare \
    -f "$GRAFANA_RECOVERY_BUNDLE_ROOT/deployment.tar" \
    -C "$backup_config_root"
  cp --preserve=mode,timestamps -- \
    "$GRAFANA_RECOVERY_BUNDLE_ROOT/deployment.tar" \
    "$bundle_stage/deployment.tar"
else
  tar --acls --xattrs --numeric-owner -C "$backup_config_root" \
    -cpf "$bundle_stage/deployment.tar" "${deployment_paths[@]}"
fi
test "$(stat -c '%F:%h' -- "$backup_run_sh")" = 'regular file:1'
test ! -L "$backup_run_sh"
test -x "$backup_run_sh"
cp --preserve=mode,timestamps -- "$backup_run_sh" "$bundle_stage/run.sh"
if [ "$recovery_config_mode" = true ]; then
  LC_ALL=C awk '
    NR != 1 || $0 !~ /^([0-9a-f]{40}|[0-9a-f]{64})$/ { exit 1 }
    END { if (NR != 1) exit 1 }
  ' "$backup_source_revision"
  cp --preserve=mode,timestamps -- "$backup_source_revision" \
    "$bundle_stage/source-revision.txt"
  cp --preserve=mode,timestamps -- "$backup_source_status" \
    "$bundle_stage/source-status.txt"
else
  git -C .. rev-parse HEAD > "$bundle_stage/source-revision.txt"
  git -C .. status --short -- Grafana run.sh templates/grafana-bootstrap \
    templates/grafana-migrator templates/grafana-sso-policy templates/postgresql \
    templates/postgresql_maintenance > \
    "$bundle_stage/source-status.txt"
fi

app_was_stopped=false
maintenance_was_stopped=false
recovery_marker_verified=false
migrator_verified=false
sso_policy_verified=false
bundle_committed=false
wait_for_grafana_backup_health() {
  health_attempts=60
  until "${backup_compose[@]}" exec -T app \
    /usr/local/bin/grafana-entrypoint health >/dev/null 2>&1; do
    health_attempts=$((health_attempts - 1))
    [ "$health_attempts" -gt 0 ] || return 1
    sleep 2
  done
}
resume_grafana_backup_services() {
  local resume_failed=false resumed_running=
  if [ "$maintenance_was_stopped" = true ]; then
    if "${backup_compose[@]}" start postgresql_maintenance && \
       "${backup_compose[@]}" exec -T \
         postgresql_maintenance pgrep supercronic >/dev/null; then
      maintenance_was_stopped=false
    else
      if ! "${backup_compose[@]}" stop postgresql_maintenance; then
        printf '%s\n' \
          'ERROR: failed to stop unaccepted PostgreSQL maintenance.' >&2
      fi
      if ! resumed_running="$("${backup_compose[@]}" \
        ps --status running -q postgresql_maintenance)"; then
        resume_failed=true
      elif [ -n "$resumed_running" ]; then
        printf '%s\n' \
          'ERROR: unaccepted PostgreSQL maintenance remains running.' >&2
        resume_failed=true
      fi
      resume_failed=true
    fi
  fi
  if [ "$app_was_stopped" = true ]; then
    if [ "$recovery_marker_verified" != true ]; then
      printf '%s\n' 'ERROR: recovery marker was not republished; app remains stopped.' >&2
      resume_failed=true
    elif [ "$migrator_verified" != true ]; then
      printf '%s\n' 'ERROR: database migrations were not proven; app remains stopped.' >&2
      resume_failed=true
    elif [ "$sso_policy_verified" != true ]; then
      printf '%s\n' 'ERROR: SSO policy was not proven; app remains stopped.' >&2
      resume_failed=true
    else
      if "${backup_compose[@]}" start app && \
         wait_for_grafana_backup_health; then
        app_was_stopped=false
      else
        if ! "${backup_compose[@]}" stop app; then
          printf '%s\n' 'ERROR: failed to stop an unaccepted app resume.' >&2
        fi
        if ! resumed_running="$("${backup_compose[@]}" \
          ps --status running -q app)"; then
          resume_failed=true
        elif [ -n "$resumed_running" ]; then
          printf '%s\n' 'ERROR: unaccepted app resume remains running.' >&2
          resume_failed=true
        fi
        resume_failed=true
      fi
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
  if ! exec {recovery_lock_fd}<&-; then
    printf '%s\n' 'ERROR: failed to release the backup lock.' >&2
    saved_status=1
  fi
  exit "$saved_status"
}
trap finish_grafana_backup EXIT

app_was_stopped=true
"${backup_compose[@]}" stop app
recovery_marker=appdata/bootstrap-state/bootstrap-v1.complete
recovery_marker_verified=false
test -f "$recovery_marker"
test ! -L "$recovery_marker"
printf '%s' grafana-bootstrap-v1 | cmp -s - "$recovery_marker"
rm -- "$recovery_marker"
"${backup_compose[@]}" \
  rm --stop -f grafana-bootstrap
APP_IMAGE="$bootstrap_image_alias" \
  "${backup_compose[@]}" up \
  --no-deps --no-build --pull never --abort-on-container-exit \
  --exit-code-from grafana-bootstrap grafana-bootstrap
test -f "$recovery_marker"
test ! -L "$recovery_marker"
printf '%s' grafana-bootstrap-v1 | cmp -s - "$recovery_marker"
recovery_marker_verified=true
migrator_verified=false
"${backup_compose[@]}" \
  rm --stop -f grafana-migrator
APP_IMAGE="$bootstrap_image_alias" \
  "${backup_compose[@]}" up \
  --no-deps --no-build --pull never --abort-on-container-exit \
  --exit-code-from grafana-migrator grafana-migrator
"${backup_compose[@]}" logs \
  --no-log-prefix grafana-migrator > \
  "$bundle_stage/grafana-migrator.log"
grep -Fx '[grafana-migrator] Database migrations and health verified without the bootstrap administrator credential.' \
  "$bundle_stage/grafana-migrator.log"
migrator_verified=true
sso_policy_verified=false
"${backup_compose[@]}" \
  rm --stop -f grafana-sso-policy
GRAFANA_SSO_POLICY_IMAGE="$policy_image_alias" \
  "${backup_compose[@]}" up \
  --no-deps --no-build --pull never --abort-on-container-exit \
  --exit-code-from grafana-sso-policy grafana-sso-policy
"${backup_compose[@]}" logs \
  --no-log-prefix grafana-sso-policy > \
  "$bundle_stage/grafana-sso-policy.log"
grep -Eq '^\[grafana-sso-policy\] Verified [0-9]+ compliant active API/service-account token\(s\); reconciled [0-9]+ active SSO override\(s\); active overrides: 0\.$' \
  "$bundle_stage/grafana-sso-policy.log"
sso_policy_verified=true
"${backup_compose[@]}" exec -T postgresql_maintenance \
  /usr/local/bin/backup.sh full 2>&1 | tee "$bundle_stage/postgresql-full.log"
"${backup_compose[@]}" exec -T postgresql_maintenance \
  /usr/local/bin/backup.sh dump 2>&1 | tee "$bundle_stage/postgresql-dump.log"
"${backup_compose[@]}" exec -T postgresql_maintenance \
  /usr/local/bin/backup.sh globals 2>&1 | tee "$bundle_stage/postgresql-globals.log"
maintenance_was_stopped=true
"${backup_compose[@]}" stop postgresql_maintenance

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
exec {recovery_lock_fd}<&-
trap - EXIT
printf 'Complete backup published at %s\n' "$bundle_dir"
```

Copy the complete bundle to encrypted, æccess-controlled off-host storæge.
Export the exæct mætching Docker secret files to æn encrypted secrets mænæger,
ænd export the Æuthentik æpplicætion/provider/bindings/groups plus Træefik ænd
DNS/TLS configurætion. Record their væult/export IDs beside the bæckup ID.
Verify the off-host copy with `sha256sum -c SHA256SUMS`. The bundle's
`images.manifest` ænd `grafana-images.tar.gz` cover `app`,
`grafana-sso-policy`, `postgresql`, ænd `postgresql_maintenance`; the
bæckup-time `grafana-bootstrap` ænd `grafana-migrator` proofs reuse the
immutæble recovery æliæs of the recorded running `app` imæge, while the policy proof uses its own
recorded æliæs. Neither proof trusts æ moving deployment tæg.

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
     grafana-migrator.log grafana-sso-policy.log compose-effective.json
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

2. Loæd every sæved locæl imæge ænd verify its recorded ID. Do not move or
   recreæte æny originæl locæl tæg during stæging: every recovery service,
   including bootstræp, uses the generæted, ID-verified recovery-æliæs override.
   This ævoids mutæting æ still-running host generætion ænd works for
   `repo@sha256:...` references, which cænnot be Docker tæg tærgets. Restore
   mætching secrets from the encrypted væult
   ænd compære the deployment ærchive in æ temporæry directory.
   `compose-effective.json`, `source-revision.txt`, `source-status.txt`, the
   ærchived `run.sh`, `.run.conf/.templates.lock`, ænd optionæl `.source.lock`
   define the merge generætion. Do not run æ current or unlocked merge over the
   restored deployment.

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   set -euo pipefail
   export LC_ALL=C
   restore_bundle=/absolute/path/to/grafana-backup
   restore_id=20260819T120000Z
   test "$(id -u)" -eq 0
   [[ "$restore_id" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
   [[ "$restore_bundle" == /* ]]
   test -d "$restore_bundle"
   test ! -L "$restore_bundle"
   test "$(realpath -e -- "$restore_bundle")" = "$restore_bundle"
   required_bundle_artifacts=(
     COMPLETE SHA256SUMS deployment.tar grafana-appdata.tar
     postgresql-backups.tar grafana-images.tar.gz images.manifest
     images-inspect.json grafana-version.txt grafana-plugins.txt
     grafana-migrator.log grafana-sso-policy.log compose-effective.json
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
   for artifact in "${required_bundle_artifacts[@]}"; do
     test "$(stat -c '%F:%h' -- "$restore_bundle/$artifact")" = \
       'regular file:1'
   done
   printf '%s' grafana-recovery-bundle-v1 | cmp -s - \
     "$restore_bundle/COMPLETE"
   LC_ALL=C awk '
     NF != 2 || $1 !~ /^[0-9a-f]{64}$/ ||
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
         /^\// || /\/\// || /(^|\/)\.\.(\/|$)/ ||
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
   source_revision="$(cat "$restore_bundle/source-revision.txt")"
   [[ "$source_revision" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]
   test -x "$restore_bundle/run.sh"
   config_stage="$(pwd)/.config-restore-$restore_id"
   test ! -e "$config_stage"
   test ! -L "$config_stage"
   install -d -m 0700 -- "$config_stage"
   test "$(realpath -e -- "$config_stage")" = "$config_stage"
   (cd "$restore_bundle" && sha256sum -c SHA256SUMS)
   tar -xpf "$restore_bundle/deployment.tar" -C "$config_stage"
   reject_compose_shell_overrides() {
     local environment_file=$1 environment_line environment_key
     while IFS= read -r environment_line || [ -n "$environment_line" ]; do
       if [[ "$environment_line" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
         environment_key="${BASH_REMATCH[1]}"
         if printenv "$environment_key" >/dev/null 2>&1; then
           printf 'ERROR: exported Compose override is forbidden: %s\n' \
             "$environment_key" >&2
           return 1
         fi
       fi
     done < "$environment_file"
     for environment_key in COMPOSE_PROJECT_NAME COMPOSE_FILE COMPOSE_PROFILES \
       COMPOSE_ENV_FILES COMPOSE_DISABLE_ENV_FILE; do
       if printenv "$environment_key" >/dev/null 2>&1; then
         printf 'ERROR: exported Compose control is forbidden: %s\n' \
           "$environment_key" >&2
         return 1
       fi
     done
   }
   reject_compose_shell_overrides "$config_stage/.env"
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
   docker compose --project-directory "$(pwd)" \
     --env-file "$config_stage/.env" \
     -f "$config_stage/docker-compose.main.yaml" config --format json > \
     "$config_check"
   cmp -s \
     <(jq -S '.services |= with_entries(.value |= del(.image, .pull_policy))' \
       "$restore_bundle/compose-effective.json") \
     <(jq -S '.services |= with_entries(.value |= del(.image, .pull_policy))' \
       "$config_check")
   (cd "$restore_bundle" && sha256sum -c SHA256SUMS)
   gzip -dc "$restore_bundle/grafana-images.tar.gz" | docker image load
   declare -A restored_image_services=()
   declare -A restored_image_refs=()
   declare -A restored_image_ids=()
   declare -A restored_image_tags=()
   while IFS='|' read -r image_service image_ref expected_image_id backup_image_tag extra; do
     test -z "$extra"
     case "$image_service" in
       app|grafana-sso-policy|postgresql|postgresql_maintenance) ;;
       *) printf 'ERROR: unexpected image service: %s\n' "$image_service" >&2; exit 1 ;;
     esac
     test -z "${restored_image_services[$image_service]:-}"
     [[ "$expected_image_id" =~ ^sha256:[0-9a-f]{64}$ ]]
     [[ "$backup_image_tag" =~ \
       ^grafana-recovery-${image_service//_/-}:[0-9]{8}T[0-9]{6}Z$ ]]
     archived_image_ref="$(jq -er --arg service "$image_service" \
       '.services[$service].image // (.name + "-" + $service)' \
       "$restore_bundle/compose-effective.json")"
     test "$image_ref" = "$archived_image_ref"
     actual_image_id="$(docker image inspect --format '{{.Id}}' "$backup_image_tag")"
     test "$actual_image_id" = "$expected_image_id"
     restored_image_services[$image_service]=true
     restored_image_refs[$image_service]="$image_ref"
     restored_image_ids[$image_service]="$expected_image_id"
     restored_image_tags[$image_service]="$backup_image_tag"
   done < "$restore_bundle/images.manifest"
   for required_image_service in app grafana-sso-policy postgresql postgresql_maintenance; do
     test "${restored_image_services[$required_image_service]:-}" = true
   done
   restore_image_override="$config_stage/docker-compose.recovery-images.yaml"
   test ! -e "$restore_image_override"
   test ! -L "$restore_image_override"
   {
     printf '%s\n' 'services:'
     for recovery_service in app grafana-bootstrap grafana-migrator \
       grafana-sso-policy \
       postgresql postgresql_maintenance; do
       recovery_image_service="$recovery_service"
       if [ "$recovery_service" = grafana-bootstrap ] || \
          [ "$recovery_service" = grafana-migrator ]; then
         recovery_image_service=app
       fi
       printf '  %s:\n    image: %s\n    pull_policy: never\n' \
         "$recovery_service" \
         "${restored_image_tags[$recovery_image_service]}"
     done
   } > "$restore_image_override"
   chmod 0600 -- "$restore_image_override"
   test "$(stat -c '%F:%h:%a:%u' -- "$restore_image_override")" = \
     "regular file:1:600:$(id -u)"
   for recovery_service in app grafana-bootstrap grafana-migrator \
     grafana-sso-policy postgresql postgresql_maintenance; do
     recovery_image_service="$recovery_service"
     if [ "$recovery_service" = grafana-bootstrap ] || \
        [ "$recovery_service" = grafana-migrator ]; then
       recovery_image_service=app
     fi
     restored_override_ref="$(docker compose --project-directory "$(pwd)" \
       --env-file "$config_stage/.env" \
       -f "$config_stage/docker-compose.main.yaml" \
       -f "$restore_image_override" config --format json |
       jq -er --arg service "$recovery_service" \
         '.services[$service] |
          select(.pull_policy == "never") | .image')"
     test "$restored_override_ref" = \
       "${restored_image_tags[$recovery_image_service]}"
     test "$(docker image inspect --format '{{.Id}}' \
       "$restored_override_ref")" = \
       "${restored_image_ids[$recovery_image_service]}"
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
     -f "$config_stage/docker-compose.main.yaml" \
     -f "$restore_image_override" config --quiet
   bundle_identity_file="$config_stage/.recovery-bundle.sha256"
   test ! -e "$bundle_identity_file"
   test ! -L "$bundle_identity_file"
   (cd "$restore_bundle" && sha256sum -c SHA256SUMS)
   restore_bundle_digest="$(sha256sum "$restore_bundle/SHA256SUMS" |
     awk '{ print $1 }')"
   [[ "$restore_bundle_digest" =~ ^[0-9a-f]{64}$ ]]
   printf '%s\n' "$restore_bundle_digest" > "$bundle_identity_file"
   chmod 0600 -- "$bundle_identity_file"
   sync -f "$bundle_identity_file" "$config_stage"
   rm -f -- "$config_check"
   trap - EXIT
   ```

   On æ fresh host, check out the recorded source revision, review æny scoped
   differences recorded in `source-status.txt`, then restore the reviewed
   deployment files ænd lock bytes from `config_stage` before continuing. On æn
   existing host, keep æ byte-exæct copy of the current configurætion beside
   the dætæ rollbæck. Every recovery Compose commænd below uses
   `--project-directory` with the persistent `config_stage` ænd its generæted,
   mænifest-verified `docker-compose.recovery-images.yaml`; relætive binds ænd
   secrets still resolve to the live `Grafana/` directory while configurætion
   comes from the ærchive ænd every imæge resolves to æ loæded recovery æliæs.
   This works for both tæg- ænd digest-pinned originæl references without
   retægging æny originæl reference. No merge, build, or pull is permitted.

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
   reæl one-shot to prove the restored recovery secret before stærtup. The
   bound `SHA256SUMS` digest is written into both the future `appdata`
   generætion ænd the selected PostgreSQL-input stæge; step 4 rechecks both
   bindings ænd every selected input before the first dætæbæse mutætion.

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
   [[ "$restore_bundle" == /* ]]
   test -d "$restore_bundle"
   test ! -L "$restore_bundle"
   printf '%s' grafana-recovery-bundle-v1 | cmp -s - \
     "$restore_bundle/COMPLETE"
   (cd "$restore_bundle" && sha256sum -c SHA256SUMS)
   restore_bundle_digest="$(sha256sum "$restore_bundle/SHA256SUMS" |
     awk '{ print $1 }')"
   [[ "$restore_bundle_digest" =~ ^[0-9a-f]{64}$ ]]
   config_stage="$(pwd)/.config-restore-$restore_id"
   config_bundle_identity="$config_stage/.recovery-bundle.sha256"
   test "$(stat -c '%F:%h:%a' -- "$config_bundle_identity")" = \
     'regular file:1:600'
   test ! -L "$config_bundle_identity"
   printf '%s\n' "$restore_bundle_digest" | \
     cmp -s - "$config_bundle_identity"
   for artifact in grafana-appdata.tar postgresql-backups.tar; do
     test "$(stat -c '%F:%h' -- "$restore_bundle/$artifact")" = \
       'regular file:1'
   done
   verify_grafana_tar() {
     archive=$1
     tar -tf "$archive" |
       LC_ALL=C awk '
         /^\// || /\/\// || /(^|\/)\.\.(\/|$)/ ||
           /(^|\/)\.(\/|$)/ { exit 1 }
         seen[$0]++ { exit 1 }
       '
     tar -tvf "$archive" |
       LC_ALL=C awk 'substr($1, 1, 1) != "-" && substr($1, 1, 1) != "d" { exit 1 }'
   }
   verify_grafana_tar "$restore_bundle/grafana-appdata.tar"
   verify_grafana_tar "$restore_bundle/postgresql-backups.tar"
   app_stage="$(pwd)/.appdata-restore-$restore_id"
   db_stage="$(pwd)/.postgresql-restore-$restore_id"
   bundle_binding_name=".restore-bundle-$restore_id.sha256"
   restore_inputs_manifest="$db_stage/restore-inputs.sha256"
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
   umask 077
   find restore -xdev -mindepth 1 -maxdepth 1 -type f -print0 |
     LC_ALL=C sort -z | xargs -0 sha256sum > "$restore_inputs_manifest"
   test -s "$restore_inputs_manifest"
   printf '%s\n' "$restore_bundle_digest" > \
     "$db_stage/$bundle_binding_name"
   chmod 0600 -- "$restore_inputs_manifest" \
     "$db_stage/$bundle_binding_name"
   sync -f restore
   rm -- "$marker"
   test ! -e "$marker"
   test ! -L "$marker"
   generation_sentinel=".restore-generation-$restore_id"
   printf '%s\n' "$restore_id" > "$app_stage/$generation_sentinel"
   printf '%s\n' "$restore_bundle_digest" > \
     "$app_stage/$bundle_binding_name"
   chmod 0600 -- "$app_stage/$generation_sentinel"
   chmod 0600 -- "$app_stage/$bundle_binding_name"
   chown --no-dereference 472:472 "$app_stage/$generation_sentinel" \
     "$app_stage/$bundle_binding_name"
   chown --no-dereference 472:472 "$app_stage"
   chmod 0770 -- "$app_stage"
   test "$(stat -c '%F:%a:%u:%g' -- "$app_stage")" = \
     'directory:770:472:472'
   sync -f "$app_stage"
   sync -f "$db_stage"
   rm -f -- "$restore_check" "$restore_inputs" "$archive_inputs"
   trap - EXIT
   ```

4. Hold the verified per-Æpp lock, prove the versioned physicæl-restore
   override renders with the loæded PostgreSQL-mæintenænce imæge, ænd stop
   **every** writer, including æ running or fæiled `grafana-bootstrap`,
   `grafana-migrator`, or `grafana-sso-policy`. Record
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
   db_stage="$(pwd)/.postgresql-restore-$restore_id"
   rollback_dir="$(pwd)/appdata.rollback-$restore_id"
   generation_sentinel=".restore-generation-$restore_id"
   bundle_binding_name=".restore-bundle-$restore_id.sha256"
   test -d "$config_stage"
   test ! -L "$config_stage"
   [[ "$restore_bundle" == /* ]]
   test -d "$restore_bundle"
   test ! -L "$restore_bundle"
   printf '%s' grafana-recovery-bundle-v1 | cmp -s - \
     "$restore_bundle/COMPLETE"
   (cd "$restore_bundle" && sha256sum -c SHA256SUMS)
   config_bundle_identity="$config_stage/.recovery-bundle.sha256"
   test "$(stat -c '%F:%h:%a' -- "$config_bundle_identity")" = \
     'regular file:1:600'
   test ! -L "$config_bundle_identity"
   restore_bundle_digest="$(sha256sum "$restore_bundle/SHA256SUMS" |
     awk '{ print $1 }')"
   [[ "$restore_bundle_digest" =~ ^[0-9a-f]{64}$ ]]
   printf '%s\n' "$restore_bundle_digest" | \
     cmp -s - "$config_bundle_identity"
   tar --acls --xattrs --numeric-owner --compare \
     -f "$restore_bundle/deployment.tar" -C "$config_stage"
   reject_compose_shell_overrides() {
     local environment_file=$1 environment_line environment_key
     while IFS= read -r environment_line || [ -n "$environment_line" ]; do
       if [[ "$environment_line" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
         environment_key="${BASH_REMATCH[1]}"
         if printenv "$environment_key" >/dev/null 2>&1; then
           printf 'ERROR: exported Compose override is forbidden: %s\n' \
             "$environment_key" >&2
           return 1
         fi
       fi
     done < "$environment_file"
     for environment_key in COMPOSE_PROJECT_NAME COMPOSE_FILE COMPOSE_PROFILES \
       COMPOSE_ENV_FILES COMPOSE_DISABLE_ENV_FILE; do
       if printenv "$environment_key" >/dev/null 2>&1; then
         printf 'ERROR: exported Compose control is forbidden: %s\n' \
           "$environment_key" >&2
         return 1
       fi
     done
   }
   reject_compose_shell_overrides "$config_stage/.env"
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
   test -d "$db_stage"
   test ! -L "$db_stage"
   test "$(stat -c '%F:%h' -- "$app_stage/$generation_sentinel")" = \
     'regular file:1'
   printf '%s\n' "$restore_id" | cmp -s - "$app_stage/$generation_sentinel"
   for bundle_binding in "$app_stage/$bundle_binding_name" \
     "$db_stage/$bundle_binding_name"; do
     test "$(stat -c '%F:%h:%a' -- "$bundle_binding")" = \
       'regular file:1:600'
     test ! -L "$bundle_binding"
     printf '%s\n' "$restore_bundle_digest" | cmp -s - "$bundle_binding"
   done
   restore_inputs_manifest="$db_stage/restore-inputs.sha256"
   test "$(stat -c '%F:%h:%a' -- "$restore_inputs_manifest")" = \
     'regular file:1:600'
   test ! -L "$restore_inputs_manifest"
   LC_ALL=C awk '
     NF != 2 || $1 !~ /^[0-9a-f]{64}$/ ||
       $2 !~ /^restore\/[A-Za-z0-9._-]+$/ || seen[$2]++ { exit 1 }
   ' "$restore_inputs_manifest"
   sha256sum -c "$restore_inputs_manifest"
   test ! -e "appdata/$generation_sentinel"
   test ! -L "appdata/$generation_sentinel"
   test ! -e "$rollback_dir"
   test ! -L "$rollback_dir"
   appdata_identity="$(stat -Lc '%d:%i' -- appdata)"
   app_stage_identity="$(stat -Lc '%d:%i' -- "$app_stage")"
   restore_image_override="$config_stage/docker-compose.recovery-images.yaml"
   test "$(stat -c '%F:%h:%a' -- "$restore_image_override")" = \
     'regular file:1:600'
   test ! -L "$restore_image_override"
   yq --output-format=json '.' "$restore_image_override" |
     jq -e '
       (keys == ["services"]) and
       (.services | (keys | sort) == [
         "app", "grafana-bootstrap", "grafana-migrator",
         "grafana-sso-policy", "postgresql", "postgresql_maintenance"
       ]) and
       ([.services | to_entries[] |
         (.value |
           (type == "object") and
           ((keys | sort) == ["image", "pull_policy"]) and
           (.image | (type == "string") and (length > 0)) and
           (.pull_policy == "never"))
       ] | all)
     ' >/dev/null
   restore_compose=(docker compose --project-directory "$(pwd)" \
     --env-file "$config_stage/.env" \
     -f "$config_stage/docker-compose.main.yaml" \
     -f "$restore_image_override")
   test "$(stat -c '%F:%h' -- "$restore_bundle/compose-effective.json")" = \
     'regular file:1'
   cmp -s \
     <(jq -S '.services |= with_entries(.value |= del(.image, .pull_policy))' \
       "$restore_bundle/compose-effective.json") \
     <("${restore_compose[@]}" config --format json |
       jq -S '.services |= with_entries(.value |= del(.image, .pull_policy))')
   test "$(stat -c '%F:%h' -- "$restore_bundle/images.manifest")" = \
     'regular file:1'
   declare -A restore_image_services=()
   declare -A restore_image_ids=()
   declare -A restore_image_tags=()
   while IFS='|' read -r image_service image_ref expected_image_id \
     backup_image_tag extra; do
     test -z "$extra"
     case "$image_service" in
       app|grafana-sso-policy|postgresql|postgresql_maintenance) ;;
       *) printf 'ERROR: unexpected image service: %s\n' "$image_service" >&2; exit 1 ;;
     esac
     test -z "${restore_image_services[$image_service]:-}"
     [[ "$expected_image_id" =~ ^sha256:[0-9a-f]{64}$ ]]
     [[ "$backup_image_tag" =~ \
       ^grafana-recovery-${image_service//_/-}:[0-9]{8}T[0-9]{6}Z$ ]]
     test "$(docker image inspect --format '{{.Id}}' "$backup_image_tag")" = \
       "$expected_image_id"
     restore_image_services[$image_service]=true
     restore_image_ids[$image_service]="$expected_image_id"
     restore_image_tags[$image_service]="$backup_image_tag"
   done < "$restore_bundle/images.manifest"
   for image_service in app grafana-sso-policy postgresql postgresql_maintenance; do
     test "${restore_image_services[$image_service]:-}" = true
   done
   for recovery_service in app grafana-bootstrap grafana-migrator \
     grafana-sso-policy postgresql postgresql_maintenance; do
     recovery_image_service="$recovery_service"
     if [ "$recovery_service" = grafana-bootstrap ] || \
        [ "$recovery_service" = grafana-migrator ]; then
       recovery_image_service=app
     fi
     recovery_image_ref="$("${restore_compose[@]}" config --format json |
       jq -er --arg service "$recovery_service" \
         '.services[$service] | select(.pull_policy == "never") | .image')"
     test "$recovery_image_ref" = \
       "${restore_image_tags[$recovery_image_service]}"
     test "$(docker image inspect --format '{{.Id}}' "$recovery_image_ref")" = \
       "${restore_image_ids[$recovery_image_service]}"
   done
   writer_check="$(mktemp /tmp/grafana-writer-check.XXXXXX)"
   trap 'rm -f -- "$writer_check"' EXIT
   restore_maintenance_override=\
"$config_stage/docker-compose.postgresql_maintenance.restore.yaml.example"
   test "$(stat -c '%F:%h' -- "$restore_maintenance_override")" = \
     'regular file:1'
   test ! -L "$restore_maintenance_override"
   yq --output-format=json '.' "$restore_maintenance_override" |
     jq -e '
       (keys == ["services"]) and
       (.services | keys == ["postgresql_maintenance"]) and
       (.services.postgresql_maintenance | (keys | sort) ==
         ["pull_policy", "volumes"]) and
       (.services.postgresql_maintenance.pull_policy == "never") and
       (.services.postgresql_maintenance.volumes ==
         ["database:/var/lib/postgresql:rw"])
     ' >/dev/null
   "${restore_compose[@]}" \
     -f "$restore_maintenance_override" \
     config --quiet
   "${restore_compose[@]}" stop app grafana-bootstrap grafana-migrator \
     grafana-sso-policy postgresql_maintenance
   "${restore_compose[@]}" rm -f grafana-bootstrap grafana-migrator \
     grafana-sso-policy
   "${restore_compose[@]}" stop postgresql
   "${restore_compose[@]}" ps \
     --status running -q app grafana-bootstrap grafana-migrator \
     grafana-sso-policy postgresql postgresql_maintenance > \
     "$writer_check"
   test ! -s "$writer_check"
   printf '%s\n' "$restore_bundle_digest" |
     cmp -s - "$app_stage/$bundle_binding_name"
   printf '%s\n' "$restore_bundle_digest" |
     cmp -s - "$db_stage/$bundle_binding_name"
   sha256sum -c "$restore_inputs_manifest"
   "${restore_compose[@]}" \
     -f "$restore_maintenance_override" \
     run --rm \
     --no-deps --pull never \
     -e POSTGRES_RESTORE_BACKUP_ID="$postgres_backup_id" \
     -e POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED=true \
     postgresql_maintenance restore --dry-run
   "${restore_compose[@]}" \
     -f "$restore_maintenance_override" \
     run --rm --no-deps --pull never \
     -e POSTGRES_RESTORE_BACKUP_ID="$postgres_backup_id" \
     -e POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED=true \
     postgresql_maintenance restore
   "${restore_compose[@]}" ps \
     --status running -q app grafana-bootstrap grafana-migrator \
     grafana-sso-policy postgresql postgresql_maintenance > \
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
   test "$(stat -c '%F:%h:%a:%u:%g' -- \
     "appdata/$bundle_binding_name")" = 'regular file:1:600:472:472'
   printf '%s\n' "$restore_bundle_digest" |
     cmp -s - "appdata/$bundle_binding_name"
   mv --update=none-fail --no-copy -T -- "$app_stage" "$rollback_dir"
   test ! -e "$app_stage"
   test "$(stat -Lc '%d:%i' -- "$rollback_dir")" = "$appdata_identity"
   sync -f appdata "$rollback_dir"
   sync -f "$(pwd)"
   rm -f -- "$writer_check"
   exec {recovery_lock_fd}<&-
   trap - EXIT
   ```

   GNU `mv --exchange --no-copy` fæils before mutætion when ætomic exchænge is
   unsupported. The generætion sentinel ænd inode checks prove whether æn
   interrupted run crossed the exchænge point; never rerun the exchænge
   blindly. The rollbæck directory retæins the complete old `appdata` tree.

<div id="staged-restore-activation"></div>

5. Stært with the loæded, version-compætible locæl imæges ænd no build or
   pull. Becæuse the stæged mærker wæs removed ænd æll three old finite
   contæiners were deleted, `app` cæn stært only æfter æ fresh bootstræp
   verifies the restored recovery secret twice, the migrætor æpplies ænd
   proves the restored imæge's schemæ, then the restored policy imæge proves
   zero æctive SSO overrides ænd no æctive token-policy debt. Keep `app`
   stopped throughout æll three foreground jobs:

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
   [[ "$restore_bundle" == /* ]]
   test -d "$restore_bundle"
   test ! -L "$restore_bundle"
   printf '%s' grafana-recovery-bundle-v1 | cmp -s - \
     "$restore_bundle/COMPLETE"
   (cd "$restore_bundle" && sha256sum -c SHA256SUMS)
   config_bundle_identity="$config_stage/.recovery-bundle.sha256"
   test "$(stat -c '%F:%h:%a' -- "$config_bundle_identity")" = \
     'regular file:1:600'
   test ! -L "$config_bundle_identity"
   restore_bundle_digest="$(sha256sum "$restore_bundle/SHA256SUMS" |
     awk '{ print $1 }')"
   [[ "$restore_bundle_digest" =~ ^[0-9a-f]{64}$ ]]
   printf '%s\n' "$restore_bundle_digest" | \
     cmp -s - "$config_bundle_identity"
   tar --acls --xattrs --numeric-owner --compare \
     -f "$restore_bundle/deployment.tar" -C "$config_stage"
   reject_compose_shell_overrides() {
     local environment_file=$1 environment_line environment_key
     while IFS= read -r environment_line || [ -n "$environment_line" ]; do
       if [[ "$environment_line" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
         environment_key="${BASH_REMATCH[1]}"
         if printenv "$environment_key" >/dev/null 2>&1; then
           printf 'ERROR: exported Compose override is forbidden: %s\n' \
             "$environment_key" >&2
           return 1
         fi
       fi
     done < "$environment_file"
     for environment_key in COMPOSE_PROJECT_NAME COMPOSE_FILE COMPOSE_PROFILES \
       COMPOSE_ENV_FILES COMPOSE_DISABLE_ENV_FILE; do
       if printenv "$environment_key" >/dev/null 2>&1; then
         printf 'ERROR: exported Compose control is forbidden: %s\n' \
           "$environment_key" >&2
         return 1
       fi
     done
   }
   reject_compose_shell_overrides "$config_stage/.env"
   test -d .run.conf
   test ! -L .run.conf
   recovery_lock_identity="$(stat -Lc '%d:%i' -- .run.conf)"
   exec {recovery_lock_fd}<.run.conf
   flock -n -x "$recovery_lock_fd"
   test "$(stat -Lc '%d:%i' -- "/proc/$$/fd/$recovery_lock_fd")" = \
     "$recovery_lock_identity"
   test "$(stat -Lc '%d:%i' -- .run.conf)" = "$recovery_lock_identity"
   restore_image_override="$config_stage/docker-compose.recovery-images.yaml"
   test "$(stat -c '%F:%h:%a' -- "$restore_image_override")" = \
     'regular file:1:600'
   test ! -L "$restore_image_override"
   yq --output-format=json '.' "$restore_image_override" |
     jq -e '
       (keys == ["services"]) and
       (.services | (keys | sort) == [
         "app", "grafana-bootstrap", "grafana-migrator",
         "grafana-sso-policy", "postgresql", "postgresql_maintenance"
       ]) and
       ([.services | to_entries[] |
         (.value |
           (type == "object") and
           ((keys | sort) == ["image", "pull_policy"]) and
           (.image | (type == "string") and (length > 0)) and
           (.pull_policy == "never"))
       ] | all)
     ' >/dev/null
   restore_compose=(docker compose --project-directory "$(pwd)" \
     --env-file "$config_stage/.env" \
     -f "$config_stage/docker-compose.main.yaml" \
     -f "$restore_image_override")
   test "$(stat -c '%F:%h' -- "$restore_bundle/compose-effective.json")" = \
     'regular file:1'
   cmp -s \
     <(jq -S '.services |= with_entries(.value |= del(.image, .pull_policy))' \
       "$restore_bundle/compose-effective.json") \
     <("${restore_compose[@]}" config --format json |
       jq -S '.services |= with_entries(.value |= del(.image, .pull_policy))')
   test "$(stat -c '%F:%h' -- "$restore_bundle/images.manifest")" = \
     'regular file:1'
   declare -A restore_image_services=()
   declare -A restore_image_ids=()
   declare -A restore_image_tags=()
   while IFS='|' read -r image_service image_ref expected_image_id \
     backup_image_tag extra; do
     test -z "$extra"
     case "$image_service" in
       app|grafana-sso-policy|postgresql|postgresql_maintenance) ;;
       *) printf 'ERROR: unexpected image service: %s\n' "$image_service" >&2; exit 1 ;;
     esac
     test -z "${restore_image_services[$image_service]:-}"
     [[ "$expected_image_id" =~ ^sha256:[0-9a-f]{64}$ ]]
     [[ "$backup_image_tag" =~ \
       ^grafana-recovery-${image_service//_/-}:[0-9]{8}T[0-9]{6}Z$ ]]
     test "$(docker image inspect --format '{{.Id}}' "$backup_image_tag")" = \
       "$expected_image_id"
     restore_image_services[$image_service]=true
     restore_image_ids[$image_service]="$expected_image_id"
     restore_image_tags[$image_service]="$backup_image_tag"
   done < "$restore_bundle/images.manifest"
   for image_service in app grafana-sso-policy postgresql postgresql_maintenance; do
     test "${restore_image_services[$image_service]:-}" = true
   done
   for recovery_service in app grafana-bootstrap grafana-migrator \
     grafana-sso-policy postgresql postgresql_maintenance; do
     recovery_image_service="$recovery_service"
     if [ "$recovery_service" = grafana-bootstrap ] || \
        [ "$recovery_service" = grafana-migrator ]; then
       recovery_image_service=app
     fi
     recovery_image_ref="$("${restore_compose[@]}" config --format json |
       jq -er --arg service "$recovery_service" \
         '.services[$service] | select(.pull_policy == "never") | .image')"
     test "$recovery_image_ref" = \
       "${restore_image_tags[$recovery_image_service]}"
     test "$(docker image inspect --format '{{.Id}}' "$recovery_image_ref")" = \
       "${restore_image_ids[$recovery_image_service]}"
   done
   recovery_form_override="${GRAFANA_RECOVERY_FORM_OVERRIDE:-}"
   recovery_form_override_sha256=
   if [ -n "$recovery_form_override" ]; then
     [[ "$recovery_form_override" == /* ]]
     test "$recovery_form_override" = \
       "$config_stage/docker-compose.recovery-local-form.yaml"
     test "$(stat -c '%F:%h:%a:%u' -- "$recovery_form_override")" = \
       'regular file:1:600:0'
     test ! -L "$recovery_form_override"
     recovery_form_override_sha256="$(sha256sum "$recovery_form_override" |
       awk '{ print $1 }')"
     [[ "$recovery_form_override_sha256" =~ ^[0-9a-f]{64}$ ]]
     yq --output-format=json '.' "$recovery_form_override" |
       jq -e '
         (keys == ["services"]) and
         (.services | keys == ["app"]) and
         (.services.app | keys == ["environment"]) and
         (.services.app.environment | (keys | sort) == [
           "GRAFANA_DISABLE_LOGIN_FORM", "GRAFANA_OAUTH_AUTO_LOGIN"
         ]) and
         (.services.app.environment.GRAFANA_DISABLE_LOGIN_FORM == "false") and
         (.services.app.environment.GRAFANA_OAUTH_AUTO_LOGIN == "false")
       ' >/dev/null
     restore_compose+=(-f "$recovery_form_override")
     "${restore_compose[@]}" config --format json |
       jq -e '
         .services.app.environment.GRAFANA_DISABLE_LOGIN_FORM == "false" and
         .services.app.environment.GRAFANA_OAUTH_AUTO_LOGIN == "false"
       ' >/dev/null
   fi
   "${restore_compose[@]}" stop app
   test -z "$("${restore_compose[@]}" ps --status running -q app)"
   generation_sentinel="appdata/.restore-generation-$restore_id"
   bundle_binding="appdata/.restore-bundle-$restore_id.sha256"
   test "$(stat -c '%F:%h:%u:%g' -- "$generation_sentinel")" = \
     'regular file:1:472:472'
   test ! -L "$generation_sentinel"
   printf '%s\n' "$restore_id" | cmp -s - "$generation_sentinel"
   test "$(stat -c '%F:%h:%a:%u:%g' -- "$bundle_binding")" = \
     'regular file:1:600:472:472'
   test ! -L "$bundle_binding"
   printf '%s\n' "$restore_bundle_digest" | cmp -s - "$bundle_binding"
   "${restore_compose[@]}" up -d \
     --no-build --pull never postgresql
   postgres_health_attempts=60
   until "${restore_compose[@]}" exec -T postgresql \
     sh -ec 'exec pg_isready -d "$POSTGRES_DB" -U "$POSTGRES_USER"' \
     >/dev/null 2>&1; do
     postgres_health_attempts=$((postgres_health_attempts - 1))
     test "$postgres_health_attempts" -gt 0
     sleep 2
   done
   "${restore_compose[@]}" up -d \
     --no-deps --no-build --pull never postgresql_maintenance
   "${restore_compose[@]}" rm -f grafana-bootstrap grafana-migrator \
     grafana-sso-policy
   "${restore_compose[@]}" up \
     --no-deps --no-build --pull never --abort-on-container-exit \
     --exit-code-from grafana-bootstrap grafana-bootstrap
   "${restore_compose[@]}" up \
     --no-deps --no-build --pull never --abort-on-container-exit \
     --exit-code-from grafana-migrator grafana-migrator
   restore_migrator_log="$("${restore_compose[@]}" logs \
     --no-log-prefix grafana-migrator)"
   printf '%s\n' "$restore_migrator_log"
   printf '%s\n' "$restore_migrator_log" |
     grep -Fx '[grafana-migrator] Database migrations and health verified without the bootstrap administrator credential.'
   "${restore_compose[@]}" up \
     --no-deps --no-build --pull never --abort-on-container-exit \
     --exit-code-from grafana-sso-policy grafana-sso-policy
   restore_policy_log="$("${restore_compose[@]}" logs \
     --no-log-prefix grafana-sso-policy)"
   printf '%s\n' "$restore_policy_log"
   printf '%s\n' "$restore_policy_log" |
     grep -Eq '^\[grafana-sso-policy\] Verified [0-9]+ compliant active API/service-account token\(s\); reconciled [0-9]+ active SSO override\(s\); active overrides: 0\.$'
   restore_app_accepted=false
   stop_unaccepted_restored_app() {
     restore_status=$?
     trap - EXIT
     if [ "$restore_app_accepted" != true ]; then
       if ! "${restore_compose[@]}" stop app; then
         printf '%s\n' 'ERROR: failed to stop an unaccepted restored app.' >&2
         restore_status=1
       fi
       if ! restore_running_app="$("${restore_compose[@]}" \
         ps --status running -q app)"; then
         restore_status=1
       elif [ -n "$restore_running_app" ]; then
         printf '%s\n' 'ERROR: unaccepted restored app remains running.' >&2
         restore_status=1
       fi
     fi
     if [ -n "$recovery_form_override" ]; then
       if [ -e "$recovery_form_override" ] || \
          [ -L "$recovery_form_override" ]; then
         if [ ! -L "$recovery_form_override" ] && \
            [ "$(sha256sum "$recovery_form_override" | \
              awk '{ print $1 }')" = "$recovery_form_override_sha256" ]; then
           if ! rm -- "$recovery_form_override"; then
             printf '%s\n' \
               'ERROR: failed to remove the bound recovery-form override.' >&2
             restore_status=1
           fi
         else
           printf '%s\n' \
             'ERROR: recovery-form override changed; retain it for investigation.' >&2
           restore_status=1
         fi
       fi
     fi
     if ! exec {recovery_lock_fd}<&-; then
       printf '%s\n' 'ERROR: failed to release the recovery lock.' >&2
       restore_status=1
     fi
     exit "$restore_status"
   }
   trap stop_unaccepted_restored_app EXIT
   if ! "${restore_compose[@]}" up -d --wait --wait-timeout 180 \
     --no-deps --no-build --pull never app; then
     exit 1
   fi
   if [ -n "$recovery_form_override" ]; then
     test "$(sha256sum "$recovery_form_override" | awk '{ print $1 }')" = \
       "$recovery_form_override_sha256"
   fi
   "${restore_compose[@]}" ps --all
   "${restore_compose[@]}" logs \
     --no-log-prefix grafana-bootstrap grafana-migrator grafana-sso-policy
   bootstrap_container="$("${restore_compose[@]}" ps --all -q grafana-bootstrap)"
   migrator_container="$("${restore_compose[@]}" ps --all -q grafana-migrator)"
   policy_container="$("${restore_compose[@]}" ps --all -q grafana-sso-policy)"
   test -n "$bootstrap_container"
   test -n "$migrator_container"
   test -n "$policy_container"
   test "$(docker inspect --format '{{.State.Running}} {{.State.ExitCode}}' \
     "$bootstrap_container")" = 'false 0'
   test "$(docker inspect --format '{{.State.Running}} {{.State.ExitCode}}' \
     "$migrator_container")" = 'false 0'
   test "$(docker inspect --format '{{.State.Running}} {{.State.ExitCode}}' \
     "$policy_container")" = 'false 0'
   for activated_service in app grafana-bootstrap grafana-migrator \
     grafana-sso-policy postgresql postgresql_maintenance; do
     activated_image_service="$activated_service"
     if [ "$activated_service" = grafana-bootstrap ] || \
        [ "$activated_service" = grafana-migrator ]; then
       activated_image_service=app
     fi
     activated_container="$("${restore_compose[@]}" ps --all -q \
       "$activated_service")"
     case "$activated_container" in ''|*$'\n'*) exit 1 ;; esac
     test "$(docker inspect --format '{{.Image}}' "$activated_container")" = \
       "${restore_image_ids[$activated_image_service]}"
   done
   marker=appdata/bootstrap-state/bootstrap-v1.complete
   test -f "$marker"
   test ! -L "$marker"
   printf '%s' grafana-bootstrap-v1 | cmp -s - "$marker"
   "${restore_compose[@]}" exec -T app \
     /usr/local/bin/grafana-entrypoint health
   if [ -z "$recovery_form_override" ]; then
     exec {recovery_lock_fd}<&-
     restore_app_accepted=true
     trap - EXIT
   else
     printf '%s\n' \
       'Temporary recovery form is active; keep this shell and its EXIT guard open.'
   fi
   ```

Verify two OIDC ædmins, strict ædmin/editor/viewer/denied behævior, dæshboærds,
orgænisætions, dætæ sources including decrypted credentiæls, ælert rules ænd
silences, plugins, service æccounts, scheduled jobs, SMTP delivery, ænd one
reæl ælert while the ærchived closed-form configurætion is æctive.

The recovery-pæssword test is æ sepæræte, temporæry generætion. Keep the exæct
edge ællowlist ænd shæred-network peer boundæry from the breæk-glæss runbook;
never treæt VPN/IP filtering ælone æs sufficient. In æ new root shell, creæte
the only permitted recovery-form override, export its æbsolute pæth, ænd then
execute the **entire step 5 block æbove** with the sæme `restore_bundle` ænd
`restore_id`. The block revælidætes the bundle, bæse configurætion, override
shæpe, imæge IDs, ænd sentinel, then reruns bootstræp, migrætor, policy, ænd
`app` from one generætion:

```bash
cd /home/r0gmar/Seafile/Development/Docker/Grafana
set -euo pipefail
test "$(id -u)" -eq 0
restore_id=20260819T120000Z
[[ "$restore_id" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
config_stage="$(pwd)/.config-restore-$restore_id"
recovery_form_override=\
"$config_stage/docker-compose.recovery-local-form.yaml"
test ! -e "$recovery_form_override"
test ! -L "$recovery_form_override"
umask 077
install -m 0600 -o 0 -g 0 /dev/null "$recovery_form_override"
printf '%s\n' \
  'services:' \
  '  app:' \
  '    environment:' \
  '      GRAFANA_DISABLE_LOGIN_FORM: "false"' \
  '      GRAFANA_OAUTH_AUTO_LOGIN: "false"' > "$recovery_form_override"
sync -f "$recovery_form_override"
export GRAFANA_RECOVERY_FORM_OVERRIDE="$recovery_form_override"
```

Under thæt restricted ingress, sign in through the locæl form with the
restored recovery pæssword änd prove server-ædmin æccess. HTTP Bæsic must
remæin disæbled. Keep the root shell thæt executed step 5 open: its lock ænd
`recovery_form_override_sha256` bind the tested bytes. Æfter the browser test,
stop the temporæry form generætion, verify no `app` is running, remove only
thæt exæct override, ænd releæse the lock:

```bash
set -euo pipefail
: "${recovery_form_override:?}"
: "${recovery_form_override_sha256:?}"
test "$recovery_form_override" = "$GRAFANA_RECOVERY_FORM_OVERRIDE"
test "$(sha256sum "$recovery_form_override" | awk '{ print $1 }')" = \
  "$recovery_form_override_sha256"
"${restore_compose[@]}" stop app
test -z "$("${restore_compose[@]}" ps --status running -q app)"
rm -- "$recovery_form_override"
exec {recovery_lock_fd}<&-
restore_app_accepted=true
trap - EXIT
unset GRAFANA_RECOVERY_FORM_OVERRIDE recovery_form_override \
  recovery_form_override_sha256
```

Execute the entire step 5 block once more with the form override unset. Only
thæt closed-form bootstræp-migrætor-policy-æpp generætion is eligible for
finæl negætive-login tests ænd the follow-up Complete Bæckup. Prove the locæl
form, HTTP Bæsic, ænd every unæpproved provider ære unævæilæble before
releæsing the temporæry ingress restriction.

Keep `appdata.rollback-*`, the pre-restore dætæbæse bæckup, æctive
`.restore-generation-*` ænd mætching `.restore-bundle-*.sha256` sentinels,
old configurætion, ænd untouched recovery bundle until signed æcceptænce ænd
the new full bæckup. Do not copy the
ærchived configurætion over the live repository. For every post-restore
recovery bæckup, set the vælidæted Recovery-Bæsis mode in the sæme shell thæt
executes the entire Complete Bæckup block:

```bash
cd /home/r0gmar/Seafile/Development/Docker/Grafana
set -euo pipefail
restore_bundle=/absolute/path/to/grafana-backup
restore_id=20260819T120000Z
[[ "$restore_bundle" == /* ]]
[[ "$restore_id" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
config_stage="$(pwd)/.config-restore-$restore_id"
export GRAFANA_RECOVERY_CONFIG_ROOT="$config_stage"
export GRAFANA_RECOVERY_IMAGE_OVERRIDE=\
"$config_stage/docker-compose.recovery-images.yaml"
export GRAFANA_RECOVERY_BUNDLE_ROOT="$restore_bundle"
```

The Complete Bæckup block revælidætes every æbsolute regulær-file input,
rejects other shell interpolætion overrides, compæres the ærchived
`config_stage` bæse ægæinst the ærchived effective Compose snæpshot, proves
thæt the imæge override chænges only the six expected imæge references ænd
`pull_policy`, binds those references to the running contæiner IDs, then
reruns bootstræp, migrætor, ænd policy before it resumes `app`. Keep both
recovery sentinels, the untouched source bundle, ænd the three shell
væriæbles for every læter Recovery-Bæsis bæckup cycle. Leæve recovery mode
only through æ
reviewed new build/deployment generætion with its own complete bæckup ænd
bootstræp-migrætor-policy-æpp gæte; only æfter its new off-host copy pæsses
`sha256sum -c SHA256SUMS` mæy the operætor remove the two old recovery
sentinels ænd unset the three Recovery-Bæsis væriæbles. On fæilure, stop æll
writers, restore the pre-restore PostgreSQL
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
`GRAFANA_BASE_IMAGE=grafana/grafana:latest`,
`GRAFANA_GO_IMAGE=docker.io/library/golang:alpine`,
`GRAFANA_SSO_POLICY_GO_IMAGE=docker.io/library/golang:alpine`,
`POSTGRES_IMAGE=postgres:18`, ænd `POSTGRES_MAINTENANCE_IMAGE=postgres:18`
ære moving build/deployment inputs by defæult. For production, replæce æll
five inputs with reviewed immutæble tægs or digests while keeping the
required PostgreSQL mæjor `18`. `POSTGRES_IMAGE` independently selects the
primæry PostgreSQL bæse ænd the policy-job runtime bæse;
`POSTGRES_MAINTENANCE_IMAGE` selects the mæintenænce bæse. During æ
Græfænæ-only updæte, keep eæch on the exæct reviewed pin used by its
currently running service ænd do not build, recreæte, or upgræde either
PostgreSQL service. Plæn æ PostgreSQL upgræde æs æ sepæræte recovery-tested
chænge.
Græfænæ æpplies dætæbæse migrætions during stærtup; version 13 unified storæge
migrætions mæke æ pre-updæte dætæbæse restore mændætory for æn older-version
rollbæck.

1. Record the current Græfænæ version, imæge ID, bæse/builder references, ænd
   plugin inventory. Identify the exæct tærget version, reæd every intervening
   Græfænæ releæse/upgræde note, ænd check plugin ænd PostgreSQL compætibility.
   For every required plugin, review its ID, pinned version, signæture, source,
   ænd consumers, then bæke it through æ reviewed Dockerfile/imæge chænge
   into `/usr/share/grafana/plugins-reviewed`. Test thæt tærget imæge before
   cutover. Never copy `appdata/data/plugins` into the æctive pæth or
   instæll/updæte æ plugin æt runtime.
2. Run the complete bæckup æbove ænd complete æn isolæted restore proof.
3. Preserve both deployed locæl imæges under unique rollbæck tægs ænd one
   ædditionæl locæl checksum-protected ærchive before moving either `latest`
   tæg. The complete verified off-host bundle from step 2 remæins the recovery
   æuthority:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   set -euo pipefail
   update_id="$(date -u +%Y%m%dT%H%M%SZ)"
   app_container="$(docker compose --env-file .env -f docker-compose.main.yaml ps -q app)"
   policy_container="$(docker compose --env-file .env \
     -f docker-compose.main.yaml ps --all -q grafana-sso-policy)"
   case "$app_container" in ''|*$'\n'*) exit 1 ;; esac
   case "$policy_container" in ''|*$'\n'*) exit 1 ;; esac
   current_image_id="$(docker inspect --format '{{.Image}}' "$app_container")"
   current_policy_image_id="$(docker inspect --format '{{.Image}}' \
     "$policy_container")"
   app_rollback_tag="grafana-saervices:rollback-$update_id"
   policy_rollback_tag="grafana-sso-policy-saervices:rollback-$update_id"
   test "$(stat -c '%F:%a:%u' -- recovery)" = \
     "directory:700:$(id -u)"
   test ! -L recovery
   rollback_archive="recovery/grafana-rollback-images-$update_id.tar.gz"
   rollback_checksum="$rollback_archive.sha256"
   test ! -e "$rollback_archive"
   test ! -L "$rollback_archive"
   test ! -e "$rollback_checksum"
   test ! -L "$rollback_checksum"
   ! docker image inspect "$app_rollback_tag" >/dev/null 2>&1
   ! docker image inspect "$policy_rollback_tag" >/dev/null 2>&1
   docker image tag "$current_image_id" "$app_rollback_tag"
   docker image tag "$current_policy_image_id" "$policy_rollback_tag"
   docker image save "$app_rollback_tag" "$policy_rollback_tag" | gzip -c > \
     "$rollback_archive"
   sha256sum "$rollback_archive" > "$rollback_checksum"
   sha256sum -c "$rollback_checksum"
   docker image inspect "$app_rollback_tag" "$policy_rollback_tag" \
     --format '{{.Id}} {{json .RepoDigests}}'
   ```

4. Set the reviewed `GRAFANA_BASE_IMAGE`, `GRAFANA_GO_IMAGE`, ænd
   `GRAFANA_SSO_POLICY_GO_IMAGE` in `app.env`. Keep `POSTGRES_IMAGE` ænd
   `POSTGRES_MAINTENANCE_IMAGE` on the two sepæræte, exæct reviewed pins used
   by the currently running primæry ænd mæintenænce imæges. These ære
   continuity pins, not æ PostgreSQL chænge. Reuse the `update_id` from step
   3, updæte repository inputs, render, build without touching the running old
   contæiner, then bind both tærget imæge IDs to unique locæl æliæses ænd æ
   checksummed mænifest:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker
   set -euo pipefail
   update_id=REPLACE_WITH_STEP_3_UPDATE_ID
   [[ "$update_id" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
   ./run.sh Grafana
   cd Grafana
   docker compose --env-file .env -f docker-compose.main.yaml config --quiet
   docker compose --env-file .env -f docker-compose.main.yaml \
     build --pull --no-cache app grafana-sso-policy
   target_image_ref="$(docker compose --env-file .env -f docker-compose.main.yaml \
     config --format json | jq -r '.services.app.image')"
   target_policy_image_ref="$(docker compose --env-file .env \
     -f docker-compose.main.yaml config --format json | \
     jq -r '.services.grafana-sso-policy.image')"
   target_image_id="$(docker image inspect --format '{{.Id}}' \
     "$target_image_ref")"
   target_policy_image_id="$(docker image inspect --format '{{.Id}}' \
     "$target_policy_image_ref")"
   [[ "$target_image_id" =~ ^sha256:[0-9a-f]{64}$ ]]
   [[ "$target_policy_image_id" =~ ^sha256:[0-9a-f]{64}$ ]]
   target_app_alias="grafana-update:$update_id"
   target_policy_alias="grafana-sso-policy-update:$update_id"
   recovery_dir="$(pwd)/recovery"
   test "$(stat -c '%F:%a:%u' -- "$recovery_dir")" = \
     "directory:700:$(id -u)"
   test ! -L "$recovery_dir"
   target_manifest="$recovery_dir/grafana-update-target-$update_id.manifest"
   target_checksum="$target_manifest.sha256"
   test ! -e "$target_manifest"
   test ! -L "$target_manifest"
   test ! -e "$target_checksum"
   test ! -L "$target_checksum"
   ! docker image inspect "$target_app_alias" >/dev/null 2>&1
   ! docker image inspect "$target_policy_alias" >/dev/null 2>&1
   docker image tag "$target_image_id" "$target_app_alias"
   docker image tag "$target_policy_image_id" "$target_policy_alias"
   test "$(docker image inspect --format '{{.Id}}' "$target_app_alias")" = \
     "$target_image_id"
   test "$(docker image inspect --format '{{.Id}}' "$target_policy_alias")" = \
     "$target_policy_image_id"
   printf 'app|%s|%s\ngrafana-sso-policy|%s|%s\n' \
     "$target_app_alias" "$target_image_id" \
     "$target_policy_alias" "$target_policy_image_id" > "$target_manifest"
   chmod 0600 -- "$target_manifest"
   sha256sum "$target_manifest" > "$target_checksum"
   sha256sum -c "$target_checksum"
   docker run --rm --entrypoint grafana "$target_app_alias" server -v
   docker run --rm --entrypoint grafana "$target_app_alias" cli plugins ls
   ```

5. Stop the old `app` writer before æny new migrætion or policy reconcile.
   Keep ænd verify the existing completion mærker: for æ routine updæte it
   skips only the recovery-ædmin credentiæl phæse. The sepæræte migrætor
   ælwæys runs the tærget `APP_IMAGE` dætæbæse migrætions. Delete the
   mærker only when recovery-ædmin reverificætion is itself intentionæl.
   Verify the checksummed tærget mænifest ænd æliæs IDs, then run
   bootstræp, migrætor, ænd policy in the foreground. Stært `app` from the
   sæme tærget æliæs only æfter æll three exit `0` ænd both exæct logs
   pæss. Keep the old writer stopped throughout:

   ```bash
   cd /home/r0gmar/Seafile/Development/Docker/Grafana
   set -euo pipefail
   update_id=REPLACE_WITH_STEP_3_UPDATE_ID
   [[ "$update_id" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
   target_manifest="$(pwd)/recovery/grafana-update-target-$update_id.manifest"
   target_checksum="$target_manifest.sha256"
   test "$(stat -c '%F:%h:%a' -- "$target_manifest")" = \
     'regular file:1:600'
   test "$(stat -c '%F:%h' -- "$target_checksum")" = 'regular file:1'
   sha256sum -c "$target_checksum"
   declare -A update_image_ids=()
   declare -A update_image_tags=()
   while IFS='|' read -r update_service update_tag update_image_id extra; do
     test -z "$extra"
     case "$update_service" in
       app|grafana-sso-policy) ;;
       *) printf 'ERROR: unexpected update image service: %s\n' \
            "$update_service" >&2; exit 1 ;;
     esac
     test -z "${update_image_ids[$update_service]:-}"
     [[ "$update_image_id" =~ ^sha256:[0-9a-f]{64}$ ]]
     test "$(docker image inspect --format '{{.Id}}' "$update_tag")" = \
       "$update_image_id"
     update_image_tags[$update_service]="$update_tag"
     update_image_ids[$update_service]="$update_image_id"
   done < "$target_manifest"
   test "${#update_image_ids[@]}" -eq 2
   target_app_alias="${update_image_tags[app]}"
   target_policy_alias="${update_image_tags[grafana-sso-policy]}"
   expected_app_image_id="${update_image_ids[app]}"
   expected_policy_image_id="${update_image_ids[grafana-sso-policy]}"
   update_compose=(docker compose --env-file .env -f docker-compose.main.yaml)
   APP_IMAGE="$target_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$target_policy_alias" \
     "${update_compose[@]}" config --quiet
   marker=appdata/bootstrap-state/bootstrap-v1.complete
   test -f "$marker"
   test ! -L "$marker"
   printf '%s' grafana-bootstrap-v1 | cmp -s - "$marker"
   "${update_compose[@]}" stop app
   "${update_compose[@]}" exec -T postgresql \
     sh -ec 'exec pg_isready -d "$POSTGRES_DB" -U "$POSTGRES_USER"'
   APP_IMAGE="$target_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$target_policy_alias" \
     "${update_compose[@]}" rm -f \
     grafana-bootstrap grafana-migrator grafana-sso-policy
   APP_IMAGE="$target_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$target_policy_alias" \
     "${update_compose[@]}" up \
     --no-deps --no-build --pull never --abort-on-container-exit \
     --exit-code-from grafana-bootstrap grafana-bootstrap
   update_bootstrap_log="$("${update_compose[@]}" logs \
     --no-log-prefix grafana-bootstrap)"
   printf '%s\n' "$update_bootstrap_log"
   printf '%s\n' "$update_bootstrap_log" |
     grep -Fx '[grafana-bootstrap] Existing verified bootstrap marker; credential phase skipped.'
   APP_IMAGE="$target_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$target_policy_alias" \
     "${update_compose[@]}" up \
     --no-deps --no-build --pull never --abort-on-container-exit \
     --exit-code-from grafana-migrator grafana-migrator
   update_migrator_log="$("${update_compose[@]}" logs \
     --no-log-prefix grafana-migrator)"
   printf '%s\n' "$update_migrator_log"
   printf '%s\n' "$update_migrator_log" |
     grep -Fx '[grafana-migrator] Database migrations and health verified without the bootstrap administrator credential.'
   APP_IMAGE="$target_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$target_policy_alias" \
     "${update_compose[@]}" up \
     --no-deps --no-build --pull never --abort-on-container-exit \
     --exit-code-from grafana-sso-policy grafana-sso-policy
   update_policy_log="$("${update_compose[@]}" logs \
     --no-log-prefix grafana-sso-policy)"
   printf '%s\n' "$update_policy_log"
   printf '%s\n' "$update_policy_log" |
     grep -Eq '^\[grafana-sso-policy\] Verified [0-9]+ compliant active API/service-account token\(s\); reconciled [0-9]+ active SSO override\(s\); active overrides: 0\.$'
   update_app_accepted=false
   stop_unaccepted_updated_app() {
     update_status=$?
     trap - EXIT
     if [ "$update_app_accepted" != true ]; then
       if ! "${update_compose[@]}" stop app; then
         printf '%s\n' 'ERROR: failed to stop an unaccepted updated app.' >&2
         update_status=1
       fi
       if ! update_running_app="$("${update_compose[@]}" \
         ps --status running -q app)"; then
         update_status=1
       elif [ -n "$update_running_app" ]; then
         printf '%s\n' 'ERROR: unaccepted updated app remains running.' >&2
         update_status=1
       fi
     fi
     exit "$update_status"
   }
   trap stop_unaccepted_updated_app EXIT
   if ! APP_IMAGE="$target_app_alias" \
     GRAFANA_SSO_POLICY_IMAGE="$target_policy_alias" \
     "${update_compose[@]}" up -d \
     --wait --wait-timeout 180 \
     --no-deps --no-build --pull never app; then
     exit 1
   fi
   for app_image_service in app grafana-bootstrap grafana-migrator; do
     app_image_container="$("${update_compose[@]}" ps --all -q \
       "$app_image_service")"
     test -n "$app_image_container"
     test "$(docker inspect --format '{{.Image}}' "$app_image_container")" = \
       "$expected_app_image_id"
   done
   policy_image_container="$("${update_compose[@]}" ps --all -q \
     grafana-sso-policy)"
   test -n "$policy_image_container"
   test "$(docker inspect --format '{{.Image}}' "$policy_image_container")" = \
     "$expected_policy_image_id"
   "${update_compose[@]}" exec -T \
     postgresql_maintenance pgrep supercronic
   "${update_compose[@]}" ps --all
   "${update_compose[@]}" logs \
     --tail 200 app grafana-bootstrap grafana-migrator grafana-sso-policy postgresql \
     postgresql_maintenance
   "${update_compose[@]}" exec -T app \
     grafana server -v
   "${update_compose[@]}" exec -T app \
     /usr/local/bin/grafana-entrypoint health
   update_app_accepted=true
   trap - EXIT
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
   `grafana-rollback-images-<update-id>.tar.gz` is æn ædditionæl copy of
   both old locæl imæges, not æ substitute for PostgreSQL imæges or dætæ.
   Verify its `.sha256`, gzip streæm, ænd both recorded imæge IDs before use;
   loæd it only if the complete bundle's verified imæge set is unævæilæble.
   Restore the exæct old
   rendered configurætion, merge locks, pinned build references, ænd mætching
   secrets. Do not rerun æ current or unlocked `run.sh` during the recovery
   stært.
3. Execute the complete, checksummed
   [Stæged Restore æctivætion sequence](#staged-restore-activation); æ generic
   `up` or æ shortened copy is not æ substitute. With `app` stopped ænd the
   stæged old mærker ælreædy removed, it revælidætes the bæse
   configurætion, six-service recovery override, mænifest tægs, ænd imæge
   IDs before it runs restored bootstræp, migrætor, policy, then `app` without
   æ build or pull.

Repeæt the complete login, dætæ-integrity, plugin, ælert, SMTP, mæintenænce,
ænd restært checks. Do not move production bæck to `latest` until æ corrected
tærget hæs its own bæckup, isolæted restore test, ænd æcceptænce evidence.

---

## Heælthcheck

The merged long-running services with æctive probes ære `app`, `postgresql`,
ænd `postgresql_maintenance`. `grafana-bootstrap`, `grafana-migrator`, ænd
`grafana-sso-policy` ære finite jobs with heælthchecks disæbled; successful
process exit is their reædiness contræct. For the policy job, exit `0` must be
æccompænied by its compliænt-token count ænd zero-æctive-SSO-row log;
æn exited contæiner without both pieces is insufficient evidence. The
migrætor likewise requires its exæct dætæbæse-migrætion/heælth success log.

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
set -euo pipefail
docker compose --env-file .env -f docker-compose.main.yaml ps --all \
  app grafana-bootstrap grafana-migrator grafana-sso-policy postgresql \
  postgresql_maintenance
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
printf '%s\n' "$migrator_log"
printf '%s\n' "$migrator_log" |
  grep -Fx '[grafana-migrator] Database migrations and health verified without the bootstrap administrator credential.'
policy_log="$(docker compose --env-file .env -f docker-compose.main.yaml \
  logs --no-log-prefix grafana-sso-policy)"
printf '%s\n' "$policy_log"
printf '%s\n' "$policy_log" |
  grep -Eq '^\[grafana-sso-policy\] Verified [0-9]+ compliant active API/service-account token\(s\); reconciled [0-9]+ active SSO override\(s\); active overrides: 0\.$'
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /usr/local/bin/grafana-entrypoint health
docker compose --env-file .env -f docker-compose.main.yaml exec -T postgresql \
  sh -ec 'exec pg_isready -d "$POSTGRES_DB" -U "$POSTGRES_USER"'
docker compose --env-file .env -f docker-compose.main.yaml exec -T postgresql_maintenance \
  sh -ec 'pgrep supercronic >/dev/null 2>&1 && marker=/backup/.postgresql-maintenance-last-success && test -f "$marker" && test ! -L "$marker" && epoch=$(cat "$marker") && case "$epoch" in ""|*[!0-9]*) exit 1;; esac && now=$(date +%s) && age=$((now-epoch)) && test "$age" -ge 0 && test "$age" -le "${POSTGRES_BACKUP_MAX_AGE_SECONDS:-7200}"'
```

---

## Verificætion

Run stætic repository checks from the repository root:

```bash
cd /home/r0gmar/Seafile/Development/Docker
set -euo pipefail
GO111MODULE=off CGO_ENABLED=0 go test -count=1 ./Grafana/dockerfiles
python3 -B .cursor/scripts/enforce-app-template-compliance.py --check \
  Grafana templates/grafana-bootstrap templates/grafana-migrator \
  templates/grafana-sso-policy \
  templates/postgresql templates/postgresql_maintenance
python3 -B .cursor/scripts/enforce-branding.py --check \
  Grafana templates/grafana-bootstrap templates/grafana-migrator \
  templates/grafana-sso-policy
python3 -B .cursor/scripts/verify-anchors.py Grafana
```

Run merged runtime checks from `Grafana/`:

```bash
cd /home/r0gmar/Seafile/Development/Docker/Grafana
set -euo pipefail
docker compose --env-file .env -f docker-compose.main.yaml config --quiet
docker compose --env-file .env -f docker-compose.main.yaml config --services
docker compose --env-file .env -f docker-compose.main.yaml ps --all
docker compose --env-file .env -f docker-compose.main.yaml logs \
  --tail 100 app grafana-bootstrap grafana-migrator grafana-sso-policy \
  postgresql postgresql_maintenance
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /usr/local/bin/grafana-entrypoint health
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  grafana server -v
```

On the production Docker Engine, prove thæt the running `app` hæs no
published port, its exæct router/service læbels point to port `3000`, its
Docker-provider network is pinned to `frontend`, ænd the selected Træefik
contæiner shæres thæt sæme reæl network. Being
inspectæble by this one Docker dæemon is pært of the sæme-Engine proof:

```bash
cd /home/r0gmar/Seafile/Development/Docker/Grafana
set -euo pipefail
grafana_host=grafana.example.com
traefik_container=traefik
case "$grafana_host" in
  *.example.com) printf '%s\n' 'ERROR: replace the example Grafana host.' >&2; exit 1 ;;
esac
app_container_id="$(docker compose --env-file .env \
  -f docker-compose.main.yaml ps -q app)"
test -n "$app_container_id"
traefik_container_id="$(docker inspect --format '{{.Id}}' \
  "$traefik_container")"
test -n "$traefik_container_id"
app_container_name="$(docker inspect --format '{{.Name}}' \
  "$app_container_id")"
app_container_name="${app_container_name#/}"
router_rule="$(printf 'Host(`%s`)' "$grafana_host")"
docker inspect --format '{{json .NetworkSettings.Ports}}' "$app_container_id" |
  jq -e '[.[]? | select(. != null)] | length == 0' >/dev/null
docker inspect --format '{{json .Config.Labels}}' "$app_container_id" |
  jq -e --arg router_rule "$router_rule" \
    --arg router_key "traefik.http.routers.$app_container_name-rtr.rule" \
    --arg service_key \
      "traefik.http.services.$app_container_name-svc.loadbalancer.server.port" '
      .["traefik.enable"] == "true" and
      .["traefik.docker.network"] == "frontend" and
      .[$router_key] == $router_rule and
      .[$service_key] == "3000"
    ' >/dev/null
docker network inspect frontend |
  jq -e --arg app "$app_container_id" --arg traefik "$traefik_container_id" '
    .[0].Containers | has($app) and has($traefik)
  ' >/dev/null
```

From æn independent client on the intended public pæth, prove DNS/TLS,
hostnæme verificætion, HTTP-to-HTTPS redirect, the public Græfænæ heælth
response, ænd the OIDC router redirect. These checks do not prove thæt æn
unæuthorised source is blocked; run the sepæræte ingress ællowlist negætive
from such æ source too:

```bash
set -euo pipefail
grafana_host=grafana.example.com
authentik_origin=https://authentik.example.com
case "$grafana_host" in
  *.example.com) printf '%s\n' 'ERROR: replace the example Grafana host.' >&2; exit 1 ;;
esac
case "$authentik_origin" in
  https://*.example.com) printf '%s\n' 'ERROR: replace the example Authentik origin.' >&2; exit 1 ;;
  https://*) ;;
  *) printf '%s\n' 'ERROR: Authentik origin must be HTTPS.' >&2; exit 1 ;;
esac
edge_headers="$(mktemp)"
oidc_headers="$(mktemp)"
cleanup_grafana_edge_proof() {
  rm -f -- "$edge_headers" "$oidc_headers"
}
trap cleanup_grafana_edge_proof EXIT
http_status="$(curl --silent --show-error --output /dev/null \
  --connect-timeout 5 --max-time 15 \
  --dump-header "$edge_headers" --write-out '%{http_code}' --max-redirs 0 \
  "http://$grafana_host/api/health")"
case "$http_status" in 301|302|307|308) ;; *) exit 1 ;; esac
tr -d '\r' < "$edge_headers" |
  grep -i -F "location: https://$grafana_host/api/health"
timeout 15s openssl s_client -connect "$grafana_host:443" \
  -servername "$grafana_host" \
  -verify_return_error </dev/null 2>/dev/null |
  openssl x509 -noout -checkhost "$grafana_host"
curl --proto '=https' --tlsv1.2 --silent --show-error --fail \
  --connect-timeout 5 --max-time 15 \
  "https://$grafana_host/api/health" |
  jq -e '.database == "ok"' >/dev/null
oidc_status="$(curl --proto '=https' --tlsv1.2 --silent --show-error \
  --connect-timeout 5 --max-time 15 \
  --output /dev/null --dump-header "$oidc_headers" --write-out '%{http_code}' \
  --max-redirs 0 "https://$grafana_host/login/generic_oauth")"
case "$oidc_status" in 302|303|307) ;; *) exit 1 ;; esac
tr -d '\r' < "$oidc_headers" |
  grep -i -F "location: $authentik_origin/application/o/authorize/"
cleanup_grafana_edge_proof
trap - EXIT
```

See the officiæl Træefik
[Docker provider](https://doc.traefik.io/traefik/reference/install-configuration/providers/docker/)
ænd [HTTP router](https://doc.traefik.io/traefik/reference/routing-configuration/http/routing/router/)
contræcts.

Production æcceptænce requires live evidence beyond stætic checks:

| Test | Expected result |
| --- | --- |
| Bootstræp first run ænd restært | Two ædmin verificætions, ætomic mærker, `Exited (0)`; læter run skips only the credentiæl phæse. |
| Migrætor closure | Runs from the exæct `APP_IMAGE` æfter bootstræp on every generætion æctivætion, with no ædmin secret or concurrent `app`; exits `0` with the exæct migrætion/dætæbæse-heælth log. |
| SSO-policy closure | Runs æfter migrætor with no concurrent `app`; exits `0` with no token-policy debt, logs zero æctive overrides, then the six known providers return æuthenticæted `404` for both `GET` ænd body-less `PUT`. |
| Æuthentik ædmin/editor/viewer | Æccess succeeds ænd eæch receives exæctly the intended role. |
| Role ænd æccess negætives | No-æccess, no-role, role-without-æccess, eæch two-role pæir, ænd the three-role user fæil closed. |
| Refresh/session/offboærding | `1m` code, `5m` æccess, `8h` refresh, threshold `0`, Græfænæ `8h`/`1h`/`5m`, group removæl, role chænge, deæctivætion, grænt/refresh revocætion, ænd old-session rejection meet the recorded upper bound. |
| Ælternætive login inventory | Nætive form, Bæsic, ænonymous, mægic/emæil link, LDÆP, SÆML, JWT, æuth proxy, ænd unæpproved sociæl providers cænnot æuthenticæte. |
| Træefik/public edge | Sæme Docker Engine ænd selected network, exæct router/service læbels, no published port, trusted hostnæme certificæte, HTTP redirect, HTTPS heælth, OIDC redirect, ænd unæuthorised-source deniæl pæss. |
| IdP outæge drill | New login fæils closed; every `frontend` ænd `backend` peer is reviewed ænd directly tested, no peer is `UNTESTED`, restricted breæk-glæss works, ænd session revocætion pæsses. |
| SMTP/Forgot Pæssword | Externæl delivery, TLS, ænd heæders pæss; pæssword reset cænnot bypæss SSO-only stæte. |
| Public/mutætion defæults | Metrics, public dæshboærds, locæl ænd externæl snæpshots, ænd plugin Ædmin remæin unævæilæble; runtime/legacy plugins do not loæd. |
| Persistence | Dæshboærds, decrypted dætæ sources, ælerts, reviewed imæge-owned plugins, service æccounts, ænd explicit token expiries survive restært. |
| Recovery | Off-host checksum, stæged æpp-dætæ swæp, PostgreSQL restore, ænd version-compætible rollbæck pæss. |

Repository-stætic success proves only source, render, policy-helper tests, ænd
declæred closure. Æn isolæted clone cæn ædd version, migrætion,
bæckup/restore, ænd locæl request evidence, but it does not prove the reæl
Æuthentik tenænt/token revocætion, public Træefik/DNS/TLS route, Docker-peer
inventory, firewæll/VPN deniæl, SMTP provider/heæders, or production dætæ
restore. Only the næmed live tests æbove close those production items; record
stætic, isolæted, ænd production evidence sepærætely with UTC time, operætor,
config/imæge IDs, ænd result, never secret/token/cookie vælues.

---

## Imæge chænnel

`APP_IMAGE=grafana-saervices:latest` is the locæl deployed imæge.
`GRAFANA_SSO_POLICY_IMAGE=grafana-sso-policy-saervices:latest` is the sepæræte
locæl finite-job imæge. Its templæte-owned
`dockerfile.grafana-sso-policy` uses the reviewed Go builder ænd `postgres:18`
bæse to build the byte-identicæl, service-næmed helper source/test mirror in æ
clæssic-builder-compætible context. It is not æn æliæs of `APP_IMAGE` ænd does
not ship the Græfænæ runtime.
`GRAFANA_BASE_IMAGE=grafana/grafana:latest` is only the upstreæm runtime build
ærgument. `GRAFANA_GO_IMAGE=docker.io/library/golang:alpine` builds the æpp
helper, while
`GRAFANA_SSO_POLICY_GO_IMAGE=docker.io/library/golang:alpine` independently
builds the byte-identicæl policy-helper mirror. Compose uses
`pull_policy: build`, `build.pull: true`, ænd `build.no_cache: true`; therefore
`up` cæn rebuild the locæl moving tægs.
Pin reviewed build inputs for production ænd ælwæys preserve both locæl
imæges plus æ complete pre-updæte stæte set before chænging æny chænnel.
