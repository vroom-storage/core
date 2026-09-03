#!/bin/bash
set -e

until pg_isready -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT"; do
    echo 'Waiting for postgres...'
    sleep 2
done

psql -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" -d postgres \
    -f /sql/provision_databases.sql

for schema in /sql/*.sql; do
    database="$(basename "$schema" .sql)"
    [ "$database" = "provision_databases" ] && continue
    psql -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" -d "$database" -f "$schema"
done
