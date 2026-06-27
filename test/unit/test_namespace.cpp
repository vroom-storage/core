// Copyright 2026 UltiHash Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#define BOOST_TEST_MODULE "path tests"

#include <boost/test/unit_test.hpp>

#include <common/etcd/namespace.h>

namespace vrm::cluster::ns {

BOOST_AUTO_TEST_CASE(a_root_supports_group_namespace) {
    BOOST_TEST(std::string(root.storage_groups) == "/vrm/storage_groups");
    BOOST_TEST(std::string(root.storage_groups.group_configs) ==
               "/vrm/storage_groups/group_configs");
    BOOST_TEST(std::string(root.storage_groups.group_configs[2]) ==
               "/vrm/storage_groups/group_configs/2");
    BOOST_TEST(std::string(root.storage_groups[2].storage_states[3]) ==
               "/vrm/storage_groups/2/storage_states/3");
    BOOST_TEST(std::string(root.storage_groups[2].group_initialized) ==
               "/vrm/storage_groups/2/group_initialized");
    BOOST_TEST(std::string(root.storage_groups[2].storage_hostports[3]) ==
               "/vrm/storage_groups/2/storage_hostports/3");
    BOOST_TEST(std::string(root.storage_groups[2].group_state) ==
               "/vrm/storage_groups/2/group_state");
}

} // namespace vrm::cluster::ns
