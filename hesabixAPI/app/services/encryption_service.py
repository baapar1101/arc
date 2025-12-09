"""
سرویس رمزنگاری و رمزگشایی اطلاعات حساس
"""
from __future__ import annotations

import base64
import os
from typing import Optional

from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.backends import default_backend

from app.core.settings import get_settings


class EncryptionService:
    """
    سرویس رمزنگاری با استفاده از Fernet (symmetric encryption)
    """

    def __init__(self, encryption_key: Optional[str] = None):
        """
        Args:
            encryption_key: کلید رمزنگاری (base64). اگر None باشد از تنظیمات خوانده می‌شود.
        """
        if encryption_key is None:
            settings = get_settings()
            # TODO: باید در settings یک ENCRYPTION_KEY تعریف شود
            # برای الان از SECRET_KEY استفاده می‌کنیم
            secret = getattr(settings, 'secret_key', 'default-secret-key-change-me')
            encryption_key = self._derive_key_from_secret(secret)
        
        self.cipher = Fernet(encryption_key.encode() if isinstance(encryption_key, str) else encryption_key)

    @staticmethod
    def _derive_key_from_secret(secret: str, salt: Optional[bytes] = None) -> str:
        """
        تولید کلید رمزنگاری از روی یک secret
        
        Args:
            secret: رشته secret
            salt: نمک برای KDF (اگر None باشد یک salt ثابت استفاده می‌شود)
        
        Returns:
            کلید base64 برای Fernet
        """
        if salt is None:
            # استفاده از salt ثابت (در production باید از environment variable خوانده شود)
            salt = b'hesabix-tax-salt-2025'
        
        kdf = PBKDF2HMAC(
            algorithm=hashes.SHA256(),
            length=32,
            salt=salt,
            iterations=100000,
            backend=default_backend()
        )
        key = base64.urlsafe_b64encode(kdf.derive(secret.encode()))
        return key.decode()

    def encrypt(self, plaintext: str) -> str:
        """
        رمزنگاری متن
        
        Args:
            plaintext: متن اصلی
        
        Returns:
            متن رمزشده (base64)
        """
        if not plaintext:
            return ""
        
        encrypted_bytes = self.cipher.encrypt(plaintext.encode('utf-8'))
        return base64.urlsafe_b64encode(encrypted_bytes).decode('utf-8')

    def decrypt(self, ciphertext: str) -> str:
        """
        رمزگشایی متن
        
        Args:
            ciphertext: متن رمزشده
        
        Returns:
            متن اصلی
        """
        if not ciphertext:
            return ""
        
        try:
            encrypted_bytes = base64.urlsafe_b64decode(ciphertext.encode('utf-8'))
            decrypted_bytes = self.cipher.decrypt(encrypted_bytes)
            return decrypted_bytes.decode('utf-8')
        except Exception:
            # اگر رمزگشایی ناموفق بود، احتمالا متن رمز نشده است
            # برای سازگاری با داده‌های قدیمی
            return ciphertext

    def is_encrypted(self, text: str) -> bool:
        """
        بررسی اینکه آیا متن رمز شده است یا خیر
        
        Args:
            text: متن برای بررسی
        
        Returns:
            True اگر احتمالا رمز شده باشد
        """
        if not text:
            return False
        
        try:
            # تلاش برای decode کردن
            base64.urlsafe_b64decode(text.encode('utf-8'))
            # اگر decode شد، احتمالا رمز شده است
            return True
        except Exception:
            return False


# Instance سراسری
_encryption_service: Optional[EncryptionService] = None


def get_encryption_service() -> EncryptionService:
    """دریافت instance سرویس رمزنگاری"""
    global _encryption_service
    if _encryption_service is None:
        _encryption_service = EncryptionService()
    return _encryption_service


def encrypt_private_key(private_key: str) -> str:
    """
    رمزنگاری کلید خصوصی
    
    Args:
        private_key: کلید خصوصی PEM
    
    Returns:
        کلید رمز شده
    """
    service = get_encryption_service()
    return service.encrypt(private_key)


def decrypt_private_key(encrypted_key: str) -> str:
    """
    رمزگشایی کلید خصوصی
    
    Args:
        encrypted_key: کلید رمز شده
    
    Returns:
        کلید اصلی PEM
    """
    service = get_encryption_service()
    return service.decrypt(encrypted_key)

