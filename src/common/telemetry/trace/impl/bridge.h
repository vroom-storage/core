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

#include <common/telemetry/trace/trace_context.h>

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

#ifdef __clang__
#pragma GCC diagnostic ignored "-Wdeprecated-builtins"
#endif

#include <opentelemetry/context/context.h>

#pragma GCC diagnostic pop

namespace boost::asio::detail {

class trace_context_bridge {
  public:
    static const opentelemetry::context::Context &
    native_context(const trace_context &context);

    static opentelemetry::context::Context &
    native_context(trace_context &context);

    static trace_context
    make_trace_context(opentelemetry::context::Context context);
};

} // namespace boost::asio::detail