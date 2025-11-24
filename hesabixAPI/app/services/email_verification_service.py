from __future__ import annotations

from datetime import datetime, timedelta
from typing import Optional
from urllib.parse import urlencode

from sqlalchemy.orm import Session

from adapters.db.models.user import User
from adapters.db.repositories.user_repo import UserRepository
from adapters.db.repositories.email_verification_repo import EmailVerificationRepository
from app.core.security import hash_api_key
from app.core.responses import ApiError
from app.services.email_service import EmailService
from app.core.settings import get_settings


def create_email_verification_token(db: Session, user_id: int, email: str, base_url: str | None = None) -> str:
	"""
	ایجاد token برای تایید ایمیل و ارسال ایمیل verification
	
	Args:
		db: Database session
		user_id: شناسه کاربر
		email: آدرس ایمیل برای verification
		base_url: آدرس پایه برای ساخت لینک verification (اختیاری)
	
	Returns:
		token: Token ایجاد شده (برای تست)
	"""
	from secrets import token_urlsafe
	
	# بررسی وجود کاربر
	user_repo = UserRepository(db)
	user = db.get(User, user_id)
	if not user:
		raise ApiError("USER_NOT_FOUND", "کاربر یافت نشد", http_status=404)
	
	# ایجاد token
	token = token_urlsafe(32)
	token_hash = hash_api_key(token)
	
	# زمان انقضا: 24 ساعت
	expires_at = datetime.utcnow() + timedelta(hours=24)
	
	# ذخیره token
	verification_repo = EmailVerificationRepository(db)
	verification_repo.create(
		user_id=user_id,
		email=email,
		token_hash=token_hash,
		expires_at=expires_at
	)
	
	# ارسال ایمیل
	send_verification_email(db, user_id, email, token, base_url)
	
	return token


def send_verification_email(db: Session, user_id: int, email: str, token: str, base_url: str | None = None) -> bool:
	"""
	ارسال ایمیل verification
	
	Args:
		db: Database session
		user_id: شناسه کاربر
		email: آدرس ایمیل
		token: Token verification
		base_url: آدرس پایه برای ساخت لینک (اختیاری)
	
	Returns:
		bool: True اگر ایمیل با موفقیت ارسال شد
	"""
	user_repo = UserRepository(db)
	user = db.get(User, user_id)
	if not user:
		return False
	
	# ساخت لینک verification
	if not base_url:
		settings = get_settings()
		# استفاده از تنظیمات یا مقدار پیش‌فرض
		base_url = "https://app.hesabix.com"  # TODO: از تنظیمات سیستم بخوان
	
	verify_url = f"{base_url}/verify-email?{urlencode({'token': token})}"
	
	# ساخت محتوای ایمیل
	user_name = f"{user.first_name or ''} {user.last_name or ''}".strip() or "کاربر گرامی"
	subject = "تایید ایمیل حساب کاربری حسابیکس"
	
	body_text = f"""
سلام {user_name}،

برای فعال‌سازی حساب کاربری خود در حسابیکس، لطفاً روی لینک زیر کلیک کنید:

{verify_url}

این لینک تا 24 ساعت معتبر است.

اگر شما این درخواست را انجام نداده‌اید، لطفاً این ایمیل را نادیده بگیرید.

با احترام
تیم حسابیکس
"""
	
	html_body = f"""
<!DOCTYPE html>
<html dir="rtl" lang="fa">
<head>
	<meta charset="UTF-8">
	<meta name="viewport" content="width=device-width, initial-scale=1.0">
	<title>تایید ایمیل</title>
</head>
<body style="font-family: Tahoma, Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
	<div style="background-color: #f8f9fa; padding: 30px; border-radius: 10px; border: 1px solid #dee2e6;">
		<h2 style="color: #0F4C81; margin-top: 0;">تایید ایمیل حساب کاربری</h2>
		<p>سلام {user_name}،</p>
		<p>برای فعال‌سازی حساب کاربری خود در حسابیکس، لطفاً روی دکمه زیر کلیک کنید:</p>
		<div style="text-align: center; margin: 30px 0;">
			<a href="{verify_url}" style="background-color: #0F4C81; color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; display: inline-block; font-weight: bold;">تایید ایمیل</a>
		</div>
		<p style="color: #666; font-size: 14px;">یا می‌توانید لینک زیر را در مرورگر خود کپی کنید:</p>
		<p style="word-break: break-all; color: #0F4C81; font-size: 12px;">{verify_url}</p>
		<p style="color: #666; font-size: 14px; margin-top: 30px;">این لینک تا 24 ساعت معتبر است.</p>
		<p style="color: #666; font-size: 14px;">اگر شما این درخواست را انجام نداده‌اید، لطفاً این ایمیل را نادیده بگیرید.</p>
		<hr style="border: none; border-top: 1px solid #dee2e6; margin: 30px 0;">
		<p style="color: #999; font-size: 12px; text-align: center;">با احترام<br>تیم حسابیکس</p>
	</div>
</body>
</html>
"""
	
	# ارسال ایمیل
	email_service = EmailService(db)
	return email_service.send_email(
		to=email,
		subject=subject,
		body=body_text,
		html_body=html_body
	)


def verify_email_token(db: Session, token: str) -> User:
	"""
	تایید ایمیل با استفاده از token
	
	Args:
		db: Database session
		token: Token verification
	
	Returns:
		User: کاربر تایید شده
	
	Raises:
		ApiError: در صورت نامعتبر بودن token
	"""
	from app.core.security import hash_api_key
	
	verification_repo = EmailVerificationRepository(db)
	token_hash = hash_api_key(token)
	
	# یافتن token
	verification_token = verification_repo.get_by_hash(token_hash)
	if not verification_token:
		raise ApiError("INVALID_TOKEN", "Token نامعتبر یا استفاده شده است", http_status=400)
	
	# بررسی انقضا
	if verification_token.expires_at < datetime.utcnow():
		raise ApiError("TOKEN_EXPIRED", "Token منقضی شده است", http_status=400)
	
	# یافتن کاربر
	user = db.get(User, verification_token.user_id)
	if not user:
		raise ApiError("USER_NOT_FOUND", "کاربر یافت نشد", http_status=404)
	
	# بررسی تطابق ایمیل
	if user.email != verification_token.email:
		raise ApiError("EMAIL_MISMATCH", "ایمیل کاربر تغییر کرده است", http_status=400)
	
	# تایید ایمیل
	user.email_verified = True
	db.add(user)
	
	# علامت‌گذاری token به عنوان استفاده شده
	verification_repo.mark_used(verification_token)
	
	db.commit()
	db.refresh(user)
	
	return user


def can_resend_verification(db: Session, user_id: int, max_per_hour: int = 3) -> bool:
	"""
	بررسی امکان ارسال مجدد ایمیل verification (rate limiting)
	
	Args:
		db: Database session
		user_id: شناسه کاربر
		max_per_hour: حداکثر تعداد ارسال در ساعت
	
	Returns:
		bool: True اگر امکان ارسال وجود دارد
	"""
	verification_repo = EmailVerificationRepository(db)
	count = verification_repo.count_recent_by_user(user_id, hours=1)
	return count < max_per_hour


def resend_verification_email(db: Session, user_id: int, base_url: str | None = None) -> bool:
	"""
	ارسال مجدد ایمیل verification
	
	Args:
		db: Database session
		user_id: شناسه کاربر
		base_url: آدرس پایه برای ساخت لینک (اختیاری)
	
	Returns:
		bool: True اگر ایمیل با موفقیت ارسال شد
	
	Raises:
		ApiError: در صورت عدم امکان ارسال
	"""
	# بررسی rate limiting
	if not can_resend_verification(db, user_id):
		raise ApiError("RATE_LIMIT_EXCEEDED", "شما بیش از حد مجاز درخواست ارسال مجدد داده‌اید. لطفاً یک ساعت صبر کنید.", http_status=429)
	
	# یافتن کاربر
	user = db.get(User, user_id)
	if not user:
		raise ApiError("USER_NOT_FOUND", "کاربر یافت نشد", http_status=404)
	
	if not user.email:
		raise ApiError("EMAIL_NOT_SET", "ایمیل کاربر تنظیم نشده است", http_status=400)
	
	if user.email_verified:
		raise ApiError("EMAIL_ALREADY_VERIFIED", "ایمیل کاربر قبلاً تایید شده است", http_status=400)
	
	# ایجاد و ارسال token جدید
	create_email_verification_token(db, user_id, user.email, base_url)
	
	return True

