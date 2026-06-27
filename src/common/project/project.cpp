#include "project.h"
#include "config.h"

namespace vrm {

const project_info& project_info::get() {
    static project_info info {
        .project_name = PROJECT_NAME,
        .project_version = PROJECT_VERSION,
        .project_vcsid = PROJECT_VCSID,
        .project_repository = PROJECT_REPOSITORY,
        .project_source_dir = PROJECT_SOURCE_DIR,
    };

    return info;
}

}
