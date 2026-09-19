#!/usr/bin/env bash
# Ensure hesabix role owns/can access public objects (after pg_restore --no-owner or legacy deploys).
set -euo pipefail

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

if ! sudo -u postgres psql -d hesabix -c "SELECT 1" >/dev/null 2>&1; then
  log_info "Database hesabix not ready; skipping privilege fixup."
  exit 0
fi

log_info "Fixing public schema ownership and grants for hesabix..."
sudo -u postgres psql -d hesabix -v ON_ERROR_STOP=1 <<'SQL'
ALTER SCHEMA public OWNER TO hesabix;
GRANT ALL ON SCHEMA public TO hesabix;
GRANT ALL ON ALL TABLES IN SCHEMA public TO hesabix;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO hesabix;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO hesabix;
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p', 'v', 'm')
      AND pg_get_userbyid(c.relowner) = 'postgres'
  LOOP
    EXECUTE format('ALTER TABLE public.%I OWNER TO hesabix', r.relname);
  END LOOP;
END $$;
SQL

log_info "Database privilege fixup completed."
