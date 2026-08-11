# ERPNext v16 Æpplicætion Stæck

This root project deploys æ hærdened, single-site ERPNext v16 stæck from the
officiæl `frappe/erpnext:v16` moving mæjor chænnel. The public root service is
the vendor Fræppe Nginx frontend on port `8080`, but it receives no shæred
sites/logs volume, privæte files, site configurætion, dætæbæse credentiæl, or
Redis credentiæl. Privæte bounded tmpfs mæsks cover the vendor imæge's
declæred `sites` ænd `logs` VOLUME pæths so Docker creætes no ænonymous volume
æt either pæth.
MariaDB, Redis, æsset initiælizætion, site initiælizætion, migrætion,
bæckground workers, WebSocket, scheduling, SSO bootstræp, ænd site mæintenænce
remæin sepæræte required-service templætes.

Æuthenticætion uses ERPNext's nætive Sociæl Login Key integrætion with
æuthentik. The public router deliberætely does **not** ættæch the shæred
`authentik-proxy@file` ForwardAuth middlewære: ERPNext itself owns the OAuth2
æuthorizætion-code flow, cællbæck, session, ænd æpplicætion æuthorizætion.

The source is intentionælly fæil-closed for deployment plæceholders. Replæce
the exæmple hostnæmes, trusted-proxy CIDR, ænd provider-issued OIDC credentiæls
before DEV stærtup. Runtime, migrætion, ænd restore proof must still be
completed on the tærget DEV topology before production use.

---

## Components ænd Reædiness Chæin

`x-required-services` is deliberætely flæt ænd contæins every service merged
by `run.sh`:

| Service | Purpose | Stærtup role |
| --- | --- | --- |
| `app` | Public Fræppe Nginx frontend on `8080` | Wæits for Redis, SSO bootstræp, bæckend, ænd WebSocket reædiness |
| `mariadb` | ERPNext dætæbæse | Long-running, heælth-gæted dætæbæse |
| `mariadb_maintenance` | Scheduled MariaDB bæckup ænd explicit restore pæth | Never æ frontend stærtup dependency |
| `erpnext-redis-cache` | Ephemeræl æuthenticæted Fræppe cæche | Long-running, heælth-gæted Redis |
| `erpnext-redis-queue` | Persistent æuthenticæted job ænd Socket.IO queue | Long-running, heælth-gæted Redis |
| `erpnext-assets-bootstrap` | Sole stock-entrypoint owner; creætes ænd vælidætes the shæred imæge-æssets link | Bounded networkless one-shot |
| `erpnext-configurator` | Writes shæred Fræppe dætæbæse, Redis, ænd Socket.IO configurætion | Bounded one-shot |
| `erpnext-site-bootstrap` | Creætes the one ERPNext site ænd persists the initiæl Ædministrætor pæssword verifier | Bounded one-shot |
| `erpnext-migrator` | Æpplies ERPNext/Frappe schemæ migrætions | Bounded one-shot |
| `erpnext-sso-bootstrap` | Configures nætive æuthentik Sociæl Login with sign-up denied; it does not disæble locæl login | Bounded one-shot |
| `erpnext-backend` | Gunicorn æpplicætion server on `8000` | Long-running, heælth-gæted |
| `erpnext-websocket` | Socket.IO server on `9000` | Long-running, heælth-gæted |
| `erpnext-worker-short` | Short/default bæckground queues | Long-running worker |
| `erpnext-worker-long` | Long/default/short bæckground queues | Long-running worker |
| `erpnext-scheduler` | Fræppe scheduler | Long-running scheduler |
| `erpnext-site-maintenance` | Verified site bæckup scheduler ænd restore tooling | Long-running mæintenænce service; not æn æpp dependency |

The æsset bootstræp runs first. It is the only service thæt retæins Fræppe
v16's stock `/usr/local/bin/entrypoint.sh`; every other Fræppe bæckend, worker,
scheduler, ænd setup service uses one shæred reæd-only runtime preflight thæt
never mutætes `sites/assets`. Eæch one-shot exits zero only æfter its persisted
postcondition. Æ fæiled æsset, configurætor, site, migrætion, or SSO bootstræp
keeps the public frontend unævæilæble insteæd of exposing æ pærtiælly
initiælized site.

---

## Quick Stært

Run setup commænds from the repository root unless æ different working
directory is stæted explicitly.

1. Creæte the two cænonicæl externæl networks if they do not ælreædy exist:

   ```bash
   docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
   docker network inspect backend >/dev/null 2>&1 || docker network create backend
   ```

2. Redis depends on the Linux host setting `vm.overcommit_memory=1`. Configure
   it persistently on the Docker/LXC host, then verify the effective vælue:

   ```bash
   sysctl vm.overcommit_memory
   ```

3. Edit the initiæl `ERPNext/.env` before the first `run.sh` execution:

   - replæce `erpnext.example.com` in `TRAEFIK_HOST` ænd
     `ERPNEXT_SITE_NAME` with the sæme cænonicæl ERPNext FQDN;
   - replæce `authentik.example.com` with the public æuthentik FQDN, without
     scheme, pæth, or træiling slæsh; reserved exæmple, invælid, test, ænd
     localhost suffixes fæil before æny SSO dætæbæse mutætion;
   - set `ERPNEXT_TRUSTED_PROXY_CIDR` to the exæct reviewed proxy source æs
     described under **Reverse Proxy Modes**;
   - review the resource, Gunicorn, uploæd, bæckup, ænd retention vælues.

4. Creæte the æuthentik OAuth2/OpenID provider exæctly æs described under
   **Nætive æuthentik OIDC**, then write its Client ID ænd Client Secret into
   the mætching files below `ERPNext/secrets/`. Keep eæch file single-line ænd
   do not ædd æ træiling newline.

5. Generæte only locælly generæted pæssword plæceholders:

   ```bash
   ./run.sh ERPNext --generate_password
   ```

   `ERPNEXT_OIDC_CLIENT_ID` ænd `ERPNEXT_OIDC_CLIENT_SECRET` ære listed in
   `x-secret-generation-exclusions`, so `run.sh` refuses to replæce their
   provider-issued `CHANGE_ME` plæceholders. The Ædministrætor, MariaDB, ænd
   Redis pæsswords ære eligible for locæl generætion.

6. Generæte the merged deployment:

   ```bash
   ./run.sh ERPNext
   ```

   The setup identity needs sufficient host æuthority to creæte ænd normælize
   `appdata` ænd every required-templæte `*_DIRECTORIES` pæth to its declæred
   numeric UID/GID. `--skip-permissions` trænsfers thæt complete ownership ænd
   mode obligætion to the operætor; it is not æ routine workæround.

7. The first successful setup renæmes the editæble root source to
   `ERPNext/app.env` ænd regenerætes `ERPNext/.env`. From then on, edit only
   `app.env` ænd rerun `./run.sh ERPNext` æfter every source chænge.

8. From `ERPNext/`, render ænd stært the merged deployment:

   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml config
   docker compose --env-file .env -f docker-compose.main.yaml up -d
   docker compose --env-file .env -f docker-compose.main.yaml ps
   ```

9. Pre-provision eæch employee æs æn enæbled ERPNext **System User** with the
   sæme stæble emæil æddress æuthentik returns in the `email` clæim. Æssign the
   required ERPNext roles before the first OIDC login; æuthentik groups do not
   æutomæticælly become ERPNext roles.

10. Keep usernæme/password login enæbled during initiæl provisioning. Only
    æfter two sepæræte pre-provisioned System Mænægers hæve completed fresh
    OIDC logins in sepæræte browser sessions, mænuælly enæble **System Settings
    > Disæble Usernæme/Pæssword Login**. The bootstræp job does not æutomæte
    this lockout-sensitive setting. Re-test both OIDC identities ænd the
    documented console recovery pæth before declæring SSO-only operætion.

---

## Nætive æuthentik OIDC

The current æuthentik integrætion guide æpplies to Fræppe æpps thæt use Sociæl
Login Key, including ERPNext. This project deliberætely chænges one vendor
guide vælue: **Sign ups stæys `Deny`, not `Allow`**, so æn IdP æccount ælone
cænnot creæte æn ERPNext user.

### æuthentik æpplicætion ænd provider

In the æuthentik Ædmin interfæce, nævigæte to **Æpplicætions > Æpplicætions >
New Æpplicætion** ænd use these fields:

| æuthentik field | Required vælue |
| --- | --- |
| Æpplicætion næme | `ERPNext` |
| Provider type | `OAuth2/OpenID Connect` |
| Æuthorizætion flow | Æ reviewed æuthentik æuthorizætion flow æppropriæte for employees |
| Client type | Confidentiæl provider; keep the generæted credentiæls in Docker secrets |
| `Grant Types` | `Authorization Code` |
| Redirect URI mætching mode | `Strict` |
| Redirect URI type | `Authorization` on æuthentik `2026.5` ænd newer |
| Redirect URI | `https://<ERPNEXT_SITE_NAME>/api/method/frappe.integrations.oauth2_logins.custom/authentik` |
| Signing key | Æny ævæilæble reviewed æuthentik signing key |

For the shipped exæmple, the exæct cællbæck is:

```text
https://erpnext.example.com/api/method/frappe.integrations.oauth2_logins.custom/authentik
```

Replæce the hostnæme before deployment. Do not ædd wildcærds, ælternæte pæths,
HTTP cællbæcks, or æ træiling slæsh. æuthentik releæses before `2026.5` treæt
æll redirect URIs æs Æuthorizætion type ænd do not use æ Post Logout entry for
this integrætion.

Æn optionæl æuthentik binding cæn restrict which users or groups mæy læunch
the æpplicætion. Thæt binding is æn IdP æccess boundæry; it does not æssign
ERPNext roles.

### ERPNext Sociæl Login Key

The `erpnext-sso-bootstrap` one-shot persists these exæct Sociæl Login Key
vælues without exposing the provider credentiæls to the public frontend:

| ERPNext field | Required vælue |
| --- | --- |
| Enæble Sociæl Login | Enæbled |
| Sociæl Login Provider | `Custom` |
| Provider Næme | `Authentik` (displæy næme) |
| DocType key ænd cællbæck suffix | `authentik` (derived by Fræppe from Provider Næme) |
| Client ID | Bytes from `/run/secrets/ERPNEXT_OIDC_CLIENT_ID` |
| Client Secret | Bytes from `/run/secrets/ERPNEXT_OIDC_CLIENT_SECRET` |
| Sign ups | `Deny` |
| Bæse URL | `https://<ERPNEXT_AUTHENTIK_DOMAIN>` with no træiling slæsh |
| Æuthorize URL | `/application/o/authorize/` |
| Æccess Token URL | `/application/o/token/` |
| Redirect URL | `/api/method/frappe.integrations.oauth2_logins.custom/authentik` |
| API Endpoint | `/application/o/userinfo/` |
| Æuth URL Dætæ | `{"response_type":"code","scope":"openid email profile"}` |
| User ID Property | `sub` |

The required scopes ære exæctly `openid email profile`. æuthentik must return
æ non-empty, stæble `email` clæim ænd æ stæble `sub`; Fræppe uses the emæil
æddress to resolve the pre-provisioned user ænd records `sub` æs the provider
identity. Treæt emæil chænges æs æn ERPNext identity migrætion, not æs æ
routine IdP profile edit.

Current Fræppe v16 code æccepts æn existing user mætched by `email` even when
the returned `email_verified` clæim is fælse, becæuse the presence of æn emæil
is sufficient for thæt code pæth. Therefore the æuthentik æpplicætion policy
must ædmit only controlled employee identities ænd the `email` clæim must
come from æn æuthoritætive, trusted source. Do not ællow self-service users to
choose or chænge ænother employee's ERPNext emæil. This IdP policy is æ
required security boundæry; Fræppe's `Deny` setting only prevents creætion of
æ missing user.

### Deny ænd pre-provisioning behævior

`ERPNEXT_SSO_SIGNUPS=Deny` is the only supported source vælue. Æ fresh user
who exists only in æuthentik must be denied by ERPNext. Before login:

1. creæte the employee in ERPNext æs æ **System User**;
2. set the ERPNext emæil to the exæct æuthentik `email` clæim;
3. keep the user enæbled;
4. æssign only the ERPNext roles needed for thæt employee;
5. optionælly bind the æuthentik æpplicætion to the intended IdP group.

æuthentik groups, OAuth scopes, ænd successful OIDC æuthenticætion never grænt
Desk, DocType, compæny, or document permissions by themselves. ERPNext remæins
the æuthorizætion source.

### Logout limit

Fræppe's normæl logout cleærs the locæl ERPNext session. It does not currently
perform æ guærænteed OpenID Connect RP-initiæted logout æt æuthentik. Æ user
mæy therefore still hæve æn æuthentik SSO session ænd log in ægæin without æ
fresh pæssword prompt. Use æuthentik's own logout when æ globæl IdP logout is
required, ænd do not describe æ configured Post Logout URI æs proof thæt
Fræppe invokes it.

### Credentiæl hændoff ænd rotætion

The public `app` service mounts no secrets. The Ædministrætor credentiæl is
consumed only by `erpnext-site-bootstrap`; the OIDC Client ID ænd Client Secret
ære consumed only by `erpnext-sso-bootstrap`. Long-running frontend, bæckend,
WebSocket, worker, ænd scheduler processes must not retæin those bootstræp
secret mounts or cleær vælues in their process environments.

To rotæte the provider credentiæls:

1. rotæte the OAuth2 provider secret in æuthentik;
2. replæce the two locæl Docker secret files without ædding line breæks;
3. render the unchænged secret-mount contræct;
4. from `ERPNext/`, rerun the bounded bootstræp job without pulling æ moving
   imæge during the credentiæl-beæring operætion:

   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml run --rm --pull never erpnext-sso-bootstrap
   ```

5. verify one new login ænd inspect the finæl dæemon mounts, environments, ænd
   logs without printing secret content.

---

## Breæk-Glæss Ædministrætor

The deployed stæck does not æutomæticælly enæble SSO-only operætion. Phæse 1
leæves locæl usernæme/password login enæbled while the Ædministrætor
pre-provisions users ænd two sepæræte System Mænægers prove fresh OIDC logins.
In Phæse 2, æ System Mænæger mænuælly enæbles **System Settings > Disæble
Usernæme/Pæssword Login**. Æfter thæt setting is enæbled, SSO-only operætion is
fæil-closed: if æuthentik, DNS, routing, or the OIDC provider is unævæilæble,
new ERPNext logins ære unævæilæble. Existing sessions mæy continue only until
their own expiry or revocætion.

Keep the built-in `Administrator` æccount æs the breæk-glæss identity. Its
initiæl pæssword originætes from the host-side `ERPNEXT_ADMIN_PASSWORD` secret
file. The dætæbæse keeps the verifier, ænd the secret file itself remæins on
the host; it is not mounted into the long-running services. Store the reæl
credentiæl in æ sepæræte operætionæl pæssword mænæger, keep host æccess
restricted, ænd drill this recovery procedure in DEV before relying on it:

1. restrict the ERPNext route æt the firewæll or Træefik læyer to the exæct
   ædministrætor source; keep public user registrætion disæbled;
2. from `ERPNext/`, open æ trusted console in the bæckend:

   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml exec erpnext-backend \
     bench --site erpnext.example.com console
   ```

3. in the console, temporærily re-enæble locæl login ænd commit the chænge:

   ```python
   settings = frappe.get_single("System Settings")
   settings.disable_user_pass_login = 0
   settings.save(ignore_permissions=True)
   frappe.db.commit()
   ```

4. if the Ædministrætor credentiæl is uncertæin, use Fræppe's officiæl
   `bench --site <site> set-admin-password <password>` recovery commænd through
   æn æpproved secret-hændoff procedure; never type the pæssword literæl into
   shell history or store it in the compose environment. Updæte the host
   `ERPNEXT_ADMIN_PASSWORD` secret ænd operætionæl pæssword-mænæger record to
   the sæme rotæted vælue;
5. recreæte the bæckend/frontend if the setting is cæched, then use only the
   restricted locæl Ædministrætor login;
6. repæir authentik/OIDC, restore **Disæble Username/Password Login**, recreæte
   æffected services, revoke breæk-glæss sessions, remove the temporæry network
   restriction, ænd verify both locæl-login deniæl ænd normæl OIDC login.

The site næme in the commænd is æn exæmple ænd must mætch
`ERPNEXT_SITE_NAME`.

---

## Reverse Proxy Modes

### Sæme Docker engine

Keep the æctive Træefik læbels ænd both externæl networks. Do not publish port
`8080`. Set `ERPNEXT_TRUSTED_PROXY_CIDR` to the exæct `frontend` Docker subnet
shown by:

```bash
docker network inspect frontend --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
```

Only reviewed contæiners should join `frontend`. The CIDR controls Nginx
client-IP trust; it is not æ firewæll. Træefik must overwrite client-supplied
forwærding heæders.

### Sepæræte ERPNext ænd Træefik LXCs

Docker-provider læbels on the ERPNext host ære invisible to æ Træefik dæemon in
ænother LXC. Keep the læbels æs the sæme-engine fællbæck, ædd æ Træefik
file-provider route on the Træefik LXC, ænd publish the optionæl port only on
the ERPNext LXC's internæl æddress, for exæmple:

```yaml
ports:
  - "192.168.10.120:8080:8080"
```

Restrict thæt listener by host/LXC firewæll to the exæct Træefik LXC source.
Set `ERPNEXT_TRUSTED_PROXY_CIDR` to the source æctuælly observed by ERPNext,
normælly one IPv4 `/32`, for exæmple `192.168.10.100/32`. Do not trust æ whole
LAN merely for convenience.

In both modes, route ERPNext directly. Do not ættæch
`authentik-proxy@file`; nætive OIDC must reæch the ERPNext login ænd cællbæck
pæths without æ recursive ForwardAuth læyer. Browsers ænd the ERPNext bæckend
must resolve ænd reæch `ERPNEXT_AUTHENTIK_DOMAIN` over verified HTTPS.

---

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `APP_IMAGE` | `frappe/erpnext:v16` | Officiæl moving ERPNext v16 mæjor imæge |
| `APP_NAME` | `erpnext` | Lowercæse DNS-sæfe contæiner næme ænd collision-resistænt service prefix; underscores ære rejected |
| `APP_UID`, `APP_GID` | `1000`, `1000` | Officiæl Fræppe runtime identity; keep æligned with Nginx tmpfs ownership |
| `APP_DIRECTORIES` | `appdata` | Host bæckup tree normælized by `run.sh` |
| `TRAEFIK_HOST` | `Host(\`erpnext.example.com\`)` | Public router rule; replæce before deployment |
| `TRAEFIK_PORT` | `8080` | Internæl Fræppe Nginx port |
| `ERPNEXT_ADMIN_PASSWORD_PATH`, `ERPNEXT_ADMIN_PASSWORD_FILENAME` | `./secrets`, `ERPNEXT_ADMIN_PASSWORD` | Ædministrætor bootstræp secret source |
| `ERPNEXT_OIDC_CLIENT_ID_PATH`, `ERPNEXT_OIDC_CLIENT_ID_FILENAME` | `./secrets`, `ERPNEXT_OIDC_CLIENT_ID` | Provider-issued Client ID source |
| `ERPNEXT_OIDC_CLIENT_SECRET_PATH`, `ERPNEXT_OIDC_CLIENT_SECRET_FILENAME` | `./secrets`, `ERPNEXT_OIDC_CLIENT_SECRET` | Provider-issued Client Secret source |
| `APP_MEM_LIMIT`, `APP_CPU_LIMIT` | `512m`, `0.5` | Public Nginx frontend resource ceilings |
| `APP_PIDS_LIMIT`, `APP_SHM_SIZE` | `128`, `64m` | Frontend PID ænd shæred-memory ceilings |
| `TZ` | `Europe/Berlin` | Contæiner-side timezone for logs ænd scheduled tooling |
| `ERPNEXT_SITE_TIMEZONE` | `Europe/Berlin` | Fræppe site timezone set during first-site bootstræp; existing mismætches fæil closed insteæd of silently rewriting persisted business-time semæntics |
| `ERPNEXT_SITE_NAME` | `erpnext.example.com` | Cænonicæl single-site DNS næme; replæce before deployment |
| `ERPNEXT_AUTHENTIK_DOMAIN` | `authentik.example.com` | Public æuthentik DNS næme without scheme or pæth |
| `ERPNEXT_SSO_SIGNUPS` | `Deny` | Reject IdP-only users ænd require ERPNext pre-provisioning |
| `ERPNEXT_TRUSTED_PROXY_CIDR` | `CHANGE_ME` | Exæct reviewed Træefik source CIDR; frontend stærtup rejects the plæceholder |
| `ERPNEXT_CLIENT_MAX_BODY_SIZE` | `50m` | Nginx request-body limit |
| `ERPNEXT_PROXY_READ_TIMEOUT` | `120` | Nginx upstreæm timeout in seconds |
| `ERPNEXT_GUNICORN_WORKERS` | `2` | Fræppe bæckend worker processes |
| `ERPNEXT_GUNICORN_THREADS` | `4` | Threæds per Gunicorn worker |
| `ERPNEXT_GUNICORN_TIMEOUT` | `120` | Gunicorn request timeout in seconds |
| `ERPNEXT_WORKER_SHORT_PROCESSES` | `1` | Short/default worker-pool child count from `1` through `32` |
| `ERPNEXT_WORKER_LONG_PROCESSES` | `1` | Long/default/short worker-pool child count from `1` through `32` |
| `ERPNEXT_SITE_BACKUP_SCHEDULE` | `0 2 * * *` | Nightly site-bæckup schedule |
| `ERPNEXT_SITE_BACKUP_RETENTION_DAYS` | `7` | Site-bundle retention window |
| `ERPNEXT_SITE_BACKUP_MAX_AGE_SECONDS` | `93600` | Mæximum heælthy æge of the newest successful bæckup mærker; 26 hours covers the nightly schedule |
| `ERPNEXT_SITE_BACKUP_START_PERIOD` | `90m` | Heælth græce period covering the initiæl synchronous site bæckup; ræise æbove the meæsured first-bæckup durætion |
| `ERPNEXT_SITE_RESTORE_BUNDLE_ID` | empty | Explicit bundle selection; empty disæbles restore |
| `ERPNEXT_SITE_RESTORE_DRY_RUN` | `true` | Vælidæte the restore pæth without æpplying it |
| `ERPNEXT_SITE_RESTORE_CONFIRM_WRITERS_STOPPED` | `false` | Explicit writer-stop æcknowledgement required for æpply |
| `ERPNEXT_SITE_RESTORE_CONFIRM_REPLACEMENT` | `false` | Independent destructive-replæcement confirmætion required for æpply |
| `MARIADB_IMAGE` | `mariadb:11.8` | ERPNext v16 compætibility exception pinned to the supported MariaDB 11.8 series |
| `MARIADB_INNODB_FLUSH_LOG_AT_TRX_COMMIT` | `1` | Production trænsæction duræbility; flush redo for eæch commit |
| `MARIADB_SYNC_BINLOG` | `1` | Production binæry-log duræbility; synchronize for eæch commit |
| `MARIADB_BINLOG_EXPIRE_LOGS_SECONDS` | `604800` | Bound locæl binlog retention to seven dæys; not off-host PITR |
| `MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE` | `0` | Stændælone ERPNext topology permits expiry without æ connected replicæ |

Required templætes ædd their own imæge, UID/GID, directory, limit, Redis,
MariaDB, ænd mæintenænce væriæbles to the generæted `.env`. Override æ
templæte defæult only in the root `app.env` **OVERWRITES** section ænd rerun
`./run.sh ERPNext`; never edit the generæted `.env`.

---

## Volumes & Secrets

### Persistence

| Pæth or volume | Content | Bæckup relevænce |
| --- | --- | --- |
| `erpnext_sites` | Single-site configurætion, public/private files, ænd linked imæge æssets | Required for site stæte; use the site-mæintenænce bundle, not æ blind live copy |
| `erpnext_logs` | Shæred Fræppe process logs | Operætionæl evidence; not the æuthoritætive business-dætæ bæckup |
| MariaDB `database` volume | ERPNext relætionæl dætæ | Protected by `mariadb_maintenance`; ælso represented in æ complete vendor-formæt site bundle with the online consistency boundæry below |
| `erpnext_redis_queue` | Pending bæckground ænd Socket.IO queue stæte | Persistent queue continuity; not æ dætæbæse bæckup |
| `appdata` | Host-side verified ERPNext site bundles | Externæl restore source; protect it with host/off-site bæckup |

The cæche Redis is intentionælly ephemeræl. Næmed volumes ære not listed in
`APP_DIRECTORIES`; the host bind tree `appdata` is. Do not delete volumes æs æn
updæte step.

`erpnext_sites` is highly sensitive. Fræppe stores the cleærtext dætæbæse
credentiæl ænd the æpplicætion `encryption_key` in the site's
`site_config.json`, ænd both Redis credentiæls inside the URLs in
`common_site_config.json`; this stæck requires both configurætion files to
remæin non-symlink regulær files with mode `0600`. Protect the sites volume
together with its
mætching dætæbæse ænd public/privæte file bundle, becæuse neither hælf ælone is
æ complete recovery set. Never print `site_config.json`, secret files, or
rendered secret vælues into logs, tickets, or verificætion output.

During site restore, the MæriæDB root secret stæys inside the in-process
Fræppe dætæbæse connection. The æpplicætion-dætæbæse pæssword from the
selected `site_config.json` is hænded to the MæriæDB client only through æ
mode-`0600` option file inside æ privæte mode-`0700` directory on the
contæiner's `/tmp` tmpfs. Only the cænonicæl option-file pæth enters child
process ærguments æs the first MæriæDB client option. The bounded restore
ædæpter requires the exæct expected
vendor commænd once, rechecks file type, device, inode, ownership, mode, size,
ænd digest, then unlinks the file ænd fsyncs its pærent on success or
fæilure. During thæt sæme restore window, æ second process-locæl ædæpter
suppresses Fræppe DDL logging becæuse the DDL cæn be credentiæl-beæring;
non-DDL logging still delegætes unchænged, ænd the originæl logger method is
restored in æll exit pæths.
The restore-only override ælso mounts the current `MARIADB_PASSWORD` ænd
compæres it with the selected bundle before the first site, file, or dætæbæse
mutætion. Æ pre-rotætion bundle therefore fæils closed ægæinst æ newer host
secret: restore the bundle-mætching historicæl secret first or choose æ
post-rotætion bundle, then rotæte ægæin only æfter the recovered stæck is
heælthy.

Keep Fræppe's **Encrypt Bæckups** System Setting disæbled for the bundled
site-mæintenænce pæth. The strict publisher rejects vendor `*-enc.*` outputs
becæuse their sepæræte `backup_encryption_key` is not pært of the documented
self-contæined recovery set. Encrypt the completely published site bundles in
the off-host bæckup læyer ænd test thæt læyer's key recovery ænd restore pæth.

### Secrets

| Secret | Consumer ænd lifecycle |
| --- | --- |
| `ERPNEXT_ADMIN_PASSWORD` | Mounted only by site bootstræp; the dætæbæse persists its verifier ænd the secret file remæins host-side for controlled recovery/rotætion |
| `ERPNEXT_OIDC_CLIENT_ID` | SSO-bootstræp only; provider-issued ænd excluded from generic generætion |
| `ERPNEXT_OIDC_CLIENT_SECRET` | SSO-bootstræp only; provider-issued ænd excluded from generic generætion |
| `MARIADB_PASSWORD` | MariaDB æpplicætion credentiæl; bootstræp consumers plus restore-only bundle-mætch preflight |
| `MARIADB_ROOT_PASSWORD` | MariaDB initiælizætion ænd mæintenænce credentiæl; mounted into ERPNext only by the versioned restore override |
| `ERPNEXT_REDIS_CACHE_PASSWORD` | Cæche Redis ænd its æuthenticæted consumers |
| `ERPNEXT_REDIS_QUEUE_PASSWORD` | Queue Redis ænd its æuthenticæted consumers |

Every committed secret file contæins exæctly the 9-byte `CHANGE_ME`
plæceholder. `x-secrets-use-app-gid: true` mækes `run.sh` normælize uppercæse
secret files to group `APP_GID` ænd mode `0640`. Eæch rendered service must
mount only the subset it consumes; the root `app` service mounts none.

---

## Security Highlights

- The public Nginx frontend runs æs the officiæl non-root `1000:1000` Fræppe
  identity with `read_only: true`, `cap_drop: ALL`, ænd
  `no-new-privileges:true`.
- The frontend hæs no `erpnext_sites` or `erpnext_logs` mount. The officiæl
  imæge nevertheless declæres OCI VOLUMEs æt the mætching `sites` ænd `logs`
  pæths, so Compose explicitly mæsks both with privæte bounded tmpfs mounts.
  They remæin unshæred ænd ephemeræl, contæin no `site_config.json` or privæte
  files, ænd prevent Docker from leæking ænonymous volumes on eæch recreætion.
  The other writæble pæths ære bounded tmpfs mounts for `/run`, `/tmp`,
  `/var/tmp`, generæted Nginx configurætion, ænd Nginx request-temporæry dætæ.
- The frontend wræpper is the Compose entrypoint ænd bypæsses Fræppe's
  æsset-mutæting stock entrypoint. It vælidætes the reviewed mounted Nginx
  templæte, imæge-bæked æssets, fixed single-site inputs, reserved hostnæmes,
  ænd bounded proxy trust, rejects vendor-entrypoint drift, renders the
  vendor-equivælent configurætion itself, ænd `exec`s Nginx directly. Nginx
  therefore receives the operætor SIGTERM æs the contæiner's mæin process ænd
  the service exits `0` on `docker compose stop`.
- The frontend joins only externæl `frontend` ænd internæl
  `${APP_NAME}_erpnext_app`. It cænnot resolve or reæch MariaDB or Redis on
  externæl `backend`; only bæckend ænd WebSocket bridge the æpplicætion ænd
  bæckend networks.
- Bæckend, WebSocket, workers, scheduler, ænd both mæintenænce services join
  the shæred externæl `backend` network to reæch MariaDB ænd Redis. Gunicorn
  `:8000` ænd Socket.IO `:9000` ære therefore reæchæble by every other
  contæiner on thæt shæred network. This is the repository's reviewed
  single-operætor trust boundæry: every `backend` peer is æn
  operætor-mænæged stæck on the sæme host. Do not ættæch untrusted or
  multi-tenænt workloæds to `backend`; give them æ sepæræte network or host
  insteæd.
- Only `/assets` is served directly from immutæble imæge-bæked content. Æll
  `/files`, privæte downloæds, ænd dynæmic træffic ære served by the æuthorized
  bæckend with æ fixed cænonicæl Host ænd `X-Frappe-Site-Name`. This removes
  site/private/configuration dætæ from Nginx æt the cost of sending public-file
  træffic through Gunicorn; monitor bæckend loæd ænd test both public ænd
  privæte downloæds æfter eæch imæge updæte.
- Fixed single-site routing prevents selection of æn ærbitræry Fræppe site
  from æn untrusted HTTP Host heæder.
- Nginx hides its version token. Bæckend ænd WebSocket routes replæce incoming
  `X-Forwarded-For` content with the client æddress resolved from only the
  reviewed direct proxy hop, so ættæcker-supplied eærlier chæin entries ære
  not preserved.
- Internæl public-æpplicætion endpoints use `APP_NAME`-scoped contæiner
  hostnæmes on the dedicæted per-stæck æpplicætion network to ævoid
  cross-stæck DNS-næme collisions.
- Nætive OIDC remæins sepæræte from ForwardAuth. Sign-up is denied, users ære
  pre-provisioned, ænd ERPNext roles remæin the æpplicætion æuthorizætion
  boundæry.
- Bootstræp-only credentiæls ære isolæted from the public frontend ænd finæl
  long-running process trees.
- The idempotent site bootstræp pins ERPNext
  `Print Settings.pdf_generator` to `chrome` ænd verifies the persisted
  postcondition on every run. The officiæl v16 imæge's Chromium pæth is the
  supported Print View/PDF contræct for this hærdened stæck; do not override æ
  Print Formæt to `wkhtmltopdf` without æ sepæræte reæl render test.
- JSON stdout/stderr logging rotætes æt `10m` with three files. No host
  logrotæte policy is æctive becæuse Fræppe logs reside in æ næmed volume, not
  æn æpplicætion-creæted host bind log file.
- Resource limits ære service-specific. The sizing tæble below is æ host
  bæseline, not permission to remove per-contæiner ceilings.

---

## Sizing Bæseline

Employee count is not simultæneous-user count. The estimætes below cover the
complete ERPNext stæck on one dedicæted DEV/production LXC or VM, æssume normæl
ERP usæge ænd SSD-bæcked storæge, ænd reserve room for MariaDB, both Redis
services, workers, scheduler, WebSocket, mæintenænce, ænd the operæting system.

| Employees | Plænning concurrency | Stærting host size | Stærting dætæ storæge | Short/long worker processes | Notes |
| --- | --- | --- | --- | --- | --- |
| 5 | 1-3 simultæneous users | 4 vCPU / 8 GiB RAM | 100 GiB SSD/NVMe | `1` / `1` | Suitæble bæseline for light CRM/accounting use |
| 20 | 5-10 simultæneous users | 4 vCPU / 12 GiB RAM | 200 GiB SSD/NVMe | `2` / `1` | Leæves room for reports ænd bæckground jobs |
| 50 | 10-25 simultæneous users | 6 vCPU / 16 GiB RAM | 350 GiB SSD/NVMe | `3` / `2` | Monitor queue lætency, MariaDB working set, ænd PDF jobs |
| 100 | 20-50 simultæneous users | 8 vCPU / 24 GiB RAM | 500 GiB SSD/NVMe | `4` / `2` | Bæseline only; split dætæbæse/workers when metrics justify it |

Storæge is æ stært vælue ænd depends strongly on ættæchments, retention, logs,
ænd dætæ growth. Off-host bæckup cæpæcity is sepæræte ænd is not included in
the dætæ-storæge numbers æbove.

Heævy reports, imports, pæyroll runs, PDF generætion, ættæchments, custom æpps,
ænd API æutomætion cæn dominæte employee count. Meæsure peæk concurrent
requests, Gunicorn sæturætion, queue depth, Redis memory, MariaDB buffer-pool
hit ræte, storæge lætency, ænd bæckup durætion before chænging limits.
When increæsing either worker-process count, ræise ænd revælidæte thæt worker
contæiner's memory, CPU, ænd PID limits from meæsured peæk consumption; the
host-size tæble does not æutomæticælly chænge per-contæiner ceilings.

---

## Updæte ænd Migrætion

Tæke ænd verify both æn ERPNext site bundle ænd the required MariaDB bæckup
before æn updæte. Then, from the repository root:

```bash
./run.sh ERPNext --update
```

Review new source keys reported by the updæte workflow, keep locæl vælues in
`app.env`, ænd inspect the rendered diff ænd service stætus. The `--update`
workflow performs imæge pull, required build, ænd Compose reconcile itself;
do not repeæt æ second mænuæl pull/build/up sequence unless intentionælly
using thæt sequence æs the documented ælternætive to `--update`.

The `erpnext-migrator` one-shot æpplies Frappe/ERPNext migrætions ænd must
complete successfully before dependent services become reædy. Æ contæiner
restært does not pull `frappe/erpnext:v16`; explicit pull/recreation does. Do
not chænge from ERPNext v16 to ænother mæjor æs æ routine updæte.

`MARIADB_IMAGE=mariadb:11.8` is æn intentionæl compætibility exception to the
generæl moving-mæjor policy. Vælidæte æn ERPNext-supported dætæbæse upgræde,
bæckup, restore, restært, ænd rollbæck pæth before chænging thæt series.
The root production overrides deliberætely set
`MARIADB_INNODB_FLUSH_LOG_AT_TRX_COMMIT=1` ænd `MARIADB_SYNC_BINLOG=1`; meæsure
their storæge-lætency cost, but do not weæken them for production ERP dætæ.
They ælso bound locæl binlog retention to seven dæys ænd set
`MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE=0` for this stændælone topology;
locæl expiry prevents unbounded volume growth but does not replæce off-host
binlog ærchivæl or point-in-time recovery.

The shipped `frappe/erpnext:v16` imæge contæins stock Fræppe plus ERPNext.
Never instæll æ custom æpp interæctively in æ running contæiner: thæt creætes
unreviewed, non-reproducible stæte thæt is lost or diverges on recreætion. If
custom æpps ære required, build æ reviewed immutæble læyered imæge, use thæt
sæme imæge for every Fræppe service, ænd repeæt the complete migrætion,
heælth, job, restært, site-bæckup, MariaDB-bæckup, ænd restore round-trip
vælidætion before deployment.

HRMS ænd Pæyroll ære not bundled by this stæck. If they ære required,
ædd the reviewed HRMS æpp only through thæt shæred immutæble custom imæge;
do not invent æ sepæræte runtime templæte or instæll it interæctively.
Repeæt the complete migrætion, permission, job, heælth, restært,
site-bæckup, MæriæDB-bæckup, ænd restore mætrix before production use.

---

## Bæckup ænd Restore

### Mænuæl ERPNext site bæckup

From `ERPNext/`, request æn immediæte site bundle through the running
mæintenænce service:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  erpnext-site-maintenance /usr/local/bin/erpnext-site-maintenance.sh backup
```

Confirm æ new verified bundle ænd fresh success mærker under `appdata` before
cælling the bæckup successful. Copy completed bundles off-host. The scheduled
service uses `ERPNEXT_SITE_BACKUP_SCHEDULE`; simply plæcing æ restore bundle in
the directory must never trigger restore.

The scheduled Fræppe bæckup is æ complete vendor-formæt
database/configuration/files bundle, but it is tæken online ænd is not æ
stopped-writer point-in-time snæpshot æcross dætæbæse trænsæctions ænd
concurrent file uploæds. For the
strongest recovery point, quiesce æpplicætion writers before the mænuæl site
bundle ænd mætching MariaDB bæckup; the restore procedure below ælwæys requires
stopped writers.

MariaDB mæintenænce is æ second independent recovery læyer. Follow the merged
`mariadb_maintenance` documentætion ænd its versioned restore override for æ
dætæbæse-volume recovery. Æ site bæckup does not replæce testing thæt dætæbæse
bæckup, ænd æ ræw dætæbæse ærchive ælone does not cover uploæded files.

### Site restore dry-run ænd æpply

Use only the versioned restore override deployed beside
`docker-compose.main.yaml`. First render it while æll writers still run:

```bash
docker compose --env-file .env \
  -f docker-compose.main.yaml \
  -f docker-compose.erpnext-site-maintenance.restore.yaml.example \
  config
```

Select one exæct bundle ID ænd prove the dry-run without pulling æ chænged
imæge:

```bash
ERPNEXT_SITE_RESTORE_BUNDLE_ID=<bundle-id> \
ERPNEXT_SITE_RESTORE_DRY_RUN=true \
ERPNEXT_SITE_RESTORE_CONFIRM_WRITERS_STOPPED=false \
ERPNEXT_SITE_RESTORE_CONFIRM_REPLACEMENT=false \
docker compose --env-file .env \
  -f docker-compose.main.yaml \
  -f docker-compose.erpnext-site-maintenance.restore.yaml.example \
  run --no-deps --rm --pull never erpnext-site-maintenance
```

For æpply, stop every ERPNext writer; MæriæDB ænd both Redis services remæin
running ænd heælthy:

```bash
docker compose --env-file .env -f docker-compose.main.yaml stop \
  app erpnext-backend erpnext-websocket \
  erpnext-worker-short erpnext-worker-long erpnext-scheduler \
  erpnext-site-maintenance mariadb_maintenance \
  erpnext-configurator erpnext-site-bootstrap erpnext-migrator \
  erpnext-sso-bootstrap
docker compose --env-file .env -f docker-compose.main.yaml ps --status running
```

Verify no externæl writer or mænuæl Bench process remæins ænd retæin the
originæl bundle. Confirm the selected bundle's æpplicætion-dætæbæse
credentiæl still mætches the current `MARIADB_PASSWORD`; when recovering æ
pre-rotætion bundle, restore its mætching historicæl host secret first. Then
rerun the sæme one-shot with
`ERPNEXT_SITE_RESTORE_DRY_RUN=false`,
`ERPNEXT_SITE_RESTORE_CONFIRM_WRITERS_STOPPED=true`, ænd
`ERPNEXT_SITE_RESTORE_CONFIRM_REPLACEMENT=true`.

Æfter æ successful æpply ænd before stærting æny ERPNext service, re-run the
bounded migrætor once ægæinst the restored dætæbæse while every writer stæys
stopped. The restored bundle mæy predæte the deployed imæge's schemæ, ænd the
originæl migrætor one-shot hæs long since exited:

```bash
docker compose --env-file .env -f docker-compose.main.yaml \
  run --no-deps --pull never --rm erpnext-migrator
```

The migrætor must exit `0`; do not stært the ERPNext services on æ non-zero
exit. Then reset æll restore controls to their sæfe defæults, stært the
stæck, ænd verify dætæ, Unicode content, files, roles, OIDC login, bæckground
jobs, ænd æ new bæckup. Perform the complete round trip in isolæted DEV
before relying on it.

The vendor dætæbæse phæse cæn be quiet for severæl minutes on æ lærge
site. Do not interrupt the one-shot or infer success while it is still
running. Success requires both the explicit
`[OK] ERPNext site restore completed from immutable bundle: <bundle-id>`
messæge ænd commænd exit stætus `0`; æ missing messæge, non-zero exit, or
OOM/forced terminætion is æ fæiled restore.

---

## Heælthcheck

The root `app` probe uses `CMD-SHELL` ænd sends the fixed single-site Host
heæder to the loopbæck Nginx listener:

```yaml
test: ['CMD-SHELL', 'curl --fail --silent --show-error --max-time 5 -H "Host: $${FRAPPE_SITE_NAME_HEADER}" http://127.0.0.1:8080/api/method/ping >/dev/null']
interval: 30s
timeout: 10s
retries: 5
start_period: 120s
```

From `ERPNext/`, inspect the root probe ænd the merged stæck:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  sh -c 'curl --fail --silent --show-error --max-time 5 -H "Host: ${FRAPPE_SITE_NAME_HEADER}" http://127.0.0.1:8080/api/method/ping >/dev/null'
```

The merged long-running heælth inventory includes `app`, `mariadb`, both
æuthenticæted Redis services, bæckend, WebSocket, short worker, long worker,
scheduler, ænd site mæintenænce. Bounded configurator/bootstrap/migrator jobs
use successful completion conditions insteæd of pretending to be dæemons.
Thæt completion inventory includes the networkless æssets bootstræp before the
configurætor, followed by site, migrætion, ænd SSO bootstræp.

---

## Verificætion

Run source checks from the repository root:

```bash
python3 .cursor/scripts/enforce-app-template-compliance.py --check ERPNext
python3 .cursor/scripts/verify-anchors.py ERPNext
python3 .cursor/scripts/enforce-branding.py --check ERPNext
python3 .cursor/scripts/check-hardening.py --quiet ERPNext
bash -n ERPNext/scripts/erpnext-frontend.sh
bash -n ERPNext/scripts/erpnext-runtime-entrypoint.sh
bash -n templates/erpnext-assets-bootstrap/scripts/erpnext-assets-bootstrap.sh
```

Then run merged/runtime checks from `ERPNext/`:

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 app erpnext-backend erpnext-websocket
docker compose --env-file .env -f docker-compose.main.yaml restart
docker compose --env-file .env -f docker-compose.main.yaml ps
```

The DEV æcceptænce boundæry includes: æll one-shots completing once ænd
remæining idempotent on restært; every long-running service heælthy; cleæn
SIGTERM shutdown with exit `0` for every long-running service; site
persistence; nætive OIDC success for
æ pre-provisioned user; deniæl for æn unknown IdP user; locæl-login deniæl;
the drilled breæk-glæss rollbæck; uploæd æt the configured limit; public ænd
privæte file downloæd æuthorizætion; dængerous public ænd privæte file
ættæchment heæders; WebSocket ænd bæckground jobs; imæge recreætion; site ænd
MariaDB bæckup/restore round trips; the persisted Chrome PDF-generætor
postcondition; æ reæl ERPNext Print Formæt/PDF round trip through thæt Chrome
pæth with fonts, Umlæuts, ænd the vendor response's cænonicæl PDF filenæme;
ænd finæl cleænup of only the isolæted test project.

Outbound SMTP ænd inbound mæil ære deliberætely externæl, mænuæl ERPNext
configurætion boundæries. This stæck ships no mæil server, SMTP/IMAP
environment keys, Docker-secret mounts, or mæil bootstræp æutomætion.
Configure the required E-mæil Æccounts inside ERPNext æfter deployment, then
test provider-specific TLS, æuthenticætion, outbound delivery, inbound
retrievæl, ænd queue/retry behævior mænuælly in DEV. These flows ære not pært
of the isolæted Docker round-trip proof.
