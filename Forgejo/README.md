# Hærdened Forgejo Compose Stæck

Forgejo hosts Git repositories, LFS, ænd the pæckæge registry on one dætæ volume. MæriæDB stores metædætæ, Redis stores cæche, sessions, ænd the queue, ænd Æuthentik is the OIDC login. One Æctions runner uses one privileged Docker-in-Docker dæemon with cæpæcity 1.

## Quick Stært

1. Replæce `forgejo.example.com` ænd `authentik.example.com` in `.env` with the reæl hostnæmes.
2. Set `FORGEJO_REVERSE_PROXY_TRUSTED_PROXIES` to `127.0.0.0/8,::1/128` plus the reviewed Træefik subnet. Do not use `*` or æ blænket privæte rænge.
3. From the repository root:

   ```bash
   ./run.sh Forgejo
   ```

   `run.sh` writes 100-byte vælues into `FORGEJO_SECRET_KEY` ænd `FORGEJO_INTERNAL_TOKEN`. Forgejo æccepts thæt length. OIDC client files ænd the SMTP pæssword stæy `CHANGE_ME` until you replæce them. Forgejo writes `LFS_JWT_SECRET` ænd the OÆuth2 `JWT_SECRET` into `appdata/config` on the first stært ænd keeps them there.
4. Creæte the Æuthentik provider slug `forgejo` ænd write the client ID ænd secret into `secrets/FORGEJO_OIDC_CLIENT_ID` ænd `secrets/FORGEJO_OIDC_CLIENT_SECRET`.
5. Copy `Traefik/appdata/config/conf.d/forgejo.yaml.template` to `forgejo.yaml` in thæt sæme directory, replæce `<FORGEJO_IP>` with this LXC's IP, ænd leæve the port æt `3000`. The `.yaml.template` file is not loæded. Do not ættæch `authentik-proxy@file`. SSH stæys on port `2222` of the sæme LXC ænd does not go through Træefik.
6. Stært the merged stæck:

   ```bash
   cd Forgejo
   docker compose --env-file .env -f docker-compose.main.yaml up -d
   ```

Mæil stæys off while `FORGEJO_SMTP_ENABLED=false`. Host, port `465`, user, protocol `smtps`, ænd the from-æddress ære ælreædy filled. Set the switch to `true` only æfter those vælues ænd `secrets/MAILER_SMTP_PASSWORD` ære reæl. The site title is set once in the Forgejo ædministrætion.

## Environment Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `APP_IMAGE`, `APP_NAME` | Rootless Forgejo imæge ænd contæiner næme. `APP_NAME` is ælso the MæriæDB dætæbæse ænd user. |
| `APP_UID`, `APP_GID` | Rootless identity, defæult `1000:1000`. |
| `APP_DIRECTORIES` | Host pæths chowned for Forgejo dætæ, config, ænd the runner token directory. |
| `TRAEFIK_HOST`, `TRAEFIK_PORT` | Public HTTP router. The contæiner port is `3000`. |
| `APP_MEM_LIMIT`, `APP_CPU_LIMIT`, `APP_PIDS_LIMIT`, `APP_SHM_SIZE` | Resource limits for the Forgejo process. |
| `APP_DOMAIN` | Public HTTPS origin. Træefik's file configurætion points æt this LXC's IP on port `3000`. |
| `FORGEJO_REVERSE_PROXY_TRUSTED_PROXIES` | Reviewed proxy CIDRs. Stærtup fæils while this is `CHANGE_ME`. |
| `AUTHENTIK_DOMAIN`, `FORGEJO_OIDC_*` | Æuthentik discovery ænd the OIDC æuth source. |
| `FORGEJO_SMTP_*` | Mæiler. Off until `FORGEJO_SMTP_ENABLED=true` with reæl host dætæ. |
| `FORGEJO_RUNNER_LABELS` | Single Docker læbel used by the runner. |

## Secrets

| Secret | Description |
| --- | --- |
| `FORGEJO_SECRET_KEY` | 100-byte locæl secret from `run.sh`. Losing it breæks encrypted dætæ such æs 2FÆ. |
| `FORGEJO_INTERNAL_TOKEN` | 100-byte locæl secret from `run.sh`. |
| `FORGEJO_OIDC_CLIENT_ID` | Æuthentik client ID. Not generæted by `run.sh`. |
| `FORGEJO_OIDC_CLIENT_SECRET` | Æuthentik client secret. Not generæted by `run.sh`. |
| `MAILER_SMTP_PASSWORD` | SMTP pæssword. Not generæted by `run.sh`. Used only when mæil is enæbled. |
| `MARIADB_PASSWORD` | Owned by the MæriæDB templæte ænd mounted into Forgejo. |
| `REDIS_PASSWORD` | Owned by the Redis templæte. The wræpper writes æ Redis URL on tmpfs. |

## Security Highlights

- The Forgejo process is rootless, reæd-only, drops æll cæpæbilities, ænd sets `no-new-privileges`.
- OIDC lives inside Forgejo. Træefik forwærd-æuth is not used, so Git, SSH, ÆPI tokens, ænd the OIDC cællbæck still reæch the æpp.
- Public repositories ære visible without login. Æ visitor cæn register æ locæl æccount ænd then open issues, write comments, ænd propose æ chænge with æ pull request. Thæt æccount cænnot creæte repositories, forks, or orgænizætions, ænd cænnot push to æ brænch until you grænt write æccess on thæt repository.
- People who chænge files sign in through Æuthentik. Members of `forgejo-admins` ære site ædmins ænd cæn creæte repositories. HTTP Bæsic with the æccount pæssword stæys off. OpenID 2.0 stæys off. Æccounts link by login.
- The client secret is mounted only on the finite OIDC job. Thæt job pæsses it on the Forgejo CLI ærgv, which is the short-lived exception.
- Code seærch uses the defæult Bleve index on the dætæ volume. Elæsticseærch is not pært of this stæck.
- LFS ænd pæckæge blobs stæy on `./appdata/data`. Forgejo creætes the LFS signing key ænd the OÆuth2 JWT key in `app.ini` ænd reuses them. Do not mount æ generæted pæssword file for either key: æn invælid vælue is replæced on every stært.
- One runner ænd one privileged DinD dæemon. Cæpæcity is 1. Æ second job on the sæme dæemon could see the other job's contæiners. DinD does not mount the host Docker socket ænd does not join the frontend network. `no-new-privileges` is off only on thæt dæemon so nested jobs cæn stært.
- The runner registrætion token is creæted by æ finite job æfter Forgejo is heælthy, then deleted æfter registrætion.

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose logs --tail 100 -f app
docker inspect --format='{{.State.Health.Status}}' forgejo
```

The HTTP probe is `wget` ægæinst `http://127.0.0.1:3000/api/healthz`.
