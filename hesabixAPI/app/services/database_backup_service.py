"""
سرویس بکاپ دیتابیس PostgreSQL برای مدیر سیستم.
پشتیبانی از سه روش تحویل: دانلود مستقیم، ایمیل، FTP.
"""
from __future__ import annotations

import gzip
import io
import logging
import os
import subprocess
import tempfile
from datetime import datetime
from typing import Literal

from sqlalchemy.orm import Session

from app.core.settings import get_settings
from adapters.db.models.file_storage import StorageConfig

logger = logging.getLogger(__name__)

DeliveryType = Literal["download", "email", "ftp"]


class DatabaseBackupError(Exception):
    """خطای بکاپ دیتابیس"""

    pass


class DatabaseBackupService:
    """سرویس بکاپ کل دیتابیس PostgreSQL"""

    def __init__(self, db: Session):
        self.db = db
        self.settings = get_settings()

    def create_backup(self, compress: bool = True) -> bytes:
        """
        ایجاد بکاپ کامل دیتابیس با pg_dump.
        خروجی به صورت plain SQL یا gzip شده.
        """
        env = os.environ.copy()
        env["PGPASSWORD"] = self.settings.db_password

        cmd = [
            "pg_dump",
            "-h",
            self.settings.db_host,
            "-p",
            str(self.settings.db_port),
            "-U",
            self.settings.db_user,
            "-d",
            self.settings.db_name,
            "--no-owner",
            "--no-acl",
        ]

        try:
            result = subprocess.run(
                cmd,
                env=env,
                capture_output=True,
                timeout=3600,
                check=True,
            )
            raw_data = result.stdout
        except subprocess.TimeoutExpired:
            raise DatabaseBackupError("زمان بکاپ به پایان رسید (timeout)")
        except subprocess.CalledProcessError as e:
            stderr = (e.stderr or b"").decode("utf-8", errors="replace")
            logger.error("pg_dump failed: %s", stderr)
            raise DatabaseBackupError(f"خطا در pg_dump: {stderr[:200]}")
        except FileNotFoundError:
            raise DatabaseBackupError(
                "ابزار pg_dump یافت نشد. لطفاً PostgreSQL client tools را نصب کنید."
            )
        except Exception as e:
            logger.exception("database_backup_unexpected_error")
            raise DatabaseBackupError(str(e)) from e

        if compress:
            buf = io.BytesIO()
            with gzip.GzipFile(fileobj=buf, mode="wb") as gz:
                gz.write(raw_data)
            return buf.getvalue()
        return raw_data

    def get_backup_filename(self, compress: bool = True) -> str:
        ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        ext = "sql.gz" if compress else "sql"
        return f"hesabix_db_backup_{ts}.{ext}"

    def deliver_download(self, compress: bool = True) -> tuple[bytes, str]:
        """بکاپ برای دانلود مستقیم. برمی‌گرداند (content, filename)."""
        content = self.create_backup(compress=compress)
        filename = self.get_backup_filename(compress=compress)
        return content, filename

    def deliver_email(
        self,
        to_email: str,
        config_id: int | None = None,
        compress: bool = True,
    ) -> bool:
        """ارسال بکاپ به ایمیل به صورت پیوست."""
        from app.services.email_service import EmailService

        content = self.create_backup(compress=compress)
        filename = self.get_backup_filename(compress=compress)
        email_service = EmailService(self.db)
        return email_service.send_email_with_attachment(
            to=to_email,
            subject=f"بکاپ دیتابیس Hesabix - {datetime.utcnow().strftime('%Y-%m-%d %H:%M')}",
            body="فایل بکاپ دیتابیس در پیوست این ایمیل قرار دارد.",
            attachment_filename=filename,
            attachment_content=content,
            config_id=config_id,
        )

    def deliver_ftp(
        self,
        storage_config_id: str,
        compress: bool = True,
    ) -> dict:
        """آپلود بکاپ به سرور FTP. از StorageConfig با storage_type=ftp استفاده می‌کند."""
        config = (
            self.db.query(StorageConfig)
            .filter(
                StorageConfig.id == storage_config_id,
                StorageConfig.storage_type == "ftp",
                StorageConfig.is_active == True,
            )
            .first()
        )
        if not config:
            raise DatabaseBackupError("تنظیمات FTP یافت نشد یا نامعتبر است.")

        config_data = config.config_data or {}
        host = config_data.get("host")
        port = int(config_data.get("port", 21))
        username = config_data.get("username")
        password = config_data.get("password")
        directory = config_data.get("directory", "/")
        use_tls = config_data.get("use_tls", False)

        if not all([host, username, password]):
            raise DatabaseBackupError("پارامترهای ضروری FTP (host, username, password) موجود نیست")

        content = self.create_backup(compress=compress)
        filename = self.get_backup_filename(compress=compress)

        import ftplib

        try:
            if use_tls:
                ftp = ftplib.FTP_TLS()
            else:
                ftp = ftplib.FTP()
            ftp.connect(host, port, timeout=60)
            ftp.login(username, password)
            if use_tls and hasattr(ftp, "prot_p"):
                ftp.prot_p()

            if directory and directory != "/":
                try:
                    ftp.cwd(directory)
                except ftplib.error_perm:
                    raise DatabaseBackupError(
                        f"دسترسی به دایرکتوری {directory} وجود ندارد یا مسیر وجود ندارد"
                    ) from None

            buf = io.BytesIO(content)
            ftp.storbinary(f"STOR {filename}", buf)
            ftp.quit()
        except ftplib.error_perm as e:
            raise DatabaseBackupError(f"خطای FTP: {str(e)}") from e
        except ftplib.error_temp as e:
            raise DatabaseBackupError(f"خطای موقت FTP: {str(e)}") from e
        except Exception as e:
            logger.exception("ftp_upload_failed")
            raise DatabaseBackupError(str(e)) from e

        return {
            "success": True,
            "filename": filename,
            "host": host,
            "directory": directory,
            "size_bytes": len(content),
        }
