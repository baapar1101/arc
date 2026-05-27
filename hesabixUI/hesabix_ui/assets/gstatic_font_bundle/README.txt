آینهٔ محلی fonts.gstatic.com/s/ برای Flutter Web (fontFallbackBaseUrl در web/index.html).
هدف: بدون وابستگی به CDN گوگل در runtime — مناسب محدودیت‌های شبکه در ایران.

گردش کار:
  1. bash scripts/extract_flutter_gstatic_font_paths.sh   # پس از ارتقای Flutter
  2. bash scripts/populate_gstatic_font_bundle.sh         # دانلود یک‌بار (نیاز به اینترنت/VPN)
  3. git add assets/gstatic_font_bundle && commit

اگر fonts.gstatic.com در دسترس نیست:
  GSTATIC_BASE_URL=https://آینه-شما/s bash scripts/populate_gstatic_font_bundle.sh

بیلد/دیپلوی: sync_font_fallback_mirror.sh از build_web.sh و run_web.sh فراخوانی می‌شود.
اختیاری در بیلد ناقص: SYNC_FONT_FETCH_NETWORK=1 (فقط توسعه؛ ترجیحاً باندل کامل در repo).
