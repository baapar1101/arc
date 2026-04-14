"""
API Endpoints برای افزونه مدیریت تعمیرگاه
"""
from typing import Optional
from fastapi import APIRouter, Depends, Request, Query
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.core.repair_shop_plugin_dependency import (
    check_repair_shop_plugin_active,
    get_business_plugin_status
)
from adapters.api.v1.schema_models.repair_shop import (
    RepairShopSettingsUpdate,
    RepairShopSettingsResponse,
    RepairTechnicianCreate,
    RepairTechnicianUpdate,
    RepairTechnicianResponse,
    RepairOrderCreate,
    RepairOrderUpdate,
    RepairOrderResponse,
    RepairOrderListItem,
    AssignTechnicianRequest,
    UpdateStatusRequest,
    AddPartsRequest,
    CalculateCostsRequest,
    CalculateCostsResponse,
    CompleteRepairRequest,
    DeliverRepairRequest,
    RepairOrderFilters,
)
from app.services import repair_shop_service
from app.services import repair_shop_operations

router = APIRouter(prefix="/repair-shop", tags=["Repair Shop"])


# ========== Plugin Status ==========

@router.get("/businesses/{business_id}/plugin-status")
def get_plugin_status(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """دریافت وضعیت افزونه برای کسب‌وکار"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    status = get_business_plugin_status(db, business_id)
    return success_response(data=status, request=request)


# ========== Settings ==========

@router.get("/businesses/{business_id}/settings")
def get_settings(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """دریافت تنظیمات تعمیرگاه"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "read"):
        raise ApiError("FORBIDDEN", "دسترسی به بخش تعمیرگاه ندارید", http_status=403)
    
    result = repair_shop_service.get_repair_shop_settings(db, business_id)
    return success_response(data=result, request=request)


@router.put("/businesses/{business_id}/settings")
def update_settings(
    request: Request,
    business_id: int,
    settings_data: RepairShopSettingsUpdate,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """به‌روزرسانی تنظیمات تعمیرگاه"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "manage"):
        raise ApiError("FORBIDDEN", "دسترسی مدیریت تعمیرگاه ندارید", http_status=403)
    
    result = repair_shop_service.update_repair_shop_settings(
        db, business_id, settings_data.dict(exclude_unset=True)
    )
    return success_response(data=result, request=request)


# ========== Technicians ==========

@router.get("/businesses/{business_id}/technicians")
def list_technicians(
    request: Request,
    business_id: int,
    only_active: bool = Query(True, description="فقط تعمیرکاران فعال"),
    offset: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """لیست تعمیرکاران"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "read"):
        raise ApiError("FORBIDDEN", "دسترسی به بخش تعمیرگاه ندارید", http_status=403)
    
    result = repair_shop_service.list_technicians(db, business_id, only_active, offset, limit)
    return success_response(data=result, request=request)


@router.get("/businesses/{business_id}/technicians/{technician_id}")
def get_technician(
    request: Request,
    business_id: int,
    technician_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """دریافت اطلاعات یک تعمیرکار"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "read"):
        raise ApiError("FORBIDDEN", "دسترسی به بخش تعمیرگاه ندارید", http_status=403)
    
    result = repair_shop_service.get_technician(db, business_id, technician_id)
    return success_response(data=result, request=request)


@router.post("/businesses/{business_id}/technicians")
def create_technician(
    request: Request,
    business_id: int,
    data: RepairTechnicianCreate,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """ایجاد تعمیرکار جدید"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "manage"):
        raise ApiError("FORBIDDEN", "دسترسی مدیریت تعمیرگاه ندارید", http_status=403)
    
    result = repair_shop_service.create_technician(
        db, business_id, data.dict(), ctx.user.id
    )
    return success_response(data=result, request=request, http_status=201)


@router.put("/businesses/{business_id}/technicians/{technician_id}")
def update_technician(
    request: Request,
    business_id: int,
    technician_id: int,
    data: RepairTechnicianUpdate,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """به‌روزرسانی تعمیرکار"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "manage"):
        raise ApiError("FORBIDDEN", "دسترسی مدیریت تعمیرگاه ندارید", http_status=403)
    
    result = repair_shop_service.update_technician(
        db, business_id, technician_id, data.dict(exclude_unset=True), ctx.user.id
    )
    return success_response(data=result, request=request)


@router.delete("/businesses/{business_id}/technicians/{technician_id}")
def delete_technician(
    request: Request,
    business_id: int,
    technician_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """حذف (غیرفعال کردن) تعمیرکار"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "delete"):
        raise ApiError("FORBIDDEN", "دسترسی حذف ندارید", http_status=403)
    
    result = repair_shop_service.delete_technician(
        db, business_id, technician_id, ctx.user.id
    )
    return success_response(data=result, request=request)


# ========== Repair Orders ==========

@router.get("/businesses/{business_id}/orders")
def list_repair_orders(
    request: Request,
    business_id: int,
    status: Optional[str] = Query(None),
    customer_person_id: Optional[int] = Query(None),
    assigned_technician_id: Optional[int] = Query(None),
    warranty_code_id: Optional[int] = Query(None),
    search: Optional[str] = Query(None),
    offset: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """لیست سفارشات تعمیر"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "read"):
        raise ApiError("FORBIDDEN", "دسترسی به بخش تعمیرگاه ندارید", http_status=403)
    
    filters = {
        "status": status,
        "customer_person_id": customer_person_id,
        "assigned_technician_id": assigned_technician_id,
        "warranty_code_id": warranty_code_id,
        "search": search,
    }
    
    result = repair_shop_service.list_repair_orders(db, business_id, filters, offset, limit)
    return success_response(data=result, request=request)


@router.get("/businesses/{business_id}/orders/{order_id}")
def get_repair_order(
    request: Request,
    business_id: int,
    order_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """دریافت اطلاعات کامل یک سفارش تعمیر"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "read"):
        raise ApiError("FORBIDDEN", "دسترسی به بخش تعمیرگاه ندارید", http_status=403)
    
    result = repair_shop_service.get_repair_order(db, business_id, order_id)
    return success_response(data=result, request=request)


@router.post("/businesses/{business_id}/orders")
def create_repair_order(
    request: Request,
    business_id: int,
    data: RepairOrderCreate,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """ایجاد سفارش تعمیر جدید"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "write"):
        raise ApiError("FORBIDDEN", "دسترسی ثبت سفارش تعمیر ندارید", http_status=403)
    
    result = repair_shop_service.create_repair_order(
        db, business_id, data.dict(), ctx.user.id
    )
    return success_response(data=result, request=request, http_status=201)


@router.put("/businesses/{business_id}/orders/{order_id}")
def update_repair_order(
    request: Request,
    business_id: int,
    order_id: int,
    data: RepairOrderUpdate,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """به‌روزرسانی سفارش تعمیر"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "write"):
        raise ApiError("FORBIDDEN", "دسترسی ویرایش سفارش تعمیر ندارید", http_status=403)
    
    result = repair_shop_service.update_repair_order(
        db, business_id, order_id, data.dict(exclude_unset=True), ctx.user.id
    )
    return success_response(data=result, request=request)


@router.delete("/businesses/{business_id}/orders/{order_id}")
def delete_repair_order(
    request: Request,
    business_id: int,
    order_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """حذف (لغو) سفارش تعمیر"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "delete"):
        raise ApiError("FORBIDDEN", "دسترسی حذف ندارید", http_status=403)
    
    result = repair_shop_service.delete_repair_order(
        db, business_id, order_id, ctx.user.id
    )
    return success_response(data=result, request=request)


# ========== Operations ==========

@router.post("/businesses/{business_id}/orders/{order_id}/assign-technician")
def assign_technician(
    request: Request,
    business_id: int,
    order_id: int,
    data: AssignTechnicianRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """اختصاص تعمیرکار به سفارش"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "write"):
        raise ApiError("FORBIDDEN", "دسترسی ویرایش سفارش تعمیر ندارید", http_status=403)
    
    result = repair_shop_operations.assign_technician_to_order(
        db, business_id, order_id, data.technician_id, ctx.user.id
    )
    return success_response(data=result, request=request)


@router.post("/businesses/{business_id}/orders/{order_id}/update-status")
def update_status(
    request: Request,
    business_id: int,
    order_id: int,
    data: UpdateStatusRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """تغییر وضعیت سفارش"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "write"):
        raise ApiError("FORBIDDEN", "دسترسی ویرایش سفارش تعمیر ندارید", http_status=403)
    
    result = repair_shop_operations.update_repair_order_status(
        db, business_id, order_id, data.status, data.notes, ctx.user.id, data.send_notification
    )
    return success_response(data=result, request=request)


@router.post("/businesses/{business_id}/orders/{order_id}/add-parts")
def add_parts(
    request: Request,
    business_id: int,
    order_id: int,
    data: AddPartsRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """افزودن قطعات به سفارش"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "write"):
        raise ApiError("FORBIDDEN", "دسترسی ویرایش سفارش تعمیر ندارید", http_status=403)
    
    parts_list = [part.dict() for part in data.parts]
    result = repair_shop_operations.add_parts_to_repair_order(
        db, business_id, order_id, parts_list, ctx.user.id
    )
    return success_response(data=result, request=request)


@router.post("/businesses/{business_id}/orders/{order_id}/calculate-costs")
def calculate_costs(
    request: Request,
    business_id: int,
    order_id: int,
    data: CalculateCostsRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """محاسبه هزینه‌های نهایی"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "write"):
        raise ApiError("FORBIDDEN", "دسترسی ویرایش سفارش تعمیر ندارید", http_status=403)
    
    result = repair_shop_operations.calculate_repair_costs(
        db, business_id, order_id, data.labor_cost, ctx.user.id
    )
    return success_response(data=result, request=request)


@router.post("/businesses/{business_id}/orders/{order_id}/complete")
def complete_repair(
    request: Request,
    business_id: int,
    order_id: int,
    data: CompleteRepairRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """اتمام تعمیر"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "write"):
        raise ApiError("FORBIDDEN", "دسترسی ویرایش سفارش تعمیر ندارید", http_status=403)
    
    result = repair_shop_operations.complete_repair_order(
        db, business_id, order_id, data.is_fixed, ctx.user.id, data.notes
    )
    return success_response(data=result, request=request)


@router.post("/businesses/{business_id}/orders/{order_id}/deliver")
def deliver_repair(
    request: Request,
    business_id: int,
    order_id: int,
    data: DeliverRepairRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """تحویل کالا به مشتری"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "write"):
        raise ApiError("FORBIDDEN", "دسترسی ویرایش سفارش تعمیر ندارید", http_status=403)
    
    result = repair_shop_operations.deliver_repair_order(
        db, business_id, order_id, ctx.user.id, data.notes
    )
    return success_response(data=result, request=request)


# ========== Accounting ==========

@router.post("/businesses/{business_id}/orders/{order_id}/create-invoice")
def create_repair_invoice(
    request: Request,
    business_id: int,
    order_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """صدور فاکتور تعمیر و ثبت اسناد حسابداری"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "write"):
        raise ApiError("FORBIDDEN", "دسترسی ویرایش سفارش تعمیر ندارید", http_status=403)
    
    from app.services.repair_shop_accounting import create_repair_invoice_accounting
    from adapters.db.repositories.repair_shop_repository import RepairOrderRepository
    
    repo = RepairOrderRepository(db)
    repair_order = repo.get_by_id(order_id, business_id)
    
    if not repair_order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "سفارش تعمیر یافت نشد", http_status=404)
    
    result = create_repair_invoice_accounting(db, business_id, repair_order, ctx.user.id)
    db.commit()
    
    return success_response(data=result, request=request, http_status=201)


@router.get("/businesses/{business_id}/orders/{order_id}/accounting-summary")
def get_accounting_summary(
    request: Request,
    business_id: int,
    order_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """دریافت خلاصه حسابداری سفارش تعمیر"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "read"):
        raise ApiError("FORBIDDEN", "دسترسی به بخش تعمیرگاه ندارید", http_status=403)
    
    from app.services.repair_shop_accounting import get_repair_accounting_summary
    
    result = get_repair_accounting_summary(db, business_id, order_id)
    return success_response(data=result, request=request)


# ========== Reports ==========

@router.get("/businesses/{business_id}/warranty/{warranty_code_id}/history")
def get_warranty_repair_history(
    request: Request,
    business_id: int,
    warranty_code_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """تاریخچه تعمیرات براساس کد گارانتی"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("repair_shop", "read"):
        raise ApiError("FORBIDDEN", "دسترسی به بخش تعمیرگاه ندارید", http_status=403)
    
    result = repair_shop_operations.get_repair_history_by_warranty(
        db, business_id, warranty_code_id
    )
    return success_response(data={"items": result}, request=request)

