# پیاده‌سازی گفت‌وگوی صوتی (دوطرفه و استریم) برای AI

## فازهای اجرایی

| فاز | محتوا | وضعیت |
|-----|--------|--------|
| **۱ — بک‌اند** | پردازش utterance غیرمسدودکننده، availability قبل از ذخیره پیام، رویداد `voice_status`، ثبت `ai_voice_interactions` برای بازخورد، بررسی وابستگی‌ها | ✅ |
| **۲ — فرانت** | state machine (`VoicePhase`)، مسدودسازی چت متنی، reconnect با `start` مجدد، نوار وضعیت | ✅ |
| **۳ — UX / l10n** | متن‌های ترجمه‌شده، میکروفون فقط برای شروع، پایان با دکمه قرمز | ✅ |
| **۴ — کیفیت** | تست‌های کمکی، مستندات، هشدار TTS dummy | ✅ |
| **۵ — وب** | AudioWorklet + WS باینری PCM (بدون base64) | ✅ |
| **۶ — فشرده‌سازی** | WebM/Opus با MediaRecorder مرورگر + PyAV محلی | ✅ |
| **۷ — TTS فارسی** | Piper ONNX محلی (`voice_tts_piper_voice_fa`) — سازگار Python 3.12 | ✅ |

> همه مراحل STT/VAD/TTS/فشرده‌سازی روی **سرور و مرورگر خودتان** اجرا می‌شوند؛ API ابری صوتی استفاده نمی‌شود.

## Endpoint

- **WebSocket**: `/ws/ai/voice` (بدون query؛ `api_key` در URL قرار نگیرد.)
- **احراز هویت** (اولین فریم JSON):
  - `{"type":"auth","api_key":"<کلید_کاربر>"}`
- **شروع جلسه** (پس از `ready`):
  - دسکتاپ/موبایل: `{"type":"start","session_id":123,"input_codec":"pcm","audio_transport":"binary"}`
  - وب (PCM): `input_codec":"pcm"`, `audio_transport":"binary"` — فریم‌های PCM باینری
  - وب (فشرده): `input_codec":"webm_opus"`, `audio_transport":"base64"` — chunkهای `audio_webm` با Opus داخل WebM
- **ورودی صوت**: PCM16LE mono 16kHz (فریم‌های ~20ms توصیه می‌شود؛ VAD در سرور buffer می‌کند)
- **خروجی**:
  - رویدادهای JSON (`transcript_final`, `voice_status`, `assistant_text_delta`, …)
  - فریم PCM16LE یا `assistant_audio` با base64 (وب)

### رویدادهای وضعیت (`voice_status`)

| phase | معنی |
|-------|------|
| `listening` | آماده شنیدن کاربر |
| `thinking` | LLM در حال پردازش |
| `planning_tools` | برنامه‌ریزی ابزار |
| `tool_running` | اجرای ابزار (+ `label` / `tool_key`) |
| `writing` | تولید متن |
| `speaking` | پخش TTS |

## تنظیمات (ENV / Settings)

در `hesabixAPI/app/core/settings.py`:

- `voice_enabled`
- `voice_*` برای VAD/STT/TTS
- `voice_tts_engine`: `dummy` (آزمایش) یا `piper` (تولید، Python 3.12+)
- `voice_tts_piper_voice_fa`: شناسه مدل، مثلاً `fa_IR-ganji-medium`
- `voice_tts_piper_models_dir`: مسیر ذخیره فایل‌های `.onnx`
- `voice_tts_model_name` / `voice_tts_model_path`: override اختیاری Piper
- `coqui`: فقط Python <3.12 (legacy)
- `voice_data_collection_enabled` + `voice_data_collection_dir` برای ذخیره PCM با opt-in

## نصب وابستگی‌ها

### خودکار (deploy / update)

- **deploy.sh**: در پرسش‌ها «Install AI voice chat dependencies?» — با `y` نصب می‌شود.
- **update.sh** (`hesabix -update`): اگر وابستگی‌ها نصب نباشند، همان سؤال پرسیده می‌شود.
- اسکریپت مشترک: `scripts/ensure_voice_chat.sh` (apt libav، `pip install -e ".[voice]"`، `/var/lib/hesabix/voice-data`، تنظیمات نمونه در `.env`)

| متغیر | معنی |
|--------|------|
| `INSTALL_VOICE=Y` | نصب بدون پرسش (با `--non-interactive`) |
| `INSTALL_VOICE=N` | رد کردن |

مقدار `INSTALL_VOICE` در `${APP_ROOT}/.deploy_env` ذخیره می‌شود.

### دستی

```bash
cd hesabixAPI
sudo apt install -y libavformat-dev libavcodec-dev libavutil-dev libswresample-dev libswscale-dev libavdevice-dev pkg-config
pip install -e ".[voice]"
```

### خطای `webrtcvad` روی آینه PyPI

پکیج قدیمی `webrtcvad` برای Python 3.12 wheel ندارد و اغلب روی `p.mirror.hesabix.ir` نیست. پروژه از **`webrtcvad-wheels`** استفاده می‌کند.

| راه‌حل | دستور |
|--------|--------|
| wheel آفلاین | `bash scripts/populate_voice_wheels_vendor.sh` → rsync به `hesabixAPI/vendor/voice_wheels/` |
| آپلود به Nexus | `scripts/pypi_voice_packages.txt` |
| CPU قدیمی (بدون x86-64-v2) | خودکار: `numpy<2` از `https://pypi.devneeds.ir/simple/` (`VOICE_PIP_FALLBACK_INDEX_URL`) |
| PyPI مستقیم | `export VOICE_PIP_EXTRA_INDEX_URL=https://pypi.org/simple` |

## دیتابیس

- جدول `ai_voice_interactions` (بازخورد + opt-in صوتی)
- Migration: `migrations/versions/20251223_002500_create_ai_voice_interactions.py`
- بازخورد: `POST /api/v1/ai/voice/interactions/{id}/feedback`

## کلاینت Flutter

- `lib/services/voice/voice_chat_controller.dart` (io / web)
- `lib/services/voice/voice_phase.dart`
- UI: `ai_chat_dialog.dart` + `ai_chat_composer.dart`

## فایل‌های وب

- `web/hesabix_voice_capture.js` — پل ضبط (Worklet یا MediaRecorder)
- `web/voice_capture_processor.js` — AudioWorklet PCM16 @ 16kHz

## TTS فارسی (محلی — Piper)

```bash
# env نمونه
VOICE_TTS_ENGINE=piper
VOICE_TTS_PIPER_VOICE_FA=fa_IR-ganji-medium
VOICE_TTS_PIPER_MODELS_DIR=/var/lib/hesabix/voice-data/piper
```

مدل‌های فارسی Piper: `fa_IR-ganji-medium`, `fa_IR-amir-medium`, `fa_IR-gyro-medium`, …

```bash
python3 -m piper.download_voices fa_IR-ganji-medium --download-dir /var/lib/hesabix/voice-data/piper
```

یا در نصب voice: `INSTALL_VOICE=Y bash scripts/ensure_voice_chat.sh` (دانلود خودکار).

## گام‌های بعدی (اختیاری)

- A/B کیفیت TTS از روی `rating`
- بهینه‌سازی بیشتر WebM streaming (کاهش latency decode)
