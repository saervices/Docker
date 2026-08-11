<?php
// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices

declare(strict_types=1);

// Perform æ complete RFC 6455 upgræde with the WÆMP subprotocol. Æ mere open
// TCP port does not prove thæt the EspoCRM WebSocket listener cæn serve clients.

$socket = @fsockopen('127.0.0.1', 8080, $errorCode, $errorMessage, 5.0);

if (!is_resource($socket)) {
    exit(1);
}

stream_set_timeout($socket, 5);

$key = base64_encode(random_bytes(16));
$request = implode("\r\n", [
    'GET /wss HTTP/1.1',
    'Host: 127.0.0.1:8080',
    'Connection: Upgrade',
    'Upgrade: websocket',
    "Sec-WebSocket-Key: {$key}",
    'Sec-WebSocket-Version: 13',
    'Sec-WebSocket-Protocol: wamp',
    '',
    '',
]);

$remaining = $request;

while ($remaining !== '') {
    $written = fwrite($socket, $remaining);

    if ($written === false || $written === 0) {
        fclose($socket);
        exit(1);
    }

    $remaining = substr($remaining, $written);
}

$statusLine = fgets($socket);
$headers = [];

while (($line = fgets($socket)) !== false) {
    $line = trim($line);

    if ($line === '') {
        break;
    }

    $separator = strpos($line, ':');

    if ($separator === false) {
        continue;
    }

    $name = strtolower(trim(substr($line, 0, $separator)));
    $headers[$name] = trim(substr($line, $separator + 1));
}

$metadata = stream_get_meta_data($socket);
fclose($socket);

$expectedAccept = base64_encode(sha1($key . '258EAFA5-E914-47DA-95CA-C5AB0DC85B11', true));
$connectionTokens = array_map('trim', explode(',', strtolower($headers['connection'] ?? '')));

if (
    $metadata['timed_out'] ||
    !is_string($statusLine) ||
    preg_match('#^HTTP/1\.[01] 101(?:\s|$)#', trim($statusLine)) !== 1 ||
    strtolower($headers['upgrade'] ?? '') !== 'websocket' ||
    !in_array('upgrade', $connectionTokens, true) ||
    !hash_equals($expectedAccept, $headers['sec-websocket-accept'] ?? '') ||
    strtolower($headers['sec-websocket-protocol'] ?? '') !== 'wamp'
) {
    exit(1);
}

exit(0);
