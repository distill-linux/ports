#ifndef DISTILL_SINK_GIT_UTIL_H
#define DISTILL_SINK_GIT_UTIL_H

int sink_git_init(void);
void sink_git_shutdown(void);
int sink_git_checkout_repo(const char *repo_url, const char *commit, const char *dest_dir);

#endif /* DISTILL_SINK_GIT_UTIL_H */
