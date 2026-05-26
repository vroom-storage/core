#include <benchmark/benchmark.h>

#include <common/utils/random.h>
#include <storage/interfaces/local_storage.h>

#include <util/temp_directory.h>

#include <memory>

namespace {

using namespace uh::cluster;

struct storage_fixture : public benchmark::Fixture {

    struct fixture_state {
        fixture_state()
            : dir(),
              store({}, dir.path(), 0),
              random_4k(random_string(4 * 1024)),
              random_64k(random_string(64 * 1024)),
              random_1024k(random_string(1024 * 1024))
        {}

        temp_directory dir;
        default_data_store store;

        std::string random_4k;
        std::string random_64k;
        std::string random_1024k;
    };

    void SetUp(const ::benchmark::State& state) override {
        s = std::make_unique<fixture_state>();
    }

    void TearDown(const ::benchmark::State& state) override {
        s.reset();
    }

    std::unique_ptr<fixture_state> s;
};

BENCHMARK_F(storage_fixture, profile_storage_write_4k)
    (benchmark::State& state) {
    const auto& data = s->random_4k;
    for (auto _ : state) {
        auto alloc = s->store.allocate(data.size());
        s->store.write(alloc, { std::span<const char>{data.c_str(), data.size() } });
    }
}

}
