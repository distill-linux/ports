#ifndef DISTILL_SINK_BUILDER_H
#define DISTILL_SINK_BUILDER_H

#include "../common/port.h"

typedef struct {
    const char *workdir;
    const char *outdir;
    const char *target_root;
    const char *drop_bin;
    int auto_confirm;
    int auto_install;
} sink_build_options;

int sink_build_recipe(distill_port *recipe, const sink_build_options *opts,
                      char out_archive[1024]);

int sink_clean_scratch(void);

#endif /* DISTILL_SINK_BUILDER_H */
