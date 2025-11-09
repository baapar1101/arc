#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Hesabix one-click deployment script (server-side)
# - Clones from: https://source.hesabix.ir/morrning/hesabixArc.git
# - Prompts for API/UI domains and branch
# - Installs prerequisites, DB, backend (FastAPI), frontend (Flutter Web), Nginx
#
# Usage:
#   sudo bash deploy.sh
#   # or
#   API_DOMAIN=api.example.com UI_DOMAIN=app.example.com BRANCH=main sudo -E bash deploy.sh
#
# Notes:
# - Designed for Ubuntu 22.04+/Debian 12+
# - Idempotent-ish: safe to re-run; will update and restart services

REPO_URL="https://source.hesabix.ir/morrning/hesabixArc.git"
APP_ROOT="/opt/hesabix"
CHECK_MARK=$'\xE2\x9C\x94'
CROSS_MARK=$'\xE2\x9D\x8C'

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$CROSS_MARK ابزار لازم یافت نشد: $1"
    exit 1
  fi
}

prompt_vars() {
  : "${API_DOMAIN:=}"
  : "${UI_DOMAIN:=}"
  : "${BRANCH:=main}"
  if [[ -z "${API_DOMAIN}" ]]; then
    read -rp "دامنه API (مثال: api.example.com): " API_DOMAIN
  fi
  if [[ -z "${UI_DOMAIN}" ]]; then
    read -rp "دامنه Front (مثال: app.example.com): " UI_DOMAIN
  fi
  if [[ -z "${BRANCH}" ]]; then
    read -rp "نام برنچ (پیش‌فرض main): " BRANCH
    BRANCH=${BRANCH:-main}
  fi
  export API_DOMAIN UI_DOMAIN BRANCH
  echo "$CHECK_MARK متغیرها:"
  echo "  API_DOMAIN=${API_DOMAIN}"
  echo "  UI_DOMAIN=${UI_DOMAIN}"
  echo "  BRANCH=${BRANCH}"
}

install_prereqs() {
  echo ">> نصب پیش‌نیازها..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y git curl unzip xz-utils ca-certificates \
    python3.11 python3.11-venv python3-pip build-essential \
    nginx mariadb-server
  echo "$CHECK_MARK پیش‌نیازها نصب شد."
}

clone_repo() {
  echo ">> کلون/به‌روزرسانی مخزن..."
  mkdir -p "${APP_ROOT}"
  cd "${APP_ROOT}"
  if [[ ! -d "${APP_ROOT}/app/.git" ]]; then
    git clone -b "${BRANCH}" --depth=1 "${REPO_URL}" app
  else
    cd app
    git fetch --all --prune
    git checkout "${BRANCH}"
    git pull --ff-only
  fi
  echo "$CHECK_MARK مخزن آماده است در ${APP_ROOT}/app"
}

setup_db() {
  echo ">> پیکربندی دیتابیس (MariaDB/MySQL)..."
  systemctl enable --now mariadb || systemctl enable --now mysql || true
  mysql --protocol=socket -uroot <<'SQL'
CREATE DATABASE IF NOT EXISTS hesabix CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS 'hesabix'@'localhost' IDENTIFIED BY 'StrongPass#ChangeMe';
GRANT ALL PRIVILEGES ON hesabix.* TO 'hesabix'@'localhost';
FLUSH PRIVILEGES;
SQL
  echo "$CHECK_MARK دیتابیس و کاربر آماده شد."
}

deploy_backend() {
  echo ">> استقرار بک‌اند..."
  local api_dir="${APP_ROOT}/app/hesabixAPI"
  cd "${api_dir}"

  # Python venv + install
  if [[ ! -d ".venv" ]]; then
    python3.11 -m venv .venv
  fi
  # shellcheck disable=SC1091
  source .venv/bin/activate
  pip install --upgrade pip
  pip install -e .

  # .env
  cat > .env <<ENV
environment=production
debug=false
db_user=hesabix
db_password=StrongPass#ChangeMe
db_host=127.0.0.1
db_port=3306
db_name=hesabix
log_level=INFO
cors_allowed_origins=["https://${UI_DOMAIN}","http://${UI_DOMAIN}"]
ENV

  # Alembic migrations
  alembic upgrade head

  # systemd service
  cat > /etc/systemd/system/hesabix-api.service <<'UNIT'
[Unit]
Description=Hesabix API (FastAPI/Uvicorn)
After=network.target mariadb.service mysql.service

[Service]
User=www-data
WorkingDirectory=/opt/hesabix/app/hesabixAPI
Environment=PATH=/opt/hesabix/app/hesabixAPI/.venv/bin
Environment=PYTHONUNBUFFERED=1
ExecStart=/opt/hesabix/app/hesabixAPI/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable --now hesabix-api
  echo "$CHECK_MARK بک‌اند اجرا شد (service: hesabix-api)."
}

install_flutter_and_build_frontend() {
  echo ">> نصب Flutter و بیلد فرانت..."
  local flutter_root="/opt/flutter"
  if [[ ! -d "${flutter_root}/flutter" ]]; then
    mkdir -p "${flutter_root}"
    cd "${flutter_root}"
    curl -L https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.0-stable.tar.xz -o flutter.tar.xz
    tar -xf flutter.tar.xz
  fi
  local flutter_bin="${flutter_root}/flutter/bin/flutter"
  "${flutter_bin}" --version
  "${flutter_bin}" config --enable-web

  local ui_dir="${APP_ROOT}/app/hesabixUI/hesabix_ui"
  cd "${ui_dir}"
  "${flutter_bin}" pub get
  "${flutter_bin}" build web --release

  mkdir -p "/var/www/${UI_DOMAIN}"
  rsync -a --delete build/web/ "/var/www/${UI_DOMAIN}/"
  chown -R www-data:www-data "/var/www/${UI_DOMAIN}"
  echo "$CHECK_MARK فرانت بیلد و در /var/www/${UI_DOMAIN} مستقر شد."
}

configure_nginx() {
  echo ">> پیکربندی Nginx..."
  cat > /etc/nginx/sites-available/hesabix.conf <<NGINX
# Frontend (Flutter Web)
server {
  listen 80;
  server_name ${UI_DOMAIN};

  root /var/www/${UI_DOMAIN};
  index index.html;

  location / {
    try_files \$uri \$uri/ /index.html;
  }

  gzip on;
  gzip_types text/plain text/css application/javascript application/json image/svg+xml;
}

# Backend API
server {
  listen 80;
  server_name ${API_DOMAIN};

  location / {
    return 404;
  }

  location /api/ {
    proxy_pass http://127.0.0.1:8000/api/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_read_timeout 300;
    client_max_body_size 20m;
  }
}
NGINX

  ln -sf /etc/nginx/sites-available/hesabix.conf /etc/nginx/sites-enabled/hesabix.conf
  nginx -t
  systemctl reload nginx
  echo "$CHECK_MARK Nginx پیکربندی و ری‌لود شد."
}

maybe_enable_tls() {
  echo
  read -rp "آیا TLS خودکار با certbot فعال شود؟ (y/N): " ENABLE_TLS
  ENABLE_TLS=${ENABLE_TLS:-N}
  if [[ "${ENABLE_TLS}" =~ ^[Yy]$ ]]; then
    apt-get install -y certbot python3-certbot-nginx
    certbot --nginx -d "${UI_DOMAIN}" -d "${API_DOMAIN}" --redirect --non-interactive --agree-tos -m "admin@${UI_DOMAIN}" || true
    echo "$CHECK_MARK تلاش برای صدور TLS انجام شد."
  else
    echo "TLS رد شد؛ می‌توانید بعداً certbot اجرا کنید."
  fi
}

main() {
  if [[ $EUID -ne 0 ]]; then
    echo "$CROSS_MARK لطفاً اسکریپت را با دسترسی روت اجرا کنید (sudo)."
    exit 1
  fi
  prompt_vars
  install_prereqs
  clone_repo
  setup_db
  deploy_backend
  install_flutter_and_build_frontend
  configure_nginx
  maybe_enable_tls
  echo
  echo "$CHECK_MARK استقرار تکمیل شد."
  echo "  API:  http://${API_DOMAIN}/api/v1/health"
  echo "  UI:   http://${UI_DOMAIN}/"
  echo
  echo "برای اجرای مجدد/آپگرید:"
  echo "  BRANCH=${BRANCH} API_DOMAIN=${API_DOMAIN} UI_DOMAIN=${UI_DOMAIN} sudo -E bash deploy.sh"
}

main "$@"


