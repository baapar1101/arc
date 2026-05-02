# نصب به‌عنوان: /etc/nginx/snippets/p-mirror-pypi-location.conf
# از داخل sites-available با include فراخوانده می‌شود (p-mirror-pypi.conf).
#
# پروکسی PyPI (Runflare) — پشت دامنهٔ آینه (مثلاً p.mirror.hesabix.ir)
# بدون X-Forwarded-For/X-Real-IP تا 402 payment_required نشود؛ upstream: mirror-pypi.runflare.com
#
# pip اگر در HTML/JSON لینک مطلق mirror-pypi.runflare.com ببیند مستقیم آنجا می‌رود و ۴۰۲ می‌گیرد؛
# پس برای مسیرهای غیر از آرشیو حجیم (/packages/) دامنه در بدنهٔ پاسخ و Location به $host بازنویسی می‌شود.

    location ^~ /packages/ {
        limit_req zone=pypi_req burst=100 nodelay;
        limit_req_status 429;

        proxy_pass https://mirror-pypi.runflare.com;
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        proxy_set_header Host mirror-pypi.runflare.com;
        proxy_set_header X-Forwarded-For "";
        proxy_set_header X-Real-IP "";

        proxy_ssl_server_name on;
        proxy_ssl_name mirror-pypi.runflare.com;

        proxy_cache pypi_cache;
        proxy_cache_key "$scheme$proxy_host$request_uri";

        proxy_cache_valid 200 206 301 302 3650d;
        proxy_cache_valid any 1m;

        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;

        proxy_cache_lock on;
        proxy_cache_lock_timeout 60s;

        proxy_buffering on;
        proxy_request_buffering on;

        proxy_force_ranges on;

        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;

        add_header X-Cache-Status $upstream_cache_status always;
    }

    location / {
        limit_req zone=pypi_req burst=100 nodelay;
        limit_req_status 429;

        proxy_pass https://mirror-pypi.runflare.com;
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        proxy_set_header Host mirror-pypi.runflare.com;
        proxy_set_header X-Forwarded-For "";
        proxy_set_header X-Real-IP "";
        proxy_set_header Accept-Encoding "";

        proxy_ssl_server_name on;
        proxy_ssl_name mirror-pypi.runflare.com;

        proxy_redirect https://mirror-pypi.runflare.com/ https://$host/;
        proxy_redirect http://mirror-pypi.runflare.com/ http://$host/;
        proxy_redirect https://mirror-pypi.runflare.com https://$host;
        proxy_redirect http://mirror-pypi.runflare.com http://$host;

        gunzip on;
        sub_filter_once off;
        sub_filter_types application/vnd.pypi.simple.v1+json application/json text/plain;
        sub_filter mirror-pypi.runflare.com $host;

        proxy_cache pypi_cache;
        proxy_cache_key "$scheme$proxy_host$request_uri";

        proxy_cache_valid 200 206 301 302 3650d;
        proxy_cache_valid any 1m;

        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;

        proxy_cache_lock on;
        proxy_cache_lock_timeout 60s;

        proxy_buffering on;
        proxy_request_buffering on;

        proxy_force_ranges on;

        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;

        add_header X-Cache-Status $upstream_cache_status always;
    }
