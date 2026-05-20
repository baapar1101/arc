# include داخل server { } — gradle.mirror.hesabix.ir
# upstream: https://maven.myket.ir (Maven مایکت)
# نگاشت مسیر نسبت به مایکت:
#   /distributions/…     → /gradle/distributions/…
#   /maven2/…            → /… (بدون پیشوند maven2، مثل Central روی مایکت)
#   /android/maven2/…    → /… (androidx/com.google… بدون android/maven2)
#   /gradle-plugins/…    → /… (پلاگین‌ها در ریشهٔ org/… روی مایکت)
#
# X-Forwarded-For/X-Real-IP خالی (هم‌راستا با سایر آینه‌های hesabix).

    location = / {
        default_type text/plain; charset utf-8;
        return 200 "Gradle/Android proxy (Hesabix → Myket). Base: https://gradle.mirror.hesabix.ir — distributions, android/maven2, maven2, gradle-plugins\n";
    }

    location = /distributions {
        default_type text/plain; charset utf-8;
        return 200 "ok\n";
    }
    location = /maven2 {
        default_type text/plain; charset utf-8;
        return 200 "ok\n";
    }
    location = /gradle-plugins {
        default_type text/plain; charset utf-8;
        return 200 "ok\n";
    }

    location = /android/maven2 {
        default_type text/plain; charset utf-8;
        return 200 "ok\n";
    }

    location /distributions/ {
        proxy_pass https://maven.myket.ir/gradle/distributions/;

        proxy_set_header Host maven.myket.ir;
        proxy_set_header X-Forwarded-For "";
        proxy_set_header X-Real-IP "";
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        proxy_ssl_server_name on;
        proxy_ssl_name maven.myket.ir;

        proxy_connect_timeout 30s;
        proxy_send_timeout 600s;
        proxy_read_timeout 600s;

        proxy_cache gradle_mirror_cache;
        proxy_cache_key "$scheme$request_method$host$request_uri";
        proxy_cache_methods GET HEAD;
        proxy_cache_valid 200 302 7d;
        proxy_cache_valid 404 1h;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
        proxy_cache_lock on;
        proxy_cache_background_update on;
        proxy_ignore_headers Cache-Control Set-Cookie;

        proxy_buffers 32 32k;
        proxy_buffer_size 64k;

        add_header X-Cache-Status $upstream_cache_status always;
    }

    location /android/maven2/ {
        proxy_pass https://maven.myket.ir/;

        proxy_set_header Host maven.myket.ir;
        proxy_set_header X-Forwarded-For "";
        proxy_set_header X-Real-IP "";
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        proxy_ssl_server_name on;
        proxy_ssl_name maven.myket.ir;

        proxy_connect_timeout 10s;
        proxy_send_timeout 600s;
        proxy_read_timeout 600s;

        proxy_cache gradle_mirror_cache;
        proxy_cache_key "$scheme$request_method$host$request_uri";
        proxy_cache_methods GET HEAD;
        proxy_cache_valid 200 302 7d;
        proxy_cache_valid 404 1h;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
        proxy_cache_lock on;
        proxy_cache_background_update on;
        proxy_ignore_headers Cache-Control Set-Cookie;

        proxy_buffers 32 32k;
        proxy_buffer_size 64k;

        add_header X-Cache-Status $upstream_cache_status always;
    }

    location /maven2/ {
        proxy_pass https://maven.myket.ir/;

        proxy_set_header Host maven.myket.ir;
        proxy_set_header X-Forwarded-For "";
        proxy_set_header X-Real-IP "";
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        proxy_ssl_server_name on;
        proxy_ssl_name maven.myket.ir;

        proxy_connect_timeout 10s;
        proxy_send_timeout 600s;
        proxy_read_timeout 600s;

        proxy_cache gradle_mirror_cache;
        proxy_cache_key "$scheme$request_method$host$request_uri";
        proxy_cache_methods GET HEAD;
        proxy_cache_valid 200 302 7d;
        proxy_cache_valid 404 1h;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
        proxy_cache_lock on;
        proxy_cache_background_update on;
        proxy_ignore_headers Cache-Control Set-Cookie;

        proxy_buffers 32 32k;
        proxy_buffer_size 64k;

        add_header X-Cache-Status $upstream_cache_status always;
    }

    location /gradle-plugins/ {
        proxy_pass https://maven.myket.ir/;

        proxy_set_header Host maven.myket.ir;
        proxy_set_header X-Forwarded-For "";
        proxy_set_header X-Real-IP "";
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        proxy_ssl_server_name on;
        proxy_ssl_name maven.myket.ir;

        proxy_connect_timeout 10s;
        proxy_send_timeout 600s;
        proxy_read_timeout 600s;

        proxy_cache gradle_mirror_cache;
        proxy_cache_key "$scheme$request_method$host$request_uri";
        proxy_cache_methods GET HEAD;
        proxy_cache_valid 200 302 7d;
        proxy_cache_valid 404 1h;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
        proxy_cache_lock on;
        proxy_cache_background_update on;
        proxy_ignore_headers Cache-Control Set-Cookie;

        proxy_buffers 32 32k;
        proxy_buffer_size 64k;

        add_header X-Cache-Status $upstream_cache_status always;
    }
