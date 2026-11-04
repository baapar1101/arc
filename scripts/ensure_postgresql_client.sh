#!/usr/bin/env bash
# نصب idempotent بستهٔ postgresql-client هم‌نسخه با سرور PostgreSQL.
# مشکل رایج Ubuntu/Debian: postgresql-client-common فقط wrapper می‌گذارد و
# /usr/bin/pg_dump با این پیام می‌میرد:
#   Error: You must install at least one postgresql-client-<version> package
# این اسکریپت از deploy.sh، update.sh و hesabix-api-prestart.sh صدا زده می‌شود
# تا نصب‌های قبلی هم با update یا ری‌استارت API کلاینت واقعی را بگیرند.
#
# Usage:
#   ensure_postgresql_client.sh           # exit 1 if tools still missing
#   ensure_postgresql_client.sh --nonfatal  # always exit 0 (API prestart)
set -euo pipefail

NONFATAL=0
if [[ "${1:-}" == "--nonfatal" ]]; then
  NONFATAL=1
fi

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
log_ok()   { echo "OK: $*"; }
log_warn() { echo "WARN: $*" >&2; }

finish() {
  local rc="$1"
  if [[ "${NONFATAL}" -eq 1 ]]; then
    exit 0
  fi
  exit "${rc}"
}

real_pg_bin() {
  local major="${1:-}"
  local tool="${2:-pg_dump}"
  if [[ -n "${major}" ]] && [[ -x "/usr/lib/postgresql/${major}/bin/${tool}" ]]; then
    printf '%s' "/usr/lib/postgresql/${major}/bin/${tool}"
    return 0
  fi
  return 1
}

tools_ready_for_major() {
  local major="${1:-}"
  [[ -n "${major}" ]] || return 1
  [[ -x "/usr/lib/postgresql/${major}/bin/pg_dump" ]] || return 1
  [[ -x "/usr/lib/postgresql/${major}/bin/psql" ]] || return 1
  [[ -x "/usr/lib/postgresql/${major}/bin/pg_restore" ]] || return 1
}

any_versioned_pg_dump() {
  local m
  for m in 18 17 16 15 14 13 12; do
    if [[ -x "/usr/lib/postgresql/${m}/bin/pg_dump" ]]; then
      printf '%s' "${m}"
      return 0
    fi
  done
  return 1
}

detect_postgresql_major() {
  local v d cluster_online cluster_any
  if command -v pg_lsclusters >/dev/null 2>&1; then
    cluster_online=$(pg_lsclusters 2>/dev/null | awk 'NR>1 && $1 ~ /^[0-9]+$/ && $4 ~ /online/ {print $1; exit}')
    if [[ -n "${cluster_online}" ]]; then
      printf '%s' "${cluster_online}"
      return 0
    fi
    cluster_any=$(pg_lsclusters 2>/dev/null | awk 'NR>1 && $1 ~ /^[0-9]+$/ {print $1; exit}')
    if [[ -n "${cluster_any}" ]]; then
      printf '%s' "${cluster_any}"
      return 0
    fi
  fi
  if command -v psql >/dev/null 2>&1; then
    v=$(psql -h 127.0.0.1 -U postgres -tAc "SHOW server_version_num;" 2>/dev/null | tr -d '[:space:]' || true)
    if [[ "${v}" =~ ^[0-9]+$ ]] && [[ "${v}" -ge 10000 ]]; then
      echo $((10#${v} / 10000))
      return 0
    fi
  fi
  if command -v sudo >/dev/null 2>&1; then
    v=$(sudo -n -u postgres psql -tAc "SHOW server_version_num;" 2>/dev/null | tr -d '[:space:]' || true)
    if [[ "${v}" =~ ^[0-9]+$ ]] && [[ "${v}" -ge 10000 ]]; then
      echo $((10#${v} / 10000))
      return 0
    fi
  fi
  shopt -s nullglob
  for d in /etc/postgresql/*/main; do
    [[ -d "${d}" ]] || continue
    v=$(basename "$(dirname "${d}")")
    if [[ "${v}" =~ ^[0-9]+$ ]]; then
      echo "${v}"
      shopt -u nullglob
      return 0
    fi
  done
  for d in /usr/lib/postgresql/*/bin/postgres; do
    [[ -x "${d}" ]] || continue
    v=$(basename "$(dirname "$(dirname "${d}")")")
    if [[ "${v}" =~ ^[0-9]+$ ]]; then
      echo "${v}"
      shopt -u nullglob
      return 0
    fi
  done
  shopt -u nullglob
  if command -v dpkg-query >/dev/null 2>&1; then
    v=$(dpkg-query -W -f='${Package}\n' 'postgresql-[0-9]*' 2>/dev/null \
      | sed -n 's/^postgresql-\([0-9][0-9]*\)$/\1/p' | sort -nr | head -1 || true)
    if [[ "${v}" =~ ^[0-9]+$ ]]; then
      printf '%s' "${v}"
      return 0
    fi
  fi
  return 1
}

ensure_pgdg_apt_repo() {
  if [[ -f /etc/apt/sources.list.d/pgdg.list ]]; then
    return 0
  fi
  command -v apt-get >/dev/null 2>&1 || return 1
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y curl ca-certificates gnupg lsb-release >/dev/null 2>&1 || true
  install -d /usr/share/postgresql-common/pgdg
  if ! command -v curl >/dev/null 2>&1 || ! command -v gpg >/dev/null 2>&1; then
    return 1
  fi
  if ! curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | gpg --batch --yes --dearmor -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg 2>/dev/null; then
    return 1
  fi
  local codename
  codename=$(. /etc/os-release 2>/dev/null && printf '%s' "${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}")
  [[ -z "${codename}" ]] && return 1
  printf '%s\n' \
    "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg] https://apt.postgresql.org/pub/repos/apt ${codename}-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list
  apt-get update -y >/dev/null 2>&1 || return 1
}

apt_install() {
  local -a pkgs=("$@")
  local -a apt_bin
  [[ ${#pkgs[@]} -gt 0 ]] || return 1
  command -v apt-get >/dev/null 2>&1 || return 1
  export DEBIAN_FRONTEND=noninteractive
  apt_bin=(apt-get)
  if command -v timeout >/dev/null 2>&1; then
    apt_bin=(timeout 90 apt-get)
  fi
  if "${apt_bin[@]}" install -y "${pkgs[@]}"; then
    return 0
  fi
  "${apt_bin[@]}" update -y || true
  if "${apt_bin[@]}" install -y "${pkgs[@]}"; then
    return 0
  fi
  return 1
}

write_postgres_bin_dropin() {
  local bin_dir="${1:-}"
  local dropin_dir dropin_file
  [[ -n "${bin_dir}" ]] || return 0
  [[ -d "${bin_dir}" ]] || return 0
  [[ -d /etc/systemd/system ]] || return 0
  dropin_dir="/etc/systemd/system/hesabix-api.service.d"
  dropin_file="${dropin_dir}/20-postgres-bin-dir.conf"
  mkdir -p "${dropin_dir}" || return 0
  cat > "${dropin_file}" <<EOF || return 0
[Service]
Environment=HESABIX_POSTGRES_BIN_DIR=${bin_dir}
EOF
  log_ok "systemd drop-in: HESABIX_POSTGRES_BIN_DIR=${bin_dir}"
}

pg_major=""
if pg_major=$(detect_postgresql_major); then
  log_info "PostgreSQL major detected: ${pg_major}"
else
  pg_major=""
  log_warn "PostgreSQL major version not detected; will try postgresql-client metapackage."
fi

if [[ -n "${pg_major}" ]] && tools_ready_for_major "${pg_major}"; then
  write_postgres_bin_dropin "/usr/lib/postgresql/${pg_major}/bin" || true
  log_ok "postgresql-client-${pg_major} already present."
  finish 0
fi

if [[ -z "${pg_major}" ]]; then
  if found_major=$(any_versioned_pg_dump); then
    write_postgres_bin_dropin "/usr/lib/postgresql/${found_major}/bin" || true
    log_ok "Found pg_dump at /usr/lib/postgresql/${found_major}/bin (major unknown from server)."
    finish 0
  fi
fi

if ! command -v apt-get >/dev/null 2>&1; then
  log_warn "apt-get not available; cannot install postgresql-client."
  finish 1
fi

if [[ -n "${pg_major}" ]]; then
  log_info "Installing postgresql-client-${pg_major} (required for pg_dump/psql/pg_restore)..."
  if ! apt_install "postgresql-client-${pg_major}" postgresql-client; then
    log_warn "Ubuntu/Debian repos did not provide postgresql-client-${pg_major}; trying PGDG..."
    if ensure_pgdg_apt_repo; then
      apt_install "postgresql-client-${pg_major}" postgresql-client || true
    fi
  fi
else
  log_info "Installing postgresql-client metapackage..."
  apt_install postgresql-client || true
  if pg_major=$(detect_postgresql_major); then
    log_info "Retrying versioned client for PostgreSQL ${pg_major}..."
    apt_install "postgresql-client-${pg_major}" || true
  fi
fi

if [[ -z "${pg_major}" ]]; then
  pg_major=$(detect_postgresql_major || true)
fi
if [[ -z "${pg_major}" ]]; then
  pg_major=$(any_versioned_pg_dump || true)
fi

if [[ -n "${pg_major}" ]] && tools_ready_for_major "${pg_major}"; then
  write_postgres_bin_dropin "/usr/lib/postgresql/${pg_major}/bin" || true
  log_ok "Installed postgresql-client-${pg_major}."
  finish 0
fi

if found_major=$(any_versioned_pg_dump); then
  write_postgres_bin_dropin "/usr/lib/postgresql/${found_major}/bin" || true
  log_ok "pg_dump available at /usr/lib/postgresql/${found_major}/bin."
  finish 0
fi

log_warn "postgresql-client tools are still missing. Database backup/restore needs postgresql-client-<version>."
finish 1
