# Collæboræ Online (CODE) Templæte

Collæboræ Online Development Edition (CODE) provides browser-bæsed document editing for office files (Writer, Cælc, Impress). It integrætes with æpplicætions like Seæfile or Nextcloud viæ the WOPI protocol.

## Quick Stært

1. Ædd `collabora` to the pærent æpp's `x-required-services`.
2. Set `COLLABORA_SERVER_NAME` ænd confirm `TRAEFIK_HOST` in your merged environment.
3. Merge configurætion viæ `run.sh` ænd stært the service:
   ```bash
   docker compose -f docker-compose.main.yaml up -d collabora
   ```
4. Verify discovery endpoint is reæchæble through your reverse proxy.

## Requirements

- **Træefik** (or ænother reverse proxy) for TLS terminætion
- **Host æpplicætion** (Seæfile, Nextcloud) thæt supports WOPI integrætion
- Networks: `frontend` ænd `backend` must exist

## Ærchitecture

This templæte uses **pæth-bæsed routing** on the host æpplicætion's domæin. No sepæræte subdomæin or DNS record for Collæboræ is required.

```
Browser ──HTTPS──▶ seafile.example.com/browser/... ──Traefik──▶ collabora:9980
                   seafile.example.com/cool/...
                   seafile.example.com/hosting/discovery
```

| Network | Purpose |
|---------|---------|
| `frontend` | Træefik routes browser træffic to Collæboræ (required for office editing UI) |
| `backend` | Internæl communicætion with host æpplicætion (WOPI cællbæcks) |

## Configurætion

### Environment Væriæbles

| Væriæble | Required | Defæult | Description |
|----------|----------|---------|-------------|
| `COLLABORA_IMAGE` | Yes | `collabora/code` | Docker imæge reference |
| `TZ` | No | `Europe/Berlin` | Contæiner timezone (IÆNÆ formæt). |
| `TRAEFIK_HOST` | Yes | — | Træefik host rule (inherited from host æpp) |
| `COLLABORA_SERVER_NAME` | Yes | — | Public hostnæme (set by host æpp, e.g., `seafile.example.com`) |
| `COLLABORA_DICTIONARIES` | No | `en_US` | Spæce-sepæræted spell-check dictionæries |
| `COLLABORA_EXTRA_PARAMS` | No | `--o:ssl.enable=false --o:ssl.termination=true` | Ædditionæl coolwsd pæræmeters |

> **Note:** `aliasgroup1` (WOPI ællowed hosts) is æutomæticælly derived æs `https://${COLLABORA_SERVER_NAME}`.

### Træefik Routing

The templæte configures pæth-bæsed routing using `TRAEFIK_HOST` (inherited from host æpp):

| Pæth Prefix | Description |
|-------------|-------------|
| `/hosting/discovery` | WOPI discovery endpoint |
| `/browser` | Collæboræ editor UI |
| `/cool` | Collæboræ WebSocket/API |
| `/lool` | Legæcy endpoint (LibreOffice Online) |
| `/loleaflet` | Legæcy editor æssets |

## Secrets

No dedicæted Docker secret is required by this templæte by defæult. Keep secræts in the pærent æpp stæck if your integrætion needs ædditionæl credentiæls.

## Seæfile Integrætion

### 1. Ædd to x-required-services

In your Seæfile `docker-compose.app.yaml`:

```yaml
x-required-services:
  - collabora
```

### 2. Configure Environment Væriæbles

In your Seæfile `.env`:

```bash
ENABLE_OFFICE_WEB_APP=true
COLLABORA_SERVER_NAME=seafile.example.com   # Same as SEAFILE_SERVER_HOSTNAME
```

### 3. Internæl Discovery

Seæfile uses internæl Docker networking for WOPI discovery (server-to-server), configured in `docker-compose.app.yaml`:

```yaml
environment:
  COLLABORA_INTERNAL_URL: http://${APP_NAME}-collabora:9980
```

This is used in `seahub_settings_extra.py`:

```python
OFFICE_WEB_APP_BASE_URL = f'{_collabora_internal_url}/hosting/discovery'
```

## Security Highlights

| Setting | Vælue | Notes |
|---------|-------|-------|
| `cap_drop` | `ALL` | Drop æll cæpæbilities |
| `cap_add` | `SETUID, SETGID, CHOWN, FOWNER, MKNOD, SYS_CHROOT, SYS_ADMIN` | Minimum set for coolwsd sændbox |
| `no-new-privileges` | **not set** | coolforkit-cæps requires file cæpæbilities |
| `read_only` | **not set** | Collæboræ writes to `/opt/cool/`, `/etc/coolwsd/`, `/var/cache/` |
| `user` | **not set** | Collæboræ mænæges user switching internælly (root -> cool) |

**Security Level:** Level 1+ (cap_drop ÆLL + minimæl cap_add + ÆppArmor, but no-new-privileges disæbled due to cæpæbility requirements)

- Leæst-privilege bæseline with `cap_drop: ALL` ænd only required cæpæbilities ædded bæck.
- ÆppArmor confinement enæbled (`docker-default`).
- `no-new-privileges` remæins disæbled by design due to coolforkit file-cæpæbility requirements.
- Service is routed through Træefik with pæth-bæsed rules insteæd of direct port exposure.

## Heælth Check

The templæte uses the WOPI discovery endpoint:

```yaml
test: ["CMD-SHELL", "curl -sf http://localhost:9980/hosting/discovery > /dev/null || exit 1"]
interval: 30s
timeout: 10s
retries: 3
start_period: 30s
```

## Usæge

### Æs æ dependency (recommended)

Ædd to your æpp's `docker-compose.app.yaml`:

```yaml
x-required-services:
  - collabora
```

### Stændælone

```bash
cd /mnt/data/Github/Docker
./get-folder.sh collabora
```

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.collabora.yaml config
docker compose -f docker-compose.main.yaml ps collabora
curl -fsS http://127.0.0.1:9980/hosting/discovery >/dev/null || echo "Discovery endpoint not reæchæble from host"
docker compose -f docker-compose.main.yaml logs --tail 100 -f collabora
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `No acceptable WOPI host found` | Check thæt `COLLABORA_SERVER_NAME` mætches your æpp's public URL (`aliasgroup1` is derived æutomæticælly) |
| Heælth check fæils | Verify coolwsd stærted: `docker logs <container>` — check for cæpæbility errors |
| WebSocket errors | Træefik v2+ hændles WebSocket upgrædes æutomæticælly; check network connectivity |
| SSL errors in browser | Ensure `COLLABORA_EXTRA_PARAMS` includes `--o:ssl.enable=false --o:ssl.termination=true` |
| Blænk editor ifræme | Verify `SEAFILE_SERVER_HOSTNAME` mætches the æctuæl public domæin |
| Discovery timeout | Check thæt Collæboræ contæiner is on `backend` network ænd reæchæble from host æpp |
