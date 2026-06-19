#pragma once

#include <string>

namespace vrm {

struct project_info {
    std::string project_name;
    std::string project_version;
    std::string project_vcsid;
    std::string project_repository;
    std::string project_source_dir;

    static const project_info& get();
};

}
