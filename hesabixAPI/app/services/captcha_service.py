from __future__ import annotations

import base64
import io
import os
import secrets
from datetime import datetime, timedelta
from typing import Tuple

from PIL import Image, ImageDraw, ImageFont, ImageFilter
from sqlalchemy.orm import Session

from adapters.db.models.captcha import Captcha
from app.core.settings import get_settings
import hashlib


def _generate_numeric_code(length: int) -> str:
	return "".join(str(secrets.randbelow(10)) for _ in range(length))


def _hash_code(code: str, secret: str) -> str:
	return hashlib.sha256(f"{secret}:{code}".encode("utf-8")).hexdigest()


def _render_image(code: str, width: int = 140, height: int = 48) -> Image.Image:
	bg_color = (245, 246, 248)
	img = Image.new("RGB", (width, height), bg_color)
	draw = ImageDraw.Draw(img)

	try:
		font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
		font = ImageFont.truetype(font_path, 28)
	except Exception:
		font = ImageFont.load_default()

	# Noise lines
	for _ in range(3):
		xy = [(secrets.randbelow(width), secrets.randbelow(height)) for _ in range(2)]
		draw.line(xy, fill=(200, 205, 210), width=1)

	# measure text
	try:
		bbox = draw.textbbox((0, 0), code, font=font)
		text_w = bbox[2] - bbox[0]
		text_h = bbox[3] - bbox[1]
	except Exception:
		# fallback approximate
		text_w, text_h = (len(code) * 16, 24)

	x = (width - text_w) // 2
	y = (height - text_h) // 2
	# Slight jitter per character
	avg_char_w = max(1, text_w // max(1, len(code)))
	for idx, ch in enumerate(code):
		cx = x + idx * avg_char_w + secrets.randbelow(3)
		cy = y + secrets.randbelow(3)
		draw.text((cx, cy), ch, font=font, fill=(60, 70, 80))

	img = img.filter(ImageFilter.SMOOTH)
	return img


def create_captcha(db: Session) -> tuple[str, str, int]:
	settings = get_settings()
	code = _generate_numeric_code(settings.captcha_length)
	code_hash = _hash_code(code, settings.captcha_secret)
	captcha_id = f"cpt_{secrets.token_hex(8)}"
	expires_at = datetime.utcnow() + timedelta(seconds=settings.captcha_ttl_seconds)

	obj = Captcha(id=captcha_id, code_hash=code_hash, expires_at=expires_at, attempts=0)
	db.add(obj)
	db.commit()

	image = _render_image(code)
	buf = io.BytesIO()
	image.save(buf, format="PNG")
	image_base64 = base64.b64encode(buf.getvalue()).decode("ascii")
	return captcha_id, image_base64, settings.captcha_ttl_seconds


def validate_captcha(db: Session, captcha_id: str, code: str) -> bool:
	settings = get_settings()
	obj = db.get(Captcha, captcha_id)
	if obj is None:
		return False
	if obj.expires_at < datetime.utcnow():
		return False
	provided_hash = _hash_code(code.strip(), settings.captcha_secret)
	if secrets.compare_digest(provided_hash, obj.code_hash):
		# مصرف یک‌باره: جلوگیری از ارسال موازی/بازپخش با همان کپچا
		db.delete(obj)
		db.commit()
		return True
	obj.attempts += 1
	db.add(obj)
	db.commit()
	return False


