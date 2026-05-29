from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple
from datetime import datetime, timedelta, date
from decimal import Decimal
import math
import calendar

import structlog
from sqlalchemy.orm import Session
from sqlalchemy import and_, func, asc

from app.core.responses import ApiError
from adapters.db.models.document_monetization import (
	DocumentSubscriptionPlan,
	BusinessDocumentSubscription,
	DocumentUsagePolicy,
	DocumentUsageCharge,
	DocumentUsagePeriod,
	DocumentUsageCursor,
)
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.account import Account
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.currency import Currency
from adapters.db.models.wallet import WalletAccount
from app.services.wallet_service import (
	charge_wallet_for_service,
	_get_fixed_account_by_code,
	_resolve_wallet_currency_id,
	_create_simple_document,
	_get_current_fiscal_year as _get_fiscal_year_wallet,
)
from app.services.system_settings_service import (
	get_wallet_settings,
	DEFAULT_WALLET_CURRENCY_CODE,
	get_default_document_policies,
)
from app.services.business_service import ensure_wallet_currency_in_business


logger = structlog.get_logger()


def _decimal(value: Any) -> Decimal:
	return Decimal(str(value or 0))


def _get_current_fiscal_year(db: Session, business_id: int) -> FiscalYear:
	"""دریافت سال مالی جاری کسب‌وکار"""
	try:
		return _get_fiscal_year_wallet(db, business_id)
	except Exception:
		# Fallback implementation
		from datetime import date
		today = date.today()
		fy = (
			db.query(FiscalYear)
			.filter(
				and_(
					FiscalYear.business_id == business_id,
					FiscalYear.start_date <= today,
					FiscalYear.end_date >= today,
				)
			)
			.first()
		)
		if not fy:
			# Try to get last fiscal year
			fy = (
				db.query(FiscalYear)
				.filter(FiscalYear.business_id == business_id)
				.order_by(FiscalYear.start_date.desc())
				.first()
			)
		if not fy:
			raise ApiError("FISCAL_YEAR_NOT_FOUND", "سال مالی جاری یافت نشد", http_status=404)
		return fy


def _ensure_document_monetization_expense_account(db: Session) -> Account:
	"""
	بررسی و ایجاد/به‌روزرسانی حساب هزینه اشتراک و خدمات سیستم (70507)
	"""
	account = db.query(Account).filter(
		and_(
			Account.code == "70507",
			Account.business_id.is_(None)
		)
	).first()
	
	expected_name = "هزینه اشتراک و خدمات سیستم"
	
	if not account:
		try:
			parent_account = _get_fixed_account_by_code(db, "705")
			parent_id = parent_account.id if parent_account else None
		except Exception:
			parent_id = None
		
		account = Account(
			name=expected_name,
			code="70507",
			account_type="accounting_document",
			business_id=None,
			parent_id=parent_id
		)
		db.add(account)
		db.flush()
		logger.info("created_document_monetization_expense_account", account_id=account.id)
	else:
		if account.name != expected_name:
			account.name = expected_name
			if account.account_type != "accounting_document":
				account.account_type = "accounting_document"
			db.flush()
			logger.info("updated_document_monetization_expense_account", account_id=account.id)
	
	return account


def _create_document_monetization_accounting_document(
	db: Session,
	business_id: int,
	user_id: int,
	charge: DocumentUsageCharge,
	amount: Decimal,
	charge_type: str,
) -> int:
	"""
	ایجاد سند حسابداری برای تراکنش‌های درآمدزایی اسناد
	
	Args:
		db: Database session
		business_id: شناسه کسب‌وکار
		user_id: شناسه کاربر
		charge: DocumentUsageCharge object
		amount: مبلغ تراکنش
		charge_type: نوع هزینه (subscription_fee, per_document, volume_cycle)
	
	Returns:
		شناسه سند حسابداری ایجاد شده
	"""
	from datetime import date as date_type
	
	try:
		# بررسی و اضافه کردن ارز کیف پول به کسب و کار در صورت نیاز
		try:
			ensure_wallet_currency_in_business(db, business_id)
		except Exception as e:
			logger.warning("failed_to_ensure_wallet_currency", business_id=business_id, error=str(e))
		
		# دریافت حساب‌ها
		expense_account = _ensure_document_monetization_expense_account(db)
		wallet_account = _get_fixed_account_by_code(db, "10205")  # حساب کیف پول
		
		# دریافت سال مالی
		fiscal_year = _get_current_fiscal_year(db, business_id)
		
		# تولید کد سند
		doc_date = charge.created_at.date() if charge.created_at else date_type.today()
		prefix = f"PY-{doc_date.strftime('%Y%m%d')}"
		last_doc = (
			db.query(Document)
			.filter(
				and_(
					Document.business_id == business_id,
					Document.code.like(f"{prefix}-%"),
				)
			)
			.order_by(Document.code.desc())
			.first()
		)
		if last_doc:
			try:
				last_num = int(str(last_doc.code).split("-")[-1])
				next_num = last_num + 1
			except Exception:
				next_num = 1
		else:
			next_num = 1
		doc_code = f"{prefix}-{next_num:04d}"
		
		# تعیین توضیحات بر اساس نوع charge
		charge_type_names = {
			"subscription_fee": "هزینه اشتراک نامحدود",
			"per_document": "هزینه ثبت سند",
			"volume_cycle": "هزینه دوره حجمی",
			"manual": "هزینه دستی",
		}
		type_name = charge_type_names.get(charge_type, "هزینه خدمات سیستم")
		
		description = charge.description or f"{type_name} - {charge.id}"
		
		# ایجاد سند
		document = Document(
			business_id=business_id,
			fiscal_year_id=fiscal_year.id,
			code=doc_code,
			document_type="payment",
			document_date=doc_date,
			currency_id=charge.currency_id,
			created_by_user_id=user_id,
			registered_at=datetime.utcnow(),
			is_proforma=False,
			description=description,
			extra_info={
				"source": "document_monetization",
				"charge_id": charge.id,
				"charge_type": charge_type,
				"policy_id": charge.policy_id,
			},
		)
		db.add(document)
		db.flush()
		
		# ایجاد ردیف‌های حسابداری
		# ردیف 1: بدهکار - هزینه اشتراک و خدمات سیستم
		db.add(DocumentLine(
			document_id=document.id,
			account_id=expense_account.id,
			debit=amount,
			credit=Decimal("0"),
			description=type_name,
		))
		
		# ردیف 2: بستانکار - کیف پول
		db.add(DocumentLine(
			document_id=document.id,
			account_id=wallet_account.id,
			debit=Decimal("0"),
			credit=amount,
			description="پرداخت از کیف پول",
		))
		
		db.flush()
		logger.info(
			"created_document_monetization_accounting_document",
			document_id=document.id,
			charge_id=charge.id,
			charge_type=charge_type,
			amount=float(amount),
		)
		return int(document.id)
	except Exception as e:
		logger.error(
			"failed_to_create_document_monetization_accounting_document",
			charge_id=charge.id,
			error=str(e),
			error_type=type(e).__name__,
			exc_info=True,
		)
		raise


def _serialize_plan(plan: DocumentSubscriptionPlan) -> Dict[str, Any]:
	return {
		"id": plan.id,
		"name": plan.name,
		"code": plan.code,
		"description": plan.description,
		"period_months": plan.period_months,
		"price": float(plan.price or 0),
		"currency_id": plan.currency_id,
		"currency_code": plan.currency.code if plan.currency else None,
		"is_active": plan.is_active,
		"created_at": plan.created_at,
		"updated_at": plan.updated_at,
	}


def _get_wallet_currency(db: Session) -> tuple[int, str]:
	settings = get_wallet_settings(db)
	code = (settings.get("wallet_base_currency_code") or DEFAULT_WALLET_CURRENCY_CODE or "").strip() or DEFAULT_WALLET_CURRENCY_CODE
	currency_id = settings.get("wallet_base_currency_id")
	if currency_id:
		return int(currency_id), code
	currency = db.query(Currency).filter(Currency.code == code).first()
	if currency:
		return int(currency.id), currency.code
	currency = db.query(Currency).order_by(Currency.id.asc()).first()
	if not currency:
		raise ApiError("CURRENCY_NOT_FOUND", "هیچ ارزی در سیستم ثبت نشده است", http_status=400)
	return int(currency.id), currency.code


def _attach_wallet_currency(config: Dict[str, Any] | None, db: Session) -> Dict[str, Any]:
	cfg = dict(config or {})
	currency_id, currency_code = _get_wallet_currency(db)
	cfg["currency_id"] = currency_id
	cfg["currency_code"] = currency_code
	return cfg


def _resolve_currency_id(db: Session, preferred_id: Any = None, fallback_id: Any = None) -> int:
	if preferred_id:
		return int(preferred_id)
	if fallback_id:
		return int(fallback_id)
	currency = db.query(Currency).order_by(Currency.id.asc()).first()
	if not currency:
		raise ApiError("CURRENCY_NOT_FOUND", "هیچ ارزی در سیستم ثبت نشده است", http_status=400)
	return int(currency.id)


def list_document_subscription_plans(db: Session, only_active: bool | None = None) -> List[Dict[str, Any]]:
	query = db.query(DocumentSubscriptionPlan)
	if only_active is not None:
		query = query.filter(DocumentSubscriptionPlan.is_active == bool(only_active))
	plans = query.order_by(DocumentSubscriptionPlan.id.asc()).all()
	return [_serialize_plan(p) for p in plans]


def create_document_subscription_plan(db: Session, payload: Dict[str, Any]) -> Dict[str, Any]:
	name = (payload.get("name") or "").strip()
	code = (payload.get("code") or "").strip()
	period_months = int(payload.get("period_months") or 0)
	price = _decimal(payload.get("price"))

	if not name:
		raise ApiError("VALIDATION_ERROR", "نام پلن الزامی است", http_status=422)
	if not code:
		raise ApiError("VALIDATION_ERROR", "کد پلن الزامی است", http_status=422)
	if period_months <= 0:
		raise ApiError("VALIDATION_ERROR", "مدت پلن باید بزرگتر از صفر باشد", http_status=422)

	exists = db.query(DocumentSubscriptionPlan).filter(DocumentSubscriptionPlan.code == code).first()
	if exists:
		raise ApiError("DUPLICATE_CODE", "کد پلن تکراری است", http_status=409)

	currency_id, _ = _get_wallet_currency(db)

	plan = DocumentSubscriptionPlan(
		name=name,
		code=code,
		description=payload.get("description"),
		period_months=period_months,
		price=price,
		currency_id=int(currency_id),
		is_active=bool(payload.get("is_active", True)),
	)
	db.add(plan)
	db.flush()
	db.commit()
	db.refresh(plan)
	return _serialize_plan(plan)


def update_document_subscription_plan(db: Session, plan_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	plan = db.query(DocumentSubscriptionPlan).filter(DocumentSubscriptionPlan.id == int(plan_id)).first()
	if not plan:
		raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد", http_status=404)

	if "name" in payload:
		name = (payload.get("name") or "").strip()
		if not name:
			raise ApiError("VALIDATION_ERROR", "نام پلن الزامی است", http_status=422)
		plan.name = name
	if "description" in payload:
		plan.description = payload.get("description")
	if "period_months" in payload:
		period = int(payload.get("period_months") or 0)
		if period <= 0:
			raise ApiError("VALIDATION_ERROR", "مدت پلن باید بزرگتر از صفر باشد", http_status=422)
		plan.period_months = period
	if "price" in payload:
		plan.price = _decimal(payload.get("price"))
	if "is_active" in payload:
		plan.is_active = bool(payload.get("is_active"))

	wallet_currency_id, _ = _get_wallet_currency(db)
	plan.currency_id = wallet_currency_id

	db.flush()
	db.commit()
	db.refresh(plan)
	return _serialize_plan(plan)


def delete_document_subscription_plan(db: Session, plan_id: int) -> Dict[str, Any]:
	plan = db.query(DocumentSubscriptionPlan).filter(DocumentSubscriptionPlan.id == int(plan_id)).first()
	if not plan:
		raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد", http_status=404)

	has_subscriptions = (
		db.query(BusinessDocumentSubscription)
		.filter(BusinessDocumentSubscription.plan_id == plan.id, BusinessDocumentSubscription.status == "active")
		.count()
		> 0
	)
	if has_subscriptions:
		plan.is_active = False
		db.flush()
		return {"deleted": False, "plan": _serialize_plan(plan)}

	db.delete(plan)
	db.flush()
	db.commit()
	return {"deleted": True}


def _add_months(dt: datetime, months: int) -> datetime:
	month = dt.month - 1 + months
	year = dt.year + month // 12
	month = month % 12 + 1
	day = min(dt.day, calendar.monthrange(year, month)[1])
	return dt.replace(year=year, month=month, day=day)


def assign_subscription_to_business(
	db: Session,
	business_id: int,
	plan_id: int,
	user_id: int,
	*,
	auto_renew: bool = False,
) -> Dict[str, Any]:
	plan = db.query(DocumentSubscriptionPlan).filter(
		DocumentSubscriptionPlan.id == int(plan_id),
		DocumentSubscriptionPlan.is_active == True,  # noqa: E712
	).first()
	if not plan:
		raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد یا غیرفعال است", http_status=404)

	now = datetime.utcnow()
	ends_at = _add_months(now, plan.period_months)

	subscription = BusinessDocumentSubscription(
		business_id=int(business_id),
		plan_id=plan.id,
		status="active",
		starts_at=now,
		ends_at=ends_at,
		auto_renew=bool(auto_renew),
		created_by_user_id=user_id,
		extra_data={"plan_price": float(plan.price or 0)},
	)
	db.add(subscription)
	db.flush()

	charge_result: Dict[str, Any] | None = None
	if _decimal(plan.price) > 0:
		desc = f"هزینه اشتراک {plan.name}"
		charge = DocumentUsageCharge(
			business_id=int(business_id),
			policy_id=None,
			document_id=None,
			charge_type="subscription_fee",
			status="pending",
			amount=_decimal(plan.price),
			currency_id=plan.currency_id,
			description=desc,
			metrics={
				"subscription_id": subscription.id,
				"plan_id": plan.id,
				"plan_code": plan.code,
			},
		)
		db.add(charge)
		db.flush()
		subscription.extra_data = {"charge_id": charge.id}
		try:
			charge_result = charge_wallet_for_service(
				db,
				business_id,
				_decimal(plan.price),
				description=desc,
				tx_type="document_subscription_fee",
			)
			charge.status = "paid"
			charge.wallet_transaction_id = charge_result["transaction_id"]
			charge.paid_at = datetime.utcnow()
			
			# ایجاد سند حسابداری
			try:
				doc_id = _create_document_monetization_accounting_document(
					db=db,
					business_id=business_id,
					user_id=user_id,
					charge=charge,
					amount=_decimal(plan.price),
					charge_type="subscription_fee",
				)
				charge.document_id = doc_id
				# به‌روزرسانی WalletTransaction با document_id
				from adapters.db.models.wallet import WalletTransaction
				if charge.wallet_transaction_id:
					wallet_tx = db.query(WalletTransaction).filter(
						WalletTransaction.id == charge.wallet_transaction_id
					).first()
					if wallet_tx:
						wallet_tx.document_id = doc_id
			except Exception as doc_exc:
				logger.warning(
					"subscription_accounting_document_creation_failed",
					business_id=business_id,
					charge_id=charge.id,
					error=str(doc_exc),
				)
		except ApiError as exc:  # type: ignore[assignment]
			logger.warning("subscription_charge_failed", business_id=business_id, error=str(exc))
			charge.status = "awaiting_payment"
			subscription.status = "pending"
		db.flush()
	else:
		charge_result = {"status": "free"}

	db.commit()
	db.refresh(subscription)

	return {
		"subscription": {
			"id": subscription.id,
			"business_id": subscription.business_id,
			"plan_id": subscription.plan_id,
			"status": subscription.status,
			"starts_at": subscription.starts_at,
			"ends_at": subscription.ends_at,
			"auto_renew": subscription.auto_renew,
		},
		"charge": charge_result,
	}


def get_business_subscription_status(db: Session, business_id: int) -> Optional[Dict[str, Any]]:
	subscription = (
		db.query(BusinessDocumentSubscription)
		.filter(BusinessDocumentSubscription.business_id == int(business_id))
		.order_by(BusinessDocumentSubscription.id.desc())
		.first()
	)
	if not subscription:
		return None

	plan = subscription.plan
	return {
		"id": subscription.id,
		"plan_id": subscription.plan_id,
		"plan_name": plan.name if plan else None,
		"plan_code": plan.code if plan else None,
		"plan_description": plan.description if plan else None,
		"plan_period_months": plan.period_months if plan else None,
		"plan_price": float(plan.price or 0) if plan else None,
		"currency_code": plan.currency.code if plan and plan.currency else None,
		"status": subscription.status,
		"starts_at": subscription.starts_at,
		"ends_at": subscription.ends_at,
		"auto_renew": subscription.auto_renew,
	}


def list_business_policies(db: Session, business_id: int) -> List[Dict[str, Any]]:
	policies = (
		db.query(DocumentUsagePolicy)
		.filter(DocumentUsagePolicy.business_id == int(business_id))
		.order_by(asc(DocumentUsagePolicy.priority), asc(DocumentUsagePolicy.id))
		.all()
	)
	return [_serialize_policy(p) for p in policies]


def _serialize_policy(policy: DocumentUsagePolicy) -> Dict[str, Any]:
	return {
		"id": policy.id,
		"business_id": policy.business_id,
		"policy_type": policy.policy_type,
		"title": policy.title,
		"priority": policy.priority,
		"is_active": policy.is_active,
		"config": policy.config or {},
		"starts_at": policy.starts_at,
		"ends_at": policy.ends_at,
	}


def upsert_business_policy(
	db: Session,
	business_id: int,
	payload: Dict[str, Any],
	user_id: int,
) -> Dict[str, Any]:
	policy_id = payload.get("id")
	title = (payload.get("title") or "").strip()
	policy_type = (payload.get("policy_type") or "").strip()
	config_payload = payload.get("config")

	if not title:
		raise ApiError("VALIDATION_ERROR", "عنوان سیاست الزامی است", http_status=422)
	if policy_type not in {"free", "subscription", "per_document", "volume", "hybrid"}:
		raise ApiError("VALIDATION_ERROR", "نوع سیاست نامعتبر است", http_status=422)

	normalized_config = _attach_wallet_currency(config_payload, db) if policy_type in {"per_document", "subscription", "volume"} else dict(config_payload or {})

	if policy_id:
		policy = (
			db.query(DocumentUsagePolicy)
			.filter(
				DocumentUsagePolicy.id == int(policy_id),
				DocumentUsagePolicy.business_id == int(business_id),
			)
			.first()
		)
		if not policy:
			raise ApiError("POLICY_NOT_FOUND", "سیاست یافت نشد", http_status=404)
	else:
		policy = DocumentUsagePolicy(
			business_id=int(business_id),
			policy_type=policy_type,
			title=title,
			priority=int(payload.get("priority") or 100),
			is_active=bool(payload.get("is_active", True)),
				config=normalized_config,
			starts_at=_parse_datetime(payload.get("starts_at")),
			ends_at=_parse_datetime(payload.get("ends_at")),
			created_by_user_id=user_id,
			updated_by_user_id=user_id,
		)
		db.add(policy)
		db.flush()
		db.commit()
		db.refresh(policy)
		return _serialize_policy(policy)

	if "title" in payload:
		policy.title = title
	if "priority" in payload:
		policy.priority = int(payload.get("priority") or policy.priority)
	if "is_active" in payload:
		policy.is_active = bool(payload.get("is_active"))
	if "config" in payload:
		if policy.policy_type in {"per_document", "subscription", "volume"}:
			policy.config = _attach_wallet_currency(payload.get("config"), db)
		else:
			policy.config = payload.get("config") or {}
	elif policy.policy_type in {"per_document", "subscription", "volume"}:
		policy.config = _attach_wallet_currency(policy.config, db)
	if "starts_at" in payload:
		policy.starts_at = _parse_datetime(payload.get("starts_at"))
	if "ends_at" in payload:
		policy.ends_at = _parse_datetime(payload.get("ends_at"))
	policy.updated_by_user_id = user_id
	db.flush()
	db.commit()
	db.refresh(policy)
	return _serialize_policy(policy)


def delete_business_policy(db: Session, business_id: int, policy_id: int) -> Dict[str, Any]:
	policy = (
		db.query(DocumentUsagePolicy)
		.filter(
			DocumentUsagePolicy.id == int(policy_id),
			DocumentUsagePolicy.business_id == int(business_id),
		)
		.first()
	)
	if not policy:
		raise ApiError("POLICY_NOT_FOUND", "سیاست یافت نشد", http_status=404)
	db.delete(policy)
	db.flush()
	db.commit()
	return {"deleted": True}


def _parse_datetime(value: Any) -> Optional[datetime]:
	if value in (None, ""):
		return None
	if isinstance(value, datetime):
		return value
	if isinstance(value, date):
		return datetime(value.year, value.month, value.day)
	try:
		return datetime.fromisoformat(str(value))
	except ValueError:
		return None


def ensure_document_policy_allows_creation(
	db: Session,
	business_id: int,
	*,
	document_type: str,
	document_date: Any,
	amount: Any,
) -> Dict[str, Any]:
	try:
		from app.services.legacy_import.context import is_legacy_import_active

		if is_legacy_import_active():
			return {"allowed": True, "legacy_import": True}
	except ImportError:
		pass
	result = evaluate_document_policy_for_amount(
		db,
		business_id=business_id,
		document_type=document_type,
		document_date=document_date,
		amount=amount,
	)
	if not result.get("allowed"):
		raise ApiError(result.get("code") or "POLICY_DENIED", result.get("message") or "امکان ثبت سند وجود ندارد", http_status=403)
	return result


def evaluate_document_policy_for_amount(
	db: Session,
	*,
	business_id: int,
	document_type: str,
	document_date: Any,
	amount: Any,
) -> Dict[str, Any]:
	doc_date = _normalize_document_date(document_date)
	amount_dec = _decimal(amount)
	policies = (
		db.query(DocumentUsagePolicy)
		.filter(
			DocumentUsagePolicy.business_id == int(business_id),
			DocumentUsagePolicy.is_active == True,  # noqa: E712
		)
		.order_by(asc(DocumentUsagePolicy.priority), asc(DocumentUsagePolicy.id))
		.all()
	)
	if not policies:
		return _deny_policy_result("NO_POLICY", "هیچ سیاست درآمدزایی برای این کسب‌وکار تعریف نشده است")

	for policy in policies:
		if not _is_policy_applicable(policy, doc_date):
			continue
		if policy.policy_type == "free":
			return _allow_policy_result(policy, "free", "ثبت سند در این کسب‌وکار رایگان است")
		if policy.policy_type == "subscription":
			if _has_active_subscription(db, business_id, doc_date):
				return _allow_policy_result(policy, "subscription", "سند توسط اشتراک فعال پوشش داده می‌شود")
			continue
		if policy.policy_type == "per_document":
			per_doc_result = _evaluate_per_document_policy_preflight(db, policy, business_id, amount_dec)
			per_doc_result["policy_id"] = policy.id
			per_doc_result["policy_type"] = policy.policy_type
			return per_doc_result
		if policy.policy_type == "volume":
			return _allow_policy_result(policy, "volume", "هزینه این سند در پایان دوره حجمی محاسبه می‌شود", extra={
				"document_type": document_type,
				"amount": float(amount_dec),
			})
		if policy.policy_type == "hybrid":
			# hybrid به معنی ادامه بررسی سیاست‌های بعدی است
			continue

	return _deny_policy_result("POLICY_NOT_COVERED", "هیچ سیاست فعالی امکان ثبت این سند را فراهم نمی‌کند")


def _allow_policy_result(
	policy: DocumentUsagePolicy,
	mode: str,
	message: str,
	*,
	extra: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
	result: Dict[str, Any] = {
		"allowed": True,
		"policy_id": policy.id,
		"policy_type": policy.policy_type,
		"mode": mode,
		"message": message,
	}
	if extra:
		result.update(extra)
	return result


def _deny_policy_result(code: str, message: str, *, extra: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
	result: Dict[str, Any] = {
		"allowed": False,
		"code": code,
		"message": message,
	}
	if extra:
		result.update(extra)
	return result


def _evaluate_per_document_policy_preflight(
	db: Session,
	policy: DocumentUsagePolicy,
	business_id: int,
	amount: Decimal,
) -> Dict[str, Any]:
	config = policy.config or {}
	fee_amount = _decimal(config.get("fee_amount"))
	if fee_amount <= 0:
		return _allow_policy_result(policy, "per_document", "این سیاست هزینه‌ای برای هر سند ندارد", extra={
			"charge_amount": 0,
			"auto_charge_wallet": bool(config.get("auto_charge_wallet", True)),
		})

	auto_charge = bool(config.get("auto_charge_wallet", True))
	currency_id = _resolve_currency_id(db, config.get("currency_id"))

	if not auto_charge:
		return _allow_policy_result(policy, "per_document", "هزینه ثبت سند به صورت صورتحساب معوق ثبت می‌شود", extra={
			"charge_amount": float(fee_amount),
			"currency_id": currency_id,
			"auto_charge_wallet": False,
		})

	available_balance = _get_wallet_available_balance(db, business_id)
	if available_balance >= fee_amount:
		return _allow_policy_result(policy, "per_document", "هزینه ثبت سند از کیف‌پول برداشت خواهد شد", extra={
			"charge_amount": float(fee_amount),
			"currency_id": currency_id,
			"auto_charge_wallet": True,
			"wallet_balance": float(available_balance),
		})

	return _deny_policy_result(
		"INSUFFICIENT_FUNDS",
		"موجودی کیف‌پول برای هزینه ثبت سند کافی نیست",
		extra={
			"required_amount": float(fee_amount),
			"currency_id": currency_id,
			"wallet_balance": float(available_balance),
		},
	)


def _get_wallet_available_balance(db: Session, business_id: int) -> Decimal:
	wallet = db.query(WalletAccount).filter(WalletAccount.business_id == int(business_id)).first()
	if not wallet:
		return Decimal(0)
	return _decimal(wallet.available_balance)


def _normalize_document_date(value: Any) -> datetime:
	if isinstance(value, datetime):
		return value
	if isinstance(value, date):
		return datetime(value.year, value.month, value.day)
	parsed = _parse_datetime(value)
	if parsed:
		return parsed
	return datetime.utcnow()


def list_document_usage_charges(
	db: Session,
	business_id: int,
	*,
	status: Optional[str] = None,
	charge_type: Optional[str] = None,
	limit: int = 50,
	skip: int = 0,
) -> Dict[str, Any]:
	query = (
		db.query(DocumentUsageCharge)
		.filter(DocumentUsageCharge.business_id == int(business_id))
		.order_by(DocumentUsageCharge.id.desc())
	)
	if status:
		query = query.filter(DocumentUsageCharge.status == status)
	if charge_type:
		query = query.filter(DocumentUsageCharge.charge_type == charge_type)
	total = query.count()
	items = query.offset(max(0, int(skip))).limit(max(1, min(200, int(limit)))).all()
	return {
		"total": total,
		"items": [_serialize_charge(item) for item in items],
	}


def _serialize_charge(charge: DocumentUsageCharge) -> Dict[str, Any]:
	return {
		"id": charge.id,
		"business_id": charge.business_id,
		"policy_id": charge.policy_id,
		"document_id": charge.document_id,
		"charge_type": charge.charge_type,
		"status": charge.status,
		"amount": float(charge.amount or 0),
		"currency_id": charge.currency_id,
		"wallet_transaction_id": charge.wallet_transaction_id,
		"description": charge.description,
		"metrics": charge.metrics,
		"period_key": charge.period_key,
		"period_start": charge.period_start,
		"period_end": charge.period_end,
		"paid_at": charge.paid_at,
		"created_at": charge.created_at,
	}


def pay_document_usage_charge(db: Session, business_id: int, charge_id: int, user_id: int) -> Dict[str, Any]:
	charge = (
		db.query(DocumentUsageCharge)
		.filter(
			DocumentUsageCharge.id == int(charge_id),
			DocumentUsageCharge.business_id == int(business_id),
		)
		.first()
	)
	if not charge:
		raise ApiError("CHARGE_NOT_FOUND", "صورتحساب یافت نشد", http_status=404)
	if charge.status not in {"pending", "awaiting_payment"}:
		raise ApiError("INVALID_STATE", "صورتحساب قابل پرداخت نیست", http_status=400)

	desc = charge.description or "هزینه ثبت سند"
	tx = charge_wallet_for_service(
		db,
		business_id,
		_decimal(charge.amount),
		description=desc,
		tx_type="document_usage_charge",
		document_id=charge.document_id,
		extra_info={"charge_id": charge.id, "charge_type": charge.charge_type},
	)
	charge.wallet_transaction_id = tx["transaction_id"]
	charge.status = "paid"
	charge.paid_at = datetime.utcnow()

	# ایجاد سند حسابداری
	try:
		doc_id = _create_document_monetization_accounting_document(
			db=db,
			business_id=business_id,
			user_id=user_id,
			charge=charge,
			amount=_decimal(charge.amount),
			charge_type=charge.charge_type,
		)
		charge.document_id = doc_id
		# به‌روزرسانی WalletTransaction با document_id
		from adapters.db.models.wallet import WalletTransaction
		if charge.wallet_transaction_id:
			wallet_tx = db.query(WalletTransaction).filter(
				WalletTransaction.id == charge.wallet_transaction_id
			).first()
			if wallet_tx:
				wallet_tx.document_id = doc_id
	except Exception as doc_exc:
		logger.warning(
			"pay_charge_accounting_document_creation_failed",
			business_id=business_id,
			charge_id=charge.id,
			error=str(doc_exc),
		)

	if charge.charge_type == "subscription_fee" and charge.metrics:
		subscription_id = charge.metrics.get("subscription_id")
		if subscription_id:
			subscription = (
				db.query(BusinessDocumentSubscription)
				.filter(BusinessDocumentSubscription.id == int(subscription_id))
				.first()
			)
			if subscription:
				subscription.status = "active"

	db.flush()
	return {
		"charge": _serialize_charge(charge),
		"wallet_transaction": tx,
	}


def process_document_usage_for_document(db: Session, document_id: int) -> Dict[str, Any]:
	document = db.query(Document).filter(Document.id == int(document_id)).first()
	if not document:
		raise ApiError("DOCUMENT_NOT_FOUND", "سند یافت نشد", http_status=404)
	if document.is_proforma:
		return {"skipped": True, "reason": "proforma"}

	doc_date = datetime.combine(document.document_date, datetime.min.time())
	_finalize_expired_periods(db, business_id=document.business_id, as_of=doc_date)

	policies = (
		db.query(DocumentUsagePolicy)
		.filter(
			DocumentUsagePolicy.business_id == int(document.business_id),
			DocumentUsagePolicy.is_active == True,  # noqa: E712
		)
		.order_by(asc(DocumentUsagePolicy.priority), asc(DocumentUsagePolicy.id))
		.all()
	)
	if not policies:
		return {"skipped": True, "reason": "no_policy"}

	totals = _calculate_document_totals(db, document.id)
	applied: List[Dict[str, Any]] = []
	should_continue = True

	for policy in policies:
		if not should_continue:
			break
		if not _is_policy_applicable(policy, doc_date):
			continue
		result = _apply_policy(db, policy, document, totals, doc_date)
		if result:
			applied.append(result)
			should_continue = result.get("cascade", False)

	_update_usage_cursor(db, document.id, document.created_at)
	return {
		"document_id": document.id,
		"applied": applied,
		"totals": {
			"debit": float(totals["total_debit"]),
			"credit": float(totals["total_credit"]),
			"amount": float(totals["amount"]),
		},
	}


def _update_usage_cursor(db: Session, document_id: int, created_at: datetime) -> None:
	cursor = (
		db.query(DocumentUsageCursor)
		.filter(DocumentUsageCursor.scope == "global", DocumentUsageCursor.business_id.is_(None))
		.first()
	)
	if not cursor:
		cursor = DocumentUsageCursor(scope="global", business_id=None, last_document_id=document_id, last_document_created_at=created_at)
		db.add(cursor)
	else:
		if not cursor.last_document_id or document_id > cursor.last_document_id:
			cursor.last_document_id = document_id
			cursor.last_document_created_at = created_at
	db.flush()


def process_document_usage_queue(db: Session, batch_size: int = 50) -> Dict[str, Any]:
	cursor = (
		db.query(DocumentUsageCursor)
		.filter(DocumentUsageCursor.scope == "global", DocumentUsageCursor.business_id.is_(None))
		.first()
	)
	last_id = cursor.last_document_id if cursor else None
	query = db.query(Document).filter(Document.is_proforma == False)  # noqa: E712
	if last_id:
		query = query.filter(Document.id > last_id)
	documents = query.order_by(Document.id.asc()).limit(max(1, batch_size)).all()
	count = 0
	for doc in documents:
		process_document_usage_for_document(db, doc.id)
		count += 1
	return {
		"processed": count,
		"last_document_id": documents[-1].id if documents else last_id,
	}


def _calculate_document_totals(db: Session, document_id: int) -> Dict[str, Decimal]:
	totals = (
		db.query(
			func.coalesce(func.sum(DocumentLine.debit), 0),
			func.coalesce(func.sum(DocumentLine.credit), 0),
		)
		.filter(DocumentLine.document_id == int(document_id))
		.first()
	)
	total_debit = _decimal(totals[0])
	total_credit = _decimal(totals[1])
	amount = max(total_debit, total_credit)
	return {
		"total_debit": total_debit,
		"total_credit": total_credit,
		"amount": amount,
	}


def _is_policy_applicable(policy: DocumentUsagePolicy, document_date: datetime) -> bool:
	if policy.starts_at and document_date < policy.starts_at:
		return False
	if policy.ends_at and document_date > policy.ends_at:
		return False
	return True


def _apply_policy(
	db: Session,
	policy: DocumentUsagePolicy,
	document: Document,
	totals: Dict[str, Decimal],
	doc_date: datetime,
) -> Optional[Dict[str, Any]]:
	config = policy.config or {}
	if policy.policy_type == "free":
		return {"policy_id": policy.id, "type": "free", "status": "covered", "cascade": False}
	if policy.policy_type == "subscription":
		if _has_active_subscription(db, document.business_id, doc_date):
			return {"policy_id": policy.id, "type": "subscription", "status": "covered", "cascade": bool(config.get("cascade", False))}
		return None
	if policy.policy_type == "per_document":
		return _apply_per_document_policy(db, policy, document, totals)
	if policy.policy_type == "volume":
		return _apply_volume_policy(db, policy, document, totals, doc_date)
	if policy.policy_type == "hybrid":
		return {"policy_id": policy.id, "type": "hybrid", "status": "noop", "cascade": True}
	return None


def _has_active_subscription(db: Session, business_id: int, as_of: datetime) -> bool:
	record = (
		db.query(BusinessDocumentSubscription)
		.filter(
			BusinessDocumentSubscription.business_id == int(business_id),
			BusinessDocumentSubscription.status == "active",
			BusinessDocumentSubscription.starts_at <= as_of,
			BusinessDocumentSubscription.ends_at >= as_of,
		)
		.first()
	)
	return record is not None


def _apply_per_document_policy(
	db: Session,
	policy: DocumentUsagePolicy,
	document: Document,
	totals: Dict[str, Decimal],
) -> Optional[Dict[str, Any]]:
	config = policy.config or {}
	fee_amount = _decimal(config.get("fee_amount"))
	if fee_amount <= 0:
		return None
	currency_id = _resolve_currency_id(db, config.get("currency_id"), document.currency_id)

	existing = (
		db.query(DocumentUsageCharge)
		.filter(
			DocumentUsageCharge.policy_id == policy.id,
			DocumentUsageCharge.document_id == document.id,
			DocumentUsageCharge.charge_type == "per_document",
		)
		.first()
	)
	if existing:
		return {"policy_id": policy.id, "type": "per_document", "status": existing.status, "charge_id": existing.id, "cascade": bool(config.get("cascade", False))}

	description = config.get("description") or f"هزینه ثبت سند {document.code}"
	charge = DocumentUsageCharge(
		business_id=document.business_id,
		policy_id=policy.id,
		document_id=document.id,
		charge_type="per_document",
		status="pending",
		amount=fee_amount,
		currency_id=currency_id,
		description=description,
		metrics={
			"document_code": document.code,
			"document_type": document.document_type,
			"total_amount": float(totals["amount"]),
		},
	)
	db.add(charge)
	db.flush()

	auto_charge = bool(config.get("auto_charge_wallet", True))
	if auto_charge:
		try:
			tx = charge_wallet_for_service(
				db,
				document.business_id,
				fee_amount,
				description=description,
				tx_type="document_usage_charge",
				document_id=document.id,
				extra_info={"policy_id": policy.id, "charge_id": charge.id},
			)
			charge.status = "paid"
			charge.wallet_transaction_id = tx["transaction_id"]
			charge.paid_at = datetime.utcnow()
			
			# ایجاد سند حسابداری
			try:
				doc_id = _create_document_monetization_accounting_document(
					db=db,
					business_id=document.business_id,
					user_id=document.created_by_user_id or 0,
					charge=charge,
					amount=fee_amount,
					charge_type="per_document",
				)
				charge.document_id = doc_id
				# به‌روزرسانی WalletTransaction با document_id
				from adapters.db.models.wallet import WalletTransaction
				if charge.wallet_transaction_id:
					wallet_tx = db.query(WalletTransaction).filter(
						WalletTransaction.id == charge.wallet_transaction_id
					).first()
					if wallet_tx:
						wallet_tx.document_id = doc_id
			except Exception as doc_exc:
				logger.warning(
					"per_document_accounting_document_creation_failed",
					business_id=document.business_id,
					charge_id=charge.id,
					document_id=document.id,
					error=str(doc_exc),
				)
		except ApiError as exc:
			if exc.code == "INSUFFICIENT_FUNDS":
				charge.status = "awaiting_payment"
			else:
				raise
	else:
		charge.status = "awaiting_payment"
	db.flush()

	return {
		"policy_id": policy.id,
		"type": "per_document",
		"status": charge.status,
		"charge_id": charge.id,
		"cascade": bool(config.get("cascade", False)),
	}


def _apply_volume_policy(
	db: Session,
	policy: DocumentUsagePolicy,
	document: Document,
	totals: Dict[str, Decimal],
	doc_date: datetime,
) -> Optional[Dict[str, Any]]:
	config = policy.config or {}
	cycle = config.get("cycle", "monthly")
	tier_amount = _decimal(config.get("tier_amount") or 0)
	price_per_tier = _decimal(config.get("price_per_tier") or 0)
	free_threshold = _decimal(config.get("free_threshold_amount") or 0)
	if tier_amount <= 0 or price_per_tier <= 0:
		return None

	period = _get_or_create_period(db, policy, doc_date, cycle)
	period.documents_count = int(period.documents_count or 0) + 1
	period.total_amount = _decimal(period.total_amount) + totals["amount"]
	db.flush()

	return {
		"policy_id": policy.id,
		"type": "volume",
		"status": "accrued",
		"period_key": period.period_key,
		"documents_count": period.documents_count,
		"total_amount": float(period.total_amount or 0),
		"cascade": bool(config.get("cascade", True)),
	}


def _get_or_create_period(db: Session, policy: DocumentUsagePolicy, doc_date: datetime, cycle: str) -> DocumentUsagePeriod:
	start, end, period_key = _resolve_period_window(doc_date, cycle)
	# استفاده از with_for_update برای جلوگیری از race condition
	period = (
		db.query(DocumentUsagePeriod)
		.filter(
			DocumentUsagePeriod.policy_id == policy.id,
			DocumentUsagePeriod.period_key == period_key,
		)
		.with_for_update()
		.first()
	)
	if period:
		return period
	# اگر وجود نداشت، دوباره بدون lock بررسی کن (ممکن است thread دیگری ایجاد کرده باشد)
	period = (
		db.query(DocumentUsagePeriod)
		.filter(
			DocumentUsagePeriod.policy_id == policy.id,
			DocumentUsagePeriod.period_key == period_key,
		)
		.first()
	)
	if period:
		return period
	# ایجاد period جدید
	period = DocumentUsagePeriod(
		business_id=policy.business_id,
		policy_id=policy.id,
		period_key=period_key,
		cycle=cycle,
		period_start=start,
		period_end=end,
		documents_count=0,
		total_amount=Decimal("0"),
		status="open",
	)
	db.add(period)
	db.flush()
	return period


def _resolve_period_window(doc_date: datetime, cycle: str) -> Tuple[datetime, datetime, str]:
	if cycle == "weekly":
		start = doc_date - timedelta(days=doc_date.weekday())
		start = datetime(start.year, start.month, start.day)
		end = start + timedelta(days=6, hours=23, minutes=59, seconds=59)
		period_key = f"weekly-{start.strftime('%Y-%m-%d')}"
	elif cycle == "yearly":
		start = datetime(doc_date.year, 1, 1)
		end = datetime(doc_date.year, 12, 31, 23, 59, 59)
		period_key = f"yearly-{doc_date.year}"
	else:
		start = datetime(doc_date.year, doc_date.month, 1)
		last_day = calendar.monthrange(doc_date.year, doc_date.month)[1]
		end = datetime(doc_date.year, doc_date.month, last_day, 23, 59, 59)
		period_key = f"monthly-{doc_date.strftime('%Y-%m')}"
	return start, end, period_key


def _finalize_expired_periods(db: Session, *, business_id: int, as_of: datetime) -> None:
	open_periods = (
		db.query(DocumentUsagePeriod)
		.filter(
			DocumentUsagePeriod.business_id == int(business_id),
			DocumentUsagePeriod.status == "open",
			DocumentUsagePeriod.period_end < as_of,
		)
		.all()
	)
	for period in open_periods:
		_finalize_period(db, period)


def finalize_volume_periods(db: Session, *, business_id: Optional[int] = None) -> Dict[str, Any]:
	query = db.query(DocumentUsagePeriod).filter(DocumentUsagePeriod.status == "open")
	if business_id:
		query = query.filter(DocumentUsagePeriod.business_id == int(business_id))
	periods = query.all()
	count = 0
	for period in periods:
		_finalize_period(db, period)
		count += 1
	return {"finalized": count}


def _finalize_period(db: Session, period: DocumentUsagePeriod) -> None:
	policy = db.query(DocumentUsagePolicy).filter(DocumentUsagePolicy.id == period.policy_id).first()
	if not policy:
		period.status = "finalized"
		db.flush()
		return
	config = policy.config or {}
	tier_amount = _decimal(config.get("tier_amount") or 0)
	price_per_tier = _decimal(config.get("price_per_tier") or 0)
	free_threshold = _decimal(config.get("free_threshold_amount") or 0)
	min_invoice_amount = _decimal(config.get("min_invoice_amount") or 0)
	auto_charge = bool(config.get("auto_charge_wallet", False))
	policy_business_currency = getattr(policy.business, "default_currency_id", None)
	currency_id = _resolve_currency_id(db, config.get("currency_id"), policy_business_currency)

	total_amount = _decimal(period.total_amount)
	if total_amount <= free_threshold or tier_amount <= 0 or price_per_tier <= 0:
		period.status = "finalized"
		db.flush()
		return

	chargeable = total_amount - free_threshold
	tiers = math.ceil(float(chargeable / tier_amount))
	charge_amount = Decimal(str(tiers)) * price_per_tier
	if min_invoice_amount > 0:
		charge_amount = max(charge_amount, min_invoice_amount)

	description = config.get("description") or f"هزینه دوره {period.period_key}"
	charge = DocumentUsageCharge(
		business_id=period.business_id,
		policy_id=policy.id,
		document_id=None,
		charge_type="volume_cycle",
		status="pending",
		amount=charge_amount,
		currency_id=currency_id,
		description=description,
		metrics={
			"documents_count": period.documents_count,
			"total_amount": float(total_amount),
			"free_threshold": float(free_threshold),
			"tiers": tiers,
		},
		period_key=period.period_key,
		period_start=period.period_start,
		period_end=period.period_end,
	)
	db.add(charge)
	db.flush()

	if auto_charge:
		try:
			tx = charge_wallet_for_service(
				db,
				period.business_id,
				charge_amount,
				description=description,
				tx_type="document_volume_charge",
				extra_info={"period_key": period.period_key, "policy_id": policy.id},
			)
			charge.status = "paid"
			charge.wallet_transaction_id = tx["transaction_id"]
			charge.paid_at = datetime.utcnow()
			
			# ایجاد سند حسابداری
			try:
				# دریافت user_id از policy یا business
				user_id = policy.created_by_user_id or policy.updated_by_user_id or 0
				doc_id = _create_document_monetization_accounting_document(
					db=db,
					business_id=period.business_id,
					user_id=user_id,
					charge=charge,
					amount=charge_amount,
					charge_type="volume_cycle",
				)
				charge.document_id = doc_id
				# به‌روزرسانی WalletTransaction با document_id
				from adapters.db.models.wallet import WalletTransaction
				if charge.wallet_transaction_id:
					wallet_tx = db.query(WalletTransaction).filter(
						WalletTransaction.id == charge.wallet_transaction_id
					).first()
					if wallet_tx:
						wallet_tx.document_id = doc_id
			except Exception as doc_exc:
				logger.warning(
					"volume_cycle_accounting_document_creation_failed",
					business_id=period.business_id,
					charge_id=charge.id,
					period_key=period.period_key,
					error=str(doc_exc),
				)
		except ApiError as exc:
			if exc.code == "INSUFFICIENT_FUNDS":
				charge.status = "awaiting_payment"
			else:
				raise
	else:
		charge.status = "awaiting_payment"
	db.flush()

	period.charge_id = charge.id
	period.status = "invoiced"
	db.flush()


def apply_default_policies_to_business(
	db: Session,
	business_id: int,
	user_id: int | None = None,
) -> List[Dict[str, Any]]:
	"""
	اعمال خودکار سیاست‌های پیش‌فرض به یک کسب‌وکار جدید
	"""
	default_policies = get_default_document_policies(db)
	if not default_policies:
		return []
	
	applied = []
	currency_id, _ = _get_wallet_currency(db)
	
	for policy_def in default_policies:
		if not policy_def.get("is_active", True):
			continue
		
		policy_type = policy_def.get("policy_type")
		title = policy_def.get("title", "")
		priority = int(policy_def.get("priority", 100))
		config = dict(policy_def.get("config") or {})
		
		# اطمینان از استفاده از ارز کیف‌پول
		if policy_type in {"per_document", "subscription", "volume"}:
			config = _attach_wallet_currency(config, db)
		
		policy = DocumentUsagePolicy(
			business_id=int(business_id),
			policy_type=policy_type,
			title=title,
			priority=priority,
			is_active=True,
			config=config,
			starts_at=None,
			ends_at=None,
			created_by_user_id=user_id,
			updated_by_user_id=user_id,
		)
		db.add(policy)
		applied.append(policy)
	
	if applied:
		db.flush()
		db.commit()
		for policy in applied:
			db.refresh(policy)
	
	return [_serialize_policy(p) for p in applied]


