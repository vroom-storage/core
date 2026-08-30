#pragma once

#include "address.h"

namespace vrm::cluster {

struct dedupe_response {
    std::size_t effective_size{};
    address addr;

    void append(const dedupe_response& other) {
        effective_size += other.effective_size;
        addr.append(other.addr);
    }
};

}
