#define _GNU_SOURCE
#include "builder.h"
#include "git_util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <limits.h>

static void print_usage(const char *prog) {
    fprintf(stderr,
        "Distill Linux Community Package Engine & Builder (sink)\n"
        "Usage: %s [options] <verb> [arguments]\n\n"
        "Core verbs:\n"
        "  make [-i] <recipe.port | name>   Build package from recipe (and optionally install)\n"
        "  clean                            Purge temporary build/scratch dirs in /tmp/sink\n"
        "  info <recipe.port | name>        Display recipe metadata\n"
        "  help                             Show this help screen\n\n"
        "Options:\n"
        "  -i, --install                    Automatically install artifact via 'drop in'\n"
        "  -y, --noconfirm                  Automatically confirm dependency installations\n"
        "  -r, --root <path>                Target root prefix for drop install (default: /)\n"
        "  --out <dir>                      Output directory for .drop archive (default: .)\n"
        "  --workdir <dir>                  Custom workspace directory\n"
        "  --drop <path>                    Path to drop executable\n",
        prog);
}

int main(int argc, char *argv[]) {
    sink_build_options opts;
    memset(&opts, 0, sizeof(opts));
    opts.outdir = ".";
    opts.target_root = getenv("DROP_ROOT");
    if (!opts.target_root) opts.target_root = "/";
    opts.drop_bin = "drop";

    int arg_idx = 1;
    while (arg_idx < argc && argv[arg_idx][0] == '-') {
        if (strcmp(argv[arg_idx], "-i") == 0 || strcmp(argv[arg_idx], "--install") == 0) {
            opts.auto_install = 1;
        } else if (strcmp(argv[arg_idx], "-y") == 0 || strcmp(argv[arg_idx], "--noconfirm") == 0) {
            opts.auto_confirm = 1;
        } else if (strcmp(argv[arg_idx], "-r") == 0 || strcmp(argv[arg_idx], "--root") == 0) {
            if (arg_idx + 1 >= argc) {
                fprintf(stderr, "sink: option '%s' requires an argument\n", argv[arg_idx]);
                return 1;
            }
            opts.target_root = argv[++arg_idx];
        } else if (strcmp(argv[arg_idx], "--out") == 0) {
            if (arg_idx + 1 >= argc) {
                fprintf(stderr, "sink: option '--out' requires an argument\n");
                return 1;
            }
            opts.outdir = argv[++arg_idx];
        } else if (strcmp(argv[arg_idx], "--workdir") == 0) {
            if (arg_idx + 1 >= argc) {
                fprintf(stderr, "sink: option '--workdir' requires an argument\n");
                return 1;
            }
            opts.workdir = argv[++arg_idx];
        } else if (strcmp(argv[arg_idx], "--drop") == 0) {
            if (arg_idx + 1 >= argc) {
                fprintf(stderr, "sink: option '--drop' requires an argument\n");
                return 1;
            }
            opts.drop_bin = argv[++arg_idx];
        } else if (strcmp(argv[arg_idx], "-h") == 0 || strcmp(argv[arg_idx], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        } else {
            fprintf(stderr, "sink: unrecognized option '%s'\n", argv[arg_idx]);
            print_usage(argv[0]);
            return 1;
        }
        arg_idx++;
    }

    if (arg_idx >= argc) {
        print_usage(argv[0]);
        return 1;
    }

    const char *verb = argv[arg_idx++];

    if (strcmp(verb, "clean") == 0) {
        return sink_clean_scratch();
    }

    if (strcmp(verb, "make") == 0) {
        /* Check if -i is provided after 'make' */
        while (arg_idx < argc && argv[arg_idx][0] == '-') {
            if (strcmp(argv[arg_idx], "-i") == 0 || strcmp(argv[arg_idx], "--install") == 0) {
                opts.auto_install = 1;
            } else if (strcmp(argv[arg_idx], "-y") == 0 || strcmp(argv[arg_idx], "--noconfirm") == 0) {
                opts.auto_confirm = 1;
            }
            arg_idx++;
        }

        if (arg_idx >= argc) {
            fprintf(stderr, "sink: make requires a .port recipe file or port name\n");
            return 1;
        }

        const char *recipe_arg = argv[arg_idx];
        char recipe_path[PATH_MAX * 2];
        if (access(recipe_arg, R_OK) == 0) {
            snprintf(recipe_path, sizeof(recipe_path), "%s", recipe_arg);
        } else {
            /* Check recipes/<recipe_arg>.port */
            snprintf(recipe_path, sizeof(recipe_path), "recipes/%s.port", recipe_arg);
            if (access(recipe_path, R_OK) != 0) {
                snprintf(recipe_path, sizeof(recipe_path), "%s", recipe_arg);
            }
        }

        distill_port recipe;
        if (distill_port_load(recipe_path, &recipe) != 0) {
            fprintf(stderr, "sink: cannot load recipe '%s'\n", recipe_path);
            return 1;
        }

        sink_git_init();
        char out_archive[1024] = {0};
        int res = sink_build_recipe(&recipe, &opts, out_archive);
        distill_port_free(&recipe);
        sink_git_shutdown();
        return res;
    } else if (strcmp(verb, "info") == 0) {
        if (arg_idx >= argc) {
            fprintf(stderr, "sink: info requires a .port recipe file\n");
            return 1;
        }

        const char *recipe_arg = argv[arg_idx];
        char recipe_path[PATH_MAX * 2];
        if (access(recipe_arg, R_OK) == 0) {
            snprintf(recipe_path, sizeof(recipe_path), "%s", recipe_arg);
        } else {
            snprintf(recipe_path, sizeof(recipe_path), "recipes/%s.port", recipe_arg);
            if (access(recipe_path, R_OK) != 0) {
                snprintf(recipe_path, sizeof(recipe_path), "%s", recipe_arg);
            }
        }

        distill_port recipe;
        if (distill_port_load(recipe_path, &recipe) != 0) {
            fprintf(stderr, "sink: cannot load recipe '%s'\n", recipe_path);
            return 1;
        }

        printf("Port Name:     %s\n", recipe.name);
        printf("Port Version:  %s (release %s)\n", recipe.version, recipe.release[0] ? recipe.release : "1");
        if (recipe.desc[0]) printf("Description:   %s\n", recipe.desc);
        if (recipe.url[0])  printf("Port URL:      %s\n", recipe.url);
        if (recipe.commit[0]) printf("Port Commit:   %s\n", recipe.commit);
        if (recipe.build_system[0]) printf("Build System:  %s\n", recipe.build_system);
        if (recipe.build_deps[0]) printf("Build Deps:    %s\n", recipe.build_deps);
        if (recipe.run_deps[0]) printf("Run Deps:      %s\n", recipe.run_deps);
        printf("Build Script:  %zu bytes\n", recipe.build_script_len);

        distill_port_free(&recipe);
        return 0;
    } else if (strcmp(verb, "help") == 0) {
        print_usage(argv[0]);
        return 0;
    } else {
        fprintf(stderr, "sink: unknown verb '%s'\n", verb);
        print_usage(argv[0]);
        return 1;
    }
}
