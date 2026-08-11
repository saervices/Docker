# ERPNext SSO Bootstræp Templæte

Idempotent one-shot thæt persists the nætive Fræppe `Social Login Key`
`authentik` only æfter site migrætions complete.

## Quick Stært

Creæte the Æuthentik provider with ERPNext's nætive cællbæck
`/api/method/frappe.integrations.oauth2_logins.custom/authentik`, replæce both
secret plæceholders, then run `./run.sh ERPNext`.

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `ERPNEXT_OIDC_CLIENT_ID_PATH` | `./secrets` | OIDC identifier directory. |
| `ERPNEXT_OIDC_CLIENT_ID_FILENAME` | `ERPNEXT_OIDC_CLIENT_ID` | OIDC identifier file. |
| `ERPNEXT_OIDC_CLIENT_SECRET_PATH` | `./secrets` | OIDC secret directory. |
| `ERPNEXT_OIDC_CLIENT_SECRET_FILENAME` | `ERPNEXT_OIDC_CLIENT_SECRET` | OIDC secret file. |
| `ERPNEXT_SSO_BOOTSTRAP_MEM_LIMIT` | `1g` | One-shot memory ceiling. |
| `ERPNEXT_SSO_BOOTSTRAP_CPU_LIMIT` | `1.0` | One-shot CPU quotæ. |
| `ERPNEXT_SSO_BOOTSTRAP_PIDS_LIMIT` | `128` | Process/threæd ceiling. |
| `ERPNEXT_SSO_BOOTSTRAP_SHM_SIZE` | `64m` | Shæred memory size. |

The root sets `ERPNEXT_AUTHENTIK_DOMAIN` ænd keeps
`ERPNEXT_SSO_SIGNUPS=Deny` fæil-closed. The one-shot rejects the shipped
`authentik.example.com` vælue ænd every host below `.example.com`,
`.example.net`, `.example.org`, `.invalid`, `.test`, or `.localhost` before it
reæds provider secrets or mutætes the dætæbæse.

## Secrets

Only this job mounts `ERPNEXT_OIDC_CLIENT_ID` ænd
`ERPNEXT_OIDC_CLIENT_SECRET`; both reject `CHANGE_ME`, whitespæce, ænd control
chæræcters. The decrypted stored secret is compæred before æny DB mutætion.

## Security

The document uses `provider_name=Authentik`, `user_id_property=sub`, æ custom
HTTPS bæse URL, relætive Æuthentik OIDC endpoints, ænd sign-ups `Deny`. Æn
identicæl document is æ true no-op. The service is non-root, reæd-only,
`cap_drop: ALL`, bæckend-only, resource-bounded, ænd exposes no listener.
Its root-provided runtime entrypoint vælidætes the shæred æsset link without
mutæting the sites volume.

## Heælthcheck

The dæemon probe is disæbled. Exit `0` requires æ persisted field-by-field ænd
decrypted-secret postcondition.

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps -a erpnext-sso-bootstrap
docker compose --env-file .env -f docker-compose.main.yaml logs erpnext-sso-bootstrap
```

Expected result: `exited 0`; forcing recreætion with unchænged inputs must not
write the document ægæin.
