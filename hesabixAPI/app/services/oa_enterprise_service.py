"""شعبه، نگهداری بدون حذف، تبادل نامه عادی، و ثبت نتیجه ارائه‌دهنده امضا."""
from __future__ import annotations

import json
from datetime import datetime, timedelta
from typing import Optional
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener

from sqlalchemy.orm import Session

from adapters.db.models.oa_document import OaDocument, OaDocumentVersion
from adapters.db.models.crm import Deal
from adapters.db.models.document import Document
from adapters.db.models.oa_enterprise import (
	OaBranch,
	OaLetterCommercialLink,
	OaLetterExchange,
	OaQualifiedSignRequest,
	OaRetentionPolicy,
	OaSignatureProvider,
)
from adapters.db.models.office_automation import OaLetter, OaPosition, OaPositionHolder, OaSecretariat
from app.core.responses import ApiError
from app.services.crm_guards import assert_document_in_business
from app.services.office_automation_service import (
	_audit,
	_can_view_letter,
	_ensure_plugin,
	_visible_letter_clause,
	create_letter_draft,
	resolve_acting_position,
	resolve_i18n,
)

_CONFIDENTIALITY = frozenset({"normal", "confidential", "highly_confidential", "secret"})
_CLASSIFIED = frozenset({"confidential", "highly_confidential", "secret"})


def _now() -> datetime:
	return datetime.utcnow()


def _branch_dict(row: OaBranch, lang: str) -> dict:
	return {"id": row.id, "code": row.code, "title": resolve_i18n(row.name_i18n, lang), "is_active": row.is_active}


def require_branch(db: Session, business_id: int, branch_id: int) -> OaBranch:
	row = db.query(OaBranch).filter(OaBranch.id == branch_id, OaBranch.business_id == business_id, OaBranch.is_active.is_(True)).first()
	if row is None:
		raise ApiError("OA_BRANCH_NOT_FOUND", "Branch was not found.", http_status=404)
	return row


def create_branch(db: Session, business_id: int, user_id: int, payload: dict, lang: str = "fa") -> dict:
	_ensure_plugin(db, business_id)
	code = str(payload.get("code") or "").strip()
	name = str(payload.get("name") or "").strip()
	if not code or not name:
		raise ApiError("OA_BRANCH_INVALID", "Branch code and name are required.", http_status=400)
	row = OaBranch(business_id=business_id, code=code[:64], name_i18n={"fa": name, "en": name}, is_active=True, created_at=_now())
	db.add(row)
	try:
		db.flush()
	except Exception as exc:
		db.rollback()
		raise ApiError("OA_BRANCH_EXISTS", "Branch code is already used.", http_status=400) from exc
	_audit(db, business_id=business_id, user_id=user_id, action="branch.create", payload={"branch_id": row.id})
	db.commit()
	db.refresh(row)
	return _branch_dict(row, lang)


def list_branches(db: Session, business_id: int, lang: str = "fa") -> dict:
	_ensure_plugin(db, business_id)
	rows = db.query(OaBranch).filter(OaBranch.business_id == business_id).order_by(OaBranch.id).all()
	return {"items": [_branch_dict(row, lang) for row in rows]}


def list_retention_policies(db: Session, business_id: int) -> dict:
	_ensure_plugin(db, business_id)
	rows = (
		db.query(OaRetentionPolicy)
		.filter(OaRetentionPolicy.business_id == business_id)
		.order_by(OaRetentionPolicy.id)
		.all()
	)
	return {"items": [{"id": row.id, "confidentiality": row.confidentiality, "retain_days": row.retain_days} for row in rows]}


def list_signature_providers(db: Session, business_id: int) -> dict:
	_ensure_plugin(db, business_id)
	rows = (
		db.query(OaSignatureProvider)
		.filter(OaSignatureProvider.business_id == business_id, OaSignatureProvider.is_active.is_(True))
		.order_by(OaSignatureProvider.id)
		.all()
	)
	return {"items": [_provider_public(row) for row in rows]}


def save_retention_policy(db: Session, business_id: int, user_id: int, payload: dict) -> dict:
	_ensure_plugin(db, business_id)
	confidentiality = str(payload.get("confidentiality") or "")
	days = int(payload.get("retain_days") or 0)
	if confidentiality not in _CONFIDENTIALITY or days < 1 or days > 36500:
		raise ApiError("OA_RETENTION_INVALID", "Retention policy is invalid.", http_status=400)
	row = (
		db.query(OaRetentionPolicy)
		.filter(OaRetentionPolicy.business_id == business_id, OaRetentionPolicy.confidentiality == confidentiality)
		.first()
	)
	if row is None:
		row = OaRetentionPolicy(business_id=business_id, confidentiality=confidentiality, retain_days=days, created_at=_now())
		db.add(row)
	else:
		row.retain_days = days
	_audit(db, business_id=business_id, user_id=user_id, action="retention.policy", payload={"confidentiality": confidentiality, "retain_days": days})
	db.commit()
	db.refresh(row)
	return {"id": row.id, "confidentiality": row.confidentiality, "retain_days": row.retain_days}


def _policy_days(db: Session, business_id: int, confidentiality: str) -> Optional[int]:
	row = (
		db.query(OaRetentionPolicy)
		.filter(OaRetentionPolicy.business_id == business_id, OaRetentionPolicy.confidentiality == confidentiality)
		.first()
	)
	return row.retain_days if row else None


def apply_letter_scope(db: Session, letter: OaLetter) -> None:
	if letter.secretariat_id and not letter.branch_id:
		secretariat = db.query(OaSecretariat).filter(OaSecretariat.id == letter.secretariat_id).first()
		if secretariat is not None and secretariat.branch_id:
			letter.branch_id = secretariat.branch_id
	days = _policy_days(db, letter.business_id, letter.confidentiality)
	if days and letter.letter_date and letter.retain_until is None:
		letter.retain_until = letter.letter_date + timedelta(days=days)
		letter.retention_status = letter.retention_status or "none"


def apply_document_scope(db: Session, doc: OaDocument) -> None:
	days = _policy_days(db, doc.business_id, doc.confidentiality)
	if days and doc.retain_until is None:
		doc.retain_until = _now().date() + timedelta(days=days)
		doc.retention_status = doc.retention_status or "none"


def mark_due_retention(db: Session, business_id: Optional[int] = None) -> dict:
	today = _now().date()
	letters = db.query(OaLetter).filter(OaLetter.retain_until.isnot(None), OaLetter.retain_until <= today, OaLetter.retention_status == "none")
	documents = db.query(OaDocument).filter(OaDocument.retain_until.isnot(None), OaDocument.retain_until <= today, OaDocument.retention_status == "none")
	if business_id is not None:
		letters = letters.filter(OaLetter.business_id == business_id)
		documents = documents.filter(OaDocument.business_id == business_id)
	letter_count = 0
	for row in letters.all():
		row.retention_status = "due_review"
		letter_count += 1
	document_count = 0
	for row in documents.all():
		row.retention_status = "due_review"
		document_count += 1
	db.commit()
	return {"letters": letter_count, "documents": document_count, "deleted": 0}


def list_retention_reviews(db: Session, business_id: int, user_id: Optional[int] = None, is_admin: bool = False) -> dict:
	_ensure_plugin(db, business_id)
	if not is_admin and user_id is None:
		return {"items": [], "documents": []}
	letters = db.query(OaLetter).filter(OaLetter.business_id == business_id, OaLetter.retention_status == "due_review")
	documents = db.query(OaDocument).filter(OaDocument.business_id == business_id, OaDocument.retention_status == "due_review")
	if not is_admin:
		letters = letters.filter(_visible_letter_clause(db, business_id, int(user_id), False))
		from app.services.oa_document_service import visible_document_clause

		documents = documents.filter(visible_document_clause(db, business_id, int(user_id)))
	letter_rows = letters.order_by(OaLetter.retain_until, OaLetter.id).limit(50).all()
	document_rows = documents.order_by(OaDocument.retain_until, OaDocument.id).limit(50).all()
	return {
		"items": [
			{"letter_id": row.id, "number": row.secretariat_number, "retain_until": row.retain_until, "confidentiality": row.confidentiality}
			for row in letter_rows
		],
		"documents": [
			{"document_id": row.id, "title": row.title, "retain_until": row.retain_until, "confidentiality": row.confidentiality}
			for row in document_rows
		],
	}


def hold_letter_retention(db: Session, business_id: int, user_id: int, letter_id: int) -> dict:
	_ensure_plugin(db, business_id)
	row = db.query(OaLetter).filter(OaLetter.id == letter_id, OaLetter.business_id == business_id).first()
	if row is None:
		raise ApiError("OA_LETTER_NOT_FOUND", "Letter was not found.", http_status=404)
	if row.retention_status != "due_review":
		raise ApiError("OA_RETENTION_NOT_DUE", "Letter is not due for retention review.", http_status=400)
	row.retention_status = "held"
	_audit(db, business_id=business_id, user_id=user_id, action="retention.hold", letter_id=row.id, payload={"retain_until": str(row.retain_until)})
	db.commit()
	return {"letter_id": row.id, "retention_status": row.retention_status, "deleted": False}


def hold_document_retention(db: Session, business_id: int, user_id: int, document_id: int) -> dict:
	_ensure_plugin(db, business_id)
	row = db.query(OaDocument).filter(OaDocument.id == document_id, OaDocument.business_id == business_id).first()
	if row is None:
		raise ApiError("OA_DOCUMENT_NOT_FOUND", "Document was not found.", http_status=404)
	if row.retention_status != "due_review":
		raise ApiError("OA_RETENTION_NOT_DUE", "Document is not due for retention review.", http_status=400)
	file_id = None
	if row.current_version_id:
		version = db.query(OaDocumentVersion).filter(OaDocumentVersion.id == row.current_version_id).first()
		file_id = version.file_storage_id if version is not None else None
	row.retention_status = "held"
	_audit(db, business_id=business_id, user_id=user_id, action="retention.hold.document", payload={"document_id": row.id, "retain_until": str(row.retain_until)})
	db.commit()
	return {"document_id": row.id, "retention_status": row.retention_status, "file_storage_id": file_id, "deleted": False}


class _RefuseRedirect(HTTPRedirectHandler):
	def redirect_request(self, req, fp, code, msg, headers, newurl):
		raise ApiError("OA_PROVIDER_REDIRECT", "Provider redirects are not followed.", http_status=502)


def _provider_url(value: str) -> str:
	url = str(value or "").strip()
	parsed = urlparse(url)
	if parsed.scheme not in {"http", "https"} or not parsed.netloc or len(url) > 500:
		raise ApiError("OA_PROVIDER_URL_INVALID", "Provider endpoint must be an http(s) URL.", http_status=400)
	return url


def post_signature_provider(url: str, payload: dict, token: Optional[str]) -> dict:
	"""POST به ارائه‌دهنده. توکن و متن نامه در این تابع لاگ نمی‌شود."""
	body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
	headers = {"Content-Type": "application/json", "Accept": "application/json"}
	if token:
		headers["Authorization"] = f"Bearer {token}"
	request = Request(_provider_url(url), data=body, headers=headers, method="POST")
	opener = build_opener(_RefuseRedirect)
	try:
		with opener.open(request, timeout=10) as response:
			raw = response.read(20000)
	except (HTTPError, URLError, TimeoutError, OSError) as exc:
		raise ApiError("OA_PROVIDER_UNREACHABLE", "Provider did not accept the request.", http_status=502) from exc
	try:
		data = json.loads(raw.decode("utf-8"))
	except (UnicodeDecodeError, json.JSONDecodeError) as exc:
		raise ApiError("OA_PROVIDER_RESPONSE_INVALID", "Provider response was not JSON.", http_status=502) from exc
	if not isinstance(data, dict):
		raise ApiError("OA_PROVIDER_RESPONSE_INVALID", "Provider response was not JSON.", http_status=502)
	return {"external_ref": str(data.get("external_ref") or "").strip(), "outcome": str(data.get("outcome") or "").strip()}


def _provider_public(row: OaSignatureProvider) -> dict:
	return {
		"id": row.id,
		"code": row.code,
		"name": row.name,
		"endpoint_url": row.endpoint_url,
		"has_token": bool(row.access_token),
		"live": bool(row.endpoint_url),
		"assurance": "provider_attestation",
	}


def create_signature_provider(db: Session, business_id: int, user_id: int, payload: dict) -> dict:
	_ensure_plugin(db, business_id)
	code = str(payload.get("code") or "").strip()
	name = str(payload.get("name") or "").strip()
	if not code or not name:
		raise ApiError("OA_PROVIDER_INVALID", "Provider code and name are required.", http_status=400)
	endpoint = _provider_url(payload["endpoint_url"]) if payload.get("endpoint_url") else None
	token = str(payload.get("access_token") or "").strip() or None
	row = OaSignatureProvider(
		business_id=business_id,
		code=code[:64],
		name=name[:160],
		endpoint_url=endpoint,
		access_token=token[:500] if token else None,
		is_active=True,
		created_at=_now(),
	)
	db.add(row)
	try:
		db.flush()
	except Exception as exc:
		db.rollback()
		raise ApiError("OA_PROVIDER_EXISTS", "Provider code is already used.", http_status=400) from exc
	_audit(db, business_id=business_id, user_id=user_id, action="signature.provider", payload={"provider_id": row.id, "live": bool(endpoint)})
	db.commit()
	db.refresh(row)
	return _provider_public(row)


def request_qualified_signature(db: Session, business_id: int, user_id: int, position_id: int, letter_id: int, provider_id: int, is_admin: bool = False) -> dict:
	resolve_acting_position(db, business_id, user_id, position_id, required_scope="refer")
	letter = db.query(OaLetter).filter(OaLetter.id == letter_id, OaLetter.business_id == business_id).first()
	provider = db.query(OaSignatureProvider).filter(OaSignatureProvider.id == provider_id, OaSignatureProvider.business_id == business_id, OaSignatureProvider.is_active.is_(True)).first()
	if letter is None or provider is None:
		raise ApiError("OA_PROVIDER_NOT_FOUND", "Letter or provider was not found.", http_status=404)
	if not _can_view_letter(db, letter, user_id, is_admin):
		raise ApiError("OA_LETTER_FORBIDDEN", "You cannot request a signature for a letter you cannot view.", http_status=403)
	if letter.confidentiality in _CLASSIFIED:
		raise ApiError(
			"OA_CLASSIFIED_EXTERNAL",
			"A classified letter is not sent to a signature provider.",
			http_status=403,
		)
	image_status = letter.sign_status
	row = OaQualifiedSignRequest(
		business_id=business_id,
		letter_id=letter.id,
		provider_id=provider.id,
		requested_by_user_id=user_id,
		status="awaiting_provider",
		created_at=_now(),
	)
	letter.qualified_sign_status = "pending"
	db.add(row)
	_audit(db, business_id=business_id, user_id=user_id, action="signature.provider.request", letter_id=letter.id, position_id=position_id, payload={"provider_id": provider.id, "live": bool(provider.endpoint_url)})
	db.commit()
	db.refresh(letter)
	db.refresh(row)
	if not provider.endpoint_url:
		return _sign_result(letter, row, image_status, delivered=False)
	try:
		answer = post_signature_provider(
			provider.endpoint_url,
			{"request_id": row.id, "business_id": business_id, "letter_id": letter.id, "number": letter.secretariat_number},
			provider.access_token,
		)
	except ApiError as exc:
		return _sign_result(letter, row, image_status, delivered=False, delivery_error=exc.code)
	outcome = answer["outcome"]
	ref = answer["external_ref"]
	if outcome in {"completed", "rejected"} and len(ref) >= 4:
		return _finish_provider_result(db, row, letter, user_id, ref, outcome, image_status)
	if len(ref) >= 4:
		row.external_ref = ref[:120]
		db.commit()
	db.refresh(letter)
	return _sign_result(letter, row, image_status, delivered=True)


def _sign_result(letter: OaLetter, row: OaQualifiedSignRequest, image_status: str, **extra) -> dict:
	return {
		"id": row.id,
		"status": row.status,
		"external_ref": row.external_ref,
		"sign_status": letter.sign_status,
		"qualified_sign_status": letter.qualified_sign_status,
		"image_sign_unchanged": letter.sign_status == image_status,
		"assurance": "provider_attestation",
		**extra,
	}


def _finish_provider_result(db: Session, row: OaQualifiedSignRequest, letter: OaLetter, user_id: int, external_ref: str, outcome: str, image_status: str) -> dict:
	row.status = outcome
	row.external_ref = external_ref[:120]
	row.completed_at = _now()
	letter.qualified_sign_status = "completed" if outcome == "completed" else "rejected"
	_audit(db, business_id=row.business_id, user_id=user_id, action="signature.provider.result", letter_id=letter.id, payload={"outcome": outcome, "request_id": row.id})
	db.commit()
	db.refresh(letter)
	db.refresh(row)
	return _sign_result(letter, row, image_status, delivered=True)


def record_provider_result(db: Session, business_id: int, user_id: int, request_id: int, external_ref: str, outcome: str) -> dict:
	_ensure_plugin(db, business_id)
	ref = str(external_ref or "").strip()
	if outcome not in {"completed", "rejected"} or len(ref) < 4:
		raise ApiError("OA_PROVIDER_RESULT_INVALID", "Provider result needs an external reference.", http_status=400)
	row = db.query(OaQualifiedSignRequest).filter(OaQualifiedSignRequest.id == request_id, OaQualifiedSignRequest.business_id == business_id).first()
	if row is None or row.status != "awaiting_provider":
		raise ApiError("OA_PROVIDER_REQUEST_CLOSED", "Provider request is not awaiting a result.", http_status=400)
	provider = db.query(OaSignatureProvider).filter(OaSignatureProvider.id == row.provider_id).first()
	if provider is not None and provider.endpoint_url:
		raise ApiError("OA_PROVIDER_LIVE", "A live provider result comes from its endpoint.", http_status=409)
	letter = db.query(OaLetter).filter(OaLetter.id == row.letter_id).first()
	if letter is None:
		raise ApiError("OA_LETTER_NOT_FOUND", "Letter was not found.", http_status=404)
	return _finish_provider_result(db, row, letter, user_id, ref, outcome, letter.sign_status)


def _visible_letter(db: Session, business_id: int, user_id: int, position_id: int, letter_id: int, *, scope: str) -> tuple[OaLetter, int]:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope=scope)
	letter = db.query(OaLetter).filter(OaLetter.id == letter_id, OaLetter.business_id == business_id).first()
	if letter is None or not _can_view_letter(db, letter, user_id, False):
		raise ApiError("OA_LETTER_FORBIDDEN", "You cannot view this letter.", http_status=403)
	return letter, position.id


def _commercial_label(db: Session, business_id: int, kind: str, target_id: int, user_id: int | None = None, *, write: bool = False) -> str:
	if kind == "document":
		assert_document_in_business(db, business_id, target_id)
		row = db.get(Document, int(target_id))
		return row.code if row is not None else str(target_id)
	if kind == "deal":
		row = db.query(Deal).filter(Deal.id == int(target_id), Deal.business_id == business_id).first()
		if row is None:
			raise ApiError("OA_DEAL_NOT_FOUND", "Deal was not found in this business.", http_status=404)
		if user_id is not None:
			from app.services.crm_enterprise_service import acl_actor, assert_can_view_record

			assert_can_view_record(db, business_id, acl_actor(db, int(user_id)), "deal", row, write=write)
		return row.title
	raise ApiError("OA_LINK_KIND_INVALID", "Link target must be a document or a deal.", http_status=400)


def link_letter_commercial(db: Session, business_id: int, user_id: int, position_id: int, letter_id: int, target_kind: str, target_id: int) -> dict:
	letter, acting_id = _visible_letter(db, business_id, user_id, position_id, letter_id, scope="full")
	kind = str(target_kind or "").strip()
	label = _commercial_label(db, business_id, kind, int(target_id), user_id, write=True)
	body_before = letter.body
	existing = (
		db.query(OaLetterCommercialLink)
		.filter(
			OaLetterCommercialLink.letter_id == letter.id,
			OaLetterCommercialLink.target_kind == kind,
			OaLetterCommercialLink.target_id == int(target_id),
		)
		.first()
	)
	if existing is None:
		existing = OaLetterCommercialLink(
			business_id=business_id,
			letter_id=letter.id,
			target_kind=kind,
			target_id=int(target_id),
			created_by_user_id=user_id,
			created_at=_now(),
		)
		db.add(existing)
		_audit(db, business_id=business_id, user_id=user_id, action="letter.link.commercial", letter_id=letter.id, position_id=acting_id, payload={"target_kind": kind, "target_id": int(target_id)})
		db.commit()
		db.refresh(existing)
	db.refresh(letter)
	if letter.body != body_before:
		raise ApiError("OA_LINK_MUTATED_LETTER", "Linking must not change the letter.", http_status=500)
	return {"id": existing.id, "letter_id": letter.id, "target_kind": kind, "target_id": int(target_id), "label": label}


def list_letter_qualified_requests(db: Session, business_id: int, user_id: int, position_id: int, letter_id: int) -> dict:
	letter, _acting = _visible_letter(db, business_id, user_id, position_id, letter_id, scope="view")
	rows = (
		db.query(OaQualifiedSignRequest, OaSignatureProvider)
		.join(OaSignatureProvider, OaSignatureProvider.id == OaQualifiedSignRequest.provider_id)
		.filter(OaQualifiedSignRequest.letter_id == letter.id, OaQualifiedSignRequest.business_id == business_id)
		.order_by(OaQualifiedSignRequest.id)
		.all()
	)
	return {
		"items": [
			{
				"id": request.id,
				"status": request.status,
				"external_ref": request.external_ref,
				"provider_id": provider.id,
				"provider_name": provider.name,
				"live": bool(provider.endpoint_url),
				"assurance": "provider_attestation",
				"sign_status": letter.sign_status,
				"qualified_sign_status": letter.qualified_sign_status,
			}
			for request, provider in rows
		]
	}


def list_letter_commercial_links(db: Session, business_id: int, user_id: int, position_id: int, letter_id: int) -> dict:
	letter, _acting = _visible_letter(db, business_id, user_id, position_id, letter_id, scope="view")
	rows = (
		db.query(OaLetterCommercialLink)
		.filter(OaLetterCommercialLink.letter_id == letter.id, OaLetterCommercialLink.business_id == business_id)
		.order_by(OaLetterCommercialLink.id)
		.all()
	)
	items = []
	for row in rows:
		try:
			label = _commercial_label(db, business_id, row.target_kind, row.target_id, user_id)
		except ApiError:
			continue
		items.append({"id": row.id, "target_kind": row.target_kind, "target_id": row.target_id, "label": label})
	return {"items": items}


def exchange_letter(db: Session, business_id: int, user_id: int, position_id: int, letter_id: int, target_business_id: int, target_position_id: int, is_admin: bool = False) -> dict:
	resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	if int(target_business_id) == int(business_id):
		raise ApiError("OA_EXCHANGE_SAME_BUSINESS", "Choose another business.", http_status=400)
	source = db.query(OaLetter).filter(OaLetter.id == letter_id, OaLetter.business_id == business_id).first()
	if source is None:
		raise ApiError("OA_LETTER_NOT_FOUND", "Letter was not found.", http_status=404)
	if not _can_view_letter(db, source, user_id, is_admin):
		raise ApiError("OA_LETTER_FORBIDDEN", "You cannot exchange a letter you cannot view.", http_status=403)
	if source.confidentiality in _CLASSIFIED or source.status == "draft":
		raise ApiError("OA_EXCHANGE_FORBIDDEN", "Only a registered normal letter can be exchanged.", http_status=403)
	_ensure_plugin(db, target_business_id)
	target_position = db.query(OaPosition).filter(OaPosition.id == target_position_id, OaPosition.business_id == target_business_id, OaPosition.is_active.is_(True), OaPosition.is_secretariat.is_(True)).first()
	holder = (
		db.query(OaPositionHolder)
		.filter(OaPositionHolder.position_id == target_position_id, OaPositionHolder.business_id == target_business_id, OaPositionHolder.is_active.is_(True))
		.order_by(OaPositionHolder.is_primary.desc())
		.first()
	)
	if target_position is None or holder is None:
		raise ApiError("OA_EXCHANGE_TARGET", "Target secretariat position has no active holder.", http_status=400)
	draft = create_letter_draft(
		db,
		target_business_id,
		{"subject": source.subject, "body": source.body or "", "letter_kind": "incoming", "confidentiality": "normal"},
		holder.user_id,
		target_position.id,
	)
	link = OaLetterExchange(
		source_business_id=business_id,
		source_letter_id=source.id,
		target_business_id=target_business_id,
		target_letter_id=int(draft["id"]),
		created_by_user_id=user_id,
		created_at=_now(),
	)
	db.add(link)
	_audit(db, business_id=business_id, user_id=user_id, action="letter.exchange", letter_id=source.id, position_id=position_id, payload={"target_business_id": target_business_id, "target_letter_id": draft["id"]})
	db.commit()
	return {"source_letter_id": source.id, "target_letter_id": draft["id"], "target_status": draft["status"], "copied_confidentiality": "normal"}
