#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# Hesabix - سیستم حسابداری جامع و متن باز
# ============================================================================
#
# Hesabix یک سیستم حسابداری کامل و مدرن است که شامل یک API قدرتمند 
# (FastAPI + PostgreSQL) و رابط کاربری زیبا (Flutter Web) می‌باشد.
#
# این نرم‌افزار تحت مجوز GNU General Public License v3.0 منتشر شده است.
# برای مشاهده کامل متن لایسنس به آدرس زیر مراجعه کنید:
# http://www.gnu.org/licenses/gpl-3.0.txt
#
# توسعه‌دهندگان: Hesabix Team
# وب‌سایت: https://hesabix.ir
# مخزن پروژه: https://source.hesabix.ir/hesabix/arc.git
# پشتیبانی: https://hesabix.ir/support
#
# ============================================================================
# Deployment Script
# ============================================================================
#
# این اسکریپت برای نصب و راه‌اندازی خودکار Hesabix طراحی شده است:
# - Clone از مخزن: https://source.hesabix.ir/hesabix/arc.git
# - دریافت دامنه API و UI از کاربر
# - نصب پیش‌نیازها، دیتابیس (PostgreSQL)، بک‌اند (FastAPI)، 
#   فرانت‌اند (Flutter Web)، Nginx و SSL
#
# Usage:
#   sudo bash deploy.sh
#   # or
#   API_DOMAIN=api.example.com UI_DOMAIN=app.example.com BRANCH=main DB_PASSWORD=secure_password sudo -E bash deploy.sh
#
# Notes:
# - Designed for Ubuntu 22.04+/Debian 12+
# - Idempotent: safe to re-run; will update and restart services
#
# ============================================================================

REPO_URL="https://source.hesabix.ir/hesabix/arc.git"
APP_ROOT="/opt/hesabix"
STATE_FILE="${APP_ROOT}/.deploy_state"
LOG_FILE="${APP_ROOT}/deploy.log"
CHECK_MARK=$'\xE2\x9C\x94'
CROSS_MARK=$'\xE2\x9D\x8C'
WARNING_MARK=$'\xE2\x9A\xA0'

# Initialize log file
init_log_file() {
  mkdir -p "${APP_ROOT}"
  local log_header="========================================
Hesabix Deployment Log
Started: $(date '+%Y-%m-%d %H:%M:%S')
========================================"
  echo "${log_header}" > "${LOG_FILE}"
  chmod 644 "${LOG_FILE}"
}

# Logging functions
log_info() {
  local message="$1"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[INFO] ${timestamp} - ${message}" >> "${LOG_FILE}"
  echo "${message}"
}

log_success() {
  local message="$1"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[SUCCESS] ${timestamp} - ${message}" >> "${LOG_FILE}"
  echo "$CHECK_MARK ${message}"
}

log_warning() {
  local message="$1"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[WARNING] ${timestamp} - ${message}" >> "${LOG_FILE}"
  echo "$WARNING_MARK ${message}"
}

log_error() {
  local message="$1"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[ERROR] ${timestamp} - ${message}" >> "${LOG_FILE}"
  echo "$CROSS_MARK ${message}" >&2
}

log_step() {
  local message="$1"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[STEP] ${timestamp} - ${message}" >> "${LOG_FILE}"
  echo ">> ${message}"
}

# Generate random password if not provided
generate_password() {
  openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Calculate optimal worker count based on CPU cores
calculate_optimal_workers() {
  local cpu_cores
  if command -v nproc >/dev/null 2>&1; then
    cpu_cores=$(nproc)
  elif [[ -f /proc/cpuinfo ]]; then
    cpu_cores=$(grep -c "^processor" /proc/cpuinfo)
  else
    cpu_cores=4  # Default fallback
  fi
  
  # Formula: (2 * CPU cores) + 1 for optimal performance
  echo $((2 * cpu_cores + 1))
}

# Calculate optimal database pool settings based on worker count
calculate_db_pool_settings() {
  local workers=$1
  local pool_size max_overflow
  
  # Base pool size per worker: 20 connections
  # Max overflow per worker: 30 connections
  # Total per worker: 50 connections
  # With safety margin: use 80% of calculated value
  pool_size=$((workers * 20))
  max_overflow=$((workers * 30))
  
  # Set reasonable limits (min 20, max 200 for pool_size)
  if [[ $pool_size -lt 20 ]]; then
    pool_size=20
  elif [[ $pool_size -gt 200 ]]; then
    pool_size=200
  fi
  
  # Set reasonable limits for max_overflow (min 30, max 300)
  if [[ $max_overflow -lt 30 ]]; then
    max_overflow=30
  elif [[ $max_overflow -gt 300 ]]; then
    max_overflow=300
  fi
  
  echo "${pool_size}:${max_overflow}"
}

# Validate domain format
validate_domain() {
  local domain="$1"
  if [[ ! "${domain}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    echo "$CROSS_MARK Invalid domain format: ${domain}"
    return 1
  fi
  return 0
}

# Check if service is running
check_service() {
  local service="$1"
  if systemctl is-active --quiet "${service}"; then
    return 0
  else
    return 1
  fi
}

# Wait for PostgreSQL to be ready
wait_for_db() {
  local max_attempts=30
  local attempt=0
  log_info "Waiting for PostgreSQL to be ready..."
  while [ $attempt -lt $max_attempts ]; do
    if sudo -u postgres psql -c "SELECT 1" >/dev/null 2>&1; then
      log_success "PostgreSQL is ready"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 2
  done
  log_error "Database not ready after $max_attempts attempts"
  return 1
}

# Check disk space (requires at least 2GB free)
check_disk_space() {
  local available_space
  available_space=$(df / | tail -1 | awk '{print $4}')
  if [ "$available_space" -lt 2097152 ]; then
    log_warning "Low disk space (less than 2GB). This may cause issues."
    read -rp "Continue anyway? (y/N): " continue_anyway
    if [[ ! "${continue_anyway}" =~ ^[Yy]$ ]]; then
      log_error "Installation aborted by user due to low disk space"
      exit 1
    fi
    log_info "User chose to continue despite low disk space"
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$CROSS_MARK Required tool not found: $1"
    exit 1
  fi
}

# Check if OS is Debian or Ubuntu
check_os_compatibility() {
  if [[ ! -f /etc/os-release ]]; then
    log_error "Cannot detect operating system. /etc/os-release not found."
    log_error "This script supports only Debian and Ubuntu."
    exit 1
  fi
  
  # Source os-release to get distribution info
  # shellcheck disable=SC1091
  source /etc/os-release
  
  local os_id="${ID:-}"
  local os_id_like="${ID_LIKE:-}"
  
  # Check if it's Ubuntu or Debian
  if [[ "${os_id}" == "ubuntu" ]] || [[ "${os_id}" == "debian" ]]; then
    log_success "Detected compatible OS: ${PRETTY_NAME:-${os_id}}"
    return 0
  fi
  
  # Check ID_LIKE for compatibility (e.g., Ubuntu is based on Debian)
  if [[ "${os_id_like}" == *"debian"* ]] || [[ "${os_id_like}" == *"ubuntu"* ]]; then
    log_success "Detected compatible OS: ${PRETTY_NAME:-${os_id}} (based on Debian/Ubuntu)"
    return 0
  fi
  
  log_error "Unsupported operating system detected: ${PRETTY_NAME:-${os_id}}"
  log_error "This script supports only Debian and Ubuntu distributions."
  log_error "Detected OS ID: ${os_id}"
  if [[ -n "${os_id_like}" ]]; then
    log_error "OS ID_LIKE: ${os_id_like}"
  fi
  exit 1
}

# State tracking functions for resume capability
mark_step_completed() {
  local step="$1"
  mkdir -p "${APP_ROOT}"
  echo "${step}" >> "${STATE_FILE}"
}

check_step_completed() {
  local step="$1"
  if [[ -f "${STATE_FILE}" ]] && grep -q "^${step}$" "${STATE_FILE}"; then
    return 0
  fi
  return 1
}

clear_deployment_state() {
  if [[ -f "${STATE_FILE}" ]]; then
    rm -f "${STATE_FILE}"
  fi
}

reset_deployment_state() {
  : "${RESET_STATE:=}"
  if [[ -z "${RESET_STATE}" ]] && [[ -f "${STATE_FILE}" ]]; then
    echo
    read -rp "Previous deployment state found. Reset and start from beginning? (y/N): " RESET_STATE
    RESET_STATE=${RESET_STATE:-N}
  fi
  
  if [[ "${RESET_STATE}" =~ ^[Yy]$ ]]; then
    clear_deployment_state
    echo "$CHECK_MARK Deployment state reset. Starting from beginning."
  fi
}

show_license_info() {
  cat <<LICENSE

╔═══════════════════════════════════════════════════════════════════════╗
║                  Hesabix - Comprehensive Accounting System            ║
║                    Open Source Software under GPL v3                  ║
╚═══════════════════════════════════════════════════════════════════════╝

📋 About the Software:
   Hesabix is a complete and modern accounting system that includes:
   • Powerful API (FastAPI + PostgreSQL)
   • Beautiful User Interface (Flutter Web)
   • Open source and free

👨‍💻 Developers:
   Hesabix Team
   Website: https://hesabix.ir
   Support: https://hesabix.ir/support

📦 Project Repository:
   https://source.hesabix.ir/hesabix/arc.git

📄 License:
   This software is distributed under the GNU General Public License v3.0 (GPL-3.0).

   Full license text: http://www.gnu.org/licenses/gpl-3.0.txt

   Summary of Rights:
   ✓ You are free to run the software
   ✓ You are free to study and modify the software
   ✓ You are free to distribute the software
   ✓ You are free to distribute improved versions

   Condition: Any distribution or modified version must be under the same GPL v3 
              license and source code must be made available.

   ⚠️  This software is provided WITHOUT ANY WARRANTY.

╔═══════════════════════════════════════════════════════════════════════╗
║                     GNU GENERAL PUBLIC LICENSE                        ║
║                           Version 3, 29 June 2007                     ║
║                                                                       ║
║  Copyright (C) 2024 Hesabix Team <https://hesabix.ir>                ║
║                                                                       ║
║  This program is free software: you can redistribute it and/or       ║
║  modify it under the terms of the GNU General Public License as      ║
║  published by the Free Software Foundation, either version 3 of the  ║
║  License, or (at your option) any later version.                     ║
║                                                                       ║
║  This program is distributed in the hope that it will be useful,     ║
║  but WITHOUT ANY WARRANTY; without even the implied warranty of      ║
║  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU    ║
║  General Public License for more details.                            ║
║                                                                       ║
║  You should have received a copy of the GNU General Public License   ║
║  along with this program. If not, see                                ║
║  <http://www.gnu.org/licenses/>.                                     ║
╚═══════════════════════════════════════════════════════════════════════╝

LICENSE
}

accept_license() {
  : "${ACCEPT_LICENSE:=}"
  
  if [[ -z "${ACCEPT_LICENSE}" ]]; then
    echo
    echo "⚠️  To continue installation, you must agree to the GNU GPL v3 license terms."
    echo
    read -rp "Do you agree to the terms of the GNU General Public License v3.0? (yes/no): " ACCEPT_LICENSE
  fi
  
  case "${ACCEPT_LICENSE}" in
    [Yy][Ee][Ss]|y|Y)
      echo "$CHECK_MARK License agreement accepted (GNU GPL v3.0)."
      return 0
      ;;
    *)
      echo "$CROSS_MARK You must agree to the license terms to continue installation."
      echo
      echo "To view the full license text, visit:"
      echo "  http://www.gnu.org/licenses/gpl-3.0.txt"
      echo
      exit 1
      ;;
  esac
}

prompt_vars() {
  : "${API_DOMAIN:=}"
  : "${UI_DOMAIN:=}"
  : "${BRANCH:=main}"
  : "${DB_PASSWORD:=}"
  : "${FLUTTER_VERSION:=3.24.0}"
  
  # Calculate optimal worker count based on CPU cores if not provided
  if [[ -z "${UVICORN_WORKERS}" ]]; then
    UVICORN_WORKERS=$(calculate_optimal_workers)
    log_info "Auto-calculated optimal worker count: ${UVICORN_WORKERS} (based on CPU cores)"
  fi
  
  # Calculate optimal database pool settings based on worker count
  local pool_settings
  pool_settings=$(calculate_db_pool_settings "${UVICORN_WORKERS}")
  DB_POOL_SIZE=$(echo "${pool_settings}" | cut -d: -f1)
  DB_MAX_OVERFLOW=$(echo "${pool_settings}" | cut -d: -f2)
  
  log_info "Auto-calculated database pool settings: pool_size=${DB_POOL_SIZE}, max_overflow=${DB_MAX_OVERFLOW}"
  
  if [[ -z "${API_DOMAIN}" ]]; then
    read -rp "API domain (e.g., api.example.com): " API_DOMAIN
  fi
  if ! validate_domain "${API_DOMAIN}"; then
    exit 1
  fi
  
  if [[ -z "${UI_DOMAIN}" ]]; then
    read -rp "Frontend domain (e.g., app.example.com): " UI_DOMAIN
  fi
  if ! validate_domain "${UI_DOMAIN}"; then
    exit 1
  fi
  
  if [[ -z "${BRANCH}" ]]; then
    read -rp "Branch name (default: main): " BRANCH
    BRANCH=${BRANCH:-main}
  fi
  
  # Generate or prompt for DB password
  if [[ -z "${DB_PASSWORD}" ]]; then
    if [[ -f "${APP_ROOT}/.db_password" ]]; then
      DB_PASSWORD=$(cat "${APP_ROOT}/.db_password")
      echo "$CHECK_MARK Using existing password from previous run"
    else
      read -rsp "Database password (empty for auto-generate): " DB_PASSWORD
      echo
      if [[ -z "${DB_PASSWORD}" ]]; then
        DB_PASSWORD=$(generate_password)
        echo "$CHECK_MARK Password auto-generated"
      fi
      # Save password for future runs
      mkdir -p "${APP_ROOT}"
      echo -n "${DB_PASSWORD}" > "${APP_ROOT}/.db_password"
      chmod 600 "${APP_ROOT}/.db_password"
    fi
  else
    # Save provided password
    mkdir -p "${APP_ROOT}"
    echo -n "${DB_PASSWORD}" > "${APP_ROOT}/.db_password"
    chmod 600 "${APP_ROOT}/.db_password"
  fi
  
  # Prompt for pgAdmin4 installation (optional)
  : "${INSTALL_PGADMIN4:=}"
  : "${PGADMIN4_DOMAIN:=}"
  : "${PGADMIN4_EMAIL:=}"
  : "${PGADMIN4_PASSWORD:=}"
  
  if [[ -z "${INSTALL_PGADMIN4}" ]]; then
    echo
    read -rp "Install pgAdmin4 (PostgreSQL web admin)? (y/N): " INSTALL_PGADMIN4
    INSTALL_PGADMIN4=${INSTALL_PGADMIN4:-N}
  fi
  
  if [[ "${INSTALL_PGADMIN4}" =~ ^[Yy]$ ]]; then
    if [[ -z "${PGADMIN4_DOMAIN}" ]]; then
      read -rp "pgAdmin4 domain (e.g., pgadmin.example.com): " PGADMIN4_DOMAIN
    fi
    if ! validate_domain "${PGADMIN4_DOMAIN}"; then
      echo "$WARNING_MARK Invalid pgAdmin4 domain. Skipping pgAdmin4 installation."
      INSTALL_PGADMIN4="N"
    else
      if [[ -z "${PGADMIN4_EMAIL}" ]]; then
        read -rp "pgAdmin4 admin email: " PGADMIN4_EMAIL
      fi
      if [[ -z "${PGADMIN4_PASSWORD}" ]]; then
        read -rsp "pgAdmin4 admin password: " PGADMIN4_PASSWORD
        echo
      fi
    fi
  fi
  
  export API_DOMAIN UI_DOMAIN BRANCH DB_PASSWORD UVICORN_WORKERS FLUTTER_VERSION INSTALL_PGADMIN4 PGADMIN4_DOMAIN PGADMIN4_EMAIL PGADMIN4_PASSWORD DB_POOL_SIZE DB_MAX_OVERFLOW
}

# Show configuration summary and ask for confirmation
show_config_summary() {
  echo
  echo "=========================================="
  echo "  Configuration Summary"
  echo "=========================================="
  echo
  echo "Domains:"
  echo "  • API Domain:     ${API_DOMAIN}"
  echo "  • UI Domain:      ${UI_DOMAIN}"
  echo
  echo "Repository Settings:"
  echo "  • Branch:         ${BRANCH}"
  echo "  • Repository:     ${REPO_URL}"
  echo
  echo "Database Settings:"
  echo "  • Database Name:  hesabix"
  echo "  • Database User:  hesabix"
  echo "  • Database Host:  127.0.0.1:5432"
  if [[ -f "${APP_ROOT}/.db_password" ]]; then
    echo "  • Password:       (Using existing password)"
  else
    echo "  • Password:       (Auto-generated)"
  fi
  echo
  echo "Server Settings:"
  echo "  • Uvicorn Workers: ${UVICORN_WORKERS} (auto-calculated based on CPU cores)"
  echo "  • Flutter Version: ${FLUTTER_VERSION}"
  echo "  • DB Pool Size: ${DB_POOL_SIZE} (auto-calculated)"
  echo "  • DB Max Overflow: ${DB_MAX_OVERFLOW} (auto-calculated)"
  echo
  if [[ "${INSTALL_PGADMIN4}" =~ ^[Yy]$ ]]; then
    echo "pgAdmin4:"
    echo "  • Domain:         ${PGADMIN4_DOMAIN}"
    echo "  • Admin Email:    ${PGADMIN4_EMAIL}"
    echo
  else
    echo "pgAdmin4:          Not installed"
    echo
  fi
  echo "Installation Paths:"
  echo "  • Application:    ${APP_ROOT}/app"
  echo "  • Frontend:       /var/www/${UI_DOMAIN}"
  echo "  • Log File:       ${LOG_FILE}"
  echo
  echo "=========================================="
  echo
}

# Ask user for final confirmation before starting installation
confirm_installation() {
  : "${CONFIRM_INSTALL:=}"
  
  if [[ -z "${CONFIRM_INSTALL}" ]]; then
    echo "⚠️  Do you want to start installation with these settings?"
    echo
    read -rp "Confirm installation (yes/no): " CONFIRM_INSTALL
  fi
  
  case "${CONFIRM_INSTALL}" in
    [Yy][Ee][Ss]|yes|y|Y)
      log_info "User confirmed installation. Starting deployment..."
      return 0
      ;;
    *)
      log_info "Installation cancelled by user."
      echo
      echo "$CROSS_MARK Installation cancelled."
      echo "To start again, please run the script again."
      echo
      exit 0
      ;;
  esac
}

install_prereqs() {
  echo ">> Installing prerequisites..."
  export DEBIAN_FRONTEND=noninteractive
  
  # Update package list
  apt-get update -y
  
  # Install prerequisites (apt-get install is idempotent - will skip if already installed)
  echo "Installing: git, curl, unzip, xz-utils, ca-certificates, python3.11, python3.11-venv, python3-pip, build-essential, nginx, postgresql, postgresql-contrib..."
  apt-get install -y git curl unzip xz-utils ca-certificates \
    python3.11 python3.11-venv python3-pip build-essential \
    nginx postgresql postgresql-contrib
  
  echo "$CHECK_MARK Prerequisites installed (or already present)."
}

clone_repo() {
  echo ">> Cloning/updating repository..."
  mkdir -p "${APP_ROOT}"
  cd "${APP_ROOT}"
  
  if [[ ! -d "${APP_ROOT}/app/.git" ]]; then
    echo "Cloning repository..."
    if ! git clone -b "${BRANCH}" "${REPO_URL}" app; then
      echo "$CROSS_MARK Error cloning repository"
      exit 1
    fi
    cd app
  else
    echo "Updating existing repository..."
    cd app
    
    # Save current branch
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    
    # Fetch all branches
    if ! git fetch --all --prune; then
      echo "$WARNING_MARK Error fetching. Continuing with current state..."
    fi
    
    # Checkout target branch
    if ! git checkout "${BRANCH}" 2>/dev/null; then
      echo "$WARNING_MARK Branch ${BRANCH} not found. Using current branch: ${current_branch}"
      BRANCH="${current_branch}"
    fi
    
    # Try to pull, but don't fail if it's not a fast-forward
    if ! git pull --ff-only 2>/dev/null; then
      echo "$WARNING_MARK Pull failed (may need merge). Using current state..."
      git reset --hard "origin/${BRANCH}" 2>/dev/null || true
    fi
  fi
  
  # Verify we're on the right branch
  local actual_branch
  actual_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  echo "$CHECK_MARK Repository ready at ${APP_ROOT}/app (branch: ${actual_branch})"
}

setup_db() {
  log_step "Configuring database (PostgreSQL)..."
  
  # Start and enable PostgreSQL service
  if systemctl list-unit-files | grep -q postgresql.service; then
    log_info "Starting PostgreSQL service..."
    systemctl enable --now postgresql || true
  else
    log_error "PostgreSQL service not found. Please install PostgreSQL."
    exit 1
  fi
  
  # Wait for database to be ready
  if ! wait_for_db; then
    log_error "Database not ready"
    exit 1
  fi
  
  # Configure PostgreSQL to allow local connections (if needed)
  local pg_version
  pg_version=$(sudo -u postgres psql -tAc "SELECT version();" | grep -oE '[0-9]+' | head -1)
  local pg_hba="/etc/postgresql/${pg_version}/main/pg_hba.conf"
  
  # Allow password authentication for localhost connections
  # Use scram-sha-256 (more secure than md5) if PostgreSQL version supports it
  # For PostgreSQL 10+, scram-sha-256 is the default and recommended method
  if [[ -f "${pg_hba}" ]] && ! grep -q "host.*hesabix.*127.0.0.1/32" "${pg_hba}"; then
    # Try scram-sha-256 first (PostgreSQL 10+), fallback to md5 for older versions
    if [[ "${pg_version}" -ge 10 ]]; then
      echo "host    hesabix    hesabix    127.0.0.1/32    scram-sha-256" >> "${pg_hba}"
    else
      echo "host    hesabix    hesabix    127.0.0.1/32    md5" >> "${pg_hba}"
    fi
    systemctl reload postgresql || true
  fi
  
  # Create database and user
  sudo -u postgres psql <<SQL
-- Create user if not exists
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'hesabix') THEN
    CREATE USER hesabix WITH PASSWORD '${DB_PASSWORD}';
  ELSE
    ALTER USER hesabix WITH PASSWORD '${DB_PASSWORD}';
  END IF;
END
\$\$;
SQL

  # Create database separately to avoid issues with conditional creation
  if ! sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = 'hesabix'" | grep -q 1; then
    sudo -u postgres createdb -O hesabix -E UTF8 -T template0 hesabix
  fi
  
  # Grant privileges
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE hesabix TO hesabix;"
  
  # Verify connection
  if PGPASSWORD="${DB_PASSWORD}" psql -U hesabix -h 127.0.0.1 -d hesabix -c "SELECT 1" >/dev/null 2>&1; then
    log_success "Database and user created, connection verified."
  else
    log_warning "Connection test failed, but database may still be accessible. Continuing..."
  fi
}

deploy_backend() {
  log_step "Deploying backend..."
  local api_dir="${APP_ROOT}/app/hesabixAPI"
  
  if [[ ! -d "${api_dir}" ]]; then
    log_error "Backend path not found: ${api_dir}"
    exit 1
  fi
  
  cd "${api_dir}"

  # Python venv + install
  if [[ ! -d ".venv" ]]; then
    python3.11 -m venv .venv
  fi
  # shellcheck disable=SC1091
  source .venv/bin/activate
  pip install --upgrade pip setuptools wheel
  pip install -e .

  # Check if .env.example exists and use it as base
  local env_file=".env"
  if [[ -f "env.example" ]]; then
    cp env.example "${env_file}"
    # Update production values
    sed -i "s/^ENVIRONMENT=.*/ENVIRONMENT=production/" "${env_file}"
    sed -i "s/^DEBUG=.*/DEBUG=false/" "${env_file}"
    sed -i "s/^DB_USER=.*/DB_USER=hesabix/" "${env_file}"
    sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${DB_PASSWORD}/" "${env_file}"
    sed -i "s/^DB_HOST=.*/DB_HOST=127.0.0.1/" "${env_file}"
    sed -i "s/^DB_PORT=.*/DB_PORT=5432/" "${env_file}"
    sed -i "s/^DB_NAME=.*/DB_NAME=hesabix/" "${env_file}"
    sed -i "s/^LOG_LEVEL=.*/LOG_LEVEL=INFO/" "${env_file}"
    
    # Update database connection pool settings for optimal performance
    if ! grep -q "^DB_POOL_SIZE=" "${env_file}"; then
      echo "DB_POOL_SIZE=${DB_POOL_SIZE}" >> "${env_file}"
    else
      sed -i "s/^DB_POOL_SIZE=.*/DB_POOL_SIZE=${DB_POOL_SIZE}/" "${env_file}"
    fi
    
    if ! grep -q "^DB_MAX_OVERFLOW=" "${env_file}"; then
      echo "DB_MAX_OVERFLOW=${DB_MAX_OVERFLOW}" >> "${env_file}"
    else
      sed -i "s/^DB_MAX_OVERFLOW=.*/DB_MAX_OVERFLOW=${DB_MAX_OVERFLOW}/" "${env_file}"
    fi
    
    # Set optimal pool timeout and recycle for persistent connections
    if ! grep -q "^DB_POOL_TIMEOUT=" "${env_file}"; then
      echo "DB_POOL_TIMEOUT=30" >> "${env_file}"
    else
      sed -i "s/^DB_POOL_TIMEOUT=.*/DB_POOL_TIMEOUT=30/" "${env_file}"
    fi
    
    if ! grep -q "^DB_POOL_RECYCLE=" "${env_file}"; then
      echo "DB_POOL_RECYCLE=300" >> "${env_file}"
    else
      sed -i "s/^DB_POOL_RECYCLE=.*/DB_POOL_RECYCLE=300/" "${env_file}"
    fi
    
    # Add CORS if not exists (public API - allow all origins)
    if ! grep -q "CORS_ALLOWED_ORIGINS" "${env_file}"; then
      echo "CORS_ALLOWED_ORIGINS=[\"*\"]" >> "${env_file}"
    else
      sed -i "s|^CORS_ALLOWED_ORIGINS=.*|CORS_ALLOWED_ORIGINS=[\"*\"]|" "${env_file}"
    fi
  else
    # Fallback: create minimal .env with optimized settings
    cat > "${env_file}" <<ENV
ENVIRONMENT=production
DEBUG=false
DB_USER=hesabix
DB_PASSWORD=${DB_PASSWORD}
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=hesabix
LOG_LEVEL=INFO
CORS_ALLOWED_ORIGINS=["*"]
# Database Connection Pool Settings (optimized for performance and persistent connections)
DB_POOL_SIZE=${DB_POOL_SIZE}
DB_MAX_OVERFLOW=${DB_MAX_OVERFLOW}
DB_POOL_TIMEOUT=30
DB_POOL_RECYCLE=300
ENV
  fi
  
  log_info "Database connection pool configured: pool_size=${DB_POOL_SIZE}, max_overflow=${DB_MAX_OVERFLOW}, timeout=30s, recycle=300s"
  
  # Secure .env file permissions (contains sensitive data like DB_PASSWORD)
  chmod 600 "${env_file}"
  chown www-data:www-data "${env_file}"

  # Verify database connection before migrations
  echo "Verifying database connection..."
  if ! python3 -c "
import sys
sys.path.insert(0, '.')
from app.core.settings import get_settings
settings = get_settings()
from sqlalchemy import create_engine, text
engine = create_engine(settings.postgresql_dsn)
with engine.connect() as conn:
    conn.execute(text('SELECT 1'))
print('Connection successful')
" 2>/dev/null; then
    echo "$WARNING_MARK Database connection failed. Migrations may fail."
  fi

  # Alembic migrations
  echo "Running migrations..."
  if ! alembic upgrade head; then
    echo "$CROSS_MARK Error running migrations"
    exit 1
  fi

  # Check if www-data user exists
  if ! id -u www-data >/dev/null 2>&1; then
    echo "$WARNING_MARK User www-data not found. Creating user..."
    useradd -r -s /bin/false www-data || true
  fi

  # Set ownership
  chown -R www-data:www-data "${api_dir}"

  # systemd service
  cat > /etc/systemd/system/hesabix-api.service <<UNIT
[Unit]
Description=Hesabix API (FastAPI/Uvicorn)
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=notify
User=www-data
Group=www-data
WorkingDirectory=${api_dir}
Environment=PATH=${api_dir}/.venv/bin
Environment=PYTHONUNBUFFERED=1
ExecStart=${api_dir}/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers ${UVICORN_WORKERS}
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  
  # Stop service if running to avoid conflicts
  if check_service hesabix-api; then
    systemctl stop hesabix-api
  fi
  
  systemctl enable hesabix-api
  systemctl start hesabix-api
  
  # Wait a bit and check if service started successfully
  sleep 3
  if check_service hesabix-api; then
    log_success "Backend started (service: hesabix-api)."
  else
    log_error "Backend failed to start. Check logs: journalctl -u hesabix-api"
    exit 1
  fi

  # RQ Worker service for background jobs
  cat > /etc/systemd/system/hesabix-rq-worker.service <<UNIT
[Unit]
Description=Hesabix RQ Worker (Background Jobs)
After=network.target redis.service postgresql.service
Wants=redis.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=${api_dir}
Environment=PATH=${api_dir}/.venv/bin
Environment=PYTHONUNBUFFERED=1
ExecStart=${api_dir}/.venv/bin/python ${api_dir}/rq_worker.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  
  # Stop service if running to avoid conflicts
  if check_service hesabix-rq-worker; then
    systemctl stop hesabix-rq-worker
  fi
  
  systemctl enable hesabix-rq-worker
  
  # Start RQ worker only if Redis is available
  if systemctl is-active --quiet redis || systemctl is-enabled --quiet redis 2>/dev/null; then
    systemctl start hesabix-rq-worker
    sleep 2
    if check_service hesabix-rq-worker; then
      log_success "RQ Worker started (service: hesabix-rq-worker)."
    else
      log_warning "RQ Worker failed to start. Check logs: journalctl -u hesabix-rq-worker"
      log_warning "Background jobs will not work until Redis is configured and RQ worker is running."
    fi
  else
    log_warning "Redis service not found. RQ Worker not started."
    log_warning "To enable background jobs, install and configure Redis, then run: systemctl start hesabix-rq-worker"
  fi

  # Notification Moderation Worker service
  cat > /etc/systemd/system/hesabix-notification-moderation.service <<UNIT
[Unit]
Description=Hesabix Notification Moderation Worker
Documentation=https://hesabix.com/docs/notification-moderation
After=network.target postgresql.service redis.service
Requires=postgresql.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=${api_dir}
Environment=PATH=${api_dir}/.venv/bin
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONPATH=${api_dir}
ExecStart=${api_dir}/.venv/bin/python -m app.workers.notification_moderation_worker
Restart=always
RestartSec=10
StartLimitInterval=5min
StartLimitBurst=3
StandardOutput=journal
StandardError=journal
SyslogIdentifier=hesabix-notification-moderation

# Security
NoNewPrivileges=true
PrivateTmp=true

# Resource limits
MemoryLimit=512M
CPUQuota=50%

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  
  # Stop service if running to avoid conflicts
  if check_service hesabix-notification-moderation; then
    systemctl stop hesabix-notification-moderation
  fi
  
  systemctl enable hesabix-notification-moderation
  
  # Start notification moderation worker
  systemctl start hesabix-notification-moderation
  sleep 2
  if check_service hesabix-notification-moderation; then
    log_success "Notification Moderation Worker started (service: hesabix-notification-moderation)."
  else
    log_warning "Notification Moderation Worker failed to start. Check logs: journalctl -u hesabix-notification-moderation"
  fi
}

install_flutter_and_build_frontend() {
  log_step "Building Flutter frontend..."
  
  local app_dir="${APP_ROOT}/app"
  if [[ ! -d "${app_dir}" ]]; then
    log_error "App directory not found: ${app_dir}"
    exit 1
  fi
  
  local build_script="${app_dir}/build_web.sh"
  if [[ ! -f "${build_script}" ]]; then
    log_error "build_web.sh not found: ${build_script}"
    exit 1
  fi
  
  # Make build script executable
  chmod +x "${build_script}"
  
  # Build API URL (use HTTPS for API domain)
  local api_url="https://${API_DOMAIN}"
  
  echo "Building Flutter web with:"
  echo "  Mode: release"
  echo "  API URL: ${api_url}"
  echo "  Output: /var/www/${UI_DOMAIN}"
  echo
  echo "$CHECK_MARK Flutter mirror auto-detection enabled:"
  echo "  The build script will automatically detect and use available mirrors"
  echo "  (Chinese mirrors → Official → Other mirrors) if Google services are blocked."
  echo "  This ensures Flutter packages and SDK downloads work even with sanctions."
  
  # Build using build_web.sh script
  cd "${app_dir}"
  log_info "Building Flutter web application..."
  if ! bash build_web.sh \
    --mode release \
    --api-base-url "${api_url}" \
    --clean \
    --install-deps; then
    log_error "Error building frontend"
    exit 1
  fi
  
  # Find the build output directory
  local ui_project_dir="${app_dir}/hesabixUI/hesabix_ui"
  local build_output="${ui_project_dir}/build/web"
  
  log_info "Checking build output..."
  log_info "  Build directory: ${build_output}"
  
  if [[ ! -d "${build_output}" ]]; then
    log_error "Build output directory not found: ${build_output}"
    exit 1
  fi
  
  # Verify that index.html exists
  if [[ ! -f "${build_output}/index.html" ]]; then
    log_error "index.html not found in build output. Build may have failed."
    exit 1
  fi
  
  log_success "Build output verified (${build_output})"

  # Deploy to web directory
  log_info "Deploying to web directory..."
  log_info "  Source: ${build_output}/"
  log_info "  Destination: /var/www/${UI_DOMAIN}/"
  
  mkdir -p "/var/www/${UI_DOMAIN}"
  rsync -a --delete "${build_output}/" "/var/www/${UI_DOMAIN}/"
  
  # Verify deployment
  if [[ ! -f "/var/www/${UI_DOMAIN}/index.html" ]]; then
    log_error "Deployment failed: index.html not found in destination"
    exit 1
  fi
  
  chown -R www-data:www-data "/var/www/${UI_DOMAIN}"
  log_success "Frontend built and deployed to /var/www/${UI_DOMAIN}."
}

configure_nginx_api() {
  echo ">> Configuring Nginx for API..."
  
  # Check if nginx is installed
  if ! command -v nginx >/dev/null 2>&1; then
    echo "$CROSS_MARK Nginx is not installed"
    exit 1
  fi
  
  # Remove default site if exists
  if [[ -L /etc/nginx/sites-enabled/default ]]; then
    rm -f /etc/nginx/sites-enabled/default
  fi
  
  # Create rate limiting zone configuration (included in http context)
  if [[ -d /etc/nginx/conf.d ]]; then
    cat > /etc/nginx/conf.d/rate-limit-api.conf <<RATELIMIT
# Rate limiting zone for API
limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=10r/s;
RATELIMIT
  fi
  
  # Create API-specific configuration
  cat > /etc/nginx/sites-available/hesabix-api.conf <<NGINX
# Backend API
server {
  listen 80;
  server_name ${API_DOMAIN};

  # Security headers
  add_header X-Frame-Options "DENY" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-XSS-Protection "1; mode=block" always;
  add_header Referrer-Policy "strict-origin-when-cross-origin" always;

  location / {
    return 404;
  }

  location /api/ {
    limit_req zone=api_limit burst=20 nodelay;
    proxy_pass http://127.0.0.1:8000/api/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 300;
    proxy_connect_timeout 60;
    proxy_send_timeout 300;
    client_max_body_size 20m;
    
    # WebSocket support (if needed in future)
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }
}
NGINX

  ln -sf /etc/nginx/sites-available/hesabix-api.conf /etc/nginx/sites-enabled/hesabix-api.conf
  
  # Test nginx configuration
  if ! nginx -t; then
    echo "$CROSS_MARK Error in Nginx configuration"
    exit 1
  fi
  
  # Reload nginx
  if systemctl reload nginx; then
    echo "$CHECK_MARK Nginx configured and reloaded for API."
  else
    echo "$CROSS_MARK Error reloading Nginx"
    exit 1
  fi
}

configure_nginx_ui() {
  echo ">> Configuring Nginx for UI..."
  
  # Check if nginx is installed
  if ! command -v nginx >/dev/null 2>&1; then
    echo "$CROSS_MARK Nginx is not installed"
    exit 1
  fi
  
  # Create UI-specific configuration
  cat > /etc/nginx/sites-available/hesabix-ui.conf <<NGINX
# Frontend (Flutter Web)
server {
  listen 80;
  server_name ${UI_DOMAIN};

  root /var/www/${UI_DOMAIN};
  index index.html;

  # Security headers
  add_header X-Frame-Options "SAMEORIGIN" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-XSS-Protection "1; mode=block" always;
  add_header Referrer-Policy "strict-origin-when-cross-origin" always;

  location / {
    try_files \$uri \$uri/ /index.html;
  }

  # Cache static assets
  location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
  }

  gzip on;
  gzip_vary on;
  gzip_min_length 1024;
  gzip_types text/plain text/css application/javascript application/json image/svg+xml text/xml application/xml application/xml+rss;
  gzip_comp_level 6;
}
NGINX

  ln -sf /etc/nginx/sites-available/hesabix-ui.conf /etc/nginx/sites-enabled/hesabix-ui.conf
  
  # Test nginx configuration
  if ! nginx -t; then
    echo "$CROSS_MARK Error in Nginx configuration"
    exit 1
  fi
  
  # Reload nginx
  if systemctl reload nginx; then
    echo "$CHECK_MARK Nginx configured and reloaded for UI."
  else
    echo "$CROSS_MARK Error reloading Nginx"
    exit 1
  fi
}

configure_api_ssl() {
  echo ">> Configuring SSL for API domain..."
  
  : "${ENABLE_API_SSL:=}"
  if [[ -z "${ENABLE_API_SSL}" ]]; then
    echo
    read -rp "Enable SSL/TLS for API domain (${API_DOMAIN}) with Let's Encrypt? (y/N): " ENABLE_API_SSL
    ENABLE_API_SSL=${ENABLE_API_SSL:-N}
  fi
  
  if [[ "${ENABLE_API_SSL}" =~ ^[Yy]$ ]]; then
    echo ">> Installing and configuring TLS for API..."
    
    # Check if certbot is already installed
    if ! command -v certbot >/dev/null 2>&1; then
      apt-get install -y certbot python3-certbot-nginx
    fi
    
    # Get email for certbot
    : "${CERTBOT_EMAIL:=admin@${API_DOMAIN}}"
    if [[ -z "${CERTBOT_EMAIL}" ]] || [[ "${CERTBOT_EMAIL}" == "admin@${API_DOMAIN}" ]]; then
      read -rp "Email for SSL certificate (default: admin@${API_DOMAIN}): " input_email
      CERTBOT_EMAIL=${input_email:-admin@${API_DOMAIN}}
    fi
    
    # Validate email format (basic)
    if [[ ! "${CERTBOT_EMAIL}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
      echo "$WARNING_MARK Invalid email format. Using default: admin@${API_DOMAIN}"
      CERTBOT_EMAIL="admin@${API_DOMAIN}"
    fi
    
    # Configure SSL for API domain only
    if certbot --nginx -d "${API_DOMAIN}" --redirect --non-interactive --agree-tos -m "${CERTBOT_EMAIL}" 2>&1; then
      echo "$CHECK_MARK SSL/TLS enabled for API domain."
      # Setup auto-renewal
      systemctl enable certbot.timer
      systemctl start certbot.timer
      echo "$CHECK_MARK SSL certificate auto-renewal enabled."
    else
      echo "$WARNING_MARK Error issuing SSL certificate for API domain. You can run manually later:"
      echo "  certbot --nginx -d ${API_DOMAIN}"
    fi
  else
    echo "SSL/TLS skipped for API domain; you can run certbot later:"
    echo "  certbot --nginx -d ${API_DOMAIN}"
  fi
}

configure_ui_ssl() {
  echo ">> Configuring SSL for UI domain..."
  
  : "${ENABLE_UI_SSL:=}"
  if [[ -z "${ENABLE_UI_SSL}" ]]; then
    echo
    read -rp "Enable SSL/TLS for UI domain (${UI_DOMAIN}) with Let's Encrypt? (y/N): " ENABLE_UI_SSL
    ENABLE_UI_SSL=${ENABLE_UI_SSL:-N}
  fi
  
  if [[ "${ENABLE_UI_SSL}" =~ ^[Yy]$ ]]; then
    echo ">> Installing and configuring TLS for UI..."
    
    # Check if certbot is already installed
    if ! command -v certbot >/dev/null 2>&1; then
      apt-get install -y certbot python3-certbot-nginx
    fi
    
    # Get email for certbot (use same as API if already set)
    : "${CERTBOT_EMAIL:=admin@${UI_DOMAIN}}"
    if [[ -z "${CERTBOT_EMAIL}" ]] || [[ "${CERTBOT_EMAIL}" == "admin@${UI_DOMAIN}" ]]; then
      read -rp "Email for SSL certificate (default: admin@${UI_DOMAIN}): " input_email
      CERTBOT_EMAIL=${input_email:-admin@${UI_DOMAIN}}
    fi
    
    # Validate email format (basic)
    if [[ ! "${CERTBOT_EMAIL}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
      echo "$WARNING_MARK Invalid email format. Using default: admin@${UI_DOMAIN}"
      CERTBOT_EMAIL="admin@${UI_DOMAIN}"
    fi
    
    # Configure SSL for UI domain only
    if certbot --nginx -d "${UI_DOMAIN}" --redirect --non-interactive --agree-tos -m "${CERTBOT_EMAIL}" 2>&1; then
      echo "$CHECK_MARK SSL/TLS enabled for UI domain."
      # Setup auto-renewal (only if not already enabled)
      if ! systemctl is-enabled certbot.timer >/dev/null 2>&1; then
        systemctl enable certbot.timer
        systemctl start certbot.timer
        echo "$CHECK_MARK SSL certificate auto-renewal enabled."
      fi
    else
      echo "$WARNING_MARK Error issuing SSL certificate for UI domain. You can run manually later:"
      echo "  certbot --nginx -d ${UI_DOMAIN}"
    fi
  else
    echo "SSL/TLS skipped for UI domain; you can run certbot later:"
    echo "  certbot --nginx -d ${UI_DOMAIN}"
  fi
}

install_pgadmin4() {
  echo ">> Installing pgAdmin4..."
  
  # Check if pgAdmin4 is already installed
  if command -v /usr/pgadmin4/bin/setup-web.sh >/dev/null 2>&1; then
    echo "$CHECK_MARK pgAdmin4 is already installed. Skipping installation..."
    return 0
  fi
  
  # Install Apache2 (required for pgAdmin4 web)
  if ! command -v apache2 >/dev/null 2>&1; then
    echo "Installing Apache2 (required for pgAdmin4)..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y apache2
    systemctl enable apache2
    systemctl start apache2
  fi
  
  # Add pgAdmin4 repository
  if [[ ! -f /usr/share/keyrings/pgadmin4-archive-keyring.gpg ]]; then
    echo "Adding pgAdmin4 repository..."
    curl -fsS https://www.pgadmin.org/static/packages_pgadmin_org.pub | gpg --dearmor -o /usr/share/keyrings/pgadmin4-archive-keyring.gpg
    local distro_codename
    distro_codename=$(lsb_release -cs)
    echo "deb [signed-by=/usr/share/keyrings/pgadmin4-archive-keyring.gpg] https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/${distro_codename} pgadmin4 main" > /etc/apt/sources.list.d/pgadmin4.list
    apt-get update -y
  fi
  
  # Install pgAdmin4 web
  echo "Installing pgAdmin4 web..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y pgadmin4-web
  
  # Configure pgAdmin4
  echo "Configuring pgAdmin4..."
  if [[ -n "${PGADMIN4_EMAIL}" ]] && [[ -n "${PGADMIN4_PASSWORD}" ]]; then
    # Install expect if not available
    if ! command -v expect >/dev/null 2>&1; then
      apt-get install -y expect
    fi
    
    # Use expect to automate setup-web.sh
    expect <<EOF
set timeout 300
spawn /usr/pgadmin4/bin/setup-web.sh
expect "Email address:"
send "${PGADMIN4_EMAIL}\r"
expect "Password:"
send "${PGADMIN4_PASSWORD}\r"
expect "Retype password:"
send "${PGADMIN4_PASSWORD}\r"
expect eof
EOF
    
    if [[ $? -eq 0 ]]; then
      echo "$CHECK_MARK pgAdmin4 configured successfully."
    else
      echo "$WARNING_MARK pgAdmin4 setup had issues. Please verify manually:"
      echo "  /usr/pgadmin4/bin/setup-web.sh"
    fi
  else
    echo "$WARNING_MARK pgAdmin4 email/password not provided. Please run setup manually:"
    echo "  /usr/pgadmin4/bin/setup-web.sh"
    return 1
  fi
  
  echo "$CHECK_MARK pgAdmin4 installed and configured."
}

configure_nginx_pgadmin4() {
  echo ">> Configuring Nginx for pgAdmin4..."
  
  if [[ -z "${PGADMIN4_DOMAIN}" ]]; then
    echo "$WARNING_MARK pgAdmin4 domain not set. Skipping Nginx configuration."
    return 1
  fi
  
  # Check if nginx is installed
  if ! command -v nginx >/dev/null 2>&1; then
    echo "$CROSS_MARK Nginx is not installed"
    return 1
  fi
  
  # Check if Apache2 is running (required for pgAdmin4)
  if ! systemctl is-active --quiet apache2; then
    echo "Starting Apache2 service..."
    systemctl start apache2
    systemctl enable apache2
  fi
  
  # Create pgAdmin4 Nginx configuration (reverse proxy to Apache2)
  cat > /etc/nginx/sites-available/pgadmin4.conf <<NGINX
# pgAdmin4 (reverse proxy to Apache2)
server {
  listen 80;
  server_name ${PGADMIN4_DOMAIN};

  # Security headers
  add_header X-Frame-Options "SAMEORIGIN" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-XSS-Protection "1; mode=block" always;
  add_header Referrer-Policy "strict-origin-when-cross-origin" always;

  location / {
    proxy_pass http://127.0.0.1/pgadmin4;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Script-Name /;
    proxy_set_header X-Scheme \$scheme;
    proxy_redirect off;
    
    # Increase timeouts for long-running queries
    proxy_read_timeout 300;
    proxy_connect_timeout 60;
    proxy_send_timeout 300;
    
    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }
}
NGINX

  ln -sf /etc/nginx/sites-available/pgadmin4.conf /etc/nginx/sites-enabled/pgadmin4.conf
  
  # Test nginx configuration
  if ! nginx -t; then
    echo "$CROSS_MARK Error in Nginx configuration"
    return 1
  fi
  
  # Reload nginx
  if systemctl reload nginx; then
    echo "$CHECK_MARK Nginx configured and reloaded for pgAdmin4."
  else
    echo "$CROSS_MARK Error reloading Nginx"
    return 1
  fi
}

configure_pgadmin4_ssl() {
  echo ">> Configuring SSL for pgAdmin4 domain..."
  
  if [[ -z "${PGADMIN4_DOMAIN}" ]]; then
    echo "$WARNING_MARK pgAdmin4 domain not set. Skipping SSL configuration."
    return 1
  fi
  
  : "${ENABLE_PGADMIN4_SSL:=}"
  if [[ -z "${ENABLE_PGADMIN4_SSL}" ]]; then
    echo
    read -rp "Enable SSL/TLS for pgAdmin4 domain (${PGADMIN4_DOMAIN}) with Let's Encrypt? (y/N): " ENABLE_PGADMIN4_SSL
    ENABLE_PGADMIN4_SSL=${ENABLE_PGADMIN4_SSL:-N}
  fi
  
  if [[ "${ENABLE_PGADMIN4_SSL}" =~ ^[Yy]$ ]]; then
    echo ">> Installing and configuring TLS for pgAdmin4..."
    
    # Check if certbot is already installed
    if ! command -v certbot >/dev/null 2>&1; then
      apt-get install -y certbot python3-certbot-nginx
    fi
    
    # Get email for certbot (use same as API if already set, or pgAdmin4 email)
    : "${CERTBOT_EMAIL:=${PGADMIN4_EMAIL:-admin@${PGADMIN4_DOMAIN}}}"
    if [[ -z "${CERTBOT_EMAIL}" ]] || [[ "${CERTBOT_EMAIL}" == "admin@${PGADMIN4_DOMAIN}" ]]; then
      read -rp "Email for SSL certificate (default: ${CERTBOT_EMAIL}): " input_email
      CERTBOT_EMAIL=${input_email:-${CERTBOT_EMAIL}}
    fi
    
    # Validate email format (basic)
    if [[ ! "${CERTBOT_EMAIL}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
      echo "$WARNING_MARK Invalid email format. Using default: ${PGADMIN4_EMAIL:-admin@${PGADMIN4_DOMAIN}}"
      CERTBOT_EMAIL="${PGADMIN4_EMAIL:-admin@${PGADMIN4_DOMAIN}}"
    fi
    
    # Configure SSL for pgAdmin4 domain
    if certbot --nginx -d "${PGADMIN4_DOMAIN}" --redirect --non-interactive --agree-tos -m "${CERTBOT_EMAIL}" 2>&1; then
      echo "$CHECK_MARK SSL/TLS enabled for pgAdmin4 domain."
      # Setup auto-renewal (only if not already enabled)
      if ! systemctl is-enabled certbot.timer >/dev/null 2>&1; then
        systemctl enable certbot.timer
        systemctl start certbot.timer
        echo "$CHECK_MARK SSL certificate auto-renewal enabled."
      fi
    else
      echo "$WARNING_MARK Error issuing SSL certificate for pgAdmin4 domain. You can run manually later:"
      echo "  certbot --nginx -d ${PGADMIN4_DOMAIN}"
    fi
  else
    echo "SSL/TLS skipped for pgAdmin4 domain; you can run certbot later:"
    echo "  certbot --nginx -d ${PGADMIN4_DOMAIN}"
  fi
}

main() {
  if [[ $EUID -ne 0 ]]; then
    echo "$CROSS_MARK Please run this script with root privileges (sudo)."
    exit 1
  fi
  
  # Initialize log file
  init_log_file
  
  # Check OS compatibility (must be Debian/Ubuntu)
  check_os_compatibility
  
  # Show license information
  show_license_info
  
  # Require license acceptance
  accept_license
  
  echo
  echo "=========================================="
  echo "  Hesabix Deployment Script"
  echo "=========================================="
  echo
  log_info "Starting deployment process..."
  log_info "Please provide the required information when prompted."
  echo
  
  # Check disk space
  check_disk_space
  
  # Check if port 8000 is available
  if command -v netstat >/dev/null 2>&1; then
    if netstat -tuln | grep -q ":8000 "; then
      log_warning "Port 8000 is in use. You may need to stop the previous service."
    fi
  fi
  
  # Prompt user for configuration
  prompt_vars
  
  # Show configuration summary
  show_config_summary
  
  # Ask for final confirmation
  confirm_installation
  echo
  
  # Reset state if requested
  reset_deployment_state
  echo
  
  # Install prerequisites (skip if already done)
  if ! check_step_completed "prereqs"; then
    install_prereqs
    mark_step_completed "prereqs"
  else
    echo "$CHECK_MARK Prerequisites already installed. Skipping..."
  fi
  echo
  
  # Clone repository (always update)
  clone_repo
  mark_step_completed "repo"
  echo
  
  # Setup database (idempotent)
  if ! check_step_completed "db"; then
    setup_db
    mark_step_completed "db"
  else
    echo "$CHECK_MARK Database already configured. Skipping..."
  fi
  echo
  
  # Deploy backend (always update)
  deploy_backend
  mark_step_completed "backend"
  echo
  
  # Build frontend (always rebuild for latest changes)
  install_flutter_and_build_frontend
  mark_step_completed "frontend"
  echo
  
  # Configure Nginx API (always update)
  configure_nginx_api
  mark_step_completed "nginx_api"
  echo
  
  # Configure Nginx UI (always update)
  configure_nginx_ui
  mark_step_completed "nginx_ui"
  echo
  
  # Configure SSL API (skip if already configured)
  if ! check_step_completed "ssl_api"; then
    configure_api_ssl
    mark_step_completed "ssl_api"
  else
    echo "$CHECK_MARK SSL for API already configured. Skipping..."
  fi
  echo
  
  # Configure SSL UI (skip if already configured)
  if ! check_step_completed "ssl_ui"; then
    configure_ui_ssl
    mark_step_completed "ssl_ui"
  else
    echo "$CHECK_MARK SSL for UI already configured. Skipping..."
  fi
  echo
  
  # Install and configure pgAdmin4 (optional)
  if [[ "${INSTALL_PGADMIN4}" =~ ^[Yy]$ ]]; then
    if ! check_step_completed "pgadmin4"; then
      install_pgadmin4
      mark_step_completed "pgadmin4"
    else
      echo "$CHECK_MARK pgAdmin4 already installed. Skipping..."
    fi
    echo
    
    if ! check_step_completed "nginx_pgadmin4"; then
      configure_nginx_pgadmin4
      mark_step_completed "nginx_pgadmin4"
    else
      echo "$CHECK_MARK Nginx for pgAdmin4 already configured. Skipping..."
    fi
    echo
    
    if ! check_step_completed "ssl_pgadmin4"; then
      configure_pgadmin4_ssl
      mark_step_completed "ssl_pgadmin4"
    else
      echo "$CHECK_MARK SSL for pgAdmin4 already configured. Skipping..."
    fi
    echo
  fi
  
  # Clear state file on successful completion
  clear_deployment_state
  
  echo "=========================================="
  log_success "Deployment completed!"
  echo "=========================================="
  echo
  log_info "Access URLs:"
  echo "  API:  https://${API_DOMAIN}/api/v1/health"
  echo "  UI:   https://${UI_DOMAIN}/"
  if [[ "${INSTALL_PGADMIN4}" =~ ^[Yy]$ ]] && [[ -n "${PGADMIN4_DOMAIN}" ]]; then
    echo "  pgAdmin4: https://${PGADMIN4_DOMAIN}/"
  fi
  echo
  log_info "Service management:"
  echo "  systemctl status hesabix-api                      # API status"
  echo "  systemctl restart hesabix-api                      # Restart API"
  echo "  journalctl -u hesabix-api -f                       # View API logs"
  echo "  systemctl status hesabix-rq-worker                 # RQ Worker status"
  echo "  systemctl status hesabix-notification-moderation   # Notification Moderation Worker status"
  echo "  systemctl status nginx                             # Nginx status"
  echo
  log_info "Deployment log file:"
  echo "  ${LOG_FILE}"
  echo
  log_info "To re-run/upgrade:"
  echo "  BRANCH=${BRANCH} API_DOMAIN=${API_DOMAIN} UI_DOMAIN=${UI_DOMAIN} sudo -E bash deploy.sh"
  echo
  log_info "Database password is stored in:"
  echo "  ${APP_ROOT}/.db_password"
  echo
}

main "$@"


