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

#include "trace.h"
#include "trace_asio.h"
#include "impl/bridge.h"

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

#ifdef __clang__
#pragma GCC diagnostic ignored "-Wdeprecated-builtins"
#endif

#include <opentelemetry/context/propagation/global_propagator.h>
#include <opentelemetry/context/propagation/text_map_propagator.h>
#include <opentelemetry/exporters/ostream/span_exporter_factory.h>
#include <opentelemetry/exporters/otlp/otlp_grpc_exporter_factory.h>
#include <opentelemetry/exporters/otlp/otlp_grpc_exporter_options.h>
#include <opentelemetry/sdk/trace/batch_span_processor_factory.h>
#include <opentelemetry/sdk/trace/batch_span_processor_options.h>
#include <opentelemetry/sdk/trace/processor.h>
#include <opentelemetry/sdk/trace/simple_processor_factory.h>
#include <opentelemetry/sdk/trace/tracer_provider_factory.h>
#include <opentelemetry/trace/propagation/http_trace_context.h>
#include <opentelemetry/trace/provider.h>

#pragma GCC diagnostic pop

namespace trace_api = opentelemetry::trace;
namespace trace_sdk = opentelemetry::sdk::trace;
namespace otlp = opentelemetry::exporter::otlp;

namespace {

class HeaderMapCarrier
    : public opentelemetry::context::propagation::TextMapCarrier {
  public:
    explicit HeaderMapCarrier(uh::cluster::trace_headers& headers)
        : m_headers(headers) {}

    opentelemetry::nostd::string_view
    Get(opentelemetry::nostd::string_view key) const noexcept override {
        const auto key_to_compare = std::string(key.data(), key.size());
        auto it = m_headers.find(key_to_compare);
        if (it == m_headers.end()) {
            return {};
        }
        return {it->second.data(), it->second.size()};
    }

    void Set(opentelemetry::nostd::string_view key,
             opentelemetry::nostd::string_view value) noexcept override {
        m_headers[std::string(key.data(), key.size())] =
            std::string(value.data(), value.size());
    }

  private:
    uh::cluster::trace_headers& m_headers;
};

void init_propagation() {
    opentelemetry::context::propagation::GlobalTextMapPropagator::
        SetGlobalPropagator(
            opentelemetry::nostd::shared_ptr<
                opentelemetry::context::propagation::TextMapPropagator>(
                new opentelemetry::trace::propagation::HttpTraceContext()));

    auto prop = opentelemetry::context::propagation::GlobalTextMapPropagator::
        GetGlobalPropagator();
    if (!prop)
        throw std::runtime_error("Failed to set global propagator");
}
} // namespace

namespace uh::cluster {

void initialize_trace(const std::string& tracer_name,
                      const std::string& tracer_version,
                      const std::string& endpoint) {
    boost::asio::traced_asio_initialize(tracer_name, tracer_version);

    if (endpoint == TRACE_STDOUT_ENDPOINT) {
        auto exporter = opentelemetry::exporter::trace::
            OStreamSpanExporterFactory::Create();
        auto processor =
            trace_sdk::SimpleSpanProcessorFactory::Create(std::move(exporter));
        std::shared_ptr<opentelemetry::trace::TracerProvider> provider =
            trace_sdk::TracerProviderFactory::Create(std::move(processor));
        trace_api::Provider::SetTracerProvider(provider);
    } else {
        trace_sdk::BatchSpanProcessorOptions bspOpts{};
        opentelemetry::exporter::otlp::OtlpGrpcExporterOptions opts;
        opts.endpoint = endpoint;
        auto exporter = otlp::OtlpGrpcExporterFactory::Create(opts);
        auto processor = trace_sdk::BatchSpanProcessorFactory::Create(
            std::move(exporter), bspOpts);

        std::shared_ptr<opentelemetry::trace::TracerProvider> provider =
            trace_sdk::TracerProviderFactory::Create(std::move(processor));
        trace_api::Provider::SetTracerProvider(provider);
    }

    init_propagation();
}

trace_headers encode_context_headers(const trace_context& context) {
    trace_headers headers;
    HeaderMapCarrier carrier(headers);

    auto propagator = opentelemetry::context::propagation::
        GlobalTextMapPropagator::GetGlobalPropagator();
    propagator->Inject(
        carrier,
        boost::asio::detail::trace_context_bridge::native_context(context));

    return headers;
}

trace_context decode_context_headers(const trace_headers& headers) {
    auto headers_copy = headers;
    HeaderMapCarrier carrier(headers_copy);

    auto propagator = opentelemetry::context::propagation::
        GlobalTextMapPropagator::GetGlobalPropagator();

    opentelemetry::context::Context empty_context;
    auto context = propagator->Extract(carrier, empty_context);
    return boost::asio::detail::trace_context_bridge::make_trace_context(
        std::move(context));
}

std::string encode_context(const trace_context& context) {
    auto headers = encode_context_headers(context);
    auto it = headers.find("traceparent");
    auto desired_length = get_encoded_context_len();
    if (it == headers.end() || it->second.size() != desired_length) {
        auto ret = std::string{};
        ret.resize(desired_length);
        return ret;
    }
    return it->second;
}

trace_context decode_context(std::string traceparent) {
    if (traceparent.empty()) {
        return {};
    }

    trace_headers headers;
    headers["traceparent"] = std::move(traceparent);
    return decode_context_headers(headers);
}

} // namespace uh::cluster
