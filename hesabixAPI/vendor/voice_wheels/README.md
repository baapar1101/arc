# Wheelهای آفلاین برای `[voice]`

روی سرورهایی که فقط `p.mirror.hesabix.ir` در دسترس است، برخی بسته‌ها (مثل `webrtcvad-wheels`) ممکن است روی آینه نباشند.

## روش ۱ — پر کردن این پوشه (توصیه برای deploy آفلاین)

روی ماشینی با دسترسی به PyPI:

```bash
cd /path/to/hesabix/app
bash scripts/populate_voice_wheels_vendor.sh
# سپس پوشه vendor/voice_wheels را به سرور منتقل کنید (rsync/git-lfs)
```

روی سرور:

```bash
INSTALL_VOICE=Y bash scripts/ensure_voice_chat.sh --non-interactive
```

## روش ۲ — آپلود به آینه Nexus

فهرست نام پکیج‌ها: `scripts/pypi_voice_packages.txt` (شامل `piper-tts` به‌جای `TTS`/torch)

## روش ۳ — ایندکس کمکی (اگر سرور به PyPI دسترسی دارد)

```bash
export VOICE_PIP_FALLBACK_INDEX_URL=https://pypi.devneeds.ir/simple/
export VOICE_PIP_EXTRA_INDEX_URL=https://pypi.org/simple
INSTALL_VOICE=Y bash scripts/ensure_voice_chat.sh
```
