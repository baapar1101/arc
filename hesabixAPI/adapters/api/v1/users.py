# Removed __future__ annotations to fix OpenAPI schema generation

from fastapi import APIRouter, Depends, Request, Query, UploadFile, File, Body
from sqlalchemy.orm import Session
import io

from adapters.db.session import get_db
from adapters.db.repositories.user_repo import UserRepository
from adapters.db.repositories.password_reset_repo import PasswordResetRepository
from adapters.api.v1.schemas import (
	QueryInfo, SuccessResponse, UsersListResponse, UsersSummaryResponse, UserResponse,
	BulkActivateRequest, BulkSuspendRequest, BulkResetPasswordRequest,
	UserDetailResponse, BulkOperationResponse, BulkResetPasswordResponse,
	AdminSetUserPasswordRequest,
)
from app.core.responses import success_response, format_datetime_fields, ApiError
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_user_management
from app.core.cache import get_cache
from app.services.file_storage_service import FileStorageService
from app.services.auth_service import (
	_hash_reset_token,
	send_password_reset_notification,
	admin_set_user_password,
	build_password_reset_web_url,
)
from app.core.settings import get_settings
from secrets import token_urlsafe
from datetime import datetime, timedelta, date, time
from typing import Literal
from uuid import UUID
from starlette.responses import StreamingResponse


router = APIRouter(prefix="/users", tags=["کاربران", "مدیریت سیستم"])


def verify_user_management_page_access(ctx: AuthContext = Depends(get_current_user)) -> AuthContext:
	"""همان بازهٔ دسترسی UI: سوپرادمین یا system_settings یا user_management."""
	if ctx.is_superadmin() or ctx.has_app_permission("system_settings") or ctx.has_app_permission("user_management"):
		return ctx
	raise ApiError("FORBIDDEN", "مجوز دسترسی به مدیریت کاربران یا تنظیمات سیستم لازم است", http_status=403)


@router.post("/search", 
	summary="لیست کاربران با فیلتر پیشرفته", 
	description="""
	دریافت لیست کاربران با قابلیت فیلتر، جستجو، مرتب‌سازی و صفحه‌بندی.
	
	### نکات:
	- نیاز به مجوز `user_management` در سطح اپلیکیشن دارد
	- Rate Limit: 500 request در دقیقه (عمومی برای تمام endpoint ها)
	- نتایج به مدت 60 ثانیه cache می‌شوند (Cache key بر اساس query parameters و user_id ایجاد می‌شود)
	- برای جستجوی ساده از `GET /users` استفاده کنید
	- حداکثر تعداد رکورد در هر صفحه: 1000 (پارامتر `take`)
	""",
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
		},
		422: {
			"description": "خطا در اعتبارسنجی داده‌ها",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "take نمی‌تواند بیشتر از 1000 باشد",
						"error_code": "VALIDATION_ERROR"
					}
				}
			}
		},
		429: {
			"description": "تعداد درخواست‌ها بیش از حد مجاز",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "تعداد درخواست‌های شما بیش از حد مجاز است. لطفاً کمی صبر کنید.",
						"error_code": "RATE_LIMIT_EXCEEDED"
					}
				}
			},
			"headers": {
				"X-RateLimit-Limit": {"description": "حد مجاز درخواست", "schema": {"type": "integer", "example": 500}},
				"X-RateLimit-Remaining": {"description": "تعداد درخواست‌های باقیمانده", "schema": {"type": "integer", "example": 0}},
				"X-RateLimit-Reset": {"description": "زمان reset به ثانیه (Unix timestamp)", "schema": {"type": "integer", "example": 1705324800}},
				"Retry-After": {"description": "زمان باقیمانده تا retry به ثانیه", "schema": {"type": "integer", "example": 30}}
			}
		}
	}
)
@require_user_management()
def list_users(
	request: Request,
	query_info: QueryInfo = Body(..., description="پارامترهای جستجو، فیلتر، مرتب‌سازی و صفحه‌بندی"),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
	"""
	دریافت لیست کاربران با قابلیت فیلتر، جستجو، مرتب‌سازی و صفحه‌بندی
	
	### پارامترهای QueryInfo:
	- **sort_by**: فیلد مرتب‌سازی (مثال: created_at, first_name, email)
	- **sort_desc**: ترتیب نزولی (true/false)
	- **take**: تعداد رکورد در هر صفحه (پیش‌فرض: 10، حداکثر: 100)
	- **skip**: تعداد رکورد صرف‌نظر شده (پیش‌فرض: 0)
	- **search**: عبارت جستجو (جستجو در فیلدهای مشخص شده)
	- **search_fields**: فیلدهای جستجو (مثال: ["first_name", "last_name", "email"])
	- **filters**: آرایه فیلترها با ساختار:
	  ```json
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
		},
		{
		  "property": "status",
		  "operator": "in",
		  "value": ["active", "inactive"]
		},
		{
		  "property": "role",
		  "operator": "=",
		  "value": "admin"
		}
	  ]
	  ```
	
	### عملگرهای پشتیبانی شده:
	- **=**: برابر
	- **>**: بزرگتر از
	- **>=**: بزرگتر یا مساوی
	- **<**: کوچکتر از
	- **<=**: کوچکتر یا مساوی
	- **!=**: نامساوی
	- **\\***: شامل (contains)
	- **?\\***: خاتمه یابد (ends with)
	- **\\*?**: شروع شود (starts with)
	- **in**: در بین مقادیر آرایه
	- **not_in**: موجود نیست در لیست
	- **is_null**: مقدار خالی است
	- **is_not_null**: مقدار خالی نیست
	
	### فیلترهای خاص:
	- **status**: می‌تواند "active", "inactive", "suspended" باشد (به صورت خودکار به is_active تبدیل می‌شود)
	- **role**: می‌تواند "user", "admin", "operator", "supervisor" باشد (بر اساس app_permissions)
	
	### Cache:
	- نتایج به مدت 60 ثانیه cache می‌شوند
	- Cache key بر اساس query parameters و user_id ایجاد می‌شود
	
	### مثال cURL:
	```bash
	curl -X POST "http://localhost:8000/api/v1/users/search" \\
		 -H "Authorization: Bearer sk_your_api_key" \\
		 -H "Content-Type: application/json" \\
		 -d '{
		   "take": 20,
		   "skip": 0,
		   "sort_by": "created_at",
		   "sort_desc": true,
		   "search": "احمد",
		   "search_fields": ["first_name", "last_name", "email"],
		   "filters": [
			 {
			   "property": "is_active",
			   "operator": "=",
			   "value": true
			 }
		   ]
		 }'
	```
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
	
	# کش لیست کاربران مدیریت‌شده
	cache = get_cache()
	cache_key = None

	if cache.enabled:
		import json, hashlib
		key_payload = {
			"admin_user_id": ctx.get_user_id(),
			"query": {
				"sort_by": query_info.sort_by,
				"sort_desc": query_info.sort_desc,
				"take": query_info.take,
				"skip": query_info.skip,
				"search": query_info.search,
				"search_fields": query_info.search_fields,
				"filters": [f.model_dump() for f in (query_info.filters or [])],
			},
		}
		key_str = json.dumps(key_payload, sort_keys=True, ensure_ascii=False)
		key_hash = hashlib.sha256(key_str.encode("utf-8")).hexdigest()[:16]
		cache_key = f"users_list:{key_hash}"
		cached = cache.get(cache_key)
		if cached is not None:
			return success_response(cached, request)
	
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
	
	if cache.enabled and cache_key:
		cache.set(cache_key, response_data, ttl=60)
	
	return success_response(response_data, request)


@router.get("", 
	summary="لیست ساده کاربران", 
	description="""
	دریافت لیست ساده کاربران با صفحه‌بندی.
	
	### Query Parameters:
	- **limit**: تعداد رکورد در هر صفحه (پیش‌فرض: 10، حداقل: 1، حداکثر: 100)
	- **offset**: تعداد رکورد صرف‌نظر شده (پیش‌فرض: 0، حداقل: 0)
	
	### نکات:
	- این endpoint برای دریافت لیست ساده کاربران بدون فیلتر پیشرفته است
	- برای جستجو و فیلتر پیشرفته از `POST /users/search` استفاده کنید
	- نیاز به مجوز `user_management` در سطح اپلیکیشن دارد
	- Rate Limit: 500 request در دقیقه (عمومی برای تمام endpoint ها)
	- حداکثر تعداد رکورد در هر صفحه: 100 (پارامتر `limit`)
	
	### مثال cURL:
	```bash
	curl -X GET "http://localhost:8000/api/v1/users?limit=20&offset=0" \\
		 -H "Authorization: Bearer sk_your_api_key"
	```
	""",
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
								"created_at": "2024-01-01T00:00:00Z",
								"updated_at": "2024-01-01T00:00:00Z"
							}
						]
					}
				}
			}
		},
		401: {
			"description": "کاربر احراز هویت نشده است",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "Unauthorized",
						"error_code": "UNAUTHORIZED"
					}
				}
			}
		},
		403: {
			"description": "دسترسی غیرمجاز - نیاز به مجوز user_management",
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
		422: {
			"description": "خطا در اعتبارسنجی query parameters",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "limit must be between 1 and 100",
						"error_code": "VALIDATION_ERROR"
					}
				}
			}
		},
		429: {
			"description": "تعداد درخواست‌ها بیش از حد مجاز",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "تعداد درخواست‌های شما بیش از حد مجاز است. لطفاً کمی صبر کنید.",
						"error_code": "RATE_LIMIT_EXCEEDED"
					}
				}
			},
			"headers": {
				"X-RateLimit-Limit": {"description": "حد مجاز درخواست", "schema": {"type": "integer", "example": 500}},
				"X-RateLimit-Remaining": {"description": "تعداد درخواست‌های باقیمانده", "schema": {"type": "integer", "example": 0}},
				"X-RateLimit-Reset": {"description": "زمان reset به ثانیه (Unix timestamp)", "schema": {"type": "integer", "example": 1705324800}},
				"Retry-After": {"description": "زمان باقیمانده تا retry به ثانیه", "schema": {"type": "integer", "example": 30}}
			}
		}
	}
)
@require_user_management()
def list_users_simple(
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	limit: int = Query(10, ge=1, le=100, description="تعداد رکورد در هر صفحه (حداقل: 1، حداکثر: 100)"),
	offset: int = Query(0, ge=0, description="تعداد رکورد صرف‌نظر شده (حداقل: 0)")
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
	description="""
	آپلود تصویر امضای کاربر و ذخیره آن در سیستم فایل.
	
	### محدودیت‌های فایل:
	- **فرمت‌های مجاز**: JPG, JPEG, PNG, GIF, WebP, BMP
	- **MIME Types**: image/jpeg, image/png, image/gif, image/webp, image/bmp
	- **حداکثر حجم**: بر اساس تنظیمات سیستم (پیش‌فرض: 10 مگابایت)
	- **ابعاد تصویر**: محدودیت خاصی ندارد (توصیه می‌شود برای بهینه‌سازی حداکثر 2000x2000 پیکسل)
	- **نسبت تصویر**: محدودیت خاصی ندارد
	- **انقضا**: فایل به مدت 10 سال (3650 روز) نگهداری می‌شود
	
	### مثال cURL:
	```bash
	curl -X POST "http://localhost:8000/api/v1/users/me/signature" \\
		 -H "Authorization: Bearer sk_your_api_key" \\
		 -F "file=@signature.png"
	```
	""",
	response_model=SuccessResponse,
	responses={
		200: {
			"description": "امضا با موفقیت آپلود شد",
			"content": {
				"application/json": {
					"example": {
						"success": True,
						"message": "امضا با موفقیت آپلود شد",
						"data": {
							"signature_file_id": "550e8400-e29b-41d4-a716-446655440000",
							"file": {
								"file_id": "550e8400-e29b-41d4-a716-446655440000",
								"filename": "signature.png",
								"mime_type": "image/png",
								"file_size": 245678,
								"uploaded_at": "2024-01-15T10:30:00Z"
							}
						}
					}
				}
			}
		},
		400: {
			"description": "خطا در آپلود فایل",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "فرمت فایل معتبر نیست. فقط فرمت‌های JPG, PNG, GIF, WebP و BMP پشتیبانی می‌شوند",
						"error_code": "INVALID_FILE_FORMAT"
					}
				}
			}
		},
		401: {
			"description": "کاربر احراز هویت نشده است"
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
		},
		413: {
			"description": "حجم فایل بیش از حد مجاز",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "حجم فایل از حداکثر مجاز (10 مگابایت) تجاوز می‌کند",
						"error_code": "FILE_SIZE_EXCEEDED",
						"file_size_mb": 15.5,
						"max_file_size_mb": 10
					}
				}
			}
		},
		429: {
			"description": "تعداد درخواست‌ها بیش از حد مجاز",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "تعداد درخواست‌های شما بیش از حد مجاز است. لطفاً کمی صبر کنید.",
						"error_code": "RATE_LIMIT_EXCEEDED"
					}
				}
			},
			"headers": {
				"X-RateLimit-Limit": {"description": "حد مجاز درخواست", "schema": {"type": "integer", "example": 500}},
				"X-RateLimit-Remaining": {"description": "تعداد درخواست‌های باقیمانده", "schema": {"type": "integer", "example": 0}},
				"X-RateLimit-Reset": {"description": "زمان reset به ثانیه (Unix timestamp)", "schema": {"type": "integer", "example": 1705324800}},
				"Retry-After": {"description": "زمان باقیمانده تا retry به ثانیه", "schema": {"type": "integer", "example": 30}}
			}
		}
	}
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
	description="""
	بازگرداندن تصویر امضای کاربر کنونی به‌صورت فایل (برای نمایش در پروفایل یا فاکتور).
	
	### مثال cURL:
	```bash
	curl -X GET "http://localhost:8000/api/v1/users/me/signature" \\
		 -H "Authorization: Bearer sk_your_api_key" \\
		 --output signature.png
	```
	
	### Response:
	- Content-Type: image/png (یا فرمت فایل آپلود شده)
	- Content-Disposition: inline; filename="signature.png"
	""",
	responses={
		200: {
			"description": "فایل امضا با موفقیت دریافت شد",
			"content": {
				"image/png": {
					"schema": {
						"type": "string",
						"format": "binary"
					}
				},
				"image/jpeg": {
					"schema": {
						"type": "string",
						"format": "binary"
					}
				}
			}
		},
		401: {
			"description": "کاربر احراز هویت نشده است"
		},
		404: {
			"description": "امضایی برای این کاربر ثبت نشده است",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "امضایی برای این کاربر ثبت نشده است",
						"error_code": "SIGNATURE_NOT_SET"
					}
				}
			}
		},
		429: {
			"description": "تعداد درخواست‌ها بیش از حد مجاز",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "تعداد درخواست‌های شما بیش از حد مجاز است. لطفاً کمی صبر کنید.",
						"error_code": "RATE_LIMIT_EXCEEDED"
					}
				}
			},
			"headers": {
				"X-RateLimit-Limit": {"description": "حد مجاز درخواست", "schema": {"type": "integer", "example": 500}},
				"X-RateLimit-Remaining": {"description": "تعداد درخواست‌های باقیمانده", "schema": {"type": "integer", "example": 0}},
				"X-RateLimit-Reset": {"description": "زمان reset به ثانیه (Unix timestamp)", "schema": {"type": "integer", "example": 1705324800}},
				"Retry-After": {"description": "زمان باقیمانده تا retry به ثانیه", "schema": {"type": "integer", "example": 30}}
			}
		}
	}
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
	description="""
	دریافت اطلاعات کامل یک کاربر بر اساس شناسه شامل:
	- اطلاعات پایه کاربر (ایمیل، موبایل، نام و ...)
	- لیست کسب‌وکارهای کاربر (مالک یا عضو)
	- نشست‌های فعال کاربر
	- آخرین فعالیت‌های کاربر (حداکثر 50 مورد)
	
	### نکات:
	- نیاز به مجوز `user_management` در سطح اپلیکیشن دارد
	- Rate Limit: 500 request در دقیقه (عمومی برای تمام endpoint ها)
	
	### مثال cURL:
	```bash
	curl -X GET "http://localhost:8000/api/v1/users/123" \\
		 -H "Authorization: Bearer sk_your_api_key"
	```
	""",
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
							"app_permissions": {"user_management": True},
							"created_at": "2024-01-01T00:00:00Z",
							"updated_at": "2024-01-01T00:00:00Z",
							"signature_file_id": "550e8400-e29b-41d4-a716-446655440000",
							"businesses": [
								{
									"id": 1,
									"name": "شرکت نمونه",
									"field": "بازرگانی",
									"role": "owner",
									"status": "active",
									"created_at": "2024-01-01T00:00:00Z"
								},
								{
									"id": 2,
									"name": "فروشگاه نمونه",
									"field": "خدماتی",
									"role": "admin",
									"status": "active",
									"created_at": "2024-01-05T00:00:00Z"
								}
							],
							"sessions": [
								{
									"id": 1,
									"device": "Chrome on Windows",
									"ip": "192.168.1.1",
									"last_active_at": "2024-01-15T10:30:00Z",
									"created_at": "2024-01-01T00:00:00Z"
								},
								{
									"id": 2,
									"device": "Firefox on Linux",
									"ip": "192.168.1.2",
									"last_active_at": "2024-01-14T15:20:00Z",
									"created_at": "2024-01-10T00:00:00Z"
								}
							],
							"audit_logs": [
								{
									"id": 1,
									"action": "login",
									"description": "ورود به سیستم",
									"category": "authentication",
									"entity_type": "user",
									"entity_id": 1,
									"created_at": "2024-01-15T10:30:00Z"
								},
								{
									"id": 2,
									"action": "update_profile",
									"description": "به‌روزرسانی پروفایل",
									"category": "profile",
									"entity_type": "user",
									"entity_id": 1,
									"created_at": "2024-01-14T09:15:00Z"
								}
							]
						}
					}
				}
			}
		},
		401: {
			"description": "کاربر احراز هویت نشده است",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "Unauthorized",
						"error_code": "UNAUTHORIZED"
					}
				}
			}
		},
		403: {
			"description": "دسترسی غیرمجاز - نیاز به مجوز user_management",
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
		},
		429: {
			"description": "تعداد درخواست‌ها بیش از حد مجاز",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "تعداد درخواست‌های شما بیش از حد مجاز است. لطفاً کمی صبر کنید.",
						"error_code": "RATE_LIMIT_EXCEEDED"
					}
				}
			},
			"headers": {
				"X-RateLimit-Limit": {"description": "حد مجاز درخواست", "schema": {"type": "integer", "example": 500}},
				"X-RateLimit-Remaining": {"description": "تعداد درخواست‌های باقیمانده", "schema": {"type": "integer", "example": 0}},
				"X-RateLimit-Reset": {"description": "زمان reset به ثانیه (Unix timestamp)", "schema": {"type": "integer", "example": 1705324800}},
				"Retry-After": {"description": "زمان باقیمانده تا retry به ثانیه", "schema": {"type": "integer", "example": 30}}
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
	
	# دریافت کسب‌وکارهای کاربر (هم مالک و هم عضو)
	# استفاده از متد get_user_businesses که قبلاً تست شده و در business_service موجود است
	from app.services.business_service import get_user_businesses
	query_info = {"skip": 0, "take": 1000}  # دریافت همه کسب‌وکارها بدون محدودیت
	businesses_result = get_user_businesses(db, user_id, query_info)
	
	# تبدیل فرمت کسب‌وکارها به فرمت مورد نیاز برای نمایش در مدیریت کاربران
	businesses = []
	for business_item in businesses_result.get("items", []):
		# تبدیل نقش از فارسی به انگلیسی برای سازگاری با UI
		role = business_item.get("role", "user")
		if role == "مالک":
			role = "owner"
		elif role == "عضو":
			# بررسی permissions برای تعیین نقش دقیق‌تر
			permissions = business_item.get("permissions", {})
			if isinstance(permissions, dict):
				if permissions.get("admin"):
					role = "admin"
				elif permissions.get("operator"):
					role = "operator"
				elif permissions.get("supervisor"):
					role = "supervisor"
				else:
					role = "user"
			else:
				role = "user"
		
		businesses.append({
			"id": business_item.get("id"),
			"name": business_item.get("name"),
			"field": business_item.get("business_field"),
			"role": role,
			"status": "active",
			"created_at": business_item.get("created_at"),
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
	
	# دریافت آخرین فعالیت‌های کاربر
	from adapters.db.repositories.activity_log_repo import ActivityLogRepository
	activity_repo = ActivityLogRepository(db)
	activity_logs_list = activity_repo.get_by_user(user_id, limit=50, offset=0)
	
	audit_logs = []
	for log in activity_logs_list:
		audit_logs.append({
			"id": log.id,
			"action": log.action,
			"description": log.description,
			"category": log.category,
			"entity_type": log.entity_type,
			"entity_id": log.entity_id,
			"created_at": log.created_at,
		})
	
	user_dict["audit_logs"] = audit_logs
	
	formatted_user = format_datetime_fields(user_dict, request)
	
	return success_response(formatted_user, request)


@router.get("/stats/summary", 
	summary="آمار کلی کاربران", 
	description="""
	دریافت آمار کلی کاربران شامل تعداد کل، فعال و غیرفعال.
	
	### اطلاعات بازگشتی:
	- **total_users**: تعداد کل کاربران
	- **active_users**: تعداد کاربران فعال
	- **inactive_users**: تعداد کاربران غیرفعال
	- **active_percentage**: درصد کاربران فعال (با 2 رقم اعشار)
	
	### نکات:
	- نیاز به سوپرادمین یا مجوز `system_settings` یا `user_management` (همان باز کردن پنل مدیریت کاربران در UI)
	
	### مثال cURL:
	```bash
	curl -X GET "http://localhost:8000/api/v1/users/stats/summary" \\
		 -H "Authorization: Bearer sk_your_api_key"
	```
	""",
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
			"description": "کاربر احراز هویت نشده است",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "Unauthorized",
						"error_code": "UNAUTHORIZED"
					}
				}
			}
		},
		403: {
			"description": "دسترسی غیرمجاز - نیاز به مجوز user_management",
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
		429: {
			"description": "تعداد درخواست‌ها بیش از حد مجاز",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "تعداد درخواست‌های شما بیش از حد مجاز است. لطفاً کمی صبر کنید.",
						"error_code": "RATE_LIMIT_EXCEEDED"
					}
				}
			},
			"headers": {
				"X-RateLimit-Limit": {"description": "حد مجاز درخواست", "schema": {"type": "integer", "example": 500}},
				"X-RateLimit-Remaining": {"description": "تعداد درخواست‌های باقیمانده", "schema": {"type": "integer", "example": 0}},
				"X-RateLimit-Reset": {"description": "زمان reset به ثانیه (Unix timestamp)", "schema": {"type": "integer", "example": 1705324800}},
				"Retry-After": {"description": "زمان باقیمانده تا retry به ثانیه", "schema": {"type": "integer", "example": 30}}
			}
		}
	}
)
def get_users_summary(
	request: Request,
	_: AuthContext = Depends(verify_user_management_page_access),
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


@router.get(
	"/stats/online",
	summary="تعداد کاربران با فعالیت اخیر (آنلاین تقریبی)",
	description="""
بر اساس فیلد `last_activity_at` (ضربان اپ کلاینت) تعداد کاربران **فعال** را می‌دهد که
در بازهٔ اخیر (پیش‌فرض ۵ دقیقه، قابل تنظیم) فعالیت ثبت کرده باشند.

تعریف «آنلاین»: کاربری که اخیراً ضربان HTTP زده؛ نه همان واقع‌زمان WebSocket مطلق.
مجوز مانند باز کردن همین صفحه در UI: سوپرادمین، `system_settings` یا `user_management`.
""",
	response_model=SuccessResponse,
)
def get_users_online_stats(
	request: Request,
	window_minutes: int = Query(5, ge=1, le=120, description="بازه زمانی برای شمار کاربر «اخیراً فعال»"),
	_: AuthContext = Depends(verify_user_management_page_access),
	db: Session = Depends(get_db),
):
	repo = UserRepository(db)
	online_approx = repo.count_recently_active_users(within_minutes=window_minutes)
	return success_response(
		{
			"recently_active_count": online_approx,
			"window_minutes": window_minutes,
			"note": "تعداد کاربران فعال با فعالیت ثبت‌شده در بازهٔ اخیر (ضربان اپ؛ تقریبی).",
		},
		request,
	)


@router.get(
	"/stats/signups-timeline",
	summary="گزارش عضویت کاربران در بازهٔ تاریخی",
	description="""
تعداد کاربران ثبت‌شده به‌ازای هر روز / هفته / ماه در بازهٔ مشخص (تاریخ‌ها به‌صورت UTC نیمه‌شب).

مجوز مانند `GET /users/stats/online`: سوپرادمین، `system_settings` یا `user_management`.
""",
	response_model=SuccessResponse,
)
def get_users_signups_timeline(
	request: Request,
	start_date: date = Query(..., description="شروع بازه (شمولی)، YYYY-MM-DD"),
	end_date: date = Query(..., description="پایان بازه (شمولی)، YYYY-MM-DD"),
	granularity: Literal["day", "week", "month"] = Query("day", description="تجمیع روزانه، هفتگی یا ماهانه"),
	_: AuthContext = Depends(verify_user_management_page_access),
	db: Session = Depends(get_db),
):
	if end_date < start_date:
		raise ApiError("VALIDATION_ERROR", "تاریخ پایان نمی‌تواند قبل از تاریخ شروع باشد", http_status=422)
	start_utc = datetime.combine(start_date, time.min)
	end_exclusive = datetime.combine(end_date + timedelta(days=1), time.min)
	span_days = (end_exclusive - start_utc).days
	if span_days <= 0:
		raise ApiError("VALIDATION_ERROR", "بازهٔ تاریخ نامعتبر است", http_status=422)
	if granularity == "day" and span_days > 400:
		raise ApiError("VALIDATION_ERROR", "برای تجمیع روزانه حداکثر ۴۰۰ روز مجاز است", http_status=422)
	if granularity == "week" and span_days > 800:
		raise ApiError("VALIDATION_ERROR", "برای تجمیع هفتگی حداکثر ۸۰۰ روز مجاز است", http_status=422)
	if granularity == "month" and span_days > 3660:
		raise ApiError("VALIDATION_ERROR", "برای تجمیع ماهانه حداکثر ۱۰ سال مجاز است", http_status=422)

	repo = UserRepository(db)
	rows = repo.get_signups_timeline_buckets(start_utc, end_exclusive, granularity)
	buckets = [{"period_start": dt, "count": cnt} for dt, cnt in rows]
	payload = {
		"granularity": granularity,
		"start_date": start_date.isoformat(),
		"end_date": end_date.isoformat(),
		"buckets": buckets,
		"total_in_range": sum(b["count"] for b in buckets),
	}
	return success_response(format_datetime_fields(payload, request), request)


@router.post("/bulk-activate",
	summary="فعال‌سازی دسته‌ای کاربران",
	description="""
	فعال‌سازی چندین کاربر به صورت همزمان.
	
	### نکات:
	- فقط کاربران غیرفعال فعال می‌شوند
	- کاربران فعال قبلاً نادیده گرفته می‌شوند
	- نیاز به مجوز `user_management` در سطح اپلیکیشن دارد
	- Rate Limit: 500 request در دقیقه (عمومی برای تمام endpoint ها)
	- محدودیت تعداد: توصیه می‌شود حداکثر 100 کاربر در هر درخواست (بدون محدودیت سخت)
	
	### مثال cURL:
	```bash
	curl -X POST "http://localhost:8000/api/v1/users/bulk-activate" \\
		 -H "Authorization: Bearer sk_your_api_key" \\
		 -H "Content-Type: application/json" \\
		 -d '{"user_ids": [1, 2, 3, 4, 5]}'
	```
	""",
	response_model=SuccessResponse,
	responses={
		200: {
			"description": "عملیات با موفقیت انجام شد",
			"content": {
				"application/json": {
					"example": {
						"success": True,
						"message": "عملیات با موفقیت انجام شد",
						"data": {
							"updated_count": 3,
							"total_requested": 5
						}
					}
				}
			}
		},
		401: {
			"description": "کاربر احراز هویت نشده است"
		},
		403: {
			"description": "دسترسی غیرمجاز - نیاز به مجوز user_management"
		},
		422: {
			"description": "خطا در اعتبارسنجی داده‌ها",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "user_ids باید لیستی از اعداد باشد و حداقل 1 آیتم داشته باشد",
						"error_code": "VALIDATION_ERROR"
					}
				}
			}
		},
		429: {
			"description": "تعداد درخواست‌ها بیش از حد مجاز",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "تعداد درخواست‌های شما بیش از حد مجاز است. لطفاً کمی صبر کنید.",
						"error_code": "RATE_LIMIT_EXCEEDED"
					}
				}
			},
			"headers": {
				"X-RateLimit-Limit": {"description": "حد مجاز درخواست", "schema": {"type": "integer", "example": 500}},
				"X-RateLimit-Remaining": {"description": "تعداد درخواست‌های باقیمانده", "schema": {"type": "integer", "example": 0}},
				"X-RateLimit-Reset": {"description": "زمان reset به ثانیه (Unix timestamp)", "schema": {"type": "integer", "example": 1705324800}},
				"Retry-After": {"description": "زمان باقیمانده تا retry به ثانیه", "schema": {"type": "integer", "example": 30}}
			}
		}
	}
)
@require_user_management()
def bulk_activate_users(
	request: Request,
	payload: BulkActivateRequest = Body(..., description="لیست شناسه‌های کاربران برای فعال‌سازی"),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
	"""فعال‌سازی دسته‌ای کاربران"""
	repo = UserRepository(db)
	updated_count = 0
	
	for user_id in payload.user_ids:
		user = repo.get_by_id(user_id)
		if user and not user.is_active:
			user.is_active = True
			updated_count += 1
	
	db.commit()
	
	return success_response({
		"updated_count": updated_count,
		"total_requested": len(payload.user_ids)
	}, request)


@router.post("/bulk-suspend",
	summary="تعلیق دسته‌ای کاربران",
	description="""
	تعلیق چندین کاربر به صورت همزمان.
	
	### نکات:
	- فقط کاربران فعال تعلیق می‌شوند
	- کاربران غیرفعال قبلاً نادیده گرفته می‌شوند
	- نمی‌توانید خود را تعلیق کنید (نادیده گرفته می‌شود)
	- نیاز به مجوز `user_management` در سطح اپلیکیشن دارد
	- Rate Limit: 500 request در دقیقه (عمومی برای تمام endpoint ها)
	- محدودیت تعداد: توصیه می‌شود حداکثر 100 کاربر در هر درخواست (بدون محدودیت سخت)
	
	### مثال cURL:
	```bash
	curl -X POST "http://localhost:8000/api/v1/users/bulk-suspend" \\
		 -H "Authorization: Bearer sk_your_api_key" \\
		 -H "Content-Type: application/json" \\
		 -d '{"user_ids": [1, 2, 3, 4, 5]}'
	```
	""",
	response_model=SuccessResponse,
	responses={
		200: {
			"description": "عملیات با موفقیت انجام شد",
			"content": {
				"application/json": {
					"example": {
						"success": True,
						"message": "عملیات با موفقیت انجام شد",
						"data": {
							"updated_count": 3,
							"total_requested": 5
						}
					}
				}
			}
		},
		401: {
			"description": "کاربر احراز هویت نشده است"
		},
		403: {
			"description": "دسترسی غیرمجاز - نیاز به مجوز user_management"
		},
		422: {
			"description": "خطا در اعتبارسنجی داده‌ها",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "user_ids باید لیستی از اعداد باشد و حداقل 1 آیتم داشته باشد",
						"error_code": "VALIDATION_ERROR"
					}
				}
			}
		},
		429: {
			"description": "تعداد درخواست‌ها بیش از حد مجاز",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "تعداد درخواست‌های شما بیش از حد مجاز است. لطفاً کمی صبر کنید.",
						"error_code": "RATE_LIMIT_EXCEEDED"
					}
				}
			},
			"headers": {
				"X-RateLimit-Limit": {"description": "حد مجاز درخواست", "schema": {"type": "integer", "example": 500}},
				"X-RateLimit-Remaining": {"description": "تعداد درخواست‌های باقیمانده", "schema": {"type": "integer", "example": 0}},
				"X-RateLimit-Reset": {"description": "زمان reset به ثانیه (Unix timestamp)", "schema": {"type": "integer", "example": 1705324800}},
				"Retry-After": {"description": "زمان باقیمانده تا retry به ثانیه", "schema": {"type": "integer", "example": 30}}
			}
		}
	}
)
@require_user_management()
def bulk_suspend_users(
	request: Request,
	payload: BulkSuspendRequest = Body(..., description="لیست شناسه‌های کاربران برای تعلیق"),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
	"""تعلیق دسته‌ای کاربران"""
	repo = UserRepository(db)
	updated_count = 0
	
	for user_id in payload.user_ids:
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
		"total_requested": len(payload.user_ids)
	}, request)


@router.post("/bulk-reset-password",
	summary="بازنشانی رمز عبور دسته‌ای کاربران",
	description="""
	ایجاد توکن بازنشانی رمز عبور برای چندین کاربر.
	
	### نکات:
	- برای هر کاربر یک توکن منحصر به فرد ایجاد می‌شود
	- فقط برای کاربرانی که ایمیل یا موبایل دارند توکن ایجاد می‌شود
	- توکن‌ها به صورت خودکار منقضی می‌شوند (بر اساس تنظیمات سیستم)
	- نیاز به مجوز `user_management` در سطح اپلیکیشن دارد
	- Rate Limit: 500 request در دقیقه (عمومی برای تمام endpoint ها)
	- محدودیت تعداد: توصیه می‌شود حداکثر 100 کاربر در هر درخواست (بدون محدودیت سخت)
	
	### مثال cURL:
	```bash
	curl -X POST "http://localhost:8000/api/v1/users/bulk-reset-password" \\
		 -H "Authorization: Bearer sk_your_api_key" \\
		 -H "Content-Type: application/json" \\
		 -d '{"user_ids": [1, 2, 3, 4, 5]}'
	```
	""",
	response_model=SuccessResponse,
	responses={
		200: {
			"description": "توکن‌ها با موفقیت ایجاد شدند",
			"content": {
				"application/json": {
					"example": {
						"success": True,
						"message": "توکن‌ها با موفقیت ایجاد شدند",
						"data": {
							"tokens_created": 4,
							"total_requested": 5
						}
					}
				}
			}
		},
		401: {
			"description": "کاربر احراز هویت نشده است"
		},
		403: {
			"description": "دسترسی غیرمجاز - نیاز به مجوز user_management"
		},
		422: {
			"description": "خطا در اعتبارسنجی داده‌ها",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "user_ids باید لیستی از اعداد باشد و حداقل 1 آیتم داشته باشد",
						"error_code": "VALIDATION_ERROR"
					}
				}
			}
		},
		429: {
			"description": "تعداد درخواست‌ها بیش از حد مجاز",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "تعداد درخواست‌های شما بیش از حد مجاز است. لطفاً کمی صبر کنید.",
						"error_code": "RATE_LIMIT_EXCEEDED"
					}
				}
			},
			"headers": {
				"X-RateLimit-Limit": {"description": "حد مجاز درخواست", "schema": {"type": "integer", "example": 500}},
				"X-RateLimit-Remaining": {"description": "تعداد درخواست‌های باقیمانده", "schema": {"type": "integer", "example": 0}},
				"X-RateLimit-Reset": {"description": "زمان reset به ثانیه (Unix timestamp)", "schema": {"type": "integer", "example": 1705324800}},
				"Retry-After": {"description": "زمان باقیمانده تا retry به ثانیه", "schema": {"type": "integer", "example": 30}}
			}
		}
	}
)
@require_user_management()
def bulk_reset_password(
	request: Request,
	payload: BulkResetPasswordRequest = Body(..., description="لیست شناسه‌های کاربران برای بازنشانی رمز عبور"),
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
	
	for user_id in payload.user_ids:
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
					if payload.send_notification:
						rlink = build_password_reset_web_url(request=request, token=token)
						send_password_reset_notification(
							db=db, user_id=user.id, token=token, reset_link=rlink
						)
				except Exception:
					pass  # در صورت خطا ادامه می‌دهیم
	
	db.commit()
	
	return success_response({
		"tokens_created": tokens_created,
		"total_requested": len(payload.user_ids)
	}, request)


@router.post("/{user_id}/suspend",
	summary="تعلیق یک کاربر",
	description="""
	تعلیق یک کاربر خاص.
	
	### نکات:
	- نمی‌توانید خود را تعلیق کنید
	- نیاز به مجوز `user_management` در سطح اپلیکیشن دارد
	- Rate Limit: 500 request در دقیقه (عمومی برای تمام endpoint ها)
	
	### مثال cURL:
	```bash
	curl -X POST "http://localhost:8000/api/v1/users/123/suspend" \\
		 -H "Authorization: Bearer sk_your_api_key"
	```
	""",
	response_model=SuccessResponse,
	responses={
		200: {
			"description": "کاربر با موفقیت تعلیق شد",
			"content": {
				"application/json": {
					"example": {
						"success": True,
						"message": "کاربر با موفقیت تعلیق شد",
						"data": {
							"message": "کاربر با موفقیت تعلیق شد"
						}
					}
				}
			}
		},
		400: {
			"description": "نمی‌توانید خود را تعلیق کنید",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "نمی‌توانید خود را تعلیق کنید",
						"error_code": "CANNOT_SUSPEND_SELF"
					}
				}
			}
		},
		401: {
			"description": "کاربر احراز هویت نشده است"
		},
		403: {
			"description": "دسترسی غیرمجاز - نیاز به مجوز user_management"
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
		},
		429: {
			"description": "تعداد درخواست‌ها بیش از حد مجاز",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "تعداد درخواست‌های شما بیش از حد مجاز است. لطفاً کمی صبر کنید.",
						"error_code": "RATE_LIMIT_EXCEEDED"
					}
				}
			},
			"headers": {
				"X-RateLimit-Limit": {"description": "حد مجاز درخواست", "schema": {"type": "integer", "example": 500}},
				"X-RateLimit-Remaining": {"description": "تعداد درخواست‌های باقیمانده", "schema": {"type": "integer", "example": 0}},
				"X-RateLimit-Reset": {"description": "زمان reset به ثانیه (Unix timestamp)", "schema": {"type": "integer", "example": 1705324800}},
				"Retry-After": {"description": "زمان باقیمانده تا retry به ثانیه", "schema": {"type": "integer", "example": 30}}
			}
		}
	}
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
	description="""
	فعال‌سازی یک کاربر خاص.
	
	### نکات:
	- نیاز به مجوز `user_management` در سطح اپلیکیشن دارد
	- Rate Limit: 500 request در دقیقه (عمومی برای تمام endpoint ها)
	
	### مثال cURL:
	```bash
	curl -X POST "http://localhost:8000/api/v1/users/123/activate" \\
		 -H "Authorization: Bearer sk_your_api_key"
	```
	""",
	response_model=SuccessResponse,
	responses={
		200: {
			"description": "کاربر با موفقیت فعال شد",
			"content": {
				"application/json": {
					"example": {
						"success": True,
						"message": "کاربر با موفقیت فعال شد",
						"data": {
							"message": "کاربر با موفقیت فعال شد"
						}
					}
				}
			}
		},
		401: {
			"description": "کاربر احراز هویت نشده است"
		},
		403: {
			"description": "دسترسی غیرمجاز - نیاز به مجوز user_management"
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
		},
		429: {
			"description": "تعداد درخواست‌ها بیش از حد مجاز",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "تعداد درخواست‌های شما بیش از حد مجاز است. لطفاً کمی صبر کنید.",
						"error_code": "RATE_LIMIT_EXCEEDED"
					}
				}
			},
			"headers": {
				"X-RateLimit-Limit": {"description": "حد مجاز درخواست", "schema": {"type": "integer", "example": 500}},
				"X-RateLimit-Remaining": {"description": "تعداد درخواست‌های باقیمانده", "schema": {"type": "integer", "example": 0}},
				"X-RateLimit-Reset": {"description": "زمان reset به ثانیه (Unix timestamp)", "schema": {"type": "integer", "example": 1705324800}},
				"Retry-After": {"description": "زمان باقیمانده تا retry به ثانیه", "schema": {"type": "integer", "example": 30}}
			}
		}
	}
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
	description="""
	ایجاد توکن بازنشانی رمز عبور برای یک کاربر.
	
	### نکات:
	- توکن به صورت خودکار منقضی می‌شود (بر اساس تنظیمات سیستم)
	- کاربر باید ایمیل یا موبایل داشته باشد
	- اگر `send_notification=true` باشد (پیش‌فرض)، اعلان `auth.password_reset` برای کاربر ارسال می‌شود
	- فیلد `token` فقط وقتی در پاسخ می‌آید که `app.debug` در تنظیمات API روشن باشد
	- نیاز به مجوز `user_management` در سطح اپلیکیشن دارد
	- Rate Limit: 500 request در دقیقه (عمومی برای تمام endpoint ها)
	
	### مثال cURL:
	```bash
	curl -X POST "http://localhost:8000/api/v1/users/123/reset-password?send_notification=true" \\
		 -H "Authorization: Bearer sk_your_api_key"
	```
	""",
	response_model=SuccessResponse,
	responses={
		200: {
			"description": "توکن بازنشانی رمز عبور ایجاد شد",
			"content": {
				"application/json": {
					"example": {
						"success": True,
						"message": "توکن بازنشانی رمز عبور ایجاد شد",
						"data": {
							"message": "توکن بازنشانی رمز عبور ایجاد شد",
							"token": "reset_token_1234567890abcdef"
						}
					}
				}
			}
		},
		400: {
			"description": "کاربر ایمیل یا موبایل ندارد",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "کاربر ایمیل یا موبایل ندارد",
						"error_code": "NO_IDENTIFIER"
					}
				}
			}
		},
		401: {
			"description": "کاربر احراز هویت نشده است"
		},
		403: {
			"description": "دسترسی غیرمجاز - نیاز به مجوز user_management"
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
		},
		429: {
			"description": "تعداد درخواست‌ها بیش از حد مجاز",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "تعداد درخواست‌های شما بیش از حد مجاز است. لطفاً کمی صبر کنید.",
						"error_code": "RATE_LIMIT_EXCEEDED"
					}
				}
			},
			"headers": {
				"X-RateLimit-Limit": {"description": "حد مجاز درخواست", "schema": {"type": "integer", "example": 500}},
				"X-RateLimit-Remaining": {"description": "تعداد درخواست‌های باقیمانده", "schema": {"type": "integer", "example": 0}},
				"X-RateLimit-Reset": {"description": "زمان reset به ثانیه (Unix timestamp)", "schema": {"type": "integer", "example": 1705324800}},
				"Retry-After": {"description": "زمان باقیمانده تا retry به ثانیه", "schema": {"type": "integer", "example": 30}}
			}
		}
	}
)
@require_user_management()
def reset_user_password(
	user_id: int,
	request: Request,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	send_notification: bool = Query(
		default=True,
		description="ارسال اعلان بازیابی رمز (همان الگوی فراموشی رمز)",
	),
):
	"""بازنشانی رمز عبور یک کاربر (توکن + اختیار اعلان)"""
	from adapters.db.repositories.password_reset_repo import PasswordResetRepository
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
	reset_link = build_password_reset_web_url(request=request, token=token)
	if send_notification:
		send_password_reset_notification(
			db=db, user_id=user.id, token=token, reset_link=reset_link
		)
	data: dict = {
		"message": "توکن بازنشانی رمز عبور ایجاد شد",
		"send_notification": send_notification,
		"reset_link": reset_link,
	}
	if settings.debug:
		data["token"] = token
	return success_response(data, request)


@router.post(
	"/{user_id}/set-password",
	summary="تنظیم رمز توسط مدیر (انتخابی یا تصادفی)",
	description="""
	تنظیم مستقیم `password_hash` برای کاربر بدون توکن بازنشانی.

	- `mode=direct`: `new_password` و `confirm_password` (۸ تا ۱۲۸ نویسه)
	- `mode=random`: رمز امن تولید می‌شود و **فقط یک‌بار** در `plain_password` برمی‌گردد

	نیاز به مجوز `user_management`.
	""",
	response_model=SuccessResponse,
)
@require_user_management()
def admin_set_user_password_endpoint(
	user_id: int,
	request: Request,
	payload: AdminSetUserPasswordRequest = Body(..., description="حالت و رمز"),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
):
	result = admin_set_user_password(
		db=db,
		target_user_id=user_id,
		mode=payload.mode,
		new_password=payload.new_password,
		confirm_password=payload.confirm_password,
	)
	out: dict = {
		"message": "رمز عبور به‌روزرسانی شد",
		"mode": payload.mode,
	}
	plain = result.get("plain_password")
	if plain:
		out["plain_password"] = plain
	return success_response(out, request)


