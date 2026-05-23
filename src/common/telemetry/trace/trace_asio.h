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

#include <boost/asio.hpp>

#include <functional>
#include <initializer_list>
#include <memory>
#include <string>
#include <string_view>
#include <type_traits>
#include <utility>
#include <variant>
#include <vector>

namespace boost::asio {

template <typename, typename> class traced_awaitable;

namespace this_coro {
struct span_t {
    constexpr span_t() {}
};

inline constexpr span_t span;

struct context_t {
    constexpr context_t() {}
};

inline constexpr context_t context;

} // namespace this_coro

namespace detail {
template <typename, typename> class traced_awaitable_frame;
} // namespace detail

using trace_attribute_value =
    std::variant<bool, int64_t, uint64_t, double, std::string>;
using trace_attributes =
    std::vector<std::pair<std::string, trace_attribute_value>>;

namespace detail {

template <typename> inline constexpr bool dependent_false_v = false;

template <typename Value>
trace_attribute_value make_trace_attribute_value(Value&& value) {
    using D = std::decay_t<Value>;

    if constexpr (std::is_same_v<D, trace_attribute_value>) {
        return std::forward<Value>(value);
    } else if constexpr (std::is_same_v<D, bool>) {
        return value;
    } else if constexpr (std::is_integral_v<D> && std::is_signed_v<D>) {
        return static_cast<int64_t>(value);
    } else if constexpr (std::is_integral_v<D> && std::is_unsigned_v<D>) {
        return static_cast<uint64_t>(value);
    } else if constexpr (std::is_floating_point_v<D>) {
        return static_cast<double>(value);
    } else if constexpr (std::is_convertible_v<D, std::string_view>) {
        return std::string(std::string_view{std::forward<Value>(value)});
    } else {
        static_assert(dependent_false_v<D>,
                      "Unsupported trace attribute value type");
    }
}

} // namespace detail

class trace_span {
public:
    inline static bool enable = true;
    trace_span();
    ~trace_span();

    trace_span(const trace_span&) = delete;
    trace_span& operator=(const trace_span&) = delete;
    trace_span(trace_span&&) noexcept;
    trace_span& operator=(trace_span&&) noexcept;

    void set_location(const source_location& location) noexcept;
    void set_name(std::string_view name) noexcept;

    template <typename Value>
    void set_attribute(std::string_view key, Value&& value) noexcept {
        try {
            set_attribute_impl(key, detail::make_trace_attribute_value(
                                        std::forward<Value>(value)));
        } catch (...) {
        }
    }

    void add_event(std::string_view name, trace_attributes attributes) noexcept;

    template <class U>
    void add_event(std::string_view name, const U& attributes) noexcept {
        try {
            trace_attributes attrs;
            for (const auto& attribute : attributes) {
                attrs.emplace_back(
                    std::string(attribute.first),
                    detail::make_trace_attribute_value(attribute.second));
            }
            add_event(name, std::move(attrs));
        } catch (...) {
        }
    }

    void
    add_event(std::string_view name,
              const std::initializer_list<std::pair<std::string, std::string>>&
                  attributes) noexcept {
        trace_attributes attrs;
        attrs.reserve(attributes.size());
        for (const auto& attribute : attributes) {
            attrs.emplace_back(attribute.first, attribute.second);
        }
        add_event(name, std::move(attrs));
    }

    void add_event(std::string_view name) noexcept;

    trace_context context() const noexcept;

    static bool is_enabled() noexcept;
    bool is_started() const noexcept;
    bool has_context() const noexcept;

    // For Debugging
    void iterate_call_stack(std::function<void(source_location)> process);

    // For Debugging
    static std::string trace_id(const trace_context& context) noexcept;

    // For Debugging
    static bool check_context(const trace_context& context);

private:
    template <typename, typename> friend class boost::asio::traced_awaitable;
    template <typename, typename>
    friend class boost::asio::detail::traced_awaitable_frame;
    friend boost::asio::this_coro::span_t;
    friend boost::asio::this_coro::context_t;

    struct impl;
    std::unique_ptr<impl> m_impl;

    void set_parent(trace_span* parent) noexcept;
    void start_span(trace_context context) noexcept;
    static trace_context root_context() noexcept;
    void set_attribute_impl(std::string_view key,
                            trace_attribute_value value) noexcept;
};

template <typename T, typename Executor = any_io_executor>
class BOOST_ASIO_NODISCARD traced_awaitable : public awaitable<T, Executor> {
public:
    using awaitable<T, Executor>::awaitable;
    explicit traced_awaitable(
        awaitable<T, Executor>&& other,
        detail::traced_awaitable_frame<T, Executor>* frame)
        : awaitable<T, Executor>(std::move(other)),
          m_frame{frame} {}

    template <class U>
    void await_suspend(
        detail::coroutine_handle<detail::traced_awaitable_frame<U, Executor>>
            h) {
        auto& parent_promise = h.promise();

        auto parent_span = parent_promise.span();

        if (m_frame != nullptr) {
            auto current_span = m_frame->span();
            current_span->set_parent(parent_span);
            if (!current_span->has_context() && parent_span->has_context()) {
                current_span->start_span(parent_span->context());
            }
        }

        awaitable<T, Executor>::await_suspend(
            detail::coroutine_handle<detail::awaitable_frame<U, Executor>>::
                from_promise(parent_promise));
    }
    detail::traced_awaitable_frame<T, Executor>* get_coroutine_frame() {
        return m_frame;
    }

    auto& continue_trace(trace_context parent_context) & {
        if (m_frame != nullptr) {
            auto current_span = m_frame->span();
            if (!current_span->has_context()) {
                current_span->start_span(std::move(parent_context));
            }
        }
        return *this;
    }

    auto&& continue_trace(trace_context parent_context) && {
        return std::move(this->continue_trace(std::move(parent_context)));
    }

    auto& start_trace() & { return continue_trace(trace_span::root_context()); }

    auto&& start_trace() && { return std::move(this->start_trace()); }

    auto& set_name(std::string_view name) & noexcept {
        if (m_frame != nullptr) {
            m_frame->span()->set_name(name);
        }
        return *this;
    }

    auto&& set_name(std::string_view name) && noexcept {
        return std::move(this->set_name(name));
    }

    template <typename Value>
    auto& set_attribute(std::string_view key, Value&& value) & noexcept {
        if (m_frame != nullptr) {
            m_frame->span()->set_attribute(key, std::forward<Value>(value));
        }
        return *this;
    }

    template <typename Value>
    auto&& set_attribute(std::string_view key, Value&& value) && noexcept {
        return std::move(this->set_attribute(key, std::forward<Value>(value)));
    }

    template <class U>
    auto& add_event(std::string_view name, const U& attributes) & noexcept {
        if (m_frame != nullptr) {
            m_frame->span()->add_event(name, attributes);
        }
        return *this;
    }

    template <class U>
    auto&& add_event(std::string_view name, const U& attributes) && noexcept {
        return std::move(this->add_event(name, attributes));
    }

    auto&
    add_event(std::string_view name,
              const std::initializer_list<std::pair<std::string, std::string>>&
                  attributes) & noexcept {
        if (m_frame != nullptr) {
            m_frame->span()->add_event(name, attributes);
        }
        return *this;
    }

    auto&&
    add_event(std::string_view name,
              const std::initializer_list<std::pair<std::string, std::string>>&
                  attributes) && noexcept {
        return std::move(this->add_event(name, attributes));
    }

    auto& add_event(std::string_view name) & noexcept {
        if (m_frame != nullptr) {
            m_frame->span()->add_event(name);
        }
        return *this;
    }

    auto&& add_event(std::string_view name) && noexcept {
        return std::move(this->add_event(name));
    }

private:
    detail::traced_awaitable_frame<T, Executor>* m_frame{nullptr};
};

#define CURRENT_LOCATION                                                       \
    ::boost::source_location(__builtin_FILE(), __builtin_LINE(),               \
                             __builtin_FUNCTION())

namespace detail {
template <typename T, typename Executor>
class traced_awaitable_frame : public awaitable_frame<T, Executor> {
public:
    using awaitable_frame<T, Executor>::awaitable_frame;

    auto initial_suspend(
        const source_location& location = CURRENT_LOCATION) noexcept {
        m_span.set_location(location);
        return awaitable_frame<T, Executor>::initial_suspend();
    }

    traced_awaitable<T, Executor> get_return_object() noexcept {
        return traced_awaitable<T, Executor>(
            awaitable_frame<T, Executor>::get_return_object(), this);
    }

    using awaitable_frame_base<Executor>::await_transform;

    template <typename U>
    auto await_transform(traced_awaitable<U, Executor> a) const {
        return traced_awaitable<U, Executor>(
            awaitable_frame_base<Executor>::await_transform(
                std::move(static_cast<awaitable<U, Executor>&>(a))),
            a.get_coroutine_frame());
    }

    template <typename U> auto await_transform(awaitable<U, Executor> a) const {
        return traced_awaitable<U, Executor>(
            awaitable_frame_base<Executor>::await_transform(std::move(a)),
            nullptr);
    }

    auto await_transform(this_coro::span_t) noexcept {
        struct result {
            traced_awaitable_frame* this_;

            bool await_ready() const noexcept { return true; }

            void await_suspend(coroutine_handle<void>) noexcept {}

            auto await_resume() const noexcept { return this_->span(); }
        };

        return result{this};
    }

    auto await_transform(this_coro::context_t) noexcept {
        struct result {
            traced_awaitable_frame* this_;

            bool await_ready() const noexcept { return true; }

            void await_suspend(coroutine_handle<void>) noexcept {}

            auto await_resume() const noexcept {
                return this_->span()->context();
            }
        };

        return result{this};
    }

    trace_span* span() noexcept { return &m_span; }

private:
    trace_span m_span;
};

// void specialization
template <typename Executor>
class traced_awaitable_frame<void, Executor>
    : public awaitable_frame<void, Executor> {
public:
    using awaitable_frame<void, Executor>::awaitable_frame;

    auto initial_suspend(
        const source_location& location = CURRENT_LOCATION) noexcept {
        m_span.set_location(location);
        return awaitable_frame<void, Executor>::initial_suspend();
    }

    traced_awaitable<void, Executor> get_return_object() noexcept {
        return traced_awaitable<void, Executor>(
            awaitable_frame<void, Executor>::get_return_object(), this);
    }

    using awaitable_frame_base<Executor>::await_transform;

    template <typename U>
    auto await_transform(traced_awaitable<U, Executor> a) const {
        return traced_awaitable<U, Executor>(
            awaitable_frame_base<Executor>::await_transform(
                std::move(static_cast<awaitable<U, Executor>&>(a))),
            a.get_coroutine_frame());
    }

    template <typename U> auto await_transform(awaitable<U, Executor> a) const {
        return traced_awaitable<U, Executor>(
            awaitable_frame_base<Executor>::await_transform(std::move(a)),
            nullptr);
    }

    auto await_transform(this_coro::span_t) noexcept {
        struct result {
            traced_awaitable_frame* this_;

            bool await_ready() const noexcept { return true; }

            void await_suspend(coroutine_handle<void>) noexcept {}

            auto await_resume() const noexcept { return this_->span(); }
        };

        return result{this};
    }

    auto await_transform(this_coro::context_t) noexcept {
        struct result {
            traced_awaitable_frame* this_;

            bool await_ready() const noexcept { return true; }

            void await_suspend(coroutine_handle<void>) noexcept {}

            auto await_resume() const noexcept {
                return this_->span()->context();
            }
        };

        return result{this};
    }

    trace_span* span() noexcept { return &m_span; }

private:
    trace_span m_span;
};

} // namespace detail

namespace detail {

template <typename T> struct traced_awaitable_signature;

template <typename T, typename Executor>
struct traced_awaitable_signature<traced_awaitable<T, Executor>> {
    typedef void type(std::exception_ptr, T);
};

template <typename Executor>
struct traced_awaitable_signature<traced_awaitable<void, Executor>> {
    typedef void type(std::exception_ptr);
};

} // namespace detail

template <
    typename Executor, typename F,
    BOOST_ASIO_COMPLETION_TOKEN_FOR(typename detail::traced_awaitable_signature<
                                    result_of_t<F()>>::type) CompletionToken>
inline BOOST_ASIO_INITFN_AUTO_RESULT_TYPE(
    CompletionToken,
    typename detail::traced_awaitable_signature<result_of_t<F()>>::type)
    co_spawn(const Executor& ex, F&& f, CompletionToken&& token,
             constraint_t<is_executor<Executor>::value ||
                          execution::is_executor<Executor>::value> = 0) {
    return async_initiate<
        CompletionToken,
        typename detail::traced_awaitable_signature<result_of_t<F()>>::type>(
        detail::initiate_co_spawn<typename result_of_t<F()>::executor_type>(ex),
        token, std::forward<F>(f));
}

template <
    typename ExecutionContext, typename F,
    BOOST_ASIO_COMPLETION_TOKEN_FOR(typename detail::traced_awaitable_signature<
                                    result_of_t<F()>>::type) CompletionToken>
inline BOOST_ASIO_INITFN_AUTO_RESULT_TYPE(
    CompletionToken,
    typename detail::traced_awaitable_signature<result_of_t<F()>>::type)
    co_spawn(ExecutionContext& ctx, F&& f, CompletionToken&& token,
             constraint_t<is_convertible<ExecutionContext&,
                                         execution_context&>::value> = 0) {
    return (co_spawn)(ctx.get_executor(), std::forward<F>(f),
                      std::forward<CompletionToken>(token));
}

void traced_asio_initialize(const std::string& tracer_name,
                            const std::string& tracer_version);

} // namespace boost::asio

namespace std {
template <typename T, typename Executor, typename... Args>
struct coroutine_traits<boost::asio::traced_awaitable<T, Executor>, Args...> {
    typedef boost::asio::detail::traced_awaitable_frame<T, Executor>
        promise_type;
};
} // namespace std