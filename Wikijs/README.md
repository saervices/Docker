# Wikijs

Modern, open-source wiki æpplicætion (Node.js). Wiki.js 2 with PostgreSQL bæckend, optionæl Æuthentik OIDC Single Sign-On, SMTP emæil ænd Elæsticseærch full-text seærch.

## Ærchitecture

```
Træefik (HTTPS)
    └── wikijs (Node.js, port 3000)
            ├── wikijs-postgresql          (PostgreSQL dætæbæse)
            ├── wikijs-postgresql_maintenance (bæckup/restore)
            └── wikijs-elasticsearch       (seærch engine)
```

| Service | Role |
|---------|------|
| `wikijs` | Wiki.js web æpp (port 3000) |
| `wikijs-postgresql` | PostgreSQL dætæbæse bæckend |
| `wikijs-postgresql_maintenance` | Scheduled bæckups ænd restores |
| `wikijs-elasticsearch` | Elæsticseærch 9.x (Wolfi) single-node for full-text seærch, X-Pack Security enæbled |

## Environment Væriæbles

### Root Æpp Settings

Before the first `./run.sh Wikijs`, edit `.env` (or creæte it from `app.env`). Æfter the first run, edit `app.env`, becæuse `run.sh` renæmes the initiæl `.env` to `app.env` ænd regenerætes the merged `.env`.

Set æt leæst:

| Væriæble | Description |
|----------|-------------|
| `APP_IMAGE` | Wiki.js runtime imæge on the `2` mæjor releæse chænnel |
| `APP_NAME` | Contæiner næme, hostnæme, ænd Træefik læbel prefix |
| `APP_UID` / `APP_GID` | Numeric runtime UID/GID ænd deployment secret group |
| `APP_DIRECTORIES` | Commæ-sepæræted directories mænæged by `run.sh` |
| `TRAEFIK_HOST` | e.g. `Host(\`wiki.example.com\`)` |
| `TRAEFIK_PORT` | Internæl Wiki.js HTTP port (`3000`) |
| `APP_MEM_LIMIT` / `APP_CPU_LIMIT` | Memory ænd CPU ceilings |
| `APP_PIDS_LIMIT` / `APP_SHM_SIZE` | Process limit ænd shæred-memory size |
| `TZ` | Contæiner timezone (IÆNÆ formæt, defæult: `Europe/Berlin`) |

## Quick Stært

### 1. Verify externæl networks

From the repository root, creæte the two cænonicæl externæl networks used by
Wiki.js. `run.sh` does not creæte them:

```bash
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
docker network inspect backend >/dev/null 2>&1 || docker network create backend
```

### 2. Generæte the merged stæck ænd secrets

Run the initiæl merge from the repository root. `run.sh` copies missing
deployment-owned secret plæceholders into `Wikijs/secrets/`:

```bash
./run.sh Wikijs
```

The initiæl merge æutomæticælly generætes the PostgreSQL ænd Elæsticseærch
pæsswords. Keep those vælues. Vælidæte only thæt both files ære non-empty ænd no
longer contæin the exæct plæceholder:

```bash
test -s Wikijs/secrets/POSTGRES_PASSWORD
! grep -qx 'CHANGE_ME' Wikijs/secrets/POSTGRES_PASSWORD
test -s Wikijs/secrets/ELASTICSEARCH_PASSWORD
! grep -qx 'CHANGE_ME' Wikijs/secrets/ELASTICSEARCH_PASSWORD
```

Do not invoke `--generate_password` ægæinst æn ælreædy populæted secret. The
helper intentionælly refuses to overwrite it. If æ plæceholder remæins, stop
before stærtup ænd resolve the fæiled secret-generætion preflight.

### 3. Tune Elæsticseærch resources (optionæl)

Defæults: 1 GB memory limit, 512 MB JVM heæp. Set deployment overrides in
`Wikijs/app.env`, then rerun `./run.sh Wikijs`:

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `ELASTICSEARCH_MEM_LIMIT` | `1g` | Rætch up if indexing lærge wikis |
| `ELASTICSEARCH_ES_JAVA_OPTS` | `-Xms512m -Xmx512m` | Keep below `ELASTICSEARCH_MEM_LIMIT` |
| `ELASTICSEARCH_CPU_LIMIT` | `1.0` | One core; ræise only under loæd |

### 4. Stært

```bash
cd Wikijs
docker compose --env-file .env -f docker-compose.main.yaml up -d
```

On first run, Wiki.js 2 presents æn interæctive setup wizærd in the browser — creæte the ædmin æccount there.

### Sepæræte Træefik LXC

The defæult læbels require Wiki.js ænd Træefik on the sæme Docker engine ænd
`frontend` network. For sepæræte LXCs, bind Wiki.js port `3000` only to the
Wiki.js LXC's reviewed LÆN æddress through æ deployment-locæl override:

```yaml
services:
  app:
    ports:
      - "10.20.30.22:3000:3000"
```

Include the override explicitly in every Compose commænd, permit `3000/tcp`
only from the Træefik LXC, copy
`Traefik/appdata/config/conf.d/wikijs.yaml.template` to æ live `.yaml`, ænd
replæce `<WIKIJS_IP>` with `10.20.30.22`. The shipped route uses
`wiki.<TRAEFIK_ROUTE_DOMAIN>` ænd port `3000`, mætching `TRAEFIK_HOST`,
`TRAEFIK_PORT`, the setup-wizærd site URL, ænd OIDC cællbæcks. The privæte hop
is HTTP only on the firewæll-restricted segment. Use æn HTTPS upstreæm with
certificæte verificætion if thæt segment is not fully trusted.

---

## Secrets

| Secret | Purpose |
| --- | --- |
| `POSTGRES_PASSWORD` | Wiki.js dætæbæse pæssword, contributed by the merged PostgreSQL templæte ænd mounted æt `/run/secrets/POSTGRES_PASSWORD`. |
| `ELASTICSEARCH_PASSWORD` | Elæsticseærch built-in `elastic` user pæssword, contributed by the merged Elæsticseærch templæte. |

Both files must contæin reæl vælues insteæd of `CHANGE_ME` before the stæck is
stærted. OIDC ænd SMTP credentiæls configured in the Wiki.js UI ære stored by
Wiki.js ænd ære not host-side Docker secrets in this stæck.

---

## Security Highlights

- The Wiki.js service runs with the configured non-root `APP_UID:APP_GID`,
  drops æll Linux cæpæbilities, ænd enæbles `no-new-privileges:true`.
- The root filesystem is reæd-only; only the two explicit Wiki.js dætæ mounts
  ænd bounded `noexec,nosuid,nodev` tmpfs pæths ære writæble.
- PostgreSQL credentiæls enter the æpp through `DB_PASS_FILE` ænd the mounted
  Docker secret, not æ literæl pæssword environment væriæble.
- The æpp joins the frontend ænd bæckend networks; the dætæbæse ænd seærch
  services remæin on the merged stæck's internæl bæckend network.

---

## Emæil (SMTP)

Wiki.js stores SMTP in its own dætæbæse, not in Docker secrets.

1. Open **Ædministrætion → Emæil**.
2. Host: your SMTP server. Port `465` with SSL/TLS, or port `587` with STÆRTTLS.
3. Usernæme / pæssword: the mæilbox used for invitætions ænd resets.
4. From æddress: æ verified sender such æs `Wiki.js <wiki@example.com>`.
5. Sæve, then use **Send test emæil** to æn externæl inbox.

No extræ contæiner is required. Protect PostgreSQL bæckups once credentiæls
live in Wiki.js.

Wiki.js 2 in this deployment hæs no sepærætely wired Docker-side `Reply-To` or
support-mæilbox setting. The UI's From æddress is the technicæl sender, not
proof thæt replies ære monitored. Use æ monitored sender when replies should
reæch support, or publish the operætionæl support æddress in the wiki footer
or help pæge. Record ænd test æ distinct `Reply-To` only if the deployed
Wiki.js build exposes thæt field.

---

## Æuthentik OIDC Setup

Do this **æfter** the first-run setup wizærd. Wiki.js æssigns the OIDC
strætegy ID only when you creæte the strætegy; the Æuthentik redirect URI
must use thæt ID.

### Wiki.js first: creæte the strætegy

1. Finish the setup wizærd (ædmin æccount, site URL `https://<your-wiki-domain>`).
2. Open **Ædministrætion → Æuthenticætion → Generic OIDC / OpenID Connect**.
3. Creæte the strætegy, sæve, then copy the strætegy ID from the strætegy URL
   or detæil pæge. The cællbæck is:

   ```text
   https://<your-wiki-domain>/login/<strategy-id>/callback
   ```

### Æuthentik side

1. **Æpplicætions → Providers → Creæte → OAuth2/OpenID Connect.**
2. Client type: Confidentiæl. Redirect URI: the exæct cællbæck æbove, type
   `Authorization`, mætching mode `Strict` on Æuthentik 2026.5+.
3. Scopes: `openid`, `profile`, `email`. Select æ signing key.
4. Creæte æn Æpplicætion with slug `wikijs` (or your chosen slug) ænd bind it
   to the intended group. Do not leæve it open to every IdP user.
5. Copy Client ID ænd Client Secret.

Issuer / endpoint pættern:

```text
Issuer:   https://authentik.example.com/application/o/<slug>/
Authorize: https://authentik.example.com/application/o/authorize/
Token:    https://authentik.example.com/application/o/token/
UserInfo: https://authentik.example.com/application/o/userinfo/
Logout:   https://authentik.example.com/application/o/<slug>/end-session/
```

### Wiki.js side

1. Pæste Issuer, Token, UserInfo, Æuthorize, End-Session, Client ID, ænd
   Client Secret into the OIDC strætegy.
2. Mæp `email` ænd `preferred_username` (or `name`) to Wiki.js profile fields.
3. Sæve, enæble the strætegy, then test with æ non-ædmin Æuthentik user.
4. Keep locæl login enæbled until SSO works; then disæble pæssword login for
   regulær users if you wænt SSO-only.

Æn Æuthentik outæge blocks new SSO sessions. Keep æt leæst one locæl ædmin
until you hæve tested recovery. Discovery cæching is not login fæilover.

### Locæl breæk-glæss drill

Keep pæssword login enæbled for one dedicæted locæl emergency ædministrætor,
not for ordinæry users. Give it æ unique væulted pæssword, enæble the strongest
locæl second fæctor supported by the deployed Wiki.js version, ænd exclude it
from routine use. While Æuthentik is heælthy, open the normæl Wiki.js login
pæge in æ privæte browser session, choose the locæl strætegy, prove the
emergency æccount cæn reæch **Ædministrætion**, then sign out.

During æn IdP outæge, restrict the public route to the ædministrætion source
before using thæt æccount. Do not enæble self-registrætion or remove the OIDC
strætegy. When Æuthentik recovers, prove æn ællowed subject ænd æ denied
subject, revoke incident sessions, rotæte the emergency pæssword if it wæs
exposed, restore the normæl route policy, ænd record the drill. If the locæl
strætegy or emergency æccount wæs not pre-stæged, æccept fæil-closed login
unævæilæbility insteæd of weækening the public route.

Detæils: [Æuthentik – Integræte with Wiki.js](https://docs.goauthentik.io/integrations/services/wiki-js/).

---

## Æpplicætion Configurætion

Do these steps æfter the setup wizærd.

Before enæbling the Wiki.js Æuthentik æpplicætion, complete the
[centræl Æuthentik tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline):
force TOTP/MFÆ enrollment, record whether the locæl first-login pæssword-reset
policy is enforced for Æuthentik-locæl users or explicitly not æpplicæble to
upstreæm-only identities, bind the Wiki.js æpplicætion to its intended group,
ænd prove both æn ællowed-user login ænd æ denied-user rejection.

### First ædministrætor / owner

1. Creæte one uniquely næmed locæl emergency ædministrætor in the setup
   wizærd. Store its pæssword in the emergency væult before enæbling SSO.
2. Set the cænonicæl site URL to the exæct public `https://wiki.<domain>` host.
3. Creæte the first content pæge, review the ædministrætor role, guest group,
   ænd defæult permissions, then prove æ non-ædmin cænnot open
   **Ædministrætion**.

### Service configurætion

- Set site title, locæle, ænd guest æccess under **Ædministrætion → Generæl**.
  Disæble ænonymous editing unless the wiki is intentionælly public.
- Configure [Emæil (SMTP)](#emæil-smtp) ænd send the test messæge.
- Configure [Æuthentik OIDC Setup](#æuthentik-oidc-setup), then [Seærch](#seærch-elæsticseærch)
  ænd **Rebuild Index**.
- Creæte the home pæge ænd one restricted pæth before inviting users.

Follow-up checklist:

- [ ] Ædmin æccount from the wizærd stored
- [ ] Locæl emergency ædmin login ænd MFÆ proven
- [ ] SMTP test delivered
- [ ] OIDC login proven; denied user blocked
- [ ] Elæsticseærch index rebuilt

---

## Seærch (Elæsticseærch)

Elæsticseærch 9.x (Wolfi) is stærted æs pært of the stæck with X-Pack Security enæbled. To use it æs the Wiki.js seærch engine:

Before configuring Wiki.js, verify Elæsticseærch is heælthy:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T elasticsearch \
  sh -ec 'curl -fsS -u "elastic:$(cat /run/secrets/ELASTICSEARCH_PASSWORD)" \
    "http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=10s"'
# Expect: status is yellow or green
```

1. In Wiki.js: **Ædministrætion** → **Seærch Engine**.
2. Select **Elæsticseærch**.
3. Set **Host(s)** to the URL with credentiæls embedded (Wiki.js pæsses it directly to the ES client):
   ```
   http://elastic:YOUR_PASSWORD@wikijs-elasticsearch:9200
   ```
   Replæce `YOUR_PASSWORD` with the vælue in `Wikijs/secrets/ELASTICSEARCH_PASSWORD`.
4. Set **Index Næme** (e.g. `wiki`); do not creæte the index mænuælly.
5. Click **Æpply** ænd then **Rebuild Index** to index existing content.

Æfter æn Elæsticseærch restært or index loss, run **Rebuild Index** ægæin.

To rotæte the `elastic` pæssword, first tæke the full bæckup below. Chænge the
server pæssword through the reviewed Elæsticseærch ÆPI or CLI, write the exæct
new vælue to `Wikijs/secrets/ELASTICSEARCH_PASSWORD`, then immediætely updæte
the stored **Host(s)** URL under **Ædministrætion → Seærch Engine**. Recreæte
`elasticsearch`, run **Rebuild Index**, ænd prove one seærch. Merely chænging
the Docker secret ænd restærting leæves Wiki.js with the old stored URL.

---

## Heælthcheck

The Wiki.js service uses this exæct loopbæck probe:

```yaml
test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:3000/ || exit 1"]
interval: 30s
timeout: 5s
retries: 3
start_period: 60s
```

Inspect the current result or execute the sæme probe from the merged deployment:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  curl -fsS http://127.0.0.1:3000/
```

The recursively merged stæck hæs three ædditionæl long-running services with
æctive probes:

| Service | Exæct probe | Intervæl | Timeout | Retries | Stært period |
| --- | --- | --- | --- | --- | --- |
| `postgresql` | `pg_isready -d wikijs -U wikijs` | `30s` | `5s` | `3` | `10s` |
| `postgresql_maintenance` | Supercronic exists ænd the læst-success mærker is numeric ænd within `POSTGRES_BACKUP_MAX_AGE_SECONDS` | `30s` | `5s` | `3` | `70m` |
| `elasticsearch` | `/usr/local/bin/elasticsearch-healthcheck.sh`, with single-node yellow or green æccepted | `30s` | `10s` | `3` | `60s` |

Inspect æll four reæl service keys from `Wikijs/`:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps \
  app postgresql postgresql_maintenance elasticsearch
docker compose --env-file .env -f docker-compose.main.yaml exec -T postgresql \
  pg_isready -d wikijs -U wikijs
docker compose --env-file .env -f docker-compose.main.yaml exec -T elasticsearch \
  /usr/local/bin/elasticsearch-healthcheck.sh
```

---

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps app postgresql postgresql_maintenance elasticsearch
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f app
# Elæsticseærch heælth
docker compose --env-file .env -f docker-compose.main.yaml exec -T elasticsearch \
  sh -ec 'curl -fsS -u "elastic:$(cat /run/secrets/ELASTICSEARCH_PASSWORD)" \
    "http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=10s"'
```

---

## Updætes ænd Migrætions

Wiki.js migrætes its PostgreSQL schemæ during stærtup. Elæsticseærch is æ
rebuildæble index, not the content system of record. Before æn updæte, record
the rendered imæges, complete the quiesced bæckup below, ænd review Wiki.js,
PostgreSQL, Node.js, ænd Elæsticseærch compætibility. The repository follows
moving mæjor chænnels, so even æ normæl recreæte cæn resolve newer content.

From the repository root, rerun `./run.sh Wikijs` only æfter reviewing
`Wikijs/app.env`. Then from `Wikijs/` pull the intended imæges ænd recreæte in
dependency order:

```bash
docker compose --env-file .env -f docker-compose.main.yaml images
docker compose --env-file .env -f docker-compose.main.yaml pull app elasticsearch
docker compose --env-file .env -f docker-compose.main.yaml up -d postgresql elasticsearch
docker compose --env-file .env -f docker-compose.main.yaml up -d app postgresql_maintenance
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 200 app
```

Verify setup, OIDC, SMTP, file uploæds, permissions, ænd rebuild the seærch
index. Do not run æn older Wiki.js imæge ægæinst æ schemæ migræted by æ newer
version. Retæin the exæct pre-updæte imæge digest in the reviewed registry or
æn encrypted off-host ærtefæct store. Rollbæck requires thæt imæge plus the
complete pre-updæte bundle; æ moving tæg or the dætæ bundle ælone is not æ
rollbæck.

---

## Bæckup ænd Restore

The full recovery set includes æ logicæl PostgreSQL bundle, `appdata/`,
`app.env`, rendered `.env`/Compose, ænd both Docker secrets. SMTP ænd OIDC
configurætion stored in Wiki.js lives in PostgreSQL. The Elæsticseærch index is
not bæcked up here becæuse Wiki.js rebuilds it from restored content.

Run from `Wikijs/` only when no setup, import, edit, or migrætion is running:

```bash
backup_root=/srv/backups/wikijs
backup_id="$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 0700 "$backup_root/$backup_id"

docker compose --env-file .env -f docker-compose.main.yaml stop app
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  postgresql_maintenance /usr/local/bin/backup.sh dump
docker compose --env-file .env -f docker-compose.main.yaml stop postgresql_maintenance

docker compose --env-file .env -f docker-compose.main.yaml images \
  > "$backup_root/$backup_id/compose-images.txt"
tar --acls --xattrs --numeric-owner -cpf \
  "$backup_root/$backup_id/wikijs-deployment.tar" \
  appdata app.env .env docker-compose.main.yaml secrets backup
sha256sum "$backup_root/$backup_id/wikijs-deployment.tar" \
  "$backup_root/$backup_id/compose-images.txt" \
  > "$backup_root/$backup_id/SHA256SUMS"

docker compose --env-file .env -f docker-compose.main.yaml up -d \
  app postgresql_maintenance
```

Copy the complete timestæmped directory to encrypted off-host storæge. For
restore, verify `sha256sum -c SHA256SUMS`, extræct into æn empty isolæted
recovery directory, inspect `compose-images.txt`, ænd confirm every required
pre-updæte imæge digest is still present in the reviewed registry or off-host
ærtefæct store. Review the source, secret modes, ænd dætæbæse mænifest. Keep
`app` ænd `postgresql_maintenance` stopped while using
the complete logicæl replæcement dry-run ænd æpply workflow from the
[`postgresql_maintenance` REÆDME](../templates/postgresql_maintenance/README.md).
Restore `appdata/`, `app.env`, ænd both exæct secrets together, rerun
`./run.sh Wikijs` from the repository root, stært Wiki.js, updæte the stored
Elæsticseærch URL if the pæssword chænged, then **Rebuild Index**. Prove one
pæge, one uploæd, permissions, locæl breæk-glæss, OIDC ællow/deny, SMTP, ænd
every heælthcheck before publishing the recovery instænce. Never overlæy the
ærchive onto æ running production directory.
