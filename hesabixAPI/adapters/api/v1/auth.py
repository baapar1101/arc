from __future__ import annotations

import datetime
from fastapi import APIRouter, Depends, Request
from fastapi.responses import Response
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.responses import success_response, format_datetime_fields
from app.services.captcha_service import create_captcha
from app.services.auth_service import register_user, login_user, create_password_reset, reset_password, change_password, referral_stats
from app.services.pdf import PDFService
from .schemas import RegisterRequest, LoginRequest, ForgotPasswordRequest, ResetPasswordRequest, ChangePasswordRequest, CreateApiKeyRequest, QueryInfo, FilterItem
from app.core.auth_dependency import get_current_user, AuthContext
from app.services.api_key_service import list_personal_keys, create_personal_key, revoke_key


router = APIRouter(prefix="/auth", tags=["auth"]) 


@router.post("/captcha", summary="Generate numeric captcha")
def generate_captcha(db: Session = Depends(get_db)) -> dict:
	captcha_id, image_base64, ttl = create_captcha(db)
	return success_response({
		"captcha_id": captcha_id,
		"image_base64": image_base64,
		"ttl_seconds": ttl,
	})


@router.post("/register", summary="Register new user")
def register(request: Request, payload: RegisterRequest, db: Session = Depends(get_db)) -> dict:
	user_id = register_user(
		db=db,
		first_name=payload.first_name,
		last_name=payload.last_name,
		email=payload.email,
		mobile=payload.mobile,
		password=payload.password,
		captcha_id=payload.captcha_id,
		captcha_code=payload.captcha_code,
		referrer_code=payload.referrer_code,
	)
	# Create a session api key similar to login
	user_agent = request.headers.get("User-Agent")
	ip = request.client.host if request.client else None
	from app.core.security import generate_api_key
	from adapters.db.repositories.api_key_repo import ApiKeyRepository
	api_key, key_hash = generate_api_key()
	api_repo = ApiKeyRepository(db)
	api_repo.create_session_key(user_id=user_id, key_hash=key_hash, device_id=payload.device_id, user_agent=user_agent, ip=ip, expires_at=None)
	from adapters.db.models.user import User
	user_obj = db.get(User, user_id)
	user = {"id": user_id, "first_name": payload.first_name, "last_name": payload.last_name, "email": payload.email, "mobile": payload.mobile, "referral_code": getattr(user_obj, "referral_code", None), "app_permissions": getattr(user_obj, "app_permissions", None)}
	response_data = {"api_key": api_key, "expires_at": None, "user": user}
	formatted_data = format_datetime_fields(response_data, request)
	return success_response(formatted_data, request)


@router.post("/login", summary="Login with email or mobile")
def login(request: Request, payload: LoginRequest, db: Session = Depends(get_db)) -> dict:
	user_agent = request.headers.get("User-Agent")
	ip = request.client.host if request.client else None
	api_key, expires_at, user = login_user(
		db=db,
		identifier=payload.identifier,
		password=payload.password,
		captcha_id=payload.captcha_id,
		captcha_code=payload.captcha_code,
		device_id=payload.device_id,
		user_agent=user_agent,
		ip=ip,
	)
	# Ensure referral_code is included
	from adapters.db.repositories.user_repo import UserRepository
	repo = UserRepository(db)
	from adapters.db.models.user import User
	user_obj = None
	if 'id' in user and user['id']:
		user_obj = repo.db.get(User, user['id'])
	if user_obj is not None:
		user["referral_code"] = getattr(user_obj, "referral_code", None)
	response_data = {"api_key": api_key, "expires_at": expires_at, "user": user}
	formatted_data = format_datetime_fields(response_data, request)
	return success_response(formatted_data, request)


@router.post("/forgot-password", summary="Create password reset token")
def forgot_password(payload: ForgotPasswordRequest, db: Session = Depends(get_db)) -> dict:
	# In production do not return token; send via email/SMS. Here we return for dev/testing.
	token = create_password_reset(db=db, identifier=payload.identifier, captcha_id=payload.captcha_id, captcha_code=payload.captcha_code)
	return success_response({"ok": True, "token": token if token else None})


@router.post("/reset-password", summary="Reset password with token")
def reset_password_endpoint(payload: ResetPasswordRequest, db: Session = Depends(get_db)) -> dict:
	reset_password(db=db, token=payload.token, new_password=payload.new_password, captcha_id=payload.captcha_id, captcha_code=payload.captcha_code)
	return success_response({"ok": True})


@router.get("/api-keys", summary="List personal API keys")
def list_keys(request: Request, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db)) -> dict:
	items = list_personal_keys(db, ctx.user.id)
	return success_response(items)


@router.post("/api-keys", summary="Create personal API key")
def create_key(request: Request, payload: CreateApiKeyRequest, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db)) -> dict:
	id_, api_key = create_personal_key(db, ctx.user.id, payload.name, payload.scopes, None)
	return success_response({"id": id_, "api_key": api_key})


@router.post("/change-password", summary="Change user password")
def change_password_endpoint(request: Request, payload: ChangePasswordRequest, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db)) -> dict:
	# دریافت translator از request state
	translator = getattr(request.state, "translator", None)
	
	change_password(
		db=db,
		user_id=ctx.user.id,
		current_password=payload.current_password,
		new_password=payload.new_password,
		confirm_password=payload.confirm_password,
		translator=translator
	)
	return success_response({"ok": True})


@router.delete("/api-keys/{key_id}", summary="Revoke API key")
def delete_key(request: Request, key_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db)) -> dict:
	revoke_key(db, ctx.user.id, key_id)
	return success_response({"ok": True})


@router.get("/referrals/stats", summary="Referral stats for current user")
def get_referral_stats(request: Request, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), start: str | None = None, end: str | None = None) -> dict:
	from datetime import datetime
	start_dt = datetime.fromisoformat(start) if start else None
	end_dt = datetime.fromisoformat(end) if end else None
	stats = referral_stats(db=db, user_id=ctx.user.id, start=start_dt, end=end_dt)
	return success_response(stats)


@router.post("/referrals/list", summary="Referral list with advanced filtering")
def get_referral_list_advanced(
	request: Request,
	query_info: QueryInfo,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
) -> dict:
	"""
	دریافت لیست معرفی‌ها با قابلیت فیلتر پیشرفته
	
	پارامترهای QueryInfo:
	- sort_by: فیلد مرتب‌سازی (مثال: created_at, first_name, last_name, email)
	- sort_desc: ترتیب نزولی (true/false)
	- take: تعداد رکورد در هر صفحه (پیش‌فرض: 10)
	- skip: تعداد رکورد صرف‌نظر شده (پیش‌فرض: 0)
	- search: عبارت جستجو
	- search_fields: فیلدهای جستجو (مثال: ["first_name", "last_name", "email"])
	- filters: آرایه فیلترها با ساختار:
	  [
		{
		  "property": "created_at",
		  "operator": ">=",
		  "value": "2024-01-01T00:00:00"
		},
		{
		  "property": "first_name", 
		  "operator": "*",
		  "value": "احمد"
		}
	  ]
	"""
	from adapters.db.repositories.user_repo import UserRepository
	from adapters.db.models.user import User
	from datetime import datetime
	
	# Create a custom query for referrals
	repo = UserRepository(db)
	
	# Add filter for referrals only (users with referred_by_user_id = current user)
	referral_filter = FilterItem(
		property="referred_by_user_id",
		operator="=",
		value=ctx.user.id
	)
	
	# Add referral filter to existing filters
	if query_info.filters is None:
		query_info.filters = [referral_filter]
	else:
		query_info.filters.append(referral_filter)
	
	# Set default search fields for referrals
	if query_info.search_fields is None:
		query_info.search_fields = ["first_name", "last_name", "email"]
	
	# Execute query with filters
	referrals, total = repo.query_with_filters(query_info)
	
	# Convert to dictionary format
	referral_dicts = [repo.to_dict(referral) for referral in referrals]
	
	# Format datetime fields
	formatted_referrals = format_datetime_fields(referral_dicts, request)
	
	# Calculate pagination info
	page = (query_info.skip // query_info.take) + 1
	total_pages = (total + query_info.take - 1) // query_info.take
	
	return success_response({
		"items": formatted_referrals,
		"total": total,
		"page": page,
		"limit": query_info.take,
		"total_pages": total_pages,
		"has_next": page < total_pages,
		"has_prev": page > 1
	}, request)


@router.post("/referrals/export/pdf", summary="Export referrals to PDF")
def export_referrals_pdf(
	request: Request,
	query_info: QueryInfo,
	selected_only: bool = False,
	selected_indices: str | None = None,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
) -> Response:
	"""
	خروجی PDF لیست معرفی‌ها
	
	پارامترها:
	- selected_only: آیا فقط سطرهای انتخاب شده export شوند
	- selected_indices: لیست ایندکس‌های انتخاب شده (JSON string)
	- سایر پارامترهای QueryInfo برای فیلتر
	"""
	from app.services.pdf import PDFService
	from app.services.auth_service import referral_stats
	import json
	
	# Parse selected indices if provided
	indices = None
	if selected_only and selected_indices:
		try:
			indices = json.loads(selected_indices)
		except (json.JSONDecodeError, TypeError):
			indices = None
	
	# Get stats for the report
	stats = None
	try:
		# Extract date range from filters if available
		start_date = None
		end_date = None
		if query_info.filters:
			for filter_item in query_info.filters:
				if filter_item.property == 'created_at':
					if filter_item.operator == '>=':
						start_date = filter_item.value
					elif filter_item.operator == '<':
						end_date = filter_item.value
		
		stats = referral_stats(
			db=db,
			user_id=ctx.user.id,
			start=start_date,
			end=end_date
		)
	except Exception:
		pass  # Continue without stats
	
	# Get calendar type from request headers
	calendar_header = request.headers.get("X-Calendar-Type", "jalali")
	calendar_type = "jalali" if calendar_header.lower() in ["jalali", "persian", "shamsi"] else "gregorian"
	
	# Generate PDF using new modular service
	pdf_service = PDFService()
	
	# Get locale from request headers
	locale_header = request.headers.get("Accept-Language", "fa")
	locale = "fa" if locale_header.startswith("fa") else "en"
	
	pdf_bytes = pdf_service.generate_pdf(
		module_name='marketing',
		data={},  # Empty data - module will fetch its own data
		calendar_type=calendar_type,
		locale=locale,
		db=db,
		user_id=ctx.user.id,
		query_info=query_info,
		selected_indices=indices,
		stats=stats
	)
	
	# Return PDF response
	from fastapi.responses import Response
	import datetime
	
	filename = f"referrals_export_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
	
	return Response(
		content=pdf_bytes,
		media_type="application/pdf",
		headers={
			"Content-Disposition": f"attachment; filename={filename}",
			"Content-Length": str(len(pdf_bytes))
		}
	)


@router.post("/referrals/export/excel", summary="Export referrals to Excel")
def export_referrals_excel(
	request: Request,
	query_info: QueryInfo,
	selected_only: bool = False,
	selected_indices: str | None = None,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
) -> Response:
	"""
	خروجی Excel لیست معرفی‌ها (فایل Excel واقعی برای دانلود)
	
	پارامترها:
	- selected_only: آیا فقط سطرهای انتخاب شده export شوند
	- selected_indices: لیست ایندکس‌های انتخاب شده (JSON string)
	- سایر پارامترهای QueryInfo برای فیلتر
	"""
	from app.services.pdf import PDFService
	import json
	import io
	from openpyxl import Workbook
	from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
	
	# Parse selected indices if provided
	indices = None
	if selected_only and selected_indices:
		try:
			indices = json.loads(selected_indices)
		except (json.JSONDecodeError, TypeError):
			indices = None
	
	# Get calendar type from request headers
	calendar_header = request.headers.get("X-Calendar-Type", "jalali")
	calendar_type = "jalali" if calendar_header.lower() in ["jalali", "persian", "shamsi"] else "gregorian"
	
	# Generate Excel data using new modular service
	pdf_service = PDFService()
	
	# Get locale from request headers
	locale_header = request.headers.get("Accept-Language", "fa")
	locale = "fa" if locale_header.startswith("fa") else "en"
	
	excel_data = pdf_service.generate_excel_data(
		module_name='marketing',
		data={},  # Empty data - module will fetch its own data
		calendar_type=calendar_type,
		locale=locale,
		db=db,
		user_id=ctx.user.id,
		query_info=query_info,
		selected_indices=indices
	)
	
	# Create Excel workbook
	wb = Workbook()
	ws = wb.active
	ws.title = "Referrals"
	
	# Define styles
	header_font = Font(bold=True, color="FFFFFF")
	header_fill = PatternFill(start_color="366092", end_color="366092", fill_type="solid")
	header_alignment = Alignment(horizontal="center", vertical="center")
	border = Border(
		left=Side(style='thin'),
		right=Side(style='thin'),
		top=Side(style='thin'),
		bottom=Side(style='thin')
	)
	
	# Add headers
	if excel_data:
		headers = list(excel_data[0].keys())
		for col, header in enumerate(headers, 1):
			cell = ws.cell(row=1, column=col, value=header)
			cell.font = header_font
			cell.fill = header_fill
			cell.alignment = header_alignment
			cell.border = border
		
		# Add data rows
		for row, data in enumerate(excel_data, 2):
			for col, header in enumerate(headers, 1):
				cell = ws.cell(row=row, column=col, value=data.get(header, ""))
				cell.border = border
				# Center align for numbers and dates
				if header in ["ردیف", "Row", "تاریخ ثبت", "Registration Date"]:
					cell.alignment = Alignment(horizontal="center")
	
	# Auto-adjust column widths
	for column in ws.columns:
		max_length = 0
		column_letter = column[0].column_letter
		for cell in column:
			try:
				if len(str(cell.value)) > max_length:
					max_length = len(str(cell.value))
			except:
				pass
		adjusted_width = min(max_length + 2, 50)
		ws.column_dimensions[column_letter].width = adjusted_width
	
	# Save to BytesIO
	excel_buffer = io.BytesIO()
	wb.save(excel_buffer)
	excel_buffer.seek(0)
	
	# Generate filename
	filename = f"referrals_export_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"
	
	# Return Excel file as response
	return Response(
		content=excel_buffer.getvalue(),
		media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
		headers={
			"Content-Disposition": f"attachment; filename={filename}",
			"Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
		}
	)

