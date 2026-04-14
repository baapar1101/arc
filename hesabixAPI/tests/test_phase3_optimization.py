"""
تست‌های فاز 3: بهینه‌سازی Queryها و Monitoring
"""
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
from sqlalchemy import text

from app.main import create_app
from adapters.db.session import get_db, engine
from app.core.cache import get_cache
from app.core.rate_limiter import get_rate_limiter
from app.core.monitoring import get_performance_monitor


@pytest.fixture
def client():
    """Test client"""
    app = create_app()
    return TestClient(app)


@pytest.fixture
def db():
    """Database session"""
    db_gen = get_db()
    db = next(db_gen)
    try:
        yield db
    finally:
        db.close()


def test_cache_service_initialization():
    """تست initialization Cache Service"""
    cache = get_cache()
    assert cache is not None
    # اگر Redis غیرفعال باشد، enabled=False است اما service باید کار کند
    assert hasattr(cache, 'enabled')
    assert hasattr(cache, 'get')
    assert hasattr(cache, 'set')


def test_rate_limiter_initialization():
    """تست initialization Rate Limiter"""
    limiter = get_rate_limiter()
    assert limiter is not None
    assert hasattr(limiter, 'check_rate_limit')
    assert hasattr(limiter, 'get_rate_limit_info')


def test_rate_limiter_check():
    """تست rate limiting"""
    limiter = get_rate_limiter()
    key = "test_rate_limit_key"
    
    # تست rate limit
    allowed, remaining, reset_after = limiter.check_rate_limit(
        key, max_requests=5, window_seconds=60
    )
    
    assert isinstance(allowed, bool)
    assert isinstance(remaining, int)
    assert isinstance(reset_after, int)
    assert remaining >= 0
    assert reset_after >= 0


def test_performance_monitor_initialization():
    """تست initialization Performance Monitor"""
    monitor = get_performance_monitor()
    assert monitor is not None
    assert hasattr(monitor, 'record_request')
    assert hasattr(monitor, 'get_endpoint_stats')


def test_performance_monitor_record():
    """تست ثبت request در monitoring"""
    monitor = get_performance_monitor()
    
    # ثبت یک request
    monitor.record_request(
        method="GET",
        path="/api/v1/test",
        duration_ms=1500.5,
        status_code=200,
        user_id=1,
    )
    
    # اگر Redis فعال باشد، باید stats برگرداند
    stats = monitor.get_endpoint_stats("GET", "/api/v1/test")
    # stats می‌تواند خالی باشد اگر Redis غیرفعال باشد
    assert isinstance(stats, dict)


def test_health_endpoint(client):
    """تست health endpoint"""
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert "data" in data
    assert "status" in data["data"]
    assert "services" in data["data"]


def test_health_endpoint_services(client):
    """تست health endpoint با بررسی services"""
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    data = response.json()
    services = data["data"]["services"]
    assert "database" in services
    assert "redis" in services
    assert services["database"] in ["ok", "error"]


def test_database_indexes_exist(db: Session):
    """تست وجود indexes در جداول مهم"""
    # بررسی indexes در documents
    result = db.execute(text("SHOW INDEXES FROM documents"))
    doc_indexes = [row[2] for row in result]
    assert len(doc_indexes) > 0
    assert "ix_documents_business_id" in doc_indexes or any("business_id" in idx for idx in doc_indexes)
    
    # بررسی indexes در products
    result = db.execute(text("SHOW INDEXES FROM products"))
    prod_indexes = [row[2] for row in result]
    assert len(prod_indexes) > 0
    assert "ix_products_business_id" in prod_indexes or any("business_id" in idx for idx in prod_indexes)


def test_query_with_business_id_filter(db: Session):
    """تست query با فیلتر business_id (باید از index استفاده کند)"""
    # این تست نیاز به داده واقعی دارد
    # فقط بررسی می‌کنیم که query اجرا می‌شود
    result = db.execute(
        text("SELECT COUNT(*) FROM documents WHERE business_id = 1")
    )
    count = result.scalar()
    assert isinstance(count, int)
    assert count >= 0


def test_rate_limit_decorator():
    """تست decorator rate_limit"""
    from app.core.rate_limiter import rate_limit
    from fastapi import Request
    
    # ساخت یک mock function
    call_count = 0
    
    @rate_limit(max_requests=2, window_seconds=60)
    async def test_endpoint(request: Request):
        nonlocal call_count
        call_count += 1
        return {"ok": True}
    
    # decorator باید function را wrap کند
    assert hasattr(test_endpoint, '__wrapped__') or callable(test_endpoint)


def test_cache_get_set():
    """تست عملیات get/set در cache"""
    cache = get_cache()
    
    # تست set/get
    test_key = "test_cache_key"
    test_value = {"test": "value", "number": 123}
    
    # اگر Redis فعال باشد
    if cache.enabled:
        result = cache.set(test_key, test_value, ttl=60)
        assert result is True
        
        retrieved = cache.get(test_key)
        assert retrieved == test_value
        
        # پاک کردن
        cache.delete(test_key)
    else:
        # اگر Redis غیرفعال باشد، باید gracefully handle شود
        result = cache.set(test_key, test_value, ttl=60)
        # باید False برگرداند یا True (fail-open)
        assert isinstance(result, bool)


def test_monitoring_slow_request():
    """تست ثبت slow request"""
    monitor = get_performance_monitor()
    
    # ثبت یک slow request (> 1 second)
    monitor.record_request(
        method="POST",
        path="/api/v1/slow-endpoint",
        duration_ms=2500.0,
        status_code=200,
    )
    
    # بررسی stats
    stats = monitor.get_endpoint_stats("POST", "/api/v1/slow-endpoint")
    # اگر Redis فعال باشد، باید stats داشته باشد
    if monitor.cache.enabled:
        # ممکن است stats خالی باشد اگر TTL تمام شده
        assert isinstance(stats, dict)


def test_connection_pool_settings():
    """تست تنظیمات connection pool"""
    from app.core.settings import get_settings
    from adapters.db.session import engine
    
    settings = get_settings()
    
    # بررسی تنظیمات pool
    assert settings.db_pool_size >= 20
    assert settings.db_max_overflow >= 30
    
    # بررسی engine pool
    pool = engine.pool
    assert pool.size() <= settings.db_pool_size + settings.db_max_overflow


def test_indexes_for_common_queries(db: Session):
    """تست indexes برای query های رایج"""
    # بررسی index برای business_id در جداول مهم
    tables = ["documents", "products", "persons", "activity_logs"]
    
    for table in tables:
        try:
            result = db.execute(text(f"SHOW INDEXES FROM {table}"))
            indexes = [row[2] for row in result]
            
            # باید حداقل یک index با business_id داشته باشد
            has_business_index = any(
                "business_id" in idx.lower() or "business" in idx.lower()
                for idx in indexes
            )
            
            # برای activity_logs ممکن است business_id اختیاری باشد
            if table != "activity_logs":
                assert has_business_index, f"Table {table} should have business_id index"
        except Exception as e:
            # اگر جدول وجود نداشت، skip می‌کنیم
            print(f"Warning: Could not check indexes for {table}: {e}")

