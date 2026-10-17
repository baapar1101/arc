#!/bin/sh
set -eu

: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"

seed_file=""
for candidate in /seed/hesabix_seed*.dump; do
  [ -f "$candidate" ] || continue
  # Shell pathname expansion is lexically sorted; the seed filenames carry timestamps.
  seed_file="$candidate"
done

if [ -z "$seed_file" ]; then
  echo "No hesabix_seed*.dump file found in /seed." >&2
  exit 1
fi

until pg_isready --host=db --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" >/dev/null 2>&1; do
  echo "Waiting for PostgreSQL..."
  sleep 2
done

table_count="$(psql --host=db --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
  --no-psqlrc --tuples-only --no-align --set=ON_ERROR_STOP=1 \
  --command="SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';" \
  | tr -d '[:space:]')"

if [ "$table_count" -gt 0 ]; then
  missing="$(psql --host=db --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
    --no-psqlrc --tuples-only --no-align --set=ON_ERROR_STOP=1 \
    --command="SELECT string_agg(required.name, ', ' ORDER BY required.name) FROM (VALUES ('accounts'), ('businesses'), ('document_lines'), ('documents'), ('users')) AS required(name) WHERE to_regclass('public.' || required.name) IS NULL;" \
    | tr -d '[:space:]')"
  if [ -z "$missing" ]; then
    echo "Hesabix base schema is already present; seed import skipped."
    exit 0
  fi
  echo "Database is not empty but its Hesabix base schema is incomplete (missing: $missing)." >&2
  echo "Refusing to reset or overwrite existing database contents." >&2
  exit 1
fi

echo "Importing initial Hesabix data from $(basename "$seed_file")..."
pg_restore --host=db --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
  --no-owner --no-acl --exit-on-error "$seed_file"

missing="$(psql --host=db --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
  --no-psqlrc --tuples-only --no-align --set=ON_ERROR_STOP=1 \
  --command="SELECT string_agg(required.name, ', ' ORDER BY required.name) FROM (VALUES ('accounts'), ('businesses'), ('document_lines'), ('documents'), ('users')) AS required(name) WHERE to_regclass('public.' || required.name) IS NULL;" \
  | tr -d '[:space:]')"
if [ -n "$missing" ]; then
  echo "Seed import completed without required Hesabix tables: $missing" >&2
  exit 1
fi

echo "Initial Hesabix schema and data imported successfully."
