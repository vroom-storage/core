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

#include "trace_context.h"

#include <concepts>
#include <map>
#include <string>
#include <string_view>
#include <utility>

namespace vrm::cluster {

inline constexpr std::string TRACE_STDOUT_ENDPOINT = "stdout";

using trace_context = boost::asio::trace_context;
using trace_headers = std::map<std::string, std::string>;

template <typename T>
concept HttpRequestLike =
    requires(T message, const std::string& key, std::string_view value) {
        { message.set(key, value) };
        { message[key] } -> std::convertible_to<std::string_view>;
    };

template <typename T>
concept MapLike = requires(T message, typename T::key_type key,
                           typename T::mapped_type value) {
    typename T::key_type;
    typename T::mapped_type;
    {
        message.insert(
            std::pair<typename T::key_type, typename T::mapped_type>(key,
                                                                    value))
    };
    { message.find(key) } -> std::same_as<decltype(message.end())>;
    { message.end() };
};

void initialize_trace(const std::string& tracer_name,
                      const std::string& tracer_version,
                      const std::string& endpoint = "localhost:4317");

trace_headers encode_context_headers(const trace_context& context);
trace_context decode_context_headers(const trace_headers& headers);

template <HttpRequestLike Req>
void encode_context(Req& req, const trace_context& context) {
    auto headers = encode_context_headers(context);
    for (const auto& [key, value] : headers) {
        req.set(key, value);
    }
}

template <HttpRequestLike Req>
trace_context decode_context(Req& req) {
    trace_headers headers;

    auto add_header = [&](std::string key) {
        auto value = std::string_view(req[key]);
        if (!value.empty()) {
            headers.emplace(std::move(key), std::string(value));
        }
    };

    add_header("traceparent");
    add_header("tracestate");

    return decode_context_headers(headers);
}

template <MapLike Map>
void encode_context(Map& map, const trace_context& context) {
    auto headers = encode_context_headers(context);
    for (const auto& [key, value] : headers) {
        map.insert(std::pair<typename Map::key_type, typename Map::mapped_type>(
            key, value));
    }
}

template <MapLike Map>
trace_context decode_context(Map& map) {
    trace_headers headers;

    auto add_header = [&](const std::string& key) {
        auto it = map.find(key);
        if (it != map.end()) {
            auto value = std::string_view(it->second);
            if (!value.empty()) {
                headers.emplace(key, std::string(value));
            }
        }
    };

    add_header("traceparent");
    add_header("tracestate");

    return decode_context_headers(headers);
}

template <std::size_t N>
constexpr std::size_t constexpr_strlen(const char (&str)[N]) {
    return N - 1;
}

constexpr auto get_encoded_context_len() {
    constexpr auto length = constexpr_strlen(
        "00-996c6ce7ece3dcf1d2acfb7b89421fd6-28a16557cb531132-01");
    return length;
}

std::string encode_context(const trace_context& context);
trace_context decode_context(std::string traceparent);

} // namespace vrm::cluster