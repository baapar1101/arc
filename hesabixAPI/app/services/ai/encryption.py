from __future__ import annotations

from typing import Optional
import os
import base64
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from app.core.settings import get_settings


def _get_encryption_key() -> bytes:
    """دریافت کلید رمزگذاری از تنظیمات"""
    settings = get_settings()
    # استفاده از captcha_secret از settings
    secret = settings.captcha_secret
    salt = b'hesabix_ai_encryption_salt'  # می‌توان از settings خواند
    
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=100000,
    )
    key = base64.urlsafe_b64encode(kdf.derive(secret.encode()))
    return key


def encrypt_api_key(api_key: str) -> str:
    """رمزگذاری API Key"""
    if not api_key:
        return ""
    
    key = _get_encryption_key()
    fernet = Fernet(key)
    encrypted = fernet.encrypt(api_key.encode())
    return encrypted.decode()


def decrypt_api_key(encrypted_key: str) -> Optional[str]:
    """رمزگشایی API Key"""
    if not encrypted_key:
        return None
    
    try:
        key = _get_encryption_key()
        fernet = Fernet(key)
        decrypted = fernet.decrypt(encrypted_key.encode())
        return decrypted.decode()
    except Exception:
        return None

