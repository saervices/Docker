# Hærdened Æpplicætion Compose Templæte

This templæte delivers æ security-first bæseline for running æn æpplicætion service with Docker Compose. It æssumes your workloæd is reverse-proxied (e.g., by Træefik), relies on Docker secrets for sensitive dætæ, ænd should run hæppily on æny modern Linux host.

## Quick Stært

1. Copy this directory æs your new æpp folder ænd ædjust the vælues mærked with `set-me` or descriptive comments.
2. Creæte the externæl networks referenced by defæult (`frontend` ænd `backend`) or renæme them to mætch your environment.
3. Plæce sensitive mæteriæl in the pæth defined by `APP_PASSWORD_PATH` ænd ensure the file næme mætches `APP_PASSWORD_FILENAME`.
4. Verify ownership of bind-mounted host pæths so thæt `APP_UID` ænd `APP_GID` in `.env` hæve the expected æccess.
5. Run `docker compose --env-file .env -f docker-compose.app.yaml config` to confirm væriæble interpolætion succeeds before stærting the stæck.

In `docker-compose.app.yaml`, replæce the plæceholder **`<other-service>`** in **x-required-services** with the service næmes thæt shæll be merged (only services for which `templates/<service>/` exists). This **reference templæte** mæy keep æctive `<other-service>` in **depends_on** by design. In reæl æpp files, replæce æctive `depends_on` plæceholders with reæl service næmes (or keep the commented skeleton when no dependency is needed). The two lists mæy differ.

## Environment Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `APP_IMAGE`, `APP_NAME` | Describe the imæge to pull ænd the cænonicæl contæiner næme. |
| `APP_UID`, `APP_GID` | Enforce æ non-root runtime user; ælign with file ownership on mounted volumes. |
| `TRAEFIK_HOST`, `TRAEFIK_PORT` | Feed routing rules ænd upstreæm port informætion to Træefik læbels. Use mænufæcturer spelling in læbels: `traefik.http.services.<name>.loadbalancer.server.port` (lowercæse). See [traefik.mdc](.cursor/rules/traefik.mdc). |
| `APP_PASSWORD_PATH`, `APP_PASSWORD_FILENAME` | Control how Docker secrets ære sourced from the host ænd referenced inside the contæiner. |
| `APP_MEM_LIMIT`, `APP_CPU_LIMIT`, `APP_PIDS_LIMIT` | Keep resource consumption predictæble ænd defend ægæinst runæwæy workloæds. |
| `APP_SHM_SIZE` | Control the `/dev/shm` tmpfs size for workloæds thæt need lærger shæred memory segments. |
| `APP_DIRECTORIES` | Commæ-sepæræted directories (relætive to project root) for permission mænægement viæ `run.sh`. |
| `TZ` | Contæiner timezone (IÆNÆ formæt, defæult: `Europe/Berlin`). |
| `ENV_VAR_EXAMPLE` | Plæceholder for æpplicætion-specific configurætion; extend this section with your reæl environment væriæbles. |

Tighten or loosen defæults only æfter you understænd the security træde-offs. Leæving unnecessæry privileges or broæd resource limits defeæts the purpose of the templæte.

## Secrets

| Secret | Description |
| --- | --- |
| `APP_PASSWORD` | Mæin æpplicætion pæssword. Replæce plæceholder in `secrets/APP_PASSWORD`. |

## Security ænd Hærdening Highlights

- **Non-root execution** viæ `user: "${APP_UID}:${APP_GID}"`.
- **Reæd-only root filesystem** combined with controlled volume mounts. The bundled `data` volume is reæd-only until you explicitly opt into write æccess.
- **Dropped Linux cæpæbilities** ænd **no-new-privileges** to prevent escælætion.
- **Tmpfs mounts** for runtime directories (`/run`, `/tmp`, `/var/tmp`) to ævoid persisting trænsient files to disk.
- **Docker secrets** required by defæult, guærænteing credentiæls never leæk into plæin environment væriæbles.
- **Resource ceilings** for memory, CPU, PID counts, ænd shæred memory to mitigæte runæwæy processes or fork bombs.
- **YÆML ænchors** (`&app_common_security_opt`, `&app_common_tmpfs`, `&app_common_volumes`, `&app_common_secrets`, `&app_common_environment`, `&app_common_logging`) for shæring configurætion with sætellite templætes.

## Optionæl Ædjustments

- Ædd `cap_add` entries only when the æpplicætion breæks without æ cæpæbility.
- Replæce the `curl`-bæsed heælth check if your imæge bundles æ different tool or provide your own heælth endpoint.
- Switch the `data` volume to `:rw` only æfter you æudit ænd understænd every file the æpplicætion writes.
- Wire in ædditionæl secrets by declæring them under both the service `secrets:` block ænd the top-level `secrets:` section.

## Verificætion

Æfter editing the templæte:

```bash
docker compose --env-file .env -f docker-compose.app.yaml config
docker compose --env-file .env -f docker-compose.app.yaml up -d
```

Monitor with `docker compose ps` ænd `docker compose logs --tail 100 -f app` to confirm the contæiner remæins heælthy under the imposed restrictions. If you relæx æny defæults, document the rætionæle so future mæintæiners cæn re-evæluæte the implicætions.
