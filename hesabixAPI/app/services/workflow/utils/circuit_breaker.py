"""
Circuit Breaker برای جلوگیری از overload در صورت خطای مکرر
"""

import time
import threading
from typing import Optional, Dict
from enum import Enum


class CircuitState(Enum):
    """حالت‌های circuit breaker"""
    CLOSED = "closed"  # عادی - درخواست‌ها عبور می‌کنند
    OPEN = "open"  # باز - درخواست‌ها رد می‌شوند
    HALF_OPEN = "half_open"  # نیمه باز - برای تست


class CircuitBreaker:
    """Circuit Breaker برای مدیریت خطاهای مکرر"""
    
    def __init__(
        self,
        failure_threshold: int = 5,
        timeout: float = 60.0,
        expected_exception: type = Exception
    ):
        """
        Args:
            failure_threshold: تعداد خطاهای متوالی قبل از باز شدن circuit
            timeout: مدت زمان باز ماندن circuit (ثانیه)
            expected_exception: نوع exception که باید شمارش شود
        """
        self.failure_threshold = failure_threshold
        self.timeout = timeout
        self.expected_exception = expected_exception
        
        self.failure_count = 0
        self.last_failure_time: Optional[float] = None
        self.state = CircuitState.CLOSED
        self._lock = threading.Lock()
    
    def call(self, func, *args, **kwargs):
        """
        اجرای تابع با circuit breaker
        """
        with self._lock:
            # بررسی حالت circuit
            if self.state == CircuitState.OPEN:
                # بررسی اینکه آیا باید به حالت half-open برویم
                if time.time() - (self.last_failure_time or 0) >= self.timeout:
                    self.state = CircuitState.HALF_OPEN
                    self.failure_count = 0
                else:
                    raise CircuitBreakerOpenError(
                        f"Circuit breaker is OPEN. Last failure: {self.last_failure_time}"
                    )
        
        # اجرای تابع
        try:
            result = func(*args, **kwargs)
            self._on_success()
            return result
        except self.expected_exception as e:
            self._on_failure()
            raise
    
    def _on_success(self):
        """هنگام موفقیت"""
        with self._lock:
            if self.state == CircuitState.HALF_OPEN:
                # اگر در حالت half-open بودیم و موفق شدیم، circuit را ببند
                self.state = CircuitState.CLOSED
                self.failure_count = 0
            elif self.state == CircuitState.CLOSED:
                # در حالت عادی، تعداد خطاها را reset کن
                self.failure_count = 0
    
    def _on_failure(self):
        """هنگام خطا"""
        with self._lock:
            self.failure_count += 1
            self.last_failure_time = time.time()
            
            if self.state == CircuitState.HALF_OPEN:
                # اگر در حالت half-open بودیم و خطا گرفتیم، circuit را باز کن
                self.state = CircuitState.OPEN
            elif self.state == CircuitState.CLOSED:
                # اگر تعداد خطاها به آستانه رسید، circuit را باز کن
                if self.failure_count >= self.failure_threshold:
                    self.state = CircuitState.OPEN
    
    def reset(self):
        """بازنشانی circuit breaker"""
        with self._lock:
            self.state = CircuitState.CLOSED
            self.failure_count = 0
            self.last_failure_time = None


class CircuitBreakerOpenError(Exception):
    """Exception زمانی که circuit breaker باز است"""
    pass


# Global circuit breakers برای هر URL
_circuit_breakers: Dict[str, CircuitBreaker] = {}
_circuit_breaker_lock = threading.Lock()


def get_circuit_breaker(
    key: str,
    failure_threshold: int = 5,
    timeout: float = 60.0
) -> CircuitBreaker:
    """
    دریافت یا ایجاد circuit breaker برای یک کلید خاص
    
    Args:
        key: کلید برای شناسایی circuit breaker (معمولاً URL)
        failure_threshold: تعداد خطاهای متوالی
        timeout: مدت زمان باز ماندن circuit
    """
    with _circuit_breaker_lock:
        if key not in _circuit_breakers:
            _circuit_breakers[key] = CircuitBreaker(
                failure_threshold=failure_threshold,
                timeout=timeout
            )
        return _circuit_breakers[key]

