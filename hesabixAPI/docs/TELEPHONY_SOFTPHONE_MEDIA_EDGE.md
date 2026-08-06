# Softphone Media Edge (WebSocket + REST وابسته به media_hub)

## مشکل

`media_hub` در حافظهٔ هر process uvicorn نگه داشته می‌شود. با `--workers N` (N>1):

1. کلاینت Softphone به worker A وصل می‌شود
2. تونل Connector ممکن است روی worker B باشد
3. `POST .../softphone/calls` به worker C می‌رود → `SOFTPHONE_WS_REQUIRED`

## راه‌حل استاندارد

یک سرویس جدا با **`--workers 1`** روی پورت `8001` (`hesabix-api-media.service`) و مسیریابی nginx:

| مسیر | مقصد |
|------|------|
| `/ws/telephony/*` | Media Edge `:8001` |
| `/api/v1/telephony/business/*/softphone/*` | Media Edge `:8001` |
| `/api/v1/telephony/connector/media*` | Media Edge `:8001` |
| بقیه API/WS | API عمومی `:8000` |

نقش process از env:

- `HESABIX_PROCESS_ROLE=media_edge` روی سرویس Media
- `HESABIX_PROCESS_ROLE=api` روی API عمومی (رد کردن softphone media اگر nginx اشتباه بود)
- `HESABIX_PROCESS_ROLE=auto` برای dev تک‌process

## نصب روی همین سرور

```bash
# upstream
sudo cp hesabixAPI/nginx-conf.d/hesabix-media-edge-upstream.conf /etc/nginx/conf.d/

# include داخل serverهای arc و hsxn قبل از /api/ و /ws/
# include /opt/hesabix/app/hesabixAPI/nginx-snippets/hesabix-media-edge-locations.inc;

sudo cp hesabixAPI/deployment/systemd/hesabix-api-media.service /etc/systemd/system/
# روی hesabix-api.service: Environment=HESABIX_PROCESS_ROLE=api

sudo systemctl daemon-reload
sudo systemctl enable --now hesabix-api-media.service
sudo nginx -t && sudo systemctl reload nginx
sudo systemctl restart hesabix-api.service
```

پس از استقرار، Connector باید تونل `/ws/telephony/connector/media` را دوباره وصل کند (معمولاً با reconnect خودکار).
