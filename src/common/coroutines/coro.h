#pragma once

#include <common/telemetry/trace/trace_asio.h>

namespace uh::cluster {

template <typename T> using coro = boost::asio::traced_awaitable<T>;

inline thread_local boost::asio::trace_context THREAD_LOCAL_CONTEXT;

} // namespace uh::cluster