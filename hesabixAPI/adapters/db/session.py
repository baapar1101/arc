from collections.abc import Generator
from contextlib import contextmanager
from typing import Callable, Any
import time
import logging

from sqlalchemy import create_engine, text
from sqlalchemy.exc import OperationalError, TimeoutError as SQLTimeoutError
from sqlalchemy.orm import sessionmaker, DeclarativeBase, Session

from app.core.settings import get_settings

logger = logging.getLogger(__name__)


class Base(DeclarativeBase):
	pass


settings = get_settings()
engine = create_engine(
    settings.mysql_dsn,
    echo=settings.sqlalchemy_echo,
    pool_pre_ping=True,  # بررسی سلامت اتصالات قبل از استفاده
    pool_recycle=3600,  # بازیابی اتصالات هر ساعت
    pool_size=settings.db_pool_size,
    max_overflow=settings.db_max_overflow,
    pool_timeout=settings.db_pool_timeout,
    # تنظیمات اضافی برای بهبود عملکرد
    connect_args={
        "connect_timeout": 10,
        "read_timeout": 30,
        "write_timeout": 30,
    },
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, expire_on_commit=False)


def get_db() -> Generator[Session, None, None]:
	db = SessionLocal()
	try:
		yield db
	finally:
		db.close()


@contextmanager
def get_db_session(retries: int = 3, delay: float = 1.0):
	"""
	Context manager برای مدیریت session در background jobs
	اطمینان می‌دهد که session همیشه بسته می‌شود حتی در صورت exception
	همچنین retry logic برای اتصالات timeout شده دارد
	
	Args:
		retries: تعداد تلاش‌های مجدد در صورت خطای اتصال
		delay: تأخیر بین تلاش‌ها (ثانیه)
	"""
	db = None
	last_exception = None
	
	for attempt in range(retries):
		db = None
		try:
			db = SessionLocal()
			# تست اتصال قبل از yield
			try:
				# یک query ساده برای تست اتصال
				db.execute(text("SELECT 1"))
			except (OperationalError, SQLTimeoutError) as e:
				# اگر اتصال برقرار نشد، retry می‌کنیم
				if db:
					try:
						db.close()
					except Exception:
						pass
					db = None
				
				last_exception = e
				if attempt < retries - 1:
					wait_time = delay * (2 ** attempt)  # exponential backoff
					logger.warning(
						f"Database connection error (attempt {attempt + 1}/{retries}): {e}. "
						f"Retrying in {wait_time:.2f}s..."
					)
					time.sleep(wait_time)
					continue
				else:
					logger.error(f"Database connection failed after {retries} attempts: {e}")
					raise
			
			# اگر اتصال برقرار شد، yield می‌کنیم
			try:
				yield db
				# اگر به اینجا رسیدیم، همه چیز خوب است
				db.commit()
				return
			except (OperationalError, SQLTimeoutError) as e:
				# در صورت خطای اتصال در حین اجرا، rollback و retry می‌کنیم
				if db:
					try:
						db.rollback()
					except Exception:
						pass
					try:
						db.close()
					except Exception:
						pass
					db = None
				
				last_exception = e
				if attempt < retries - 1:
					wait_time = delay * (2 ** attempt)
					logger.warning(
						f"Database operation error (attempt {attempt + 1}/{retries}): {e}. "
						f"Retrying in {wait_time:.2f}s..."
					)
					time.sleep(wait_time)
					continue
				else:
					logger.error(f"Database operation failed after {retries} attempts: {e}")
					raise
			except Exception as e:
				# برای سایر exception ها، rollback و raise می‌کنیم
				if db:
					try:
						db.rollback()
					except Exception:
						pass
				raise
		except (OperationalError, SQLTimeoutError):
			# این exception ها قبلاً handle شده‌اند
			if attempt == retries - 1:
				# آخرین تلاش ناموفق بود
				if db:
					try:
						db.close()
					except Exception:
						pass
				raise
			# برای تلاش‌های بعدی، continue می‌کنیم
			continue
		except Exception:
			# برای سایر exception ها، session را بسته و raise می‌کنیم
			if db:
				try:
					db.close()
				except Exception:
					pass
			raise
		finally:
			# اطمینان از بسته شدن session در صورت عدم موفقیت
			if db:
				try:
					# اگر session هنوز باز است و commit نشده، بسته می‌شود
					if not db.is_active:
						db.close()
				except Exception:
					pass
	
	# اگر به اینجا رسیدیم، همه تلاش‌ها ناموفق بودند
	if last_exception:
		raise last_exception
