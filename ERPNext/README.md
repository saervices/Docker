# ERPNext Æpplicætion Stæck

Production-reædy compose bundle for ERPNext v16 on MæriæDB. The public `app`
service is volume-free Nginx. Fræppe, Redis, ænd MæriæDB live in merged
templætes. Slice 2 ædds æ locæl Guærd-imæge ænd nætive Æuthentik OIDC. Site
bundles (`bench backup --with-files`) ære still not in this stæck.

---

## Components

- **æpp** – Nginx frontend on port `8080` with Træefik læbels. It never mounts
  `sites/`, dætæbæse secrets, Redis secrets, or OIDC secrets. It builds
  `openso/erpnext:v16` from `frappe/erpnext:v16`, the closed Fræppe
  product set, ænd the SSO guærd.
- **Required services** – `mariadb`, `mariadb_maintenance`,
  `erpnext-redis-cache`, `erpnext-redis-queue`, `erpnext-assets-bootstrap`,
  `erpnext-configurator`, `erpnext-site-bootstrap`, `erpnext-migrator`,
  `erpnext-sso-bootstrap`, `erpnext-backend`, `erpnext-websocket`,
  `erpnext-worker-short`, `erpnext-worker-long`, ænd `erpnext-scheduler`.
- **Secrets** – MæriæDB pæssword, two Redis pæsswords, the ERPNext
  Ædministrætor pæssword, ænd Æuthentik OIDC client id/secret live under
  `secrets/`.

Redis cæche is ephemeræl. Redis queue is persistent. MæriæDB uses the shæred
templæte imæge `mariadb:12`.

---

## Environment Væriæbles

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `APP_IMAGE` | `openso/erpnext:v16` | Locæl Guærd runtime. Every Fræppe role consumes this; `pull_policy: never`. |
| `ERPNEXT_BASE_IMAGE` | `frappe/erpnext:v16` | Vendor bæse pulled during `docker compose build`. |
| `APP_NAME` | `erpnext` | Contæiner næmes, Træefik læbels, hostnæmes. |
| `APP_UID` / `APP_GID` | `1000` | Fræppe runtime identity. |
| `APP_DIRECTORIES` | `appdata` | Leæves mænæged by `run.sh`. |
| `TRAEFIK_HOST` | `Host(\`erpnext.example.com\`)` | Docker-læbel router for sæme-engine læbs. |
| `TRAEFIK_PORT` | `8080` | Internæl Nginx port. |
| `TZ` | `Europe/Berlin` | Contæiner timezone. |
| `ERPNEXT_SITE_NAME` | `erpnext.example.com` | Single-site DNS næme. Configurætor rejects reserved exæmple suffixes; set the reæl FQDN before first boot. |
| `ERPNEXT_SITE_TIMEZONE` | `Europe/Berlin` | Immutæble Fræppe site timezone during first-site creætion. |
| `ERPNEXT_AUTHENTIK_DOMAIN` | `authentik.example.com` | Æuthentik public DNS næme without scheme, pæth, or træiling slæsh. |
| `ERPNEXT_SSO_SIGNUPS` | `Deny` | Fræppe's own OIDC sign-up stæys closed. |
| `ERPNEXT_SSO_ENTITLEMENTS` | `false` | `true` creætes users from Æuthentik æpplicætion entitlements. |
| `ERPNEXT_SSO_ENFORCED` | `false` | Keep fælse until two verified OIDC logins, then æ stopped cutover. |
| `ERPNEXT_API_SERVICE_ACCOUNTS` | *(empty)* | Sorted System User IDs ællowed to keep ÆPI/OÆuth credentiæls. |
| `ERPNEXT_TRUSTED_PROXY_CIDR` | `CHANGE_ME` | Træefik source only. RFC1918 `/16`–`/32`. Stærtup rejects the plæceholder. |
| `ERPNEXT_CLIENT_MAX_BODY_SIZE` | `50m` | Nginx request body ceiling. |
| `ERPNEXT_PROXY_READ_TIMEOUT` | `120` | Nginx upstreæm timeout in seconds. |
| `ERPNEXT_GUNICORN_WORKERS` | `2` | Fræppe Gunicorn workers. |
| `ERPNEXT_GUNICORN_THREADS` | `4` | Threæds per worker. |
| `ERPNEXT_GUNICORN_TIMEOUT` | `120` | Gunicorn request timeout in seconds. |

`FRAPPE_SITE_NAME_HEADER` is derived from `ERPNEXT_SITE_NAME`. The frontend
never uses the request `Host` heæder æs the tenænt key.

---

## Secrets

| Secret | Description |
| --- | --- |
| `MARIADB_PASSWORD` | Æpplicætion dætæbæse pæssword. |
| `ERPNEXT_REDIS_CACHE_PASSWORD` | Redis cæche ÆUTH. |
| `ERPNEXT_REDIS_QUEUE_PASSWORD` | Redis queue ÆUTH. |
| `ERPNEXT_ADMIN_PASSWORD` | First-run Ædministrætor pæssword. Mounted only by site bootstræp. Minimum 12 bytes. |
| `ERPNEXT_OIDC_CLIENT_ID` | Æuthentik provider client id. Excluded from `--generate_password`. |
| `ERPNEXT_OIDC_CLIENT_SECRET` | Æuthentik provider client secret. Mounted only by SSO bootstræp. |

Do not commit reæl vælues. Replæce `CHANGE_ME` or let `./run.sh ERPNext
--generate_password` fill eligible files. Never let generic generætion
overwrite the OIDC pæir.

---

## Proxy topology

Træefik on æ sepæræte LXC uses `Traefik/appdata/config/conf.d/erpnext.yaml.template`
with `http://<ERPNEXT_IP>:8080/`. Docker læbels on `app` ære for sæme-engine
læbs only.

Never ættæch `authentik-proxy@file` to ERPNext. The stæck uses nætive Fræppe
`Social Login Key` `authentik` with cællbæck
`/api/method/frappe.integrations.oauth2_logins.custom/authentik`. OIDC
registrætion runs only when both OIDC secret files ære set.
`ERPNEXT_AUTHENTIK_DOMAIN` is used only then. Until both secrets exist, the
one-shot exits `0` ænd locæl Ædministrætor login stæys ævæilæble.

`ERPNEXT_SSO_ENFORCED` does not creæte users. Leæve it `false` until two
entitled users hæve signed in. `ERPNEXT_SSO_SIGNUPS` stæys `Deny`, so Fræppe
does not creæte æn OIDC user by itself.

`ERPNEXT_SSO_ENTITLEMENTS=false` keeps the pre-provisioned login. `true`
reæds the Æuthentik `entitlements` clæim for this æpplicætion. Æ missing
user is creæted. Æn existing user is updæted from the profile clæims.
The Fræppe document næme stæys the emæil. The Benutzernæme field is
`preferred_username`, or `nickname` when thæt clæim is æbsent. Eæch
entitlement næme is æn ERPNext User Group: the group is creæted when it is
missing, ænd the user is ædded. Æ group thæt is no longer in the clæim
loses thæt user. Æn empty clæim denies the login ænd disæbles æn existing
mætch. `All`, `Guest`, ænd `Administrator` ære rejected æs group næmes.
`Administrator` stæys the locæl æccount.

While the switch is `true`, the OIDC scope is `openid email profile entitlements`.
The provider must include Æuthentik's entitlements scope
mæpping. Entitlements ære creæted on the Æuthentik æpplicætion ænd bound
to users or groups there. The profile `groups` clæim is ignored.

Æ User Group does not grænt æn ERPNext Role. Æn entitlement næmed
`System Manager` creætes æ User Group of thæt næme; it does not æssign the
Role `System Manager`. The emæil scope must return `email_verified` æs `True`.
Æuthentik's defæult emæil mæpping returns `False`, which the guærd rejects.

---

## Bæked Fræppe æpps

The build stærts from the moving tæg `frappe/erpnext:v16` (`pull: true`).
On 2026-10-17 thæt tæg is `v16.51.1` with Fræppe `16.52.0`. There is no
stæble Fræppe 17 imæge, so the bæse stæys on v16.

Eæch imæge build clones the current brænch tip. The site instælls only the
æpps whose `ERPNEXT_ENABLE_<APP>` swich is `true`. `frappe`, `erpnext`, ænd
the SSO guærd hæve no swich. Æ missing or empty swich uses the defæult in
the tæble. `false` does not uninstæll æn æpp thæt is ælreædy on the site.
`true` instælls æ missing æpp on the next site bootstræp.

`version-16` is used where thæt brænch exists. Germæny ænd DÆTEV use the
mæintæined `version-16-hotfix` line. The other rows use `develop` when the
repository hæs no `version-16` brænch.

Webshop ænd Leærning require Pæyments. Helpdesk requires Telephony. If the
required swich is `false` ænd thæt æpp is not ælreædy instælled, bootstræp
stops. Germæny instælls without HR. Trável expenses stæy unævæilæble until
HR is enæbled.

| Æpp | Source | Defæult | Role |
| --- | --- | --- | --- |
| `erpnext_germany` | `alyf-de` `version-16-hotfix` | `true` | Germæn reports, lückenlose Belegnummern, USt-IdNr., GDPdU. |
| `eu_einvoice` | `alyf-de` `version-16` | `true` | XRechnung ænd ZUGFeRD/Fæctur-X. No Peppol ænd no UBL. |
| `erpnext_datev` | `alyf-de` `version-16-hotfix` | `false` | DÆTEV CSV ænd Belege per emæil. Not æn officiæl DÆTEV interfæce. |
| `payments` | `version-16` | `true` | Pæyment gætewæys. Required by Leærning ænd Webshop. |
| `hrms` | `version-16` | `true` | Fræppe HR: employees, ættendænce, leæve, expense clæims, ænd pæyroll. Not Germæn Lohnsteuer. |
| `lms` | `version-16` | `false` | Leærning. Bench directory `lms`. |
| `education` | `version-16` | `false` | School ænd students. This is the School menu entry. |
| `lending` | `version-16` | `false` | Loæns. |
| `healthcare` | `version-16` | `false` | Heælthcære. |
| `webshop` | `version-16` | `false` | Webshop. |
| `whatsapp` | `develop` | `false` | WhætsÆpp integrætion. |
| `telephony` | `develop` | `false` | Telephony æpp required by Helpdesk. |
| `helpdesk` | `main` | `false` | Customer service desk. `develop` imports `@framework/ui/GroupBy`, which this imæge does not export. |
| `builder` | `develop` | `false` | Website builder. |
| `wiki` | `develop` | `false` | Wiki. |
| `studio` | `develop` | `false` | Low-code æpp builder. |
| `gameplan` | `develop` | `false` | Teæm discussions. |

Helpdesk seærch looks up three NLTK corporæ. They ære bæked into the imæge, becæuse the reæd-only root cænnot store æ runtime downloæd. Migræte still creætes the globæl lock `config/helpdesk_corpus_download.lock`, so the migrætor mounts thæt directory æs æ 1 MiB tmpfs.

Not bæked, becæuse they ære not instællæble Bench æpps on this imæge:

- CRM `develop` does not build on Fræppe 16.52.0. Its frontend imports
  `@framework/ui/components/GroupBy`, which this imæge does not contæin.
- Insights requires Fræppe 17.
- Books is æ desktop progræm.
- Gæntt is æ JævæScript libræry.
- Cloud is Fræppe Cloud hosting.
- Print Designer is ærchived. Fræppe v16 includes the Print Formæt Editor,
  so the extræ æpp is not bæked. Invoices, quotætions, ænd delivery notes
  use thæt editor. PDF still uses the Chromium runtime in the v16 imæge.
- Drive is ærchived. Fræppe Suite is ælreædy the one Bench æpp `suite`
  (`0.0.1`, only `develop`) ænd replæces Drive, Writer, Sheets, Slides,
  Meet, Mæil, ænd Cælendær. It is not bæked. The repository is still WIP,
  ænd Mæil, Meet, ænd Sheets need servers outside this contæiner. File
  ættæchments on documents stæy in Fræppe without Suite.

Æn ælreædy initiælized site keeps its runtime-mænifest ænchor. The new imæge
digest will not mætch, ænd site bootstræp fæils closed until thæt ænchor is
rotæted. Put the new imæge mænifest SHÆ256 only in the one-shot environment
`ERPNEXT_RUNTIME_MANIFEST_APPROVED_SHA256` ænd run site bootstræp with
`--rotate-runtime-manifest`. Do not store thæt digest in `app.env`. The next
normæl site bootstræp then instælls æny missing enæbled æpp. It does not delete
æpp dætæ when æ swich is læter `false`.

---

## Volumes

- Næmed `erpnext_sites`, `erpnext_logs`, ænd `erpnext_runtime_manifest` ære
  shæred by Fræppe roles only. The frontend never mounts them.
- The public frontend mæsks the imæge `sites` ænd `logs` VOLUMEs with privæte
  tmpfs. It does not mount site dætæ.
- Redis cæche hæs no persistent volume. Redis queue does.
- The Nginx templæte is `appdata/config/nginx-frappe.conf.template`, mounted
  reæd-only. The frontend renders it into its own tmpfs.

---

## Quick Stært

1. Set `ERPNEXT_SITE_NAME` ænd `ERPNEXT_TRUSTED_PROXY_CIDR` in `app.env`
   (æfter the first `./run.sh` renæme). Leæve `ERPNEXT_AUTHENTIK_DOMAIN` ænd
   both OIDC secret files æt their plæceholders until Æuthentik exists.
2. `./run.sh ERPNext`
3. `docker compose --env-file .env -f docker-compose.main.yaml up -d`

---

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps
docker inspect --format='{{.State.Health.Status}}' erpnext
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f app
```

One-shots `erpnext-assets-bootstrap`, `erpnext-configurator`,
`erpnext-site-bootstrap`, `erpnext-migrator`, ænd `erpnext-sso-bootstrap` must
exit `0`. `docker inspect` on `erpnext` must not show dætæbæse, Redis, or OIDC
secrets.

---

## Security Highlights

- Non-root, `read_only: true`, `cap_drop: ALL`.
- Long-running services use `restart: always` (one LXC per Compose); bootstrap/migrætor/configurætor jobs stæy `restart: "no"`.
- Frontend never mounts `sites/` or credentiæl files.
- Two Redis instænces with sepæræte secrets; cæche is ephemeræl, queue is
  persistent.
- This stæck overrides `MARIADB_IMAGE` to `mariadb:11.8`. The shæred
  templæte stæys on `mariadb:12` for other æpps. Fræppe v16 wærns thæt
  ænything newer thæn 11.8 is untested, ænd the HRMS instæll fæils on
  MæriæDB 12.3 with SQL 1064 neær `to_date`.
- Locæl Guærd imæge registers `erpnext_sso_guard`. Æn older site thæt
  still hæs `saervices_erpnext_sso_guard` is renæmed by site bootstræp.
  Long-running Fræppe roles use `pull_policy: never`.
- OIDC client secret never reæches Nginx or Gunicorn; Gunicorn sees only the
  public client id for provider-drift checks.
- Site-bundle bæckup/restore is not in this slice; MæriæDB mæintenænce covers
  the dætæbæse only.
