# Copyright 2026 UltiHash Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set_property(GLOBAL PROPERTY TEST_TYPE "unit")

vrm_add_test(test_address)
vrm_add_test(test_http_client PRIVATE http_server network nlohmann_json)
vrm_add_test(test_async_http_client PRIVATE http_server network nlohmann_json)
vrm_add_test(test_backend_client PRIVATE http_server network nlohmann_json)
vrm_add_test(test_task)
vrm_add_test(test_cors PRIVATE entrypoint)
vrm_add_test(test_cpr PRIVATE http_server nlohmann_json cpr::cpr)
vrm_add_test(test_data_file PRIVATE storage)
vrm_add_test(test_deduplicator PRIVATE vrm_mock_global_data deduplicator)
vrm_add_test(test_deletion_queue)
vrm_add_test(test_disk_cache_body PRIVATE vrm_mock_global_data entrypoint storage)
vrm_add_test(test_disk_cache_manager PRIVATE vrm_mock_global_data entrypoint storage)
vrm_add_test(test_exp_backoff PRIVATE license)
vrm_add_test(test_formats PRIVATE entrypoint)
vrm_add_test(test_hash PRIVATE vrmcrypto)
vrm_add_test(test_http_range PRIVATE entrypoint)
vrm_add_test(test_integral)
vrm_add_test(test_lfu_cache)
vrm_add_test(test_license PRIVATE license)
vrm_add_test(test_namespace)
vrm_add_test(test_opentelemetry PRIVATE telemetry)
vrm_add_test(test_parallel_coroutines PRIVATE telemetry)
vrm_add_test(test_plain_cache)
vrm_add_test(test_pointer_traits)
vrm_add_test(test_policies PRIVATE vrm_mock_entrypoint)
vrm_add_test(test_policies_with_action PRIVATE vrm_mock_entrypoint)
vrm_add_test(test_policies_with_condition PRIVATE vrm_mock_entrypoint)
vrm_add_test(test_policies_with_examples PRIVATE vrm_mock_entrypoint)
vrm_add_test(test_policy_parser PRIVATE entrypoint)
vrm_add_test(test_pool)
vrm_add_test(test_promise_future)
vrm_add_test(test_proxy_cache)
vrm_add_test(test_scoped_buffer)
# vrm_add_test(test_service_registry PRIVATE etcd)
add_executable(signals signals.cpp)
target_link_libraries(signals Boost::headers)
#vrm_add_test(test_signals)
#add_dependencies(test_signals signals)
vrm_add_test(test_storage_group_config PRIVATE group_data)
# vrm_add_test(test_storage_group_externals PRIVATE group_data storage_interfaces)
# vrm_add_test(test_storage_group_internals PRIVATE group_data)
vrm_add_test(test_strings)
vrm_add_test(test_trace_asio PRIVATE telemetry)
vrm_add_test(test_variables PRIVATE vrm_mock_entrypoint)
vrm_add_test(test_xml_parser)
vrm_add_test(test_beast)
