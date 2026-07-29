from __future__ import annotations

from typing import Optional
import base64
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from app.core.settings import get_settings

_AI_ENCRYPTION_SALT = b"hesabix_ai_encryption_salt"


def _is_valid_fernet_key(key: str | bytes) -> bool:
    try:
        raw = key.encode() if isinstance(key, str) else key
        Fernet(raw)
        return True
    except (ValueError, TypeError):
        return False


def _derive_fernet_key(secret: str, *, salt: bytes = _AI_ENCRYPTION_SALT) -> bytes:
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=100000,
    )
    return base64.urlsafe_b64encode(kdf.derive(secret.encode()))


def _get_encryption_key() -> bytes:
    """دریافت کلید رمزگذاری از تنظیمات"""
    settings = get_settings()
    raw_key = (settings.encryption_key or "").strip()
    if raw_key:
        if _is_valid_fernet_key(raw_key):
            return raw_key.encode()
        # ENCRYPTION_KEY ممکن است hex یا secret خام باشد، نه کلید Fernet
        return _derive_fernet_key(raw_key)

    return _derive_fernet_key(settings.captcha_secret)


def _legacy_decryption_keys() -> list[bytes]:
    """کلیدهای قدیمی برای رمزگشایی داده‌هایی که قبل از اصلاح ذخیره شده‌اند."""
    settings = get_settings()
    keys: list[bytes] = []
    if (settings.encryption_key or "").strip():
        keys.append(_derive_fernet_key(settings.captcha_secret))
    return keys


def encrypt_api_key(api_key: str) -> str:
    """رمزگذاری API Key"""
    if not api_key:
        return ""

    fernet = Fernet(_get_encryption_key())
    encrypted = fernet.encrypt(api_key.encode())
    return encrypted.decode()


def decrypt_api_key(encrypted_key: str) -> Optional[str]:
    """رمزگشایی API Key"""
    if not encrypted_key:
        return None

    candidate_keys = [_get_encryption_key(), *_legacy_decryption_keys()]
    seen: set[bytes] = set()
    for key in candidate_keys:
        if key in seen:
            continue
        seen.add(key)
        try:
            decrypted = Fernet(key).decrypt(encrypted_key.encode())
            return decrypted.decode()
        except Exception:
            continue
    return None
