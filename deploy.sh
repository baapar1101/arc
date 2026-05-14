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
# - حداقل RAM نصب: حدود ۵٫۵ گیگابایت (GiB) — تابع check_minimum_ram
# - Nginx: بعد از SSL، برای عوض کردن فقط دامنه‌ها از scripts/update_nginx_domains.sh استفاده کنید؛
#   این اسکریپت listen 443 و مسیرهای /p/ و /i/ را با گواهی Let's Encrypt (یا SSL_LETSENCRYPT_LIVE در .deploy_env) می‌سازد.
# - آدرس API در بیلد وب: به‌صورت خودکار http یا https از روی وجود گواهی در
#   /etc/letsencrypt/live/<API_DOMAIN>؛ برای TLS بدون این مسیر، API_PUBLIC_SCHEME را در محیط export کنید.
#   نوشتن دستی hesabix-api فقط با HTTP باعث می‌شود https به سرور پیش‌فرض 443 (مثلاً pgAdmin) بخورد.
# - Resume from failure: if a step fails, re-run the script to continue from that step
#   (completed steps are skipped using .deploy_state)
# - Saved inputs: last entered domain, branch, pgAdmin4 options, etc. are stored in .deploy_saved_vars
#   and used as defaults on next run (override by env vars or leave blank to be prompted again).
# - For full re-run/upgrade (e.g. pull latest code and rebuild): use RESET_STATE=y
# - pip: only Hesabix PyPI mirror — https://p.mirror.hesabix.ir/simple (see configure_pip_hesabix_mirror, set_pip_mirror_env).
#   If PIP_INDEX_URL is set in the environment before deploy, that value is used instead (advanced override).
# - Flutter/Dart: همیشه آینهٔ داخلی f.mirror.hesabix.ir (pub + gcs). shell.hesabix.ir فقط برای tarball SDK است.
# - Flutter SDK git clone: official (GitHub) is tried first; if it fails, alternatives are tried (FLUTTER_SDK_GIT_URL if set, then Tsinghua, Gitee).
# - Flutter SDK: first try internal tarball (FLUTTER_SDK_TARBALL_URL_INTERNAL = shell.hesabix.ir/...), then snap, then git clone; pub packages via PUB_HOSTED_URL.
#   Large tarball (~2GB): download uses --progress-bar, resume (-C -), FLUTTER_SDK_CONNECT_TIMEOUT (default 120s),
#   FLUTTER_SDK_DOWNLOAD_MAX_TIME (default 0 = no overall time limit; was 120s and caused false failures).
#   Unreliable links: FLUTTER_SDK_TARBALL_ATTEMPTS (default 3), post-download tar test, optional FLUTTER_SDK_TARBALL_SHA256,
#   FLUTTER_SDK_CURL_HTTP11=1 (default) sends --http1.1 to reduce flaky proxy/CDN issues.
# - Flutter PATH: /etc/profile.d/hesabix-flutter.sh (+ یک خط در /etc/bash.bashrc برای شِل تعاملی غیر-login).
# - Ubuntu APT mirror (only when ID=ubuntu): UBUNTU_APT_MIRROR=keep|arvan|official (non-interactive);
#   default keep. arvan uses http://mirror.arvancloud.ir/ubuntu for archive.ubuntu.com and security.ubuntu.com.
#   official restores those URLs from Arvan (per-stanza: *-security → security.ubuntu.com).
# - Debian: mirror prompt skipped; sources unchanged.
# - Apt/needrestart: by default NEEDRESTART_SUSPEND=1 during deploy so post-install service
#   restarts (e.g. fwupd-refresh) do not run and fail on headless VPS. Set NEEDRESTART_SUSPEND=0
#   to allow needrestart behavior.
#
# ============================================================================

REPO_URL="https://source.hesabix.ir/hesabix/arc.git"
APP_ROOT="/opt/hesabix"
# مخزن داخلی tarball SDK (ایران)؛ کتابخانه‌های pub فقط از f.mirror.hesabix.ir
FLUTTER_SDK_TARBALL_URL_INTERNAL="https://shell.hesabix.ir/flutter_linux_3.41.1-stable.tar.xz"
# tarball SDK حجیم؛ 0 یعنی بدون سقف زمانی برای کل دانلود (جلوگیری از قطع ناخواسته)
: "${FLUTTER_SDK_CONNECT_TIMEOUT:=120}"
: "${FLUTTER_SDK_DOWNLOAD_MAX_TIME:=0}"
: "${FLUTTER_SDK_TARBALL_ATTEMPTS:=3}"
: "${FLUTTER_SDK_CURL_HTTP11:=1}"
STATE_FILE="${APP_ROOT}/.deploy_state"
LOG_FILE="${APP_ROOT}/deploy.log"
CHECK_MARK=$'\xE2\x9C\x94'
CROSS_MARK=$'\xE2\x9D\x8C'
WARNING_MARK=$'\xE2\x9A\xA0'

DEPLOY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/api_public_scheme.sh
if [[ -r "${DEPLOY_SCRIPT_DIR}/scripts/api_public_scheme.sh" ]]; then
  # shellcheck disable=SC1091
  source "${DEPLOY_SCRIPT_DIR}/scripts/api_public_scheme.sh"
fi
if ! declare -F hesabix_resolve_api_public_scheme >/dev/null 2>&1; then
  hesabix_resolve_api_public_scheme() {
    if [[ -n "${API_DOMAIN:-}" ]] && [[ -d "/etc/letsencrypt/live/${API_DOMAIN}" ]]; then
      printf '%s' "https"; return 0
    fi
    local s="${API_PUBLIC_SCHEME:-}"
    s="${s,,}"
    case "$s" in http|https) printf '%s' "$s"; return 0 ;; esac
    printf '%s' "http"
  }
fi

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

# MemTotal از /proc/meminfo (کیلوبایت)
get_mem_total_kb() {
  if [[ -r /proc/meminfo ]]; then
    awk '/^MemTotal:/ {print int($2); exit}' /proc/meminfo 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

# حداقل ۵٫۵ گیگابایت RAM (GiB) برای نصب Hesabix
check_minimum_ram() {
  local mem_kb min_kb mem_mb min_mb
  mem_kb=$(get_mem_total_kb)
  if [[ ! "${mem_kb}" =~ ^[0-9]+$ ]] || [[ "${mem_kb}" -eq 0 ]]; then
    log_error "خواندن مقدار RAM از /proc/meminfo ممکن نیست. نصب متوقف شد."
    exit 1
  fi
  # 5.5 GiB = 5.5 * 1024 * 1024 kB
  min_kb=$(( (11 * 1024 * 1024) / 2 ))
  mem_mb=$((mem_kb / 1024))
  min_mb=$((min_kb / 1024))
  if [[ "${mem_kb}" -lt "${min_kb}" ]]; then
    log_error "برای نصب Hesabix حداقل ${min_mb} مگابایت RAM (حدود ۵٫۵ گیگابایت) لازم است. MemTotal فعلی: حدود ${mem_mb} مگابایت."
    log_error "سرور را ارتقا دهید یا swap/RAM کافی فراهم کنید و دوباره اجرا کنید."
    exit 1
  fi
  log_success "بررسی RAM: حدود ${mem_mb} مگابایت (حداقل مورد نیاز: ${min_mb} مگابایت)"
}

# متغیرهای پروفایل PostgreSQL را بر اساس MemTotal (kB) تنظیم می‌کند
assign_pg_memory_profile_from_mem_kb() {
  local mem_kb="${1:-0}"
  if [[ ! "${mem_kb}" =~ ^[0-9]+$ ]]; then
    mem_kb=0
  fi
  # آستانه‌ها بر حسب kB: 8GiB=8388608، 16GiB=16777216، 32GiB=33554432
  if [[ "${mem_kb}" -ge 33554432 ]]; then
    PG_SHARED_BUFFERS="8GB"
    PG_EFFECTIVE_CACHE_SIZE="24GB"
    PG_WORK_MEM="16MB"
    PG_MAINTENANCE_WORK_MEM="512MB"
    PG_MAX_CONN_CAP=800
  elif [[ "${mem_kb}" -ge 16777216 ]]; then
    PG_SHARED_BUFFERS="4GB"
    PG_EFFECTIVE_CACHE_SIZE="12GB"
    PG_WORK_MEM="12MB"
    PG_MAINTENANCE_WORK_MEM="256MB"
    PG_MAX_CONN_CAP=500
  elif [[ "${mem_kb}" -ge 8388608 ]]; then
    PG_SHARED_BUFFERS="1GB"
    PG_EFFECTIVE_CACHE_SIZE="6GB"
    PG_WORK_MEM="8MB"
    PG_MAINTENANCE_WORK_MEM="128MB"
    PG_MAX_CONN_CAP=280
  else
    PG_SHARED_BUFFERS="512MB"
    PG_EFFECTIVE_CACHE_SIZE="3GB"
    PG_WORK_MEM="4MB"
    PG_MAINTENANCE_WORK_MEM="64MB"
    PG_MAX_CONN_CAP=200
  fi
}

# کاهش workers و در صورت نیاز pool تا مجموع اتصال موردنیاز از سقف منطقی RAM عبور نکند
tune_deployment_for_system_ram() {
  local mem_kb need pool_settings cap
  mem_kb=$(get_mem_total_kb)
  if [[ ! "${mem_kb}" =~ ^[0-9]+$ ]] || [[ "${mem_kb}" -eq 0 ]]; then
    log_warning "RAM خوانده نشد؛ تنظیم خودکار worker/pool رد شد."
    return 0
  fi
  assign_pg_memory_profile_from_mem_kb "${mem_kb}"
  cap="${PG_MAX_CONN_CAP}"
  need=$(( UVICORN_WORKERS * (DB_POOL_SIZE + DB_MAX_OVERFLOW) + 100 ))
  while [[ "${need}" -gt "${cap}" ]] && [[ "${UVICORN_WORKERS}" -gt 1 ]]; do
    UVICORN_WORKERS=$((UVICORN_WORKERS - 1))
    pool_settings=$(calculate_db_pool_settings "${UVICORN_WORKERS}")
    DB_POOL_SIZE=$(echo "${pool_settings}" | cut -d: -f1)
    DB_MAX_OVERFLOW=$(echo "${pool_settings}" | cut -d: -f2)
    need=$(( UVICORN_WORKERS * (DB_POOL_SIZE + DB_MAX_OVERFLOW) + 100 ))
    log_warning "کاهش UVICORN_WORKERS به ${UVICORN_WORKERS} برای هم‌خوانی با سقف اتصال PostgreSQL (~${cap}) بر اساس RAM."
  done
  while [[ "${need}" -gt "${cap}" ]]; do
    if [[ "${DB_POOL_SIZE}" -gt 20 ]]; then
      DB_POOL_SIZE=$((DB_POOL_SIZE - 10))
    elif [[ "${DB_MAX_OVERFLOW}" -gt 30 ]]; then
      DB_MAX_OVERFLOW=$((DB_MAX_OVERFLOW - 10))
    else
      log_warning "حداکثر اتصال موردنیاز (${need}) از سقف پیشنهادی (${cap}) بیشتر است؛ max_connections در PostgreSQL بالاتر از cap تنظیم می‌شود."
      break
    fi
    need=$(( UVICORN_WORKERS * (DB_POOL_SIZE + DB_MAX_OVERFLOW) + 100 ))
    log_warning "کاهش DB_POOL_SIZE/DB_MAX_OVERFLOW برای جا شدن در محدوده RAM (نیاز اتصال تقریبی: ${need})."
  done
  log_info "تنظیم نهایی بر اساس RAM: workers=${UVICORN_WORKERS}, pool_size=${DB_POOL_SIZE}, max_overflow=${DB_MAX_OVERFLOW}, سقف اتصال پیشنهادی PG≈${cap}"
}

# نوشتن conf.d/hesabix-optimization.conf بر اساس RAM و بار محاسبه‌شده
write_postgresql_hesabix_optimization_conf() {
  local pg_version="$1"
  local mem_kb max_conn pg_conf_dest tmpf workers pool ov
  mem_kb=$(get_mem_total_kb)
  assign_pg_memory_profile_from_mem_kb "${mem_kb}"
  workers="${UVICORN_WORKERS:-1}"
  pool="${DB_POOL_SIZE:-20}"
  ov="${DB_MAX_OVERFLOW:-30}"
  max_conn=$(( workers * (pool + ov) + 100 ))
  if [[ "${max_conn}" -lt 100 ]]; then
    max_conn=100
  fi
  if [[ "${max_conn}" -lt $((pool + ov + 20)) ]]; then
    max_conn=$((pool + ov + 20))
  fi
  pg_conf_dest="/etc/postgresql/${pg_version}/main/conf.d/hesabix-optimization.conf"
  sudo mkdir -p "/etc/postgresql/${pg_version}/main/conf.d"
  tmpf="$(mktemp)"
  {
    echo "# Generated by Hesabix deploy.sh — do not edit by hand (re-run deploy or adjust deploy.sh)."
    echo "# MemTotal ~ $((mem_kb / 1024)) MB — profile shared_buffers=${PG_SHARED_BUFFERS}"
    echo ""
    echo "# Hesabix app: uvicorn workers × (pool_size + max_overflow) + headroom"
    echo "max_connections = ${max_conn}"
    echo ""
    echo "shared_buffers = ${PG_SHARED_BUFFERS}"
    echo "effective_cache_size = ${PG_EFFECTIVE_CACHE_SIZE}"
    echo "work_mem = ${PG_WORK_MEM}"
    echo "maintenance_work_mem = ${PG_MAINTENANCE_WORK_MEM}"
    echo ""
    echo "random_page_cost = 1.1"
  } > "${tmpf}"
  sudo install -o postgres -g postgres -m 0644 "${tmpf}" "${pg_conf_dest}"
  rm -f "${tmpf}"
  log_success "فایل بهینه‌سازی PostgreSQL نوشته شد: ${pg_conf_dest}"
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

# Create or alter PostgreSQL role hesabix with password (any characters; uses dollar-quoting + format %L).
apply_postgres_hesabix_password() {
  DB_PASSWORD="${DB_PASSWORD}" python3 <<'PY'
import os, subprocess, secrets
pw = os.environ["DB_PASSWORD"]
for _ in range(32):
    delim = "h" + secrets.token_hex(16)
    boundary = f"${delim}$"
    if boundary not in pw:
        break
else:
    raise SystemExit("Could not pick a safe dollar-quote delimiter for the database password")
lit = boundary + pw + boundary
sql = (
    "DO $do$\n"
    "BEGIN\n"
    "  IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'hesabix') THEN\n"
    "    EXECUTE format('CREATE USER hesabix WITH PASSWORD %L', " + lit + ");\n"
    "  ELSE\n"
    "    EXECUTE format('ALTER USER hesabix WITH PASSWORD %L', " + lit + ");\n"
    "  END IF;\n"
    "END\n"
    "$do$;"
)
subprocess.run(
    ["sudo", "-u", "postgres", "psql", "-v", "ON_ERROR_STOP=1", "-c", sql],
    check=True,
)
PY
}

# Merge production keys into hesabixAPI .env (values with special chars are quoted for dotenv).
merge_hesabix_api_env_file() {
  local env_file="$1"
  export MERGE_ENV_PATH="${env_file}"
  export MERGE_DB_PASSWORD="${DB_PASSWORD}"
  export MERGE_DB_POOL_SIZE="${DB_POOL_SIZE}"
  export MERGE_DB_MAX_OVERFLOW="${DB_MAX_OVERFLOW}"
  python3 <<'PY'
import os, re
path = os.environ["MERGE_ENV_PATH"]

def fmt_val(v: str) -> str:
    if v is None:
        return ""
    if re.search(r'[\s#"\'\\]', v) or v.startswith("#"):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    return v

updates = {
    "ENVIRONMENT": "production",
    "DEBUG": "false",
    "DB_USER": "hesabix",
    "DB_PASSWORD": os.environ["MERGE_DB_PASSWORD"],
    "DB_HOST": "127.0.0.1",
    "DB_PORT": "5432",
    "DB_NAME": "hesabix",
    "LOG_LEVEL": "INFO",
    "DB_POOL_SIZE": os.environ["MERGE_DB_POOL_SIZE"],
    "DB_MAX_OVERFLOW": os.environ["MERGE_DB_MAX_OVERFLOW"],
    "DB_POOL_TIMEOUT": "30",
    "DB_POOL_RECYCLE": "300",
    "CORS_ALLOWED_ORIGINS": '["*"]',
}
lines = []
if os.path.isfile(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = f.readlines()
keys_done = set()
key_re = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=")
out = []
for line in lines:
    m = key_re.match(line)
    if m and m.group(1) in updates:
        k = m.group(1)
        out.append(f"{k}={fmt_val(updates[k])}\n")
        keys_done.add(k)
    else:
        out.append(line)
for k, v in updates.items():
    if k not in keys_done:
        out.append(f"{k}={fmt_val(v)}\n")
with open(path, "w", encoding="utf-8") as f:
    f.writelines(out)
PY
}

# Check disk space (requires at least 2GB free)
check_disk_space() {
  local available_space
  local min_avail=999999999999
  local space
  for mnt in / "${APP_ROOT}"; do
    [[ -d "${mnt}" ]] || continue
    space=$(df -P "${mnt}" 2>/dev/null | tail -1 | awk '{print $4}')
    [[ "${space}" =~ ^[0-9]+$ ]] || continue
    if [ "${space}" -lt "${min_avail}" ]; then
      min_avail="${space}"
    fi
  done
  available_space="${min_avail}"
  if [[ ! "${available_space}" =~ ^[0-9]+$ ]]; then
    log_warning "Could not read free disk space; skipping disk check."
    return 0
  fi
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

# Load saved deploy inputs (domain, branch, pgAdmin4, etc.) as defaults. Only sets vars that are not already set (env overrides).
load_saved_deploy_vars() {
  local file="${APP_ROOT}/.deploy_saved_vars"
  [[ ! -f "${file}" ]] && return 0
  log_info "Loading saved inputs from previous run (use env vars to override)..."
  local line key val
  while IFS= read -r line; do
    [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    key="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"
    # Only set if not already set by environment
    if [[ -z "${!key:-}" ]]; then
      export "${key}=${val}"
    fi
  done < "${file}"
}

# Save current deploy inputs so next run can use them as defaults (resume after failure without re-entering).
save_deploy_saved_vars() {
  mkdir -p "${APP_ROOT}"
  local file="${APP_ROOT}/.deploy_saved_vars"
  {
    echo "API_DOMAIN=${API_DOMAIN:-}"
    echo "UI_DOMAIN=${UI_DOMAIN:-}"
    echo "BRANCH=${BRANCH:-main}"
    echo "INSTALL_PGADMIN4=${INSTALL_PGADMIN4:-N}"
    echo "PGADMIN4_DOMAIN=${PGADMIN4_DOMAIN:-}"
    echo "PGADMIN4_EMAIL=${PGADMIN4_EMAIL:-}"
    echo "PGADMIN4_PASSWORD=${PGADMIN4_PASSWORD:-}"
    echo "UBUNTU_APT_MIRROR=${UBUNTU_APT_MIRROR:-}"
  } > "${file}"
  chmod 600 "${file}"
  log_info "Saved inputs for next run (${file})"
}

# Persist UBUNTU_APT_MIRROR into .deploy_saved_vars (after apt mirror step).
persist_ubuntu_apt_mirror_to_saved_vars() {
  local f="${APP_ROOT}/.deploy_saved_vars"
  [[ ! -f "${f}" ]] && return 0
  local tmp
  tmp=$(mktemp)
  grep -v '^UBUNTU_APT_MIRROR=' "${f}" > "${tmp}" 2>/dev/null || true
  echo "UBUNTU_APT_MIRROR=${UBUNTU_APT_MIRROR:-keep}" >> "${tmp}"
  mv "${tmp}" "${f}"
  chmod 600 "${f}"
}

# Ubuntu only: optional switch to Arvan apt mirror before apt-get update (deb822 + classic deb lines).
configure_ubuntu_apt_mirror() {
  local id=""
  # shellcheck disable=SC1091
  [[ -f /etc/os-release ]] && source /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || return 0

  local codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
  log_info "Ubuntu apt mirror: detected codename ${codename:-unknown}"

  UBUNTU_APT_MIRROR="${UBUNTU_APT_MIRROR:-}"
  UBUNTU_APT_MIRROR="${UBUNTU_APT_MIRROR,,}"
  if [[ -z "${UBUNTU_APT_MIRROR}" ]]; then
    echo
    echo "APT package sources (Ubuntu only):"
    echo "  [1] Keep current system configuration (default)"
    echo "  [2] Arvan Cloud mirror — mirror.arvancloud.ir (replaces archive.ubuntu.com and security.ubuntu.com)"
    echo "  [3] Restore official Ubuntu — only if Arvan was configured (archive + security)"
    read -rp "Choose [1/2/3] (default 1): " _apt_mirror_choice
    _apt_mirror_choice=${_apt_mirror_choice:-1}
    case "${_apt_mirror_choice}" in
      2) UBUNTU_APT_MIRROR=arvan ;;
      3) UBUNTU_APT_MIRROR=official ;;
      *) UBUNTU_APT_MIRROR=keep ;;
    esac
  fi
  export UBUNTU_APT_MIRROR

  if [[ "${UBUNTU_APT_MIRROR}" == "keep" ]]; then
    log_info "APT sources: leaving unchanged (UBUNTU_APT_MIRROR=keep)."
    persist_ubuntu_apt_mirror_to_saved_vars
    return 0
  fi

  if [[ "${UBUNTU_APT_MIRROR}" != "arvan" && "${UBUNTU_APT_MIRROR}" != "official" ]]; then
    log_warning "Invalid UBUNTU_APT_MIRROR='${UBUNTU_APT_MIRROR}', using keep."
    UBUNTU_APT_MIRROR=keep
    export UBUNTU_APT_MIRROR
    persist_ubuntu_apt_mirror_to_saved_vars
    return 0
  fi

  local backup_dir="/etc/apt/hesabix-apt-mirror-backup-$(date +%Y%m%d%H%M%S)"
  mkdir -p "${backup_dir}"

  local candidates=()
  local f
  [[ -f /etc/apt/sources.list ]] && candidates+=("/etc/apt/sources.list")
  for f in /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do
    [[ -f "${f}" ]] || continue
    candidates+=("${f}")
  done

  local files_to_edit=()
  for f in "${candidates[@]}"; do
    if grep -qE 'archive\.ubuntu\.com/ubuntu|security\.ubuntu\.com/ubuntu|mirror\.arvancloud\.ir/ubuntu' "${f}" 2>/dev/null; then
      files_to_edit+=("${f}")
      local rel="${f#/}"
      rel="${rel//\//__}"
      cp -a "${f}" "${backup_dir}/${rel}.bak"
    fi
  done

  if [[ ${#files_to_edit[@]} -eq 0 ]]; then
    log_info "No Ubuntu archive/security/Arvan lines found in apt sources; nothing to change."
    persist_ubuntu_apt_mirror_to_saved_vars
    return 0
  fi

  log_info "APT mirror mode: ${UBUNTU_APT_MIRROR} (backup: ${backup_dir})"

  local apt_file_list
  apt_file_list=$(printf '%s\n' "${files_to_edit[@]}")

  UBUNTU_APT_MIRROR_MODE="${UBUNTU_APT_MIRROR}" HESABIX_APT_FILE_LIST="${apt_file_list}" python3 <<'PY'
import os, re, sys

mode = os.environ.get("UBUNTU_APT_MIRROR_MODE", "")
paths = [p for p in os.environ.get("HESABIX_APT_FILE_LIST", "").splitlines() if p.strip()]
ARVAN = "http://mirror.arvancloud.ir/ubuntu"
ARCHIVE = "http://archive.ubuntu.com/ubuntu"
SECURITY = "http://security.ubuntu.com/ubuntu"


def apply_arvan(text: str) -> str:
    if "archive.ubuntu.com/ubuntu" not in text and "security.ubuntu.com/ubuntu" not in text:
        return text
    t = re.sub(r"https?://archive\.ubuntu\.com/ubuntu\b", ARVAN, text)
    t = re.sub(r"https?://security\.ubuntu\.com/ubuntu\b", ARVAN, t)
    return t


def apply_official(text: str) -> str:
    if "mirror.arvancloud.ir" not in text:
        return text
    if re.search(r"(?m)^Types:\s*deb", text) and re.search(r"(?m)^URIs:", text):
        blocks = re.split(r"\n{2,}", text)
        out = []
        for b in blocks:
            if not b.strip():
                continue
            if re.search(r"(?m)^URIs:\s*https?://mirror\.arvancloud\.ir/ubuntu\b", b):
                sm = re.search(r"(?m)^Suites:(.*)$", b)
                suites = sm.group(1) if sm else ""
                uri = SECURITY if re.search(r"\b[\w.-]+-security\b", suites) else ARCHIVE
                b = re.sub(r"(?m)^URIs:\s*[^\n]+", "URIs: " + uri, b, count=1)
            out.append(b)
        joined = "\n\n".join(out)
        if text.endswith("\n") and not joined.endswith("\n"):
            joined += "\n"
        return joined
    lines = []
    for line in text.splitlines(True):
        if re.match(r"^\s*deb(-src)?\s+", line) and "mirror.arvancloud.ir" in line:
            parts = line.split()
            if len(parts) >= 3 and parts[0] in ("deb", "deb-src"):
                suite = parts[2]
                parts[1] = SECURITY if "-security" in suite else ARCHIVE
                line = " ".join(parts) + ("\n" if line.endswith("\n") else "")
        lines.append(line)
    return "".join(lines)


for path in paths:
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            content = fh.read()
    except OSError as e:
        print(f"skip read {path}: {e}", file=sys.stderr)
        continue
    if mode == "arvan":
        new = apply_arvan(content)
    elif mode == "official":
        new = apply_official(content)
    else:
        new = content
    if new != content:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(new)
        print(path)
PY

  if ! apt-get update -y; then
    log_error "apt-get update failed after mirror change; restoring from ${backup_dir}"
    for f in "${files_to_edit[@]}"; do
      local rel="${f#/}"
      rel="${rel//\//__}"
      if [[ -f "${backup_dir}/${rel}.bak" ]]; then
        cp -a "${backup_dir}/${rel}.bak" "${f}"
      fi
    done
    UBUNTU_APT_MIRROR=keep
    export UBUNTU_APT_MIRROR
    persist_ubuntu_apt_mirror_to_saved_vars
    if apt-get update -y; then
      log_warning "Restored previous apt sources; continuing with prerequisite install."
      return 0
    fi
    return 1
  fi

  log_success "APT sources updated (${UBUNTU_APT_MIRROR}); apt-get update succeeded."
  persist_ubuntu_apt_mirror_to_saved_vars
  return 0
}

# Save deployment config for hesabix CLI (-update, -services, …) and install /usr/local/bin/hesabix
install_hesabix_command() {
  mkdir -p "${APP_ROOT}"
  local env_file="${APP_ROOT}/.deploy_env"
  cat > "${env_file}" <<ENV
API_DOMAIN=${API_DOMAIN}
UI_DOMAIN=${UI_DOMAIN}
BRANCH=${BRANCH}
REPO_URL=${REPO_URL}
ENV
  chmod 600 "${env_file}"
  log_info "Saved deployment config to ${env_file}"

  local bin_hesabix="/usr/local/bin/hesabix"
  local cli_src="${APP_ROOT}/app/scripts/hesabix"
  if [[ ! -f "${cli_src}" ]]; then
    cli_src="$(pwd)/scripts/hesabix"
  fi
  if [[ ! -f "${cli_src}" ]]; then
    log_error "CLI source not found: scripts/hesabix (expected at ${APP_ROOT}/app/scripts/hesabix)"
    return 1
  fi
  if command -v install >/dev/null 2>&1; then
    install -m 755 "${cli_src}" "${bin_hesabix}"
  else
    cp -f "${cli_src}" "${bin_hesabix}"
    chmod 755 "${bin_hesabix}" 2>/dev/null || true
  fi
  log_success "Command installed: hesabix (e.g. sudo hesabix -update | sudo hesabix -services restart | sudo hesabix -cli reload)"
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
  # نمایش در خلاصه؛ tarball پیش‌فرض داخلی FLUTTER_SDK_TARBALL_URL_INTERNAL ≈ 3.41.x stable
  : "${FLUTTER_VERSION:=3.41.1}"
  : "${UVICORN_WORKERS:=}"
  
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
  tune_deployment_for_system_ram
  
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
  
  save_deploy_saved_vars
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
  log_step "Installing prerequisites..."
  export DEBIAN_FRONTEND=noninteractive
  
  configure_ubuntu_apt_mirror

  # Update package list
  log_info "Updating package list..."
  apt-get update -y
  
  # Detect Python 3 version and install appropriate packages
  # Ubuntu 24.04 uses python3.12 by default, Ubuntu 22.04 uses python3.10/3.11
  # We'll use python3 and python3-venv which work on all versions
  # WeasyPrint (PDF) requires: libcairo2, libpango*, libgdk-pixbuf-2.0-0 (note: hyphen in package name on Ubuntu 24)
  log_info "Installing: git, curl, unzip, xz-utils, ca-certificates, python3, python3-venv, python3-pip, build-essential, nginx, postgresql, postgresql-contrib, postgresql-client, redis-server, WeasyPrint system deps (libpango/cairo)..."
  apt-get install -y git curl unzip xz-utils ca-certificates \
    python3 python3-venv python3-pip build-essential \
    nginx postgresql postgresql-contrib postgresql-client redis-server \
    libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libgdk-pixbuf-2.0-0 libffi-dev shared-mime-info
  
  # Detect Python version for logging
  PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
  log_info "Python version detected: ${PYTHON_VERSION}"
  
  # Ensure PostgreSQL service is enabled and started
  if command -v systemctl >/dev/null 2>&1; then
    # Check if postgresql service exists (may be postgresql or postgresql@*)
    if systemctl list-unit-files 2>/dev/null | grep -qE "postgresql(@|\.service)"; then
      log_info "Enabling and starting PostgreSQL service..."
      systemctl enable postgresql 2>/dev/null || true
      systemctl start postgresql 2>/dev/null || true
      
      # Also try specific version service (e.g., postgresql@16-main)
      local pg_service
      pg_service=$(systemctl list-units --type=service --state=inactive,active 2>/dev/null | grep -oE "postgresql@[0-9]+-main" | head -1 || echo "")
      if [[ -n "${pg_service}" ]]; then
        log_info "Starting PostgreSQL service: ${pg_service}"
        systemctl enable "${pg_service}" 2>/dev/null || true
        systemctl start "${pg_service}" 2>/dev/null || true
      fi
    fi
    
    # Ensure Redis service is enabled and started
    if systemctl list-unit-files 2>/dev/null | grep -qE "redis(@|\.service|server)"; then
      log_info "Enabling and starting Redis service..."
      systemctl enable redis-server 2>/dev/null || systemctl enable redis 2>/dev/null || true
      systemctl start redis-server 2>/dev/null || systemctl start redis 2>/dev/null || true
    fi
  fi
  
  log_success "Prerequisites installed (or already present)."
}

clone_repo() {
  log_step "Cloning/updating repository..."
  mkdir -p "${APP_ROOT}"
  cd "${APP_ROOT}"
  
  # If app exists but .git is missing (e.g. previous clone failed halfway), remove for fresh clone
  if [[ -d "${APP_ROOT}/app" ]] && [[ ! -d "${APP_ROOT}/app/.git" ]]; then
    log_info "Removing incomplete app directory for fresh clone..."
    rm -rf "${APP_ROOT}/app"
  fi
  
  if [[ ! -d "${APP_ROOT}/app/.git" ]]; then
    log_info "Cloning repository..."
    
    # Try to clone with specified branch first
    if git clone -b "${BRANCH}" "${REPO_URL}" app 2>/dev/null; then
      cd app
      log_success "Repository cloned successfully on branch: ${BRANCH}"
    else
      # If branch doesn't exist, clone without branch and use default
      log_warning "Branch '${BRANCH}' not found. Cloning default branch..."
      if ! git clone "${REPO_URL}" app; then
        log_error "Error cloning repository"
        exit 1
      fi
      cd app
      
      # Detect default branch (git clone automatically checks out default branch)
      local default_branch
      default_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
      if [[ -n "${default_branch}" ]]; then
        BRANCH="${default_branch}"
        log_info "Using default branch: ${default_branch}"
      else
        log_warning "Could not detect default branch. Using current HEAD."
      fi
    fi
  else
    log_info "Updating existing repository..."
    cd app
    
    # Save current branch
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    
    # Fetch all branches
    if ! git fetch --all --prune; then
      log_warning "Error fetching. Continuing with current state..."
    fi
    
    # Checkout target branch
    if ! git checkout "${BRANCH}" 2>/dev/null; then
      log_warning "Branch ${BRANCH} not found. Using current branch: ${current_branch}"
      BRANCH="${current_branch}"
    fi
    
    # Try to pull, but don't fail if it's not a fast-forward
    if ! git pull --ff-only 2>/dev/null; then
      log_warning "Pull failed (may need merge). Using current state..."
      git reset --hard "origin/${BRANCH}" 2>/dev/null || true
    fi
  fi
  
  # Verify we're on the right branch
  local actual_branch
  actual_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  log_success "Repository ready at ${APP_ROOT}/app (branch: ${actual_branch})"
}

setup_db() {
  log_step "Configuring database (PostgreSQL)..."
  
  # Start and enable PostgreSQL service
  # PostgreSQL service may be named 'postgresql' or 'postgresql@VERSION-main'
  local pg_service_found=false
  local pg_service=""
  
  # Try to find PostgreSQL service
  if systemctl list-unit-files 2>/dev/null | grep -qE "^postgresql\.service"; then
    pg_service="postgresql"
    pg_service_found=true
  elif systemctl list-units --type=service 2>/dev/null | grep -qE "postgresql@"; then
    # Try to find specific version service (e.g., postgresql@16-main)
    pg_service=$(systemctl list-units --type=service --state=inactive,active,failed 2>/dev/null | grep -oE "postgresql@[0-9]+-main" | head -1 || echo "")
    if [[ -z "${pg_service}" ]]; then
      # Try listing all postgresql services
      pg_service=$(systemctl list-unit-files 2>/dev/null | grep -oE "postgresql@[0-9]+-main\.service" | head -1 | sed 's/\.service$//' || echo "")
    fi
    if [[ -n "${pg_service}" ]]; then
      pg_service_found=true
    fi
  fi
  
  if [[ "${pg_service_found}" == "true" ]]; then
    log_info "Starting PostgreSQL service: ${pg_service:-postgresql}..."
    systemctl enable "${pg_service:-postgresql}" 2>/dev/null || true
    systemctl start "${pg_service:-postgresql}" 2>/dev/null || true
    
    # Wait a moment for service to start
    sleep 2
  else
    # Check if PostgreSQL is actually installed
    if ! command -v psql >/dev/null 2>&1 && ! command -v postgres >/dev/null 2>&1; then
      log_error "PostgreSQL is not installed. Please ensure prerequisites installation completed successfully."
      exit 1
    fi
    
    # If service not found, try to start postgresql anyway (might work)
    log_warning "PostgreSQL service unit not found in systemd. Attempting to start postgresql service..."
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable postgresql 2>/dev/null || true
    systemctl start postgresql 2>/dev/null || true
    
    # Also try pg_ctlcluster if available (Debian/Ubuntu specific)
    if command -v pg_ctlcluster >/dev/null 2>&1; then
      local pg_version
      pg_version=$(pg_lsclusters 2>/dev/null | tail -1 | awk '{print $1}' || echo "")
      if [[ -n "${pg_version}" ]]; then
        log_info "Starting PostgreSQL cluster ${pg_version} using pg_ctlcluster..."
        pg_ctlcluster "${pg_version}" main start 2>/dev/null || true
      fi
    fi
    
    sleep 2
  fi
  
  # Wait for database to be ready
  if ! wait_for_db; then
    log_error "Database not ready. Please check PostgreSQL installation and service status."
    log_error "You can check PostgreSQL status with: systemctl status postgresql"
    exit 1
  fi
  
  # Configure PostgreSQL to allow local connections (if needed)
  local pg_version
  local ver_num
  ver_num=$(sudo -u postgres psql -tAc "SHOW server_version_num;" 2>/dev/null | tr -d '[:space:]')
  if [[ -n "${ver_num}" ]] && [[ "${ver_num}" =~ ^[0-9]+$ ]]; then
    pg_version=$((10#${ver_num} / 10000))
  else
    pg_version=$(sudo -u postgres psql -tAc "SHOW server_version;" 2>/dev/null | cut -d. -f1 | tr -d '[:space:]')
  fi
  if [[ -z "${pg_version}" ]] || [[ ! "${pg_version}" =~ ^[0-9]+$ ]]; then
    log_error "Could not detect PostgreSQL major version for config paths."
    exit 1
  fi
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
  
  # Create database and user (password may contain quotes/special characters)
  if ! apply_postgres_hesabix_password; then
    log_error "Failed to create/update PostgreSQL user hesabix (password apply failed)."
    exit 1
  fi

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

  # بهینه‌سازی PostgreSQL بر اساس RAM سرور و workers/pool (نه فایل ثابت ۳۲GB)
  log_info "اعمال تنظیمات PostgreSQL متناسب با RAM و بار Hesabix..."
  write_postgresql_hesabix_optimization_conf "${pg_version}"
  systemctl daemon-reload 2>/dev/null || true
  if [[ -n "${pg_service:-}" ]]; then
    systemctl restart "${pg_service}" 2>/dev/null || systemctl restart "postgresql@${pg_version}-main" 2>/dev/null || systemctl restart postgresql 2>/dev/null || true
  else
    systemctl restart "postgresql@${pg_version}-main" 2>/dev/null || systemctl restart postgresql 2>/dev/null || true
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

  configure_pip_hesabix_mirror
  set_pip_mirror_env
  # Python venv + install
  if [[ ! -d ".venv" ]]; then
    python3 -m venv .venv
  fi
  # shellcheck disable=SC1091
  source .venv/bin/activate
  log_info "Installing backend deps from PyPI: ${PIP_INDEX_URL}"
  if pip install --upgrade pip setuptools wheel && pip install -e .; then
    log_success "Backend dependencies installed from ${PIP_INDEX_URL}"
  else
    log_error "Failed to install backend dependencies from ${PIP_INDEX_URL}. Check mirror reachability or PIP_INDEX_URL override."
    exit 1
  fi

  # env.example as base, then merge production keys (DB_PASSWORD etc. safe for special chars)
  local env_file=".env"
  if [[ -f "env.example" ]]; then
    cp env.example "${env_file}"
  else
    : > "${env_file}"
  fi
  merge_hesabix_api_env_file "${env_file}"
  
  log_info "Database connection pool configured: pool_size=${DB_POOL_SIZE}, max_overflow=${DB_MAX_OVERFLOW}, timeout=30s, recycle=300s"
  
  # Secure .env file permissions (contains sensitive data like DB_PASSWORD)
  chmod 600 "${env_file}"
  chown www-data:www-data "${env_file}"

  # Verify database connection before init
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
    echo "$WARNING_MARK Database connection failed. Initial data import may fail."
  fi

  # Import seed when DB is empty, then always run migrations
  local backup_dir="${APP_ROOT}/app/backup"
  local seed_dump
  seed_dump=$(ls -t "${backup_dir}"/hesabix_seed*.dump 2>/dev/null | head -1)
  local table_count
  table_count=$(PGPASSWORD="${DB_PASSWORD}" psql -h 127.0.0.1 -p 5432 -U hesabix -d hesabix -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';" 2>/dev/null | tr -d '[:space:]')
  if [[ ! "${table_count}" =~ ^[0-9]+$ ]]; then
    table_count=999
  fi

  if [[ "${table_count}" -eq 0 ]] && [[ -n "${seed_dump}" && -f "${seed_dump}" ]]; then
    echo "Importing seed database from: ${seed_dump}"
    if PGPASSWORD="${DB_PASSWORD}" pg_restore -h 127.0.0.1 -p 5432 -U hesabix -d hesabix --no-owner --no-acl "${seed_dump}" 2>/dev/null; then
      log_success "Seed database imported successfully."
    else
      # pg_restore may exit 1 for non-fatal warnings; verify DB is usable
      if PGPASSWORD="${DB_PASSWORD}" psql -h 127.0.0.1 -p 5432 -U hesabix -d hesabix -c "SELECT 1" >/dev/null 2>&1; then
        log_success "Seed database imported (some non-fatal warnings may have occurred)."
      else
        log_error "Error importing seed database. Check pg_restore output."
        exit 1
      fi
    fi
  elif [[ "${table_count}" -gt "0" ]]; then
    log_info "Database already initialized (${table_count} tables). Skipping seed import."
  else
    if [[ -z "${seed_dump}" || ! -f "${seed_dump}" ]]; then
      echo "$WARNING_MARK Seed dump not found in ${backup_dir}/hesabix_seed*.dump"
    fi
  fi

  # Always run migrations (after optional seed import, or when DB was already initialized)
  log_step "Running Alembic migrations..."
  if ! alembic upgrade head; then
    echo "$CROSS_MARK Error running migrations"
    exit 1
  fi
  log_success "Migrations completed."

  # Check if www-data user exists
  if ! id -u www-data >/dev/null 2>&1; then
    echo "$WARNING_MARK User www-data not found. Creating user..."
    useradd -r -s /bin/false www-data || true
  fi

  # Set ownership
  chown -R www-data:www-data "${api_dir}"
  chmod +x "${api_dir}/deployment/systemd/hesabix-api-prestart.sh" 2>/dev/null || true

  # systemd service
  # Type=simple: uvicorn does not send sd_notify; Type=notify would cause start timeout.
  # TimeoutStartSec=300: app startup (WeasyPrint/imports) can take 60-90+ seconds.
  cat > /etc/systemd/system/hesabix-api.service <<UNIT
[Unit]
Description=Hesabix API (FastAPI/Uvicorn)
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
TimeoutStartSec=300
User=www-data
Group=www-data
WorkingDirectory=${api_dir}
Environment=PATH=/usr/bin:/usr/local/bin:${api_dir}/.venv/bin
Environment=PYTHONUNBUFFERED=1
# ! = اجرا با root: daemon-reload + در صورت نیاز pip از آینه‌های deploy (قبل از alembic)
ExecStartPre=!${api_dir}/deployment/systemd/hesabix-api-prestart.sh
# قبل از start/restart: اعمال میگریشن‌ها؛ در صورت شکست، سرویس استارت نمی‌شود
ExecStartPre=${api_dir}/.venv/bin/python -m alembic -c ${api_dir}/alembic.ini upgrade head
ExecStart=${api_dir}/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers ${UVICORN_WORKERS}
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload

  # Stop service if running so the new unit definition is used on next start
  if check_service hesabix-api; then
    systemctl stop hesabix-api
  fi

  systemctl enable hesabix-api
  systemctl start hesabix-api

  # Wait for service to become active (startup with WeasyPrint can take 30-90s)
  log_info "Waiting for hesabix-api to become active (up to 120s)..."
  for i in $(seq 1 24); do
    if systemctl is-active --quiet hesabix-api 2>/dev/null; then
      log_success "Backend started (service: hesabix-api)."
      break
    fi
    if [ "$i" -eq 24 ]; then
      log_error "Backend failed to start within 120s. Check logs: journalctl -xeu hesabix-api"
      exit 1
    fi
    sleep 5
  done

  # RQ Worker service for background jobs
  # redis-server.service = Debian/Ubuntu; redis.service = other distros
  cat > /etc/systemd/system/hesabix-rq-worker.service <<UNIT
[Unit]
Description=Hesabix RQ Worker (Background Jobs)
After=network.target postgresql.service redis-server.service redis.service
Wants=redis-server.service redis.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=${api_dir}
Environment=PATH=${api_dir}/.venv/bin
Environment=PYTHONUNBUFFERED=1
ExecStart=${api_dir}/.venv/bin/python ${api_dir}/rq_worker.py
Restart=on-failure
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
  
  # همیشه RQ worker را استارت می‌کنیم: اگر Redis در تنظیمات سیستم خاموش باشد، اسکریپت با کد ۰ خارج می‌شود
  # و با Restart=on-failure دیگر حلقهٔ ری‌استارت بی‌معنی ایجاد نمی‌شود.
  systemctl start hesabix-rq-worker
  sleep 2
  if systemctl is-active --quiet hesabix-rq-worker 2>/dev/null; then
    log_success "RQ Worker is running (hesabix-rq-worker)."
  else
    log_warning "RQ Worker is not active. If Redis is disabled in system settings, this is expected; enable Redis then: systemctl start hesabix-rq-worker"
    log_warning "Otherwise check: journalctl -u hesabix-rq-worker -n 50"
  fi

  # Notification Moderation Worker service
  # redis-server.service = Debian/Ubuntu; redis.service = other distros
  cat > /etc/systemd/system/hesabix-notification-moderation.service <<UNIT
[Unit]
Description=Hesabix Notification Moderation Worker
Documentation=https://hesabix.com/docs/notification-moderation
After=network.target postgresql.service redis-server.service redis.service
Wants=postgresql.service

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
MemoryMax=512M
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
  
  # Start notification moderation worker (uses DB; not the same as RQ/Redis)
  systemctl start hesabix-notification-moderation
  sleep 2
  if check_service hesabix-notification-moderation; then
    log_success "Notification Moderation Worker started (service: hesabix-notification-moderation)."
  else
    log_warning "Notification Moderation Worker failed to start. Check logs: journalctl -u hesabix-notification-moderation"
  fi
}

# میرور داخلی PyPI (pip) — فقط Hesabix
HESABIX_PIP_INDEX_URL="https://p.mirror.hesabix.ir/simple"
HESABIX_PIP_TRUSTED_HOST="p.mirror.hesabix.ir"

# pip config سراسری کاربر — همان آدرس برای نصب‌های بعدی
configure_pip_hesabix_mirror() {
  if ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi
  python3 -m pip config --user set global.index "${HESABIX_PIP_INDEX_URL}" 2>/dev/null || true
  python3 -m pip config --user set global.index-url "${HESABIX_PIP_INDEX_URL}" 2>/dev/null || true
  python3 -m pip config --user set global.trusted-host "${HESABIX_PIP_TRUSTED_HOST}" 2>/dev/null || true
  log_info "pip user config: Hesabix PyPI (${HESABIX_PIP_INDEX_URL})"
}

# Set PIP_INDEX_URL and PIP_TRUSTED_HOST for a given mirror URL. Call before pip install.
set_pip_mirror_for_url() {
  local index_url="$1"
  export PIP_INDEX_URL="${index_url}"
  if [[ "${index_url}" != *"pypi.org"* ]]; then
    local host
    host=$(echo "${index_url}" | sed -n 's|https\?://\([^/]*\).*|\1|p')
    export PIP_TRUSTED_HOST="${host}"
  else
    unset PIP_TRUSTED_HOST
  fi
}

# میرور پیش‌فرض: Hesabix. اگر PIP_INDEX_URL از قبل در محیط باشد، همان (override) استفاده می‌شود.
# قبل از هر pip install (بک‌اند و pgAdmin4) صدا بزنید.
set_pip_mirror_env() {
  if [[ -n "${PIP_INDEX_URL:-}" ]]; then
    log_info "Using PyPI index from environment: PIP_INDEX_URL=$PIP_INDEX_URL"
    export PIP_INDEX_URL
    if [[ -n "${PIP_TRUSTED_HOST:-}" ]]; then
      export PIP_TRUSTED_HOST
    else
      set_pip_mirror_for_url "${PIP_INDEX_URL}"
    fi
    return 0
  fi
  set_pip_mirror_for_url "${HESABIX_PIP_INDEX_URL}"
  log_info "Using Hesabix PyPI mirror: ${PIP_INDEX_URL}"
  return 0
}

# یک آینهٔ ثابت (کش Nginx → Runflare) برای pub و engine artifacts
set_flutter_mirror_env() {
  export PUB_HOSTED_URL="https://f.mirror.hesabix.ir/pub"
  export FLUTTER_STORAGE_BASE_URL="https://f.mirror.hesabix.ir/gcs"
  log_info "Flutter pub/storage: PUB_HOSTED_URL=$PUB_HOSTED_URL"
}

# نصب PATH دائمی برای شِل‌های جدید (ورود به سیستم / bash --login). فایل POSIX-sh برای /etc/profile.d.
persist_flutter_path_in_profile_d() {
  local f="/etc/profile.d/hesabix-flutter.sh"
  if [[ ! -x /opt/flutter/bin/flutter && ! -x /snap/bin/flutter ]]; then
    return 0
  fi
  cat > "${f}" <<'PROFILE'
# Hesabix: add Flutter to PATH for login shells (deploy.sh / update.sh); avoid manual edits if possible.
if [ -x /opt/flutter/bin/flutter ]; then
  case ":${PATH}:" in
    *:/opt/flutter/bin:*) ;;
    *) PATH="/opt/flutter/bin${PATH:+:$PATH}"; export PATH ;;
  esac
fi
if [ -x /snap/bin/flutter ]; then
  case ":${PATH}:" in
    *:/snap/bin:*) ;;
    *) PATH="/snap/bin${PATH:+:$PATH}"; export PATH ;;
  esac
fi
PROFILE
  chmod 644 "${f}" 2>/dev/null || true
  log_success "Flutter added to PATH for login shells: ${f}"

  # ترمینال گرافیکی اوبونتو/دبیان معمولاً login نیست؛ یک خط idempotent در bash.bashrc
  local marker="# hesabix-flutter-PATH (deploy.sh)"
  if [[ -f /etc/bash.bashrc ]] && ! grep -qF "${marker}" /etc/bash.bashrc 2>/dev/null; then
    printf '\n%s\n[ -r /etc/profile.d/hesabix-flutter.sh ] && . /etc/profile.d/hesabix-flutter.sh\n' "${marker}" >> /etc/bash.bashrc
    log_success "Interactive bash: sourced ${f} from /etc/bash.bashrc."
  fi
}

# After curl, validate .tar.xz (truncated or corrupted transfers can still exit 0).
hesabix_verify_flutter_sdk_tarball() {
  local f="$1"
  local err
  [[ -f "$f" ]] || return 1
  if [[ -n "${FLUTTER_SDK_TARBALL_SHA256:-}" ]]; then
    if printf '%s  %s\n' "${FLUTTER_SDK_TARBALL_SHA256}" "$f" | sha256sum -c --status 2>/dev/null; then
      return 0
    fi
    log_warning "SHA256 mismatch for ${f} (expected FLUTTER_SDK_TARBALL_SHA256 from mirror/docs)."
    return 1
  fi
  err="$(mktemp -t flutter_tar_test.XXXXXX 2>/dev/null || echo /tmp/flutter_tar_test.err)"
  log_info "Verifying tarball integrity (tar -tJf; may take 1-3 min for ~1GB)..."
  if ! tar -tJf "$f" >/dev/null 2>"${err}"; then
    log_warning "Tarball integrity check failed (corrupt or incomplete file). First lines: $(head -3 "${err}" 2>/dev/null | tr '\n' ' ')"
    rm -f "${err}" 2>/dev/null || true
    return 1
  fi
  rm -f "${err}" 2>/dev/null || true
  return 0
}

# Ensure Flutter SDK is available (install if missing). Exports PATH for current shell.
# Must be called after set_flutter_mirror_env so first-run Dart SDK download uses mirror.
# Order: 1) Existing 2) مخزن داخلی (دقیقا FLUTTER_SDK_TARBALL_URL_INTERNAL) 3) Snap 4) Git clone.
ensure_flutter_sdk() {
  local opt_flutter="/opt/flutter/bin"
  local use_mirror=0
  if [[ -n "${FLUTTER_STORAGE_BASE_URL:-}" && "${FLUTTER_STORAGE_BASE_URL}" != *"storage.googleapis.com"* ]]; then
    use_mirror=1
    log_info "Mirror is set (non-Google); /opt/flutter will be preferred for engine downloads."
  fi

  # 1) Use existing Flutter if already available
  # با mirror غیر گوگل فقط /opt/flutter قابل قبول است (snap از storage.googleapis.com دانلود می‌کند و تحریم می‌خورد)
  if [[ $use_mirror -eq 1 ]]; then
    if [[ -x "${opt_flutter}/flutter" ]]; then
      export PATH="${opt_flutter}:$PATH"
      git config --global --add safe.directory /opt/flutter 2>/dev/null || true
      log_info "Using Flutter from ${opt_flutter} (mirror mode; snap ignored so engine uses mirror)"
      return 0
    fi
    log_info "Mirror mode: skipping snap Flutter; will use /opt/flutter (tarball or git clone)."
  else
    if command -v flutter >/dev/null 2>&1; then
      log_info "Flutter found in PATH: $(command -v flutter)"
      return 0
    fi
    if [[ -x "${opt_flutter}/flutter" ]]; then
      export PATH="${opt_flutter}:$PATH"
      git config --global --add safe.directory /opt/flutter 2>/dev/null || true
      log_info "Using Flutter from ${opt_flutter}"
      return 0
    fi
    local snap_bin="$HOME/snap/flutter/current/flutter/bin"
    local snap_bin_common="$HOME/snap/flutter/common/flutter/bin"
    if [[ -d "${snap_bin}" && -x "${snap_bin}/flutter" ]]; then
      export PATH="${snap_bin}:$PATH"
      log_info "Using Flutter from snap (current): ${snap_bin}"
      return 0
    fi
    if [[ -d "${snap_bin_common}" && -x "${snap_bin_common}/flutter" ]]; then
      export PATH="${snap_bin_common}:$PATH"
      log_info "Using Flutter from snap (common): ${snap_bin_common}"
      return 0
    fi
  fi

  # 2) اول: مخزن داخلی (دقیقا همین آدرس) — فقط SDK؛ کتابخانه‌های pub از mirror
  if [[ ! -d /opt/flutter ]]; then
    log_info "Trying Flutter SDK from internal mirror (first): ${FLUTTER_SDK_TARBALL_URL_INTERNAL}"
    apt-get install -y -qq curl xz-utils >/dev/null 2>&1 || true
    local tarball_ok=0
    local flutter_curl_maxtime=()
    if [[ -n "${FLUTTER_SDK_DOWNLOAD_MAX_TIME:-}" && "${FLUTTER_SDK_DOWNLOAD_MAX_TIME}" != "0" ]]; then
      flutter_curl_maxtime=(--max-time "${FLUTTER_SDK_DOWNLOAD_MAX_TIME}")
    fi
    local flutter_curl_http=()
    [[ "${FLUTTER_SDK_CURL_HTTP11:-1}" != "0" ]] && flutter_curl_http=(--http1.1)
    local flutter_tb="/tmp/flutter_sdk.tar.xz"
    local tb_attempt tb_max="${FLUTTER_SDK_TARBALL_ATTEMPTS:-3}"
    [[ "${tb_max}" =~ ^[0-9]+$ ]] && [[ "${tb_max}" -lt 1 ]] && tb_max=1
    [[ "${tb_max}" =~ ^[0-9]+$ ]] || tb_max=3
    for ((tb_attempt = 1; tb_attempt <= tb_max; tb_attempt++)); do
      log_info "Flutter tarball attempt ${tb_attempt}/${tb_max}: download (progress, resume) then verify+extract."
      log_info "curl: connect_timeout=${FLUTTER_SDK_CONNECT_TIMEOUT}s max_time=${FLUTTER_SDK_DOWNLOAD_MAX_TIME:-0}s http1.1=${FLUTTER_SDK_CURL_HTTP11:-1}"
      local flutter_curl_ok=0
      if curl -fL "${flutter_curl_maxtime[@]}" "${flutter_curl_http[@]}" --connect-timeout "${FLUTTER_SDK_CONNECT_TIMEOUT}" \
        --retry 5 --retry-delay 8 --retry-connrefused \
        --progress-bar -C - -o "${flutter_tb}" \
        -w '\n[curl] finished: %{size_download} bytes in %{time_total}s (avg %{speed_download} B/s)\n' \
        "${FLUTTER_SDK_TARBALL_URL_INTERNAL}"; then
        flutter_curl_ok=1
      fi
      if [[ "${flutter_curl_ok}" -ne 1 ]]; then
        log_warning "Download failed (attempt ${tb_attempt}/${tb_max})."
        rm -f "${flutter_tb}"
        continue
      fi
      if ! hesabix_verify_flutter_sdk_tarball "${flutter_tb}"; then
        log_warning "Removing corrupt/incomplete tarball; retrying download (attempt ${tb_attempt}/${tb_max})."
        rm -f "${flutter_tb}"
        continue
      fi
      local tar_xz_err
      tar_xz_err="$(mktemp -t flutter_tar_extract.XXXXXX 2>/dev/null || echo /tmp/flutter_tar_extract.err)"
      if tar -xJf "${flutter_tb}" -C /opt 2>"${tar_xz_err}"; then
        rm -f "${flutter_tb}" "${tar_xz_err}" 2>/dev/null || true
        if [[ -d /opt/flutter && -x /opt/flutter/bin/flutter ]]; then
          tarball_ok=1
        else
          local single_dir
          single_dir=$(ls -1 /opt 2>/dev/null | grep -E '^flutter' | head -1)
          if [[ -n "${single_dir}" && -d "/opt/${single_dir}" && -x "/opt/${single_dir}/bin/flutter" ]]; then
            mv "/opt/${single_dir}" /opt/flutter 2>/dev/null && tarball_ok=1
          fi
        fi
        if [[ $tarball_ok -eq 1 ]]; then
          break
        fi
        log_warning "Tarball verified but Flutter binary not found after extract; cleaning and retrying."
        rm -rf /opt/flutter /opt/flutter_linux* 2>/dev/null || true
        rm -f "${flutter_tb}" 2>/dev/null || true
      else
        log_warning "tar -xJf failed: $(head -5 "${tar_xz_err}" 2>/dev/null | tr '\n' ' ')"
        rm -f "${tar_xz_err}" 2>/dev/null || true
        rm -rf /opt/flutter /opt/flutter_linux* 2>/dev/null || true
        rm -f "${flutter_tb}"
      fi
    done
    if [[ $tarball_ok -eq 0 ]]; then
      log_info "Internal tarball path exhausted after ${tb_max} attempt(s); trying next method."
    fi
    if [[ $tarball_ok -eq 1 ]]; then
      export PATH="/opt/flutter/bin:$PATH"
      git config --global --add safe.directory /opt/flutter 2>/dev/null || true
      log_success "Flutter SDK installed from internal mirror (${FLUTTER_SDK_TARBALL_URL_INTERNAL}). Pub packages will use PUB_HOSTED_URL."
      log_info "Running flutter doctor (first run may download packages from mirror)..."
      if ! flutter doctor -v 2>&1; then
        log_warning "flutter doctor had issues; continuing. Packages will be fetched via mirror during build."
      fi
      log_success "Flutter SDK ready at /opt/flutter."
      return 0
    fi
  fi

  # 3) Official install: snap
  if command -v snap >/dev/null 2>&1 && ! snap list flutter 2>/dev/null | grep -q flutter; then
    log_info "Trying official install: snap install flutter (this may take a few minutes)..."
    if snap install flutter --classic 2>/dev/null; then
      export PATH="/snap/bin:$PATH"
      if command -v flutter >/dev/null 2>&1; then
        log_success "Flutter installed via snap (official)."
        return 0
      fi
    else
      log_info "Snap install failed or unavailable; will try git clone next."
    fi
  fi

  # 4) Git clone to /opt/flutter (official GitHub first, then alternative mirrors)
  log_info "Installing Flutter SDK via git clone..."
  apt-get install -y -qq git curl unzip xz-utils zip libglu1-mesa >/dev/null 2>&1 || true
  if [[ ! -d /opt/flutter ]]; then
    local flutter_cloned=0
    # 4a) Official source first: GitHub
    log_info "Trying to clone Flutter SDK from official source (GitHub)..."
    if git clone --depth 1 --branch stable "https://github.com/flutter/flutter.git" /opt/flutter 2>/dev/null; then
      flutter_cloned=1
      log_success "Flutter SDK cloned from official source (GitHub)."
    fi
    # 2) If official failed, try alternative mirrors
    if [[ $flutter_cloned -eq 0 ]]; then
      log_info "Official source failed; trying alternative mirrors..."
      local flutter_git_urls=()
      [[ -n "${FLUTTER_SDK_GIT_URL:-}" ]] && flutter_git_urls+=("${FLUTTER_SDK_GIT_URL}")
      flutter_git_urls+=(
        "https://mirrors.tuna.tsinghua.edu.cn/git/flutter-sdk.git"
        "https://gitee.com/mirrors/Flutter.git"
      )
      for repo_url in "${flutter_git_urls[@]}"; do
        log_info "Trying alternative: ${repo_url} ..."
        if git clone --depth 1 --branch stable "${repo_url}" /opt/flutter 2>/dev/null; then
          flutter_cloned=1
          log_success "Flutter SDK cloned from alternative: ${repo_url}"
          break
        fi
        rm -rf /opt/flutter 2>/dev/null || true
      done
    fi
    if [[ $flutter_cloned -eq 0 ]]; then
      log_error "Failed to install Flutter SDK (internal tarball, snap, and git clone all failed). Internal URL tried first: ${FLUTTER_SDK_TARBALL_URL_INTERNAL}. For git clone you can set FLUTTER_SDK_GIT_URL. See: https://docs.flutter.dev/get-started/install/linux"
      exit 1
    fi
  else
    (cd /opt/flutter && git fetch --depth 1 origin stable && git reset --hard origin/stable) 2>/dev/null || true
  fi
  export PATH="/opt/flutter/bin:$PATH"
  git config --global --add safe.directory /opt/flutter 2>/dev/null || true
  if ! command -v flutter >/dev/null 2>&1; then
    log_error "Flutter binary not found after install. Check /opt/flutter/bin."
    exit 1
  fi
  log_info "Running flutter doctor (first run may download Dart SDK from mirror)..."
  if ! flutter doctor -v 2>&1; then
    log_warning "flutter doctor had issues; continuing. If build fails, check f.mirror.hesabix.ir and hesabixAPI/f.mirror.hesabix.ir.conf."
  fi
  log_success "Flutter SDK ready at /opt/flutter."
}

# On low-RAM servers, add swap so Flutter/dart2js build is not OOM-killed (exit -9).
ensure_swap_for_flutter_build() {
  local total_mb avail_mb avail_kb
  if [[ -r /proc/meminfo ]]; then
    total_mb=$(awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo)
    avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    if [[ -n "${avail_kb}" ]] && [[ "${avail_kb}" =~ ^[0-9]+$ ]]; then
      avail_mb=$((avail_kb / 1024))
    else
      avail_mb=$(free -m 2>/dev/null | awk '/^Mem:/ {print $7}')
    fi
  else
    total_mb=$(free -m 2>/dev/null | awk '/^Mem:/ {print $2}')
    avail_mb=$(free -m 2>/dev/null | awk '/^Mem:/ {print $7}')
  fi
  total_mb=${total_mb:-0}
  avail_mb=${avail_mb:-0}
  if [ "${total_mb}" -lt 2500 ] || [ "${avail_mb}" -lt 1000 ]; then
    local swapfile="${APP_ROOT}/swap.flutter.bin"
    # On <2.5GB RAM use 2.5GB swap so dart compile js can finish
    local swap_mb=2560
    [ "${total_mb:-0}" -ge 2500 ] && swap_mb=1536
    local swap_bytes=$((swap_mb * 1024 * 1024))
    if [ ! -f "$swapfile" ] || [ "$(stat -c%s "$swapfile" 2>/dev/null)" -lt "$swap_bytes" ]; then
      log_info "Low memory (total ${total_mb}MB, available ${avail_mb}MB). Creating ${swap_mb}MB swap for Flutter build..."
      dd if=/dev/zero of="$swapfile" bs=1M count="$swap_mb" status=none 2>/dev/null || true
      chmod 600 "$swapfile"
      mkswap "$swapfile" 2>/dev/null || true
    fi
    swapon "$swapfile" 2>/dev/null || true
  fi
}

install_flutter_and_build_frontend() {
  log_step "Building Flutter frontend..."
  set_flutter_mirror_env
  ensure_flutter_sdk
  ensure_swap_for_flutter_build
  export PATH="/opt/flutter/bin:/snap/bin:$PATH"
  if ! command -v flutter >/dev/null 2>&1; then
    log_error "Flutter not in PATH after ensure_flutter_sdk. PATH=$PATH"
    exit 1
  fi
  persist_flutter_path_in_profile_d

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

  local api_scheme
  api_scheme="$(hesabix_resolve_api_public_scheme)"
  local api_url="${api_scheme}://${API_DOMAIN}"

  echo "Building Flutter web with:"
  echo "  Mode: release"
  echo "  API URL: ${api_url} (scheme from TLS detection or API_PUBLIC_SCHEME)"
  echo "  Output: /var/www/${UI_DOMAIN}"
  echo
  echo "$CHECK_MARK Flutter build uses Hesabix mirror: f.mirror.hesabix.ir"

  cd "${app_dir}"
  log_info "Building Flutter web (pub/storage via ${PUB_HOSTED_URL})"
  if ! env PATH="/opt/flutter/bin:/snap/bin:$PATH" \
      PUB_HOSTED_URL="${PUB_HOSTED_URL}" FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL}" \
      bash build_web.sh \
    --mode release \
    --api-base-url "${api_url}" \
    --clean \
    --install-deps; then
    log_error "Flutter build failed. Check network, DNS, and f.mirror.hesabix.ir (see hesabixAPI/f.mirror.hesabix.ir.conf)."
    exit 1
  fi
  log_success "Flutter web build succeeded"
  
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
# OPTIONS (CORS preflight) را در سهمیه نمی‌گذارد؛ هر XHR معمولاً OPTIONS + METHOD است.
map \$request_method \$api_limit_key {
	default  \$binary_remote_addr;
	OPTIONS  "";
}

limit_req_zone \$api_limit_key zone=api_limit:10m rate=40r/s;
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

  # روت ریشه (اطلاعات سرویس و نسخه)
  location = / {
    proxy_pass http://127.0.0.1:8000;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
  }

  # لینک اشتراک عمومی: /p/{code} → بک‌اند (ریدایرکت ۳۰۷)
  location /p/ {
    proxy_pass http://127.0.0.1:8000/p/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 30;
    proxy_connect_timeout 10;
    proxy_send_timeout 30;
  }

  # لینک اشتراک فاکتور/سند: /i/{code} → بک‌اند (ریدایرکت ۳۰۷ به /public/invoice-link/ در Flutter)
  location /i/ {
    proxy_pass http://127.0.0.1:8000/i/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 30;
    proxy_connect_timeout 10;
    proxy_send_timeout 30;
  }

  # وقتی API و UI روی یک دامنه هستند: مسیرهای /public/ را از روت UI سرو کن (SPA)
  # fallback با named location تا /index.html به location / { return 404; } نخورد
  location /public/ {
    root /var/www/${UI_DOMAIN};
    try_files \$uri \$uri/ @hesabix_public_spa;
  }
  location @hesabix_public_spa {
    root /var/www/${UI_DOMAIN};
    rewrite ^ /index.html break;
  }

  # Swagger / OpenAPI از بک‌اند (^~ برای /docs/* مثل oauth2-redirect؛ /docs-custom زیر همین پیشوند است)
  location ^~ /docs {
    proxy_pass http://127.0.0.1:8000;
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
  }

  location = /openapi.json {
    proxy_pass http://127.0.0.1:8000;
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
  }

  location ^~ /redoc {
    proxy_pass http://127.0.0.1:8000;
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
  }

  # /assets وب Flutter (فونت MaterialIcons، shaders، …) نباید همیشه به API پروکسی شود؛
  # وگرنه وقتی API_DOMAIN و UI_DOMAIN یکی‌اند (ادغام server در nginx)، آیکن‌ها و دارایی‌های استاتیک وب خالی/۴۰۴ می‌شوند.
  location ^~ /assets/swagger/ {
    proxy_pass http://127.0.0.1:8000;
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
  }

  location = /assets/logo-blue.png {
    proxy_pass http://127.0.0.1:8000;
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
  }

  location ^~ /assets/icons/ {
    proxy_pass http://127.0.0.1:8000;
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
  }

  location /assets/ {
    root /var/www/${UI_DOMAIN};
    try_files \$uri \$uri/ @hesabix_api_assets_fallback;
  }
  location @hesabix_api_assets_fallback {
    proxy_pass http://127.0.0.1:8000;
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
  }

  location / {
    return 404;
  }

  # چت وب عمومی: نرخ فقط در اپ (جدول firewall_rate_policies)
  location /api/v1/public/crm-chat/ {
    proxy_pass http://127.0.0.1:8000/api/v1/public/crm-chat/;
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
    client_max_body_size 1g;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }

  location /api/ {
    limit_req zone=api_limit burst=120 nodelay;
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
    client_max_body_size 1g;
    
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }

  # WebSocket endpoints (/ws/notifications, /ws/ai/voice, etc.)
  location /ws/ {
    proxy_pass http://127.0.0.1:8000/ws/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 86400;
    proxy_send_timeout 86400;
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

  # لینک اشتراک عمومی: /p/{code} → بک‌اند (ریدایرکت ۳۰۷)
  location /p/ {
    proxy_pass http://127.0.0.1:8000/p/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 30;
    proxy_connect_timeout 10;
    proxy_send_timeout 30;
  }

  # لینک اشتراک فاکتور: /i/{code} → بک‌اند (ریدایرکت ۳۰۷)
  location /i/ {
    proxy_pass http://127.0.0.1:8000/i/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 30;
    proxy_connect_timeout 10;
    proxy_send_timeout 30;
  }

  # Proxy /api/ and /ws/ to backend (when API and UI share same domain)
  location /api/ {
    proxy_pass http://127.0.0.1:8000/api/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_read_timeout 300;
    proxy_send_timeout 300;
    client_max_body_size 1g;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }
  location /ws/ {
    proxy_pass http://127.0.0.1:8000/ws/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_read_timeout 86400;
    proxy_send_timeout 86400;
  }

  # همان دامنهٔ UI+API (hsxn): بدون این بلوک، /docs به try_files می‌خورد و index.html Flutter برمی‌گردد.
  # فقط زیرمسیر /assets/swagger/ و لوگوی مستندات به بک‌اند می‌رود تا با assets وب Flutter تداخل نگیرد.
  location ^~ /docs {
    proxy_pass http://127.0.0.1:8000;
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
  }

  location = /openapi.json {
    proxy_pass http://127.0.0.1:8000;
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
  }

  location ^~ /redoc {
    proxy_pass http://127.0.0.1:8000;
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
  }

  location ^~ /assets/swagger/ {
    proxy_pass http://127.0.0.1:8000;
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
  }

  location = /assets/logo-blue.png {
    proxy_pass http://127.0.0.1:8000;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
  }

  location ^~ /assets/icons/ {
    proxy_pass http://127.0.0.1:8000;
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
  }

  # SPA: مسیرهای عمومی (لینک اشتراک و غیره) → index.html
  location /public/ {
    try_files \$uri \$uri/ /index.html;
  }

  # نسخهٔ build (همیشه تازه؛ پایهٔ تشخیص به‌روزرسانی در کلاینت)
  location = /version.json {
    add_header Cache-Control "no-store" always;
    expires off;
    try_files \$uri =404;
  }

  # Service Worker نباید با immutable یک‌ساله قفل شود
  location = /flutter_service_worker.js {
    add_header Cache-Control "no-cache, must-revalidate" always;
    expires off;
    try_files \$uri =404;
  }

  # نام فایل‌های ورودی Flutter معمولاً ثابت است؛ کش یک‌ساله immutable باعث اجرای JS قدیمی پس از دیپلوی می‌شود
  location = /flutter_bootstrap.js {
    add_header Cache-Control "no-cache, must-revalidate" always;
    expires off;
    try_files \$uri =404;
  }

  location = /main.dart.js {
    add_header Cache-Control "no-cache, must-revalidate" always;
    expires off;
    try_files \$uri =404;
  }

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
    
    if ! command -v certbot >/dev/null 2>&1; then
      if ! apt-get install -y certbot python3-certbot-nginx; then
        log_error "Failed to install certbot (API SSL)."
        return 1
      fi
    fi
    
    : "${CERTBOT_EMAIL:=admin@${API_DOMAIN}}"
    if [[ -z "${CERTBOT_EMAIL}" ]] || [[ "${CERTBOT_EMAIL}" == "admin@${API_DOMAIN}" ]]; then
      read -rp "Email for SSL certificate (default: admin@${API_DOMAIN}): " input_email
      CERTBOT_EMAIL=${input_email:-admin@${API_DOMAIN}}
    fi
    
    if [[ ! "${CERTBOT_EMAIL}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
      echo "$WARNING_MARK Invalid email format. Using default: admin@${API_DOMAIN}"
      CERTBOT_EMAIL="admin@${API_DOMAIN}"
    fi
    
    if certbot --nginx -d "${API_DOMAIN}" --redirect --non-interactive --agree-tos -m "${CERTBOT_EMAIL}" 2>&1; then
      echo "$CHECK_MARK SSL/TLS enabled for API domain."
      systemctl enable certbot.timer 2>/dev/null || true
      systemctl start certbot.timer 2>/dev/null || true
      echo "$CHECK_MARK SSL certificate auto-renewal enabled."
      return 0
    else
      echo "$WARNING_MARK Error issuing SSL certificate for API domain. You can run manually later:"
      echo "  certbot --nginx -d ${API_DOMAIN}"
      return 1
    fi
  else
    echo "SSL/TLS skipped for API domain; you can run certbot later:"
    echo "  certbot --nginx -d ${API_DOMAIN}"
    return 0
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
    
    if ! command -v certbot >/dev/null 2>&1; then
      if ! apt-get install -y certbot python3-certbot-nginx; then
        log_error "Failed to install certbot (UI SSL)."
        return 1
      fi
    fi
    
    : "${CERTBOT_EMAIL:=admin@${UI_DOMAIN}}"
    if [[ -z "${CERTBOT_EMAIL}" ]] || [[ "${CERTBOT_EMAIL}" == "admin@${UI_DOMAIN}" ]]; then
      read -rp "Email for SSL certificate (default: admin@${UI_DOMAIN}): " input_email
      CERTBOT_EMAIL=${input_email:-admin@${UI_DOMAIN}}
    fi
    
    if [[ ! "${CERTBOT_EMAIL}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
      echo "$WARNING_MARK Invalid email format. Using default: admin@${UI_DOMAIN}"
      CERTBOT_EMAIL="admin@${UI_DOMAIN}"
    fi
    
    if certbot --nginx -d "${UI_DOMAIN}" --redirect --non-interactive --agree-tos -m "${CERTBOT_EMAIL}" 2>&1; then
      echo "$CHECK_MARK SSL/TLS enabled for UI domain."
      if ! systemctl is-enabled certbot.timer >/dev/null 2>&1; then
        systemctl enable certbot.timer 2>/dev/null || true
        systemctl start certbot.timer 2>/dev/null || true
        echo "$CHECK_MARK SSL certificate auto-renewal enabled."
      fi
      return 0
    else
      echo "$WARNING_MARK Error issuing SSL certificate for UI domain. You can run manually later:"
      echo "  certbot --nginx -d ${UI_DOMAIN}"
      return 1
    fi
  else
    echo "SSL/TLS skipped for UI domain; you can run certbot later:"
    echo "  certbot --nginx -d ${UI_DOMAIN}"
    return 0
  fi
}

install_pgadmin4() {
  echo ">> Installing pgAdmin4 (Nginx + Gunicorn, no Apache)..."
  
  local pgadmin_venv="/opt/pgadmin4/venv"
  local pgadmin_data="/var/lib/pgadmin4"
  local pgadmin_log="/var/log/pgadmin4"
  
  if [[ -x "${pgadmin_venv}/bin/gunicorn" ]] && [[ -d "${pgadmin_venv}/lib" ]]; then
    echo "$CHECK_MARK pgAdmin4 (Gunicorn) is already installed. Skipping..."
    return 0
  fi
  
  configure_pip_hesabix_mirror
  set_pip_mirror_env
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y -qq python3-venv python3-pip libpq-dev >/dev/null 2>&1
  
  mkdir -p /opt/pgadmin4
  if [[ ! -d "${pgadmin_venv}" ]]; then
    echo "Creating Python venv for pgAdmin4..."
    python3 -m venv "${pgadmin_venv}"
    log_info "Installing pgAdmin4 from PyPI: ${PIP_INDEX_URL}"
    if "${pgadmin_venv}/bin/pip" install -U pip -q && "${pgadmin_venv}/bin/pip" install pgadmin4 gunicorn -q; then
      log_success "pgAdmin4 installed from ${PIP_INDEX_URL}"
    else
      log_error "Failed to install pgAdmin4 from ${PIP_INDEX_URL}. Check mirror reachability or PIP_INDEX_URL override."
      return 1
    fi
  fi
  
  mkdir -p "${pgadmin_data}"/{sessions,storage,azurecredentialcache,kerberoscache}
  mkdir -p "${pgadmin_log}"
  chown -R www-data:www-data "${pgadmin_data}" "${pgadmin_log}"
  
  local pgadmin_site
  pgadmin_site=$("${pgadmin_venv}/bin/python3" -c "import pgadmin4; print(pgadmin4.__path__[0])" 2>/dev/null)
  if [[ -z "$pgadmin_site" || ! -d "$pgadmin_site" ]]; then
    echo "$CROSS_MARK Could not find pgAdmin4 package path."
    return 1
  fi
  
  # config_local.py for server mode
  cat > "${pgadmin_site}/config_local.py" <<CONFIG
SERVER_MODE = True
LOG_FILE = '${pgadmin_log}/pgadmin4.log'
SQLITE_PATH = '${pgadmin_data}/pgadmin4.db'
SESSION_DB_PATH = '${pgadmin_data}/sessions'
STORAGE_DIR = '${pgadmin_data}/storage'
AZURE_CREDENTIAL_CACHE_DIR = '${pgadmin_data}/azurecredentialcache'
KERBEROS_CCACHE_DIR = '${pgadmin_data}/kerberoscache'
CONFIG
  chown www-data:www-data "${pgadmin_site}/config_local.py"
  
  # Setup database (must run as www-data)
  if [[ ! -f "${pgadmin_data}/pgadmin4.db" ]]; then
    echo "Initializing pgAdmin4 database..."
    sudo -u www-data "${pgadmin_venv}/bin/python3" "${pgadmin_site}/setup.py" setup-db 2>/dev/null || true
  fi
  
  # Systemd service: Gunicorn (single worker as required by pgAdmin for connection affinity)
  cat > /etc/systemd/system/pgadmin4.service <<UNIT
[Unit]
Description=pgAdmin4 (Gunicorn)
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=${pgadmin_site}
Environment="PATH=${pgadmin_venv}/bin"
ExecStart=${pgadmin_venv}/bin/gunicorn --bind 127.0.0.1:5050 --workers 1 --threads 25 --timeout 300 pgAdmin4:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
  
  systemctl daemon-reload
  
  # Stop if already running so the new unit definition is used on next start
  if check_service pgadmin4; then
    systemctl stop pgadmin4
  fi
  
  systemctl enable pgadmin4
  systemctl start pgadmin4
  
  if [[ -n "${PGADMIN4_EMAIL}" ]] && [[ -n "${PGADMIN4_PASSWORD}" ]]; then
    echo "  First login: open https://${PGADMIN4_DOMAIN:-pgadmin.example.com} and register with email: ${PGADMIN4_EMAIL}"
  fi
  echo "$CHECK_MARK pgAdmin4 installed (Gunicorn on 127.0.0.1:5050). Nginx will proxy to it."
}

configure_nginx_pgadmin4() {
  echo ">> Configuring Nginx for pgAdmin4..."
  
  if [[ -z "${PGADMIN4_DOMAIN}" ]]; then
    echo "$WARNING_MARK pgAdmin4 domain not set. Skipping Nginx configuration."
    return 1
  fi
  
  if ! command -v nginx >/dev/null 2>&1; then
    echo "$CROSS_MARK Nginx is not installed"
    return 1
  fi
  
  if ! systemctl is-active --quiet pgadmin4; then
    echo "Starting pgAdmin4 (Gunicorn) service..."
    systemctl start pgadmin4
    systemctl enable pgadmin4
  fi
  
  # Nginx reverse proxy to Gunicorn (no Apache)
  cat > /etc/nginx/sites-available/pgadmin4.conf <<NGINX
# pgAdmin4 (reverse proxy to Gunicorn on 127.0.0.1:5050)
server {
  listen 80;
  server_name ${PGADMIN4_DOMAIN};

  add_header X-Frame-Options "SAMEORIGIN" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-XSS-Protection "1; mode=block" always;
  add_header Referrer-Policy "strict-origin-when-cross-origin" always;

  location / {
    proxy_pass http://127.0.0.1:5050;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_redirect off;
    proxy_read_timeout 300;
    proxy_connect_timeout 60;
    proxy_send_timeout 300;
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
    return 0
  fi
  
  : "${ENABLE_PGADMIN4_SSL:=}"
  if [[ -z "${ENABLE_PGADMIN4_SSL}" ]]; then
    echo
    read -rp "Enable SSL/TLS for pgAdmin4 domain (${PGADMIN4_DOMAIN}) with Let's Encrypt? (y/N): " ENABLE_PGADMIN4_SSL
    ENABLE_PGADMIN4_SSL=${ENABLE_PGADMIN4_SSL:-N}
  fi
  
  if [[ "${ENABLE_PGADMIN4_SSL}" =~ ^[Yy]$ ]]; then
    echo ">> Installing and configuring TLS for pgAdmin4..."
    
    if ! command -v certbot >/dev/null 2>&1; then
      if ! apt-get install -y certbot python3-certbot-nginx; then
        log_error "Failed to install certbot (pgAdmin4 SSL)."
        return 1
      fi
    fi
    
    : "${CERTBOT_EMAIL:=${PGADMIN4_EMAIL:-admin@${PGADMIN4_DOMAIN}}}"
    if [[ -z "${CERTBOT_EMAIL}" ]] || [[ "${CERTBOT_EMAIL}" == "admin@${PGADMIN4_DOMAIN}" ]]; then
      read -rp "Email for SSL certificate (default: ${CERTBOT_EMAIL}): " input_email
      CERTBOT_EMAIL=${input_email:-${CERTBOT_EMAIL}}
    fi
    
    if [[ ! "${CERTBOT_EMAIL}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
      echo "$WARNING_MARK Invalid email format. Using default: ${PGADMIN4_EMAIL:-admin@${PGADMIN4_DOMAIN}}"
      CERTBOT_EMAIL="${PGADMIN4_EMAIL:-admin@${PGADMIN4_DOMAIN}}"
    fi
    
    if certbot --nginx -d "${PGADMIN4_DOMAIN}" --redirect --non-interactive --agree-tos -m "${CERTBOT_EMAIL}" 2>&1; then
      echo "$CHECK_MARK SSL/TLS enabled for pgAdmin4 domain."
      if ! systemctl is-enabled certbot.timer >/dev/null 2>&1; then
        systemctl enable certbot.timer 2>/dev/null || true
        systemctl start certbot.timer 2>/dev/null || true
        echo "$CHECK_MARK SSL certificate auto-renewal enabled."
      fi
      return 0
    else
      echo "$WARNING_MARK Error issuing SSL certificate for pgAdmin4 domain. You can run manually later:"
      echo "  certbot --nginx -d ${PGADMIN4_DOMAIN}"
      return 1
    fi
  else
    echo "SSL/TLS skipped for pgAdmin4 domain; you can run certbot later:"
    echo "  certbot --nginx -d ${PGADMIN4_DOMAIN}"
    return 0
  fi
}

main() {
  if [[ $EUID -ne 0 ]]; then
    echo "$CROSS_MARK Please run this script with root privileges (e.g. sudo bash deploy.sh)."
    exit 1
  fi

  # Unattended apt: avoid needrestart restarting services at end of install (fwupd-refresh etc.
  # often fail or hang on minimal/headless servers; unrelated to Hesabix). Override: NEEDRESTART_SUSPEND=0
  export DEBIAN_FRONTEND=noninteractive
  export APT_LISTCHANGES_FRONTEND=none
  export NEEDRESTART_SUSPEND="${NEEDRESTART_SUSPEND:-1}"
  
  # Initialize log file
  init_log_file
  
  # Check OS compatibility (must be Debian/Ubuntu)
  check_os_compatibility
  
  # حداقل RAM برای نصب (قبل از لایسنس تا وقت کاربر هدر نرود)
  check_minimum_ram
  
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
  
  # Check if port 8000 is in use (ss preferred; netstat optional)
  if command -v ss >/dev/null 2>&1; then
    if ss -tuln | grep -qE ':8000(\s|$)'; then
      log_warning "Port 8000 is in use. You may need to stop the previous service."
    fi
  elif command -v netstat >/dev/null 2>&1; then
    if netstat -tuln | grep -q ":8000 "; then
      log_warning "Port 8000 is in use. You may need to stop the previous service."
    fi
  fi
  
  # Load saved inputs from previous run (so re-run after failure doesn't require re-entering)
  load_saved_deploy_vars
  if [[ -f "${APP_ROOT}/.deploy_saved_vars" ]]; then
    echo "Loaded saved defaults from a previous run (domains, branch, pgAdmin4, etc.)."
    echo "To override: set environment variables (e.g. API_DOMAIN=api.example.com) or press Enter at each prompt to be asked again."
    echo
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
  
  # Clone repository (skip if already done; resume will retry from here if previous run failed after repo)
  if ! check_step_completed "repo"; then
    clone_repo
    mark_step_completed "repo"
  else
    echo "$CHECK_MARK Repository already cloned/updated. Skipping..."
  fi
  echo
  
  # Setup database (idempotent)
  if ! check_step_completed "db"; then
    setup_db
    mark_step_completed "db"
  else
    echo "$CHECK_MARK Database already configured. Skipping..."
  fi
  echo
  
  # Deploy backend (skip if already done; resume from here if previous run failed during/after backend)
  if ! check_step_completed "backend"; then
    deploy_backend
    mark_step_completed "backend"
  else
    echo "$CHECK_MARK Backend already deployed. Skipping..."
  fi
  echo
  
  # Configure Nginx API (skip if already done)
  if ! check_step_completed "nginx_api"; then
    configure_nginx_api
    mark_step_completed "nginx_api"
  else
    echo "$CHECK_MARK Nginx for API already configured. Skipping..."
  fi
  echo
  
  # Configure Nginx UI (skip if already done)
  if ! check_step_completed "nginx_ui"; then
    configure_nginx_ui
    mark_step_completed "nginx_ui"
  else
    echo "$CHECK_MARK Nginx for UI already configured. Skipping..."
  fi
  echo
  
  # Configure SSL API (mark done only on success or explicit skip — not on certbot failure)
  if ! check_step_completed "ssl_api"; then
    if configure_api_ssl; then
      mark_step_completed "ssl_api"
    else
      log_warning "API SSL step incomplete; re-run deploy.sh to retry Let's Encrypt for ${API_DOMAIN}."
    fi
  else
    echo "$CHECK_MARK SSL for API already configured. Skipping..."
  fi
  echo

  # Build frontend after API TLS attempt so dart-define matches http vs https (see scripts/api_public_scheme.sh).
  if ! check_step_completed "frontend"; then
    install_flutter_and_build_frontend
    mark_step_completed "frontend"
  else
    echo "$CHECK_MARK Frontend already built and deployed. Skipping..."
    persist_flutter_path_in_profile_d
  fi
  echo
  
  if ! check_step_completed "ssl_ui"; then
    if configure_ui_ssl; then
      mark_step_completed "ssl_ui"
    else
      log_warning "UI SSL step incomplete; re-run deploy.sh to retry Let's Encrypt for ${UI_DOMAIN}."
    fi
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
      if configure_pgadmin4_ssl; then
        mark_step_completed "ssl_pgadmin4"
      else
        log_warning "pgAdmin4 SSL step incomplete; re-run deploy.sh to retry Let's Encrypt for ${PGADMIN4_DOMAIN}."
      fi
    else
      echo "$CHECK_MARK SSL for pgAdmin4 already configured. Skipping..."
    fi
    echo
  fi
  
  # Save config and install hesabix command for future updates
  install_hesabix_command
  echo
  
  # Clear state file on successful completion
  clear_deployment_state
  
  echo "=========================================="
  log_success "Deployment completed!"
  echo "=========================================="
  echo
  log_info "Access URLs:"
  local _api_s _ui_s
  _api_s="$(hesabix_resolve_api_public_scheme)"
  if [[ -d "/etc/letsencrypt/live/${UI_DOMAIN}" ]]; then _ui_s=https; else _ui_s=http; fi
  echo "  API:  ${_api_s}://${API_DOMAIN}/api/v1/health"
  echo "  UI:   ${_ui_s}://${UI_DOMAIN}/"
  if [[ "${INSTALL_PGADMIN4}" =~ ^[Yy]$ ]] && [[ -n "${PGADMIN4_DOMAIN}" ]]; then
    if [[ -d "/etc/letsencrypt/live/${PGADMIN4_DOMAIN}" ]]; then
      echo "  pgAdmin4: https://${PGADMIN4_DOMAIN}/"
    else
      echo "  pgAdmin4: http://${PGADMIN4_DOMAIN}/"
    fi
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
  log_info "To update (pull, migrate, rebuild, restart):"
  echo "  sudo hesabix -update"
  echo "  sudo hesabix -update -source https://source.hesabix.ir/hesabix/arc.git   # override repo"
  echo "  sudo hesabix -cli reload                              # update /usr/local/bin/hesabix from repo"
  echo
  log_info "To start/stop/restart all Hesabix app services (systemd):"
  echo "  sudo hesabix -services start"
  echo "  sudo hesabix -services stop"
  echo "  sudo hesabix -services restart"
  echo "  sudo hesabix -services status"
  echo
  log_info "To re-run deploy (resume from last step or full upgrade):"
  echo "  BRANCH=${BRANCH} API_DOMAIN=${API_DOMAIN} UI_DOMAIN=${UI_DOMAIN} sudo -E bash deploy.sh"
  echo "  (Use RESET_STATE=y to run all steps from the beginning)"
  echo
  log_info "Database password is stored in:"
  echo "  ${APP_ROOT}/.db_password"
  echo
}

main "$@"


