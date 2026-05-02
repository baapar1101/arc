#!/usr/bin/env bash
# Hesabix update script: pull from repo, migrate backend, restart services, rebuild frontend, reload nginx.
# pip: Hesabix mirror only (https://p.mirror.hesabix.ir/simple) — configure_pip_hesabix_mirror before backend pip install. Nginx نصب: scripts/install_pip_mirror_nginx.sh
# Flutter: فقط f.mirror.hesabix.ir (pub + gcs) — hesabixAPI/f.mirror.hesabix.ir.conf
# Run via: hesabix -update [-source URL] [-branch NAME]
# Requires: API_DOMAIN, UI_DOMAIN, BRANCH, REPO_URL in env or in ${APP_ROOT}/.deploy_env
# آدرس API در بیلد وب: https اگر /etc/letsencrypt/live/<API_DOMAIN> وجود داشته باشد؛ وگرنه http مگر API_PUBLIC_SCHEME در محیط ست شود (TLS سفارشی).
set -euo pipefail

APP_ROOT="${APP_ROOT:-/opt/hesabix}"
LOG_FILE="${APP_ROOT}/update.log"
CHECK_MARK=$'\xE2\x9C\x94'
CROSS_MARK=$'\xE2\x9D\x8C'

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
log_ok()   { echo "${CHECK_MARK} $*" | tee -a "${LOG_FILE}"; }
log_err()  { echo "${CROSS_MARK} $*" >&2; echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "${LOG_FILE}"; }

# اگر checkout/pull معمولی شکست بخورد (فایل جنریت لوکال، merge، شاخهٔ منحرف)، کلون را با remote هم‌راستا می‌کند.
hesabix_force_sync_origin() {
  log_info "هم‌راستاسازی اجباری با origin/${BRANCH}: git reset --hard (تغییرات و commitهای لوکال این clone از بین می‌روند)."
  git fetch origin --prune
  if ! git show-ref -q "origin/${BRANCH}"; then
    log_err "origin/${BRANCH} بعد از fetch پیدا نشد."
    return 1
  fi
  if git show-ref -q "refs/heads/${BRANCH}"; then
    git checkout -f "${BRANCH}"
  else
    git checkout -b "${BRANCH}" "origin/${BRANCH}"
  fi
  if ! git reset --hard "origin/${BRANCH}"; then
    log_err "git reset --hard origin/${BRANCH} ناموفق بود."
    return 1
  fi
  return 0
}

# همان منطق deploy.sh: PATH فلاتر برای شِل‌های جدید (/etc/profile.d + خط idempotent در bash.bashrc)
persist_flutter_path_in_profile_d() {
  local f="/etc/profile.d/hesabix-flutter.sh"
  if [[ ! -x /opt/flutter/bin/flutter && ! -x /snap/bin/flutter ]]; then
    return 0
  fi
  cat > "${f}" <<'PROFILE'
# Hesabix: Flutter در PATH برای شِل‌های login (deploy.sh / update.sh) — ترجیحاً دستی ویرایش نشود.
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
  log_ok "Flutter برای شِل‌های login در PATH: ${f}"

  local marker="# hesabix-flutter-PATH (deploy.sh)"
  if [[ -f /etc/bash.bashrc ]] && ! grep -qF "${marker}" /etc/bash.bashrc 2>/dev/null; then
    printf '\n%s\n[ -r /etc/profile.d/hesabix-flutter.sh ] && . /etc/profile.d/hesabix-flutter.sh\n' "${marker}" >> /etc/bash.bashrc
    log_ok "شِل تعاملی bash: منبع ${f} به /etc/bash.bashrc اضافه شد."
  fi
}

configure_pip_hesabix_mirror() {
  if ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi
  python3 -m pip config --user set global.index "https://p.mirror.hesabix.ir/simple" 2>/dev/null || true
  python3 -m pip config --user set global.index-url "https://p.mirror.hesabix.ir/simple" 2>/dev/null || true
  python3 -m pip config --user set global.trusted-host "p.mirror.hesabix.ir" 2>/dev/null || true
  log_info "pip user config: Hesabix PyPI (p.mirror.hesabix.ir/simple)"
}

if [[ $EUID -ne 0 ]]; then
  log_err "Please run as root (e.g. sudo hesabix -update)"
  exit 1
fi

if [[ ! -d "${APP_ROOT}/app/.git" ]]; then
  log_err "Hesabix app not found at ${APP_ROOT}/app. Run deploy.sh first."
  exit 1
fi

# Load saved config if not in env
if [[ -z "${API_DOMAIN:-}" ]] && [[ -f "${APP_ROOT}/.deploy_env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${APP_ROOT}/.deploy_env"
  set +a
fi

for v in API_DOMAIN UI_DOMAIN BRANCH REPO_URL; do
  if [[ -z "${!v:-}" ]]; then
    log_err "Missing $v. Set it in env or in ${APP_ROOT}/.deploy_env"
    exit 1
  fi
done

if [[ ! -f "${APP_ROOT}/.db_password" ]]; then
  log_err "Missing ${APP_ROOT}/.db_password"
  exit 1
fi
DB_PASSWORD=$(cat "${APP_ROOT}/.db_password")
export DB_PASSWORD

echo "==========================================" | tee -a "${LOG_FILE}"
log_info "Hesabix update started (repo=${REPO_URL}, branch=${BRANCH})"
echo "==========================================" | tee -a "${LOG_FILE}"

# --- 1. Update from repo ---
log_info "Step 1: Updating source from repository..."
cd "${APP_ROOT}/app"
current_remote=$(git remote get-url origin 2>/dev/null || true)
if [[ "${current_remote}" != "${REPO_URL}" ]]; then
  git remote set-url origin "${REPO_URL}"
fi
git fetch origin --prune
if ! git show-ref -q "origin/${BRANCH}"; then
  log_err "شاخه origin/${BRANCH} روی remote نیست. BRANCH و REPO_URL را در ${APP_ROOT}/.deploy_env بررسی کنید."
  exit 1
fi
if git checkout -B "${BRANCH}" "origin/${BRANCH}" && git pull origin "${BRANCH}" --ff-only; then
  :
else
  log_info "به‌روزرسانی معمولی Git ناموفق (مثلاً تغییرات محلی یا هم‌نشانی نشدن شاخه). در حال بازیابی با reset --hard..."
  if ! hesabix_force_sync_origin; then
    exit 1
  fi
fi
log_ok "Source updated."

# --- 2. Backend: pip, migrations, restart services ---
log_info "Step 2: Backend – install deps, migrations, restart services..."
configure_pip_hesabix_mirror
api_dir="${APP_ROOT}/app/hesabixAPI"
if [[ ! -d "${api_dir}/.venv" ]]; then
  log_err "Backend venv not found. Run full deploy first."
  exit 1
fi
cd "${api_dir}"
# shellcheck disable=SC1091
source .venv/bin/activate
export PIP_INDEX_URL="${PIP_INDEX_URL:-https://p.mirror.hesabix.ir/simple}"
export PIP_TRUSTED_HOST="${PIP_TRUSTED_HOST:-p.mirror.hesabix.ir}"
pip install --upgrade pip setuptools wheel -q
pip install -e . -q
# Ensure alembic_version.version_num is VARCHAR(255) for long revision IDs (fixes StringDataRightTruncation)
log_info "Ensuring alembic_version schema compatibility..."
PGPASSWORD="${DB_PASSWORD}" psql -h 127.0.0.1 -U hesabix -d hesabix -tAc "
  DO \$\$
  BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='alembic_version') THEN
      ALTER TABLE public.alembic_version ALTER COLUMN version_num TYPE VARCHAR(255);
    ELSE
      CREATE TABLE public.alembic_version (version_num VARCHAR(255) PRIMARY KEY);
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL;
  END \$\$;
" 2>/dev/null || true
log_info "Running Alembic migrations..."
if ! alembic upgrade head; then
  log_err "Migrations failed."
  exit 1
fi
log_ok "Migrations done."
chown -R www-data:www-data "${api_dir}"
systemctl daemon-reload
systemctl restart hesabix-api hesabix-rq-worker hesabix-notification-moderation
sleep 3
for svc in hesabix-api; do
  if ! systemctl is-active --quiet "$svc"; then
    log_err "Service $svc failed to start. Check: journalctl -u $svc"
    exit 1
  fi
done
log_ok "Backend services restarted."

# --- 3. Flutter: update SDK, build web, deploy (PATH دائمی: /etc/profile.d/hesabix-flutter.sh) ---
log_info "Step 3: Flutter – update SDK, build web, deploy..."
export PATH="/opt/flutter/bin:/snap/bin:${PATH:-}"
if [[ -d /opt/flutter ]]; then
  (cd /opt/flutter && git fetch --depth 1 origin stable 2>/dev/null && git reset --hard origin/stable 2>/dev/null) || true
fi
if ! command -v flutter >/dev/null 2>&1; then
  log_err "Flutter not in PATH. Ensure Flutter is installed (e.g. run deploy.sh once)."
  exit 1
fi
persist_flutter_path_in_profile_d
export PUB_HOSTED_URL="https://f.mirror.hesabix.ir/pub"
export FLUTTER_STORAGE_BASE_URL="https://f.mirror.hesabix.ir/gcs"
app_dir="${APP_ROOT}/app"
build_script="${app_dir}/build_web.sh"
if [[ ! -f "${build_script}" ]]; then
  log_err "build_web.sh not found: ${build_script}"
  exit 1
fi
chmod +x "${build_script}"
# shellcheck disable=SC1091
if [[ -r "${app_dir}/scripts/api_public_scheme.sh" ]]; then
  source "${app_dir}/scripts/api_public_scheme.sh"
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
api_scheme="$(hesabix_resolve_api_public_scheme)"
api_url="${api_scheme}://${API_DOMAIN}"
cd "${app_dir}"
if ! env PATH="/opt/flutter/bin:/snap/bin:$PATH" \
    PUB_HOSTED_URL="${PUB_HOSTED_URL:-}" FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-}" \
    SKIP_NGINX_ENSURE=1 \
    bash build_web.sh --mode release --api-base-url "${api_url}" --clean --install-deps; then
  log_err "Frontend build failed."
  exit 1
fi
# اطمینان از nginx برای UI در «گام ۴» انجام می‌شود (یک‌بار، idempotent)؛ اینجا عمداً SKIP_NGINX_ENSURE تا دوباره‌کاری نشود.
build_output="${app_dir}/hesabixUI/hesabix_ui/build/web"
if [[ ! -f "${build_output}/index.html" ]]; then
  log_err "Build output missing index.html."
  exit 1
fi
mkdir -p "/var/www/${UI_DOMAIN}"
rsync -a --delete "${build_output}/" "/var/www/${UI_DOMAIN}/"
chown -R www-data:www-data "/var/www/${UI_DOMAIN}"
log_ok "Frontend built and deployed to /var/www/${UI_DOMAIN}."

# --- 4. Nginx: ensure client_max_body_size 1g for database restore, then reload ---
log_info "Step 4: Updating Nginx config and reloading..."
if [[ -f /etc/nginx/sites-available/hesabix-api.conf ]]; then
  if grep -q 'client_max_body_size' /etc/nginx/sites-available/hesabix-api.conf; then
    sed -i 's/client_max_body_size [0-9]*[kmgKMG]*/client_max_body_size 1g/' /etc/nginx/sites-available/hesabix-api.conf
  else
    sed -i '/proxy_send_timeout 300;/a\    client_max_body_size 1g;' /etc/nginx/sites-available/hesabix-api.conf
  fi
  log_info "Ensured client_max_body_size 1g (database restore uploads)."
fi
# UI: version.json، service worker، flutter_bootstrap.js و main.dart.js بدون کش یک‌سالهٔ immutable
# اگر هر دو location ورودی JS از قبل باشد، اسکریپت بلافاصله خارج می‌شود و فایل nginx را دست نمی‌زند.
ensure_ui_nginx="${app_dir}/scripts/ensure_nginx_ui_version_probe.sh"
if [[ -f "${ensure_ui_nginx}" ]]; then
  chmod +x "${ensure_ui_nginx}" 2>/dev/null || true
  log_info "Step 4 (UI): Ensuring nginx cache rules for Flutter web (idempotent)..."
  if bash "${ensure_ui_nginx}"; then
    log_ok "Nginx UI version/SW/entry-JS rules verified or updated."
  else
    log_info "Nginx UI ensure skipped or failed (e.g. no hesabix-ui.conf on this host); non-fatal."
  fi
else
  log_info "ensure_nginx_ui_version_probe.sh not found at ${ensure_ui_nginx}; skipped."
fi
if ! nginx -t 2>/dev/null; then
  log_err "Nginx config test failed."
  exit 1
fi
systemctl reload nginx
log_ok "Nginx reloaded."

# --- 5. Optional health check ---
if command -v curl >/dev/null 2>&1; then
  if curl -sSf --connect-timeout 5 "https://${API_DOMAIN}/api/v1/health" >/dev/null 2>&1 || \
     curl -sSf --connect-timeout 5 "http://127.0.0.1:8000/api/v1/health" >/dev/null 2>&1; then
    log_ok "API health check passed."
  else
    log_info "API health check skipped or failed (non-fatal)."
  fi
fi

echo "==========================================" | tee -a "${LOG_FILE}"
log_ok "Hesabix update completed."
echo "==========================================" | tee -a "${LOG_FILE}"
