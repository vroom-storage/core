/*
 * Copyright 2026 UltiHash Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 */

#pragma once

#include <cstdint>
#include <memory>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <typeinfo>
#include <utility>
#include <variant>

namespace boost::asio {

namespace detail {
class trace_context_bridge;
} // namespace detail

using trace_context_value =
    std::variant<std::monostate, bool, int64_t, uint64_t, double>;

class trace_context {
  public:
    trace_context();
    trace_context(const trace_context &);
    trace_context(trace_context &&) noexcept;
    trace_context &operator=(const trace_context &);
    trace_context &operator=(trace_context &&) noexcept;
    ~trace_context();

    void set_value(const std::string &key, trace_context_value val);
    trace_context_value get_value(const std::string &key) const;
    void set_baggage(const std::string &key, const std::string &value);
    std::string get_baggage(const std::string &key) const;

  private:
    struct impl;
    std::shared_ptr<impl> m_impl;

    explicit trace_context(std::shared_ptr<impl> impl);

    friend class trace_span;
    friend class detail::trace_context_bridge;
};

namespace context {

template <typename T>
concept value_type_t = std::is_same_v<T, bool> || std::is_same_v<T, int64_t> ||
                       std::is_same_v<T, uint64_t> || std::is_same_v<T, double>;

using value = trace_context_value;

inline void set_value(trace_context &ctx, const std::string &key, value val) {
    ctx.set_value(key, std::move(val));
}

inline value get_value(const trace_context &ctx, const std::string &key) {
    return ctx.get_value(key);
}

template <value_type_t T>
void set_value(trace_context &ctx, const std::string &key, T val) {
    set_value(ctx, key, value{val});
}

template <value_type_t T>
T get_value(const trace_context &ctx, const std::string &key) {
    auto val = get_value(ctx, key);
    if (!std::holds_alternative<T>(val)) {
        throw std::runtime_error(
            "Value type mismatch for key: " + key +
            ". Expected type: " + std::string(typeid(T).name()));
    }
    return std::get<T>(val);
}

/*
 * NOTE: You can set and get pointers only in a single process.
 */
template <typename T>
void set_pointer(trace_context &ctx, const std::string &key, T *ptr) {
    set_value(ctx, key, static_cast<uint64_t>(reinterpret_cast<uintptr_t>(ptr)));
}

template <typename T>
T *get_pointer(const trace_context &ctx, const std::string &key) {
    auto val = get_value(ctx, key);
    if (std::holds_alternative<uint64_t>(val)) {
        return reinterpret_cast<T *>(
            static_cast<uintptr_t>(std::get<uint64_t>(val)));
    }
    return nullptr;
}

void set_baggage(trace_context &ctx, const std::string &key,
                 const std::string &value);
std::string get_baggage(const trace_context &ctx, const std::string &key);

} // namespace context
} // namespace boost::asio
