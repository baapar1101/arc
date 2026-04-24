# include داخل server { } — توسط f.mirror.hesabix.ir.conf و f.mirror.hesabix.ir-443.conf
# Runflare: هدر X-Forwarded-For/X-Real-IP به upstream نفرست؛ باعث 402 (payment_required) می‌شود.

    location = / {
        default_type text/plain; charset utf-8;
        return 200
"Dart/Flutter proxy cache (Runflare). Set:\n  PUB_HOSTED_URL=https://f.mirror.hesabix.ir/pub\n  FLUTTER_STORAGE_BASE_URL=https://f.mirror.hesabix.ir/gcs\n";
    }

    location = /pub {
        default_type text/plain; charset utf-8;
        return 200 "ok\n";
    }
    location = /gcs {
        default_type text/plain; charset utf-8;
        return 200 "ok\n";
    }

    location /pub/ {
        proxy_pass https://hesabix_runflare_pub/;

        proxy_set_header Host mirror-flutter.runflare.com;
        proxy_set_header X-Forwarded-For "";
        proxy_set_header X-Real-IP "";
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        # مقدار خالی = این هدرها به Runflare ارسال نشوند (وگرنه 402 credit)

        proxy_ssl_server_name on;
        proxy_ssl_name mirror-flutter.runflare.com;

        proxy_connect_timeout 10s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        proxy_cache flutter_cache;
        proxy_cache_key "$scheme$request_method$host$request_uri";
        proxy_cache_methods GET HEAD;
        proxy_cache_valid 200 302 24h;
        proxy_cache_valid 404 1h;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
        proxy_cache_lock on;
        proxy_cache_background_update on;
        proxy_ignore_headers Cache-Control Set-Cookie;

        proxy_buffers 16 16k;
        proxy_buffer_size 32k;

        add_header X-Cache-Status $upstream_cache_status always;
    }

    location /gcs/ {
        proxy_pass https://hesabix_runflare_gcs/;

        proxy_set_header Host mirror-gcs.runflare.com;
        proxy_set_header X-Forwarded-For "";
        proxy_set_header X-Real-IP "";
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        proxy_ssl_server_name on;
        proxy_ssl_name mirror-gcs.runflare.com;

        proxy_connect_timeout 10s;
        proxy_send_timeout 600s;
        proxy_read_timeout 600s;

        proxy_cache flutter_cache;
        proxy_cache_key "$scheme$request_method$host$request_uri";
        proxy_cache_methods GET HEAD;
        proxy_cache_valid 200 302 24h;
        proxy_cache_valid 404 1h;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
        proxy_cache_lock on;
        proxy_cache_background_update on;
        proxy_ignore_headers Cache-Control Set-Cookie;

        proxy_buffers 32 32k;
        proxy_buffer_size 64k;

        add_header X-Cache-Status $upstream_cache_status always;
    }
