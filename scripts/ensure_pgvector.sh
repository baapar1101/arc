#!/usr/bin/env bash
# نصب idempotent بستهٔ postgresql-N-pgvector برای نسخهٔ major فعلی PostgreSQL.
# در صورت نبودن بسته در مخزن apt، بدون خطا خارج می‌شود (RAG با embedding_json ادامه می‌یابد).
set -euo pipefail

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
log_ok()   { echo "OK: $*"; }
log_warn() { echo "WARN: $*" >&2; }

detect_postgresql_major() {
  local v d
  if command -v pg_lsclusters >/dev/null 2>&1; then
    v=$(pg_lsclusters 2>/dev/null | awk 'NR>1 && $1 ~ /^[0-9]+$/ {print $1; exit}')
    if [[ -n "${v}" ]]; then
      echo "${v}"
      return 0
    fi
  fi
  if command -v psql >/dev/null 2>&1; then
    v=$(psql -h 127.0.0.1 -U postgres -tAc "SHOW server_version_num;" 2>/dev/null | tr -d '[:space:]')
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
  shopt -u nullglob
  return 1
}

ensure_pgvector_apt_package() {
  local pgv pkg
  if ! pgv=$(detect_postgresql_major); then
    log_warn "PostgreSQL major version not detected; skipping pgvector apt install."
    return 0
  fi
  pkg="postgresql-${pgv}-pgvector"
  if dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q "install ok installed"; then
    log_ok "pgvector already installed (${pkg})"
    return 0
  fi
  export DEBIAN_FRONTEND=noninteractive
  if ! apt-cache show "${pkg}" &>/dev/null; then
    log_warn "${pkg} not in apt repositories; semantic search uses JSON embeddings only."
    return 0
  fi
  log_info "Installing ${pkg}..."
  apt-get update -qq
  if apt-get install -y -qq "${pkg}"; then
    log_ok "Installed ${pkg}"
    return 0
  fi
  log_warn "Failed to install ${pkg} (non-fatal)."
  return 0
}

ensure_pgvector_apt_package
