from __future__ import annotations

import base64
import io
import secrets
from datetime import datetime, timedelta

from PIL import Image, ImageDraw, ImageFont, ImageFilter
from sqlalchemy.orm import Session

from adapters.db.models.captcha import Captcha
from app.core.settings import get_settings
from app.services.auth_security_event_service import log_auth_security_event
from app.services.system_settings_service import get_captcha_auth_security_effective
import hashlib


_ALPHANUM_CHARSET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"


def _generate_numeric_code(length: int) -> str:
	return "".join(str(secrets.randbelow(10)) for _ in range(length))


def _generate_alphanumeric_code(length: int) -> str:
	return "".join(secrets.choice(_ALPHANUM_CHARSET) for _ in range(length))


def _hash_code(code: str, secret: str) -> str:
	return hashlib.sha256(f"{secret}:{code}".encode("utf-8")).hexdigest()


def _normalize_user_code(raw: str, mode: str) -> str:
	s = (raw or "").strip()
	if mode == "alphanumeric":
		return s.upper()
	return s


def _render_image(code: str, strong: bool) -> Image.Image:
	length = max(4, min(10, len(code)))
	width = max(150, 22 * length + 20)
	height = 52
	bg0 = 235 + secrets.randbelow(15)
	bg1 = 238 + secrets.randbelow(10)
	bg2 = 242 + secrets.randbelow(8)
	img = Image.new("RGB", (width, height), (bg0, bg1, bg2))
	draw = ImageDraw.Draw(img)
	try:
		font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
		font = ImageFont.truetype(font_path, 26)
	except Exception:
		font = ImageFont.load_default()
	for _ in range(8 if strong else 3):
		xy = [(secrets.randbelow(width), secrets.randbelow(height)) for _ in range(2)]
		fill = (180 + secrets.randbelow(40), 185 + secrets.randbelow(40), 192 + secrets.randbelow(40))
		draw.line(xy, fill=fill, width=2 if strong else 1)
	if strong:
		for _ in range(50):
			x, y = secrets.randbelow(max(1, width - 1)), secrets.randbelow(max(1, height - 1))
			draw.point((x, y), fill=(80 + secrets.randbelow(120), 80 + secrets.randbelow(120), 90 + secrets.randbelow(100)))
	try:
		bbox = draw.textbbox((0, 0), code, font=font)
		text_w = bbox[2] - bbox[0]
		text_h = bbox[3] - bbox[1]
	except Exception:
		text_w, text_h = (len(code) * 16, 24)
	x = (width - text_w) // 2
	y = (height - text_h) // 2
	avg_char_w = max(1, text_w // max(1, len(code)))
	jm = 5 if strong else 3
	for idx, ch in enumerate(code):
		cx = x + idx * avg_char_w + secrets.randbelow(jm)
		cy = y + secrets.randbelow(jm)
		fill = (35 + secrets.randbelow(50), 45 + secrets.randbelow(50), 55 + secrets.randbelow(50))
		draw.text((cx, cy), ch, font=font, fill=fill)
	img = img.filter(ImageFilter.SMOOTH)
	if strong:
		img = img.filter(ImageFilter.EDGE_ENHANCE_MORE)
	return img


def create_captcha(db: Session, client_ip: str | None) -> tuple[str, str, int]:
	settings = get_settings()
	cfg = get_captcha_auth_security_effective(db)
	mode = cfg["captcha_mode"]
	length = int(cfg["captcha_length"])
	strong = bool(cfg["captcha_strong_image"])
	if mode == "alphanumeric":
		code = _generate_alphanumeric_code(length)
	else:
		code = _generate_numeric_code(length)
	code_hash = _hash_code(_normalize_user_code(code, mode), settings.captcha_secret)
	captcha_id = f"cpt_{secrets.token_hex(8)}"
	expires_at = datetime.utcnow() + timedelta(seconds=int(cfg["captcha_ttl_seconds"]))

	obj = Captcha(
		id=captcha_id,
		code_hash=code_hash,
		expires_at=expires_at,
		attempts=0,
		client_ip=(client_ip[:45] if client_ip else None),
	)
	db.add(obj)
	db.commit()

	image = _render_image(code, strong=strong)
	buf = io.BytesIO()
	image.save(buf, format="PNG")
	image_base64 = base64.b64encode(buf.getvalue()).decode("ascii")
	return captcha_id, image_base64, int(cfg["captcha_ttl_seconds"])


def validate_captcha(
	db: Session,
	captcha_id: str,
	code: str,
	*,
	client_ip: str | None = None,
) -> bool:
	settings = get_settings()
	cfg = get_captcha_auth_security_effective(db)
	max_attempts = int(cfg["captcha_max_attempts"])
	bind_ip = bool(cfg["captcha_bind_ip"])
	mode = cfg["captcha_mode"]

	obj = db.get(Captcha, captcha_id)
	if obj is None:
		log_auth_security_event(
			event_type="captcha_invalid",
			client_ip=client_ip,
			detail={"reason": "not_found", "captcha_id_prefix": (captcha_id[:12] if captcha_id else "")},
		)
		return False
	if obj.expires_at < datetime.utcnow():
		log_auth_security_event(
			event_type="captcha_invalid",
			client_ip=client_ip,
			detail={"reason": "expired"},
		)
		db.delete(obj)
		db.commit()
		return False
	if bind_ip and client_ip and obj.client_ip and obj.client_ip != client_ip[:45]:
		log_auth_security_event(
			event_type="captcha_ip_mismatch",
			client_ip=client_ip,
			detail={"expected_prefix": obj.client_ip[:8]},
		)
		db.delete(obj)
		db.commit()
		return False

	norm = _normalize_user_code(code, mode)
	provided_hash = _hash_code(norm, settings.captcha_secret)
	if secrets.compare_digest(provided_hash, obj.code_hash):
		db.delete(obj)
		db.commit()
		return True

	# اشتباه: افزایش تلاش
	new_attempts = int(obj.attempts) + 1
	if new_attempts >= max_attempts:
		log_auth_security_event(
			event_type="captcha_exhausted",
			client_ip=client_ip,
			detail={"attempts": new_attempts, "captcha_id_prefix": captcha_id[:12]},
		)
		db.delete(obj)
		db.commit()
		return False

	log_auth_security_event(
		event_type="captcha_invalid",
		client_ip=client_ip,
		detail={"reason": "wrong_code", "attempts": new_attempts},
	)
	obj.attempts = new_attempts
	db.add(obj)
	db.commit()
	return False
