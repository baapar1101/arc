from __future__ import annotations

from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.responses import success_response, format_datetime_fields
from app.services.captcha_service import create_captcha
from app.services.auth_service import register_user, login_user, create_password_reset, reset_password, change_password, referral_stats, referral_list
from .schemas import RegisterRequest, LoginRequest, ForgotPasswordRequest, ResetPasswordRequest, ChangePasswordRequest, CreateApiKeyRequest
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
	user = {"id": user_id, "first_name": payload.first_name, "last_name": payload.last_name, "email": payload.email, "mobile": payload.mobile, "referral_code": getattr(user_obj, "referral_code", None)}
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
def list_keys(ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db)) -> dict:
	items = list_personal_keys(db, ctx.user.id)
	return success_response(items)


@router.post("/api-keys", summary="Create personal API key")
def create_key(payload: CreateApiKeyRequest, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db)) -> dict:
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
def delete_key(key_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db)) -> dict:
	revoke_key(db, ctx.user.id, key_id)
	return success_response({"ok": True})


@router.get("/referrals/stats", summary="Referral stats for current user")
def get_referral_stats(ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db), start: str | None = None, end: str | None = None) -> dict:
	from datetime import datetime
	start_dt = datetime.fromisoformat(start) if start else None
	end_dt = datetime.fromisoformat(end) if end else None
	stats = referral_stats(db=db, user_id=ctx.user.id, start=start_dt, end=end_dt)
	return success_response(stats)


@router.get("/referrals/list", summary="Referral list for current user")
def get_referral_list(
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	start: str | None = None,
	end: str | None = None,
	search: str | None = None,
	page: int = 1,
	limit: int = 20,
) -> dict:
	from datetime import datetime
	start_dt = datetime.fromisoformat(start) if start else None
	end_dt = datetime.fromisoformat(end) if end else None
	resp = referral_list(db=db, user_id=ctx.user.id, start=start_dt, end=end_dt, search=search, page=page, limit=limit)
	return success_response(resp)

