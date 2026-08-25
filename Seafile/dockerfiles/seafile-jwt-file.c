// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices

#define _GNU_SOURCE

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define JWT_SECRET_PATH "/run/secrets/JWT_PRIVATE_KEY"
#define DATABASE_SECRET_PATH "/run/secrets/MARIADB_PASSWORD"
#define REDIS_SECRET_PATH "/run/secrets/REDIS_PASSWORD"
#define JWT_SECRET_MIN_BYTES 32U
#define PASSWORD_SECRET_MIN_BYTES 12U
#define JWT_SECRET_MAX_BYTES 4096U

typedef const char *(*g_getenv_function)(const char *variable);

static pthread_once_t resolver_once = PTHREAD_ONCE_INIT;
static pthread_once_t jwt_secret_once = PTHREAD_ONCE_INIT;
static pthread_once_t database_secret_once = PTHREAD_ONCE_INIT;
static pthread_once_t redis_secret_once = PTHREAD_ONCE_INIT;
static g_getenv_function next_g_getenv;
static char *jwt_private_key;
static char *database_password;
static char *redis_password;

static void resolve_next_g_getenv(void)
{
    void *symbol = dlsym(RTLD_NEXT, "g_getenv");
    memcpy(&next_g_getenv, &symbol, sizeof(next_g_getenv));
}

static bool is_valid_utf8_secret(const unsigned char *value, size_t length)
{
    size_t index = 0;

    while (index < length) {
        uint32_t codepoint;
        size_t continuation_count;
        unsigned char first = value[index++];

        if (first < 0x80U) {
            codepoint = first;
            continuation_count = 0;
        } else if (first >= 0xC2U && first <= 0xDFU) {
            codepoint = first & 0x1FU;
            continuation_count = 1;
        } else if (first >= 0xE0U && first <= 0xEFU) {
            codepoint = first & 0x0FU;
            continuation_count = 2;
        } else if (first >= 0xF0U && first <= 0xF4U) {
            codepoint = first & 0x07U;
            continuation_count = 3;
        } else {
            return false;
        }

        if (continuation_count > length - index) {
            return false;
        }
        for (size_t offset = 0; offset < continuation_count; ++offset) {
            unsigned char continuation = value[index++];
            if ((continuation & 0xC0U) != 0x80U) {
                return false;
            }
            codepoint = (codepoint << 6U) | (continuation & 0x3FU);
        }

        if ((continuation_count == 1 && codepoint < 0x80U)
            || (continuation_count == 2 && codepoint < 0x800U)
            || (continuation_count == 3 && codepoint < 0x10000U)
            || codepoint > 0x10FFFFU
            || (codepoint >= 0xD800U && codepoint <= 0xDFFFU)
            || codepoint < 0x20U
            || (codepoint >= 0x7FU && codepoint <= 0x9FU)
            || codepoint == 0x2028U
            || codepoint == 0x2029U) {
            return false;
        }
    }

    return true;
}

static void wipe_buffer(unsigned char *buffer, size_t length)
{
    volatile unsigned char *cursor = buffer;

    while (length-- > 0U) {
        *cursor++ = 0U;
    }
}

static char *load_secret_value(
    const char *path_variable,
    const char *required_path,
    size_t minimum_bytes
)
{
    const char *secret_path = getenv(path_variable);
    unsigned char buffer[JWT_SECRET_MAX_BYTES + 1U];
    struct stat before;
    struct stat after;
    size_t offset = 0;
    int descriptor = -1;
    char *secret_value = NULL;

    if (secret_path == NULL || strcmp(secret_path, required_path) != 0) {
        return NULL;
    }

    descriptor = open(
        required_path,
        O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
    );
    if (descriptor < 0) {
        return NULL;
    }

    if (fstat(descriptor, &before) != 0
        || !S_ISREG(before.st_mode)
        || before.st_nlink != 1
        || before.st_size < (off_t)minimum_bytes
        || before.st_size > (off_t)JWT_SECRET_MAX_BYTES) {
        goto cleanup;
    }

    while (offset < sizeof(buffer)) {
        ssize_t count = read(descriptor, buffer + offset, sizeof(buffer) - offset);
        if (count > 0) {
            offset += (size_t)count;
            continue;
        }
        if (count < 0 && errno == EINTR) {
            continue;
        }
        if (count < 0) {
            goto cleanup;
        }
        break;
    }

    if (fstat(descriptor, &after) != 0
        || offset != (size_t)before.st_size
        || after.st_dev != before.st_dev
        || after.st_ino != before.st_ino
        || after.st_mode != before.st_mode
        || after.st_nlink != before.st_nlink
        || after.st_size != before.st_size
        || after.st_mtim.tv_sec != before.st_mtim.tv_sec
        || after.st_mtim.tv_nsec != before.st_mtim.tv_nsec
        || after.st_ctim.tv_sec != before.st_ctim.tv_sec
        || after.st_ctim.tv_nsec != before.st_ctim.tv_nsec
        || !is_valid_utf8_secret(buffer, offset)) {
        goto cleanup;
    }

    secret_value = malloc(offset + 1U);
    if (secret_value == NULL) {
        goto cleanup;
    }
    memcpy(secret_value, buffer, offset);
    secret_value[offset] = '\0';

cleanup:
    if (descriptor >= 0 && close(descriptor) != 0) {
        free(secret_value);
        secret_value = NULL;
    }
    wipe_buffer(buffer, sizeof(buffer));
    return secret_value;
}

static void load_jwt_private_key(void)
{
    jwt_private_key = load_secret_value(
        "JWT_PRIVATE_KEY_FILE",
        JWT_SECRET_PATH,
        JWT_SECRET_MIN_BYTES
    );
}

static void load_database_password(void)
{
    database_password = load_secret_value(
        "SEAFILE_MYSQL_DB_PASSWORD_FILE",
        DATABASE_SECRET_PATH,
        PASSWORD_SECRET_MIN_BYTES
    );
}

static void load_redis_password(void)
{
    redis_password = load_secret_value(
        "REDIS_PASSWORD_FILE",
        REDIS_SECRET_PATH,
        PASSWORD_SECRET_MIN_BYTES
    );
}

const char *g_getenv(const char *variable)
{
    if (variable == NULL) {
        return NULL;
    }
    if (strcmp(variable, "JWT_PRIVATE_KEY") == 0) {
        pthread_once(&jwt_secret_once, load_jwt_private_key);
        return jwt_private_key;
    }
    if (strcmp(variable, "SEAFILE_MYSQL_DB_PASSWORD") == 0) {
        pthread_once(&database_secret_once, load_database_password);
        return database_password;
    }
    if (strcmp(variable, "REDIS_PASSWORD") == 0) {
        pthread_once(&redis_secret_once, load_redis_password);
        return redis_password;
    }

    pthread_once(&resolver_once, resolve_next_g_getenv);
    if (next_g_getenv == NULL) {
        return NULL;
    }
    return next_g_getenv(variable);
}
