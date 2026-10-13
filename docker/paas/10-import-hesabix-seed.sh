#!/bin/sh
set -eu

: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_DB:?POSTGRES_DB is required}"

echo "Importing the initial Hesabix database seed..."
pg_restore --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
  --no-owner --no-acl --exit-on-error \
  /docker-entrypoint-initdb.d/hesabix-seed.dump

missing="$(psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
  --no-psqlrc --tuples-only --no-align --set=ON_ERROR_STOP=1 \
  --command="SELECT string_agg(required.name, ', ' ORDER BY required.name) FROM (VALUES ('accounts'), ('businesses'), ('document_lines'), ('documents'), ('users')) AS required(name) WHERE to_regclass('public.' || required.name) IS NULL;" \
  | tr -d '[:space:]')"

if [ -n "$missing" ]; then
  echo "Seed import completed without required Hesabix tables: $missing" >&2
  exit 1
fi

echo "Initial Hesabix schema and data imported successfully."
