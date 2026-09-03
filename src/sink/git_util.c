#define _GNU_SOURCE
#include "git_util.h"
#include <git2.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

int sink_git_init(void) {
    return git_libgit2_init();
}

void sink_git_shutdown(void) {
    git_libgit2_shutdown();
}

int sink_git_checkout_repo(const char *repo_url, const char *commit, const char *dest_dir) {
    if (!repo_url || repo_url[0] == '\0') {
        mkdir(dest_dir, 0755);
        return 0;
    }

    printf("sink: cloning repository '%s' into %s...\n", repo_url, dest_dir);

    git_repository *repo = NULL;
    git_clone_options clone_opts;
    memset(&clone_opts, 0, sizeof(clone_opts));
    git_clone_options_init(&clone_opts, GIT_CLONE_OPTIONS_VERSION);
    clone_opts.checkout_opts.checkout_strategy = GIT_CHECKOUT_SAFE;

    int error = git_clone(&repo, repo_url, dest_dir, &clone_opts);
    if (error < 0) {
        const git_error *e = git_error_last();
        fprintf(stderr, "sink: git clone error: %s\n", e && e->message ? e->message : "unknown");
        return -1;
    }

    if (commit && commit[0] != '\0') {
        printf("sink: checking out commit '%s'...\n", commit);
        git_object *obj = NULL;
        error = git_revparse_single(&obj, repo, commit);
        if (error < 0) {
            const git_error *e = git_error_last();
            fprintf(stderr, "sink: failed to resolve commit '%s': %s\n",
                    commit, e && e->message ? e->message : "unknown");
            git_repository_free(repo);
            return -1;
        }

        git_checkout_options checkout_opts;
        memset(&checkout_opts, 0, sizeof(checkout_opts));
        git_checkout_options_init(&checkout_opts, GIT_CHECKOUT_OPTIONS_VERSION);
        checkout_opts.checkout_strategy = GIT_CHECKOUT_FORCE;
        error = git_checkout_tree(repo, obj, &checkout_opts);
        if (error < 0) {
            const git_error *e = git_error_last();
            fprintf(stderr, "sink: failed to checkout tree: %s\n",
                    e && e->message ? e->message : "unknown");
            git_object_free(obj);
            git_repository_free(repo);
            return -1;
        }

        error = git_repository_set_head_detached(repo, git_object_id(obj));
        git_object_free(obj);
        if (error < 0) {
            const git_error *e = git_error_last();
            fprintf(stderr, "sink: failed to set detached HEAD: %s\n",
                    e && e->message ? e->message : "unknown");
            git_repository_free(repo);
            return -1;
        }
    }

    git_repository_free(repo);
    return 0;
}
