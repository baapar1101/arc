# Removed __future__ annotations to fix OpenAPI schema generation

from fastapi import APIRouter, Depends, Request, Query, UploadFile, File
from sqlalchemy.orm import Session
import io

from adapters.db.session import get_db
from adapters.db.repositories.user_repo import UserRepository
from adapters.db.repositories.password_reset_repo import PasswordResetRepository
from adapters.api.v1.schemas import QueryInfo, SuccessResponse, UsersListResponse, UsersSummaryResponse, UserResponse
from app.core.responses import success_response, format_datetime_fields
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_user_management
from app.services.file_storage_service import FileStorageService
from app.services.auth_service import _hash_reset_token
from app.core.settings import get_settings
from secrets import token_urlsafe
from datetime import datetime, timedelta
from uuid import UUID
from starlette.responses import StreamingResponse


router = APIRouter(prefix="/users", tags=["users"])


@router.post("/search", 
	summary="لیست کاربران با فیلتر پیشرفته", 
	description="دریافت لیست کاربران با قابلیت فیلتر، جستجو، مرتب‌سازی و صفحه‌بندی. نیاز به مجوز usermanager در سطح اپلیکیشن دارد.",
	response_model=SuccessResponse,
	responses={
		200: {
			"description": "لیست کاربران با موفقیت دریافت شد",
			"content": {
				"application/json": {
					"example": {
						"success": True,
						"message": "لیست کاربران دریافت شد",
						"data": {
							"items": [
								{
									"id": 1,
									"email": "user@example.com",
									"mobile": "09123456789",
									"first_name": "احمد",
									"last_name": "احمدی",
									"is_active": True,
									"referral_code": "ABC123",
									"created_at": "2024-01-01T00:00:00Z"
								}
							],
							"pagination": {
								"total": 1,
								"page": 1,
								"per_page": 10,
								"total_pages": 1,
								"has_next": False,
								"has_prev": False
							}
						}
					}
				}
			}
		},
		401: {
			"description": "کاربر احراز هویت نشده است"
		},
		403: {
			"description": "دسترسی غیرمجاز - نیاز به مجوز usermanager",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "Missing app permission: user_management",
						"error_code": "FORBIDDEN"
					}
				}
			}
		}
	}
)
@require_user_management()
def list_users(
	request: Request,
	query_info: QueryInfo,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
	"""
	دریافت لیست کاربران با قابلیت فیلتر، جستجو، مرتب‌سازی و صفحه‌بندی
	
	پارامترهای QueryInfo:
	- sort_by: فیلد مرتب‌سازی (مثال: created_at, first_name)
	- sort_desc: ترتیب نزولی (true/false)
	- take: تعداد رکورد در هر صفحه (پیش‌فرض: 10)
	- skip: تعداد رکورد صرف‌نظر شده (پیش‌فرض: 0)
	- search: عبارت جستجو
	- search_fields: فیلدهای جستجو (مثال: ["first_name", "last_name", "email"])
	- filters: آرایه فیلترها با ساختار:
	  [
		{
		  "property": "is_active",
		  "operator": "=",
		  "value": true
		},
		{
		  "property": "first_name", 
		  "operator": "*",
		  "value": "احمد"
		}
	  ]
	
	عملگرهای پشتیبانی شده:
	- = : برابر
	- > : بزرگتر از
	- >= : بزرگتر یا مساوی
	- < : کوچکتر از
	- <= : کوچکتر یا مساوی
	- != : نامساوی
	- * : شامل (contains)
	- ?* : خاتمه یابد (ends with)
	- *? : شروع شود (starts with)
	- in : در بین مقادیر آرایه
	"""
	repo = UserRepository(db)
	
	# تبدیل فیلترهای status و role به فیلترهای واقعی
	if query_info.filters:
		from adapters.api.v1.schemas import FilterItem
		from adapters.db.models.user import User
		from sqlalchemy import or_, and_
		
		# ایجاد یک QueryInfo جدید با فیلترهای تبدیل شده
		converted_filters = []
		for f in query_info.filters:
			if f.property == "status":
				# تبدیل status به is_active
				if f.operator == "=":
					is_active = f.value == "active"
					converted_filters.append(FilterItem(property="is_active", operator="=", value=is_active))
				elif f.operator == "in" and isinstance(f.value, list):
					# اگر active در لیست باشد، is_active = True
					has_active = "active" in f.value
					has_inactive = any(s in ["inactive", "suspended"] for s in f.value)
					if has_active and not has_inactive:
						converted_filters.append(FilterItem(property="is_active", operator="=", value=True))
					elif has_inactive and not has_active:
						converted_filters.append(FilterItem(property="is_active", operator="=", value=False))
					# اگر هر دو وجود دارند، فیلتر نکنیم
				else:
					converted_filters.append(f)
			elif f.property == "role":
				# فیلتر role باید بعد از دریافت داده‌ها اعمال شود
				# برای حالا، فیلتر را نادیده می‌گیریم
				pass
			else:
				converted_filters.append(f)
		
		# ایجاد QueryInfo جدید
		from adapters.api.v1.schemas import QueryInfo
		modified_query_info = QueryInfo(
			sort_by=query_info.sort_by,
			sort_desc=query_info.sort_desc,
			take=query_info.take,
			skip=query_info.skip,
			search=query_info.search,
			search_fields=query_info.search_fields,
			filters=converted_filters if converted_filters else None
		)
		users, total = repo.query_with_filters(modified_query_info)
	else:
		users, total = repo.query_with_filters(query_info)
	
	# اعمال فیلتر role بعد از دریافت داده‌ها
	if query_info.filters:
		role_filters = [f for f in query_info.filters if f.property == "role"]
		if role_filters:
			filtered_users = []
			for user in users:
				# تعیین role از app_permissions
				role = "user"
				if user.app_permissions:
					if user.app_permissions.get("superadmin"):
						role = "admin"
					elif user.app_permissions.get("operator"):
						role = "operator"
					elif user.app_permissions.get("supervisor"):
						role = "supervisor"
				
				# بررسی تطابق با فیلتر
				matches = True
				for rf in role_filters:
					if rf.operator == "=":
						matches = role == rf.value
					elif rf.operator == "in" and isinstance(rf.value, list):
						matches = role in rf.value
					else:
						matches = False
					if not matches:
						break
				
				if matches:
					filtered_users.append(user)
			
			users = filtered_users
			total = len(filtered_users)
	
	# تبدیل User objects به dictionary با اطلاعات اضافی
	user_dicts = [repo.to_dict(user, include_extended=True) for user in users]
	
	# فرمت کردن تاریخ‌ها
	formatted_users = [format_datetime_fields(user_dict, request) for user_dict in user_dicts]
	
	# محاسبه اطلاعات صفحه‌بندی
	page = (query_info.skip // query_info.take) + 1
	total_pages = (total + query_info.take - 1) // query_info.take
	
	response_data = {
		"items": formatted_users,
		"pagination": {
			"total": total,
			"page": page,
			"per_page": query_info.take,
			"total_pages": total_pages,
			"has_next": page < total_pages,
			"has_prev": page > 1
		},
		"query_info": {
			"sort_by": query_info.sort_by,
			"sort_desc": query_info.sort_desc,
			"search": query_info.search,
			"search_fields": query_info.search_fields,
			"filters": [{"property": f.property, "operator": f.operator, "value": f.value} for f in (query_info.filters or [])]
		}
	}
	
	return success_response(response_data, request)


@router.get("", 
	summary="لیست ساده کاربران", 
	description="دریافت لیست ساده کاربران. نیاز به مجوز usermanager در سطح اپلیکیشن دارد.",
	response_model=SuccessResponse,
	responses={
		200: {
			"description": "لیست کاربران با موفقیت دریافت شد",
			"content": {
				"application/json": {
					"example": {
						"success": True,
						"message": "لیست کاربران دریافت شد",
						"data": [
							{
								"id": 1,
								"email": "user@example.com",
								"mobile": "09123456789",
								"first_name": "احمد",
								"last_name": "احمدی",
								"is_active": True,
								"referral_code": "ABC123",
								"created_at": "2024-01-01T00:00:00Z"
							}
						]
					}
				}
			}
		},
		401: {
			"description": "کاربر احراز هویت نشده است"
		},
		403: {
			"description": "دسترسی غیرمجاز - نیاز به مجوز usermanager",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "Missing app permission: user_management",
						"error_code": "FORBIDDEN"
					}
				}
			}
		}
	}
)
@require_user_management()
def list_users_simple(
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	limit: int = Query(10, ge=1, le=100, description="تعداد رکورد در هر صفحه"),
	offset: int = Query(0, ge=0, description="تعداد رکورد صرف‌نظر شده")
):
	"""دریافت لیست ساده کاربران"""
	repo = UserRepository(db)
	
	# Create basic query info
	query_info = QueryInfo(take=limit, skip=offset)
	users, total = repo.query_with_filters(query_info)
	
	# تبدیل User objects به dictionary
	user_dicts = [repo.to_dict(user) for user in users]
	
	# فرمت کردن تاریخ‌ها
	formatted_users = [format_datetime_fields(user_dict, None) for user_dict in user_dicts]
	
	return success_response(formatted_users, None)


@router.post(
	"/me/signature",
	summary="آپلود امضای کاربر جاری",
	description="آپلود تصویر امضای کاربر و ذخیره آن در سیستم فایل.",
	response_model=SuccessResponse,
)
async def upload_my_signature(
	request: Request,
	file: UploadFile = File(...),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
):
	"""آپلود امضای کاربر کنونی و ذخیره file_id در User.signature_file_id"""
	repo = UserRepository(db)
	user = repo.get_by_id(ctx.get_user_id())
	if not user:
		from app.core.responses import ApiError
		raise ApiError("USER_NOT_FOUND", "کاربر یافت نشد", http_status=404)

	storage = FileStorageService(db)
	saved = await storage.upload_file(
		file=file,
		user_id=ctx.get_user_id(),
		module_context="user_signature",
		context_id=None,
		developer_data={"user_id": ctx.get_user_id()},
		is_temporary=False,
		expires_in_days=3650,
	)

	# به‌روز کردن شناسه امضا روی کاربر
	user.signature_file_id = saved.get("file_id")
	db.commit()

	return success_response(
		{
			"signature_file_id": user.signature_file_id,
			"file": saved,
		},
		request,
	)


@router.get(
	"/me/signature",
	summary="دریافت فایل امضای کاربر جاری",
	description="بازگرداندن تصویر امضای کاربر کنونی به‌صورت فایل (برای نمایش در پروفایل یا فاکتور).",
)
async def get_my_signature(
	request: Request,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
):
	repo = UserRepository(db)
	user = repo.get_by_id(ctx.get_user_id())
	if not user or not getattr(user, "signature_file_id", None):
		from app.core.responses import ApiError
		raise ApiError("SIGNATURE_NOT_SET", "امضایی برای این کاربر ثبت نشده است", http_status=404)

	storage = FileStorageService(db)
	file_data = await storage.download_file(UUID(str(user.signature_file_id)))

	return StreamingResponse(
		content=io.BytesIO(file_data["content"]),
		media_type=file_data["mime_type"] or "image/png",
		headers={"Content-Disposition": f'inline; filename="{file_data["filename"]}"'},
	)


@router.get("/{user_id}", 
	summary="دریافت اطلاعات یک کاربر", 
	description="دریافت اطلاعات کامل یک کاربر بر اساس شناسه. نیاز به مجوز usermanager در سطح اپلیکیشن دارد.",
	response_model=SuccessResponse,
	responses={
		200: {
			"description": "اطلاعات کاربر با موفقیت دریافت شد",
			"content": {
				"application/json": {
					"example": {
						"success": True,
						"message": "اطلاعات کاربر دریافت شد",
						"data": {
							"id": 1,
							"email": "user@example.com",
							"mobile": "09123456789",
							"first_name": "احمد",
							"last_name": "احمدی",
							"is_active": True,
							"referral_code": "ABC123",
							"created_at": "2024-01-01T00:00:00Z"
						}
					}
				}
			}
		},
		401: {
			"description": "کاربر احراز هویت نشده است"
		},
		403: {
			"description": "دسترسی غیرمجاز - نیاز به مجوز usermanager",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "Missing app permission: user_management",
						"error_code": "FORBIDDEN"
					}
				}
			}
		},
		404: {
			"description": "کاربر یافت نشد",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "کاربر یافت نشد",
						"error_code": "USER_NOT_FOUND"
					}
				}
			}
		}
	}
)
@require_user_management()
def get_user(
	user_id: int,
	request: Request,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
	"""دریافت اطلاعات کامل یک کاربر بر اساس ID شامل کسب‌وکارها و نشست‌ها"""
	repo = UserRepository(db)
	user = repo.get_by_id(user_id)
	
	if not user:
		from fastapi import HTTPException
		raise HTTPException(status_code=404, detail="کاربر یافت نشد")
	
	# دریافت اطلاعات پایه کاربر
	user_dict = repo.to_dict(user, include_extended=True)
	
	# دریافت کسب‌وکارهای کاربر
	from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
	from adapters.db.models.business import Business
	bp_repo = BusinessPermissionRepository(db)
	business_permissions = bp_repo.get_user_businesses(user_id)
	
	businesses = []
	for bp in business_permissions:
		business = db.get(Business, bp.business_id)
		if business:
			# تعیین نقش کاربر در کسب‌وکار
			role = "user"
			if business.owner_id == user_id:
				role = "owner"
			elif bp.business_permissions:
				# بررسی نقش از permissions
				perms = bp.business_permissions
				if perms.get("admin"):
					role = "admin"
				elif perms.get("operator"):
					role = "operator"
				elif perms.get("supervisor"):
					role = "supervisor"
			
			businesses.append({
				"id": business.id,
				"name": business.name,
				"field": business.business_field.value if business.business_field else None,
				"role": role,
				"status": "active",  # می‌تواند از business status استخراج شود
				"created_at": bp.created_at,
			})
	
	user_dict["businesses"] = businesses
	
	# دریافت نشست‌های فعال کاربر
	from adapters.db.models.api_key import ApiKey
	from sqlalchemy import select, desc
	stmt = select(ApiKey).where(
		ApiKey.user_id == user_id,
		ApiKey.revoked_at.is_(None)
	).order_by(desc(ApiKey.last_used_at))
	sessions_list = db.execute(stmt).scalars().all()
	
	sessions = []
	for session in sessions_list:
		sessions.append({
			"id": session.id,
			"device": session.device_id or session.user_agent or "دستگاه نامشخص",
			"ip": session.ip,
			"last_active_at": session.last_used_at or session.created_at,
			"created_at": session.created_at,
		})
	
	user_dict["sessions"] = sessions
	
	formatted_user = format_datetime_fields(user_dict, request)
	
	return success_response(formatted_user, request)


@router.get("/stats/summary", 
	summary="آمار کلی کاربران", 
	description="دریافت آمار کلی کاربران شامل تعداد کل، فعال و غیرفعال. نیاز به مجوز usermanager در سطح اپلیکیشن دارد.",
	response_model=SuccessResponse,
	responses={
		200: {
			"description": "آمار کاربران با موفقیت دریافت شد",
			"content": {
				"application/json": {
					"example": {
						"success": True,
						"message": "آمار کاربران دریافت شد",
						"data": {
							"total_users": 100,
							"active_users": 85,
							"inactive_users": 15,
							"active_percentage": 85.0
						}
					}
				}
			}
		},
		401: {
			"description": "کاربر احراز هویت نشده است"
		},
		403: {
			"description": "دسترسی غیرمجاز - نیاز به مجوز usermanager",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "Missing app permission: user_management",
						"error_code": "FORBIDDEN"
					}
				}
			}
		}
	}
)
@require_user_management()
def get_users_summary(
	request: Request,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
	"""دریافت آمار کلی کاربران"""
	repo = UserRepository(db)
	
	# تعداد کل کاربران
	total_users = repo.count_all()
	
	# تعداد کاربران فعال
	active_users = repo.query_with_filters(QueryInfo(
		filters=[{"property": "is_active", "operator": "=", "value": True}]
	))[1]
	
	# تعداد کاربران غیرفعال
	inactive_users = total_users - active_users
	
	response_data = {
		"total_users": total_users,
		"active_users": active_users,
		"inactive_users": inactive_users,
		"active_percentage": round((active_users / total_users * 100), 2) if total_users > 0 else 0
	}
	
	return success_response(response_data, request)


@router.post("/bulk-activate",
	summary="فعال‌سازی دسته‌ای کاربران",
	description="فعال‌سازی چندین کاربر به صورت همزمان. نیاز به مجوز usermanager در سطح اپلیکیشن دارد.",
	response_model=SuccessResponse,
)
@require_user_management()
def bulk_activate_users(
	request: Request,
	user_ids: list[int],
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
	"""فعال‌سازی دسته‌ای کاربران"""
	repo = UserRepository(db)
	updated_count = 0
	
	for user_id in user_ids:
		user = repo.get_by_id(user_id)
		if user and not user.is_active:
			user.is_active = True
			updated_count += 1
	
	db.commit()
	
	return success_response({
		"updated_count": updated_count,
		"total_requested": len(user_ids)
	}, request)


@router.post("/bulk-suspend",
	summary="تعلیق دسته‌ای کاربران",
	description="تعلیق چندین کاربر به صورت همزمان. نیاز به مجوز usermanager در سطح اپلیکیشن دارد.",
	response_model=SuccessResponse,
)
@require_user_management()
def bulk_suspend_users(
	request: Request,
	user_ids: list[int],
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
	"""تعلیق دسته‌ای کاربران"""
	repo = UserRepository(db)
	updated_count = 0
	
	for user_id in user_ids:
		user = repo.get_by_id(user_id)
		if user and user.is_active:
			# جلوگیری از تعلیق خود کاربر
			if user.id == ctx.get_user_id():
				continue
			user.is_active = False
			updated_count += 1
	
	db.commit()
	
	return success_response({
		"updated_count": updated_count,
		"total_requested": len(user_ids)
	}, request)


@router.post("/bulk-reset-password",
	summary="بازنشانی رمز عبور دسته‌ای کاربران",
	description="ایجاد توکن بازنشانی رمز عبور برای چندین کاربر. نیاز به مجوز usermanager در سطح اپلیکیشن دارد.",
	response_model=SuccessResponse,
)
@require_user_management()
def bulk_reset_password(
	request: Request,
	user_ids: list[int],
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
	"""بازنشانی رمز عبور دسته‌ای کاربران"""
	from app.services.auth_service import _hash_reset_token
	from adapters.db.repositories.password_reset_repo import PasswordResetRepository
	from app.core.settings import get_settings
	from secrets import token_urlsafe
	from datetime import datetime, timedelta
	
	repo = UserRepository(db)
	tokens_created = 0
	settings = get_settings()
	pr_repo = PasswordResetRepository(db)
	
	for user_id in user_ids:
		user = repo.get_by_id(user_id)
		if user:
			identifier = user.email or user.mobile
			if identifier:
				try:
					token = token_urlsafe(32)
					token_hash = _hash_reset_token(token)
					expires_at = datetime.utcnow() + timedelta(seconds=settings.reset_password_ttl_seconds)
					pr_repo.create(user_id=user.id, token_hash=token_hash, expires_at=expires_at)
					tokens_created += 1
				except:
					pass  # در صورت خطا ادامه می‌دهیم
	
	db.commit()
	
	return success_response({
		"tokens_created": tokens_created,
		"total_requested": len(user_ids)
	}, request)


@router.post("/{user_id}/suspend",
	summary="تعلیق یک کاربر",
	description="تعلیق یک کاربر خاص. نیاز به مجوز usermanager در سطح اپلیکیشن دارد.",
	response_model=SuccessResponse,
)
@require_user_management()
def suspend_user(
	user_id: int,
	request: Request,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
	"""تعلیق یک کاربر"""
	repo = UserRepository(db)
	user = repo.get_by_id(user_id)
	
	if not user:
		from fastapi import HTTPException
		raise HTTPException(status_code=404, detail="کاربر یافت نشد")
	
	# جلوگیری از تعلیق خود کاربر
	if user.id == ctx.get_user_id():
		from app.core.responses import ApiError
		raise ApiError("CANNOT_SUSPEND_SELF", "نمی‌توانید خود را تعلیق کنید", http_status=400)
	
	user.is_active = False
	db.commit()
	
	return success_response({"message": "کاربر با موفقیت تعلیق شد"}, request)


@router.post("/{user_id}/activate",
	summary="فعال‌سازی یک کاربر",
	description="فعال‌سازی یک کاربر خاص. نیاز به مجوز usermanager در سطح اپلیکیشن دارد.",
	response_model=SuccessResponse,
)
@require_user_management()
def activate_user(
	user_id: int,
	request: Request,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
	"""فعال‌سازی یک کاربر"""
	repo = UserRepository(db)
	user = repo.get_by_id(user_id)
	
	if not user:
		from fastapi import HTTPException
		raise HTTPException(status_code=404, detail="کاربر یافت نشد")
	
	user.is_active = True
	db.commit()
	
	return success_response({"message": "کاربر با موفقیت فعال شد"}, request)


@router.post("/{user_id}/reset-password",
	summary="بازنشانی رمز عبور یک کاربر",
	description="ایجاد توکن بازنشانی رمز عبور برای یک کاربر. نیاز به مجوز usermanager در سطح اپلیکیشن دارد.",
	response_model=SuccessResponse,
)
@require_user_management()
def reset_user_password(
	user_id: int,
	request: Request,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
	"""بازنشانی رمز عبور یک کاربر"""
	from app.services.auth_service import _hash_reset_token
	from adapters.db.repositories.password_reset_repo import PasswordResetRepository
	from app.core.settings import get_settings
	from secrets import token_urlsafe
	from datetime import datetime, timedelta
	
	repo = UserRepository(db)
	user = repo.get_by_id(user_id)
	
	if not user:
		from fastapi import HTTPException
		raise HTTPException(status_code=404, detail="کاربر یافت نشد")
	
	identifier = user.email or user.mobile
	if not identifier:
		from app.core.responses import ApiError
		raise ApiError("NO_IDENTIFIER", "کاربر ایمیل یا موبایل ندارد", http_status=400)
	
	settings = get_settings()
	pr_repo = PasswordResetRepository(db)
	token = token_urlsafe(32)
	token_hash = _hash_reset_token(token)
	expires_at = datetime.utcnow() + timedelta(seconds=settings.reset_password_ttl_seconds)
	pr_repo.create(user_id=user.id, token_hash=token_hash, expires_at=expires_at)
	db.commit()
	
	return success_response({
		"message": "توکن بازنشانی رمز عبور ایجاد شد",
		"token": token  # در production نباید token برگردانده شود
	}, request)


