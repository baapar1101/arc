#!/usr/bin/env bash
# Hesabix update script: pull from repo, migrate backend, restart services, rebuild frontend, reload nginx.
# Run via: hesabix -update [-source URL] [-branch NAME]
# Requires: API_DOMAIN, UI_DOMAIN, BRANCH, REPO_URL in env or in ${APP_ROOT}/.deploy_env
set -euo pipefail

APP_ROOT="${APP_ROOT:-/opt/hesabix}"
LOG_FILE="${APP_ROOT}/update.log"
CHECK_MARK=$'\xE2\x9C\x94'
CROSS_MARK=$'\xE2\x9D\x8C'

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
log_ok()   { echo "${CHECK_MARK} $*" | tee -a "${LOG_FILE}"; }
log_err()  { echo "${CROSS_MARK} $*" >&2; echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "${LOG_FILE}"; }

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
if git show-ref -q "origin/${BRANCH}"; then
  git checkout -B "${BRANCH}" "origin/${BRANCH}" 2>/dev/null || git checkout "${BRANCH}"
  git pull origin "${BRANCH}" --ff-only 2>/dev/null || true
else
  git checkout "${BRANCH}" 2>/dev/null || true
  git pull origin "${BRANCH}" --ff-only 2>/dev/null || true
fi
log_ok "Source updated."

# --- 2. Backend: pip, migrations, restart services ---
log_info "Step 2: Backend – install deps, migrations, restart services..."
api_dir="${APP_ROOT}/app/hesabixAPI"
if [[ ! -d "${api_dir}/.venv" ]]; then
  log_err "Backend venv not found. Run full deploy first."
  exit 1
fi
cd "${api_dir}"
# shellcheck disable=SC1091
source .venv/bin/activate
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
# Mirror detection (minimal)
if [[ -z "${PUB_HOSTED_URL:-}" ]] || [[ -z "${FLUTTER_STORAGE_BASE_URL:-}" ]]; then
  for pair in "https://pub.flutter-io.cn|https://storage.flutter-io.cn" "https://pub.dev|https://storage.googleapis.com"; do
    IFS='|' read -r pub_url storage_url <<< "$pair"
    if curl -s --connect-timeout 3 -o /dev/null -w "%{http_code}" "$pub_url" 2>/dev/null | grep -q '^[23]'; then
      export PUB_HOSTED_URL="$pub_url"
      export FLUTTER_STORAGE_BASE_URL="$storage_url"
      break
    fi
  done
  export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.dev}"
  export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.googleapis.com}"
fi
app_dir="${APP_ROOT}/app"
build_script="${app_dir}/build_web.sh"
if [[ ! -f "${build_script}" ]]; then
  log_err "build_web.sh not found: ${build_script}"
  exit 1
fi
chmod +x "${build_script}"
api_url="https://${API_DOMAIN}"
cd "${app_dir}"
if ! env PATH="/opt/flutter/bin:/snap/bin:$PATH" \
    PUB_HOSTED_URL="${PUB_HOSTED_URL:-}" FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-}" \
    bash build_web.sh --mode release --api-base-url "${api_url}" --clean --install-deps; then
  log_err "Frontend build failed."
  exit 1
fi
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
