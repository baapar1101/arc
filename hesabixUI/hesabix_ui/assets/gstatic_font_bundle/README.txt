آینهٔ محلی fonts.gstatic.com/s/ برای Flutter Web (fontFallbackBaseUrl در web/index.html).
هدف: بدون وابستگی به CDN گوگل در runtime — مناسب محدودیت‌های شبکه در ایران.

گردش کار:
  1. bash scripts/extract_flutter_gstatic_font_paths.sh   # پس از ارتقای Flutter
  2. bash scripts/populate_gstatic_font_bundle.sh         # دانلود یک‌بار (نیاز به اینترنت/VPN)
     شامل shardهای واقعی notocoloremoji (نه stub یکسان)
  3. git add assets/gstatic_font_bundle && commit

اگر fonts.gstatic.com در دسترس نیست:
  GSTATIC_BASE_URL=https://آینه-شما/s bash scripts/populate_gstatic_font_bundle.sh

بیلد/دیپلوی: sync_font_fallback_mirror.sh از build_web.sh و run_web.sh فراخوانی می‌شود.
اختیاری در بیلد ناقص: SYNC_FONT_FETCH_NETWORK=1 (فقط توسعه؛ ترجیحاً باندل کامل در repo).

خانواده‌های تاریخی/نادر (هیروگلیف، میخی، …) طبق scripts/web_gstatic_rare_families.txt
به‌صورت پیش‌فرض به web کپی نمی‌شوند. برای دیپلوی کامل:
  SYNC_FONT_INCLUDE_RARE=1 bash scripts/sync_font_fallback_mirror.sh

نکته: فونت مونolith NotoColorEmoji-Regular.ttf از FontManifest حذف شده؛
ایموجی فقط از shardهای محلی fonts/gstatic/s/notocoloremoji به‌صورت lazy لود می‌شود.
