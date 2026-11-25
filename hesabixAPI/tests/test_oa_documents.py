"""سند روی FileStorage، نسخه، صف OCR و تأیید پیشنهاد."""
from __future__ import annotations

from unittest.mock import patch

import pytest

from adapters.db.models.file_storage import FileStorage
from adapters.db.models.oa_document import OaDocumentVersion, OaOcrJob
from app.services import oa_document_service as docs
from app.services import office_automation_service as oa
from tests.test_office_automation_plugin import _session, _user


def _file(db, user_id, file_id):
	row = FileStorage(
		id=file_id,
		original_name=f"{file_id}.txt",
		stored_name=f"{file_id}.txt",
		file_path=f"/tmp/{file_id}.txt",
		file_size=12,
		mime_type="text/plain",
		storage_type="local",
		uploaded_by=user_id,
		business_id=1,
		module_context="office_automation",
		is_active=True,
		is_temporary=False,
		is_verified=False,
		is_marked_for_deletion=False,
	)
	db.add(row)
	db.commit()
	return row


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_document_ocr_waits_for_confirmation_and_keeps_versions(_plugin):
	db = _session()
	owner = _user(db, "doc-owner@example.com", "d1")
	stranger = _user(db, "doc-stranger@example.com", "d2")
	bid = 1
	unit = oa.create_org_unit(db, bid, {"code": "docs", "name_i18n": {"fa": "اسناد", "en": "Docs"}}, owner.id)
	src = oa.create_position(db, bid, {"code": "arch", "org_unit_id": unit["id"], "name_i18n": {"fa": "بایگان", "en": "Archivist"}, "is_secretariat": True}, owner.id)
	other = oa.create_position(db, bid, {"code": "guest", "org_unit_id": unit["id"], "name_i18n": {"fa": "مهمان", "en": "Guest"}}, owner.id)
	oa.assign_position_holder(db, bid, {"position_id": src["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, bid, {"position_id": other["id"], "user_id": stranger.id, "is_primary": True}, owner.id)
	_file(db, owner.id, "file-secret")
	_file(db, owner.id, "file-next")
	created = docs.register_document(
		db, bid, owner.id, src["id"],
		{"title": "پوشه سری", "confidentiality": "secret", "file_storage_id": "file-secret"},
	)
	assert created["versions"][0]["version_no"] == 1
	assert created["versions"][0]["has_text"] is False
	assert db.query(OaOcrJob).filter(OaOcrJob.status == "queued").count() == 1
	hidden = docs.search_documents(db, bid, stranger.id, other["id"], "پوشه")
	assert hidden["items"] == []
	with patch(
		"app.services.office_automation_extended_service.extract_attachment_text",
		return_value="موضوع: قرارداد تازه\nشماره: ۱۲۳",
	):
		stats = docs.process_ocr_queue(db, bid)
	assert stats["done"] == 1
	opened = docs.get_document(db, bid, owner.id, src["id"], created["id"])
	assert opened["title"] == "پوشه سری"
	assert opened["versions"][0]["has_text"] is True
	assert {item["field_key"] for item in opened["suggestions"]} == {"title", "number"}
	title_suggestion = next(item for item in opened["suggestions"] if item["field_key"] == "title")
	accepted = docs.decide_suggestion(db, bid, owner.id, src["id"], title_suggestion["id"], accept=True)
	assert accepted["title"] == "قرارداد تازه"
	number_suggestion = next(item for item in opened["suggestions"] if item["field_key"] == "number")
	rejected = docs.decide_suggestion(db, bid, owner.id, src["id"], number_suggestion["id"], accept=False)
	assert rejected["reference_no"] is None
	versioned = docs.add_document_version(db, bid, owner.id, src["id"], created["id"], "file-next")
	assert [item["version_no"] for item in versioned["versions"]] == [1, 2]
	assert db.query(OaDocumentVersion).filter(OaDocumentVersion.document_id == created["id"]).count() == 2
	visible = docs.search_documents(db, bid, owner.id, src["id"], "قرارداد")
	assert any(item["id"] == created["id"] for item in visible["items"])
	db.close()


@patch("app.services.office_automation_extended_service.extract_attachment_text", return_value="متن پیوست")
@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_letter_attachment_ocr_stays_queued_until_the_background_tick(_plugin, extract):
	from app.services import office_automation_extended_service as ext
	from adapters.db.models.office_automation import OaLetter

	db = _session()
	owner = _user(db, "ocr-owner@example.com", "o1")
	unit = oa.create_org_unit(db, 1, {"code": "ocr", "name_i18n": {"fa": "متن", "en": "Text"}}, owner.id)
	position = oa.create_position(
		db, 1, {"code": "p_ocr", "org_unit_id": unit["id"], "name_i18n": {"fa": "دبیر", "en": "Clerk"}, "is_secretariat": True}, owner.id,
	)
	oa.assign_position_holder(db, 1, {"position_id": position["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	_file(db, owner.id, "file-letter")
	draft = oa.create_letter_draft(db, 1, {"subject": "نامه پیوست", "letter_kind": "internal"}, owner.id, position["id"])
	extract.reset_mock()
	oa.add_attachment(db, 1, draft["id"], {"file_storage_id": "file-letter", "title": "اسکن"}, owner.id, position["id"])
	assert extract.call_count == 0
	assert db.query(OaOcrJob).filter(OaOcrJob.status == "queued", OaOcrJob.letter_attachment_id.isnot(None)).count() == 1
	letter = db.query(OaLetter).filter(OaLetter.id == draft["id"]).one()
	assert not letter.ocr_text
	again = ext.ocr_letter_attachments(db, 1, draft["id"], owner.id, position["id"])
	assert again["ocr_queued"] == 0
	assert db.query(OaOcrJob).filter(OaOcrJob.status == "queued").count() == 1
	stats = docs.process_ocr_queue(db, 1)
	assert stats["done"] == 1
	assert extract.call_count == 1
	db.refresh(letter)
	assert letter.ocr_text == "متن پیوست"
	assert "متن پیوست" in (letter.search_text or "")
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_secret_document_on_a_normal_letter_stays_hidden(_plugin):
	from datetime import date, datetime

	from app.core.responses import ApiError
	from app.services import oa_enterprise_service as ent
	from adapters.db.models.oa_document import OaDocument

	db = _session()
	owner = _user(db, "doc-secret-owner@example.com", "ds1")
	reader = _user(db, "doc-secret-reader@example.com", "ds2")
	unit = oa.create_org_unit(db, 1, {"code": "dsec", "name_i18n": {"fa": "اسناد", "en": "Docs"}}, owner.id)
	sender = oa.create_position(
		db, 1, {"code": "p_dsec", "org_unit_id": unit["id"], "name_i18n": {"fa": "بایگان", "en": "Archivist"}, "is_secretariat": True}, owner.id,
	)
	inbox = oa.create_position(db, 1, {"code": "p_dsec_in", "org_unit_id": unit["id"], "name_i18n": {"fa": "گیرنده", "en": "Inbox"}}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": sender["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": inbox["id"], "user_id": reader.id, "is_primary": True}, owner.id)
	_file(db, owner.id, "file-secret-doc")
	_file(db, owner.id, "file-open-doc")
	draft = oa.create_letter_draft(db, 1, {"subject": "نامه عادی سند", "letter_kind": "internal"}, owner.id, sender["id"])
	registered = oa.register_letter(
		db, 1, draft["id"], {"recipients": [{"to_position_id": inbox["id"], "kind": "info"}]}, owner.id, sender["id"],
	)
	secret = docs.register_document(
		db, 1, owner.id, sender["id"],
		{"title": "سند سری روی نامه عادی", "confidentiality": "secret", "file_storage_id": "file-secret-doc", "letter_id": registered["id"]},
	)
	opened = docs.register_document(
		db, 1, owner.id, sender["id"],
		{"title": "سند عادی روی نامه", "confidentiality": "normal", "file_storage_id": "file-open-doc", "letter_id": registered["id"]},
	)
	found = docs.search_documents(db, 1, reader.id, inbox["id"], "سند")
	assert [item["id"] for item in found["items"]] == [opened["id"]]
	with pytest.raises(ApiError) as blocked:
		docs.get_document(db, 1, reader.id, inbox["id"], secret["id"])
	assert blocked.value.code == "OA_DOCUMENT_FORBIDDEN"
	owner_found = docs.search_documents(db, 1, owner.id, sender["id"], "سند سری")
	assert [item["id"] for item in owner_found["items"]] == [secret["id"]]
	now = datetime.utcnow()
	db.add_all(
		[
			OaDocument(
				business_id=1,
				title="سند پنهان",
				confidentiality="secret",
				letter_id=registered["id"],
				search_text="سند پنهان",
				created_by_user_id=owner.id,
				created_at=now,
				updated_at=now,
				retain_until=date(2020, 1, 1),
				retention_status="due_review",
			)
			for _index in range(50)
		]
	)
	visible = db.query(OaDocument).filter(OaDocument.id == opened["id"]).one()
	visible.retain_until = date(2020, 6, 1)
	visible.retention_status = "due_review"
	db.commit()
	reader_reviews = ent.list_retention_reviews(db, 1, user_id=reader.id)
	assert [item["title"] for item in reader_reviews["documents"]] == ["سند عادی روی نامه"]
	owner_reviews = ent.list_retention_reviews(db, 1, user_id=owner.id)
	assert owner_reviews["documents"][0]["title"] == "سند پنهان"
	assert len(owner_reviews["documents"]) == 50
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_hidden_office_file_is_not_downloadable_or_shareable(_plugin):
	from app.core.responses import ApiError
	from app.services.file_storage_share_service import create_share
	from app.services.oa_document_service import refuse_external_oa_file, require_oa_file_visible, restrict_file_query
	from adapters.db.models.file_storage import FileStorage

	db = _session()
	owner = _user(db, "file-owner@example.com", "ff1")
	reader = _user(db, "file-reader@example.com", "ff2")
	unit = oa.create_org_unit(db, 1, {"code": "files", "name_i18n": {"fa": "فایل", "en": "Files"}}, owner.id)
	sender = oa.create_position(
		db, 1, {"code": "p_file", "org_unit_id": unit["id"], "name_i18n": {"fa": "بایگان", "en": "Archivist"}, "is_secretariat": True}, owner.id,
	)
	inbox = oa.create_position(db, 1, {"code": "p_file_in", "org_unit_id": unit["id"], "name_i18n": {"fa": "گیرنده", "en": "Inbox"}}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": sender["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": inbox["id"], "user_id": reader.id, "is_primary": True}, owner.id)
	for file_id in ("file-secret-doc", "file-open-doc", "file-private", "file-shared", "file-loose"):
		_file(db, owner.id, file_id)
	private = oa.create_letter_draft(db, 1, {"subject": "نامه خصوصی", "letter_kind": "internal"}, owner.id, sender["id"])
	private_reg = oa.register_letter(
		db, 1, private["id"], {"recipients": [{"to_position_id": sender["id"], "kind": "info"}]}, owner.id, sender["id"],
	)
	shared = oa.create_letter_draft(db, 1, {"subject": "نامه مشترک", "letter_kind": "internal"}, owner.id, sender["id"])
	shared_reg = oa.register_letter(
		db, 1, shared["id"], {"recipients": [{"to_position_id": inbox["id"], "kind": "info"}]}, owner.id, sender["id"],
	)
	oa.add_attachment(db, 1, private_reg["id"], {"file_storage_id": "file-private", "title": "پیوست خصوصی"}, owner.id, sender["id"])
	oa.add_attachment(db, 1, shared_reg["id"], {"file_storage_id": "file-shared", "title": "پیوست مشترک"}, owner.id, sender["id"])
	docs.register_document(
		db, 1, owner.id, sender["id"],
		{"title": "سند سری", "confidentiality": "secret", "file_storage_id": "file-secret-doc", "letter_id": shared_reg["id"]},
	)
	docs.register_document(
		db, 1, owner.id, sender["id"],
		{"title": "سند عادی", "confidentiality": "normal", "file_storage_id": "file-open-doc", "letter_id": shared_reg["id"]},
	)
	for hidden_id in ("file-secret-doc", "file-private"):
		with pytest.raises(ApiError) as blocked:
			require_oa_file_visible(db, 1, reader.id, hidden_id)
		assert blocked.value.code == "FILE_NOT_FOUND"
	for visible_id in ("file-open-doc", "file-shared", "file-loose"):
		require_oa_file_visible(db, 1, reader.id, visible_id)
	require_oa_file_visible(db, 1, owner.id, "file-secret-doc")
	listed = {
		row.id
		for row in restrict_file_query(db.query(FileStorage).filter(FileStorage.business_id == 1), db, 1, reader.id, False).all()
	}
	assert "file-secret-doc" not in listed
	assert "file-private" not in listed
	assert {"file-open-doc", "file-shared", "file-loose"} <= listed
	admin_listed = {
		row.id
		for row in restrict_file_query(db.query(FileStorage).filter(FileStorage.business_id == 1), db, 1, reader.id, True).all()
	}
	assert "file-secret-doc" in admin_listed
	with pytest.raises(ApiError) as external:
		create_share(db, 1, "file-secret-doc", owner.id, is_admin=True)
	assert external.value.code == "OA_CLASSIFIED_EXTERNAL"
	with pytest.raises(ApiError) as public:
		refuse_external_oa_file(db, "file-secret-doc", public=True)
	assert public.value.code == "FILE_NOT_FOUND"
	refuse_external_oa_file(db, "file-open-doc")
	with pytest.raises(ApiError) as private_share:
		create_share(db, 1, "file-private", reader.id)
	assert private_share.value.code == "FILE_NOT_FOUND"
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_classified_file_cannot_move_onto_another_letter_or_document(_plugin):
	from app.core.responses import ApiError
	from adapters.db.models.office_automation import OaLetter, OaLetterAttachment

	db = _session()
	owner = _user(db, "move-owner@example.com", "mv1")
	stranger = _user(db, "move-stranger@example.com", "mv2")
	unit = oa.create_org_unit(db, 1, {"code": "moves", "name_i18n": {"fa": "انتقال", "en": "Move"}}, owner.id)
	sender = oa.create_position(db, 1, {"code": "p_move", "org_unit_id": unit["id"], "name_i18n": {"fa": "مبدأ", "en": "Source"}}, owner.id)
	outsider = oa.create_position(db, 1, {"code": "p_move_out", "org_unit_id": unit["id"], "name_i18n": {"fa": "بیرون", "en": "Out"}}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": sender["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": outsider["id"], "user_id": stranger.id, "is_primary": True}, owner.id)
	_file(db, owner.id, "file-classified-src")
	_file(db, owner.id, "file-plain-doc")
	secret = oa.create_letter_draft(
		db, 1, {"subject": "نامه سری فایل", "body": "متن سری فایل", "letter_kind": "internal", "confidentiality": "secret"}, owner.id, sender["id"],
	)
	other_secret = oa.create_letter_draft(
		db, 1, {"subject": "نامه سری دیگر", "letter_kind": "internal", "confidentiality": "secret"}, owner.id, sender["id"],
	)
	normal = oa.create_letter_draft(db, 1, {"subject": "نامه عادی فایل", "letter_kind": "internal"}, owner.id, sender["id"])
	stranger_draft = oa.create_letter_draft(db, 1, {"subject": "پیش‌نویس غریبه", "letter_kind": "internal"}, stranger.id, outsider["id"])
	oa.add_attachment(db, 1, secret["id"], {"file_storage_id": "file-classified-src", "title": "اسکن سری"}, owner.id, sender["id"])
	jobs_before = db.query(OaOcrJob).count()
	with pytest.raises(ApiError) as onto_normal:
		oa.add_attachment(db, 1, normal["id"], {"file_storage_id": "file-classified-src", "title": "کپی"}, owner.id, sender["id"])
	assert onto_normal.value.code == "OA_CLASSIFIED_EXTERNAL"
	with pytest.raises(ApiError) as onto_other:
		oa.add_attachment(db, 1, other_secret["id"], {"file_storage_id": "file-classified-src", "title": "کپی"}, owner.id, sender["id"])
	assert onto_other.value.code == "OA_CLASSIFIED_EXTERNAL"
	with pytest.raises(ApiError) as hidden:
		oa.add_attachment(db, 1, stranger_draft["id"], {"file_storage_id": "file-classified-src", "title": "کپی"}, stranger.id, outsider["id"])
	assert hidden.value.code == "FILE_NOT_FOUND"
	with pytest.raises(ApiError) as normal_doc:
		docs.register_document(
			db, 1, owner.id, sender["id"],
			{"title": "سند عادی از فایل سری", "confidentiality": "normal", "file_storage_id": "file-classified-src"},
		)
	assert normal_doc.value.code == "OA_CLASSIFIED_EXTERNAL"
	with pytest.raises(ApiError) as loose_secret:
		docs.register_document(
			db, 1, owner.id, sender["id"],
			{"title": "سند سری جدا", "confidentiality": "secret", "file_storage_id": "file-classified-src"},
		)
	assert loose_secret.value.code == "OA_CLASSIFIED_EXTERNAL"
	assert db.query(OaOcrJob).count() == jobs_before
	plain = docs.register_document(
		db, 1, owner.id, sender["id"],
		{"title": "سند عادی مستقل", "confidentiality": "normal", "file_storage_id": "file-plain-doc"},
	)
	with pytest.raises(ApiError) as version_move:
		docs.add_document_version(db, 1, owner.id, sender["id"], plain["id"], "file-classified-src")
	assert version_move.value.code == "OA_CLASSIFIED_EXTERNAL"
	kept = docs.register_document(
		db, 1, owner.id, sender["id"],
		{"title": "سند سری همان نامه", "confidentiality": "secret", "file_storage_id": "file-classified-src", "letter_id": secret["id"]},
	)
	assert kept["letter_id"] == secret["id"]
	assert kept["confidentiality"] == "secret"
	normal_row = db.query(OaLetter).filter(OaLetter.id == normal["id"]).one()
	assert not normal_row.ocr_text
	assert db.query(OaLetterAttachment).filter(OaLetterAttachment.letter_id == normal["id"]).count() == 0
	assert db.query(OaLetterAttachment).filter(OaLetterAttachment.letter_id == other_secret["id"]).count() == 0
	assert db.query(OaLetterAttachment).filter(OaLetterAttachment.file_storage_id == "file-classified-src").count() == 1
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_classified_attachment_and_paraph_keep_text_in_the_app_and_not_in_the_model(_plugin):
	db = _session()
	owner = _user(db, "name-owner@example.com", "nm1")
	unit = oa.create_org_unit(db, 1, {"code": "names", "name_i18n": {"fa": "نام", "en": "Name"}}, owner.id)
	from app.services import office_automation_extended_service as ext

	sec = ext.create_secretariat(db, 1, {"code": "sec_name", "name": "محرمانه", "is_confidential": True, "is_default": True}, owner.id)
	sender = oa.create_position(
		db, 1,
		{"code": "p_name", "org_unit_id": unit["id"], "name_i18n": {"fa": "دبیر", "en": "Clerk"}, "is_secretariat": True, "secretariat_id": sec["id"]},
		owner.id,
	)
	oa.assign_position_holder(db, 1, {"position_id": sender["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	_file(db, owner.id, "file-seri-name")
	secret = oa.create_letter_draft(
		db, 1,
		{"subject": "نامه سری نام فایل", "body": "متن سری نام فایل", "letter_kind": "internal", "confidentiality": "secret"},
		owner.id, sender["id"],
	)
	registered = oa.register_letter(db, 1, secret["id"], {}, owner.id, sender["id"])
	attached = oa.add_attachment(
		db, 1, registered["id"], {"file_storage_id": "file-seri-name", "title": "عنوان پیوست سری"}, owner.id, sender["id"],
	)
	assert attached["original_name"] == "file-seri-name.txt"
	assert attached["title"] == "عنوان پیوست سری"
	assert attached["confidentiality"] == "secret"
	hidden_file = oa.withhold_classified_text(attached)
	assert hidden_file["original_name"] == ""
	assert hidden_file["title"] == ""
	assert hidden_file["file_storage_id"] == "file-seri-name"
	paraph = oa.add_paraph(db, 1, registered["id"], {"text": "پاراف سری نام"}, owner.id, sender["id"])
	assert paraph["text"] == "پاراف سری نام"
	assert paraph["confidentiality"] == "secret"
	assert oa.withhold_classified_text(paraph)["text"] == ""
	opened = oa.get_letter(db, 1, registered["id"], owner.id, sender["id"])
	assert opened["attachments"][0]["original_name"] == "file-seri-name.txt"
	assert opened["paraphs"][0]["text"] == "پاراف سری نام"
	model = oa.withhold_classified_text(opened)
	assert model["attachments"][0]["original_name"] == ""
	assert model["paraphs"][0]["text"] == ""
	assert model["body"] == ""
	db.close()


def test_business_file_download_stays_in_the_url_business():
	from app.core.responses import ApiError
	from app.services.oa_document_service import require_business_file

	db = _session()
	owner = _user(db, "tenant-file@example.com", "tf1")
	_file(db, owner.id, "file-business-one")
	other = _file(db, owner.id, "file-business-two")
	other.business_id = 2
	db.commit()
	assert require_business_file(db, 1, "file-business-one").id == "file-business-one"
	with pytest.raises(ApiError) as foreign:
		require_business_file(db, 1, "file-business-two")
	assert foreign.value.code == "FILE_NOT_FOUND"
	assert foreign.value.status_code == 404
	with pytest.raises(ApiError) as missing:
		require_business_file(db, 1, "file-missing")
	assert missing.value.code == "FILE_NOT_FOUND"
	db.close()
