# include داخل server { } — توسط f.mirror.hesabix.ir.conf
# upstream: https://pub-azs.ir (همان سرویسی که با PUB_HOSTED_URL و FLUTTER_STORAGE_BASE_URL مستقیم استفاده می‌شود)
# مسیر کلاینت: /pub/... → pub-azs.ir/...  و  /gcs/... → pub-azs.ir/... (مثلاً flutter_infra_release/...)
# X-Forwarded-For/X-Real-IP به upstream نفرستیم (هم‌راستا با سایر آینه‌های hesabix).
#
# JSON پاب ممکن است لینک مطلق pub-azs.ir یا pub.dev بدهد؛ در location /pub به $host/pub بازنویسی می‌شود.

    location = / {
        default_type text/plain; charset utf-8;
        return 200
"Dart/Flutter proxy cache (pub-azs.ir upstream). Set:\n  PUB_HOSTED_URL=https://f.mirror.hesabix.ir/pub\n  FLUTTER_STORAGE_BASE_URL=https://f.mirror.hesabix.ir/gcs\n";
    }

    location = /pub {
        default_type text/plain; charset utf-8;
        return 200 "ok\n";
    }
    location = /gcs {
        default_type text/plain; charset utf-8;
        return 200 "ok\n";
    }

    location ^~ /pub/api/archives/ {
        proxy_pass https://pub-azs.ir/api/archives/;

        proxy_set_header Host pub-azs.ir;
        proxy_set_header X-Forwarded-For "";
        proxy_set_header X-Real-IP "";
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        proxy_ssl_server_name on;
        proxy_ssl_name pub-azs.ir;

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

        proxy_buffers 32 32k;
        proxy_buffer_size 64k;

        add_header X-Cache-Status $upstream_cache_status always;
    }

    location /pub/ {
        proxy_pass https://pub-azs.ir/;

        proxy_set_header Host pub-azs.ir;
        proxy_set_header X-Forwarded-For "";
        proxy_set_header X-Real-IP "";
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Accept-Encoding "";

        proxy_ssl_server_name on;
        proxy_ssl_name pub-azs.ir;

        proxy_redirect https://pub-azs.ir/ https://$host/pub/;
        proxy_redirect http://pub-azs.ir/ http://$host/pub/;
        proxy_redirect https://pub.dev/ https://$host/pub/;
        proxy_redirect http://pub.dev/ http://$host/pub/;

        gunzip on;
        sub_filter_once off;
        sub_filter_types application/json application/vnd.pub.v2+json application/vnd.pub+json;
        sub_filter https://pub-azs.ir/ https://$host/pub/;
        sub_filter http://pub-azs.ir/ http://$host/pub/;
        sub_filter https://pub.dev/ https://$host/pub/;
        sub_filter http://pub.dev/ http://$host/pub/;

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
        proxy_pass https://pub-azs.ir/;

        proxy_set_header Host pub-azs.ir;
        proxy_set_header X-Forwarded-For "";
        proxy_set_header X-Real-IP "";
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        proxy_ssl_server_name on;
        proxy_ssl_name pub-azs.ir;

        proxy_redirect https://pub-azs.ir/ https://$host/gcs/;
        proxy_redirect http://pub-azs.ir/ http://$host/gcs/;
        proxy_redirect https://storage.googleapis.com/ https://$host/gcs/;
        proxy_redirect http://storage.googleapis.com/ http://$host/gcs/;

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
