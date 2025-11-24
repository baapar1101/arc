from __future__ import annotations

import hashlib
import math
import os
import shutil
import tempfile
from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    File,
    Query,
    Request,
    UploadFile,
)
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError, success_response
from app.services.job_manager import JobManager
from app.services.tax_product_code_service import (
    get_tax_product_code,
    process_tax_product_code_import,
    search_tax_product_codes,
)
from adapters.api.v1.schemas import QueryInfo


router = APIRouter(prefix="/tax/product-codes", tags=["tax-product-codes"])
admin_router = APIRouter(prefix="/admin/tax/product-codes", tags=["admin-tax-product-codes"])


@router.get("")
def search_tax_codes_endpoint(
    request: Request,
    q: str | None = Query(None, description="عبارت جستجو (کد یا شرح)"),
    skip: int = Query(0, ge=0),
    take: int = Query(20, ge=1, le=200),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    _require_authenticated(ctx)
    data = search_tax_product_codes(db, q, skip, take)
    return success_response(data, request)


@router.get("/{code}")
def get_tax_code_endpoint(
    request: Request,
    code: str,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    _require_authenticated(ctx)
    item = get_tax_product_code(db, code)
    if not item:
        raise ApiError("TAX_CODE_NOT_FOUND", "کد مالیاتی یافت نشد", http_status=404)
    return success_response(item, request)


@admin_router.post("/search")
def search_tax_codes_admin(
    request: Request,
    payload: QueryInfo,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    _require_admin(ctx)
    take = max(1, min(payload.take or 20, 200))
    skip = max(0, payload.skip or 0)
    data = search_tax_product_codes(
        db,
        payload.search,
        skip,
        take,
        sort_by=payload.sort_by,
        sort_desc=payload.sort_desc,
    )
    total = int(data.get("total", 0))
    total_pages = math.ceil(total / take) if take else 0
    page = (skip // take) + 1
    response = {
        "items": data.get("items", []),
        "total": total,
        "page": page,
        "limit": take,
        "total_pages": total_pages,
    }
    return success_response(response, request)


@admin_router.post("/import")
async def import_tax_codes_endpoint(
    request: Request,
    background: BackgroundTasks,
    file: UploadFile = File(..., description="فایل XML دانلود شده از سامانه امور مالیاتی"),
    ctx: AuthContext = Depends(get_current_user),
):
    _require_admin(ctx)
    filename = file.filename or "product_tax.xml"
    ext = os.path.splitext(filename)[1].lower()
    if ext not in {".xml", ".zip"}:
        raise ApiError("INVALID_FILE_TYPE", "فقط فایل‌های XML یا ZIP قابل پذیرش هستند", http_status=400)

    temp_dir = tempfile.mkdtemp(prefix="tax_import_")
    temp_path = os.path.join(temp_dir, filename)
    hasher = hashlib.sha256()
    size = 0

    try:
        with open(temp_path, "wb") as out:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                size += len(chunk)
                hasher.update(chunk)
                out.write(chunk)
    finally:
        await file.close()

    if size == 0:
        try:
            os.remove(temp_path)
        except OSError:
            pass
        raise ApiError("EMPTY_FILE", "فایل ارسال شده خالی است", http_status=400)

    jm = JobManager.instance()
    job_id = jm.create("فایل در صف پردازش قرار گرفت")
    checksum = hasher.hexdigest()

    def task():
        try:
            process_tax_product_code_import(
                temp_path,
                job_id,
                filename,
                checksum=checksum,
            )
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)

    background.add_task(task)
    payload = {
        "job_id": job_id,
        "filename": filename,
        "size": size,
        "checksum": checksum,
    }
    return success_response(payload, request, "ایمپورت در پس‌زمینه آغاز شد")


def _require_authenticated(ctx: AuthContext) -> None:
    if not ctx or not ctx.get_user_id():
        raise ApiError("UNAUTHORIZED", "کاربر احراز هویت نشده است", http_status=401)


def _require_admin(ctx: AuthContext) -> None:
    if not ctx or not (ctx.is_superadmin() or ctx.can_access_system_settings()):
        raise ApiError("FORBIDDEN", "دسترسی به این بخش مجاز نیست", http_status=403)


