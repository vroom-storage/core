#!/bin/bash
set -e

until pg_isready -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT"; do
    echo 'Waiting for postgres...'
    sleep 2
done

psql -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" -d postgres \
    -f /sql/provision_databases.sql

psql -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" -d vrm \
    -f /sql/vrm.sql
