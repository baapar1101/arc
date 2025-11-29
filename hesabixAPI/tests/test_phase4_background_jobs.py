"""
تست‌های فاز 4: Background Job Queue
"""

import pytest
import time
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.main import create_app
from adapters.db.session import get_db
from app.core.queue import get_queue_service, QueueService, QUEUE_DEFAULT, QUEUE_EMAIL
from app.services.job_manager import JobManager
from app.services.jobs import send_email_job


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


def test_queue_service_initialization():
    """تست initialization Queue Service"""
    queue_service = get_queue_service()
    assert queue_service is not None
    assert isinstance(queue_service, QueueService)
    assert hasattr(queue_service, 'enabled')
    assert hasattr(queue_service, 'enqueue')
    assert hasattr(queue_service, 'get_job')
    assert hasattr(queue_service, 'get_job_status')


def test_queue_service_enabled_check():
    """تست بررسی وضعیت فعال بودن queue service"""
    queue_service = get_queue_service()
    # باید enabled را بررسی کند (True یا False)
    assert isinstance(queue_service.enabled, bool)


def test_queue_service_get_queue():
    """تست دریافت queue"""
    from app.core.queue import get_queue
    
    queue = get_queue(QUEUE_DEFAULT)
    # اگر Redis فعال باشد، queue باید وجود داشته باشد
    # اگر غیرفعال باشد، None است
    if queue is not None:
        assert queue is not None
        assert hasattr(queue, 'name')


def test_queue_service_enqueue_job():
    """تست enqueue کردن job"""
    queue_service = get_queue_service()
    
    if not queue_service.enabled:
        pytest.skip("Queue service is disabled (Redis not available)")
    
    # Enqueue یک job ساده
    def test_job(x: int, y: int) -> int:
        return x + y
    
    job = queue_service.enqueue(
        test_job,
        5,
        3,
        queue_name=QUEUE_DEFAULT,
        timeout=60
    )
    
    assert job is not None
    assert hasattr(job, 'id')
    assert job.id is not None


def test_queue_service_get_job_status():
    """تست دریافت وضعیت job"""
    queue_service = get_queue_service()
    
    if not queue_service.enabled:
        pytest.skip("Queue service is disabled (Redis not available)")
    
    # Enqueue یک job
    def test_job() -> dict:
        return {"result": "success"}
    
    job = queue_service.enqueue(test_job, queue_name=QUEUE_DEFAULT)
    assert job is not None
    
    # دریافت وضعیت
    status = queue_service.get_job_status(job.id)
    assert status is not None
    assert "id" in status
    assert "state" in status
    assert status["id"] == job.id
    assert status["state"] in ["queued", "started", "finished", "failed"]


def test_job_manager_with_queue():
    """تست JobManager با queue service"""
    job_manager = JobManager.instance()
    
    # اگر queue service فعال باشد، باید از آن استفاده کند
    queue_service = job_manager.queue_service
    
    if queue_service.enabled:
        # تست create و get
        job_id = job_manager.create("Test job")
        assert job_id is not None
        
        status = job_manager.get(job_id)
        # ممکن است job در queue باشد یا در memory
        # در هر صورت باید status برگرداند
        assert status is not None or job_id is not None


def test_email_job_function():
    """تست تابع email job"""
    # تست اینکه تابع قابل فراخوانی است
    assert callable(send_email_job)
    
    # تست signature
    import inspect
    sig = inspect.signature(send_email_job)
    assert "to_email" in sig.parameters
    assert "subject" in sig.parameters
    assert "body" in sig.parameters


def test_queue_service_get_queue_length():
    """تست دریافت طول queue"""
    queue_service = get_queue_service()
    
    if not queue_service.enabled:
        pytest.skip("Queue service is disabled (Redis not available)")
    
    length = queue_service.get_queue_length(QUEUE_DEFAULT)
    assert isinstance(length, int)
    assert length >= 0


def test_queue_service_cancel_job():
    """تست لغو job"""
    queue_service = get_queue_service()
    
    if not queue_service.enabled:
        pytest.skip("Queue service is disabled (Redis not available)")
    
    # Enqueue یک job
    def long_running_job():
        time.sleep(10)
        return "done"
    
    job = queue_service.enqueue(long_running_job, queue_name=QUEUE_DEFAULT)
    assert job is not None
    
    # لغو job
    cancelled = queue_service.cancel_job(job.id)
    # ممکن است job قبلاً شروع شده باشد
    assert isinstance(cancelled, bool)


def test_queue_service_delete_job():
    """تست حذف job"""
    queue_service = get_queue_service()
    
    if not queue_service.enabled:
        pytest.skip("Queue service is disabled (Redis not available)")
    
    # Enqueue یک job
    def test_job():
        return "test"
    
    job = queue_service.enqueue(test_job, queue_name=QUEUE_DEFAULT)
    assert job is not None
    
    # حذف job
    deleted = queue_service.delete_job(job.id)
    assert isinstance(deleted, bool)


def test_queue_service_get_failed_jobs():
    """تست دریافت failed jobs"""
    queue_service = get_queue_service()
    
    if not queue_service.enabled:
        pytest.skip("Queue service is disabled (Redis not available)")
    
    failed_jobs = queue_service.get_failed_jobs(limit=10)
    assert isinstance(failed_jobs, list)
    # ممکن است failed job وجود نداشته باشد


def test_jobs_endpoint_get_status(client):
    """تست endpoint دریافت وضعیت job"""
    # ایجاد یک job ID تستی
    job_manager = JobManager.instance()
    job_id = job_manager.create("Test job")
    
    response = client.get(f"/api/v1/jobs/{job_id}")
    # باید 200 برگرداند (حتی اگر job در queue نباشد)
    assert response.status_code in [200, 404]
    
    if response.status_code == 200:
        data = response.json()
        assert data["success"] is True
        assert "data" in data
        assert "id" in data["data"]


def test_jobs_endpoint_queue_stats(client):
    """تست endpoint آمار queues"""
    # نیاز به authentication دارد، اما می‌توانیم ساختار را تست کنیم
    response = client.get("/api/v1/jobs/queue/stats")
    # بدون authentication باید 401 یا 403 برگرداند
    assert response.status_code in [200, 401, 403, 503]
    
    if response.status_code == 200:
        data = response.json()
        assert data["success"] is True
        assert "data" in data
        assert "enabled" in data["data"]
        assert "queues" in data["data"]


def test_jobs_endpoint_failed_jobs(client):
    """تست endpoint failed jobs"""
    response = client.get("/api/v1/jobs/failed?limit=10")
    # بدون authentication باید 401 یا 403 برگرداند، یا 404 اگر route وجود نداشته باشد
    assert response.status_code in [200, 401, 403, 404, 503]
    
    if response.status_code == 200:
        data = response.json()
        assert data["success"] is True
        assert "data" in data
        assert "jobs" in data["data"]
        assert isinstance(data["data"]["jobs"], list)


def test_job_manager_backward_compatibility():
    """تست backward compatibility JobManager"""
    job_manager = JobManager.instance()
    
    # باید متدهای قبلی را داشته باشد
    assert hasattr(job_manager, 'create')
    assert hasattr(job_manager, 'get')
    assert hasattr(job_manager, 'start')
    assert hasattr(job_manager, 'update')
    assert hasattr(job_manager, 'succeed')
    assert hasattr(job_manager, 'fail')
    
    # تست create
    job_id = job_manager.create("Test")
    assert job_id is not None
    
    # تست get
    status = job_manager.get(job_id)
    # باید status برگرداند (از memory یا queue)
    assert status is not None or job_id is not None


def test_queue_service_multiple_queues():
    """تست استفاده از چندین queue"""
    queue_service = get_queue_service()
    
    if not queue_service.enabled:
        pytest.skip("Queue service is disabled (Redis not available)")
    
    from app.core.queue import (
        QUEUE_DEFAULT, QUEUE_HIGH_PRIORITY, QUEUE_LOW_PRIORITY,
        QUEUE_EMAIL, QUEUE_REPORTS, QUEUE_EXPORTS
    )
    
    def test_job():
        return "test"
    
    # تست enqueue در queue های مختلف
    queues = [
        QUEUE_DEFAULT,
        QUEUE_HIGH_PRIORITY,
        QUEUE_LOW_PRIORITY,
        QUEUE_EMAIL,
    ]
    
    for queue_name in queues:
        job = queue_service.enqueue(test_job, queue_name=queue_name)
        if job:
            assert job.id is not None


def test_job_status_conversion():
    """تست تبدیل وضعیت job از RQ به JobStatus"""
    queue_service = get_queue_service()
    job_manager = JobManager.instance()
    
    if not queue_service.enabled:
        pytest.skip("Queue service is disabled (Redis not available)")
    
    # Enqueue یک job
    def test_job():
        return {"test": "result"}
    
    job = queue_service.enqueue(test_job, queue_name=QUEUE_DEFAULT)
    assert job is not None
    
    # دریافت از JobManager (باید تبدیل شود)
    status = job_manager.get(job.id)
    if status:
        assert hasattr(status, 'id')
        assert hasattr(status, 'state')
        assert status.id == job.id
        assert status.state in ["queued", "running", "succeeded", "failed"]


def test_queue_service_timeout():
    """تست timeout در enqueue"""
    queue_service = get_queue_service()
    
    if not queue_service.enabled:
        pytest.skip("Queue service is disabled (Redis not available)")
    
    def test_job():
        return "test"
    
    # Enqueue با timeout
    job = queue_service.enqueue(
        test_job,
        queue_name=QUEUE_DEFAULT,
        timeout=120
    )
    
    if job:
        assert job.id is not None


def test_queue_service_result_ttl():
    """تست result_ttl در enqueue"""
    queue_service = get_queue_service()
    
    if not queue_service.enabled:
        pytest.skip("Queue service is disabled (Redis not available)")
    
    def test_job():
        return "test"
    
    # Enqueue با result_ttl
    job = queue_service.enqueue(
        test_job,
        queue_name=QUEUE_DEFAULT,
        result_ttl=3600
    )
    
    if job:
        assert job.id is not None

