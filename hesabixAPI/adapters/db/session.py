from collections.abc import Generator
from contextlib import contextmanager
from typing import Callable, Any, Optional
import time
import logging
import traceback
import inspect
from contextvars import ContextVar

from sqlalchemy import create_engine, text, event
from sqlalchemy.exc import OperationalError, TimeoutError as SQLTimeoutError
from sqlalchemy.orm import sessionmaker, DeclarativeBase, Session
from sqlalchemy.pool import QueuePool

from app.core.settings import get_settings

logger = logging.getLogger(__name__)

# Context variable برای ذخیره اطلاعات request
_request_context: ContextVar[Optional[dict]] = ContextVar('request_context', default=None)


class Base(DeclarativeBase):
	pass


settings = get_settings()
engine = create_engine(
    settings.mysql_dsn,
    echo=settings.sqlalchemy_echo,
    poolclass=QueuePool,  # استفاده از QueuePool برای بهتر control
    pool_pre_ping=True,  # بررسی سلامت اتصالات قبل از استفاده
    pool_recycle=getattr(settings, 'db_pool_recycle', 300),  # Recycle هر 5 دقیقه برای جلوگیری از connection leak و بهبود performance
    pool_size=settings.db_pool_size,
    max_overflow=settings.db_max_overflow,
    pool_timeout=settings.db_pool_timeout,
    # تنظیمات اضافی برای بهبود عملکرد
    connect_args={
        "connect_timeout": 10,
        "read_timeout": 30,  # کاهش برای جلوگیری از query های طولانی و connection leak
        "write_timeout": 30,
        "charset": "utf8mb4",
        "init_command": "SET sql_mode='STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO'",
    },
    # بهینه‌سازی برای Performance
    # استفاده از 'rollback' به جای 'commit' برای جلوگیری از connection leak
    # 'rollback' اطمینان می‌دهد که transaction های باز بسته می‌شوند
    pool_reset_on_return='rollback',  # Reset connection بعد از return - جلوگیری از connection leak
    isolation_level="READ COMMITTED",  # برای بهتر Concurrency
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, expire_on_commit=False)


# Event Listener برای تنظیمات MySQL Session
@event.listens_for(engine, "connect")
def set_mysql_session_params(dbapi_conn, connection_record):
	"""تنظیمات MySQL برای هر Connection جدید"""
	try:
		with dbapi_conn.cursor() as cursor:
			# بهینه‌سازی برای InnoDB
			cursor.execute("SET SESSION innodb_lock_wait_timeout = 50")
			# بهینه‌سازی برای Read Performance
			cursor.execute("SET SESSION transaction_isolation = 'READ-COMMITTED'")
			# بهینه‌سازی برای Query Performance
			cursor.execute("SET SESSION sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO'")
			# تنظیم timeout برای query ها (60 ثانیه = 60000 میلی‌ثانیه)
			# این باعث می‌شود query های طولانی‌تر از 1 دقیقه timeout شوند
			# کاهش از 120 ثانیه برای جلوگیری از connection leak
			cursor.execute("SET SESSION max_execution_time = 60000")
	except Exception as e:
		logger.warning(f"Error setting MySQL session variables: {e}")


# Event Listeners برای Monitoring Pool Statistics
@event.listens_for(engine.pool, "connect")
def receive_connect(dbapi_conn, connection_record):
	"""Log ایجاد اتصال جدید"""
	pool = engine.pool
	logger.debug(
		f"New database connection created. "
		f"Pool size: {pool.size()}, "
		f"Checked out: {pool.checkedout()}, "
		f"Overflow: {pool.overflow()}"
	)


# Rate limiting برای لاگ‌های pool usage
_last_pool_warning_time = 0
_pool_warning_interval = 30  # کاهش به 30 ثانیه برای monitoring بهتر
_last_critical_warning_time = 0
_critical_warning_interval = 10  # برای critical warnings، هر 10 ثانیه

@event.listens_for(engine.pool, "checkout")
def receive_checkout(dbapi_conn, connection_record, connection_proxy):
	"""Log checkout اتصال از Pool و ثبت زمان برای leak detection"""
	global _last_pool_warning_time, _last_critical_warning_time
	
	pool = engine.pool
	total_capacity = pool.size() + pool.overflow()
	checked_out = pool.checkedout()
	usage_percent = (checked_out / total_capacity * 100) if total_capacity > 0 else 0
	
	# ثبت زمان checkout برای leak detection با اطلاعات کامل
	connection_id = id(dbapi_conn)
	current_time = time.time()
	
	# گرفتن stack trace برای تشخیص محل checkout
	stack_frames = []
	try:
		stack = inspect.stack()
		# گرفتن 15 فریم اول برای پیدا کردن فریم‌های مربوط به کد ما
		for frame_info in stack[1:16]:
			filename = frame_info.filename
			lineno = frame_info.lineno
			function = frame_info.function
			# فقط فریم‌های مربوط به کد ما را نگه دار (بدون site-packages و __pycache__)
			if 'hesabixAPI' in filename and 'site-packages' not in filename and '__pycache__' not in filename:
				# تبدیل مسیر کامل به مسیر نسبی
				relative_path = filename
				if '/var/www/ark/hesabixAPI/' in filename:
					relative_path = filename.split('/var/www/ark/hesabixAPI/')[-1]
				stack_frames.append(f"{relative_path}:{lineno} in {function}")
		stack_trace = "\n".join(stack_frames[:5]) if stack_frames else "No stack frames found"
	except Exception as e:
		stack_trace = f"Error getting stack trace: {e}"
	
	# گرفتن اطلاعات request از context (اگر در دسترس باشد)
	request_info = {}
	try:
		request_ctx = _request_context.get()
		if request_ctx:
			request_info = request_ctx.copy()
	except Exception:
		pass
	
	# ذخیره اطلاعات کامل checkout
	_connection_checkout_times[connection_id] = {
		'checkout_time': current_time,
		'stack_trace': stack_trace,
		'request_info': request_info,
		'checked_out_count': checked_out,
		'usage_percent': usage_percent
	}
	
	# Critical warning فقط اگر Pool واقعاً پر باشد (بیش از 95% و حداقل 475 connection)
	# این از warning های غیرضروری جلوگیری می‌کند
	if usage_percent > 95 and checked_out > 475:
		if current_time - _last_critical_warning_time >= _critical_warning_interval:
			_last_critical_warning_time = current_time
			logger.error(
				f"🚨 CRITICAL: Connection pool nearly exhausted! "
				f"Usage: {usage_percent:.1f}%. "
				f"Pool size: {pool.size()}, "
				f"Checked out: {checked_out}, "
				f"Overflow: {pool.overflow()}, "
				f"Total capacity: {total_capacity}. "
				f"Possible connection leak detected!"
			)
	# Warning اگر Pool بیش از 80% استفاده شده باشد و حداقل 400 connection (با rate limiting)
	elif usage_percent > 80 and checked_out > 400:
		if current_time - _last_pool_warning_time >= _pool_warning_interval:
			_last_pool_warning_time = current_time
			logger.warning(
				f"⚠️ High connection pool usage: {usage_percent:.1f}%. "
				f"Pool size: {pool.size()}, "
				f"Checked out: {checked_out}, "
				f"Overflow: {pool.overflow()}, "
				f"Total capacity: {total_capacity}"
			)
	else:
		logger.debug(
			f"Connection checked out. "
			f"Pool usage: {usage_percent:.1f}%, "
			f"Checked out: {checked_out}/{total_capacity}"
		)


# Monitoring برای connection leak detection
_connection_checkout_times = {}  # {connection_id: {'checkout_time': float, 'stack_trace': str, 'request_info': dict}}
_connection_leak_threshold = 120  # 2 دقیقه - برای عملیات طولانی مثل AI streaming که می‌تواند چند دقیقه طول بکشد
_last_leak_check_time = 0
_leak_check_interval = 30  # بررسی leak ها هر 30 ثانیه

def _check_connection_leaks():
	"""بررسی connection leak برای اتصالاتی که هنوز checkout هستند"""
	global _last_leak_check_time
	current_time = time.time()
	
	# فقط هر 30 ثانیه یکبار بررسی کن
	if current_time - _last_leak_check_time < _leak_check_interval:
		return
	
	_last_leak_check_time = current_time
	
	pool = engine.pool
	leaked_connections = []
	
	for connection_id, checkout_info in list(_connection_checkout_times.items()):
		if isinstance(checkout_info, dict):
			checkout_time = checkout_info.get('checkout_time', current_time)
		else:
			# برای سازگاری با داده‌های قدیمی
			checkout_time = checkout_info if isinstance(checkout_info, (int, float)) else current_time
		
		connection_duration = current_time - checkout_time
		if connection_duration > _connection_leak_threshold:
			leaked_connections.append((connection_id, checkout_info, connection_duration))
	
	if leaked_connections:
		logger.warning(
			f"⚠️ Connection leak detected! "
			f"Found {len(leaked_connections)} connections checked out for more than {_connection_leak_threshold}s. "
			f"Pool size: {pool.size()}, Checked out: {pool.checkedout()}, "
			f"Usage: {(pool.checkedout() / (pool.size() + pool.overflow()) * 100) if (pool.size() + pool.overflow()) > 0 else 0:.1f}%"
		)
		
		# لاگ جزئیات هر connection leak
		for idx, (conn_id, checkout_info, duration) in enumerate(leaked_connections[:5], 1):  # فقط 5 مورد اول
			if isinstance(checkout_info, dict):
				stack_trace = checkout_info.get('stack_trace', 'N/A')
				request_info = checkout_info.get('request_info', {})
				checked_out_at = checkout_info.get('checked_out_count', 'N/A')
				usage_at = checkout_info.get('usage_percent', 'N/A')
				
				logger.warning(
					f"  🔍 Leaked Connection #{idx} (ID: {conn_id}):\n"
					f"    Duration: {duration:.1f}s\n"
					f"    Checked out when: {checked_out_at} connections active ({usage_at:.1f}% usage)\n"
					f"    Request: {request_info.get('path', 'N/A')} [{request_info.get('method', 'N/A')}]\n"
					f"    User ID: {request_info.get('user_id', 'N/A')}\n"
					f"    Stack trace:\n{stack_trace}"
				)
			else:
				logger.warning(
					f"  🔍 Leaked Connection #{idx} (ID: {conn_id}): Duration: {duration:.1f}s (legacy format)"
				)

@event.listens_for(engine.pool, "checkin")
def receive_checkin(dbapi_conn, connection_record):
	"""Log checkin اتصال به Pool و بررسی connection leak"""
	pool = engine.pool
	connection_id = id(dbapi_conn)
	
	# بررسی connection leak
	if connection_id in _connection_checkout_times:
		checkout_info = _connection_checkout_times.pop(connection_id)
		
		# استخراج checkout_time
		if isinstance(checkout_info, dict):
			checkout_time = checkout_info.get('checkout_time', time.time())
			stack_trace = checkout_info.get('stack_trace', 'N/A')
			request_info = checkout_info.get('request_info', {})
		else:
			# برای سازگاری با داده‌های قدیمی
			checkout_time = checkout_info if isinstance(checkout_info, (int, float)) else time.time()
			stack_trace = 'N/A'
			request_info = {}
		
		connection_duration = time.time() - checkout_time
		
		if connection_duration > _connection_leak_threshold:
			logger.warning(
				f"⚠️ Long-running connection detected! "
				f"Connection was checked out for {connection_duration:.1f} seconds "
				f"(threshold: {_connection_leak_threshold}s). "
				f"Pool size: {pool.size()}, Checked out: {pool.checkedout()}\n"
				f"    Request: {request_info.get('path', 'N/A')} [{request_info.get('method', 'N/A')}]\n"
				f"    User ID: {request_info.get('user_id', 'N/A')}\n"
				f"    Stack trace:\n{stack_trace}"
			)
	
	# بررسی leak های موجود
	_check_connection_leaks()
	
	logger.debug(
		f"Connection checked in. "
		f"Pool size: {pool.size()}, "
		f"Checked out: {pool.checkedout()}"
	)


def get_db() -> Generator[Session, None, None]:
	db = SessionLocal()
	try:
		yield db
		db.commit()
	except Exception:
		db.rollback()
		raise
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
			# ایجاد session جدید
			db = SessionLocal()
			
			# تست اتصال قبل از yield
			try:
				db.execute(text("SELECT 1"))
			except (OperationalError, SQLTimeoutError) as e:
				# اگر اتصال برقرار نشد، session را ببند و retry کن
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
					if db:
						try:
							db.close()
						except Exception:
							pass
					raise
			
			# اگر اتصال برقرار شد، yield می‌کنیم
			try:
				yield db
				# اگر به اینجا رسیدیم، همه چیز خوب است - commit کن
				try:
					db.commit()
				except Exception:
					db.rollback()
					raise
				# در صورت موفقیت، session را ببند و return کن
				try:
					db.close()
				except Exception:
					pass
				db = None
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
				# برای سایر exception ها، rollback و session را ببند
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
			# اطمینان از بسته شدن session در هر صورت
			if db:
				try:
					db.close()
				except Exception:
					pass
				db = None
	
	# اگر به اینجا رسیدیم، همه تلاش‌ها ناموفق بودند
	if last_exception:
		raise last_exception
