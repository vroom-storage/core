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

include(profiler)

#vrm_add_profiler(profile_deduplicator PRIVATE vrm_mock_global_data vrm_test_util deduplicator group_data)
#vrm_add_profiler(profile_ec_write PRIVATE vrm_test_util storage)
vrm_add_profiler(benchmark_local_storage PRIVATE vrm_test_util storage)
