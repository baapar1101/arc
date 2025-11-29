"""
Helper functions برای retry mechanism در workflow actions
"""

import time
import logging
from typing import Callable, Any, Optional, Dict, TypeVar, List

logger = logging.getLogger(__name__)

T = TypeVar('T')


def execute_with_retry(
    func: Callable[[], T],
    max_attempts: int = 3,
    initial_delay: float = 1.0,
    max_delay: float = 60.0,
    exponential_backoff: bool = True,
    retryable_exceptions: Optional[List[type]] = None,
    on_retry: Optional[Callable[[int, Exception], None]] = None,
    timeout: Optional[float] = None,
) -> T:
    """
    اجرای یک تابع با retry mechanism
    
    Args:
        func: تابعی که باید اجرا شود
        max_attempts: حداکثر تعداد تلاش‌ها
        initial_delay: تاخیر اولیه (ثانیه)
        max_delay: حداکثر تاخیر (ثانیه)
        exponential_backoff: استفاده از exponential backoff
        retryable_exceptions: لیست exceptionهای قابل retry (اگر None باشد، همه exceptionها retry می‌شوند)
        on_retry: callback برای زمانی که retry می‌شود
        timeout: timeout برای هر تلاش (ثانیه)
    
    Returns:
        نتیجه تابع
    
    Raises:
        آخرین exception در صورت شکست همه تلاش‌ها
    """
    if retryable_exceptions is None:
        retryable_exceptions = [Exception]
    
    last_exception = None
    
    for attempt in range(1, max_attempts + 1):
        try:
            if timeout:
                return _execute_with_timeout(func, timeout)
            else:
                return func()
        
        except Exception as e:
            last_exception = e
            
            # بررسی اینکه آیا exception قابل retry است
            is_retryable = any(isinstance(e, exc_type) for exc_type in retryable_exceptions)
            
            if not is_retryable or attempt >= max_attempts:
                logger.error(f"Failed after {attempt} attempt(s): {e}")
                raise
            
            # محاسبه تاخیر
            if exponential_backoff:
                delay = min(initial_delay * (2 ** (attempt - 1)), max_delay)
            else:
                delay = initial_delay
            
            logger.warning(f"Attempt {attempt}/{max_attempts} failed: {e}. Retrying in {delay:.2f}s...")
            
            if on_retry:
                try:
                    on_retry(attempt, e)
                except Exception:
                    pass  # Ignore errors in callback
            
            time.sleep(delay)
    
    # این نباید هرگز اجرا شود، اما برای type checker
    if last_exception:
        raise last_exception
    raise RuntimeError("Unexpected error in retry mechanism")


def _execute_with_timeout(func: Callable[[], T], timeout: float) -> T:
    """
    اجرای یک تابع با timeout (استفاده از threading)
    """
    import threading
    import queue
    
    result_queue = queue.Queue()
    exception_queue = queue.Queue()
    
    def target():
        try:
            result = func()
            result_queue.put(result)
        except Exception as e:
            exception_queue.put(e)
    
    thread = threading.Thread(target=target)
    thread.daemon = True
    thread.start()
    thread.join(timeout=timeout)
    
    if thread.is_alive():
        raise TimeoutError(f"Function execution exceeded {timeout} seconds")
    
    if not exception_queue.empty():
        raise exception_queue.get()
    
    if not result_queue.empty():
        return result_queue.get()
    
    raise RuntimeError("Unexpected error in timeout execution")


def get_retry_config_from_action_config(config: Dict[str, Any]) -> Dict[str, Any]:
    """
    استخراج تنظیمات retry از config یک action
    
    Returns:
        Dict با کلیدهای: max_attempts, initial_delay, max_delay, exponential_backoff
    """
    retry_config = config.get("retry_config", {})
    
    return {
        "max_attempts": retry_config.get("max_attempts", config.get("retry_attempts", 3)),
        "initial_delay": retry_config.get("initial_delay", config.get("retry_delay_seconds", 1.0)),
        "max_delay": retry_config.get("max_delay", 60.0),
        "exponential_backoff": retry_config.get("exponential_backoff", config.get("exponential_backoff", True)),
        "timeout": config.get("timeout_seconds"),
    }

