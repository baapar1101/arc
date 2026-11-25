"""Rewards, member consent, vouchers, campaigns, and safe dynamic segments."""
from __future__ import annotations

import secrets
import string
from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from typing import Any, Dict, List, Optional

from sqlalchemy import and_, or_, cast, String
from sqlalchemy.orm import Session

from adapters.db.models.customer_club import (
	CustomerClubBalance,
	CustomerClubCampaign,
	CustomerClubCampaignMember,
	CustomerClubLedger,
	CustomerClubMember,
	CustomerClubReward,
	CustomerClubSettings,
	CustomerClubSurveyResponse,
	CustomerClubRfmSnapshot,
	CustomerClubVoucher,
)
from adapters.db.models.person import Person
from adapters.db.models.product import Product
from app.core.responses import ApiError
from app.services import customer_club_service as points_svc
from app.core.customer_club_plugin_dependency import check_customer_club_plugin_active

_SEGMENT_KEYS = {
	"search",
	"rfm_segment",
	"min_balance_points",
	"max_balance_points",
	"min_recency_days",
	"max_recency_days",
	"min_frequency_count",
	"max_frequency_count",
	"sms_consent",
	"email_consent",
}
_REWARD_TYPES = {"discount_amount", "discount_percent", "free_product", "wallet_credit"}


def _as_decimal(value: Any, field: str, *, minimum: Decimal = Decimal("0")) -> Decimal:
	try:
		parsed = Decimal(str(value))
	except (InvalidOperation, TypeError, ValueError):
		raise ApiError("CUSTOMER_CLUB_INVALID_VALUE", f"{field} is invalid.", http_status=400)
	if not parsed.is_finite() or parsed < minimum:
		raise ApiError("CUSTOMER_CLUB_INVALID_VALUE", f"{field} must be at least {minimum}.", http_status=400)
	return parsed


def _as_positive_int(value: Any, field: str, *, maximum: int | None = None) -> int | None:
	if value in (None, ""):
		return None
	try:
		if isinstance(value, bool):
			raise ValueError
		numeric = Decimal(str(value))
		if not numeric.is_finite() or numeric != numeric.to_integral_value():
			raise ValueError
		parsed = int(numeric)
	except (TypeError, ValueError, InvalidOperation):
		raise ApiError("CUSTOMER_CLUB_INVALID_VALUE", f"{field} must be an integer.", http_status=400)
	if parsed < 1 or (maximum is not None and parsed > maximum):
		raise ApiError("CUSTOMER_CLUB_INVALID_VALUE", f"{field} is outside its allowed range.", http_status=400)
	return parsed


def _as_datetime(value: Any, field: str) -> datetime | None:
	if value in (None, ""):
		return None
	if isinstance(value, datetime):
		return value
	try:
		parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
		return parsed.astimezone(timezone.utc).replace(tzinfo=None) if parsed.tzinfo else parsed
	except (TypeError, ValueError):
		raise ApiError("CUSTOMER_CLUB_CAMPAIGN_DATETIME_INVALID", f"{field} must be an ISO datetime.", http_status=400)


def _voucher_code(db: Session, business_id: int) -> str:
	alphabet = string.ascii_uppercase + string.digits
	for _ in range(8):
		code = "CC" + "".join(secrets.choice(alphabet) for _ in range(10))
		if not db.query(CustomerClubVoucher.id).filter_by(business_id=business_id, code=code).first():
			return code
	raise ApiError("CUSTOMER_CLUB_VOUCHER_CODE_FAILED", "Could not allocate a unique voucher code.", http_status=503)


def reward_to_dict(row: CustomerClubReward) -> Dict[str, Any]:
	return {
		"id": row.id,
		"name": row.name,
		"description": row.description,
		"reward_type": row.reward_type,
		"points_cost": float(row.points_cost),
		"value": float(row.value),
		"product_id": row.product_id,
		"valid_days": row.valid_days,
		"max_issuances": row.max_issuances,
		"active": bool(row.active),
	}


def list_rewards(db: Session, business_id: int) -> List[Dict[str, Any]]:
	rows = db.query(CustomerClubReward).filter_by(business_id=business_id).order_by(CustomerClubReward.id.desc()).all()
	return [reward_to_dict(row) for row in rows]


def save_reward(db: Session, business_id: int, payload: Dict[str, Any], reward_id: int | None = None) -> Dict[str, Any]:
	row = None
	if reward_id is not None:
		row = db.query(CustomerClubReward).filter_by(id=reward_id, business_id=business_id).first()
		if not row:
			raise ApiError("CUSTOMER_CLUB_REWARD_NOT_FOUND", "Reward not found.", http_status=404)
	name = str(payload.get("name") or (row.name if row else "")).strip()
	if not name:
		raise ApiError("CUSTOMER_CLUB_REWARD_NAME_REQUIRED", "Reward name is required.", http_status=400)
	kind = str(payload.get("reward_type") or (row.reward_type if row else "discount_amount"))
	if kind not in _REWARD_TYPES:
		raise ApiError("CUSTOMER_CLUB_REWARD_TYPE_INVALID", "Unsupported reward type.", http_status=400)
	points = _as_decimal(payload.get("points_cost", row.points_cost if row else 0), "points_cost")
	value = _as_decimal(payload.get("value", row.value if row else 0), "value")
	if kind == "discount_percent" and value > 100:
		raise ApiError("CUSTOMER_CLUB_REWARD_PERCENT_INVALID", "Percentage value cannot exceed 100.", http_status=400)
	valid_days = _as_positive_int(payload.get("valid_days", row.valid_days if row else None), "valid_days", maximum=3650)
	if valid_days is not None and (valid_days < 1 or valid_days > 3650):
		raise ApiError("CUSTOMER_CLUB_REWARD_VALID_DAYS_INVALID", "valid_days must be between 1 and 3650.", http_status=400)
	max_issuances = _as_positive_int(payload.get("max_issuances", row.max_issuances if row else None), "max_issuances")
	if max_issuances is not None and max_issuances < 1:
		raise ApiError("CUSTOMER_CLUB_REWARD_LIMIT_INVALID", "max_issuances must be positive.", http_status=400)
	if row is None:
		row = CustomerClubReward(business_id=business_id, name=name, reward_type=kind, points_cost=points, value=value)
		db.add(row)
	row.name = name[:160]
	row.description = str(payload.get("description") if "description" in payload else row.description or "").strip()[:4000] or None
	row.reward_type = kind
	row.points_cost = points
	row.value = value
	product_id = payload.get("product_id", row.product_id)
	if kind == "free_product" and product_id is None:
		raise ApiError("CUSTOMER_CLUB_REWARD_PRODUCT_REQUIRED", "free_product rewards require a product_id.", http_status=400)
	product_id = _as_positive_int(product_id, "product_id")
	if product_id is not None and not db.query(Product.id).filter_by(id=product_id, business_id=business_id).first():
		raise ApiError("CUSTOMER_CLUB_REWARD_PRODUCT_NOT_FOUND", "Product does not belong to this business.", http_status=400)
	row.product_id = product_id
	row.valid_days = valid_days
	row.max_issuances = max_issuances
	row.active = bool(payload.get("active", row.active if reward_id else True))
	db.commit()
	db.refresh(row)
	return reward_to_dict(row)


def issue_voucher(
	db: Session,
	*,
	business_id: int,
	person_id: int,
	reward_type: str,
	value: Decimal,
	valid_days: int | None,
	reward_id: int | None = None,
	product_id: int | None = None,
	campaign_id: int | None = None,
) -> CustomerClubVoucher:
	if reward_type not in _REWARD_TYPES:
		raise ApiError("CUSTOMER_CLUB_REWARD_TYPE_INVALID", "Unsupported voucher reward type.", http_status=400)
	expires = datetime.utcnow() + timedelta(days=valid_days) if valid_days else None
	row = CustomerClubVoucher(
		business_id=business_id,
		person_id=person_id,
		reward_id=reward_id,
		product_id=product_id,
		campaign_id=campaign_id,
		code=_voucher_code(db, business_id),
		status="issued",
		value=value,
		reward_type=reward_type,
		expires_at=expires,
	)
	db.add(row)
	db.flush()
	return row


def redeem_reward(db: Session, business_id: int, person_id: int, reward_id: int) -> Dict[str, Any]:
	if not db.query(Person.id).filter_by(id=person_id, business_id=business_id).first():
		raise ApiError("CUSTOMER_CLUB_PERSON_NOT_FOUND", "Person not found.", http_status=404)
	reward = db.query(CustomerClubReward).filter_by(id=reward_id, business_id=business_id, active=True).with_for_update().first()
	if not reward:
		raise ApiError("CUSTOMER_CLUB_REWARD_NOT_FOUND", "Active reward not found.", http_status=404)
	if reward.max_issuances is not None:
		issued_count = db.query(CustomerClubVoucher.id).filter_by(reward_id=reward.id).count()
		if issued_count >= reward.max_issuances:
			raise ApiError("CUSTOMER_CLUB_REWARD_LIMIT_REACHED", "This reward has reached its issuance limit.", http_status=409)
	bal = points_svc._locked_balance_row(db, business_id, person_id)
	if points_svc.usable_points_balance(db, business_id, person_id, bal.balance_points) < reward.points_cost:
		raise ApiError("CUSTOMER_CLUB_INSUFFICIENT_POINTS", "Insufficient points for this reward.", http_status=409)
	if reward.points_cost > 0:
		bal.balance_points -= reward.points_cost
		bal.updated_at = datetime.utcnow()
		points_svc._append_ledger(
			db,
			business_id=business_id,
			person_id=person_id,
			delta_points=-reward.points_cost,
			balance_after=bal.balance_points,
			transaction_type="reward_redeem",
			description=f"مصرف امتیاز برای جایزهٔ {reward.name}",
		)
	voucher = issue_voucher(
		db,
		business_id=business_id,
		person_id=person_id,
		reward_type=reward.reward_type,
		value=reward.value,
		valid_days=reward.valid_days,
		reward_id=reward.id,
		product_id=reward.product_id,
	)
	db.commit()
	return voucher_to_dict(voucher)


def voucher_to_dict(row: CustomerClubVoucher) -> Dict[str, Any]:
	status = row.status
	if status == "issued" and row.expires_at and row.expires_at <= datetime.utcnow():
		status = "expired"
	return {
		"id": row.id,
		"person_id": row.person_id,
		"reward_id": row.reward_id,
		"product_id": row.product_id,
		"campaign_id": row.campaign_id,
		"code": row.code,
		"status": status,
		"reward_type": row.reward_type,
		"value": float(row.value),
		"expires_at": row.expires_at.isoformat() if row.expires_at else None,
		"redeemed_at": row.redeemed_at.isoformat() if row.redeemed_at else None,
		"created_at": row.created_at.isoformat() if row.created_at else None,
	}


def list_vouchers(db: Session, business_id: int, person_id: int | None = None) -> List[Dict[str, Any]]:
	q = db.query(CustomerClubVoucher).filter_by(business_id=business_id)
	if person_id is not None:
		q = q.filter_by(person_id=person_id)
	return [voucher_to_dict(row) for row in q.order_by(CustomerClubVoucher.created_at.desc()).limit(500).all()]


def set_member_consent(db: Session, business_id: int, person_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	person = db.query(Person).filter_by(id=person_id, business_id=business_id).first()
	if not person:
		raise ApiError("CUSTOMER_CLUB_PERSON_NOT_FOUND", "Person not found.", http_status=404)
	member = db.query(CustomerClubMember).filter_by(business_id=business_id, person_id=person_id).with_for_update().first()
	if not member:
		member = CustomerClubMember(business_id=business_id, person_id=person_id)
		db.add(member)
		db.flush()
	if not member.referral_code:
		alphabet = string.ascii_uppercase + string.digits
		for _ in range(8):
			code = "R" + "".join(secrets.choice(alphabet) for _ in range(9))
			if not db.query(CustomerClubMember.id).filter_by(business_id=business_id, referral_code=code).first():
				member.referral_code = code
				break
	referral_code = str(payload.get("referral_code") or "").strip().upper()
	if referral_code and not member.referrer_person_id:
		referrer = db.query(CustomerClubMember).filter_by(business_id=business_id, referral_code=referral_code).first()
		if not referrer or referrer.person_id == person_id:
			raise ApiError("CUSTOMER_CLUB_REFERRAL_CODE_INVALID", "Referral code is invalid.", http_status=400)
		member.referrer_person_id = referrer.person_id
	for channel in ("sms", "email"):
		key = f"{channel}_consent"
		if key in payload:
			if not isinstance(payload[key], bool):
				raise ApiError("CUSTOMER_CLUB_CONSENT_INVALID", f"{key} must be true or false.", http_status=400)
			value = payload[key]
			setattr(member, key, value)
			setattr(member, f"{channel}_consent_at", datetime.utcnow() if value else None)
	db.commit()
	return {
		"person_id": member.person_id,
		"joined_at": member.joined_at.isoformat(),
		"referral_code": member.referral_code,
		"referrer_person_id": member.referrer_person_id,
		"sms_consent": member.sms_consent,
		"sms_consent_at": member.sms_consent_at.isoformat() if member.sms_consent_at else None,
		"email_consent": member.email_consent,
		"email_consent_at": member.email_consent_at.isoformat() if member.email_consent_at else None,
	}


def submit_survey_response(db: Session, business_id: int, person_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	person = db.query(Person).filter_by(id=person_id, business_id=business_id).first()
	if not person:
		raise ApiError("CUSTOMER_CLUB_PERSON_NOT_FOUND", "Person not found.", http_status=404)
	key = str(payload.get("survey_key") or "").strip()
	if not key or len(key) > 80:
		raise ApiError("CUSTOMER_CLUB_SURVEY_KEY_REQUIRED", "survey_key is required and must be at most 80 characters.", http_status=400)
	score = payload.get("score")
	if score is not None:
		try:
			numeric_score = Decimal(str(score))
			if isinstance(score, bool) or not numeric_score.is_finite() or numeric_score != numeric_score.to_integral_value():
				raise ValueError
			score = int(numeric_score)
		except (TypeError, ValueError, InvalidOperation):
			raise ApiError("CUSTOMER_CLUB_SURVEY_SCORE_INVALID", "score must be an integer from 0 to 10.", http_status=400)
		if score < 0 or score > 10:
			raise ApiError("CUSTOMER_CLUB_SURVEY_SCORE_INVALID", "score must be between 0 and 10.", http_status=400)
	member = db.query(CustomerClubMember).filter_by(business_id=business_id, person_id=person_id).with_for_update().first()
	if not member:
		member = CustomerClubMember(business_id=business_id, person_id=person_id)
		db.add(member)
		db.flush()
	existing = db.query(CustomerClubSurveyResponse).filter_by(business_id=business_id, person_id=person_id, survey_key=key).first()
	if existing:
		return {"id": existing.id, "points_awarded": float(existing.points_awarded), "duplicate": True}
	settings = db.query(CustomerClubSettings).filter_by(business_id=business_id).first()
	points = settings.survey_points if settings else Decimal("0")
	response = CustomerClubSurveyResponse(business_id=business_id, person_id=person_id, survey_key=key,
		score=score, comment=str(payload.get("comment") or "").strip()[:2000] or None,
		points_awarded=points)
	db.add(response)
	if points > 0:
		balance = points_svc._locked_balance_row(db, business_id, person_id)
		balance.balance_points += points
		balance.updated_at = datetime.utcnow()
		points_svc._append_ledger(db, business_id=business_id, person_id=person_id, delta_points=points,
			balance_after=balance.balance_points, transaction_type="survey_reward", description=f"پاداش نظرسنجی {key}")
	apply_event_campaigns(db, business_id, person_id, "survey")
	db.commit()
	return {"id": response.id, "points_awarded": float(points), "duplicate": False}


def _segment_query(db: Session, business_id: int, filters: Dict[str, Any]):
	unknown = set(filters) - _SEGMENT_KEYS
	if unknown:
		raise ApiError("CUSTOMER_CLUB_SEGMENT_FILTER_INVALID", f"Unsupported segment filters: {', '.join(sorted(unknown))}.", http_status=400)
	settings = db.query(CustomerClubSettings).filter_by(business_id=business_id).first()
	q = (
		db.query(Person, CustomerClubBalance.balance_points, CustomerClubRfmSnapshot, CustomerClubMember)
		.outerjoin(CustomerClubBalance, and_(CustomerClubBalance.person_id == Person.id, CustomerClubBalance.business_id == business_id))
		.outerjoin(CustomerClubRfmSnapshot, and_(CustomerClubRfmSnapshot.person_id == Person.id, CustomerClubRfmSnapshot.business_id == business_id))
		.outerjoin(CustomerClubMember, and_(CustomerClubMember.person_id == Person.id, CustomerClubMember.business_id == business_id))
		.filter(Person.business_id == business_id)
	)
	if settings is None or settings.require_customer_person_type:
		q = q.filter(Person.person_types.ilike("%مشتری%"))
	if filters.get("search"):
		term = f"%{str(filters['search']).strip()}%"
		q = q.filter(or_(Person.alias_name.ilike(term), Person.company_name.ilike(term), Person.mobile.ilike(term), cast(Person.code, String).ilike(term)))
	if filters.get("rfm_segment"):
		q = q.filter(CustomerClubRfmSnapshot.segment_label == str(filters["rfm_segment"]))
	for key, column in (
		("min_balance_points", CustomerClubBalance.balance_points),
		("max_balance_points", CustomerClubBalance.balance_points),
		("min_recency_days", CustomerClubRfmSnapshot.recency_days),
		("max_recency_days", CustomerClubRfmSnapshot.recency_days),
		("min_frequency_count", CustomerClubRfmSnapshot.frequency_count),
		("max_frequency_count", CustomerClubRfmSnapshot.frequency_count),
	):
		if filters.get(key) is not None:
			try:
				if key.endswith(("recency_days", "frequency_count")):
					numeric = Decimal(str(filters[key]))
					if not numeric.is_finite() or numeric != numeric.to_integral_value():
						raise ValueError
					value = int(numeric)
				else:
					value = Decimal(str(filters[key]))
			except (TypeError, ValueError, InvalidOperation):
				raise ApiError("CUSTOMER_CLUB_SEGMENT_FILTER_INVALID", f"{key} must be numeric.", http_status=400)
			if (isinstance(value, Decimal) and not value.is_finite()) or value < 0:
				raise ApiError("CUSTOMER_CLUB_SEGMENT_FILTER_INVALID", f"{key} cannot be negative.", http_status=400)
			q = q.filter(column >= value if key.startswith("min_") else column <= value)
	if filters.get("sms_consent") is not None:
		if not isinstance(filters["sms_consent"], bool):
			raise ApiError("CUSTOMER_CLUB_SEGMENT_FILTER_INVALID", "sms_consent must be true or false.", http_status=400)
		q = q.filter(CustomerClubMember.sms_consent.is_(filters["sms_consent"]))
	if filters.get("email_consent") is not None:
		if not isinstance(filters["email_consent"], bool):
			raise ApiError("CUSTOMER_CLUB_SEGMENT_FILTER_INVALID", "email_consent must be true or false.", http_status=400)
		q = q.filter(CustomerClubMember.email_consent.is_(filters["email_consent"]))
	return q.order_by(Person.id.asc())


def preview_segment(db: Session, business_id: int, filters: Dict[str, Any], limit: int = 100) -> Dict[str, Any]:
	limit = min(max(int(limit), 1), 500)
	q = _segment_query(db, business_id, filters)
	total = q.count()
	rows = q.limit(limit).all()
	return {
		"total": int(total),
		"truncated": total > len(rows),
		"items": [
			{"person_id": p.id, "name": p.alias_name, "mobile": p.mobile, "balance_points": float(balance or 0),
			 "segment": snap.segment_label if snap else None, "recency_days": snap.recency_days if snap else None,
			 "frequency_count": snap.frequency_count if snap else None, "sms_consent": bool(member.sms_consent) if member else False}
			for p, balance, snap, member in rows
		],
	}


def campaign_to_dict(row: CustomerClubCampaign, db: Session | None = None) -> Dict[str, Any]:
	return {
		"id": row.id, "name": row.name, "description": row.description,
		"trigger_type": row.trigger_type, "segment": row.segment_json or {},
		"reward_type": row.reward_type, "reward_value": float(row.reward_value),
		"min_purchase_amount": float(row.min_purchase_amount) if row.min_purchase_amount is not None else None,
		"reward_valid_days": row.reward_valid_days, "message_template": row.message_template,
		"channel": row.channel, "starts_at": row.starts_at.isoformat() if row.starts_at else None,
		"ends_at": row.ends_at.isoformat() if row.ends_at else None, "status": row.status,
	}


def list_campaigns(db: Session, business_id: int) -> List[Dict[str, Any]]:
	return [campaign_to_dict(row) for row in db.query(CustomerClubCampaign).filter_by(business_id=business_id).order_by(CustomerClubCampaign.id.desc()).all()]


def save_campaign(db: Session, business_id: int, payload: Dict[str, Any], user_id: int, campaign_id: int | None = None) -> Dict[str, Any]:
	row = None
	if campaign_id is not None:
		row = db.query(CustomerClubCampaign).filter_by(id=campaign_id, business_id=business_id).first()
		if not row:
			raise ApiError("CUSTOMER_CLUB_CAMPAIGN_NOT_FOUND", "Campaign not found.", http_status=404)
	name = str(payload.get("name") or (row.name if row else "")).strip()
	if not name:
		raise ApiError("CUSTOMER_CLUB_CAMPAIGN_NAME_REQUIRED", "Campaign name is required.", http_status=400)
	trigger = str(payload.get("trigger_type") or (row.trigger_type if row else "manual"))
	if trigger not in {"manual", "purchase", "inactivity", "referral", "survey", "scheduled"}:
		raise ApiError("CUSTOMER_CLUB_CAMPAIGN_TRIGGER_INVALID", "Unsupported campaign trigger.", http_status=400)
 
	segment = payload.get("segment", row.segment_json if row else {}) or {}
	if not isinstance(segment, dict):
		raise ApiError("CUSTOMER_CLUB_SEGMENT_INVALID", "segment must be an object.", http_status=400)
	# Validate field names and operators before persisting untrusted JSON.
	_segment_query(db, business_id, segment)
	reward_type = str(payload.get("reward_type") or (row.reward_type if row else "points"))
	if reward_type not in {"points", *_REWARD_TYPES}:
		raise ApiError("CUSTOMER_CLUB_CAMPAIGN_REWARD_INVALID", "Unsupported campaign reward type.", http_status=400)
	reward_value = _as_decimal(payload.get("reward_value", row.reward_value if row else 0), "reward_value")
	if reward_type == "discount_percent" and reward_value > 100:
		raise ApiError("CUSTOMER_CLUB_CAMPAIGN_PERCENT_INVALID", "Percentage value cannot exceed 100.", http_status=400)
	if reward_type == "free_product":
		raise ApiError("CUSTOMER_CLUB_CAMPAIGN_PRODUCT_UNSUPPORTED", "Create a product reward in the reward catalogue instead of a campaign.", http_status=400)
	channel = str(payload.get("channel") or (row.channel if row else "none"))
	if channel not in {"none", "sms", "email"}:
		raise ApiError("CUSTOMER_CLUB_CAMPAIGN_CHANNEL_INVALID", "Supported channels are none, SMS, and email.", http_status=400)
	status = str(payload.get("status") or (row.status if row else "draft"))
	if status not in {"draft", "active", "paused", "completed"}:
		raise ApiError("CUSTOMER_CLUB_CAMPAIGN_STATUS_INVALID", "Unsupported campaign status.", http_status=400)
	if row is None:
		row = CustomerClubCampaign(business_id=business_id, name=name, created_by_user_id=user_id)
		db.add(row)
	row.name = name[:160]
	row.description = str(payload.get("description") if "description" in payload else row.description or "").strip()[:4000] or None
	row.trigger_type = trigger
	row.segment_json = segment
	row.reward_type = reward_type
	row.reward_value = reward_value
	if "min_purchase_amount" in payload:
		row.min_purchase_amount = _as_decimal(payload.get("min_purchase_amount"), "min_purchase_amount") if payload.get("min_purchase_amount") is not None else None
	valid_days = payload.get("reward_valid_days", row.reward_valid_days)
	row.reward_valid_days = _as_positive_int(valid_days, "reward_valid_days", maximum=3650)
	row.message_template = str(payload.get("message_template") if "message_template" in payload else row.message_template or "").strip()[:1000] or None
	row.channel = channel
	row.status = status
	row.starts_at = _as_datetime(payload.get("starts_at", row.starts_at), "starts_at")
	row.ends_at = _as_datetime(payload.get("ends_at", row.ends_at), "ends_at")
	if row.starts_at and row.ends_at and row.starts_at >= row.ends_at:
		raise ApiError("CUSTOMER_CLUB_CAMPAIGN_WINDOW_INVALID", "ends_at must be after starts_at.", http_status=400)
	db.commit()
	db.refresh(row)
	return campaign_to_dict(row)


def run_campaign(db: Session, business_id: int, campaign_id: int, *, limit: int = 10000,
		person_id: int | None = None) -> Dict[str, Any]:
	campaign = db.query(CustomerClubCampaign).filter_by(id=campaign_id, business_id=business_id).with_for_update().first()
	if not campaign:
		raise ApiError("CUSTOMER_CLUB_CAMPAIGN_NOT_FOUND", "Campaign not found.", http_status=404)
	if campaign.status != "active" and not (campaign.status == "completed" and campaign.channel in {"sms", "email"}):
		raise ApiError("CUSTOMER_CLUB_CAMPAIGN_NOT_ACTIVE", "Only active campaigns can be run.", http_status=409)
	now = datetime.utcnow()
	if campaign.starts_at and campaign.starts_at > now or campaign.ends_at and campaign.ends_at <= now:
		raise ApiError("CUSTOMER_CLUB_CAMPAIGN_OUTSIDE_WINDOW", "Campaign is outside its active time window.", http_status=409)
	if campaign.trigger_type in {"purchase", "referral", "survey"} or campaign.status == "completed":
		# The award record captures the eligible audience at event time. Sending
		# a retry later must not re-evaluate a changing RFM/balance segment.
		query = _segment_query(db, business_id, {}).filter(
			Person.id.in_(db.query(CustomerClubCampaignMember.person_id).filter_by(campaign_id=campaign.id))
		)
	else:
		query = _segment_query(db, business_id, campaign.segment_json or {})
	if person_id is not None:
		query = query.filter(Person.id == int(person_id))
	rows = query.limit(min(max(limit, 1), 10000)).all()
	issued = sent = skipped = errors = 0
	for person, _balance, _rfm, member in rows:
		entry = db.query(CustomerClubCampaignMember).filter_by(campaign_id=campaign.id, person_id=person.id).with_for_update().first()
		if campaign.trigger_type in {"purchase", "referral", "survey"} and entry is None:
			skipped += 1
			continue
		if entry is None:
			voucher = None
			if campaign.reward_type == "points":
				bal = points_svc._locked_balance_row(db, business_id, person.id)
				bal.balance_points += campaign.reward_value
				bal.updated_at = now
				points_svc._append_ledger(db, business_id=business_id, person_id=person.id, delta_points=campaign.reward_value,
					balance_after=bal.balance_points, transaction_type="campaign_reward", description=f"پاداش کمپین {campaign.name}")
			elif campaign.reward_type in _REWARD_TYPES:
				voucher = issue_voucher(db, business_id=business_id, person_id=person.id, reward_type=campaign.reward_type,
					value=campaign.reward_value, valid_days=campaign.reward_valid_days, campaign_id=campaign.id)
			entry = CustomerClubCampaignMember(campaign_id=campaign.id, business_id=business_id,
				person_id=person.id, status="rewarded", reward_value=campaign.reward_value)
			if voucher is not None:
				entry.voucher_code = voucher.code
			db.add(entry)
			issued += 1
		elif campaign.channel not in {"sms", "email"} or entry.sent_at:
					# The idempotency record prevents re-issuing rewards; failed or
					# consent-skipped messages can be retried after they are corrected.
			skipped += 1
			continue
		if campaign.channel in {"sms", "email"}:
			consented = bool(member and (member.sms_consent if campaign.channel == "sms" else member.email_consent))
			address = person.mobile if campaign.channel == "sms" else person.email
			if not consented or not address:
				entry.status = f"{campaign.channel}_skipped_no_consent"
				skipped += 1
				continue
			try:
				text = (campaign.message_template or "{name} عزیز، پاداش باشگاه شما آماده است: {voucher_code}")
				text = text.replace("{name}", person.alias_name).replace("{points}", str(campaign.reward_value))
				text = text.replace("{voucher_code}", entry.voucher_code or "")
				if campaign.channel == "sms":
					from app.services.system_settings_service import get_effective_notifications_settings
					from app.services.providers.sms_provider import SmsProvider
					cfg = get_effective_notifications_settings(db)
					sms = SmsProvider(provider_name=cfg.get("sms_provider_name"), api_key=cfg.get("sms_api_key"),
						sender=cfg.get("sms_sender"), username=cfg.get("sms_provider_username"), password=cfg.get("sms_provider_password"),
						is_flash=cfg.get("sms_is_flash", False))
					if not sms.is_configured():
						entry.status, entry.send_error = "sms_failed", "SMS provider is not configured"
						errors += 1
						continue
					ok, _message_id, error = sms.send_text_with_details(to_phone=address, text=text)
				else:
					from app.services.email_service import EmailService
					ok = EmailService(db).send_email(to=address, subject=campaign.name, body=text)
					error = None if ok else "Email provider is not configured or delivery failed"
				if ok:
					entry.status, entry.sent_at, entry.send_error = "sent", now, None
					sent += 1
				else:
					entry.status, entry.send_error = f"{campaign.channel}_failed", str(error or f"{campaign.channel} send failed")[:2000]
					errors += 1
			except Exception as exc:
				entry.status, entry.send_error = f"{campaign.channel}_failed", str(exc)[:2000]
				errors += 1
		db.flush()
	if campaign.trigger_type in {"inactivity", "scheduled"} and person_id is None:
		campaign.status = "completed"
	db.commit()
	return {"audience_size": len(rows), "rewards_issued": issued, "messages_sent": sent, "skipped": skipped, "errors": errors,
		"truncated": len(rows) >= min(max(limit, 1), 10000)}


def _award_campaign_to_member(db: Session, campaign: CustomerClubCampaign, person_id: int, now: datetime) -> bool:
	if db.query(CustomerClubCampaignMember.id).filter_by(campaign_id=campaign.id, person_id=person_id).first():
		return False
	voucher = None
	if campaign.reward_type == "points":
		balance = points_svc._locked_balance_row(db, int(campaign.business_id), person_id)
		balance.balance_points += campaign.reward_value
		balance.updated_at = now
		points_svc._append_ledger(db, business_id=int(campaign.business_id), person_id=person_id,
			delta_points=campaign.reward_value, balance_after=balance.balance_points,
			transaction_type="campaign_reward", description=f"پاداش کمپین {campaign.name}")
	elif campaign.reward_type in _REWARD_TYPES:
		voucher = issue_voucher(db, business_id=int(campaign.business_id), person_id=person_id,
			reward_type=campaign.reward_type, value=campaign.reward_value,
			valid_days=campaign.reward_valid_days, campaign_id=campaign.id)
	db.add(CustomerClubCampaignMember(campaign_id=campaign.id, business_id=int(campaign.business_id),
		person_id=person_id, status="rewarded", reward_value=campaign.reward_value,
		voucher_code=voucher.code if voucher else None))
	return True


def apply_event_campaigns(db: Session, business_id: int, person_id: int, trigger_type: str) -> int:
	"""Award one-time event-triggered campaigns to a member in the triggering transaction."""
	if trigger_type not in {"referral", "survey"}:
		return 0
	now = datetime.utcnow()
	campaigns = db.query(CustomerClubCampaign).filter(
		CustomerClubCampaign.business_id == business_id,
		CustomerClubCampaign.status == "active",
		CustomerClubCampaign.trigger_type == trigger_type,
		or_(CustomerClubCampaign.starts_at.is_(None), CustomerClubCampaign.starts_at <= now),
		or_(CustomerClubCampaign.ends_at.is_(None), CustomerClubCampaign.ends_at > now),
	).order_by(CustomerClubCampaign.id.asc()).limit(100).all()
	issued = 0
	for campaign in campaigns:
		if _segment_query(db, business_id, campaign.segment_json or {}).filter(Person.id == person_id).first():
			issued += int(_award_campaign_to_member(db, campaign, person_id, now))
	db.flush()
	return issued


def apply_purchase_campaigns(db: Session, business_id: int, person_id: int, purchase_amount: Decimal) -> int:
	"""Award eligible one-time purchase-trigger campaigns inside the invoice transaction."""
	now = datetime.utcnow()
	campaigns = db.query(CustomerClubCampaign).filter(
		CustomerClubCampaign.business_id == business_id,
		CustomerClubCampaign.status == "active",
		CustomerClubCampaign.trigger_type == "purchase",
		or_(CustomerClubCampaign.starts_at.is_(None), CustomerClubCampaign.starts_at <= now),
		or_(CustomerClubCampaign.ends_at.is_(None), CustomerClubCampaign.ends_at > now),
	).order_by(CustomerClubCampaign.id.asc()).limit(100).all()
	issued = 0
	for campaign in campaigns:
		if campaign.min_purchase_amount is not None and purchase_amount < campaign.min_purchase_amount:
			continue
		if not _segment_query(db, business_id, campaign.segment_json or {}).filter(Person.id == person_id).first():
			continue
		issued += int(_award_campaign_to_member(db, campaign, person_id, now))
	db.flush()
	return issued


def run_due_campaigns(db: Session, *, now: datetime | None = None) -> Dict[str, Any]:
	"""Run scheduled inactivity campaigns once when their configured start time arrives."""
	now = now or datetime.utcnow()
	rows = db.query(CustomerClubCampaign).filter(
		CustomerClubCampaign.status == "active",
		CustomerClubCampaign.trigger_type.in_(("inactivity", "scheduled")),
		or_(CustomerClubCampaign.starts_at.is_(None), CustomerClubCampaign.starts_at <= now),
		or_(CustomerClubCampaign.ends_at.is_(None), CustomerClubCampaign.ends_at > now),
	).order_by(CustomerClubCampaign.id.asc()).limit(100).all()
	completed = errors = 0
	for campaign in rows:
		if not check_customer_club_plugin_active(db, int(campaign.business_id)):
			continue
		try:
			run_campaign(db, int(campaign.business_id), int(campaign.id))
			completed += 1
		except Exception:
			db.rollback()
			errors += 1
	return {"campaigns_run": completed, "errors": errors}


def campaign_stats(db: Session, business_id: int, campaign_id: int) -> Dict[str, Any]:
	if not db.query(CustomerClubCampaign.id).filter_by(id=campaign_id, business_id=business_id).first():
		raise ApiError("CUSTOMER_CLUB_CAMPAIGN_NOT_FOUND", "Campaign not found.", http_status=404)
	rows = db.query(CustomerClubCampaignMember.status, CustomerClubCampaignMember.conversion_amount, CustomerClubCampaignMember.converted_at).filter(CustomerClubCampaignMember.campaign_id == campaign_id).all()
	counts: Dict[str, int] = {}
	converted = 0
	revenue = Decimal("0")
	for status, amount, converted_at in rows:
		counts[status] = counts.get(status, 0) + 1
		if converted_at:
			converted += 1
			revenue += amount or Decimal("0")
	return {"campaign_id": campaign_id, "members": sum(counts.values()), "by_status": counts,
		"attributed_conversions": converted, "attributed_revenue": float(revenue)}


def list_member_profile(db: Session, business_id: int, person_id: int) -> Dict[str, Any]:
	person = db.query(Person).filter_by(id=person_id, business_id=business_id).first()
	if not person:
		raise ApiError("CUSTOMER_CLUB_PERSON_NOT_FOUND", "Person not found.", http_status=404)
	member = db.query(CustomerClubMember).filter_by(business_id=business_id, person_id=person_id).first()
	balance = points_svc.get_person_balance(db, business_id, person_id)
	ledger, _ = points_svc.list_ledger(db, business_id, person_id=person_id, limit=20, skip=0)
	return {"person_id": person_id, "name": person.alias_name, "mobile": person.mobile, "joined_at": member.joined_at.isoformat() if member else None,
		"referral_code": member.referral_code if member else None,
		"referrer_person_id": member.referrer_person_id if member else None,
		"sms_consent": bool(member.sms_consent) if member else False, "email_consent": bool(member.email_consent) if member else False,
		"balance": balance, "ledger": ledger, "vouchers": list_vouchers(db, business_id, person_id)}
