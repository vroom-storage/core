#!/bin/bash
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


set -e

until pg_isready -U postgres -h $DB_HOST -p $DB_PORT; do echo 'Waiting for postgres...'; sleep 2; done

# Provision the database in advance
cat /sql/provision_databases.sql | psql -U $DB_USER -h $DB_HOST -p $DB_PORT -d postgres

# Fill out the database with its schema
psql -U $DB_USER -h $DB_HOST -p $DB_PORT -d vrm -f /sql/vrm.sql

# Set up the super user
vrm-cluster-access-client --db-host $DB_HOST:$DB_PORT --db-user $DB_USER --db-pass $PGPASSWORD user-add --superuser --if-not-exists $SUPER_USER_USERNAME
vrm-cluster-access-client --db-host $DB_HOST:$DB_PORT --db-user $DB_USER --db-pass $PGPASSWORD key-add --if-not-exists $SUPER_USER_USERNAME $SUPER_USER_ACCESS_KEY_ID $SUPER_USER_SECRET_KEY

