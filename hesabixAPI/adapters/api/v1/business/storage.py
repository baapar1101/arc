"""
API endpoints برای مدیریت ذخیره‌سازی کسب‌وکار
"""

from typing import Dict, Any, Optional
from datetime import datetime
from decimal import Decimal

from fastapi import APIRouter, Depends, Body, Query, Request, Response, UploadFile, File, Form, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from sqlalchemy import and_
from uuid import UUID

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.services.file_storage_service import FileStorageService
from app.services.file_dependency_service import FileDependencyService
from adapters.db.models.file_storage import FileStorage
from app.services.storage_subscription_service import (
	subscribe_to_plan,
	get_active_subscriptions,
	get_subscription,
	renew_subscription,
	cancel_subscription,
	get_storage_usage_info,
)
from app.services.storage_plan_service import list_storage_plans
from app.services.storage_invoice_service import (
	create_subscription_invoice,
	create_over_usage_invoice,
	pay_storage_invoice_from_wallet,
	get_storage_invoice,
	list_storage_invoices,
)
from app.services.storage_export_service import export_business_files_as_zip, get_export_info
from adapters.db.models.wallet import WalletAccount
from adapters.db.models.storage_plan import StoragePlan
import io


router = APIRouter(prefix="/business/{business_id}/storage", tags=["business-storage"])


@router.get(
	"/files/{file_id}/usage",
	summary="لیست وابستگی‌های فایل",
	description="نمایش موجودیت‌هایی که از این فایل استفاده می‌کنند",
)
async def get_file_usage_endpoint(
	business_id: int,
	file_id: str,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.can_access_business(business_id):
		raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)

	file_storage = db.query(FileStorage).filter(
		FileStorage.id == file_id,
		FileStorage.business_id == business_id,
		FileStorage.deleted_at.is_(None),
	).first()

	if not file_storage:
		raise ApiError("FILE_NOT_FOUND", "فایل یافت نشد", http_status=404)

	dependency_service = FileDependencyService(db)
	dependencies = dependency_service.get_dependencies(file_storage)

	return success_response({
		"file": {
			"id": str(file_storage.id),
			"name": file_storage.original_name,
			"module_context": file_storage.module_context,
			"context_id": file_storage.context_id,
		},
		"dependencies": [dep.to_dict() for dep in dependencies],
	}, request)


@router.get(
	"/subscriptions",
	summary="لیست اشتراک‌های فعال",
	description="دریافت تمام اشتراک‌های فعال کسب‌وکار",
)
def list_subscriptions_endpoint(
	business_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	# بررسی دسترسی به کسب‌وکار
	if not ctx.can_access_business(business_id):
		raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
	
	data = get_active_subscriptions(db, business_id)
	return success_response(data, request)


@router.post(
	"/subscribe",
	summary="اشتراک به یک پلن",
	description="اشتراک کسب‌وکار به یک پلن ذخیره‌سازی",
)
def subscribe_endpoint(
	business_id: int,
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	# بررسی دسترسی به کسب‌وکار
	if not ctx.can_access_business(business_id):
		raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
	
	plan_id = payload.get("plan_id")
	if not plan_id:
		raise ApiError("VALIDATION_ERROR", "plan_id الزامی است", http_status=422)
	
	auto_renew = bool(payload.get("auto_renew", False))
	user_id = ctx.get_user_id()

	# بررسی پلن برای دریافت قیمت و وضعیت
	plan = db.query(StoragePlan).filter(
		and_(StoragePlan.id == plan_id, StoragePlan.is_active == True)
	).first()
	if not plan:
		raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد یا غیرفعال است", http_status=404)

	plan_price = Decimal(str(plan.price or 0))
	if plan_price < 0:
		plan_price = Decimal("0")

	# بررسی موجودی کیف پول قبل از ایجاد اشتراک (برای پلن‌های پولی)
	if plan_price > 0 and not plan.is_free:
		account = (
			db.query(WalletAccount)
			.filter(WalletAccount.business_id == business_id)
			.with_for_update()
			.first()
		)
		available_balance = Decimal(str(account.available_balance or 0)) if account else Decimal("0")
		if available_balance < plan_price:
			raise ApiError(
				"INSUFFICIENT_WALLET_FUNDS",
				"موجودی کیف پول کافی نیست. لطفاً ابتدا کیف پول را شارژ کنید.",
				http_status=400,
			)
	
	# ایجاد اشتراک
	subscription = subscribe_to_plan(db, business_id, plan_id, auto_renew)
	
	# ایجاد صورتحساب
	invoice = create_subscription_invoice(db, business_id, subscription["id"], user_id)

	payment_result: Optional[Dict[str, Any]] = None

	# برای پلن‌های پولی، بلافاصله پرداخت را انجام می‌دهیم
	if plan_price > 0 and not plan.is_free:
		payment_result = pay_storage_invoice_from_wallet(db, business_id, invoice["id"], user_id)
		if payment_result.get("status") == "insufficient_funds":
			raise ApiError(
				"INSUFFICIENT_WALLET_FUNDS",
				"موجودی کیف پول کافی نیست. لطفاً ابتدا کیف پول را شارژ کنید.",
				http_status=400,
			)
	
	# تازه‌سازی داده‌های اشتراک و صورتحساب (وضعیت باید پس از پرداخت active/paid باشد)
	subscription = get_subscription(db, business_id, subscription["id"])
	invoice = get_storage_invoice(db, business_id, invoice["id"])

	response_data: Dict[str, Any] = {
		"subscription": subscription,
		"invoice": invoice,
	}
	if payment_result:
		response_data["payment"] = payment_result
	
	return success_response(
		response_data,
		request,
		"پلن با موفقیت خریداری و پرداخت شد." if plan_price > 0 and not plan.is_free else "اشتراک با موفقیت ایجاد شد.",
	)


@router.put(
	"/subscription/{subscription_id}/renew",
	summary="تمدید اشتراک",
	description="تمدید اشتراک موجود",
)
def renew_subscription_endpoint(
	business_id: int,
	subscription_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	# بررسی دسترسی به کسب‌وکار
	if not ctx.can_access_business(business_id):
		raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
	
	# ایجاد صورتحساب تمدید
	invoice = create_renewal_invoice(db, business_id, subscription_id)
	
	return success_response({
		"invoice": invoice,
	}, request, "صورتحساب تمدید ایجاد شد. لطفاً پرداخت کنید.")


@router.delete(
	"/subscription/{subscription_id}",
	summary="لغو اشتراک",
	description="لغو اشتراک موجود",
)
def cancel_subscription_endpoint(
	business_id: int,
	subscription_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	# بررسی دسترسی به کسب‌وکار
	if not ctx.can_access_business(business_id):
		raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
	
	data = cancel_subscription(db, business_id, subscription_id)
	return success_response(data, request, "اشتراک با موفقیت لغو شد")


@router.get(
	"/usage",
	summary="آمار استفاده",
	description="دریافت آمار استفاده از ذخیره‌سازی",
)
def get_usage_endpoint(
	business_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	# بررسی دسترسی به کسب‌وکار
	if not ctx.can_access_business(business_id):
		raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
	
	data = get_storage_usage_info(db, business_id)
	return success_response(data, request)


@router.get(
	"/plans",
	summary="لیست پلن‌های قابل اشتراک",
	description="دریافت لیست پلن‌های فعال برای اشتراک",
)
def list_plans_endpoint(
	business_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	# بررسی دسترسی به کسب‌وکار
	if not ctx.can_access_business(business_id):
		raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
	
	data = list_storage_plans(db, only_active=True)
	return success_response(data, request)


@router.get(
	"/invoices",
	summary="لیست صورتحساب‌ها",
	description="دریافت لیست صورتحساب‌های ذخیره‌سازی",
)
def list_invoices_endpoint(
	business_id: int,
	request: Request,
	limit: int = Query(50, ge=1, le=100),
	skip: int = Query(0, ge=0),
	status: Optional[str] = Query(None),
	invoice_type: Optional[str] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	# بررسی دسترسی به کسب‌وکار
	if not ctx.can_access_business(business_id):
		raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
	
	invoices = list_storage_invoices(db, business_id, limit=limit, skip=skip, status=status, invoice_type=invoice_type)
	return success_response({"items": invoices}, request)


@router.get(
	"/invoices/{invoice_id}",
	summary="جزئیات صورتحساب",
	description="دریافت جزئیات یک صورتحساب",
)
def get_invoice_endpoint(
	business_id: int,
	invoice_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	# بررسی دسترسی به کسب‌وکار
	if not ctx.can_access_business(business_id):
		raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
	
	data = get_storage_invoice(db, business_id, invoice_id)
	return success_response(data, request)


@router.post(
	"/invoices/{invoice_id}/pay",
	summary="پرداخت صورتحساب از کیف پول",
	description="پرداخت صورتحساب ذخیره‌سازی از کیف پول",
)
def pay_invoice_endpoint(
	business_id: int,
	invoice_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	import logging
	logger = logging.getLogger(__name__)
	logger.info(f"درخواست پرداخت صورتحساب {invoice_id} برای کسب‌وکار {business_id} از کاربر {ctx.get_user_id()}")
	
	# بررسی دسترسی به کسب‌وکار
	if not ctx.can_access_business(business_id):
		logger.warning(f"کاربر {ctx.get_user_id()} دسترسی به کسب‌وکار {business_id} ندارد")
		raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
	
	try:
		result = pay_storage_invoice_from_wallet(db, business_id, invoice_id, ctx.get_user_id())
		logger.info(f"نتیجه پرداخت صورتحساب {invoice_id}: {result}")
		
		if result.get("status") == "insufficient_funds":
			logger.warning(f"موجودی کیف پول کافی نیست برای صورتحساب {invoice_id}")
			return success_response(result, request, "موجودی کیف پول کافی نیست")
		
		logger.info(f"صورتحساب {invoice_id} با موفقیت پرداخت شد. document_id={result.get('document_id')}")
		return success_response(result, request, "صورتحساب با موفقیت پرداخت شد")
	except Exception as e:
		logger.error(f"خطا در پرداخت صورتحساب {invoice_id}: {type(e).__name__}: {e}", exc_info=True)
		raise


@router.post(
	"/pay-over-usage",
	summary="پرداخت برای استفاده اضافی",
	description="ایجاد و پرداخت صورتحساب برای استفاده اضافی از ذخیره‌سازی",
)
def pay_over_usage_endpoint(
	business_id: int,
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	# بررسی دسترسی به کسب‌وکار
	if not ctx.can_access_business(business_id):
		raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
	
	over_usage_gb = payload.get("over_usage_gb")
	file_size_bytes = payload.get("file_size_bytes")
	
	if not over_usage_gb or over_usage_gb <= 0:
		raise ApiError("VALIDATION_ERROR", "over_usage_gb باید بیشتر از صفر باشد", http_status=422)
	
	# ایجاد صورتحساب
	invoice = create_over_usage_invoice(db, business_id, over_usage_gb, file_size_bytes)
	
	# پرداخت از کیف پول
	result = pay_storage_invoice_from_wallet(db, business_id, invoice["id"], ctx.get_user_id())
	
	if result.get("status") == "insufficient_funds":
		return success_response({
			"invoice": invoice,
			"payment": result,
		}, request, "صورتحساب ایجاد شد اما موجودی کیف پول کافی نیست")
	
	return success_response({
		"invoice": invoice,
		"payment": result,
	}, request, "صورتحساب استفاده اضافی با موفقیت پرداخت شد")


@router.get(
	"/export-zip",
	summary="دانلود ZIP تمام فایل‌ها",
	description="دانلود تمام فایل‌های کسب‌وکار به صورت ZIP",
)
async def export_zip_endpoint(
	business_id: int,
	request: Request,
	module_context: Optional[str] = Query(None),
	from_date: Optional[str] = Query(None),
	to_date: Optional[str] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	# بررسی دسترسی به کسب‌وکار
	if not ctx.can_access_business(business_id):
		raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
	
	# تبدیل تاریخ‌ها
	from_dt = None
	to_dt = None
	if from_date:
		try:
			from_dt = datetime.fromisoformat(from_date.replace("Z", "+00:00"))
		except Exception:
			pass
	if to_date:
		try:
			to_dt = datetime.fromisoformat(to_date.replace("Z", "+00:00"))
		except Exception:
			pass
	
	# ایجاد ZIP
	zip_data = await export_business_files_as_zip(
		db, business_id, module_context=module_context, from_date=from_dt, to_date=to_dt
	)
	
	# بازگرداندن فایل
	return Response(
		content=zip_data,
		media_type="application/zip",
		headers={
			"Content-Disposition": f'attachment; filename="hesabix_files_{business_id}.zip"'
		}
	)


@router.get(
	"/export-info",
	summary="اطلاعات فایل‌های قابل دانلود",
	description="دریافت اطلاعات فایل‌های قابل دانلود (بدون دانلود)",
)
def get_export_info_endpoint(
	business_id: int,
	request: Request,
	module_context: Optional[str] = Query(None),
	from_date: Optional[str] = Query(None),
	to_date: Optional[str] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	# بررسی دسترسی به کسب‌وکار
	if not ctx.can_access_business(business_id):
		raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
	
	# تبدیل تاریخ‌ها
	from_dt = None
	to_dt = None
	if from_date:
		try:
			from_dt = datetime.fromisoformat(from_date.replace("Z", "+00:00"))
		except Exception:
			pass
	if to_date:
		try:
			to_dt = datetime.fromisoformat(to_date.replace("Z", "+00:00"))
		except Exception:
			pass
	
	data = get_export_info(db, business_id, module_context=module_context, from_date=from_dt, to_date=to_dt)
	return success_response(data, request)


@router.get(
	"/files",
	summary="لیست فایل‌های کسب‌وکار",
	description="دریافت لیست فایل‌های آپلود شده برای کسب‌وکار",
)
def list_files_endpoint(
	business_id: int,
	request: Request,
	module_context: Optional[str] = Query(None),
	page: int = Query(1, ge=1),
	limit: int = Query(50, ge=1, le=100),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	"""لیست فایل‌های کسب‌وکار"""
	try:
		# بررسی دسترسی به کسب‌وکار
		if not ctx.can_access_business(business_id):
			raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
		
		from sqlalchemy import and_
		
		# ساخت فیلترها
		filters = [
			FileStorage.business_id == business_id,
			FileStorage.deleted_at.is_(None),
		]
		
		if module_context:
			filters.append(FileStorage.module_context == module_context)
		
		# فیلتر بر اساس context_id (برای دریافت فایل‌های یک سند خاص)
		context_id_param = request.query_params.get("context_id")
		if context_id_param:
			filters.append(FileStorage.context_id == context_id_param)
		
		# محاسبه offset
		offset = (page - 1) * limit
		
		# دریافت فایل‌ها
		files_query = db.query(FileStorage).filter(and_(*filters))
		total_count = files_query.count()
		
		files = files_query.order_by(FileStorage.created_at.desc()).offset(offset).limit(limit).all()
		
		# تبدیل به فرمت مناسب
		files_data = []
		for file in files:
			try:
				files_data.append({
					"id": str(file.id) if file.id else None,
					"original_name": file.original_name or "",
					"file_size": file.file_size or 0,
					"mime_type": file.mime_type or "application/octet-stream",
					"module_context": file.module_context or "",
					"context_id": str(file.context_id) if file.context_id else None,
					"created_at": file.created_at.isoformat() if file.created_at else None,
				})
			except Exception as e:
				# در صورت خطا در تبدیل یک فایل، آن را رد می‌کنیم و ادامه می‌دهیم
				continue
		
		# محاسبه total_pages با محافظت در برابر تقسیم بر صفر
		total_pages = (total_count + limit - 1) // limit if limit > 0 else 1
		
		return success_response({
			"items": files_data,
			"pagination": {
				"page": page,
				"limit": limit,
				"total_count": total_count,
				"total_pages": total_pages,
			}
		}, request)
	except ApiError:
		raise
	except Exception as e:
		raise ApiError(
			"INTERNAL_ERROR",
			f"خطا در دریافت لیست فایل‌ها: {str(e)}",
			http_status=500
		)


@router.get(
	"/files/{file_id}/download",
	summary="دانلود فایل",
	description="دانلود فایل الصاق شده به کسب‌وکار",
)
async def download_file_endpoint(
	business_id: int,
	file_id: str,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	"""دانلود فایل"""
	# بررسی دسترسی به کسب‌وکار
	if not ctx.can_access_business(business_id):
		raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
	
	storage = FileStorageService(db)
	try:
		file_data = await storage.download_file(UUID(file_id))
	except Exception as e:
		raise ApiError("FILE_NOT_FOUND", f"فایل یافت نشد: {str(e)}", http_status=404)
	
	filename = file_data.get("filename") or "file"
	return StreamingResponse(
		io.BytesIO(file_data["content"]),
		media_type=file_data.get("mime_type") or "application/octet-stream",
		headers={"Content-Disposition": f'attachment; filename="{filename}"'},
	)


@router.post(
	"/files/upload",
	summary="آپلود فایل",
	description="آپلود فایل برای کسب‌وکار و الصاق به سند یا بخش خاص",
)
async def upload_file_endpoint(
	business_id: int,
	request: Request,
	file: UploadFile = File(...),
	module_context: str = Form("accounting"),
	context_id: Optional[str] = Form(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	"""آپلود فایل برای کسب‌وکار"""
	# بررسی دسترسی به کسب‌وکار
	if not ctx.can_access_business(business_id):
		raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
	
	# تبدیل context_id به UUID یا string (می‌تواند ID سند یا UUID باشد)
	context_id_final = None
	if context_id:
		# ابتدا سعی می‌کنیم به UUID تبدیل کنیم
		try:
			context_id_final = UUID(context_id)
		except ValueError:
			# اگر UUID نیست، ممکن است ID سند (عدد) باشد
			# در این صورت آن را به string تبدیل می‌کنیم
			context_id_final = str(context_id)
	
	# آپلود فایل
	storage = FileStorageService(db)
	try:
		saved = await storage.upload_file(
			file=file,
			user_id=ctx.get_user_id(),
			module_context=module_context,
			context_id=context_id_final,
			developer_data={"business_id": business_id},
			is_temporary=False,
			expires_in_days=3650,
			business_id=business_id,
			check_storage_limit=True,
		)
		return success_response(saved, request, "فایل با موفقیت آپلود شد")
	except HTTPException as e:
			# اگر خطای محدودیت ذخیره‌سازی باشد، جزئیات را برمی‌گردانیم
			if e.status_code == 400 and isinstance(e.detail, dict) and e.detail.get("error") == "STORAGE_LIMIT_EXCEEDED":
				# ساخت detail با تمام جزئیات
				error_detail = {
					"success": False,
					"error": {
						"code": "STORAGE_LIMIT_EXCEEDED",
						"message": e.detail.get("message", "حجم فایل از محدودیت ذخیره‌سازی تجاوز می‌کند"),
						"total_limit_gb": e.detail.get("total_limit_gb"),
						"current_usage_gb": e.detail.get("current_usage_gb"),
						"available_gb": e.detail.get("available_gb"),
						"required_gb": e.detail.get("required_gb"),
						"over_usage_gb": e.detail.get("over_usage_gb"),
					}
				}
				# استفاده از HTTPException مستقیم برای حفظ جزئیات
				raise HTTPException(status_code=400, detail=error_detail)
			raise


@router.get(
	"/files/{file_id}/thumbnail",
	summary="دانلود thumbnail فایل تصویر",
	description="دانلود نسخه کم‌حجم (thumbnail) برای فایل‌های تصویری الصاق شده به کسب‌وکار",
)
async def download_file_thumbnail_endpoint(
	business_id: int,
	file_id: str,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	size: str = Query(
		"small",
		description="سایز thumbnail برای تصاویر (small یا medium). در صورت عدم پشتیبانی، نادیده گرفته می‌شود.",
	),
) -> Response:
	"""دانلود thumbnail برای فایل‌های تصویری"""
	# بررسی دسترسی به کسب‌وکار
	if not ctx.can_access_business(business_id):
		raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)

	storage = FileStorageService(db)
	try:
		thumb_size = "medium" if size == "medium" else "small"
		file_data = await storage.download_image_thumbnail(UUID(file_id), size=thumb_size)  # type: ignore[arg-type]
	except Exception as e:
		raise ApiError("FILE_NOT_FOUND", f"فایل یافت نشد: {str(e)}", http_status=404)

	filename = file_data.get("filename") or "file"
	return StreamingResponse(
		io.BytesIO(file_data["content"]),
		media_type=file_data.get("mime_type") or "application/octet-stream",
		headers={"Content-Disposition": f'inline; filename=\"{filename}\"'},
	)


@router.put(
	"/files/{file_id}/rename",
	summary="تغییر نام فایل",
	description="تغییر نام فایل الصاق شده به کسب‌وکار",
)
async def rename_file_endpoint(
	business_id: int,
	file_id: str,
	request: Request,
	new_name: str = Body(..., embed=True),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	"""تغییر نام فایل"""
	# بررسی دسترسی به کسب‌وکار
	if not ctx.can_access_business(business_id):
		raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
	
	from adapters.db.models.file_storage import FileStorage
	
	# بررسی وجود فایل و تعلق آن به کسب‌وکار
	file_storage = db.query(FileStorage).filter(
		and_(
			FileStorage.id == file_id,
			FileStorage.business_id == business_id,
			FileStorage.deleted_at.is_(None),
		)
	).first()
	
	if not file_storage:
		raise ApiError("FILE_NOT_FOUND", "فایل یافت نشد", http_status=404)
	
	# بررسی اعتبار نام جدید
	if not new_name or not new_name.strip():
		raise ApiError("INVALID_NAME", "نام فایل نمی‌تواند خالی باشد", http_status=400)
	
	# تغییر نام
	file_storage.original_name = new_name.strip()
	db.commit()
	db.refresh(file_storage)
	
	return success_response({
		"id": str(file_storage.id),
		"original_name": file_storage.original_name,
	}, request, "نام فایل با موفقیت تغییر یافت")


@router.delete(
	"/files/{file_id}",
	summary="حذف فایل",
	description="حذف فایل الصاق شده به کسب‌وکار",
)
async def delete_file_endpoint(
	business_id: int,
	file_id: str,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	"""حذف فایل"""
	# بررسی دسترسی به کسب‌وکار
	if not ctx.can_access_business(business_id):
		raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
	
	from uuid import UUID
	
	# بررسی وجود فایل و تعلق آن به کسب‌وکار
	file_storage = db.query(FileStorage).filter(
		and_(
			FileStorage.id == file_id,
			FileStorage.business_id == business_id,
			FileStorage.deleted_at.is_(None),
		)
	).first()
	
	if not file_storage:
		raise ApiError("FILE_NOT_FOUND", "فایل یافت نشد", http_status=404)
	
	dependency_service = FileDependencyService(db)
	dependencies = dependency_service.get_dependencies(file_storage)
	cleared_dependencies = dependency_service.cleanup_dependencies(file_storage)
	
	# حذف فایل
	storage = FileStorageService(db)
	try:
		success = await storage.delete_file(UUID(file_id))
		if not success:
			raise ApiError("DELETE_ERROR", "خطا در حذف فایل", http_status=500)
	except Exception as e:
		raise ApiError("DELETE_ERROR", f"خطا در حذف فایل: {str(e)}", http_status=500)
	
	return success_response({
		"ok": True,
		"dependencies": [dep.to_dict() for dep in dependencies],
		"cleaned": [dep.to_dict() for dep in cleared_dependencies],
	}, request, "فایل با موفقیت حذف شد")

