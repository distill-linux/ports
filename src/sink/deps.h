#ifndef DISTILL_SINK_DEPS_H
#define DISTILL_SINK_DEPS_H

/*
 * Checks comma-separated dependencies string.
 * If any dependency is missing:
 *   - Prompts: "Missing build dependency: '<name>'. Install via official repo? [Y/n] "
 *   - Spawns `drop in <dep>` via posix_spawnp.
 * Returns 0 on success, non-zero if unsatisfied or installation fails.
 */
int sink_check_and_install_deps(const char *deps, const char *drop_bin_path,
                                const char *target_root, int auto_confirm);

#endif /* DISTILL_SINK_DEPS_H */
