# include داخل server { } — gradle.mirror.hesabix.ir
# Runflare (mirror-maven): distributions، android/maven2، maven2، gradle-plugins
# هدر X-Forwarded-For/X-Real-IP به upstream نفرست.
# همان ریسک لینک مطلق PyPI اینجا کمتر است؛ Maven metadata پاسخ‌ها عمدتاً نسبی/بدون دامنهٔ runflare بوده‌اند.

    location = / {
        default_type text/plain; charset utf-8;
        return 200 "Gradle/Android mirror (Runflare). Base: https://gradle.mirror.hesabix.ir — distributions, android/maven2, maven2, gradle-plugins\n";
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

    location /distributions/ {
        proxy_pass https://hesabix_runflare_gradle/distributions/;

        proxy_set_header Host mirror-maven.runflare.com;
        proxy_set_header X-Forwarded-For "";
        proxy_set_header X-Real-IP "";
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        proxy_ssl_server_name on;
        proxy_ssl_name mirror-maven.runflare.com;

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
        proxy_pass https://hesabix_runflare_gradle/android/maven2/;

        proxy_set_header Host mirror-maven.runflare.com;
        proxy_set_header X-Forwarded-For "";
        proxy_set_header X-Real-IP "";
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        proxy_ssl_server_name on;
        proxy_ssl_name mirror-maven.runflare.com;

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
        proxy_pass https://hesabix_runflare_gradle/maven2/;

        proxy_set_header Host mirror-maven.runflare.com;
        proxy_set_header X-Forwarded-For "";
        proxy_set_header X-Real-IP "";
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        proxy_ssl_server_name on;
        proxy_ssl_name mirror-maven.runflare.com;

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
        proxy_pass https://hesabix_runflare_gradle/gradle-plugins/;

        proxy_set_header Host mirror-maven.runflare.com;
        proxy_set_header X-Forwarded-For "";
        proxy_set_header X-Real-IP "";
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        proxy_ssl_server_name on;
        proxy_ssl_name mirror-maven.runflare.com;

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
