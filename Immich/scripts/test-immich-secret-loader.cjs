#!/usr/bin/env node
// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const loader = require('./immich-secret-loader.cjs')._test;
let passed = 0;

function pass(label) {
  passed += 1;
  process.stdout.write(`PASS ${label}\n`);
}

function expectFailure(label, callback) {
  assert.throws(callback, /\[immich-secret-loader\]/u);
  pass(label);
}

function validStartSource() {
  return [
    '#!/usr/bin/env bash',
    'read_file_and_export() { :; }',
    'read_file_and_export "DB_URL_FILE" "DB_URL"',
    'read_file_and_export "DB_HOSTNAME_FILE" "DB_HOSTNAME"',
    'read_file_and_export "DB_DATABASE_NAME_FILE" "DB_DATABASE_NAME"',
    'read_file_and_export "DB_USERNAME_FILE" "DB_USERNAME"',
    'read_file_and_export "DB_PASSWORD_FILE" "DB_PASSWORD"',
    'read_file_and_export "REDIS_PASSWORD_FILE" "REDIS_PASSWORD"',
    'exec node --no-warnings "${SERVER_HOME}/dist/main.js" "$@"',
    'exec node "${SERVER_HOME}/dist/main.js" "$@"',
    '',
  ].join('\n');
}

function validConfigSource() {
  return [
    'const node_path_1 = require("node:path");',
    'const getEnv = () => {',
    'const parseResult = env_dto_1.EnvSchema.safeParse(process.env);',
    "password: dto.REDIS_PASSWORD || undefined,",
    "password: dto.DB_PASSWORD || 'postgres',",
    '};',
    'cached = getEnv();',
    '',
  ].join('\n');
}

async function main() {
  const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'immich-secret-loader-test-'));
  fs.chmodSync(temporaryRoot, 0o700);
  const regular = path.join(temporaryRoot, 'regular');
  fs.writeFileSync(regular, 'correct horse battery staple', { mode: 0o600 });

  try {
    const supervisorSource = fs.readFileSync(path.join(__dirname, 'immich-start.sh'), 'utf8');
    assert.doesNotMatch(supervisorSource, /\brm(?:dir)?\b/u);
    pass('runtime wrapper leaves cleanup to the container tmpfs lifecycle');

    assert.equal(loader.decodeSecret(Buffer.from('correct horse battery staple'), 'test secret'), 'correct horse battery staple');
    pass('valid UTF-8 secret');
    expectFailure('placeholder rejection', () => loader.decodeSecret(Buffer.from('CHANGE_ME'), 'test secret'));
    expectFailure('invalid UTF-8 rejection', () => loader.decodeSecret(Buffer.from([0xc3, 0x28]), 'test secret'));
    for (const [label, value] of [
      ['NUL rejection', 'a\u0000b'],
      ['multiline rejection', 'a\nb'],
      ['C1 rejection', 'a\u0085b'],
      ['Unicode line separator rejection', 'a\u2028b'],
      ['Unicode paragraph separator rejection', 'a\u2029b'],
    ]) {
      expectFailure(label, () => loader.decodeSecret(Buffer.from(value), 'test secret'));
    }

    assert.equal(loader.readRegularFile(regular, 4096, 'regular test', false, true).toString(), 'correct horse battery staple');
    pass('regular one-link file acceptance');

    const symlink = path.join(temporaryRoot, 'symlink');
    fs.symlinkSync(regular, symlink);
    expectFailure('symlink rejection', () => loader.readRegularFile(symlink, 4096, 'symlink test', false, true));

    const hardlink = path.join(temporaryRoot, 'hardlink');
    fs.linkSync(regular, hardlink);
    expectFailure('hardlink rejection', () => loader.readRegularFile(regular, 4096, 'hardlink test', false, true));
    fs.unlinkSync(hardlink);

    const fifo = path.join(temporaryRoot, 'fifo');
    assert.equal(spawnSync('mkfifo', [fifo]).status, 0);
    expectFailure('FIFO rejection without blocking', () => loader.readRegularFile(fifo, 4096, 'FIFO test', false, true));

    const existingSocket = ['/var/run/docker.sock', '/run/docker.sock'].find((candidate) => {
      try {
        return fs.lstatSync(candidate).isSocket();
      } catch {
        return false;
      }
    });
    if (existingSocket) {
      expectFailure('socket rejection', () => loader.readRegularFile(existingSocket, 4096, 'socket test', false, true));
    } else {
      const socket = path.join(temporaryRoot, 'socket');
      const server = net.createServer();
      await new Promise((resolve, reject) => server.once('error', reject).listen(socket, resolve));
      expectFailure('socket rejection', () => loader.readRegularFile(socket, 4096, 'socket test', false, true));
      await new Promise((resolve) => server.close(resolve));
    }

    expectFailure('device rejection', () => loader.readRegularFile('/dev/null', 4096, 'device test', false, true));
    const empty = path.join(temporaryRoot, 'empty');
    fs.writeFileSync(empty, '');
    expectFailure('empty-file rejection', () => loader.readRegularFile(empty, 4096, 'empty test', false, true));
    const oversized = path.join(temporaryRoot, 'oversized');
    fs.writeFileSync(oversized, Buffer.alloc(4097, 0x61));
    expectFailure('oversized-file rejection', () => loader.readRegularFile(oversized, 4096, 'oversized test', false, true));

    expectFailure('plain DB environment rejection', () => loader.readRequiredSecret({ DB_PASSWORD: 'forbidden' }, 'DB_PASSWORD_FILE', 'DB_PASSWORD', 'IMMICH_POSTGRES_PASSWORD'));
    expectFailure('plain Redis environment rejection', () => loader.readRequiredSecret({ REDIS_PASSWORD: 'forbidden' }, 'REDIS_PASSWORD_FILE', 'REDIS_PASSWORD', 'IMMICH_VALKEY_PASSWORD'));
    expectFailure('plain DB URL environment rejection', () => require('./immich-secret-loader.cjs').withDockerSecrets({ DB_URL: 'postgresql://user:secret@database/db' }));
    expectFailure('DB URL file environment rejection', () => require('./immich-secret-loader.cjs').withDockerSecrets({ DB_URL_FILE: '/run/secrets/db-url' }));
    expectFailure('plain Redis URL environment rejection', () => require('./immich-secret-loader.cjs').withDockerSecrets({ REDIS_URL: 'redis://:secret@cache:6379' }));
    expectFailure('Redis URL file environment rejection', () => require('./immich-secret-loader.cjs').withDockerSecrets({ REDIS_URL_FILE: '/run/secrets/redis-url' }));

    const startSource = validStartSource();
    const transformedStart = loader.transformVendorStart(startSource);
    assert.equal(transformedStart.includes('DB_PASSWORD'), false);
    assert.equal(transformedStart.includes('REDIS_PASSWORD'), false);
    assert.equal(transformedStart.includes('DB_URL'), false);
    pass('exact vendor start transformation');
    expectFailure('vendor start drift rejection', () => loader.transformVendorStart(startSource.replace('DB_USERNAME_FILE', 'DB_USER_FILE')));
    expectFailure('duplicate vendor start match rejection', () => loader.transformVendorStart(`${startSource}${startSource}`));

    const configSource = validConfigSource();
    const transformedConfig = loader.transformVendorConfig(configSource);
    assert.match(transformedConfig, /withDockerSecrets/u);
    pass('exact vendor config transformation');
    expectFailure('vendor config drift rejection', () => loader.transformVendorConfig(configSource.replace('cached = getEnv();', 'cached = readEnv();')));
    expectFailure('duplicate vendor config match rejection', () => loader.transformVendorConfig(`${configSource}${configSource}`));
    loader.requireExactLockedSource(transformedConfig, transformedConfig);
    pass('locked output acceptance');
    expectFailure('locked output tamper rejection', () => loader.requireExactLockedSource(`${transformedConfig}\n// tampered`, transformedConfig));

    const locked = path.join(temporaryRoot, 'locked');
    fs.writeFileSync(locked, transformedConfig, { mode: 0o400 });
    loader.readRegularFile(locked, 2 * 1024 * 1024, 'locked test', true, true);
    pass('locked mode acceptance');
    fs.chmodSync(locked, 0o640);
    expectFailure('unlocked mode rejection', () => loader.readRegularFile(locked, 2 * 1024 * 1024, 'locked test', true, true));
  } finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
  }

  process.stdout.write(`${passed}/${passed} Immich secret-loader unit tests passed.\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exit(1);
});
