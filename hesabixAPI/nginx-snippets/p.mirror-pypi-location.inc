# نصب به‌عنوان: /etc/nginx/snippets/p-mirror-pypi-location.conf
# از داخل sites-available با include فراخوانده می‌شود (p-mirror-pypi.conf).
#
# پروکسی PyPI با کش Nginx — پشت دامنهٔ آینه (مثلاً p.mirror.hesabix.ir)
# upstream: میرور لیارا https://package-mirror.liara.ir/repository/pypi/
# مسیر کلاینت: /simple/... و /packages/... (مثل PyPI) → به /repository/pypi/... روی لیارا نگاشت می‌شود.
#
# X-Forwarded-For/X-Real-IP به upstream نمی‌رود (هم‌راستا با سایر آینه‌های hesabix؛ سیاست Runflare دیگر اعمال نیست).

    location ^~ /packages/ {
        limit_req zone=pypi_req burst=100 nodelay;
        limit_req_status 429;

        proxy_pass https://package-mirror.liara.ir/repository/pypi/packages/;
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        proxy_set_header Host package-mirror.liara.ir;
        proxy_set_header X-Forwarded-For "";
        proxy_set_header X-Real-IP "";

        proxy_ssl_server_name on;
        proxy_ssl_name package-mirror.liara.ir;

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

        proxy_pass https://package-mirror.liara.ir/repository/pypi/;
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        proxy_set_header Host package-mirror.liara.ir;
        proxy_set_header X-Forwarded-For "";
        proxy_set_header X-Real-IP "";
        proxy_set_header Accept-Encoding "";

        proxy_ssl_server_name on;
        proxy_ssl_name package-mirror.liara.ir;

        proxy_redirect https://package-mirror.liara.ir/repository/pypi/ https://$host/;
        proxy_redirect http://package-mirror.liara.ir/repository/pypi/ http://$host/;
        proxy_redirect https://package-mirror.liara.ir/repository/pypi https://$host;
        proxy_redirect http://package-mirror.liara.ir/repository/pypi http://$host;

        gunzip on;
        sub_filter_once off;
        sub_filter_types application/vnd.pypi.simple.v1+json application/json text/plain;
        sub_filter https://package-mirror.liara.ir/repository/pypi/ https://$host/;
        sub_filter http://package-mirror.liara.ir/repository/pypi/ http://$host/;

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
