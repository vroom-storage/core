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

#include "trace_asio.h"
#include "impl/bridge.h"

#include <array>
#include <atomic>

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

#ifdef __clang__
#pragma GCC diagnostic ignored "-Wdeprecated-builtins"
#endif

#include <opentelemetry/baggage/baggage.h>
#include <opentelemetry/common/attribute_value.h>
#include <opentelemetry/context/context.h>
#include <opentelemetry/trace/context.h>
#include <opentelemetry/trace/provider.h>

#pragma GCC diagnostic pop

namespace trace_api = opentelemetry::trace;

namespace {
std::atomic_bool g_trace_enabled{false};
std::string g_tracer_name = "default-tracer";
std::string g_tracer_version = "0.1.0";

opentelemetry::nostd::string_view otel_string_view(std::string_view view) {
    return {view.data(), view.size()};
}

opentelemetry::common::AttributeValue
otel_attribute_value(const boost::asio::trace_attribute_value& value) {
    return std::visit(
        [](const auto& v) -> opentelemetry::common::AttributeValue {
            using T = std::decay_t<decltype(v)>;
            if constexpr (std::is_same_v<T, std::string>) {
                return opentelemetry::nostd::string_view(v.data(), v.size());
            } else {
                return v;
            }
        },
        value);
}
} // namespace

namespace boost::asio {

struct trace_context::impl {
    opentelemetry::context::Context context;
};

trace_context::trace_context()
    : m_impl(std::make_shared<impl>()) {}

trace_context::trace_context(std::shared_ptr<impl> impl_ptr)
    : m_impl(std::move(impl_ptr)) {
    if (!m_impl) {
        m_impl = std::make_shared<impl>();
    }
}

trace_context::trace_context(const trace_context& other)
    : m_impl(std::make_shared<impl>(other.m_impl ? *other.m_impl : impl{})) {}

trace_context::trace_context(trace_context&&) noexcept = default;

trace_context& trace_context::operator=(const trace_context& other) {
    if (this != &other) {
        m_impl = std::make_shared<impl>(other.m_impl ? *other.m_impl : impl{});
    }
    return *this;
}

trace_context& trace_context::operator=(trace_context&&) noexcept = default;

trace_context::~trace_context() = default;

void trace_context::set_value(const std::string& key, trace_context_value val) {
    if (!m_impl) {
        m_impl = std::make_shared<impl>();
    }

    std::visit(
        [&](const auto& v) {
            using T = std::decay_t<decltype(v)>;
            if constexpr (!std::is_same_v<T, std::monostate>) {
                m_impl->context = m_impl->context.SetValue(
                    otel_string_view(key),
                    opentelemetry::context::ContextValue{v});
            }
        },
        val);
}

trace_context_value trace_context::get_value(const std::string& key) const {
    if (!m_impl) {
        return std::monostate{};
    }

    auto val = m_impl->context.GetValue(otel_string_view(key));
    if (opentelemetry::nostd::holds_alternative<bool>(val)) {
        return opentelemetry::nostd::get<bool>(val);
    }
    if (opentelemetry::nostd::holds_alternative<int64_t>(val)) {
        return opentelemetry::nostd::get<int64_t>(val);
    }
    if (opentelemetry::nostd::holds_alternative<uint64_t>(val)) {
        return opentelemetry::nostd::get<uint64_t>(val);
    }
    if (opentelemetry::nostd::holds_alternative<double>(val)) {
        return opentelemetry::nostd::get<double>(val);
    }
    return std::monostate{};
}

void trace_context::set_baggage(const std::string& key,
                                const std::string& value) {
    if (!m_impl) {
        m_impl = std::make_shared<impl>();
    }

    auto baggage_val = m_impl->context.GetValue("baggage");
    opentelemetry::nostd::shared_ptr<opentelemetry::baggage::Baggage> baggage;

    if (opentelemetry::nostd::holds_alternative<
            opentelemetry::nostd::shared_ptr<opentelemetry::baggage::Baggage>>(
            baggage_val)) {
        baggage = opentelemetry::nostd::get<
            opentelemetry::nostd::shared_ptr<opentelemetry::baggage::Baggage>>(
            baggage_val);
    } else {
        baggage = opentelemetry::baggage::Baggage::GetDefault();
    }

    auto new_baggage = baggage->Set(key, value);
    m_impl->context = m_impl->context.SetValue("baggage", new_baggage);
}

std::string trace_context::get_baggage(const std::string& key) const {
    if (!m_impl) {
        return {};
    }

    auto baggage_val = m_impl->context.GetValue("baggage");
    if (opentelemetry::nostd::holds_alternative<
            opentelemetry::nostd::shared_ptr<opentelemetry::baggage::Baggage>>(
            baggage_val)) {
        auto baggage = opentelemetry::nostd::get<
            opentelemetry::nostd::shared_ptr<opentelemetry::baggage::Baggage>>(
            baggage_val);
        std::string value;
        if (baggage && baggage->GetValue(key, value)) {
            return value;
        }
    }
    return {};
}

namespace context {
void set_baggage(trace_context& ctx, const std::string& key,
                 const std::string& value) {
    ctx.set_baggage(key, value);
}

std::string get_baggage(const trace_context& ctx, const std::string& key) {
    return ctx.get_baggage(key);
}
} // namespace context

namespace detail {
const opentelemetry::context::Context&
trace_context_bridge::native_context(const trace_context& context) {
    static const opentelemetry::context::Context empty_context;
    if (!context.m_impl) {
        return empty_context;
    }
    return context.m_impl->context;
}

opentelemetry::context::Context&
trace_context_bridge::native_context(trace_context& context) {
    if (!context.m_impl) {
        context.m_impl =
            std::shared_ptr<trace_context::impl>(new trace_context::impl{});
    }
    return context.m_impl->context;
}

trace_context trace_context_bridge::make_trace_context(
    opentelemetry::context::Context context) {
    auto impl = std::shared_ptr<trace_context::impl>(new trace_context::impl{});
    impl->context = std::move(context);
    return trace_context(std::move(impl));
}
} // namespace detail

struct trace_span::impl {
    trace_span* parent{nullptr};
    source_location location;
    opentelemetry::nostd::shared_ptr<trace_api::Span> data{nullptr};
    trace_context context;
    bool has_context{false};
};

trace_span::trace_span()
    : m_impl(std::make_unique<impl>()) {}

trace_span::~trace_span() {
    if (m_impl && is_started()) {
        m_impl->data->End();
    }
}

trace_span::trace_span(trace_span&&) noexcept = default;

trace_span& trace_span::operator=(trace_span&& other) noexcept {
    if (this != &other) {
        if (m_impl && is_started()) {
            m_impl->data->End();
        }
        m_impl = std::move(other.m_impl);
    }
    return *this;
}

void trace_span::set_location(const source_location& location) noexcept {
    if (m_impl) {
        m_impl->location = location;
    }
}

void trace_span::set_name(std::string_view name) noexcept {
    if (g_trace_enabled.load(std::memory_order_relaxed) && is_started()) {
        m_impl->data->UpdateName(otel_string_view(name));
    }
}

void trace_span::set_attribute_impl(std::string_view key,
                                    trace_attribute_value value) noexcept {
    if (g_trace_enabled.load(std::memory_order_relaxed) && is_started()) {
        auto attribute = otel_attribute_value(value);
        m_impl->data->SetAttribute(otel_string_view(key), attribute);
    }
}

void trace_span::add_event(std::string_view name,
                           trace_attributes attributes) noexcept {
    if (!g_trace_enabled.load(std::memory_order_relaxed) || !is_started()) {
        return;
    }

    std::vector<std::pair<opentelemetry::nostd::string_view,
                          opentelemetry::common::AttributeValue>>
        otel_attributes;
    otel_attributes.reserve(attributes.size());
    for (const auto& [key, value] : attributes) {
        otel_attributes.emplace_back(otel_string_view(key),
                                     otel_attribute_value(value));
    }

    m_impl->data->AddEvent(otel_string_view(name), otel_attributes);
}

void trace_span::add_event(std::string_view name) noexcept {
    if (g_trace_enabled.load(std::memory_order_relaxed) && is_started()) {
        m_impl->data->AddEvent(otel_string_view(name));
    }
}

trace_context trace_span::context() const noexcept {
    if (m_impl && m_impl->has_context) {
        return m_impl->context;
    }
    return trace_context{};
}

bool trace_span::is_enabled() noexcept {
    return g_trace_enabled.load(std::memory_order_relaxed);
}

bool trace_span::is_started() const noexcept {
    return m_impl && m_impl->data != nullptr;
}

bool trace_span::has_context() const noexcept {
    return m_impl && m_impl->has_context;
}

void trace_span::iterate_call_stack(
    std::function<void(source_location)> process) {
    auto parent = m_impl ? m_impl->parent : nullptr;
    while (parent) {
        process(parent->m_impl->location);
        parent = parent->m_impl->parent;
    }
}

std::string trace_span::trace_id(const trace_context& context) noexcept {
    if (!context.m_impl) {
        return {};
    }

    auto span = opentelemetry::trace::GetSpan(context.m_impl->context);
    auto span_context = span->GetContext();
    if (!span_context.IsValid()) {
        return {};
    }

    std::array<char, 2 * trace_api::TraceId::kSize> print_buffer{};
    span_context.trace_id().ToLowerBase16(print_buffer);
    return std::string(print_buffer.data(), print_buffer.size());
}

bool trace_span::check_context(const trace_context& context) {
    if (!context.m_impl) {
        return false;
    }

    auto span = opentelemetry::trace::GetSpan(context.m_impl->context);
    auto span_context = span->GetContext();
    return span_context.IsValid();
}

void trace_span::set_parent(trace_span* parent) noexcept {
    if (m_impl) {
        m_impl->parent = parent;
    }
}

trace_context trace_span::root_context() noexcept {
    trace_context context;
    context.m_impl->context =
        context.m_impl->context.SetValue(trace_api::kIsRootSpanKey, true);
    return context;
}

void trace_span::start_span(trace_context context) noexcept {
    if (!m_impl) {
        return;
    }

    if (g_trace_enabled.load(std::memory_order_relaxed)) {
        auto tracer = trace_api::Provider::GetTracerProvider()->GetTracer(
            g_tracer_name, g_tracer_version);
        m_impl->data = tracer->StartSpan(m_impl->location.function_name(),
                                         {.parent = context.m_impl->context});
        m_impl->data->SetAttribute("function name",
                                   m_impl->location.function_name());
        m_impl->data->SetAttribute("file", m_impl->location.file_name());
        m_impl->data->SetAttribute("line",
                                   std::to_string(m_impl->location.line()));
        m_impl->context.m_impl->context = opentelemetry::trace::SetSpan(
            context.m_impl->context, m_impl->data);
    } else {
        m_impl->context = std::move(context);
    }
    m_impl->has_context = true;
}

void traced_asio_initialize(const std::string& tracer_name,
                            const std::string& tracer_version) {
    g_tracer_name = tracer_name;
    g_tracer_version = tracer_version;
    g_trace_enabled.store(true, std::memory_order_relaxed);
}

} // namespace boost::asio