#!/usr/bin/env node
// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices
'use strict';

const fs = require('node:fs');
const Module = require('node:module');
const path = require('node:path');
const { TextDecoder } = require('node:util');

const VENDOR_START = '/usr/src/app/server/bin/start.sh';
const VENDOR_CONFIG = '/usr/src/app/server/dist/repositories/config.repository.js';
const LOCK_BASE = '/run/immich-secret-loader-';
const MAX_SECRET_BYTES = 4096;
const MAX_VENDOR_BYTES = 2 * 1024 * 1024;
const LOADER_PATH = '/usr/local/lib/immich-secret-loader.cjs';

const START_SECRET_LINES = [
  'read_file_and_export "DB_URL_FILE" "DB_URL"',
  'read_file_and_export "DB_PASSWORD_FILE" "DB_PASSWORD"',
  'read_file_and_export "REDIS_PASSWORD_FILE" "REDIS_PASSWORD"',
];
const START_REQUIRED_LINES = [
  'read_file_and_export "DB_HOSTNAME_FILE" "DB_HOSTNAME"',
  'read_file_and_export "DB_DATABASE_NAME_FILE" "DB_DATABASE_NAME"',
  'read_file_and_export "DB_USERNAME_FILE" "DB_USERNAME"',
  'exec node "${SERVER_HOME}/dist/main.js" "$@"',
  'exec node --no-warnings "${SERVER_HOME}/dist/main.js" "$@"',
];
const CONFIG_PARSE_LINE = 'const parseResult = env_dto_1.EnvSchema.safeParse(process.env);';
const CONFIG_IMPORT_LINE = 'const node_path_1 = require("node:path");';
const CONFIG_SECRET_IMPORT = `const immich_secret_loader_1 = require("${LOADER_PATH}");`;
const CONFIG_PARSE_REPLACEMENT =
  'const parseResult = env_dto_1.EnvSchema.safeParse((0, immich_secret_loader_1.withDockerSecrets)(process.env));';

function fail(message) {
  throw new Error(`[immich-secret-loader] ${message}`);
}

function countLiteral(source, literal) {
  return source.split(literal).length - 1;
}

function requireExactCount(source, literal, expected, label) {
  const actual = countLiteral(source, literal);
  if (actual !== expected) {
    fail(`Vendor ${label} drift: expected ${expected} exact occurrence(s), found ${actual}. Review the current image before starting.`);
  }
}

function readRegularFile(filePath, maximumBytes, label, requirePrivateMode = false, requireSingleLink = false) {
  let descriptor;
  const flags = fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK;
  try {
    descriptor = fs.openSync(filePath, flags);
    const before = fs.fstatSync(descriptor);
    if (!before.isFile()) {
      fail(`${label} is not a regular file.`);
    }
    if (before.size < 1 || before.size > maximumBytes) {
      fail(`${label} has an invalid length.`);
    }
    if (requireSingleLink && before.nlink !== 1) {
      fail(`${label} must have exactly one hard link.`);
    }
    if (requirePrivateMode && (before.mode & 0o077) !== 0) {
      fail(`${label} permissions are not private.`);
    }

    const bytes = Buffer.alloc(before.size);
    let offset = 0;
    while (offset < bytes.length) {
      const read = fs.readSync(descriptor, bytes, offset, bytes.length - offset, null);
      if (read === 0) {
        fail(`${label} changed while it was read.`);
      }
      offset += read;
    }
    const extra = Buffer.alloc(1);
    if (fs.readSync(descriptor, extra, 0, 1, null) !== 0) {
      fail(`${label} grew while it was read.`);
    }
    const after = fs.fstatSync(descriptor);
    if (before.dev !== after.dev || before.ino !== after.ino || before.size !== after.size) {
      fail(`${label} identity changed while it was read.`);
    }
    return bytes;
  } catch (error) {
    if (error && typeof error.message === 'string' && error.message.startsWith('[immich-secret-loader]')) {
      throw error;
    }
    fail(`${label} could not be opened safely.`);
  } finally {
    if (descriptor !== undefined) {
      fs.closeSync(descriptor);
    }
  }
}

function decodeUtf8(bytes, label) {
  let value;
  try {
    value = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    fail(`${label} is not valid UTF-8.`);
  }
  return value;
}

function decodeSecret(bytes, label) {
  const value = decodeUtf8(bytes, label);
  if (/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/u.test(value)) {
    fail(`${label} contains control characters or line breaks.`);
  }
  if (value === 'CHANGE_ME') {
    fail(`${label} still contains the placeholder value.`);
  }
  return value;
}

function readRequiredSecret(environment, fileVariable, valueVariable, expectedName) {
  if (Object.prototype.hasOwnProperty.call(environment, valueVariable)) {
    fail(`${valueVariable} must not be present in the process environment.`);
  }
  const expectedPath = `/run/secrets/${expectedName}`;
  if (environment[fileVariable] !== expectedPath) {
    fail(`${fileVariable} must reference ${expectedPath}.`);
  }
  const bytes = readRegularFile(expectedPath, MAX_SECRET_BYTES, `${expectedName} secret`, false, true);
  return decodeSecret(bytes, `${expectedName} secret`);
}

function withDockerSecrets(environment) {
  if (Object.prototype.hasOwnProperty.call(environment, 'DB_URL') ||
      Object.prototype.hasOwnProperty.call(environment, 'DB_URL_FILE')) {
    fail('DB_URL and DB_URL_FILE are forbidden; this stack requires the file-only parts contract.');
  }
  if (Object.prototype.hasOwnProperty.call(environment, 'REDIS_URL') ||
      Object.prototype.hasOwnProperty.call(environment, 'REDIS_URL_FILE')) {
    fail('REDIS_URL and REDIS_URL_FILE are forbidden; this stack requires the file-only parts contract.');
  }
  const result = { ...environment };
  result.DB_PASSWORD = readRequiredSecret(
    environment,
    'DB_PASSWORD_FILE',
    'DB_PASSWORD',
    'IMMICH_POSTGRES_PASSWORD',
  );
  result.REDIS_PASSWORD = readRequiredSecret(
    environment,
    'REDIS_PASSWORD_FILE',
    'REDIS_PASSWORD',
    'IMMICH_VALKEY_PASSWORD',
  );
  return result;
}

function readVendorSource(filePath, label) {
  return decodeUtf8(readRegularFile(filePath, MAX_VENDOR_BYTES, label), label);
}

function transformVendorStart(source) {
  if (!source.startsWith('#!/usr/bin/env bash\n')) {
    fail('Vendor start script drift: expected Bash shebang is missing.');
  }
  for (const line of START_REQUIRED_LINES) {
    requireExactCount(source, line, 1, 'start script');
  }
  requireExactCount(source, 'read_file_and_export()', 1, 'start script');
  for (const line of START_SECRET_LINES) {
    requireExactCount(source, line, 1, 'start script');
  }
  requireExactCount(source, 'DB_PASSWORD', 2, 'start script DB password contract');
  requireExactCount(source, 'REDIS_PASSWORD', 2, 'start script Redis password contract');
  requireExactCount(source, 'DB_URL', 2, 'start script DB URL contract');

  let transformed = source;
  for (const line of START_SECRET_LINES) {
    transformed = transformed.replace(line, '# Secret import delegated to the locked config loader.');
  }
  requireExactCount(transformed, 'DB_PASSWORD', 0, 'transformed start script DB file-only contract');
  requireExactCount(transformed, 'REDIS_PASSWORD', 0, 'transformed start script Redis file-only contract');
  requireExactCount(transformed, 'DB_URL', 0, 'transformed start script DB URL contract');
  requireExactCount(transformed, '# Secret import delegated to the locked config loader.', 3, 'transformed start script');
  return transformed;
}

function transformVendorConfig(source) {
  requireExactCount(source, CONFIG_IMPORT_LINE, 1, 'config repository import');
  requireExactCount(source, CONFIG_PARSE_LINE, 1, 'config repository parse');
  requireExactCount(source, 'const getEnv = () => {', 1, 'config repository getEnv');
  requireExactCount(source, 'cached = getEnv();', 1, 'config repository cache');
  requireExactCount(source, "password: dto.DB_PASSWORD || 'postgres',", 1, 'config repository database password');
  requireExactCount(source, 'password: dto.REDIS_PASSWORD || undefined,', 1, 'config repository Redis password');
  requireExactCount(source, 'DB_PASSWORD_FILE', 0, 'config repository DB file contract');
  requireExactCount(source, 'REDIS_PASSWORD_FILE', 0, 'config repository Redis file contract');

  const transformed = source
    .replace(CONFIG_IMPORT_LINE, `${CONFIG_IMPORT_LINE}\n${CONFIG_SECRET_IMPORT}`)
    .replace(CONFIG_PARSE_LINE, CONFIG_PARSE_REPLACEMENT);
  requireExactCount(transformed, CONFIG_SECRET_IMPORT, 1, 'transformed config repository import');
  requireExactCount(transformed, CONFIG_PARSE_REPLACEMENT, 1, 'transformed config repository parse');
  return transformed;
}

function writeLockedFile(filePath, source) {
  const descriptor = fs.openSync(
    filePath,
    fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW,
    0o400,
  );
  try {
    const bytes = Buffer.from(source, 'utf8');
    let offset = 0;
    while (offset < bytes.length) {
      offset += fs.writeSync(descriptor, bytes, offset, bytes.length - offset, null);
    }
    fs.fsyncSync(descriptor);
  } finally {
    fs.closeSync(descriptor);
  }
}

function validateLockDirectory(lockDirectory) {
  const details = fs.lstatSync(lockDirectory);
  if (!details.isDirectory() || details.isSymbolicLink()) {
    fail('Locked runtime path is not a real directory.');
  }
  if (details.uid !== process.getuid() || (details.mode & 0o077) !== 0) {
    fail('Locked runtime directory has unsafe ownership or permissions.');
  }
}

function requireExactLockedSource(lockedSource, expectedSource) {
  if (lockedSource !== expectedSource) {
    fail('Locked config repository does not match the verified vendor transformation.');
  }
}

function prepare() {
  withDockerSecrets(process.env);
  const transformedStart = transformVendorStart(readVendorSource(VENDOR_START, 'vendor start script'));
  const transformedConfig = transformVendorConfig(readVendorSource(VENDOR_CONFIG, 'vendor config repository'));
  const lockDirectory = fs.mkdtempSync(LOCK_BASE);
  try {
    fs.chmodSync(lockDirectory, 0o700);
    validateLockDirectory(lockDirectory);
    writeLockedFile(path.join(lockDirectory, 'start.sh'), transformedStart);
    writeLockedFile(path.join(lockDirectory, 'config.repository.js'), transformedConfig);
    const directoryDescriptor = fs.openSync(lockDirectory, fs.constants.O_RDONLY | fs.constants.O_DIRECTORY);
    try {
      fs.fsyncSync(directoryDescriptor);
    } finally {
      fs.closeSync(directoryDescriptor);
    }
    process.stdout.write(`${lockDirectory}\n`);
  } catch (error) {
    throw error;
  }
}

function installConfigHook() {
  const lockedConfig = process.env.IMMICH_SECRET_LOADER_CONFIG;
  if (!lockedConfig) {
    return;
  }
  const expectedDirectory = path.dirname(lockedConfig);
  if (!expectedDirectory.startsWith(LOCK_BASE) || path.basename(lockedConfig) !== 'config.repository.js') {
    fail('IMMICH_SECRET_LOADER_CONFIG points outside the locked runtime directory.');
  }
  validateLockDirectory(expectedDirectory);

  const expectedSource = transformVendorConfig(readVendorSource(VENDOR_CONFIG, 'vendor config repository'));
  const lockedSource = decodeUtf8(
    readRegularFile(lockedConfig, MAX_VENDOR_BYTES, 'locked config repository', true),
    'locked config repository',
  );
  requireExactLockedSource(lockedSource, expectedSource);

  const originalLoader = Module._extensions['.js'];
  let compiled = false;
  Module._extensions['.js'] = function loadJavaScript(module, filename) {
    if (filename !== VENDOR_CONFIG) {
      return originalLoader(module, filename);
    }
    if (compiled) {
      fail('Vendor config repository was compiled more than once.');
    }
    compiled = true;
    module._compile(lockedSource, filename);
  };
}

module.exports = {
  withDockerSecrets,
  _test: {
    decodeUtf8,
    decodeSecret,
    readRegularFile,
    readRequiredSecret,
    requireExactLockedSource,
    transformVendorConfig,
    transformVendorStart,
  },
};

if (require.main === module) {
  if (process.argv.length !== 3 || process.argv[2] !== '--prepare') {
    fail('Usage: immich-secret-loader.cjs --prepare');
  }
  prepare();
} else {
  installConfigHook();
}
