#define _GNU_SOURCE
#include "builder.h"
#include "deps.h"
#include "git_util.h"
#include "elf_strip.h"
#include "../common/tar.h"
#include "../common/spawn_util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>
#include <dirent.h>
#include <limits.h>
#include <time.h>

static int mkdir_p(const char *path, mode_t mode) {
    char tmp[PATH_MAX * 4];
    strncpy(tmp, path, sizeof(tmp) - 1);
    tmp[sizeof(tmp) - 1] = '\0';

    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(tmp, mode) != 0 && errno != EEXIST) return -1;
            *p = '/';
        }
    }
    if (mkdir(tmp, mode) != 0 && errno != EEXIST) return -1;
    return 0;
}

int sink_clean_scratch(void) {
    const char *scratch = "/tmp/sink";
    DIR *d = opendir(scratch);
    if (!d) {
        printf("sink: scratch directory '%s' is clean.\n", scratch);
        return 0;
    }

    printf("sink: cleaning scratch directory '%s'...\n", scratch);
    char cmd[PATH_MAX * 4];
    snprintf(cmd, sizeof(cmd), "rm -rf %s/*", scratch);
    system(cmd);
    closedir(d);
    printf("sink: scratch directory cleaned.\n");
    return 0;
}

int sink_build_recipe(distill_port *recipe, const sink_build_options *opts,
                      char out_archive[1024]) {
    if (!recipe || !opts) return -1;

    printf("==> Building port '%s-%s'...\n", recipe->name, recipe->version);

    /* Step 1: Validate dependencies */
    if (recipe->build_deps[0] != '\0') {
        printf("==> Validating build dependencies: %s\n", recipe->build_deps);
        if (sink_check_and_install_deps(recipe->build_deps, opts->drop_bin,
                                        opts->target_root, opts->auto_confirm) != 0) {
            fprintf(stderr, "sink: build dependencies check failed\n");
            return -1;
        }
    }

    /* Step 2: Prepare workspace */
    char base_workdir[PATH_MAX * 2];
    if (opts->workdir && opts->workdir[0] != '\0') {
        snprintf(base_workdir, sizeof(base_workdir), "%s", opts->workdir);
        mkdir_p(base_workdir, 0755);
    } else {
        mkdir_p("/tmp/sink", 0755);
        char tmpl[PATH_MAX * 2];
        snprintf(tmpl, sizeof(tmpl), "/tmp/sink/build-%s-XXXXXX", recipe->name);
        char *mkd = mkdtemp(tmpl);
        if (!mkd) {
            fprintf(stderr, "sink: failed to create temporary build dir: %s\n", strerror(errno));
            return -1;
        }
        snprintf(base_workdir, sizeof(base_workdir), "%s", mkd);
    }

    char src_dir[PATH_MAX * 4];
    char fakeroot_dir[PATH_MAX * 4];
    snprintf(src_dir, sizeof(src_dir), "%s/src", base_workdir);
    snprintf(fakeroot_dir, sizeof(fakeroot_dir), "%s/pkg", base_workdir);
    mkdir_p(src_dir, 0755);
    mkdir_p(fakeroot_dir, 0755);

    /* Step 3: Fetch repository via libgit2 if specified */
    if (recipe->url[0] != '\0') {
        if (sink_git_checkout_repo(recipe->url, recipe->commit, src_dir) != 0) {
            fprintf(stderr, "sink: failed to fetch source repository\n");
            return -1;
        }
    }

    /* Step 4: Execute build script inside $PKG_FAKEROOT via posix_spawnp */
    if (recipe->build_script && recipe->build_script_len > 0) {
        printf("==> Running build script...\n");

        setenv("PKG_FAKEROOT", fakeroot_dir, 1);
        setenv("DESTDIR", fakeroot_dir, 1);
        setenv("PORT_NAME", recipe->name, 1);
        setenv("PORT_VERSION", recipe->version, 1);
        setenv("PREFIX", "/usr", 1);

        char *argv[] = {"/bin/sh", "-e", "-c", recipe->build_script, NULL};
        pid_t pid = 0;
        int err = distill_spawn(argv, src_dir, NULL, -1, -1, -1, &pid);
        if (err != 0) {
            fprintf(stderr, "sink: failed to spawn build script: %s\n", strerror(err));
            return -1;
        }

        int exit_status = 0;
        int wait_res = distill_spawn_wait(pid, &exit_status);
        if (wait_res != 0 || exit_status != 0) {
            fprintf(stderr, "sink: build script failed with exit status %d\n", exit_status);
            return -1;
        }
    }

    /* Step 5: Post-build processing: strip ELF binaries */
    printf("==> Post-build processing: stripping ELF binaries...\n");
    int stripped_count = sink_elf_strip_tree(fakeroot_dir);
    printf("==> Stripped %d ELF files.\n", stripped_count);

    /* Step 6: Compute file hashes and generate .PORT manifest */
    printf("==> Scanning fakeroot and generating .PORT manifest...\n");
    port_file_list_free(&recipe->files);
    port_file_list_init(&recipe->files);
    distill_port_scan_fakeroot(fakeroot_dir, &recipe->files, &recipe->installed_size);

    recipe->timestamp = (uint64_t)time(NULL);

    char port_manifest_file[PATH_MAX * 4];
    snprintf(port_manifest_file, sizeof(port_manifest_file), "%s/.PORT", base_workdir);
    if (distill_port_save(port_manifest_file, recipe, 0) != 0) {
        fprintf(stderr, "sink: failed to save manifest '%s'\n", port_manifest_file);
        return -1;
    }

    /* Step 7: Package into <outdir>/<name>-<version>.drop with .PORT as first entry */
    const char *out_dir = (opts->outdir && opts->outdir[0] != '\0') ? opts->outdir : ".";
    mkdir_p(out_dir, 0755);

    char archive_path[PATH_MAX * 4];
    snprintf(archive_path, sizeof(archive_path), "%s/%s-%s.drop", out_dir, recipe->name, recipe->version);

    printf("==> Packaging container '%s' (.PORT as first header)...\n", archive_path);
    if (distill_tar_gz_create(archive_path, fakeroot_dir, port_manifest_file) != 0) {
        fprintf(stderr, "sink: failed to create .drop package archive\n");
        return -1;
    }

    if (out_archive) {
        strncpy(out_archive, archive_path, 1023);
        out_archive[1023] = '\0';
    }

    printf("==> Successfully created '%s' (%zu entries, %llu bytes)!\n",
           archive_path, recipe->files.count, (unsigned long long)recipe->installed_size);

    /* Step 8: Handoff to drop in if requested */
    if (opts->auto_install) {
        printf("==> Installing built artifact via drop...\n");
        const char *drop_cmd = opts->drop_bin ? opts->drop_bin : "drop";
        char *argv[10];
        int ai = 0;
        argv[ai++] = (char *)drop_cmd;
        if (opts->target_root && strcmp(opts->target_root, "/") != 0) {
            argv[ai++] = "-r";
            argv[ai++] = (char *)opts->target_root;
        }
        argv[ai++] = "in";
        argv[ai++] = archive_path;
        argv[ai] = NULL;

        int r = distill_spawn_sync(argv, NULL, NULL);
        if (r != 0) {
            fprintf(stderr, "sink: installation via drop failed with code %d\n", r);
            return -1;
        }
    }

    return 0;
}
