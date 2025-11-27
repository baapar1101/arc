from collections.abc import Generator
from contextlib import contextmanager
from typing import Callable, Any
import time
import logging

from sqlalchemy import create_engine
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
		try:
			db = SessionLocal()
			try:
				yield db
				db.commit()
				return
			except (OperationalError, SQLTimeoutError) as e:
				# در صورت خطای اتصال، rollback و دوباره تلاش می‌کنیم
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
			except Exception:
				if db:
					db.rollback()
				raise
		except Exception as e:
			if db:
				try:
					db.close()
				except Exception:
					pass
			raise
	
	# اگر به اینجا رسیدیم، همه تلاش‌ها ناموفق بودند
	if last_exception:
		raise last_exception
