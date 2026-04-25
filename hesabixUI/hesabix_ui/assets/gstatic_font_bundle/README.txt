پوشهٔ s/ همان ساختار نسبی fonts.gstatic.com/s/ است و در sync_font_fallback_mirror.sh به web/build کپی می‌شود.
برای پر کردن یا به‌روز کردن پس از تغییر Flutter / web_gstatic_fallback_font_paths.txt:
  bash hesabix_ui/scripts/populate_gstatic_font_bundle.sh
(با اینترنت؛ سپس فایل‌های جدید را commit کنید.)

ارث‌اختیاری: SYNC_FONT_FETCH_NETWORK=1 روی ماشین توسعه اگر باندل ناقص است.
