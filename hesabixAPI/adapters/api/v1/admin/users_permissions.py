from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from typing import Dict, Any, List
from pydantic import BaseModel, Field

from adapters.db.session import get_db
from adapters.db.models.user import User
from adapters.db.repositories.user_repo import UserRepository
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_app_permission
from app.core.responses import success_response

router = APIRouter(
	prefix="/admin/users",
	tags=["مدیریت کاربران", "مدیریت سیستم"]
)


# ========== Schemas ==========

class AppPermissionsResponse(BaseModel):
	"""پاسخ دریافت App Permissions"""
	user_id: int
	email: str
	app_permissions: Dict[str, bool] = Field(default_factory=dict)
	
	class Config:
		from_attributes = True


class UpdateAppPermissionsRequest(BaseModel):
	"""درخواست به‌روزرسانی App Permissions"""
	permissions: Dict[str, bool] = Field(
		..., 
		description="دسترسی‌های سطح اپلیکیشن (مثال: {'support_operator': true, 'system_settings': false})"
	)
	
	class Config:
		json_schema_extra = {
			"example": {
				"permissions": {
					"support_operator": True,
					"system_settings": False,
					"user_management": False,
					"business_management": False
				}
			}
		}


class OperatorSummary(BaseModel):
	"""خلاصه اطلاعات اپراتور"""
	id: int
	email: str
	first_name: str | None
	last_name: str | None
	full_name: str | None
	telegram_chat_id: str | None
	is_active: bool
	created_at: str
	
	class Config:
		from_attributes = True


# ========== Endpoints ==========

@router.get(
	"/{user_id}/app-permissions",
	summary="دریافت App Permissions کاربر",
	description="دریافت دسترسی‌های سطح اپلیکیشن یک کاربر. نیاز به مجوز SuperAdmin دارد.",
	response_model=AppPermissionsResponse
)
@require_app_permission("superadmin")
async def get_user_app_permissions(
	user_id: int,
	request: Request,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
	"""دریافت App Permissions کاربر"""
	user = db.get(User, user_id)
	if not user:
		raise HTTPException(status_code=404, detail="کاربر یافت نشد")
	
	return success_response(
		data={
			"user_id": user.id,
			"email": user.email,
			"app_permissions": user.app_permissions or {}
		},
		request=request
	)


@router.put(
	"/{user_id}/app-permissions",
	summary="به‌روزرسانی App Permissions کاربر",
	description="به‌روزرسانی دسترسی‌های سطح اپلیکیشن یک کاربر. فقط SuperAdmin.",
)
@require_app_permission("superadmin")
async def update_user_app_permissions(
	user_id: int,
	permissions_request: UpdateAppPermissionsRequest,
	request: Request,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
	"""به‌روزرسانی App Permissions کاربر"""
	
	# بررسی وجود کاربر
	user = db.get(User, user_id)
	if not user:
		raise HTTPException(status_code=404, detail="کاربر یافت نشد")
	
	# جلوگیری از تغییر permissions خودش
	if user.id == ctx.get_user_id():
		raise HTTPException(
			status_code=403, 
			detail="شما نمی‌توانید دسترسی‌های خود را تغییر دهید"
		)
	
	# فیلتر کردن فقط permissions معتبر
	valid_permissions = {
		"superadmin",
		"support_operator", 
		"system_settings",
		"user_management",
		"business_management"
	}
	
	# فقط permissions که true هستند را نگه می‌داریم
	new_permissions = {
		k: v for k, v in permissions_request.permissions.items()
		if k in valid_permissions and v is True
	}
	
	# به‌روزرسانی
	user.app_permissions = new_permissions
	db.commit()
	db.refresh(user)
	
	return success_response(
		data={
			"user_id": user.id,
			"email": user.email,
			"app_permissions": user.app_permissions or {}
		},
		request=request,
		message="دسترسی‌ها با موفقیت به‌روزرسانی شد"
	)


# ========== Operator Management Endpoints ==========

@router.get(
	"/operators",
	summary="لیست اپراتورهای پشتیبانی",
	description="دریافت لیست تمام اپراتورهای پشتیبانی فعال",
)
@require_app_permission("superadmin")
async def list_support_operators(
	request: Request,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
	"""لیست اپراتورهای پشتیبانی"""
	user_repo = UserRepository(db)
	operators = user_repo.get_support_operators()
	
	operators_data = []
	for op in operators:
		full_name = None
		if op.first_name or op.last_name:
			parts = [p for p in [op.first_name, op.last_name] if p]
			full_name = " ".join(parts) if parts else None
		
		operators_data.append({
			"id": op.id,
			"email": op.email,
			"first_name": op.first_name,
			"last_name": op.last_name,
			"full_name": full_name,
			"telegram_chat_id": str(op.telegram_chat_id) if op.telegram_chat_id else None,
			"is_active": op.is_active,
			"created_at": op.created_at.isoformat()
		})
	
	return success_response(
		data={"items": operators_data, "total": len(operators_data)},
		request=request
	)


@router.post(
	"/operators/{user_id}",
	summary="اضافه کردن اپراتور پشتیبانی",
	description="افزودن مجوز اپراتور پشتیبانی به یک کاربر"
)
@require_app_permission("superadmin")
async def add_support_operator(
	user_id: int,
	request: Request,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
	"""اضافه کردن اپراتور پشتیبانی"""
	user = db.get(User, user_id)
	if not user:
		raise HTTPException(status_code=404, detail="کاربر یافت نشد")
	
	# اضافه کردن permission
	permissions = user.app_permissions or {}
	permissions['support_operator'] = True
	user.app_permissions = permissions
	
	db.commit()
	db.refresh(user)
	
	return success_response(
		data={"user_id": user.id, "email": user.email},
		request=request,
		message="کاربر به عنوان اپراتور پشتیبانی اضافه شد"
	)


@router.delete(
	"/operators/{user_id}",
	summary="حذف اپراتور پشتیبانی",
	description="لغو مجوز اپراتور پشتیبانی از یک کاربر"
)
@require_app_permission("superadmin")
async def remove_support_operator(
	user_id: int,
	request: Request,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
	"""حذف اپراتور پشتیبانی"""
	user = db.get(User, user_id)
	if not user:
		raise HTTPException(status_code=404, detail="کاربر یافت نشد")
	
	# حذف permission
	if user.app_permissions and 'support_operator' in user.app_permissions:
		permissions = user.app_permissions.copy()
		del permissions['support_operator']
		user.app_permissions = permissions if permissions else {}
		
		db.commit()
		db.refresh(user)
	
	return success_response(
		data={"user_id": user.id, "email": user.email},
		request=request,
		message="مجوز اپراتور پشتیبانی لغو شد"
	)

