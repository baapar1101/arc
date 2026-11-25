"""سند، نسخه و صف OCR. بایت فایل در FileStorage می‌ماند و پیشنهاد استخراج تا تأیید اعمال نمی‌شود."""
from __future__ import annotations

import re
from datetime import datetime
from typing import List, Optional

from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from adapters.db.models.file_storage import FileStorage
from adapters.db.models.oa_document import OaDocument, OaDocumentVersion, OaExtractionSuggestion, OaOcrJob
from adapters.db.models.office_automation import OaLetter
from app.core.responses import ApiError
from app.services.office_automation_service import _audit, _can_view_letter, resolve_acting_position

_CONFIDENTIALITY = frozenset({"normal", "confidential", "highly_confidential", "secret"})
_CLASSIFIED = frozenset({"confidential", "highly_confidential", "secret"})
_FIELDS = {"title": re.compile(r"موضوع\s*[:：]\s*(.+)"), "number": re.compile(r"شماره\s*[:：]\s*(.+)")}


def _now() -> datetime:
	return datetime.utcnow()


def _file(db: Session, business_id: int, file_id: str) -> FileStorage:
	row = db.query(FileStorage).filter(FileStorage.id == file_id).first()
	if row is None or row.business_id not in (None, business_id) or row.deleted_at is not None:
		raise ApiError("FILE_NOT_FOUND", "Document file was not found.", http_status=404)
	return row


def _is_classified(value: Optional[str]) -> bool:
	return (value or "normal") in _CLASSIFIED


def _can_view(db: Session, doc: OaDocument, user_id: int, is_admin: bool) -> bool:
	if is_admin or doc.created_by_user_id == user_id:
		return True
	if not doc.letter_id:
		return False
	letter = db.query(OaLetter).filter(OaLetter.id == doc.letter_id, OaLetter.business_id == doc.business_id).first()
	if letter is None or not _can_view_letter(db, letter, user_id, False):
		return False
	if _is_classified(doc.confidentiality) and not _is_classified(letter.confidentiality):
		return False
	return True


def _require(db: Session, business_id: int, doc_id: int, user_id: int, is_admin: bool) -> OaDocument:
	row = db.query(OaDocument).filter(OaDocument.id == doc_id, OaDocument.business_id == business_id).first()
	if row is None or not _can_view(db, row, user_id, is_admin):
		raise ApiError("OA_DOCUMENT_FORBIDDEN", "Document was not found.", http_status=404)
	return row


def _version_dict(row: OaDocumentVersion) -> dict:
	return {
		"id": row.id,
		"version_no": row.version_no,
		"file_storage_id": row.file_storage_id,
		"has_text": bool(row.extracted_text),
		"created_at": row.created_at,
	}


def _suggestion_dict(row: OaExtractionSuggestion) -> dict:
	return {
		"id": row.id,
		"field_key": row.field_key,
		"suggested_value": row.suggested_value,
		"status": row.status,
		"version_id": row.version_id,
	}


def _document_dict(db: Session, row: OaDocument) -> dict:
	versions = (
		db.query(OaDocumentVersion)
		.filter(OaDocumentVersion.document_id == row.id)
		.order_by(OaDocumentVersion.version_no)
		.all()
	)
	suggestions = (
		db.query(OaExtractionSuggestion)
		.filter(OaExtractionSuggestion.document_id == row.id, OaExtractionSuggestion.status == "pending")
		.order_by(OaExtractionSuggestion.id)
		.all()
	)
	return {
		"id": row.id,
		"title": row.title,
		"confidentiality": row.confidentiality,
		"letter_id": row.letter_id,
		"reference_no": row.reference_no,
		"current_version_id": row.current_version_id,
		"retain_until": row.retain_until,
		"retention_status": row.retention_status,
		"created_at": row.created_at,
		"versions": [_version_dict(item) for item in versions],
		"suggestions": [_suggestion_dict(item) for item in suggestions],
	}


def _enqueue(db: Session, business_id: int, version: OaDocumentVersion) -> None:
	db.add(OaOcrJob(business_id=business_id, document_version_id=version.id, status="queued", created_at=_now()))


def register_document(
	db: Session,
	business_id: int,
	user_id: int,
	position_id: int,
	payload: dict,
	*,
	is_admin: bool = False,
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	title = str(payload.get("title") or "").strip()
	if not title:
		raise ApiError("OA_DOCUMENT_TITLE_REQUIRED", "Document title is required.", http_status=400)
	confidentiality = str(payload.get("confidentiality") or "normal")
	if confidentiality not in _CONFIDENTIALITY:
		raise ApiError("OA_DOCUMENT_CONFIDENTIALITY_INVALID", "Unknown confidentiality.", http_status=400)
	file_row = _file(db, business_id, str(payload.get("file_storage_id") or ""))
	letter_id = payload.get("letter_id")
	if letter_id:
		letter = db.query(OaLetter).filter(OaLetter.id == int(letter_id), OaLetter.business_id == business_id).first()
		if letter is None or not _can_view_letter(db, letter, user_id, is_admin):
			raise ApiError("OA_LETTER_FORBIDDEN", "You cannot attach a document to this letter.", http_status=403)
		letter_id = letter.id
	assert_file_stays_on_document(
		db,
		business_id,
		user_id,
		file_row.id,
		document_id=None,
		letter_id=int(letter_id) if letter_id else None,
		confidentiality=confidentiality,
		is_admin=is_admin,
	)
	doc = OaDocument(
		business_id=business_id,
		title=title[:500],
		confidentiality=confidentiality,
		letter_id=int(letter_id) if letter_id else None,
		search_text=title[:500],
		created_by_user_id=user_id,
		created_at=_now(),
		updated_at=_now(),
	)
	db.add(doc)
	db.flush()
	version = OaDocumentVersion(
		business_id=business_id,
		document_id=doc.id,
		version_no=1,
		file_storage_id=file_row.id,
		created_by_user_id=user_id,
		created_at=_now(),
	)
	db.add(version)
	db.flush()
	doc.current_version_id = version.id
	_enqueue(db, business_id, version)
	from app.services.oa_enterprise_service import apply_document_scope
	apply_document_scope(db, doc)
	_audit(db, business_id=business_id, user_id=user_id, action="document.register", letter_id=doc.letter_id, position_id=position.id, payload={"document_id": doc.id})
	db.commit()
	db.refresh(doc)
	return _document_dict(db, doc)


def add_document_version(
	db: Session,
	business_id: int,
	user_id: int,
	position_id: int,
	document_id: int,
	file_storage_id: str,
	*,
	is_admin: bool = False,
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	doc = _require(db, business_id, document_id, user_id, is_admin)
	file_row = _file(db, business_id, file_storage_id)
	assert_file_stays_on_document(
		db,
		business_id,
		user_id,
		file_row.id,
		document_id=doc.id,
		letter_id=doc.letter_id,
		confidentiality=doc.confidentiality,
		is_admin=is_admin,
	)
	last = (
		db.query(OaDocumentVersion.version_no)
		.filter(OaDocumentVersion.document_id == doc.id)
		.order_by(OaDocumentVersion.version_no.desc())
		.first()
	)
	version = OaDocumentVersion(
		business_id=business_id,
		document_id=doc.id,
		version_no=(last[0] if last else 0) + 1,
		file_storage_id=file_row.id,
		created_by_user_id=user_id,
		created_at=_now(),
	)
	db.add(version)
	db.flush()
	doc.current_version_id = version.id
	doc.updated_at = _now()
	_enqueue(db, business_id, version)
	_audit(db, business_id=business_id, user_id=user_id, action="document.version", letter_id=doc.letter_id, position_id=position.id, payload={"document_id": doc.id, "version_no": version.version_no})
	db.commit()
	db.refresh(doc)
	return _document_dict(db, doc)


def get_document(db: Session, business_id: int, user_id: int, position_id: int, document_id: int, *, is_admin: bool = False) -> dict:
	resolve_acting_position(db, business_id, user_id, position_id, required_scope="view")
	return _document_dict(db, _require(db, business_id, document_id, user_id, is_admin))


def visible_document_clause(db: Session, business_id: int, user_id: int):
	from app.services.office_automation_service import _visible_letter_clause

	visible_letters = db.query(OaLetter.id).filter(
		OaLetter.business_id == business_id,
		_visible_letter_clause(db, business_id, user_id, False),
	)
	visible_classified = visible_letters.filter(OaLetter.confidentiality.in_(tuple(_CLASSIFIED)))
	doc_classified = OaDocument.confidentiality.in_(tuple(_CLASSIFIED))
	return or_(
		OaDocument.created_by_user_id == user_id,
		and_(~doc_classified, OaDocument.letter_id.in_(visible_letters)),
		and_(doc_classified, OaDocument.letter_id.in_(visible_classified)),
	)


def hidden_oa_file_ids(db: Session, business_id: int, user_id: int):
	from adapters.db.models.office_automation import OaLetterAttachment
	from app.services.office_automation_service import _visible_letter_clause

	letter_files = (
		db.query(OaLetterAttachment.file_storage_id.label("file_storage_id"))
		.join(OaLetter, OaLetter.id == OaLetterAttachment.letter_id)
		.filter(
			OaLetterAttachment.business_id == business_id,
			~_visible_letter_clause(db, business_id, user_id, False),
		)
	)
	document_files = (
		db.query(OaDocumentVersion.file_storage_id.label("file_storage_id"))
		.join(OaDocument, OaDocument.id == OaDocumentVersion.document_id)
		.filter(
			OaDocument.business_id == business_id,
			~visible_document_clause(db, business_id, user_id),
		)
	)
	return letter_files.union(document_files)


def restrict_file_query(query, db: Session, business_id: int, user_id: Optional[int], is_admin: bool = False):
	from adapters.db.models.file_storage import FileStorage

	if is_admin or user_id is None:
		return query
	return query.filter(~FileStorage.id.in_(hidden_oa_file_ids(db, business_id, int(user_id))))


def require_business_file(db: Session, business_id: int, file_id: str) -> FileStorage:
	"""فایل باید به همان کسب‌وکار نشانی تعلق داشته باشد. نبودن و کسب‌وکار دیگر هر دو ۴۰۴ هستند."""
	row = (
		db.query(FileStorage)
		.filter(
			FileStorage.id == str(file_id),
			FileStorage.business_id == business_id,
			FileStorage.deleted_at.is_(None),
		)
		.first()
	)
	if row is None:
		raise ApiError("FILE_NOT_FOUND", "File was not found.", http_status=404)
	return row


def require_oa_file_visible(db: Session, business_id: int, user_id: int, file_id: str, *, is_admin: bool = False) -> None:
	if is_admin:
		return
	hidden = hidden_oa_file_ids(db, business_id, user_id).subquery()
	found = db.query(hidden.c.file_storage_id).filter(hidden.c.file_storage_id == str(file_id)).first()
	if found is not None:
		raise ApiError("FILE_NOT_FOUND", "File was not found.", http_status=404)


def classified_file_anchors(db: Session, file_id: str) -> tuple[set[int], set[int]]:
	"""نامه‌ها و سندهایی که این فایل را در محدوده طبقه‌بندی نگه می‌دارند."""
	from adapters.db.models.office_automation import OaLetterAttachment

	file_key = str(file_id)
	letter_ids = {
		row[0]
		for row in db.query(OaLetter.id)
		.join(OaLetterAttachment, OaLetterAttachment.letter_id == OaLetter.id)
		.filter(
			OaLetterAttachment.file_storage_id == file_key,
			OaLetter.confidentiality.in_(tuple(_CLASSIFIED)),
		)
		.all()
	}
	document_ids: set[int] = set()
	rows = (
		db.query(OaDocument.id, OaDocument.letter_id, OaDocument.confidentiality, OaLetter.confidentiality)
		.join(OaDocumentVersion, OaDocumentVersion.document_id == OaDocument.id)
		.outerjoin(OaLetter, OaLetter.id == OaDocument.letter_id)
		.filter(OaDocumentVersion.file_storage_id == file_key)
		.all()
	)
	for doc_id, letter_id, doc_confidentiality, letter_confidentiality in rows:
		if doc_confidentiality not in _CLASSIFIED and letter_confidentiality not in _CLASSIFIED:
			continue
		document_ids.add(doc_id)
		if letter_id is not None:
			letter_ids.add(int(letter_id))
	return letter_ids, document_ids


def _refuse_classified_file_move() -> None:
	raise ApiError(
		"OA_CLASSIFIED_EXTERNAL",
		"A classified office file stays on its own letter or document.",
		http_status=403,
	)


def assert_file_stays_on_letter(db: Session, business_id: int, user_id: int, file_id: str, letter: OaLetter, *, is_admin: bool = False) -> None:
	require_oa_file_visible(db, business_id, user_id, file_id, is_admin=is_admin)
	letter_ids, document_ids = classified_file_anchors(db, file_id)
	if not letter_ids and not document_ids:
		return
	if not _is_classified(letter.confidentiality) or letter_ids - {letter.id}:
		_refuse_classified_file_move()
	if not document_ids:
		return
	foreign = (
		db.query(OaDocument.id)
		.filter(
			OaDocument.id.in_(document_ids),
			or_(OaDocument.letter_id.is_(None), OaDocument.letter_id != letter.id),
		)
		.first()
	)
	if foreign is not None:
		_refuse_classified_file_move()


def assert_file_stays_on_document(
	db: Session,
	business_id: int,
	user_id: int,
	file_id: str,
	*,
	document_id: Optional[int],
	letter_id: Optional[int],
	confidentiality: str,
	is_admin: bool = False,
) -> None:
	require_oa_file_visible(db, business_id, user_id, file_id, is_admin=is_admin)
	letter_ids, document_ids = classified_file_anchors(db, file_id)
	if not letter_ids and not document_ids:
		return
	allowed_documents = {int(document_id)} if document_id else set()
	allowed_letters = {int(letter_id)} if letter_id else set()
	if not _is_classified(confidentiality) or document_ids - allowed_documents or letter_ids - allowed_letters:
		_refuse_classified_file_move()


def refuse_external_oa_file(db: Session, file_id: str, *, public: bool = False) -> None:
	from adapters.db.models.office_automation import OaLetterAttachment

	file_key = str(file_id)
	classified_letter = (
		db.query(OaLetter.id)
		.join(OaLetterAttachment, OaLetterAttachment.letter_id == OaLetter.id)
		.filter(
			OaLetterAttachment.file_storage_id == file_key,
			OaLetter.confidentiality.in_(tuple(_CLASSIFIED)),
		)
		.first()
	)
	classified_document = (
		db.query(OaDocument.id)
		.join(OaDocumentVersion, OaDocumentVersion.document_id == OaDocument.id)
		.filter(
			OaDocumentVersion.file_storage_id == file_key,
			OaDocument.confidentiality.in_(tuple(_CLASSIFIED)),
		)
		.first()
	)
	on_classified_letter = (
		db.query(OaDocument.id)
		.join(OaDocumentVersion, OaDocumentVersion.document_id == OaDocument.id)
		.join(OaLetter, OaLetter.id == OaDocument.letter_id)
		.filter(
			OaDocumentVersion.file_storage_id == file_key,
			OaLetter.confidentiality.in_(tuple(_CLASSIFIED)),
		)
		.first()
	)
	if classified_letter or classified_document or on_classified_letter:
		if public:
			raise ApiError("FILE_NOT_FOUND", "File was not found.", http_status=404)
		raise ApiError(
			"OA_CLASSIFIED_EXTERNAL",
			"Classified office files cannot be shared outside the organization.",
			http_status=403,
		)


def search_documents(
	db: Session,
	business_id: int,
	user_id: int,
	position_id: int,
	q: str = "",
	*,
	is_admin: bool = False,
) -> dict:
	resolve_acting_position(db, business_id, user_id, position_id, required_scope="view")
	query = db.query(OaDocument).filter(OaDocument.business_id == business_id)
	text = str(q or "").strip()
	if text:
		like = f"%{text}%"
		query = query.filter(or_(OaDocument.title.ilike(like), OaDocument.search_text.ilike(like), OaDocument.reference_no.ilike(like)))
	if not is_admin:
		query = query.filter(visible_document_clause(db, business_id, user_id))
	rows = query.order_by(OaDocument.updated_at.desc()).limit(100).all()
	items = [
		{
			"id": row.id,
			"title": row.title,
			"confidentiality": row.confidentiality,
			"reference_no": row.reference_no,
			"current_version_id": row.current_version_id,
		}
		for row in rows
	]
	return {"items": items, "total": len(items)}


def _apply_suggestion(doc: OaDocument, field_key: str, value: str) -> None:
	if field_key == "title":
		doc.title = value[:500]
	elif field_key == "number":
		doc.reference_no = value[:120]
	doc.updated_at = _now()


def decide_suggestion(
	db: Session,
	business_id: int,
	user_id: int,
	position_id: int,
	suggestion_id: int,
	*,
	accept: bool,
	is_admin: bool = False,
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="full")
	row = (
		db.query(OaExtractionSuggestion)
		.filter(OaExtractionSuggestion.id == suggestion_id, OaExtractionSuggestion.business_id == business_id)
		.first()
	)
	if row is None:
		raise ApiError("OA_SUGGESTION_NOT_FOUND", "Suggestion was not found.", http_status=404)
	doc = _require(db, business_id, row.document_id, user_id, is_admin)
	if row.status != "pending":
		raise ApiError("OA_SUGGESTION_CLOSED", "Suggestion is already decided.", http_status=400)
	row.status = "accepted" if accept else "rejected"
	row.confirmed_by_user_id = user_id
	row.confirmed_at = _now()
	if accept:
		_apply_suggestion(doc, row.field_key, row.suggested_value)
	_audit(
		db,
		business_id=business_id,
		user_id=user_id,
		action="document.suggestion.accept" if accept else "document.suggestion.reject",
		letter_id=doc.letter_id,
		position_id=position.id,
		payload={"document_id": doc.id, "suggestion_id": row.id},
	)
	db.commit()
	db.refresh(doc)
	return _document_dict(db, doc)


def _suggestions_from_text(text: str) -> List[tuple]:
	found = []
	for field, pattern in _FIELDS.items():
		match = pattern.search(text or "")
		if match:
			value = match.group(1).strip()
			if value:
				found.append((field, value[:500]))
	return found


def _finish_letter_attachment_job(db: Session, job: OaOcrJob) -> None:
	from app.services.office_automation_extended_service import extract_attachment_text, refresh_letter_search_text
	from adapters.db.models.office_automation import OaLetter, OaLetterAttachment

	att = db.query(OaLetterAttachment).filter(OaLetterAttachment.id == job.letter_attachment_id).first()
	if att is None:
		return
	file_row = db.query(FileStorage).filter(FileStorage.id == att.file_storage_id).first()
	text = (extract_attachment_text(file_row) if file_row is not None else "") or ""
	att.ocr_text = text[:20000] or None
	letter = db.query(OaLetter).filter(OaLetter.id == att.letter_id).one()
	rows = db.query(OaLetterAttachment).filter(OaLetterAttachment.letter_id == letter.id).all()
	letter.ocr_text = "\n".join(row.ocr_text for row in rows if row.ocr_text)[:20000] or None
	refresh_letter_search_text(db, letter)


def process_ocr_queue(db: Session, business_id: Optional[int] = None, limit: int = 20) -> dict:
	from app.services.office_automation_extended_service import extract_attachment_text

	query = db.query(OaOcrJob).filter(OaOcrJob.status == "queued").order_by(OaOcrJob.id)
	if business_id:
		query = query.filter(OaOcrJob.business_id == business_id)
	done = 0
	failed = 0
	for job in query.limit(max(1, min(int(limit or 20), 50))).all():
		if job.letter_attachment_id:
			try:
				_finish_letter_attachment_job(db, job)
				job.status = "done"
				job.finished_at = _now()
				done += 1
			except Exception as exc:
				job.status = "failed"
				job.error = str(exc)[:500]
				job.finished_at = _now()
				failed += 1
			continue
		version = db.query(OaDocumentVersion).filter(OaDocumentVersion.id == job.document_version_id).first()
		file_row = db.query(FileStorage).filter(FileStorage.id == version.file_storage_id).first() if version else None
		try:
			text = extract_attachment_text(file_row) if file_row is not None else ""
			if version is not None:
				version.extracted_text = (text or "")[:20000] or None
				doc = db.query(OaDocument).filter(OaDocument.id == version.document_id).one()
				if doc.current_version_id == version.id:
					doc.search_text = "\n".join(part for part in (doc.title, doc.reference_no, version.extracted_text) if part)[:20000]
				for field, value in _suggestions_from_text(text or ""):
					db.add(
						OaExtractionSuggestion(
							business_id=job.business_id,
							document_id=version.document_id,
							version_id=version.id,
							field_key=field,
							suggested_value=value,
							status="pending",
							created_at=_now(),
						)
					)
			job.status = "done"
			job.finished_at = _now()
			done += 1
		except Exception as exc:
			job.status = "failed"
			job.error = str(exc)[:500]
			job.finished_at = _now()
			failed += 1
	db.commit()
	return {"done": done, "failed": failed}
