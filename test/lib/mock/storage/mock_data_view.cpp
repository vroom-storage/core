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

#include "mock_data_view.h"

#include <common/utils/pointer_traits.h>
#include <storage/group/impl/address_utils.h>

namespace uh::cluster {
mock_data_view::mock_data_view(mock_data_store& storage)
    : m_storage{storage} {}

address compute_address(const std::vector<std::size_t>& offsets,
                        const std::size_t data_size,
                        const allocation_t& allocation) {
    address rv;
    std::size_t base_offset = allocation.offset;
    for (auto it = offsets.begin(); it != offsets.end(); it++) {
        auto next = std::next(it);
        std::size_t frag_size =
            next == offsets.end() ? data_size - *it : *next - *it;
        rv.emplace_back(base_offset + *it, frag_size);
    }
    return rv;
}

coro<address> mock_data_view::write(std::span<const char> data,
                                    const std::vector<std::size_t>& offsets) {
    auto alloc = m_storage.allocate(data.size());
    auto addr = compute_address(offsets, data.size(), alloc);
    m_storage.write(alloc, std::vector<std::span<const char>>{data});
    co_return addr;
}

coro<shared_buffer<>> mock_data_view::read(const uint128_t& pointer,
                                           size_t size) {
    shared_buffer<char> buffer(size);
    m_storage.read(pointer, buffer.span());
    co_return buffer;
}

coro<std::size_t> mock_data_view::read_address(const address& addr,
                                               std::span<char> buffer) {
    auto size = 0u;
    for (size_t i = 0; i < addr.size(); ++i) {
        auto frag = addr.get(i);
        m_storage.read(frag.pointer, buffer.first(frag.size));
        buffer = buffer.subspan(frag.size);
        size += frag.size;
    }

    co_return size;
}

coro<std::size_t> mock_data_view::get_used_space() {
    co_return m_storage.get_used_space();
}

coro<std::size_t> mock_data_view::unlink(const address& addr) {
    std::size_t rv = 0;
    for (unsigned i = 0; i < addr.size(); ++i) {
        const auto& f = addr.get(i);
        rv += m_storage.unlink(f.pointer, f.size);
    }

    co_return rv;
}

} // namespace uh::cluster
