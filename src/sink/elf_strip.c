#define _GNU_SOURCE
#include "elf_strip.h"
#include "../common/spawn_util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dirent.h>
#include <limits.h>

static int is_elf_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    unsigned char magic[4];
    size_t n = fread(magic, 1, 4, f);
    fclose(f);
    if (n < 4) return 0;
    return (magic[0] == 0x7f && magic[1] == 'E' && magic[2] == 'L' && magic[3] == 'F');
}

static int scan_and_strip(const char *dir_path) {
    DIR *d = opendir(dir_path);
    if (!d) return 0;

    int count = 0;
    struct dirent *ent;
    while ((ent = readdir(d)) != NULL) {
        if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0) {
            continue;
        }

        char full[PATH_MAX * 4];
        snprintf(full, sizeof(full), "%s/%s", dir_path, ent->d_name);

        struct stat st;
        if (lstat(full, &st) != 0) continue;

        if (S_ISDIR(st.st_mode)) {
            count += scan_and_strip(full);
        } else if (S_ISREG(st.st_mode)) {
            if (is_elf_file(full)) {
                printf("sink: stripping ELF binary '%s'...\n", full);
                char *argv[] = {"strip", "-s", full, NULL};
                int r = distill_spawn_sync(argv, NULL, NULL);
                if (r == 0) {
                    count++;
                } else {
                    fprintf(stderr, "sink: warning: strip failed on '%s'\n", full);
                }
            }
        }
    }
    closedir(d);
    return count;
}

int sink_elf_strip_tree(const char *root_dir) {
    if (!root_dir) return -1;
    return scan_and_strip(root_dir);
}
