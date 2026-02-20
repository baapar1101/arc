"""
سرویس ریستور کامل دیتابیس PostgreSQL برای مدیر سیستم.
از فایل بکاپ .sql یا .sql.gz با pg_dump ایجاد شده استفاده می‌کند.
"""
from __future__ import annotations

import gzip
import io
import logging
import os
import subprocess
import tempfile
from typing import Callable

from app.core.settings import get_settings

logger = logging.getLogger(__name__)

CONFIRMATION_TOKEN = "بازیابی"
CONFIRMATION_TOKEN_EN = "RESTORE"


class DatabaseRestoreError(Exception):
    """خطای ریستور دیتابیس"""

    pass


class DatabaseRestoreService:
    """سرویس ریستور کل دیتابیس PostgreSQL"""

    def __init__(self, on_progress: Callable[[int, str], None] | None = None):
        self.settings = get_settings()
        self._on_progress = on_progress or (lambda p, m: None)

    def _progress(self, percent: int, message: str) -> None:
        if self._on_progress:
            self._on_progress(percent, message)
        logger.info("database_restore_progress", percent=percent, message=message)

    def restore(self, file_path: str) -> None:
        """
        ریستور دیتابیس از فایل بکاپ.
        فایل می‌تواند .sql یا .sql.gz باشد.
        مراحل: قطع اتصالات، drop db، create db، اجرای dump.
        """
        if not os.path.isfile(file_path):
            raise DatabaseRestoreError(f"فایل بکاپ یافت نشد: {file_path}")

        basename = os.path.basename(file_path).lower()
        is_gz = basename.endswith(".sql.gz") or basename.endswith(".gz")
        is_sql = basename.endswith(".sql") or is_gz

        if not is_sql:
            raise DatabaseRestoreError(
                "فرمت فایل نامعتبر است. فایل باید .sql یا .sql.gz باشد."
            )

        env = os.environ.copy()
        env["PGPASSWORD"] = self.settings.db_password

        def run_psql(db_name: str, sql: str, description: str) -> None:
            result = subprocess.run(
                [
                    "psql",
                    "-h",
                    self.settings.db_host,
                    "-p",
                    str(self.settings.db_port),
                    "-U",
                    self.settings.db_user,
                    "-d",
                    db_name,
                    "-v",
                    "ON_ERROR_STOP=1",
                    "-c",
                    sql,
                ],
                env=env,
                capture_output=True,
                text=True,
                timeout=120,
            )
            if result.returncode != 0:
                stderr = (result.stderr or "").strip()
                raise DatabaseRestoreError(
                    f"{description} ناموفق بود: {stderr or result.stdout or 'خطای نامشخص'}"
                ) from None

        self._progress(5, "قطع اتصالات به دیتابیس")
        db_name_safe = self.settings.db_name.replace("'", "''")
        try:
            run_psql(
                "postgres",
                (
                    f"SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
                    f"WHERE datname = '{db_name_safe}' AND pid <> pg_backend_pid();"
                ),
                "قطع اتصالات",
            )
        except DatabaseRestoreError as e:
            logger.warning("terminate_connections_failed: %s", e)
            self._progress(10, "ادامه ریستور (قطع اتصالات ناتوان بود)")

        self._progress(15, "حذف دیتابیس فعلی")
        db_name_id = self.settings.db_name.replace('"', '""')  # for identifier
        try:
            run_psql(
                "postgres",
                f'DROP DATABASE IF EXISTS "{db_name_id}";',
                "حذف دیتابیس",
            )
        except DatabaseRestoreError:
            raise

        self._progress(25, "ایجاد دیتابیس جدید")
        try:
            run_psql(
                "postgres",
                f'CREATE DATABASE "{db_name_id}";',
                "ایجاد دیتابیس",
            )
        except DatabaseRestoreError:
            raise

        self._progress(35, "اجرای فایل بکاپ")
        if is_gz:
            proc = subprocess.Popen(
                ["gunzip", "-c", file_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
            )
            psql_proc = subprocess.Popen(
                [
                    "psql",
                    "-h",
                    self.settings.db_host,
                    "-p",
                    str(self.settings.db_port),
                    "-U",
                    self.settings.db_user,
                    "-d",
                    self.settings.db_name,
                    "-v",
                    "ON_ERROR_STOP=1",
                    "-f",
                    "-",
                ],
                stdin=proc.stdout,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
            )
            proc.stdout.close()
            out, err = psql_proc.communicate(timeout=7200)
            if proc.wait(timeout=5) != 0:
                raise DatabaseRestoreError(
                    f"فشرده‌سازی ناموفق بود: {(proc.stderr or b'').decode('utf-8', errors='replace')}"
                )
            if psql_proc.returncode != 0:
                err_str = (err or b"").decode("utf-8", errors="replace").strip()
                raise DatabaseRestoreError(
                    f"اجرای بکاپ ناموفق بود: {err_str[:500]}"
                )
        else:
            result = subprocess.run(
                [
                    "psql",
                    "-h",
                    self.settings.db_host,
                    "-p",
                    str(self.settings.db_port),
                    "-U",
                    self.settings.db_user,
                    "-d",
                    self.settings.db_name,
                    "-v",
                    "ON_ERROR_STOP=1",
                    "-f",
                    file_path,
                ],
                env=env,
                capture_output=True,
                text=True,
                timeout=7200,
            )
            if result.returncode != 0:
                stderr = (result.stderr or result.stdout or "").strip()
                raise DatabaseRestoreError(
                    f"اجرای بکاپ ناموفق بود: {stderr[:500]}"
                )

        self._progress(100, "ریستور با موفقیت انجام شد")
