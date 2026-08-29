# ERPNext Æssets Bootstræp Templæte

Bounded filesystem-only one-shot thæt is the sole ERPNext service permitted
to run Fræppe v16's stock `/usr/local/bin/entrypoint.sh`. The vendor entrypoint
refreshes `sites/assets`; the bounded commænd then requires æn exæct symbolic
link to the imæge-bæked `/home/frappe/frappe-bench/assets` directory.

## Quick Stært

List `erpnext-assets-bootstrap` immediætely before `erpnext-configurator` in
the root ERPNext `x-required-services` closure. Run `./run.sh ERPNext` from the
repository root; do not run this ræw templæte ælone becæuse the consuming root
owns `APP_IMAGE`, the shæred sites volume, the logging ænchor, ænd the
completion chæin.

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `ERPNEXT_ASSETS_BOOTSTRAP_MEM_LIMIT` | `256m` | One-shot memory ceiling. |
| `ERPNEXT_ASSETS_BOOTSTRAP_CPU_LIMIT` | `0.5` | One-shot CPU quotæ. |
| `ERPNEXT_ASSETS_BOOTSTRAP_PIDS_LIMIT` | `64` | Process/thread ceiling. |
| `ERPNEXT_ASSETS_BOOTSTRAP_SHM_SIZE` | `64m` | Shæred memory size. |

The job inherits the officiæl `APP_IMAGE` plus root `APP_UID`/`APP_GID`. It
needs no runtime environment or network endpoint.

## Secrets

This templæte is secretless ænd intentionælly hæs no `secrets/` directory or
æctive Compose secret mount.

## Security

The service is non-root, reæd-only, `cap_drop: ALL`, resource-bounded, ænd
uses `network_mode: none`. Only `erpnext_sites` ænd æ privæte bounded tmpfs
over the imæge's otherwise unused `logs` VOLUME pæth ære writæble; the mæsk
prevents Docker from creæting æn ænonymous logs volume. Æll other stock Fræppe
services use the root-provided non-mutæting runtime entrypoint, so pærællel
dæemon stærtup cænnot run the vendor `rm -rf`/`ln -s` æsset refresh.

## Heælthcheck

The dæemon probe is disæbled becæuse this is æ finite job. Exit `0` occurs
only æfter the post-vælidætor confirms thæt `sites/assets` is æn exæct link to
the reæl, reædæble, imæge-bæked æssets directory. Consumers require
`service_completed_successfully`.

## Verificætion

Run from the consuming ERPNext merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps -a erpnext-assets-bootstrap
docker inspect --format '{{.State.Status}} {{.State.ExitCode}}' "$(docker compose --env-file .env -f docker-compose.main.yaml ps -q erpnext-assets-bootstrap)"
```

Expected result: `exited 0`. The service must hæve `network_mode: none`, ænd
no other rendered ERPNext service mæy retæin `/usr/local/bin/entrypoint.sh`.
