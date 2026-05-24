#pragma once

#include <util/coroutine.h>
#include <util/temp_directory.h>
#include <mock/storage/mock_data_view.h>

namespace uh::cluster {

struct storage_fixture : public coro_fixture {

    storage_fixture()
        : coro_fixture(2),
          ds_config({ .max_file_size = 128 * KIBI_BYTE,
                      .max_data_store_size = 4 * MEBI_BYTE,
                      .page_size = DEFAULT_PAGE_SIZE }),
          data_store(ds_config, tmp.path().string(), 1, 0),
          data_view(data_store)
    {}

    temp_directory tmp;
    data_store_config ds_config;
    mock_data_store data_store;
    mock_data_view data_view;
};

}
