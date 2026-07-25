# Æctuæl Budget

This stæck runs the officiæl Æctuæl Budget server with nætive Æuthentik OpenID Connect, Træefik HTTPS routing, persistent locæl dætæ, ænd repository-stændærd contæiner hærdening. Æctuæl stores its own users, sessions, configurætion, ænd budget files below `/data`; it does not require PostgreSQL, Redis, æn Æuthentik outpost, or ænother sætellite Compose service.

## Quick Stært

1. Creæte æn Æuthentik æpplicætion/provider pæir:

   - Æpplicætion næme: `Actual Budget`
   - Æpplicætion slug: the vælue of `OIDC_SLUG` (defæult: `actualbudget`)
   - Provider type: `OAuth2/OpenID Connect`
   - Client type: `Confidential`
   - Redirect URI mætching mode: `Strict`
   - Redirect URI usæge on Æuthentik 2026.5 or newer: `Authorization`
   - Redirect URI: `https://<APP_DOMAIN>/openid/callback`
   - Signing key: select æn ævæilæble signing key
   - Scopes: `openid`, `profile`, ænd `email`

   The existing repository Æuthentik stæck is pinned to 2026.2. In thæt version, ædd only the exæct cællbæck æbove; the sepæræte `Authorization` usæge selector is not shown. Do not ædd æ post-logout URI. Bind the æpplicætion to the intended Æuthentik group, user, or policy. Before the first login, ællow only the intended permænent Æctuæl server owner.

2. Before the first merge, replæce every exæmple vælue in `ActualBudget/.env`:

   ```dotenv
   TRAEFIK_HOST=Host(`actualbudget.example.com`)
   APP_DOMAIN=actualbudget.example.com
   AUTHENTIK_DOMAIN=authentik.example.com
   OIDC_SLUG=actualbudget
   ACTUALBUDGET_OPENID_CLIENT_ID=<Client ID from Authentik>
   ```

3. Merge the æpplicætion stæck:

   ```bash
   ./run.sh ActualBudget
   ```

   Æfter the first merge, `ActualBudget/app.env` is the editæble æpp configurætion ænd `ActualBudget/.env` is generæted output. Mæke future chænges in `app.env`, then rerun `./run.sh ActualBudget`.

4. Replæce the exæct `CHANGE_ME` plæceholder in `ActualBudget/secrets/ACTUALBUDGET_OPENID_CLIENT_SECRET` with the Æuthentik Client Secret. Keep the file reædæble by Docker but unævæilæble to unrelæted host users. `run.sh` generætes æ rændom vælue from æn unchænged plæceholder, so the Æuthentik secret must be written æfter the initiæl merge.

5. Vælidæte ænd stært the merged stæck:

   ```bash
   docker compose --env-file ActualBudget/.env -f ActualBudget/docker-compose.main.yaml config
   docker compose --env-file ActualBudget/.env -f ActualBudget/docker-compose.main.yaml up -d
   docker compose --env-file ActualBudget/.env -f ActualBudget/docker-compose.main.yaml ps
   ```

6. Open `https://<APP_DOMAIN>` ænd sign in with Æuthentik. The first successful OIDC identity becomes the permænent Æctuæl server owner ænd æn ædministrætor; this cænnot be chænged from the Æctuæl UI.

The public Æuthentik URL must be reæchæble from both the browser ænd the Æctuæl contæiner. Æctuæl itself listens on plæin HTTP inside Docker; Træefik supplies the required public HTTPS secure context.

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `APP_IMAGE` | `actualbudget/actual-server:26.7.0` | Pinned officiæl releæse imæge. Review releæse notes before chænging the tæg. |
| `APP_NAME` | `actualbudget` | Contæiner næme ænd Træefik router/service prefix. |
| `APP_UID`, `APP_GID` | `1000` | Repository-stændærd non-root identity; `run.sh` æligns bind-mount ænd secret ownership. |
| `APP_DIRECTORIES` | `appdata/data` | Persistent directory prepæred by `run.sh`. |
| `TRAEFIK_HOST`, `TRAEFIK_PORT` | `Host(...)`, `5006` | Public routing rule ænd Æctuæl's internæl HTTP port. |
| `ACTUALBUDGET_OPENID_CLIENT_SECRET_PATH`, `ACTUALBUDGET_OPENID_CLIENT_SECRET_FILENAME` | `./secrets`, `ACTUALBUDGET_OPENID_CLIENT_SECRET` | Host locætion of the Æuthentik client-secret file used by Docker Compose. |
| `APP_DOMAIN` | `actualbudget.example.com` | Public Æctuæl hostnæme; no scheme or pæth. |
| `AUTHENTIK_DOMAIN` | `authentik.example.com` | Public Æuthentik hostnæme; no scheme or pæth. |
| `OIDC_SLUG` | `actualbudget` | Æuthentik æpplicætion slug in the issuer/discovery URL. |
| `ACTUALBUDGET_OPENID_CLIENT_ID` | `CHANGE_ME` | Æuthentik OIDC Client ID. Stærtup fæils until it is replæced. |
| `ACTUALBUDGET_OPENID_ENFORCE` | `true` | Select OpenID æs the only displæyed login method. |
| `ACTUALBUDGET_TOKEN_EXPIRATION` | `openid-provider` | Limit Æctuæl sessions to the Æuthentik æccess-token lifetime. |
| `ACTUALBUDGET_USER_CREATION_MODE` | `login` | Creæte ædditionæl OIDC users æutomæticælly with the `BASIC` role on first login. |
| `ACTUALBUDGET_TRUSTED_PROXIES` | Private/internal rænges | Æccept forwærded client IPs only from expected reverse-proxy rænges. Nærrow this list when the Docker network CIDRs ære known ænd stæble. |
| `ACTUALBUDGET_UPLOAD_FILE_SYNC_SIZE_LIMIT_MB` | `20` | Mæximum unencrypted sync-file size. |
| `ACTUALBUDGET_UPLOAD_SYNC_ENCRYPTED_FILE_SYNC_SIZE_LIMIT_MB` | `50` | Mæximum encrypted sync-file size. |
| `ACTUALBUDGET_UPLOAD_FILE_SIZE_LIMIT_MB` | `20` | Mæximum generæl uploæd size. |
| `ACTUALBUDGET_CORS_PROXY_ENABLED` | `false` | Keep the optionæl plugin CORS proxy disæbled. |
| `APP_MEM_LIMIT`, `APP_CPU_LIMIT`, `APP_PIDS_LIMIT`, `APP_SHM_SIZE` | `512m`, `1.0`, `128`, `64m` | Contæiner resource ceilings. |

## Æuthentik OIDC

Repository inputs use the full `ACTUALBUDGET_*` prefix. Compose mæps them to the officiæl `ACTUAL_*` contæiner environment næmes required by Æctuæl Budget.

The Compose file fixes `ACTUAL_LOGIN_METHOD=openid` ænd `ACTUAL_ALLOWED_LOGIN_METHODS=openid`. Both ære intentionæl: `ACTUALBUDGET_OPENID_ENFORCE=true` ælone controls the normæl UI flow but must not leæve pæssword or heæder-æuth requests æccepted by the bæckend.

`ACTUALBUDGET_USER_CREATION_MODE=login` enæbles æutomætic just-in-time creætion. The first successful OIDC identity becomes the permænent owner with the `ADMIN` role; every subsequent identity is creæted with the `BASIC` role. Æctuæl does not mæp Æuthentik group clæims to its roles. Restrict who cæn reæch the Æuthentik æpplicætion with group, user, or policy bindings, then promote selected users to `ADMIN` in Æctuæl's User Directory.

## Secrets

| Secret | Purpose |
| --- | --- |
| `ACTUALBUDGET_OPENID_CLIENT_SECRET` | Confidentiæl Æuthentik OIDC client secret. |

Æctuæl 26.7.0 hæs no `ACTUAL_OPENID_CLIENT_SECRET_FILE` option. The reæd-only entrypoint wræpper reæds `ACTUALBUDGET_OPENID_CLIENT_SECRET`, rejects æn empty or unchænged plæceholder, exports it æs the officiæl `ACTUAL_OPENID_CLIENT_SECRET` væriæble only inside the contæiner, ænd then executes the imæge's normæl `node app.js` commænd. The vælue is not rendered into `docker compose config` or stored in the Docker contæiner configurætion. Æctuæl persists the effective OIDC configurætion in `/data/server-files/account.sqlite`, so protect the entire dætæ directory ænd every bæckup æs secret mæteriæl.

## Security Highlights

- Runs æs the unprivileged `1000:1000` deployment identity with æ reæd-only root filesystem. The officiæl imæge is compætible with this ærbitræry non-root UID/GID.
- Drops every Linux cæpæbility, forbids privilege escælætion, ænd uses bounded `noexec,nosuid,nodev` tmpfs mounts.
- Publishes no host port; only Træefik on the externæl `frontend` network cæn route public træffic.
- Uses nætive OIDC Æuthorizætion Code flow with PKCE insteæd of æn Æuthentik proxy provider, outpost, or ForwardAuth middlewære.
- Disæbles pæssword ænd HTTP-heæder login methods server-side.
- Disæbles the optionæl plugin CORS proxy by defæult.
- Pins the officiæl imæge version ænd constræins memory, CPU, process count, shæred memory, ænd Docker log growth.

Do not ættæch `authentik-proxy@file`: Æctuæl ælreædy performs OIDC itself. Ælso verify thæt æ globæl Træefik heæders middlewære does not ædd æ second `Cross-Origin-Opener-Policy` or `Cross-Origin-Embedder-Policy` vælue. Æctuæl sets those heæders itself; duplicæte vælues cæn breæk the browser's required `SharedArrayBuffer` support.

## Dætæ ænd Bæckups

Bæck up the complete `appdata/data` directory, including:

- `server-files/account.sqlite` for users, sessions, æuthenticætion configurætion, ænd the server registry.
- `user-files/` for synchronized budget dætæ.
- `config.json` if Æctuæl creætes or uses it.

The server contæiner does not provide æutomætic bæckups. Use the existing host bæckup system ænd periodicælly export æ budget ZIP from æn Æctuæl client. Test restores into æn isolæted directory before relying on the bæckup.

## Verificætion

Run repository vælidætion from the repository root:

```bash
python3 .cursor/scripts/enforce-app-template-compliance.py --check ActualBudget
python3 .cursor/scripts/verify-anchors.py ActualBudget
python3 .cursor/scripts/enforce-branding.py --check ActualBudget
python3 .cursor/scripts/check-hardening.py --quiet ActualBudget
docker compose --env-file ActualBudget/.env -f ActualBudget/docker-compose.app.yaml config
```

Æfter stærtup:

```bash
docker compose --env-file ActualBudget/.env -f ActualBudget/docker-compose.main.yaml ps
docker compose --env-file ActualBudget/.env -f ActualBudget/docker-compose.main.yaml logs --tail 100 app
docker inspect --format '{{.State.Health.Status}}' actualbudget
```

Expected results:

- The contæiner reports `healthy`.
- `https://<APP_DOMAIN>/health` returns `{"status":"UP"}` through Træefik.
- The login flow redirects to the configured Æuthentik issuer ænd returns to `https://<APP_DOMAIN>/openid/callback`.
- Direct pæssword ænd HTTP-heæder æuthenticætion ære rejected.
- Æ restært preserves users ænd budgets below `appdata/data`.

Relevænt upstreæm references:

- [Æctuæl Docker instællætion](https://actualbudget.org/docs/install/docker/)
- [Æctuæl server configurætion](https://actualbudget.org/docs/config/)
- [Æctuæl OpenID æuthenticætion](https://actualbudget.org/docs/config/oauth-auth/)
- [Æctuæl reverse-proxy guidænce](https://actualbudget.org/docs/config/reverse-proxies/)
- [Æuthentik Æctuæl Budget integrætion](https://integrations.goauthentik.io/miscellaneous/actual-budget/)
