#!/usr/bin/env bash
# Applies every migration and the seed to an empty PostgreSQL + PostGIS
# database, then runs the SQL tests. Used by CI and locally:
#   PGHOST=localhost PGPORT=5432 PGUSER=postgres supabase/tests/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."
db="${TEST_DB:-drishti_test}"
psql -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists $db" -c "create database $db"
psql -v ON_ERROR_STOP=1 -q -d "$db" -c "alter database $db set search_path = public, extensions"
run() { psql -v ON_ERROR_STOP=1 -q -X -d "$db" -f "$1"; }
run tests/00_supabase_stub.sql
for f in migrations/*.sql; do echo "migrate $f"; run "$f"; done
echo "seed"; run seed.sql
for f in tests/[1-9]*_test.sql; do echo "test $f"; run "$f"; done
