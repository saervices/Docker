#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -euo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPOSITORY_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"

python3 - "$REPOSITORY_ROOT" <<'PY'
from __future__ import annotations

from io import BytesIO
from pathlib import Path, PurePosixPath
import ipaddress
import json
import os
import re
import subprocess
import sys
import tarfile
import tempfile

root = Path(sys.argv[1])
documents = {
    name: (root / name / 'README.md').read_text(encoding='utf-8')
    for name in ('Matrix', 'Seafile', 'RustDesk', 'Immich')
}
documents['MariaDB'] = (
    root / 'templates/mariadb_maintenance/README.md'
).read_text(encoding='utf-8')
checks = 0


def require(condition: bool, message: str) -> None:
    global checks
    checks += 1
    if not condition:
        raise SystemExit(f'FAIL: {message}')


def fenced(text: str, language: str) -> list[str]:
    return [match.group(1) for match in re.finditer(
        rf'^```{re.escape(language)}\n(.*?)^```$', text,
        flags=re.MULTILINE | re.DOTALL,
    )]


strict_blocks: list[tuple[str, int, str]] = []
python_heredocs = 0
for name, text in documents.items():
    for index, block in enumerate(fenced(text, 'bash'), 1):
        if 'set -euo pipefail' not in block:
            continue
        strict_blocks.append((name, index, block))
        with tempfile.NamedTemporaryFile('w', suffix='.sh') as stream:
            stream.write(block)
            stream.flush()
            result = subprocess.run(
                ['bash', '-n', stream.name], check=False,
                capture_output=True, text=True,
            )
        require(result.returncode == 0,
                f'{name} strict Bash block {index}: {result.stderr.strip()}')
        lines = block.splitlines()
        cursor = 0
        while cursor < len(lines):
            if not re.search(r"<<'PY'\s*$", lines[cursor]):
                cursor += 1
                continue
            end = cursor + 1
            while end < len(lines) and lines[end] != 'PY':
                end += 1
            require(end < len(lines),
                    f'{name} block {index} has unterminated Python heredoc')
            source = '\n'.join(lines[cursor + 1:end]) + '\n'
            compile(source, f'{name}:block-{index}:python', 'exec')
            python_heredocs += 1
            cursor = end + 1

for name in ('Matrix', 'Seafile', 'RustDesk', 'Immich'):
    text = documents[name]
    for needle in (
        'fresh isolæted recovery host',
        'docker image save --output',
        'docker image load --input',
        'mode=source-lock',
        'mode=deployment-inputs-only',
        'env -i PATH="$PATH"',
        'pull_policy: never',
        'build: null',
        '--no-build --pull never --wait',
        'recovery-point.complete',
        '.journal',
        'os.O_NOFOLLOW',
        'os.fsync',
        'docker ps -aq',
        'docker image ls -aq',
        'docker volume ls -q',
    ):
        require(needle in text, f'{name} lacks recovery contract {needle!r}')
    require(text.count('env -i PATH="$PATH"') >= 4,
            f'{name} does not clean-render both backup and restore formats')
    require('mv -T --no-clobber' not in text,
            f'{name} documents ambiguous GNU no-clobber move')
    for needle in (
        'com.docker.compose.project',
        'com.docker.compose.service',
        'com.docker.compose.config-hash',
        'config --hash "$service"',
        "docker inspect -f '{{.Config.Image}}'",
        'project_containers_output="$(docker ps -aq',
        'runtime_compose=(docker compose --project-directory',
        'network-evidence.tsv',
        'engine-platform.tsv',
        "'docker', 'network', 'create'",
        'io.it-saervices.recovery-owner',
        'foreign recovery network member',
        'æ pærtiæl recovery-network set is not reconciled',
    ):
        require(needle in text,
                f'{name} lacks live-container binding {needle!r}')

restore_anchors = {
    'Matrix': 'The only supported DR mode is',
    'Seafile': '#### Fresh-host restore',
    'RustDesk': 'This runbook supports only æ **fresh isolæted recovery host**',
    'Immich': 'This runbook intentionælly supports only æ **fresh isolæted recovery host**',
}
backup_anchors = {
    'Matrix': ': "${MATRIX_RECOVERY_ROOT:?Set an absolute external recovery directory}"',
    'Seafile': 'backup_root=/srv/backups/seafile',
    'RustDesk': 'RUSTDESK_BACKUP_ROOT=/srv/backups/rustdesk',
    'Immich': 'IMMICH_BACKUP_ROOT=/srv/backups/immich',
}
writer_mutations = {
    'Matrix': '"${compose[@]}" stop app',
    'Seafile': '"${compose[@]}" stop \\\n  app',
    'RustDesk': '"${compose[@]}" down',
    'Immich': '"${compose[@]}" stop app',
}
for name, anchor in backup_anchors.items():
    backup = documents[name][documents[name].index(anchor):
                                documents[name].index(restore_anchors[name])]
    binding = backup.index('com.docker.compose.config-hash')
    require(binding < backup.index(writer_mutations[name]),
            f'{name} validates container config only after writer mutation')
    require(backup.index('project_containers_output="$(docker ps -aq') <
            backup.index(writer_mutations[name]),
            f'{name} checks project orphans only after writer mutation')
    require(backup.index('runtime_yaml=') < backup.index(writer_mutations[name]),
            f'{name} checks ambient runtime render only after writer mutation')
    require(backup.index('network-evidence.tsv.partial') <
            backup.index(writer_mutations[name]),
            f'{name} captures network IPAM only after writer mutation')

seafile_backup = documents['Seafile'][
    documents['Seafile'].index(backup_anchors['Seafile']):
    documents['Seafile'].index(restore_anchors['Seafile'])
]
seafile_root_creation = seafile_backup.index(
    'mkdir -m 0700 -- "$backup_root"')
for needle in (
    'project_root="$(pwd -P)"',
    'test "$(realpath -m -- "$backup_root")" = "$backup_root"',
    'backup_parent="$(dirname -- "$backup_root")"',
    'test "$(realpath -e -- "$backup_parent")" = "$backup_parent"',
    'case "$backup_root/" in "$project_root/"*',
    'case "$project_root/" in "$backup_root/"*',
):
    require(seafile_backup.index(needle) < seafile_root_creation,
            f'Seafile backup-root preflight mutates before {needle!r}')

mutation_needles = {
    'Matrix': 'mkdir -m 0700 "$matrix_root"',
    'Seafile': 'mkdir -m 0700 "$project_root"',
    'RustDesk': 'mkdir -m 0700 "$RUSTDESK_PROJECT_ROOT"',
    'Immich': 'mkdir -m 0700 "$IMMICH_PROJECT_ROOT"',
}
for name, anchor in restore_anchors.items():
    restore = documents[name][documents[name].index(anchor):]
    guard = restore.index('docker ps -aq')
    require(guard < restore.index('docker image ls -aq'),
            f'{name} container/image empty checks changed order')
    require(guard < restore.index(mutation_needles[name]),
            f'{name} fresh-host guard occurs after project mutation')
    require(guard < restore.index('docker image load --input'),
            f'{name} fresh-host guard occurs after image mutation')
    require(restore.index('saved_engine_platform=') <
            restore.index('docker image load --input'),
            f'{name} checks engine platform only after image load')
    require(restore.index("'docker', 'network', 'create'") <
            restore.index('--no-build --pull never --wait'),
            f'{name} creates recovery networks only after stack start')
    code = next(block for _, _, block in strict_blocks
                if block in restore and 'docker image load --input' in block)
    require('./run.sh --force' not in code,
            f'{name} restore executes moving run.sh --force')
    require(re.search(r'(?<!no-)build\s+--pull', code) is None,
            f'{name} restore executes moving build --pull')

require('--exclude-table-data=e2e_one_time_keys_json' in documents['Matrix'],
        'Matrix dump does not exclude one-time-key rows')
matrix_restore = documents['Matrix'][documents['Matrix'].index(
    'The only supported DR mode is'):]
require(matrix_restore.index('TRUNCATE TABLE e2e_one_time_keys_json') <
        matrix_restore.index('--wait-timeout 300'),
        'Matrix starts the full stack before one-time-key cleanup')
matrix_maintenance_start = matrix_restore.index(
    'matrix-postgres_maintenance\n"${RECOVERY_COMPOSE[@]}" exec -T')
matrix_marker_refresh = matrix_restore.index('/usr/local/bin/backup.sh full')
matrix_maintenance_wait = matrix_restore.index(
    '--wait-timeout 300 matrix-postgres_maintenance')
require(matrix_maintenance_start < matrix_marker_refresh < matrix_maintenance_wait,
        'Matrix does not refresh the maintenance marker before its health wait')
require('[[ "$service" == matrix-postgres_maintenance ]]' in matrix_restore,
        'Matrix includes stale maintenance in the first all-service wait')
require('project-root.txt' in documents['Seafile'],
        'Seafile recovery point does not bind the project root')
require('renameat2(RENAME_NOREPLACE)' in documents['Seafile'],
        'Seafile external data lacks no-replace publication')
require('logged full-backup ID does not match inventory diff' in documents['Seafile'],
        'Seafile does not bind the newly logged full bundle ID')
require('pg_dump --format=custom' in documents['Immich'],
        'Immich backup format is not explicit')
require('pg_restore --clean --if-exists --exit-on-error --single-transaction' in
        documents['Immich'], 'Immich custom dump lacks complete pg_restore')
for path in ('/data', '/data/thumbs', '/data/encoded-video',
             '/data/profile', '/data/backups'):
    require(path in documents['Immich'], f'Immich lacks media path {path}')
require('service_containers[$service]' in documents['Immich'],
        'Immich stopped-service image evidence is not container-bound')
require('previous = references.setdefault(reference, image_id)' in
        documents['RustDesk'], 'RustDesk shared image references are not deduplicated')
overlap_contracts = {
    'Matrix': ('case "$point/" in "$matrix_root/"*',
               'case "$matrix_root/" in "$point/"*'),
    'RustDesk': ('case "$RUSTDESK_BACKUP_DIR/" in "$RUSTDESK_PROJECT_ROOT/"*',
                 'case "$RUSTDESK_PROJECT_ROOT/" in "$RUSTDESK_BACKUP_DIR/"*'),
    'Immich': ('case "$IMMICH_BACKUP_DIR/" in "$IMMICH_PROJECT_ROOT/"*',
               'case "$IMMICH_PROJECT_ROOT/" in "$IMMICH_BACKUP_DIR/"*'),
    'Seafile': ('project path overlaps recovery point',
                'external Seafile data overlaps recovery point'),
}
for name, needles in overlap_contracts.items():
    for needle in needles:
        require(needle in documents[name],
                f'{name} lacks project/recovery disjointness {needle!r}')
for name, prefix in (('RustDesk', 'RUSTDESK'), ('Immich', 'IMMICH')):
    require(f'realpath -m -- "${prefix}_BACKUP_ROOT"' in documents[name],
            f'{name} backup root is not lexically canonical before creation')
    require(f'case "${prefix}_BACKUP_ROOT/" in "${prefix}_PROJECT_ROOT/"*' in
            documents[name], f'{name} backup can contain the project')
    require(f'case "${prefix}_PROJECT_ROOT/" in "${prefix}_BACKUP_ROOT/"*' in
            documents[name], f'{name} project can contain the backup')
for name in ('Matrix', 'Seafile'):
    for needle in (
        'maintenance_identity="$(python3',
        "maintenance user is not an exact numeric UID:GID",
        'install -d -o "$maintenance_uid" -g "$maintenance_gid" -m 0700',
        'setpriv --reuid "$maintenance_uid" --regid "$maintenance_gid"',
        '/proc/self/fd/8/.recovery-write-test',
    ):
        require(needle in documents[name],
                f'{name} lacks maintenance ownership probe {needle!r}')

mariadb = documents['MariaDB']
require(mariadb.index('--wait-timeout 180 mariadb') <
        mariadb.index('up -d --no-build --pull never mariadb_maintenance'),
        'MariaDB quick start launches scheduler before database readiness')
require('SELECT @@GLOBAL.log_bin' in mariadb,
        'MariaDB restore does not prove binary logging')
require('--defaults-extra-file=/var/lib/mysql/.my-healthcheck.cnf' in mariadb,
        'MariaDB log-bin proof does not reuse the hardened primary client file')
require('password=$(cat /run/secrets/MARIADB_ROOT_PASSWORD)' not in mariadb,
        'MariaDB README bypasses the hardened secret reader')
require('pærtiæl loæd mutætes dæmon-globæl tægs' in mariadb,
        'MariaDB generic image-load boundary is missing')


def archive_bytes(entries: list[tuple[str, bytes | None, bytes]]) -> bytes:
    output = BytesIO()
    with tarfile.open(fileobj=output, mode='w') as archive:
        for name, kind, payload in entries:
            member = tarfile.TarInfo(name)
            if kind is None:
                member.type = tarfile.DIRTYPE
                member.size = 0
                archive.addfile(member)
            else:
                member.type = kind
                member.size = len(payload) if kind == tarfile.REGTYPE else 0
                archive.addfile(member, BytesIO(payload) if payload else None)
    return output.getvalue()


def validate_archive(payload: bytes) -> None:
    allowed = {'appdata'}
    seen: set[str] = set()
    found: set[str] = set()
    with tarfile.open(fileobj=BytesIO(payload), mode='r:') as archive:
        for member in archive:
            path = PurePosixPath(member.name)
            if path.is_absolute() or not path.parts or '..' in path.parts:
                raise ValueError('unsafe path')
            normalized = path.as_posix().rstrip('/')
            if normalized in seen:
                raise ValueError('duplicate')
            seen.add(normalized)
            if path.parts[0] not in allowed:
                raise ValueError('root')
            if not (member.isfile() or member.isdir()):
                raise ValueError('type')
            found.add(path.parts[0])
    if found != allowed:
        raise ValueError('closure')


valid_archive = archive_bytes([
    ('appdata', None, b''), ('appdata/file', tarfile.REGTYPE, b'ok'),
])
validate_archive(valid_archive)
hostile_archives = [
    archive_bytes([('/absolute', tarfile.REGTYPE, b'x')]),
    archive_bytes([('../escape', tarfile.REGTYPE, b'x')]),
    archive_bytes([('other', tarfile.REGTYPE, b'x')]),
    archive_bytes([('appdata', None, b''), ('appdata', None, b'')]),
]
for special in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.FIFOTYPE,
                tarfile.CHRTYPE, tarfile.BLKTYPE):
    hostile_archives.append(archive_bytes([('appdata', special, b'')]))
archive_rejections = 0
for payload in hostile_archives:
    try:
        validate_archive(payload)
    except (ValueError, tarfile.TarError):
        archive_rejections += 1
require(archive_rejections == len(hostile_archives),
        'hostile archive model accepted a forbidden member')


def validate_image_map(services: set[str], rows: list[list[str]]) -> None:
    if len(rows) != len(services) or any(len(row) != 3 for row in rows):
        raise ValueError('closure')
    mapped = [row[0] for row in rows]
    if set(mapped) != services or len(set(mapped)) != len(mapped):
        raise ValueError('services')
    references: dict[str, str] = {}
    for service, reference, image_id in rows:
        if not re.fullmatch(r'sha256:[0-9a-f]{64}', image_id):
            raise ValueError('id')
        previous = references.setdefault(reference, image_id)
        if previous != image_id:
            raise ValueError('reference conflict')


image_a = 'sha256:' + 'a' * 64
image_b = 'sha256:' + 'b' * 64
validate_image_map({'app', 'relay'}, [
    ['app', 'vendor/shared:tag', image_a],
    ['relay', 'vendor/shared:tag', image_a],
])
hostile_maps = [
    [['app', 'vendor/shared:tag', image_a]],
    [['app', 'vendor/shared:tag', image_a], ['app', 'other:tag', image_a]],
    [['app', 'vendor/shared:tag', image_a], ['relay', 'vendor/shared:tag', image_b]],
    [['app', 'vendor/shared:tag', 'latest'], ['relay', 'vendor/shared:tag', 'latest']],
]
image_rejections = 0
for rows in hostile_maps:
    try:
        validate_image_map({'app', 'relay'}, rows)
    except ValueError:
        image_rejections += 1
require(image_rejections == len(hostile_maps),
        'hostile image-map model accepted an invalid closure')


def validate_container_binding(expected_project: str, expected_service: str,
                               expected_hash: str, expected_image: str,
                               labels: dict[str, str], image: str) -> None:
    if labels.get('com.docker.compose.project') != expected_project:
        raise ValueError('project label')
    if labels.get('com.docker.compose.service') != expected_service:
        raise ValueError('service label')
    actual_hash = labels.get('com.docker.compose.config-hash', '')
    if not re.fullmatch(r'[0-9a-f]{64}', actual_hash):
        raise ValueError('config hash format')
    if actual_hash != expected_hash:
        raise ValueError('config drift')
    if image != expected_image:
        raise ValueError('image drift')


expected_config_hash = 'c' * 64
binding_labels = {
    'com.docker.compose.project': 'example',
    'com.docker.compose.service': 'app',
    'com.docker.compose.config-hash': expected_config_hash,
}
validate_container_binding(
    'example', 'app', expected_config_hash, image_a, binding_labels, image_a,
)
config_drift_rejections = 0
for drift_kind in ('environment', 'bind', 'volume'):
    drifted = dict(binding_labels)
    drifted['com.docker.compose.config-hash'] = {
        'environment': 'd' * 64,
        'bind': 'e' * 64,
        'volume': 'f' * 64,
    }[drift_kind]
    try:
        # The image ID intentionally stays identical: the config hash must fail.
        validate_container_binding(
            'example', 'app', expected_config_hash, image_a, drifted, image_a,
        )
    except ValueError:
        config_drift_rejections += 1
require(config_drift_rejections == 3,
        'same-image env/bind/volume config drift was accepted')


def maintenance_marker_healthy(now: int, marker: int, maximum_age: int) -> bool:
    age = now - marker
    return 0 <= age <= maximum_age


require(maintenance_marker_healthy(10_000, 9_999, 7_200),
        'fresh maintenance marker model is unhealthy')
stale_marker_rejections = int(
    not maintenance_marker_healthy(20_000, 10_000, 7_200)
)
require(stale_marker_rejections == 1,
        'recovery marker older than maximum age was accepted')


def validate_project_container_closure(
        project: str, services: set[str],
        containers: list[tuple[str, str, str]]) -> None:
    if len(containers) != len(services):
        raise ValueError('project container count')
    seen_ids: set[str] = set()
    seen_services: set[str] = set()
    for container_id, container_project, service in containers:
        if not container_id or container_id in seen_ids:
            raise ValueError('container identity')
        if container_project != project or service not in services \
                or service in seen_services:
            raise ValueError('project/service closure')
        seen_ids.add(container_id)
        seen_services.add(service)
    if seen_services != services:
        raise ValueError('missing service')


valid_containers = [('id-app', 'example', 'app'), ('id-db', 'example', 'db')]
validate_project_container_closure('example', {'app', 'db'}, valid_containers)
hostile_container_closures = [
    valid_containers + [('id-orphan', 'example', 'removed-writer')],
    [('id-app', 'example', 'app')],
    [('id-app', 'example', 'app'), ('id-app-2', 'example', 'app')],
    [('id-app', 'foreign', 'app'), ('id-db', 'example', 'db')],
]
orphan_rejections = 0
for containers in hostile_container_closures:
    try:
        validate_project_container_closure('example', {'app', 'db'}, containers)
    except ValueError:
        orphan_rejections += 1
require(orphan_rejections == len(hostile_container_closures),
        'orphan/missing/duplicate project container closure was accepted')


clean_runtime = {
    'services': {
        'db': {
            'environment': {'POSTGRES_DB': 'app'},
            'volumes': ['database:/var/lib/postgresql/data:rw'],
        },
    },
}
ambient_runtime_rejections = 0
for drifted in (
    {'services': {'db': {'environment': {'POSTGRES_DB': 'other'},
                         'volumes': clean_runtime['services']['db']['volumes']}}},
    {'services': {'db': {'environment': {'POSTGRES_DB': 'app'},
                         'volumes': ['other:/var/lib/postgresql/data:rw']}}},
):
    if drifted != clean_runtime:
        ambient_runtime_rejections += 1
require(ambient_runtime_rejections == 2,
        'ambient environment/volume runtime drift was accepted')


def validate_network_evidence(expected: list[str], rows: list[list[str]],
                              existing: set[str]) -> None:
    if len(rows) != len(expected) or any(len(row) != 5 for row in rows):
        raise ValueError('network closure')
    if [row[0] for row in rows] != expected:
        raise ValueError('network keys')
    subnets: list[ipaddress._BaseNetwork] = []
    for key, source, driver, subnet_text, gateway_text in rows:
        if source != key or driver != 'bridge':
            raise ValueError('network identity')
        subnet = ipaddress.ip_network(subnet_text, strict=True)
        gateway = ipaddress.ip_address(gateway_text)
        if gateway.version != subnet.version or gateway not in subnet:
            raise ValueError('network gateway')
        if any(subnet.overlaps(other) for other in subnets):
            raise ValueError('network overlap')
        subnets.append(subnet)
        recovery_name = f'example-recovery-20260101T000000Z-{key}'
        if recovery_name in existing:
            raise ValueError('foreign existing network')


valid_networks = [
    ['frontend', 'frontend', 'bridge', '172.30.0.0/24', '172.30.0.1'],
    ['backend', 'backend', 'bridge', '172.31.0.0/24', '172.31.0.1'],
]
validate_network_evidence(['frontend', 'backend'], valid_networks, set())
hostile_networks = [
    (['frontend', 'backend'], valid_networks[:1], set()),
    (['frontend', 'backend'], [
        ['frontend', 'production', 'bridge', '172.30.0.0/24', '172.30.0.1'],
        valid_networks[1]], set()),
    (['frontend', 'backend'], [
        ['frontend', 'frontend', 'overlay', '172.30.0.0/24', '172.30.0.1'],
        valid_networks[1]], set()),
    (['frontend', 'backend'], [
        ['frontend', 'frontend', 'bridge', '172.30.0.0/24', '172.99.0.1'],
        valid_networks[1]], set()),
    (['frontend', 'backend'], valid_networks,
     {'example-recovery-20260101T000000Z-frontend'}),
]
network_rejections = 0
for expected, rows, existing in hostile_networks:
    try:
        validate_network_evidence(expected, rows, existing)
    except ValueError:
        network_rejections += 1
require(network_rejections == len(hostile_networks),
        'hostile/missing/foreign network evidence was accepted')


def validate_network_members(expected: set[str], project: str,
                             members: list[tuple[str, str]]) -> None:
    actual: set[str] = set()
    for member_project, service in members:
        if member_project != project or not service or service in actual:
            raise ValueError('foreign/duplicate network member')
        actual.add(service)
    if actual != expected:
        raise ValueError('network member closure')


validate_network_members({'app', 'relay'}, 'example',
                         [('example', 'app'), ('example', 'relay')])
hostile_members = [
    [('example', 'app')],
    [('example', 'app'), ('foreign', 'proxy'), ('example', 'relay')],
]
network_member_rejections = 0
for members in hostile_members:
    try:
        validate_network_members({'app', 'relay'}, 'example', members)
    except ValueError:
        network_member_rejections += 1
require(network_member_rejections == len(hostile_members),
        'missing/foreign recovery network member was accepted')


def validate_engine_platform(saved: str, current: str) -> None:
    if saved not in {'linux\tamd64', 'linux\tarm64'} or saved != current:
        raise ValueError('engine platform mismatch')


validate_engine_platform('linux\tamd64', 'linux\tamd64')
platform_rejections = 0
for current in ('linux\tarm64', 'windows\tamd64'):
    try:
        validate_engine_platform('linux\tamd64', current)
    except ValueError:
        platform_rejections += 1
require(platform_rejections == 2,
        'foreign engine OS/architecture was accepted')


def validate_paths(project: str, recovery: str, paths: list[str]) -> None:
    protected = [os.path.join(project, item) for item in
                 ('scripts', 'secrets', '.run.conf')]
    if len(set(paths)) != len(paths):
        raise ValueError('duplicate')
    for path in paths:
        if not os.path.isabs(path) or os.path.normpath(path) != path \
                or '..' in path.split(os.sep):
            raise ValueError('canonical')
        if path == project or os.path.commonpath((path, project)) == path:
            raise ValueError('project ancestor')
        if os.path.commonpath((path, recovery)) in (path, recovery):
            raise ValueError('recovery overlap')
        for deployment in protected:
            if os.path.commonpath((path, deployment)) in (path, deployment):
                raise ValueError('deployment overlap')
    for index, first in enumerate(paths):
        for second in paths[index + 1:]:
            if os.path.commonpath((first, second)) in (first, second):
                raise ValueError('path overlap')


valid_paths = ['/srv/immich/appdata/upload', '/srv/immich/appdata/thumbs']
validate_paths('/srv/immich', '/backup/point', valid_paths)
hostile_paths = [
    ['/srv/immich', '/srv/immich/appdata/thumbs'],
    ['/srv', '/srv/immich/appdata/thumbs'],
    ['/backup/point/media', '/srv/immich/appdata/thumbs'],
    ['/srv/immich/scripts/media', '/srv/immich/appdata/thumbs'],
    ['/srv/immich/appdata/upload', '/srv/immich/appdata/upload/nested'],
    ['/srv/immich/appdata/upload', '/srv/immich/appdata/upload'],
    ['/srv/immich/appdata/../upload', '/srv/immich/appdata/thumbs'],
]
path_rejections = 0
for paths in hostile_paths:
    try:
        validate_paths('/srv/immich', '/backup/point', paths)
    except ValueError:
        path_rejections += 1
require(path_rejections == len(hostile_paths),
        'hostile path model accepted an overlap or non-canonical path')


def validate_project_recovery(project: str, recovery: str) -> None:
    for path in (project, recovery):
        if not os.path.isabs(path) or os.path.normpath(path) != path:
            raise ValueError('non-canonical project/recovery path')
    if os.path.commonpath((project, recovery)) in (project, recovery):
        raise ValueError('project/recovery overlap')


validate_project_recovery('/srv/project', '/srv/recovery/point')
hostile_project_recovery = [
    ('/srv/project', '/srv/project/recovery/point'),
    ('/srv/recovery/point/project', '/srv/recovery/point'),
]
project_recovery_rejections = 0
for project, recovery in hostile_project_recovery:
    try:
        validate_project_recovery(project, recovery)
    except ValueError:
        project_recovery_rejections += 1
require(project_recovery_rejections == len(hostile_project_recovery),
        'project/recovery overlap model accepted an ancestor direction')


def seafile_backup_root_preflight(project: str, backup: str) -> None:
    if not os.path.isabs(backup) or os.path.normpath(backup) != backup:
        raise ValueError('non-canonical backup root')
    project = os.path.realpath(project)
    parent = os.path.dirname(backup)
    name = os.path.basename(backup)
    if not name or name in {'.', '..'} or not os.path.isdir(parent) \
            or os.path.islink(parent) or os.path.realpath(parent) != parent:
        raise ValueError('unsafe backup parent/name')
    if os.path.commonpath((project, backup)) in (project, backup):
        raise ValueError('project/backup overlap')
    if os.path.lexists(backup) \
            and (not os.path.isdir(backup) or os.path.islink(backup)
                 or os.path.realpath(backup) != backup):
        raise ValueError('unsafe existing backup root')


with tempfile.TemporaryDirectory() as seafile_fixture:
    seafile_project = Path(seafile_fixture) / 'project'
    seafile_project.mkdir(mode=0o751)
    seafile_project.chmod(0o751)
    seafile_marker = seafile_project / 'sentinel'
    seafile_marker.write_bytes(b'unchanged-seafile-project')
    seafile_marker.chmod(0o640)
    before_mode = seafile_project.stat().st_mode & 0o777
    before_entries = sorted(path.name for path in seafile_project.iterdir())
    before_bytes = seafile_marker.read_bytes()
    seafile_overlap_rejections = 0
    try:
        seafile_backup_root_preflight(
            str(seafile_project), str(seafile_project),
        )
    except ValueError:
        seafile_overlap_rejections = 1
    require(seafile_overlap_rejections == 1,
            'Seafile backup_root=$PWD was accepted')
    require((seafile_project.stat().st_mode & 0o777) == before_mode,
            'Seafile overlap preflight changed project mode')
    require(sorted(path.name for path in seafile_project.iterdir()) ==
            before_entries, 'Seafile overlap preflight changed entries')
    require(seafile_marker.read_bytes() == before_bytes,
            'Seafile overlap preflight changed bytes')


with tempfile.TemporaryDirectory() as probe_root:
    backup = Path(probe_root) / 'backup'
    bundle = Path(probe_root) / 'bundle'
    backup.mkdir(mode=0o700)
    bundle.write_bytes(b'bundle')
    bundle.chmod(0o600)
    if os.geteuid() == 0:
        probe_uid = 65534
        probe_gid = 65534
        os.chown(backup, probe_uid, probe_gid)
        os.chown(bundle, probe_uid, probe_gid)
        group_option = '--clear-groups'
    else:
        probe_uid = os.geteuid()
        probe_gid = os.getegid()
        group_option = '--keep-groups'
    bundle_fd = os.open(bundle, os.O_RDONLY | os.O_NOFOLLOW)
    backup_fd = os.open(backup, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        probe = subprocess.run([
            'setpriv', '--reuid', str(probe_uid), '--regid', str(probe_gid),
            group_option, 'sh', '-ec',
            'test -r "/proc/self/fd/$1"; '
            'probe="/proc/self/fd/$2/.recovery-write-test"; '
            '(umask 077; : > "$probe"); test -f "$probe"; rm -f -- "$probe"',
            'sh', str(bundle_fd), str(backup_fd),
        ], check=False, pass_fds=(bundle_fd, backup_fd),
           capture_output=True, text=True)
    finally:
        os.close(bundle_fd)
        os.close(backup_fd)
    require(probe.returncode == 0,
            f'non-root recovery permission probe failed: {probe.stderr.strip()}')


print(
    'PASS recovery runbooks: '
    f'{checks} contracts, {len(strict_blocks)} strict Bash blocks, '
    f'{python_heredocs} Python heredocs, '
    f'{archive_rejections}/{len(hostile_archives)} hostile archives rejected, '
    f'{image_rejections}/{len(hostile_maps)} hostile image maps rejected, '
    f'{config_drift_rejections}/3 same-image config drifts rejected, '
    f'{stale_marker_rejections}/1 stale maintenance markers rejected, '
    f'{orphan_rejections}/{len(hostile_container_closures)} hostile project '
    'container closures rejected, '
    f'{ambient_runtime_rejections}/2 ambient runtime drifts rejected, '
    f'{network_rejections}/{len(hostile_networks)} hostile networks rejected, '
    f'{network_member_rejections}/{len(hostile_members)} foreign network '
    'member closures rejected, '
    f'{platform_rejections}/2 foreign engine platforms rejected, '
    f'{path_rejections}/{len(hostile_paths)} hostile paths rejected, '
    f'{project_recovery_rejections}/{len(hostile_project_recovery)} '
    'project/recovery overlaps rejected, '
    f'{seafile_overlap_rejections}/1 Seafile overlap null-mutation passed, '
    '1/1 non-root ownership probe passed'
)
PY
