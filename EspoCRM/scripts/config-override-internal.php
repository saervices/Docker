<?php
// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices

declare(strict_types=1);

// Æuthentik OIDC config is kept in æn internæl override so client
// credentiæls never æppeær in Compose environment blocks or docker inspect.

$readSecret = static function (string $name): string {
    $path = "/run/secrets/{$name}";

    if (!is_file($path) || !is_readable($path)) {
        throw new RuntimeException("Required OIDC secret {$name} is missing or unreadable.");
    }

    $contents = file_get_contents($path);

    if ($contents === false) {
        throw new RuntimeException("Required OIDC secret {$name} could not be read.");
    }

    $length = strlen($contents);

    if ($length < 1 || $length > 4096) {
        throw new RuntimeException("Required OIDC secret {$name} has an invalid length.");
    }

    if (hash_equals('CHANGE_ME', $contents)) {
        throw new RuntimeException("Required OIDC secret {$name} still contains the placeholder value.");
    }

    if (preg_match('/[\x00-\x1F\x7F]/', $contents) === 1) {
        throw new RuntimeException("Required OIDC secret {$name} contains control characters.");
    }

    return $contents;
};

$readBool = static function (string $name, bool $default): bool {
    $value = getenv($name);

    if ($value === false || $value === '') {
        return $default;
    }

    $normalized = strtolower(trim($value));

    if (in_array($normalized, ['1', 'true', 'yes', 'on'], true)) {
        return true;
    }

    if (in_array($normalized, ['0', 'false', 'no', 'off'], true)) {
        return false;
    }

    throw new RuntimeException("OIDC boolean setting {$name} is invalid.");
};

$readList = static function (string $name, array $default): array {
    $value = getenv($name);

    if ($value === false || trim($value) === '') {
        return $default;
    }

    $items = array_values(array_filter(preg_split('/[\s,]+/', trim($value)) ?: []));

    if ($items === []) {
        throw new RuntimeException("OIDC list setting {$name} is empty.");
    }

    return $items;
};

$isExampleHost = static function (string $host): bool {
    foreach (['example.com', 'example.net', 'example.org'] as $exampleHost) {
        if ($host === $exampleHost || str_ends_with($host, ".{$exampleHost}")) {
            return true;
        }
    }

    return false;
};

$appDomain = strtolower(trim((string) getenv('APP_DOMAIN')));

if (
    $appDomain === '' ||
    !str_contains($appDomain, '.') ||
    filter_var($appDomain, FILTER_VALIDATE_DOMAIN, FILTER_FLAG_HOSTNAME) === false
) {
    throw new RuntimeException('APP_DOMAIN must be a plain fully-qualified hostname.');
}

if ($isExampleHost($appDomain)) {
    throw new RuntimeException('APP_DOMAIN still contains an example domain.');
}

$traefikHostRule = trim((string) getenv('TRAEFIK_HOST'));

if ($traefikHostRule !== "Host(`{$appDomain}`)") {
    throw new RuntimeException('TRAEFIK_HOST must exactly match Host(`APP_DOMAIN`).');
}

$webSocketUrl = trim((string) getenv('ESPOCRM_CONFIG_WEB_SOCKET_URL'));
$webSocketParts = parse_url($webSocketUrl);

if (
    !is_array($webSocketParts) ||
    ($webSocketParts['scheme'] ?? '') !== 'wss' ||
    strtolower((string) ($webSocketParts['host'] ?? '')) !== $appDomain ||
    ($webSocketParts['path'] ?? '') !== '/wss' ||
    isset($webSocketParts['port']) ||
    isset($webSocketParts['user']) ||
    isset($webSocketParts['pass']) ||
    isset($webSocketParts['query']) ||
    isset($webSocketParts['fragment'])
) {
    throw new RuntimeException('ESPOCRM_CONFIG_WEB_SOCKET_URL must be wss://APP_DOMAIN/wss without port, credentials, query, or fragment.');
}

$authentikDomain = trim((string) getenv('AUTHENTIK_DOMAIN'));

if ($authentikDomain === '') {
    throw new RuntimeException('AUTHENTIK_DOMAIN is required for OIDC.');
}

$authentikBase = preg_match('#^https?://#', $authentikDomain)
    ? rtrim($authentikDomain, '/')
    : 'https://' . rtrim($authentikDomain, '/');
$authentikParts = parse_url($authentikBase);

if (
    !is_array($authentikParts) ||
    ($authentikParts['scheme'] ?? '') !== 'https' ||
    ($authentikParts['host'] ?? '') === '' ||
    isset($authentikParts['user']) ||
    isset($authentikParts['pass']) ||
    isset($authentikParts['query']) ||
    isset($authentikParts['fragment']) ||
    ($authentikParts['path'] ?? '') !== ''
) {
    throw new RuntimeException('AUTHENTIK_DOMAIN must be a plain hostname or HTTPS origin.');
}

$authentikHost = strtolower((string) $authentikParts['host']);

if (
    !str_contains($authentikHost, '.') ||
    filter_var($authentikHost, FILTER_VALIDATE_DOMAIN, FILTER_FLAG_HOSTNAME) === false
) {
    throw new RuntimeException('AUTHENTIK_DOMAIN must contain a valid fully-qualified hostname.');
}

if ($isExampleHost($authentikHost)) {
    throw new RuntimeException('AUTHENTIK_DOMAIN still contains an example domain.');
}

$oidcSlug = trim((string) (getenv('OIDC_SLUG') ?: 'espocrm'), '/');
$reservedOidcSlugs = ['authorize', 'token', 'device', 'userinfo', 'introspect', 'revoke'];

if (
    $oidcSlug === '' ||
    strlen($oidcSlug) > 255 ||
    in_array($oidcSlug, ['.', '..'], true) ||
    in_array(strtolower($oidcSlug), $reservedOidcSlugs, true) ||
    preg_match('/^[A-Za-z0-9._~-]+$/', $oidcSlug) !== 1
) {
    throw new RuntimeException('OIDC_SLUG is invalid.');
}

$oidcScopes = $readList('ESPOCRM_OIDC_SCOPES', ['profile', 'email']);

if (in_array('openid', $oidcScopes, true)) {
    throw new RuntimeException('ESPOCRM_OIDC_SCOPES must omit openid because EspoCRM adds it automatically.');
}

return [
    'adminExtensionUpload' => false,
    'adminUpgradeDisabled' => true,
    'passwordRecoveryForAdminDisabled' => true,
    'authenticationMethod' => 'Oidc',
    'oidcClientId' => $readSecret('ESPOCRM_OIDC_CLIENT_ID'),
    'oidcClientSecret' => $readSecret('ESPOCRM_OIDC_CLIENT_SECRET'),
    'oidcAuthorizationEndpoint' => "{$authentikBase}/application/o/authorize/",
    'oidcTokenEndpoint' => "{$authentikBase}/application/o/token/",
    'oidcUserInfoEndpoint' => "{$authentikBase}/application/o/userinfo/",
    'oidcJwksEndpoint' => "{$authentikBase}/application/o/{$oidcSlug}/jwks/",
    'oidcLogoutUrl' => "{$authentikBase}/application/o/{$oidcSlug}/end-session/",
    'oidcJwtSignatureAlgorithmList' => ['RS256'],
    'oidcScopes' => $oidcScopes,
    'oidcUsernameClaim' => getenv('ESPOCRM_OIDC_USERNAME_CLAIM') ?: 'preferred_username',
    'oidcGroupClaim' => getenv('ESPOCRM_OIDC_GROUP_CLAIM') ?: 'groups',
    'oidcCreateUser' => $readBool('ESPOCRM_OIDC_CREATE_USER', false),
    'oidcSync' => $readBool('ESPOCRM_OIDC_SYNC', true),
    'oidcSyncTeams' => $readBool('ESPOCRM_OIDC_SYNC_TEAMS', false),
    'oidcFallback' => $readBool('ESPOCRM_OIDC_FALLBACK', true),
    'oidcAllowRegularUserFallback' => $readBool('ESPOCRM_OIDC_ALLOW_REGULAR_USER_FALLBACK', false),
    'oidcAllowAdminUser' => $readBool('ESPOCRM_OIDC_ALLOW_ADMIN_USER', false),
    'oidcAuthorizationPkce' => true,
    'oidcAuthorizationPrompt' => getenv('ESPOCRM_OIDC_AUTHORIZATION_PROMPT') ?: 'login',
];
