from __future__ import annotations

from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.responses import success_response
from app.services.captcha_service import create_captcha
from app.services.auth_service import register_user, login_user, create_password_reset, reset_password
from .schemas import RegisterRequest, LoginRequest, ForgotPasswordRequest, ResetPasswordRequest, CreateApiKeyRequest
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
	)
	# Create a session api key similar to login
	user_agent = request.headers.get("User-Agent")
	ip = request.client.host if request.client else None
	from app.core.security import generate_api_key
	from adapters.db.repositories.api_key_repo import ApiKeyRepository
	api_key, key_hash = generate_api_key()
	api_repo = ApiKeyRepository(db)
	api_repo.create_session_key(user_id=user_id, key_hash=key_hash, device_id=payload.device_id, user_agent=user_agent, ip=ip, expires_at=None)
	user = {"id": user_id, "first_name": payload.first_name, "last_name": payload.last_name, "email": payload.email, "mobile": payload.mobile}
	return success_response({"api_key": api_key, "expires_at": None, "user": user})


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
	return success_response({"api_key": api_key, "expires_at": expires_at, "user": user})


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


@router.delete("/api-keys/{key_id}", summary="Revoke API key")
def delete_key(key_id: int, ctx: AuthContext = Depends(get_current_user), db: Session = Depends(get_db)) -> dict:
	revoke_key(db, ctx.user.id, key_id)
	return success_response({"ok": True})


