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

#include "mock_data_store.h"

#include <algorithm>
#include <common/telemetry/log.h>
#include <common/types/address.h>
#include <fstream>
#include <iostream>

namespace uh::cluster {

struct ds_file_info {
    std::size_t storage_id;
    std::size_t offset;
};

mock_data_store::mock_data_store(data_store_config conf,
                                 const std::filesystem::path& working_dir,
                                 uint32_t service_id, uint32_t data_store_id)
    : m_storage_id(service_id),
      m_data_store_id(data_store_id),
      m_root(working_dir / std::to_string(data_store_id)),
      m_conf{conf},
      m_data(m_conf.max_data_store_size, 0) {
    (void)m_storage_id;
    assert(m_data_store_id == 0);
    if (!std::filesystem::exists(m_root)) {
        std::filesystem::create_directories(m_root);
    }

    {
        std::ifstream ifs(m_root / m_datafile, std::ios::binary);
        if (ifs) {
            ifs.read(m_data.data(), m_data.size());

            std::streamsize bytes_read = ifs.gcount();
            LOG_WARN() << "read " << bytes_read << " bytes from data store";
            if (bytes_read < 0) {
                throw std::runtime_error("Stream read error occurred.");
            }
            m_current_offset = static_cast<std::size_t>(bytes_read);
        }
    }
}

void mock_data_store::write(const allocation_t allocation,
                            const std::vector<std::span<const char>>& buffers) {
    auto offset = allocation.offset;
    for (const auto& data : buffers) {
        std::copy(data.begin(), data.end(), m_data.begin() + offset);
        offset += data.size();
    }
}

std::size_t mock_data_store::read(const std::size_t pointer,
                                  std::span<char> buffer) {
    const auto current_offset = m_current_offset.load();

    if (pointer + buffer.size() > current_offset) {
        LOG_WARN() << "attempted to read data from the out-of-bounds offset="
                   << pointer << ", with current_offset=" << current_offset;
        throw std::out_of_range("pointer is out of range");
    }

    std::memcpy(buffer.data(), m_data.data() + pointer, buffer.size());
    return buffer.size();
}

std::size_t mock_data_store::unlink(storage_pointer pointer, std::size_t size) {
    std::lock_guard<std::mutex> lock(m_mutex);

    std::fill(m_data.begin() + pointer, m_data.begin() + pointer + size, 0);
    return size;
}

uint64_t mock_data_store::get_used_space() const noexcept {
    return m_current_offset.load();
}

size_t mock_data_store::get_available_space() const noexcept {
    return m_conf.max_data_store_size - m_current_offset.load();
}

std::size_t mock_data_store::get_write_offset() const noexcept {
    return m_current_offset.load();
}

void mock_data_store::clear() {
    m_data.clear();
}

size_t mock_data_store::id() const noexcept { return m_data_store_id; }

allocation_t mock_data_store::allocate(std::size_t size,
                                       std::size_t alignment) {

    std::unique_lock lock(m_mutex);

    if (m_conf.max_data_store_size - m_current_offset.load() < size) {
        throw std::runtime_error("datastore cannot store additional " +
                                 std::to_string(size) + " bytes");
    }

    if (m_current_offset % alignment != 0) {
        m_current_offset += alignment - (m_current_offset % alignment);
    }
    std::size_t allocation_offset = m_current_offset.load();
    m_current_offset += size;

    return {.offset = allocation_offset, .size = size};
}

mock_data_store::~mock_data_store() {
    {
        LOG_WARN() << "writing mock_data_store: " << m_current_offset.load();
        std::ofstream ofs(m_root / m_datafile, std::ios::binary);
        ofs.write(reinterpret_cast<const char*>(m_data.data()),
                  m_current_offset.load());
    }
}

} // end namespace uh::cluster
