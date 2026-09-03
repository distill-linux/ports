#define _GNU_SOURCE
#include "deps.h"
#include "../common/spawn_util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <limits.h>

static int is_executable_in_path(const char *cmd) {
    const char *path_env = getenv("PATH");
    if (!path_env) path_env = "/usr/bin:/bin";

    char *path_copy = strdup(path_env);
    if (!path_copy) return 0;

    int found = 0;
    char *saveptr = NULL;
    char *dir = strtok_r(path_copy, ":", &saveptr);
    while (dir) {
        char full[PATH_MAX * 2];
        snprintf(full, sizeof(full), "%s/%s", dir, cmd);
        if (access(full, X_OK) == 0) {
            found = 1;
            break;
        }
        dir = strtok_r(NULL, ":", &saveptr);
    }

    free(path_copy);
    return found;
}

static int is_dep_satisfied(const char *dep, const char *target_root) {
    if (!dep || dep[0] == '\0') return 1;

    if (is_executable_in_path(dep)) return 1;

    /* Build system aliases */
    if (strcmp(dep, "samurai") == 0 && is_executable_in_path("samu")) return 1;
    if (strcmp(dep, "samu") == 0 && is_executable_in_path("samurai")) return 1;
    if (strcmp(dep, "make") == 0 && is_executable_in_path("bmake")) return 1;

    /* Check in drop db */
    char port_path[PATH_MAX * 2];
    if (!target_root || target_root[0] == '\0' || strcmp(target_root, "/") == 0) {
        snprintf(port_path, sizeof(port_path), "/var/db/drop/ports/%s/.PORT", dep);
    } else {
        snprintf(port_path, sizeof(port_path), "%s/var/db/drop/ports/%s/.PORT", target_root, dep);
    }
    if (access(port_path, F_OK) == 0) return 1;

    return 0;
}

int sink_check_and_install_deps(const char *deps, const char *drop_bin_path,
                                const char *target_root, int auto_confirm) {
    if (!deps || deps[0] == '\0') return 0;

    char *copy = strdup(deps);
    if (!copy) return -1;

    char *saveptr = NULL;
    char *token = strtok_r(copy, ",", &saveptr);

    while (token) {
        while (*token == ' ' || *token == '\t') token++;
        size_t len = strlen(token);
        while (len > 0 && (token[len - 1] == ' ' || token[len - 1] == '\t')) {
            token[--len] = '\0';
        }

        if (token[0] != '\0') {
            if (!is_dep_satisfied(token, target_root)) {
                int approve = 0;
                if (auto_confirm) {
                    approve = 1;
                } else {
                    printf("Missing build dependency: '%s'. Install via official repo? [Y/n] ", token);
                    fflush(stdout);
                    char response[64];
                    if (fgets(response, sizeof(response), stdin)) {
                        char c = response[0];
                        if (c == 'y' || c == 'Y' || c == '\n' || c == '\0') {
                            approve = 1;
                        }
                    }
                }

                if (!approve) {
                    fprintf(stderr, "sink: aborted: missing build dependency '%s'\n", token);
                    free(copy);
                    return -1;
                }

                const char *drop_cmd = drop_bin_path ? drop_bin_path : "drop";
                char *argv[10];
                int ai = 0;
                argv[ai++] = (char *)drop_cmd;
                if (target_root && strcmp(target_root, "/") != 0) {
                    argv[ai++] = "-r";
                    argv[ai++] = (char *)target_root;
                }
                argv[ai++] = "in";
                argv[ai++] = token;
                argv[ai] = NULL;

                printf("sink: installing dependency '%s' via drop...\n", token);
                int r = distill_spawn_sync(argv, NULL, NULL);
                if (r != 0) {
                    fprintf(stderr, "sink: failed to install dependency '%s' (exit code %d)\n", token, r);
                    free(copy);
                    return -1;
                }
            }
        }
        token = strtok_r(NULL, ",", &saveptr);
    }

    free(copy);
    return 0;
}
