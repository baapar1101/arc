# Softphone Media Edge — include داخل server {} و قبل از location /api/ و /ws/
# کلاینت Softphone، تونل Connector و REST وابسته به media_hub باید به یک process بروند.

location ~ ^/api/v1/telephony/business/[0-9]+/softphone(/|$) {
    proxy_pass http://hesabix_media_edge;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Port $server_port;
    proxy_read_timeout 300;
    proxy_connect_timeout 60;
    proxy_send_timeout 300;
    client_max_body_size 16m;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
}

location ^~ /api/v1/telephony/connector/media {
    proxy_pass http://hesabix_media_edge;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Port $server_port;
    proxy_read_timeout 300;
    proxy_connect_timeout 60;
    proxy_send_timeout 300;
    client_max_body_size 16m;
}

location ^~ /api/v1/telephony/internal/media-edge/ {
    # فقط از localhost؛ برای جلوگیری از افشای snapshot
    allow 127.0.0.1;
    allow ::1;
    deny all;
    proxy_pass http://hesabix_media_edge;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 10;
    proxy_connect_timeout 5;
    proxy_send_timeout 10;
}

location ^~ /ws/telephony/ {
    proxy_pass http://hesabix_media_edge;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Port $server_port;
    proxy_read_timeout 86400;
    proxy_send_timeout 86400;
    proxy_connect_timeout 60;
    proxy_buffering off;
}
