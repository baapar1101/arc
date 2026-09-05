#!/usr/bin/env bash
# Shared Hesabix Nginx vhost generation for API, UI, and optional pgAdmin4.

HESABIX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hesabix_letsencrypt.sh
source "${HESABIX_LIB_DIR}/hesabix_letsencrypt.sh"

hesabix_nginx_bin() {
  if command -v nginx >/dev/null 2>&1; then
    command -v nginx
    return 0
  fi
  if [[ -x /usr/sbin/nginx ]]; then
    echo /usr/sbin/nginx
    return 0
  fi
  return 1
}

# Regenerate Nginx configs from API_DOMAIN / UI_DOMAIN (and optional PGADMIN4_DOMAIN).
# Requires those variables in the environment. Reloads nginx on success.
hesabix_apply_nginx_domain_configs() {
  local quiet="${1:-0}"

  if [[ -z "${API_DOMAIN:-}" ]] || [[ -z "${UI_DOMAIN:-}" ]]; then
    echo "API_DOMAIN and UI_DOMAIN must be set." >&2
    return 1
  fi

  local API_LETSENCRYPT_LIVE="" UI_LETSENCRYPT_LIVE="" PGADMIN_LETSENCRYPT_LIVE=""
  local API_SSL_BLOCK="" UI_SSL_BLOCK="" PGADMIN_SSL_BLOCK=""

  if API_LETSENCRYPT_LIVE="$(hesabix_pick_letsencrypt_live_for_domain "${API_DOMAIN}")"; then :; else API_LETSENCRYPT_LIVE=""; fi
  if UI_LETSENCRYPT_LIVE="$(hesabix_pick_letsencrypt_live_for_domain "${UI_DOMAIN}")"; then :; else UI_LETSENCRYPT_LIVE=""; fi
  if [[ -n "${PGADMIN4_DOMAIN:-}" ]]; then
    if PGADMIN_LETSENCRYPT_LIVE="$(hesabix_pick_letsencrypt_live_for_domain "${PGADMIN4_DOMAIN}")"; then :; else PGADMIN_LETSENCRYPT_LIVE=""; fi
  fi

  if [[ -n "${API_LETSENCRYPT_LIVE}" ]]; then
    API_SSL_BLOCK="$(hesabix_nginx_ssl_block_for_live_dir "${API_LETSENCRYPT_LIVE}")"
  fi
  if [[ -n "${UI_LETSENCRYPT_LIVE}" ]]; then
    UI_SSL_BLOCK="$(hesabix_nginx_ssl_block_for_live_dir "${UI_LETSENCRYPT_LIVE}")"
  fi
  if [[ -n "${PGADMIN_LETSENCRYPT_LIVE}" ]]; then
    PGADMIN_SSL_BLOCK="$(hesabix_nginx_ssl_block_for_live_dir "${PGADMIN_LETSENCRYPT_LIVE}")"
  fi

  if [[ "${quiet}" != "1" ]]; then
    echo ">> Updating Nginx: API_DOMAIN=${API_DOMAIN} UI_DOMAIN=${UI_DOMAIN}"
    if [[ -n "${API_SSL_BLOCK}" ]]; then
      echo ">> TLS API: ${API_LETSENCRYPT_LIVE}"
    else
      echo ">> Warning: no Let's Encrypt cert for ${API_DOMAIN}; API listens on port 80 only."
    fi
    if [[ -n "${UI_SSL_BLOCK}" ]]; then
      echo ">> TLS UI: ${UI_LETSENCRYPT_LIVE}"
    else
      echo ">> Warning: no cert for ${UI_DOMAIN}; UI listens on port 80 only."
    fi
    if [[ -n "${PGADMIN4_DOMAIN:-}" ]]; then
      if [[ -n "${PGADMIN_SSL_BLOCK}" ]]; then
        echo ">> TLS pgAdmin4: ${PGADMIN_LETSENCRYPT_LIVE}"
      else
        echo ">> Warning: no cert for ${PGADMIN4_DOMAIN}; pgAdmin4 listens on port 80 only."
      fi
    fi
  fi

# همان کانفیگ deploy.sh
if [[ -d /etc/nginx/conf.d ]]; then
  cat > /etc/nginx/conf.d/rate-limit-api.conf <<RATELIMIT
# OPTIONS (CORS preflight) را در سهمیه نمی‌گذارد؛ هر XHR معمولاً OPTIONS + METHOD است.
map \$request_method \$api_limit_key {
	default  \$binary_remote_addr;
	OPTIONS  "";
}

limit_req_zone \$api_limit_key zone=api_limit:10m rate=40r/s;
RATELIMIT
fi

cat > /etc/nginx/sites-available/hesabix-api.conf <<NGINX
# Backend API
server {
  listen 80;
${API_SSL_BLOCK}
  server_name ${API_DOMAIN};

  add_header X-Frame-Options "DENY" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-XSS-Protection "1; mode=block" always;
  add_header Referrer-Policy "strict-origin-when-cross-origin" always;

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

  # Public share link: /p/{code} → backend (307 redirect)
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

  # Public invoice share link: /i/{code} → backend (307 → Flutter /public/invoice-link/...)
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
  location /public/ {
    root /var/www/${UI_DOMAIN};
    try_files \$uri \$uri/ @hesabix_public_spa;
  }
  location @hesabix_public_spa {
    root /var/www/${UI_DOMAIN};
    rewrite ^ /index.html break;
  }

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

  # همان منطق deploy.sh: پروکسی کردن کل /assets/ آیکن‌ها و فونت Flutter را روی یک دامنه با UI می‌شکند.
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

cat > /etc/nginx/sites-available/hesabix-ui.conf <<NGINX
# Frontend (Flutter Web)
server {
  listen 80;
${UI_SSL_BLOCK}
  server_name ${UI_DOMAIN};

  root /var/www/${UI_DOMAIN};
  index index.html;

  add_header X-Frame-Options "SAMEORIGIN" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-XSS-Protection "1; mode=block" always;
  add_header Referrer-Policy "strict-origin-when-cross-origin" always;

  # Public share link redirect: /p/{code} → backend (307 to /public/person-link/{code})
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

  # Public invoice share: /i/{code} → backend (307 to /public/invoice-link/{code})
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

  # همان دامنهٔ UI+API: /docs و openapi و redoc و دارایی‌های swagger به بک‌اند (بدون تداخل با /assets Flutter)
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

  location = /version.json {
    add_header Cache-Control "no-store" always;
    expires off;
    try_files \$uri =404;
  }

  location = /flutter_service_worker.js {
    add_header Cache-Control "no-cache, must-revalidate" always;
    expires off;
    try_files \$uri =404;
  }

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

  # Branding / Flutter image assets change in place — never immutable-cache them
  location ^~ /assets/assets/ {
    add_header Cache-Control "no-cache, must-revalidate" always;
    expires off;
  }

  location ^~ /images/ {
    add_header Cache-Control "no-cache, must-revalidate" always;
    expires off;
  }

  location ^~ /icons/ {
    add_header Cache-Control "no-cache, must-revalidate" always;
    expires off;
  }

  location = /favicon.ico {
    add_header Cache-Control "no-cache, must-revalidate" always;
    expires off;
  }

  location = /favicon.png {
    add_header Cache-Control "no-cache, must-revalidate" always;
    expires off;
  }

  location / {
    try_files \$uri \$uri/ /index.html;
  }

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

[[ -L /etc/nginx/sites-enabled/default ]] && rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/hesabix-api.conf /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/hesabix-ui.conf /etc/nginx/sites-enabled/

  if [[ -n "${PGADMIN4_DOMAIN:-}" ]] && [[ -f /etc/nginx/sites-available/pgadmin4.conf || "$(systemctl show pgadmin4.service -p LoadState --value 2>/dev/null)" == "loaded" ]]; then
    cat > /etc/nginx/sites-available/pgadmin4.conf <<NGINX
# pgAdmin4 (reverse proxy to Gunicorn on 127.0.0.1:5050)
server {
  listen 80;
${PGADMIN_SSL_BLOCK}
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
  fi

  local nginx_bin
  nginx_bin="$(hesabix_nginx_bin)" || {
    echo "nginx not found." >&2
    return 1
  }
  if "${nginx_bin}" -t; then
    systemctl reload nginx
    [[ "${quiet}" != "1" ]] && echo "✓ Nginx updated and reloaded."
    return 0
  fi
  echo "Nginx configuration test failed." >&2
  return 1
}
