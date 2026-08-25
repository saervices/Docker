// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices

#include <stdio.h>
#include <string.h>

extern const char *g_getenv(const char *variable);

int main(int argc, char **argv)
{
    const char *secret_value;
    const char *delegated_value;
    int expect_value;
    size_t minimum_length;

    if (argc != 3 || (strcmp(argv[2], "present") != 0
                      && strcmp(argv[2], "absent") != 0)) {
        return 2;
    }
    if (strcmp(argv[1], "JWT_PRIVATE_KEY") == 0) {
        minimum_length = 32U;
    } else if (strcmp(argv[1], "SEAFILE_MYSQL_DB_PASSWORD") == 0
               || strcmp(argv[1], "REDIS_PASSWORD") == 0) {
        minimum_length = 12U;
    } else {
        return 2;
    }
    expect_value = strcmp(argv[2], "present") == 0;

    delegated_value = g_getenv("SEAFILE_SHIM_DELEGATION_TEST");
    if (delegated_value == NULL || strcmp(delegated_value, "delegated") != 0) {
        return 3;
    }

    secret_value = g_getenv(argv[1]);
    if ((expect_value && secret_value == NULL)
        || (!expect_value && secret_value != NULL)) {
        return 4;
    }
    if (secret_value != NULL && strlen(secret_value) < minimum_length) {
        return 5;
    }

    puts(expect_value ? "validated-present" : "validated-absent");
    return 0;
}
