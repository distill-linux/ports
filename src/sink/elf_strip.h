#ifndef DISTILL_SINK_ELF_STRIP_H
#define DISTILL_SINK_ELF_STRIP_H

/*
 * Scans root_dir recursively. For any ELF binary, invokes `strip -s` via posix_spawnp.
 * Returns number of stripped binaries or negative on error.
 */
int sink_elf_strip_tree(const char *root_dir);

#endif /* DISTILL_SINK_ELF_STRIP_H */
