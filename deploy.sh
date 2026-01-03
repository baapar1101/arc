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
# مخزن پروژه: https://source.hesabix.ir/morrning/hesabixArc.git
# پشتیبانی: https://hesabix.ir/support
#
# ============================================================================
# Deployment Script
# ============================================================================
#
# این اسکریپت برای نصب و راه‌اندازی خودکار Hesabix طراحی شده است:
# - Clone از مخزن: https://source.hesabix.ir/morrning/hesabixArc.git
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

REPO_URL="https://source.hesabix.ir/morrning/hesabixArc.git"
APP_ROOT="/opt/hesabix"
CHECK_MARK=$'\xE2\x9C\x94'
CROSS_MARK=$'\xE2\x9D\x8C'
WARNING_MARK=$'\xE2\x9A\xA0'

# Generate random password if not provided
generate_password() {
  openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
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
  while [ $attempt -lt $max_attempts ]; do
    if sudo -u postgres psql -c "SELECT 1" >/dev/null 2>&1; then
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 2
  done
  echo "$CROSS_MARK Database not ready after $max_attempts attempts"
  return 1
}

# Check disk space (requires at least 2GB free)
check_disk_space() {
  local available_space
  available_space=$(df / | tail -1 | awk '{print $4}')
  if [ "$available_space" -lt 2097152 ]; then
    echo "$WARNING_MARK Low disk space (less than 2GB). This may cause issues."
    read -rp "Continue anyway? (y/N): " continue_anyway
    if [[ ! "${continue_anyway}" =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$CROSS_MARK Required tool not found: $1"
    exit 1
  fi
}

show_license_info() {
  cat <<LICENSE

╔═══════════════════════════════════════════════════════════════════════╗
║                  Hesabix - سیستم حسابداری جامع                      ║
║                    نرم‌افزار متن باز تحت GPL v3                       ║
╚═══════════════════════════════════════════════════════════════════════╝

📋 درباره نرم‌افزار:
   Hesabix یک سیستم حسابداری کامل و مدرن است که شامل:
   • API قدرتمند (FastAPI + PostgreSQL)
   • رابط کاربری زیبا (Flutter Web)
   • متن باز و رایگان

👨‍💻 توسعه‌دهندگان:
   Hesabix Team
   وب‌سایت: https://hesabix.ir
   پشتیبانی: https://hesabix.ir/support

📦 مخزن پروژه:
   https://source.hesabix.ir/morrning/hesabixArc.git

📄 مجوز:
   این نرم‌افزار تحت مجوز GNU General Public License v3.0 (GPL-3.0) 
   منتشر شده است.

   متن کامل لایسنس: http://www.gnu.org/licenses/gpl-3.0.txt

   خلاصه حقوق:
   ✓ شما آزاد هستید نرم‌افزار را اجرا کنید
   ✓ شما آزاد هستید نرم‌افزار را مطالعه و تغییر دهید
   ✓ شما آزاد هستید نرم‌افزار را توزیع کنید
   ✓ شما آزاد هستید نسخه‌های بهبود یافته را توزیع کنید

   شرط: هر توزیع یا نسخه تغییر یافته باید تحت همان لایسنس GPL v3 
         باشد و کد منبع باید در دسترس قرار گیرد.

   ⚠️  این نرم‌افزار بدون هیچگونه ضمانتی ارائه می‌شود.

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
    echo "⚠️  برای ادامه نصب، شما باید با شرایط مجوز GNU GPL v3 موافقت کنید."
    echo
    read -rp "آیا با شرایط مجوز GNU General Public License v3.0 موافقت می‌کنید؟ (yes/no): " ACCEPT_LICENSE
  fi
  
  case "${ACCEPT_LICENSE}" in
    [Yy][Ee][Ss]|y|Y)
      echo "$CHECK_MARK موافقت با لایسنس GNU GPL v3.0 ثبت شد."
      return 0
      ;;
    *)
      echo "$CROSS_MARK شما باید با شرایط لایسنس موافقت کنید تا بتوانید نصب را ادامه دهید."
      echo
      echo "برای مشاهده متن کامل لایسنس به آدرس زیر مراجعه کنید:"
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
  # Optimize worker count for high scalability:
  # Formula: (2 * CPU cores) + 1
  # For 8-core server: 17 workers
  # With pool_size=20 and max_overflow=30, each worker has up to 50 connections
  # Total: 17 * 50 = 850 maximum connections
  : "${UVICORN_WORKERS:=17}"
  : "${FLUTTER_VERSION:=3.24.0}"
  
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
  
  export API_DOMAIN UI_DOMAIN BRANCH DB_PASSWORD UVICORN_WORKERS FLUTTER_VERSION
  echo "$CHECK_MARK Variables:"
  echo "  API_DOMAIN=${API_DOMAIN}"
  echo "  UI_DOMAIN=${UI_DOMAIN}"
  echo "  BRANCH=${BRANCH}"
  echo "  UVICORN_WORKERS=${UVICORN_WORKERS}"
  echo "  FLUTTER_VERSION=${FLUTTER_VERSION}"
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
  echo ">> Configuring database (PostgreSQL)..."
  
  # Start and enable PostgreSQL service
  if systemctl list-unit-files | grep -q postgresql.service; then
    systemctl enable --now postgresql || true
  else
    echo "$CROSS_MARK PostgreSQL service not found. Please install PostgreSQL."
    exit 1
  fi
  
  # Wait for database to be ready
  echo "Waiting for database to be ready..."
  if ! wait_for_db; then
    echo "$CROSS_MARK Database not ready"
    exit 1
  fi
  
  # Configure PostgreSQL to allow local connections (if needed)
  local pg_version
  pg_version=$(sudo -u postgres psql -tAc "SELECT version();" | grep -oE '[0-9]+' | head -1)
  local pg_hba="/etc/postgresql/${pg_version}/main/pg_hba.conf"
  
  # Allow password authentication for localhost connections
  if [[ -f "${pg_hba}" ]] && ! grep -q "host.*hesabix.*127.0.0.1/32.*md5" "${pg_hba}"; then
    echo "host    hesabix    hesabix    127.0.0.1/32    md5" >> "${pg_hba}"
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
    echo "$CHECK_MARK Database and user created, connection verified."
  else
    echo "$WARNING_MARK Connection test failed, but database may still be accessible. Continuing..."
  fi
}

deploy_backend() {
  echo ">> Deploying backend..."
  local api_dir="${APP_ROOT}/app/hesabixAPI"
  
  if [[ ! -d "${api_dir}" ]]; then
    echo "$CROSS_MARK Backend path not found: ${api_dir}"
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
    # Add CORS if not exists
    if ! grep -q "CORS_ALLOWED_ORIGINS" "${env_file}"; then
      echo "CORS_ALLOWED_ORIGINS=[\"https://${UI_DOMAIN}\",\"http://${UI_DOMAIN}\"]" >> "${env_file}"
    else
      sed -i "s|^CORS_ALLOWED_ORIGINS=.*|CORS_ALLOWED_ORIGINS=[\"https://${UI_DOMAIN}\",\"http://${UI_DOMAIN}\"]|" "${env_file}"
    fi
  else
    # Fallback: create minimal .env
    cat > "${env_file}" <<ENV
ENVIRONMENT=production
DEBUG=false
DB_USER=hesabix
DB_PASSWORD=${DB_PASSWORD}
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=hesabix
LOG_LEVEL=INFO
CORS_ALLOWED_ORIGINS=["https://${UI_DOMAIN}","http://${UI_DOMAIN}"]
ENV
  fi

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
    echo "$CHECK_MARK Backend started (service: hesabix-api)."
  else
    echo "$CROSS_MARK Backend failed to start. Check logs: journalctl -u hesabix-api"
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
      echo "$CHECK_MARK RQ Worker started (service: hesabix-rq-worker)."
    else
      echo "$WARNING_MARK RQ Worker failed to start. Check logs: journalctl -u hesabix-rq-worker"
      echo "$WARNING_MARK Background jobs will not work until Redis is configured and RQ worker is running."
    fi
  else
    echo "$WARNING_MARK Redis service not found. RQ Worker not started."
    echo "$WARNING_MARK To enable background jobs, install and configure Redis, then run: systemctl start hesabix-rq-worker"
  fi
}

install_flutter_and_build_frontend() {
  echo ">> Building Flutter frontend..."
  
  local app_dir="${APP_ROOT}/app"
  if [[ ! -d "${app_dir}" ]]; then
    echo "$CROSS_MARK App directory not found: ${app_dir}"
    exit 1
  fi
  
  local build_script="${app_dir}/build_web.sh"
  if [[ ! -f "${build_script}" ]]; then
    echo "$CROSS_MARK build_web.sh not found: ${build_script}"
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
  
  # Build using build_web.sh script
  cd "${app_dir}"
  if ! bash build_web.sh \
    --mode release \
    --api-base-url "${api_url}" \
    --clean \
    --install-deps; then
    echo "$CROSS_MARK Error building frontend"
    exit 1
  fi
  
  # Find the build output directory
  local ui_project_dir="${app_dir}/hesabixUI/hesabix_ui"
  local build_output="${ui_project_dir}/build/web"
  
  if [[ ! -d "${build_output}" ]]; then
    echo "$CROSS_MARK Build output directory not found: ${build_output}"
    exit 1
  fi

  # Deploy to web directory
  mkdir -p "/var/www/${UI_DOMAIN}"
  rsync -a --delete "${build_output}/" "/var/www/${UI_DOMAIN}/"
  chown -R www-data:www-data "/var/www/${UI_DOMAIN}"
  echo "$CHECK_MARK Frontend built and deployed to /var/www/${UI_DOMAIN}."
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

main() {
  if [[ $EUID -ne 0 ]]; then
    echo "$CROSS_MARK Please run this script with root privileges (sudo)."
    exit 1
  fi
  
  # Show license information
  show_license_info
  
  # Require license acceptance
  accept_license
  
  echo
  echo "=========================================="
  echo "  Hesabix Deployment Script"
  echo "=========================================="
  echo
  
  # Check disk space
  check_disk_space
  
  # Check if port 8000 is available
  if command -v netstat >/dev/null 2>&1; then
    if netstat -tuln | grep -q ":8000 "; then
      echo "$WARNING_MARK Port 8000 is in use. You may need to stop the previous service."
    fi
  fi
  
  prompt_vars
  echo
  
  install_prereqs
  echo
  
  clone_repo
  echo
  
  setup_db
  echo
  
  deploy_backend
  echo
  
  install_flutter_and_build_frontend
  echo
  
  configure_nginx_api
  echo
  
  configure_nginx_ui
  echo
  
  configure_api_ssl
  echo
  
  configure_ui_ssl
  echo
  
  echo "=========================================="
  echo "$CHECK_MARK Deployment completed!"
  echo "=========================================="
  echo
  echo "Access URLs:"
  echo "  API:  https://${API_DOMAIN}/api/v1/health"
  echo "  UI:   https://${UI_DOMAIN}/"
  echo
  echo "Service management:"
  echo "  systemctl status hesabix-api    # API status"
  echo "  systemctl restart hesabix-api    # Restart API"
  echo "  journalctl -u hesabix-api -f     # View API logs"
  echo "  systemctl status nginx           # Nginx status"
  echo
  echo "To re-run/upgrade:"
  echo "  BRANCH=${BRANCH} API_DOMAIN=${API_DOMAIN} UI_DOMAIN=${UI_DOMAIN} sudo -E bash deploy.sh"
  echo
  echo "Database password is stored in:"
  echo "  ${APP_ROOT}/.db_password"
  echo
}

main "$@"


