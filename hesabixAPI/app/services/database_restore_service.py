"""
سرویس ریستور کامل دیتابیس PostgreSQL برای مدیر سیستم.
از فایل بکاپ .sql یا .sql.gz با pg_dump ایجاد شده استفاده می‌کند.
"""

from __future__ import annotations

import gzip
import logging
import os
import shutil
import subprocess
import tempfile
from collections.abc import Callable
from pathlib import Path

from app.core.postgres_tools import PostgreSQLToolNotFoundError, resolve_postgres_tool
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
        logger.info("database_restore_progress percent=%s message=%s", percent, message)

    @staticmethod
    def _prepare_sql_file(file_path: str, is_gz: bool) -> tuple[str, Path | None]:
        """Return a plain SQL path, expanding gzip with Python when needed."""
        if not is_gz:
            return file_path, None

        temporary_path: Path | None = None
        try:
            with tempfile.NamedTemporaryFile(
                prefix="hesabix-restore-",
                suffix=".sql",
                delete=False,
            ) as destination:
                temporary_path = Path(destination.name)
                with gzip.open(file_path, "rb") as source:
                    shutil.copyfileobj(source, destination, length=1024 * 1024)
            return str(temporary_path), temporary_path
        except Exception:
            if temporary_path is not None:
                temporary_path.unlink(missing_ok=True)
            raise

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
            raise DatabaseRestoreError("فرمت فایل نامعتبر است. فایل باید .sql یا .sql.gz باشد.")

        env = os.environ.copy()
        env["PGPASSWORD"] = self.settings.db_password

        try:
            psql = resolve_postgres_tool("psql", environment=env)
        except PostgreSQLToolNotFoundError as e:
            raise DatabaseRestoreError(
                "ابزار psql یافت نشد. PostgreSQL client tools را نصب کنید یا "
                "HESABIX_POSTGRES_BIN_DIR را تنظیم کنید."
            ) from e

        try:
            restore_file_path, temporary_sql_path = self._prepare_sql_file(file_path, is_gz)
        except (OSError, gzip.BadGzipFile, EOFError) as e:
            raise DatabaseRestoreError(f"فایل فشرده بکاپ قابل خواندن نیست: {e}") from e

        def run_psql(db_name: str, sql: str, description: str) -> None:
            result = subprocess.run(
                [
                    str(psql),
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

        try:
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
            run_psql(
                "postgres",
                f'DROP DATABASE IF EXISTS "{db_name_id}";',
                "حذف دیتابیس",
            )

            self._progress(25, "ایجاد دیتابیس جدید")
            run_psql(
                "postgres",
                f'CREATE DATABASE "{db_name_id}";',
                "ایجاد دیتابیس",
            )

            self._progress(35, "اجرای فایل بکاپ")
            result = subprocess.run(
                [
                    str(psql),
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
                    restore_file_path,
                ],
                env=env,
                capture_output=True,
                text=True,
                timeout=7200,
            )
            if result.returncode != 0:
                stderr = (result.stderr or result.stdout or "").strip()
                raise DatabaseRestoreError(f"اجرای بکاپ ناموفق بود: {stderr[:500]}")
            self._progress(100, "ریستور با موفقیت انجام شد")
        finally:
            if temporary_sql_path is not None:
                temporary_sql_path.unlink(missing_ok=True)
