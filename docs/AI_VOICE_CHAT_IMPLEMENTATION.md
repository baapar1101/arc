# پیاده‌سازی گفت‌وگوی صوتی (دوطرفه و استریم) برای AI

این سند وضعیت فعلی پیاده‌سازی «Voice Chat» را توضیح می‌دهد و نحوه فعال‌سازی آن را مشخص می‌کند.

## Endpoint

- **WebSocket**: `\`/ws/ai/voice?api_key=...\``
- **رویداد شروع** (JSON):
  - `{"type":"start","session_id":123,"collect_data":true}`
- **ورودی صوت**: فریم‌های باینری **PCM16LE mono 16kHz** (مثلاً 20ms)
- **خروجی**:
  - رویدادهای JSON (متن/وضعیت)
  - فریم‌های باینری PCM16LE به عنوان خروجی TTS (برای پخش استریم)

## تنظیمات (ENV / Settings)

در `\`hesabixAPI/app/core/settings.py\`` تنظیمات زیر اضافه شده:

- `voice_enabled`
- `voice_*` برای VAD/STT/TTS
- `voice_tts_engine`: پیش‌فرض `dummy` (برای تست). برای تولید واقعی، `coqui`
- `voice_tts_model_name` یا `voice_tts_model_path`: **الزامی** وقتی `coqui` فعال است
- `voice_data_collection_enabled` و `voice_data_collection_dir` برای ذخیره داده‌های opt-in

## نصب وابستگی‌ها (Backend)

در `\`hesabixAPI/pyproject.toml\`` یک گروه optional با نام `voice` اضافه شده است:

```bash
cd /var/www/ark/hesabixAPI
pip install -e ".[voice]"
```

> نکته: این گروه معمولاً `torch` را هم نصب می‌کند و سنگین است؛ بهتر است فقط روی سروری که Voice Chat فعال است نصب شود.

## دیتابیس

یک جدول جدید برای ذخیره تعاملات opt-in اضافه شده است:
- `ai_voice_interactions`

Migration:
- `\`hesabixAPI/migrations/versions/20251223_002500_create_ai_voice_interactions.py\``

## وضعیت فعلی

- ✅ WebSocket دوطرفه اضافه شده
- ✅ VAD/Endpointing اضافه شده (`webrtcvad`)
- ✅ STT با `faster-whisper` (Lazy import)
- ✅ TTS پلاگین‌پذیر:
  - `dummy` (برای تست)
  - `coqui` (نیاز به تعیین مدل)
- ✅ ذخیره داده opt-in در دیسک + ثبت در DB
- ✅ ذخیره پیام assistant و انجام charge/log_usage برای LLM

## گام‌های بعدی پیشنهادی

- افزودن UI/Service در Flutter برای:
  - ضبط PCM16
  - ارسال فریم‌ها روی WS
  - پخش خروجی PCM استریم
  - barge-in (قطع پاسخ هنگام شروع صحبت کاربر)
- اضافه کردن endpoint برای ثبت **rating/feedback** روی `ai_voice_interactions`
- اضافه کردن استراتژی encode Opus (فاز ۲) برای کاهش پهنای باند


