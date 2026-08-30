/*
 * Copyright 2026 UltiHash Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#pragma once

#include "config.h"

#include <common/etcd/service.h>
#include <common/etcd/service_discovery/service_maintainer.h>
#include <common/telemetry/log.h>
#include <common/utils/common.h>
#include <common/utils/strings.h>
#include <storage/interfaces/remote_storage.h>

#include <boost/asio/spawn.hpp>
#include <boost/asio/steady_timer.hpp>

namespace vrm::cluster::coordinator {

class service {
public:
    service(boost::asio::io_context& ioc, const service_config& service,
            const coordinator_config& cc)
        : m_etcd{service.etcd_config}
    {
        publish_configs(m_etcd, cc.storage_groups);
    }

    static void publish_configs(etcd_manager& etcd,
                                const storage::group_configs& group_configs) {
        LOG_INFO() << "publishing " << group_configs.configs.size() << " storage groups";
        for (const auto& cfg : group_configs.configs) {
            auto stored_config = etcd.get(ns::root.storage_groups.group_configs[cfg.id]);
            if (!stored_config.empty() and stored_config != cfg.to_string()) {
                throw std::runtime_error("supplied storage group configuration "
                                         "with id " +
                                         std::to_string(cfg.id) +
                                         " does not match with existing "
                                         "storage group configuration");
            }
            if (cfg.type != storage::group_config::type_t::ERASURE_CODING) {
                storage::group_config modified_config = cfg;
                modified_config.stripe_size_kib = DEFAULT_PAGE_SIZE / KIBI_BYTE;
                etcd.put(
                    ns::root.storage_groups.group_configs[modified_config.id],
                    modified_config.to_string());
            } else {
                etcd.put(ns::root.storage_groups.group_configs[cfg.id],
                         cfg.to_string());
            }
        }
    }

private:
    etcd_manager m_etcd;
};
} // namespace vrm::cluster::coordinator
