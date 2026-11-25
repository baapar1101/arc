"""گیت لایسنس، گردش نامه سمت‌محور و ابزارهای MCP اتوماسیون اداری."""
from __future__ import annotations

import re
from datetime import date, datetime, timedelta
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from adapters.db.models.file_storage import FileStorage
from adapters.db.models.oa_enterprise import (
	OaBranch,
	OaLetterCommercialLink,
	OaLetterExchange,
	OaQualifiedSignRequest,
	OaRetentionPolicy,
	OaSignatureProvider,
)
from adapters.db.models.oa_mcp_confirmation import OaMcpConfirmation
from adapters.db.models.oa_document import (
	OaDocument,
	OaDocumentVersion,
	OaExtractionSuggestion,
	OaOcrJob,
)
from adapters.db.models.oa_process import (
	OaProcessDefinition,
	OaProcessInstance,
	OaProcessTask,
	OaProcessToken,
	OaProcessVersion,
)
from adapters.db.models.office_automation import (
	OaArchiveFolder,
	OaAuditLog,
	OaCartableRule,
	OaCartableSavedFilter,
	OaDelegation,
	OaDispatch,
	OaEceMessage,
	OaExternalOrg,
	OaLetter,
	OaLetterAttachment,
	OaLetterFormat,
	OaLetterLink,
	OaLetterNumberCounter,
	OaLetterSignStep,
	OaLetterTemplate,
	OaLetterVersion,
	OaMailboxMessage,
	OaOrgUnit,
	OaParaph,
	OaPosition,
	OaPositionHolder,
	OaReferral,
	OaSecretariat,
	OaSettings,
	OaSignPathTemplate,
	OaSignPathTemplateStep,
	OaUserSignature,
)
from adapters.db.models.user import User
from adapters.db.session import Base
from adapters.db.seed_data.notification_event_types_seed import OFFICE_AUTOMATION_EVENT_CODES
from app.core.office_automation_plugin_dependency import PLUGIN_CODE, check_office_automation_plugin_active
from app.core.responses import ApiError
from app.services import office_automation_extended_service as ext
from app.services import office_automation_service as svc
from app.services.ai.ai_tool_manifest import get_manifest_entry
from app.services.office_automation_ece import build_ece_xml, parse_ece_xml


def _mock_db_with_license(*, plugin_active: bool = True, business_active: bool = True, expired: bool = False):
	db = MagicMock()
	plugin = MagicMock()
	plugin.id = 77
	plugin.is_active = plugin_active
	license_row = None
	if business_active:
		license_row = MagicMock()
		license_row.status = "active"
		if expired:
			license_row.ends_at = datetime.utcnow() - timedelta(days=1)
		else:
			license_row.ends_at = datetime.utcnow() + timedelta(days=30)

	def query_side_effect(model):
		q = MagicMock()
		if model.__name__ == "MarketplacePlugin":
			q.filter.return_value.first.return_value = plugin if plugin_active else None
		elif model.__name__ == "BusinessPlugin":
			q.filter.return_value.first.return_value = license_row
		return q

	db.query.side_effect = query_side_effect
	return db


def test_plugin_active_when_licensed():
	assert check_office_automation_plugin_active(_mock_db_with_license(), 1) is True


def test_plugin_inactive_when_no_marketplace_plugin():
	assert check_office_automation_plugin_active(_mock_db_with_license(plugin_active=False), 1) is False


def test_plugin_inactive_when_no_business_license():
	assert check_office_automation_plugin_active(_mock_db_with_license(business_active=False), 1) is False


def test_plugin_inactive_when_expired():
	assert check_office_automation_plugin_active(_mock_db_with_license(expired=True), 1) is False


def test_plugin_code_constant():
	assert PLUGIN_CODE == "office_automation"
	assert "office_automation.letter_referred" in OFFICE_AUTOMATION_EVENT_CODES
	assert "office_automation.letter_returned" in OFFICE_AUTOMATION_EVENT_CODES
	assert "office_automation.letter_dispatched" in OFFICE_AUTOMATION_EVENT_CODES
	assert "office_automation.letter_followup_due" in OFFICE_AUTOMATION_EVENT_CODES


OA_TOOLS = (
	"get_oa_dashboard",
	"get_oa_personal_desk",
	"save_oa_process_draft",
	"publish_oa_process",
	"publish_oa_linear_process",
	"list_oa_process_definitions",
	"list_oa_process_versions",
	"start_oa_process",
	"list_oa_process_tasks",
	"complete_oa_process_task",
	"list_oa_mcp_confirmations",
	"suggest_oa_referral",
	"draft_oa_process_from_text",
	"list_oa_branches",
	"create_oa_branch",
	"list_oa_retention_policies",
	"save_oa_retention_policy",
	"list_oa_retention_reviews",
	"hold_oa_letter_retention",
	"hold_oa_document_retention",
	"list_oa_signature_providers",
	"create_oa_signature_provider",
	"list_oa_letter_qualified_requests",
	"request_oa_qualified_signature",
	"record_oa_qualified_sign_result",
	"exchange_oa_letter",
	"list_oa_letter_commercial_links",
	"link_oa_letter_commercial",
	"register_oa_document",
	"add_oa_document_version",
	"search_oa_documents",
	"get_oa_document",
	"accept_oa_document_suggestion",
	"reject_oa_document_suggestion",
	"get_oa_settings",
	"update_oa_settings",
	"list_oa_org_units",
	"create_oa_org_unit",
	"update_oa_org_unit",
	"list_oa_positions",
	"create_oa_position",
	"update_oa_position",
	"list_my_oa_positions",
	"list_oa_position_holders",
	"assign_oa_position_holder",
	"end_oa_position_holder",
	"list_oa_delegations",
	"create_oa_delegation",
	"end_oa_delegation",
	"list_oa_cartable",
	"list_oa_cartable_filters",
	"list_oa_cartable_board",
	"save_oa_cartable_filter",
	"delete_oa_cartable_filter",
	"get_oa_letter",
	"get_oa_letter_print",
	"create_oa_letter_draft",
	"update_oa_letter_draft",
	"delete_oa_letter_draft",
	"register_oa_letter",
	"refer_oa_letter",
	"complete_oa_referral",
	"return_oa_referral",
	"add_oa_paraph",
	"add_oa_letter_attachment",
	"remove_oa_letter_attachment",
	"archive_oa_letter",
	"set_oa_follow_up",
	"link_oa_letters",
	"reply_oa_letter",
	"search_oa_letters",
	"list_oa_letter_formats",
	"create_oa_letter_format",
	"update_oa_letter_format",
	"delete_oa_letter_format",
	"list_oa_letter_templates",
	"create_oa_letter_template",
	"update_oa_letter_template",
	"delete_oa_letter_template",
	"list_oa_secretariats",
	"create_oa_secretariat",
	"list_oa_external_orgs",
	"create_oa_external_org",
	"start_oa_sign_path",
	"sign_oa_letter",
	"dispatch_oa_letter",
	"export_oa_ece",
	"import_oa_ece",
	"summarize_oa_letter",
	"list_oa_archive_folders",
	"get_oa_delay_report",
	"import_oa_email_letter",
	"ocr_oa_letter",
	"send_oa_ece",
	"send_oa_email_letter",
)


def test_mcp_tools_cover_letter_lifecycle():
	src = Path(__file__).resolve().parents[1] / "app" / "services" / "ai" / "ai_function_extensions_mcp_office_automation.py"
	text = src.read_text(encoding="utf-8")
	names = set(re.findall(r'_register\(\s*registry,\s*"([^"]+)"', text))
	assert set(OA_TOOLS) <= names
	assert 'category="office_automation"' in text
	assert '"office_automation.refer"' in text
	assert '"registry"' in text
	registry_src = (Path(__file__).resolve().parents[1] / "app" / "services" / "ai" / "function_registry.py").read_text(encoding="utf-8")
	assert "register_mcp_office_automation_functions" in registry_src
	for name in OA_TOOLS:
		entry = get_manifest_entry(name)
		assert entry is not None, name
		assert "office_automation" in entry.domains
	assert get_manifest_entry("delete_oa_letter_draft").side_effect == "delete"
	assert get_manifest_entry("register_oa_letter").always_confirm is True


def _session():
	engine = create_engine("sqlite:///:memory:")
	Base.metadata.create_all(
		engine,
		tables=[
			User.__table__,
			FileStorage.__table__,
			OaSettings.__table__,
			OaOrgUnit.__table__,
			OaPosition.__table__,
			OaPositionHolder.__table__,
			OaDelegation.__table__,
			OaLetterFormat.__table__,
			OaLetterTemplate.__table__,
			OaLetter.__table__,
			OaLetterNumberCounter.__table__,
			OaReferral.__table__,
			OaParaph.__table__,
			OaLetterAttachment.__table__,
			OaLetterLink.__table__,
			OaAuditLog.__table__,
			OaSecretariat.__table__,
			OaExternalOrg.__table__,
			OaArchiveFolder.__table__,
			OaUserSignature.__table__,
			OaSignPathTemplate.__table__,
			OaSignPathTemplateStep.__table__,
			OaLetterSignStep.__table__,
			OaLetterVersion.__table__,
			OaDispatch.__table__,
			OaEceMessage.__table__,
			OaCartableRule.__table__,
			OaCartableSavedFilter.__table__,
			OaMailboxMessage.__table__,
			OaProcessDefinition.__table__,
			OaProcessVersion.__table__,
			OaProcessInstance.__table__,
			OaProcessToken.__table__,
			OaProcessTask.__table__,
			OaDocument.__table__,
			OaDocumentVersion.__table__,
			OaOcrJob.__table__,
			OaExtractionSuggestion.__table__,
			OaMcpConfirmation.__table__,
			OaBranch.__table__,
			OaRetentionPolicy.__table__,
			OaSignatureProvider.__table__,
			OaQualifiedSignRequest.__table__,
			OaLetterExchange.__table__,
			OaLetterCommercialLink.__table__,
		],
	)
	return sessionmaker(bind=engine)()


def _user(db, email, code):
	row = User(email=email, password_hash="x", referral_code=code, is_active=True)
	db.add(row)
	db.commit()
	db.refresh(row)
	return row


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_position_occupancy_numbering_paraph_and_referral(_plugin):
	db = _session()
	owner = _user(db, "owner@example.com", "oa1")
	clerk = _user(db, "clerk@example.com", "oa2")
	bid = 1

	unit = svc.create_org_unit(db, bid, {"code": "hq", "name_i18n": {"fa": "ستاد", "en": "HQ"}}, owner.id)
	auto_unit = svc.create_org_unit(db, bid, {"name_i18n": {"fa": "واحد خودکار"}}, owner.id)
	assert auto_unit["code"].startswith("u")
	with pytest.raises(ApiError) as dup_code:
		svc.create_org_unit(
			db, bid,
			{"code": "hq", "name_i18n": {"fa": "تکراری"}, "auto_generate_code": False},
			owner.id,
		)
	assert dup_code.value.code == "OA_CODE_EXISTS"
	with pytest.raises(ApiError) as missing_code:
		svc.create_org_unit(
			db, bid,
			{"name_i18n": {"fa": "بدون کد"}, "auto_generate_code": False},
			owner.id,
		)
	assert missing_code.value.code == "VALIDATION_ERROR"
	mgr = svc.create_position(
		db, bid,
		{"code": "mgr", "org_unit_id": unit["id"], "name_i18n": {"fa": "مدیر", "en": "Manager"}, "is_secretariat": True},
		owner.id,
	)
	exp = svc.create_position(
		db, bid,
		{"code": "exp", "org_unit_id": unit["id"], "name_i18n": {"fa": "کارشناس", "en": "Expert"}},
		owner.id,
	)
	auto_pos = svc.create_position(
		db, bid,
		{"org_unit_id": unit["id"], "name_i18n": {"fa": "سمت خودکار"}},
		owner.id,
	)
	assert auto_pos["code"].startswith("p")
	with pytest.raises(ApiError) as dup_pos:
		svc.create_position(
			db, bid,
			{"code": "mgr", "org_unit_id": unit["id"], "name_i18n": {"fa": "تکراری"}, "auto_generate_code": False},
			owner.id,
		)
	assert dup_pos.value.code == "OA_CODE_EXISTS"
	svc.assign_position_holder(db, bid, {"position_id": mgr["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	svc.assign_position_holder(db, bid, {"position_id": exp["id"], "user_id": clerk.id, "is_primary": True}, owner.id)

	mine = svc.list_my_positions(db, bid, owner.id)
	assert {p["code"] for p in mine} == {"mgr"}

	with pytest.raises(ApiError) as missing:
		svc.create_letter_draft(db, bid, {"subject": "بدون سمت"}, clerk.id, mgr["id"])
	assert missing.value.code == "OA_POSITION_NOT_HELD"

	draft = svc.create_letter_draft(
		db, bid,
		{"subject": "درخواست مرخصی", "body": "متن نامه", "letter_kind": "internal", "letter_date": "1404/08/10"},
		owner.id, mgr["id"], calendar_type="jalali",
	)
	assert draft["status"] == "draft"
	assert draft["secretariat_number"] is None

	incoming_draft = svc.create_letter_draft(
		db, bid, {"subject": "وارده", "letter_kind": "incoming"}, clerk.id, exp["id"],
	)
	with pytest.raises(ApiError) as secretariat:
		svc.register_letter(db, bid, incoming_draft["id"], {"letter_kind": "incoming"}, clerk.id, exp["id"])
	assert secretariat.value.code == "OA_SECRETARIAT_REQUIRED"

	registered = svc.register_letter(
		db, bid, draft["id"],
		{"recipients": [{"to_position_id": exp["id"], "kind": "action", "instruction": "اقدام شود"}]},
		owner.id, mgr["id"],
	)
	assert registered["status"] == "in_circulation"
	assert registered["secretariat_number"]
	assert registered["secretariat_seq"] == 1
	assert len(registered["referrals"]) == 1

	second = svc.create_letter_draft(
		db, bid, {"subject": "نامه دوم", "letter_kind": "internal", "letter_date": "1404/08/10"}, owner.id, mgr["id"], calendar_type="jalali",
	)
	second_reg = svc.register_letter(db, bid, second["id"], {}, owner.id, mgr["id"])
	assert second_reg["secretariat_seq"] == 2

	inbox = svc.list_cartable(db, bid, clerk.id, exp["id"], folder="inbox")
	assert inbox["total"] == 1
	referral_id = inbox["items"][0]["referral_id"]

	paraph = svc.add_paraph(db, bid, registered["id"], {"text": "موافقت می‌شود", "referral_id": referral_id}, clerk.id, exp["id"])
	assert "موافقت" in paraph["text"]

	done = svc.complete_referral(db, bid, referral_id, {"note": "انجام شد"}, clerk.id, exp["id"])
	assert any(r["id"] == referral_id and r["status"] == "done" for r in done["referrals"])

	file_row = FileStorage(
		id="oa-file-00000000-0000-0000-0000-000000000001",
		original_name="scan.pdf",
		stored_name="scan.pdf",
		file_path="/tmp/scan.pdf",
		file_size=12,
		mime_type="application/pdf",
		storage_type="local",
		uploaded_by=owner.id,
		business_id=None,
		module_context="office_automation",
		is_active=True,
		created_at=datetime.utcnow(),
		updated_at=datetime.utcnow(),
	)
	db.add(file_row)
	db.commit()
	attached = svc.add_attachment(
		db, bid, registered["id"],
		{"file_storage_id": file_row.id, "title": "پیوست اسکن"},
		owner.id, mgr["id"],
	)
	assert attached["title"] == "پیوست اسکن"
	letter_with_file = svc.get_letter(db, bid, registered["id"], owner.id, mgr["id"], is_admin=True)
	assert letter_with_file["attachments"]
	svc.remove_attachment(db, bid, attached["id"], owner.id, mgr["id"])

	archived = svc.archive_letter(db, bid, registered["id"], owner.id, mgr["id"])
	assert archived["status"] == "archived"
	with pytest.raises(ApiError) as attach_archived:
		svc.add_attachment(
			db, bid, registered["id"],
			{"file_storage_id": file_row.id, "title": "بعد از بایگانی"},
			owner.id, mgr["id"],
		)
	assert attach_archived.value.code == "OA_LETTER_ARCHIVED"

	registry = svc.list_cartable(db, bid, owner.id, mgr["id"], folder="registry")
	assert registry["total"] == 2
	printed = svc.get_letter_print(db, bid, registered["id"], owner.id, mgr["id"])
	assert printed["paraphs"]
	assert printed["print"]["internal_prefix"] == "INT"

	updated_draft = svc.update_letter_draft(
		db, bid, incoming_draft["id"], {"subject": "وارده دبیرخانه", "sender_org": "سازمان الف"}, clerk.id, exp["id"]
	)
	assert updated_draft["subject"] == "وارده دبیرخانه"
	incoming_reg = svc.register_letter(
		db, bid, incoming_draft["id"], {"letter_kind": "incoming"}, owner.id, mgr["id"]
	)
	assert incoming_reg["secretariat_number"].startswith("IN-")
	assert incoming_reg["letter_kind"] == "incoming"

	cced = svc.refer_letter(
		db, bid, second_reg["id"],
		{"recipients": [{"to_position_id": exp["id"], "kind": "info", "instruction": "رونوشت"}]},
		owner.id, mgr["id"],
	)
	assert any(r["kind"] == "info" for r in cced["referrals"])
	cc_box = svc.list_cartable(db, bid, clerk.id, exp["id"], folder="cc")
	assert cc_box["total"] >= 1

	ret_draft = svc.create_letter_draft(db, bid, {"subject": "نامه عودت", "letter_kind": "internal"}, owner.id, mgr["id"])
	ret_reg = svc.register_letter(
		db, bid, ret_draft["id"],
		{"recipients": [{"to_position_id": exp["id"], "kind": "action"}]},
		owner.id, mgr["id"],
	)
	ret_inbox = svc.list_cartable(db, bid, clerk.id, exp["id"], folder="inbox")
	ret_id = next(item["referral_id"] for item in ret_inbox["items"] if item["id"] == ret_reg["id"])
	returned = svc.return_referral(db, bid, ret_id, {"note": "نیاز به اصلاح"}, clerk.id, exp["id"])
	assert any(r["id"] == ret_id and r["status"] == "returned" for r in returned["referrals"])
	assert any(r["kind"] == "return" for r in returned["referrals"])

	followed = svc.set_follow_up(db, bid, second_reg["id"], {"follow_up_at": "1404/08/20"}, owner.id, mgr["id"])
	assert followed["follow_up_at"]
	follow_box = svc.list_cartable(db, bid, owner.id, mgr["id"], folder="followup")
	assert follow_box["total"] >= 1

	linked = svc.link_letters(
		db, bid, second_reg["id"],
		{"related_letter_id": registered["id"], "link_kind": "related"},
		owner.id, mgr["id"],
	)
	assert linked["related_letter_id"] == registered["id"]
	assert linked["link_kind"] == "related"

	reply = svc.reply_to_letter(db, bid, second_reg["id"], {"body": "پاسخ کوتاه"}, owner.id, mgr["id"])
	assert reply["status"] == "draft"
	assert reply["subject"].startswith("پاسخ:")
	assert any(item["link_kind"] == "reply" for item in reply["links"])
	source = svc.get_letter(db, bid, second_reg["id"], owner.id, mgr["id"])
	assert any(item["related_letter_id"] == reply["id"] and item["link_kind"] == "reply" for item in source["links"])
	assert any(item["kind"] == "referral" for item in source["timeline"])
	assert any(item["action"] == "letter.view" for item in source["timeline"])
	assert any(item["action"] == "letter.reply" and item["summary"] == "پاسخ" for item in source["timeline"])

	settings = svc.update_settings(db, bid, {"internal_prefix": "INTX", "numbering_calendar": "jalali"}, owner.id)
	assert settings["internal_prefix"] == "INTX"

	with pytest.raises(ApiError) as dup_holder:
		svc.assign_position_holder(db, bid, {"position_id": mgr["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	assert dup_holder.value.code == "OA_HOLDER_EXISTS"

	with pytest.raises(ApiError) as bad_date:
		svc.create_letter_draft(db, bid, {"subject": "x", "letter_date": "not-a-date"}, owner.id, mgr["id"])
	assert bad_date.value.code == "VALIDATION_ERROR"

	draft_only = svc.create_letter_draft(db, bid, {"subject": "فقط پیش‌نویس"}, owner.id, mgr["id"])
	with pytest.raises(ApiError) as arch:
		svc.archive_letter(db, bid, draft_only["id"], owner.id, mgr["id"])
	assert arch.value.code == "OA_LETTER_STILL_DRAFT"

	dash = svc.get_dashboard(db, bid, owner.id, 999999)
	assert dash["active_position_id"] == mgr["id"]
	assert "inbox" in dash["counts"]

	with pytest.raises(ApiError) as link_draft:
		svc.link_letters(
			db, bid, draft_only["id"],
			{"related_letter_id": registered["id"], "link_kind": "related"},
			owner.id, mgr["id"],
		)
	assert link_draft.value.code == "OA_LETTER_STILL_DRAFT"

	archived = svc.archive_letter(db, bid, second_reg["id"], owner.id, mgr["id"])
	assert archived["status"] == "archived"
	with pytest.raises(ApiError) as rearch:
		svc.archive_letter(db, bid, second_reg["id"], owner.id, mgr["id"])
	assert rearch.value.code == "OA_LETTER_ARCHIVED"

	delegation = svc.create_delegation(
		db, bid, {"position_id": mgr["id"], "delegate_user_id": clerk.id, "scope": "full"}, owner.id
	)
	assert delegation["delegate_user_id"] == clerk.id
	with pytest.raises(ApiError) as dup_del:
		svc.create_delegation(
			db, bid, {"position_id": mgr["id"], "delegate_user_id": clerk.id, "scope": "full"}, owner.id
		)
	assert dup_del.value.code == "OA_DELEGATION_EXISTS"
	delegated = svc.list_my_positions(db, bid, clerk.id)
	assert {p["code"] for p in delegated} >= {"exp", "mgr"}
	svc.end_delegation(db, bid, delegation["id"], owner.id)

	throwaway = svc.create_letter_draft(db, bid, {"subject": "حذف شود"}, owner.id, mgr["id"])
	deleted = svc.delete_letter_draft(db, bid, throwaway["id"], owner.id, mgr["id"])
	assert deleted["deleted"] is True
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_letter_templates_formats_search_and_rich_body(_plugin):
	db = _session()
	owner = _user(db, "fmt@example.com", "oa3")
	bid = 1
	unit = svc.create_org_unit(db, bid, {"code": "hq", "name_i18n": {"fa": "ستاد"}}, owner.id)
	mgr = svc.create_position(
		db, bid,
		{"code": "mgr", "org_unit_id": unit["id"], "name_i18n": {"fa": "مدیر بازرگانی"}},
		owner.id,
	)
	exp = svc.create_position(
		db, bid,
		{"code": "exp", "org_unit_id": unit["id"], "name_i18n": {"fa": "کارشناس مالی"}},
		owner.id,
	)
	svc.assign_position_holder(db, bid, {"position_id": mgr["id"], "user_id": owner.id, "is_primary": True}, owner.id)

	fmt = svc.create_letter_format(
		db, bid,
		{"name": "رسمی A4", "paper_size": "a4", "footer_text": "شرکت نمونه", "is_default": True, "margin_top": 25},
		owner.id,
	)
	assert fmt["is_default"] is True
	assert fmt["margin_top"] == 25
	settings = svc.get_settings(db, bid)
	assert settings["default_format_id"] == fmt["id"]
	assert settings["paper_size"] == "a4"

	tpl = svc.create_letter_template(
		db, bid,
		{
			"name": "درخواست مرخصی",
			"letter_kind": "internal",
			"subject": "درخواست مرخصی استحقاقی",
			"body": "## درخواست\nبا سلام",
			"body_format": "markdown",
			"format_id": fmt["id"],
			"is_default": True,
		},
		owner.id,
	)
	assert tpl["body_format"] == "markdown"
	found = svc.list_positions(db, bid, q="بازرگانی")
	assert any(p["id"] == mgr["id"] for p in found)
	miss = svc.list_positions(db, bid, q="ناموجودxyz")
	assert miss == []

	draft = svc.create_letter_draft(
		db, bid,
		{
			"subject": tpl["subject"],
			"body": tpl["body"],
			"body_format": "markdown",
			"letter_kind": "internal",
			"sender_position_id": mgr["id"],
			"receiver_position_id": exp["id"],
			"format_id": fmt["id"],
			"template_id": tpl["id"],
		},
		owner.id, mgr["id"],
	)
	assert draft["body_format"] == "markdown"
	assert draft["format_id"] == fmt["id"]
	registered = svc.register_letter(db, bid, draft["id"], {}, owner.id, mgr["id"])
	printed = svc.get_letter_print(db, bid, registered["id"], owner.id, mgr["id"], is_admin=True)
	assert printed["print"]["footer_text"] == "شرکت نمونه"
	assert printed["print"]["paper_size"] == "a4"
	assert printed["sender_position_title"] == "مدیر بازرگانی"
	hits = svc.search_letters(db, bid, owner.id, q="مرخصی", is_admin=True)
	assert any(item["id"] == registered["id"] for item in hits)
	svc.update_settings(db, bid, {"background_file_id": None, "default_body_format": "html", "footer_text": "پاورقی"}, owner.id)
	updated = svc.get_settings(db, bid)
	assert updated["default_body_format"] == "html"
	svc.delete_letter_template(db, bid, tpl["id"], owner.id)
	svc.delete_letter_format(db, bid, fmt["id"], owner.id)
	db.close()


def test_ece_xml_roundtrip_jalali_and_classification():
	from datetime import date

	xml = build_ece_xml(
		sender={"name": "دبیرخانه", "organization": "شرکت نمونه", "position": "مدیر", "department": "ستاد"},
		receiver={"name": "سازمان الف", "organization": "سازمان الف"},
		letter_no="OUT-1404-000001",
		letter_date=date(2025, 10, 31),
		subject="درخواست استعلام",
		urgency="urgent",
		confidentiality="highly_confidential",
		keywords="استعلام",
		body="متن نامه برای ECE",
		calendar_label="jalali",
	)
	assert "<letter" in xml
	assert "Protocol" in xml
	parsed = parse_ece_xml(xml)
	assert parsed["subject"] == "درخواست استعلام"
	assert parsed["urgency"] == "urgent"
	assert parsed["confidentiality"] == "highly_confidential"
	assert parsed["letter_no"] == "OUT-1404-000001"
	assert parsed["show_as"] == "jalali"
	assert "متن نامه" in (parsed.get("body") or "")


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_commercial_upgrade_secretariats_sign_ece_track_archive(_plugin):
	db = _session()
	owner = _user(db, "oa-pro@example.com", "oa4")
	clerk = _user(db, "oa-clerk@example.com", "oa5")
	bid = 1
	unit = svc.create_org_unit(db, bid, {"code": "hq", "name_i18n": {"fa": "ستاد", "en": "HQ"}}, owner.id)
	mgr = svc.create_position(
		db, bid,
		{"code": "mgr", "org_unit_id": unit["id"], "name_i18n": {"fa": "مدیر", "en": "Manager"}, "is_secretariat": True},
		owner.id,
	)
	exp = svc.create_position(
		db, bid,
		{"code": "exp", "org_unit_id": unit["id"], "name_i18n": {"fa": "کارشناس", "en": "Expert"}},
		owner.id,
	)
	svc.assign_position_holder(db, bid, {"position_id": mgr["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	svc.assign_position_holder(db, bid, {"position_id": exp["id"], "user_id": clerk.id, "is_primary": True}, owner.id)

	main_row = ext.ensure_default_secretariat(db, bid)
	db.commit()
	main = {"id": main_row.id}
	branch = ext.create_secretariat(
		db, bid,
		{"code": "branch", "name_i18n": {"fa": "دبیرخانه شعبه", "en": "Branch secretariat"}, "outgoing_prefix": "BR"},
		owner.id,
	)
	assert main["id"] != branch["id"]
	secs = ext.list_secretariats(db, bid, lang="en")
	assert any(s["title"] == "Central secretariat" for s in secs)

	org = ext.create_external_org(
		db, bid,
		{"code": "org-a", "name_i18n": {"fa": "سازمان الف", "en": "Org A"}, "ece_email": "ece@org-a.test"},
		owner.id, lang="fa",
	)
	assert org["ece_email"] == "ece@org-a.test"

	folder = ext.save_archive_folder(db, bid, {"code": "legal", "name_i18n": {"fa": "حقوقی", "en": "Legal"}}, owner.id)
	assert folder["code"] == "legal"

	ext.save_cartable_rule(
		db, bid,
		{"name": "رونوشت خودکار", "conditions": {"subject_contains": "رونوشت"}, "actions": {"mark_seen": True}},
		owner.id,
	)

	conf_sec = ext.create_secretariat(
		db, bid,
		{"code": "secret", "name_i18n": {"fa": "دبیرخانه محرمانه", "en": "Confidential secretariat"}, "is_confidential": True, "incoming_prefix": "SEC"},
		owner.id,
	)
	incoming = svc.create_letter_draft(
		db, bid,
		{
			"subject": "وارده محرمانه با کلیدواژه",
			"body": "متن کامل برای جستجوی تمام‌متن",
			"letter_kind": "incoming",
			"confidentiality": "secret",
			"keywords": "قرارداد",
			"external_org_id": org["id"],
			"receipt_number": "EXT-99",
			"letter_date": "1404/08/12",
		},
		owner.id, mgr["id"], calendar_type="jalali",
	)
	assert incoming["confidentiality"] == "secret"
	incoming_reg = svc.register_letter(db, bid, incoming["id"], {"letter_kind": "incoming"}, owner.id, mgr["id"])
	assert incoming_reg["tracking_token"]
	assert incoming_reg["secretariat_id"] == conf_sec["id"]
	assert incoming_reg["secretariat_number"].startswith("SEC-")
	assert incoming_reg["receipt_number"] == "EXT-99"
	track = ext.public_track(db, incoming_reg["tracking_token"])
	assert track["restricted"] is True
	assert track["number"] is None
	assert track["status"] is None
	assert track["subject"] is None
	assert track["confidentiality"] is None

	hits = svc.search_letters(db, bid, owner.id, q="تمام‌متن", is_admin=True)
	assert any(item["id"] == incoming_reg["id"] for item in hits)
	key_hits = svc.search_letters(db, bid, owner.id, q="قرارداد", is_admin=True)
	assert any(item["id"] == incoming_reg["id"] for item in key_hits)

	outgoing = svc.create_letter_draft(
		db, bid,
		{"subject": "صادره نیازمند امضا", "letter_kind": "outgoing", "letter_date": "2025-11-02"},
		owner.id, mgr["id"], calendar_type="gregorian",
	)
	ext.start_sign_path(
		db, bid, outgoing["id"],
		{"steps": [{"position_id": mgr["id"], "is_required": True}, {"position_id": exp["id"], "is_required": True}]},
		owner.id, mgr["id"],
	)
	with pytest.raises(ApiError) as early:
		ext.sign_letter_step(db, bid, outgoing["id"], {}, clerk.id, exp["id"])
	assert early.value.code == "OA_SIGN_STEP_NOT_FOUND"
	with pytest.raises(ApiError) as blocked:
		svc.register_letter(db, bid, outgoing["id"], {"letter_kind": "outgoing"}, owner.id, mgr["id"])
	assert blocked.value.code == "OA_SIGNATURE_REQUIRED"
	ext.sign_letter_step(db, bid, outgoing["id"], {"note": "امضا شد"}, owner.id, mgr["id"])
	ext.sign_letter_step(db, bid, outgoing["id"], {}, clerk.id, exp["id"])
	signed = svc.get_letter(db, bid, outgoing["id"], owner.id, mgr["id"], is_admin=True)
	assert signed["sign_status"] == "signed"
	out_reg = svc.register_letter(
		db, bid, outgoing["id"],
		{"letter_kind": "outgoing", "secretariat_id": branch["id"]},
		owner.id, mgr["id"], calendar_type="gregorian",
	)
	assert out_reg["secretariat_id"] == branch["id"]
	assert out_reg["secretariat_number"].startswith("BR-")
	assert out_reg["tracking_token"]
	open_track = ext.public_track(db, out_reg["tracking_token"])
	assert open_track["restricted"] is False
	assert open_track["number"] == out_reg["secretariat_number"]
	assert open_track["subject"] == "صادره نیازمند امضا"

	versions = ext.list_letter_versions(db, bid, outgoing["id"], owner.id, mgr["id"], is_admin=True)
	assert versions

	xml_data = ext.export_ece(db, bid, out_reg["id"], owner.id, mgr["id"])
	assert "<letter" in xml_data["xml"]
	imported = ext.import_ece(db, bid, {"xml": xml_data["xml"], "from_email": "ece@org-a.test"}, owner.id, mgr["id"])
	assert imported["letter_kind"] == "incoming"
	assert imported["subject"] == "صادره نیازمند امضا"

	dispatched = ext.dispatch_letter(
		db, bid, incoming_reg["id"],
		{"to_position_id": exp["id"], "instruction": "ابلاغ جهت اجرا"},
		owner.id, mgr["id"],
	)
	assert dispatched["dispatches"]
	ack = ext.acknowledge_dispatch(db, bid, dispatched["dispatches"][0]["id"], clerk.id, exp["id"])
	assert any(d["status"] == "acknowledged" for d in ack["dispatches"])

	filed = ext.archive_to_folder(db, bid, incoming_reg["id"], {"folder_id": folder["id"]}, owner.id, mgr["id"])
	assert filed["status"] == "archived"
	assert filed["archive_folder_id"] == folder["id"]

	mail = ext.import_email_as_letter(
		db, bid,
		{"subject": "ایمیل وارده", "body": "متن ایمیل", "from_email": "a@b.test", "letter_date": "1404/08/01"},
		owner.id, mgr["id"], calendar_type="jalali",
	)
	assert mail["letter_kind"] == "incoming"
	assert mail["subject"] == "ایمیل وارده"

	rule_letter = svc.create_letter_draft(db, bid, {"subject": "نامه رونوشت خودکار", "letter_kind": "internal"}, owner.id, mgr["id"])
	ruled = svc.register_letter(
		db, bid, rule_letter["id"],
		{"recipients": [{"to_position_id": exp["id"], "kind": "action"}]},
		owner.id, mgr["id"],
	)
	assert any(r["status"] == "seen" for r in ruled["referrals"])

	delay = ext.delay_report(db, bid, user_id=owner.id, is_admin=True)
	volume = ext.volume_report(db, bid, user_id=owner.id, is_admin=True)
	perf = ext.performance_report(db, bid, user_id=owner.id, is_admin=True)
	assert "items" in delay and "by_kind" in volume and "items" in perf

	summary = ext.summarize_letter(db, bid, out_reg["id"], owner.id, mgr["id"])
	assert summary["ai_summary"]

	secret_draft = svc.create_letter_draft(
		db, bid,
		{"subject": "نامه سری برای دبیرخانه محرمانه", "letter_kind": "incoming", "confidentiality": "secret"},
		owner.id, mgr["id"],
	)
	secret_reg = svc.register_letter(db, bid, secret_draft["id"], {"letter_kind": "incoming"}, owner.id, mgr["id"])
	assert secret_reg["secretariat_id"] == conf_sec["id"]
	assert secret_reg["secretariat_number"].startswith("SEC-")
	with pytest.raises(ApiError) as classified:
		blocked_draft = svc.create_letter_draft(
			db, bid,
			{"subject": "انتخاب دبیرخانه عادی برای سری", "letter_kind": "incoming", "confidentiality": "highly_confidential"},
			owner.id, mgr["id"],
		)
		svc.register_letter(
			db, bid, blocked_draft["id"],
			{"letter_kind": "incoming", "secretariat_id": main["id"]},
			owner.id, mgr["id"],
		)
	assert classified.value.code == "OA_CONFIDENTIAL_SECRETARIAT_REQUIRED"

	printed = svc.get_letter_print(db, bid, out_reg["id"], owner.id, mgr["id"], is_admin=True)
	assert "signatures" in printed["print"]
	assert printed["print"]["copies_label"] in {"Copies", "رونوشت"}

	reg_src = (Path(__file__).resolve().parents[1] / "app" / "services" / "workflow" / "trigger_registry.py").read_text(encoding="utf-8")
	assert 'self.register("office_automation.letter_registered"' in reg_src
	assert 'self.register("office_automation.letter_referred"' in reg_src
	assert 'self.register("office_automation.letter_archived"' in reg_src
	main_src = (Path(__file__).resolve().parents[1] / "app" / "main.py").read_text(encoding="utf-8")
	assert "oa_automation_background_loop" in main_src

	due_letter = svc.create_letter_draft(db, bid, {"subject": "پیگیری سررسید", "letter_kind": "internal"}, owner.id, mgr["id"])
	due_reg = svc.register_letter(db, bid, due_letter["id"], {}, owner.id, mgr["id"])
	row = db.query(OaLetter).filter(OaLetter.id == due_reg["id"]).one()
	row.follow_up_at = date.today()
	db.commit()
	stats = ext.notify_due_followups(db, bid)
	assert stats["due_letters"] >= 1
	db.commit()
	again = ext.notify_due_followups(db, bid)
	assert again["due_letters"] == 0
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_classified_letter_requires_confidential_secretariat_and_clearance(_plugin):
	db = _session()
	owner = _user(db, "oa-secret-owner@example.com", "oa6")
	stranger = _user(db, "oa-secret-stranger@example.com", "oa7")
	bid = 1
	unit = svc.create_org_unit(db, bid, {"code": "hq", "name_i18n": {"fa": "ستاد", "en": "HQ"}}, owner.id)
	clerk = svc.create_position(
		db, bid,
		{"code": "sec", "org_unit_id": unit["id"], "name_i18n": {"fa": "دبیر", "en": "Clerk"}, "is_secretariat": True},
		owner.id,
	)
	other = svc.create_position(
		db, bid,
		{"code": "other", "org_unit_id": unit["id"], "name_i18n": {"fa": "بیگانه", "en": "Outsider"}},
		owner.id,
	)
	svc.assign_position_holder(db, bid, {"position_id": clerk["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	svc.assign_position_holder(db, bid, {"position_id": other["id"], "user_id": stranger.id, "is_primary": True}, owner.id)

	blocked = svc.create_letter_draft(
		db, bid,
		{"subject": "سری بدون دبیرخانه", "letter_kind": "incoming", "confidentiality": "secret"},
		owner.id, clerk["id"],
	)
	with pytest.raises(ApiError) as missing:
		svc.register_letter(db, bid, blocked["id"], {"letter_kind": "incoming"}, owner.id, clerk["id"])
	assert missing.value.code == "OA_CONFIDENTIAL_SECRETARIAT_REQUIRED"

	conf = ext.create_secretariat(
		db, bid,
		{"code": "secret", "name_i18n": {"fa": "محرمانه", "en": "Confidential"}, "is_confidential": True, "incoming_prefix": "SEC"},
		owner.id,
	)
	draft = svc.create_letter_draft(
		db, bid,
		{"subject": "نامه سری قابل جستجو", "body": "متن سری", "letter_kind": "incoming", "confidentiality": "secret"},
		owner.id, clerk["id"],
	)
	registered = svc.register_letter(db, bid, draft["id"], {"letter_kind": "incoming"}, owner.id, clerk["id"])
	assert registered["secretariat_id"] == conf["id"]

	registry = svc.list_cartable(db, bid, owner.id, clerk["id"], folder="registry")
	assert all(item["id"] != registered["id"] for item in registry["items"])
	hidden = svc.search_letters(db, bid, stranger.id, q="قابل جستجو", is_admin=False)
	assert hidden == []
	with pytest.raises(ApiError) as forbidden:
		svc.get_letter(db, bid, registered["id"], stranger.id, other["id"], is_admin=False)
	assert forbidden.value.code == "OA_LETTER_FORBIDDEN"

	visible = svc.search_letters(db, bid, owner.id, q="قابل جستجو", is_admin=False)
	assert any(item["id"] == registered["id"] for item in visible)
	opened = svc.get_letter(db, bid, registered["id"], owner.id, clerk["id"], is_admin=False)
	assert any(event["action"] == "letter.view" for event in opened["timeline"])
	with pytest.raises(ApiError) as reply_denied:
		svc.reply_to_letter(db, bid, registered["id"], {}, stranger.id, other["id"])
	assert reply_denied.value.code == "OA_LETTER_FORBIDDEN"
	secret_reply = svc.reply_to_letter(db, bid, registered["id"], {}, owner.id, clerk["id"])
	assert secret_reply["status"] == "draft"
	assert secret_reply["confidentiality"] == "secret"

	shared = svc.refer_letter(
		db, bid, registered["id"],
		{"recipients": [{"to_position_id": other["id"], "kind": "action"}]},
		owner.id, clerk["id"],
	)
	assert any(item["to_position_id"] == other["id"] for item in shared["referrals"])
	seen = svc.get_letter(db, bid, registered["id"], stranger.id, other["id"], is_admin=False)
	assert seen["subject"] == "نامه سری قابل جستجو"

	due = svc.create_letter_draft(db, bid, {"subject": "ارجاع معوق", "letter_kind": "internal"}, owner.id, clerk["id"])
	due_reg = svc.register_letter(
		db, bid, due["id"],
		{"recipients": [{"to_position_id": other["id"], "kind": "action", "due_at": "2020-01-01"}]},
		owner.id, clerk["id"], calendar_type="gregorian",
	)
	box = svc.list_cartable(db, bid, stranger.id, other["id"], folder="overdue")
	assert any(item["id"] == due_reg["id"] for item in box["items"])
	fresh = svc.create_letter_draft(db, bid, {"subject": "ارجاع آینده", "letter_kind": "internal"}, owner.id, clerk["id"])
	fresh_reg = svc.register_letter(
		db, bid, fresh["id"],
		{"recipients": [{"to_position_id": other["id"], "kind": "action", "due_at": "2099-01-01"}]},
		owner.id, clerk["id"], calendar_type="gregorian",
	)
	box = svc.list_cartable(db, bid, stranger.id, other["id"], folder="overdue")
	assert any(item["id"] == due_reg["id"] for item in box["items"])
	assert all(item["id"] != fresh_reg["id"] for item in box["items"])
	dash = svc.get_dashboard(db, bid, stranger.id, other["id"])
	assert dash["counts"]["overdue"] >= 1
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_saved_cartable_filter_stays_private(_plugin):
	db = _session()
	owner = _user(db, "oa-filter-owner@example.com", "oa8")
	other = _user(db, "oa-filter-other@example.com", "oa9")
	saved = svc.save_saved_filter(db, 1, owner.id, {"name": "معوق قرارداد", "folder": "overdue", "q": "قرارداد"})
	assert saved["folder"] == "overdue"
	assert saved["q"] == "قرارداد"
	updated = svc.save_saved_filter(db, 1, owner.id, {"name": "معوق قرارداد", "folder": "inbox"})
	assert updated["id"] == saved["id"]
	assert updated["folder"] == "inbox"
	assert updated["q"] is None
	assert svc.list_saved_filters(db, 1, other.id) == []
	assert [item["id"] for item in svc.list_saved_filters(db, 1, owner.id)] == [saved["id"]]
	with pytest.raises(ApiError) as invalid:
		svc.save_saved_filter(db, 1, owner.id, {"name": "بد", "folder": "kanban"})
	assert invalid.value.code == "OA_FOLDER_INVALID"
	removed = svc.delete_saved_filter(db, 1, owner.id, saved["id"])
	assert removed["deleted"] is True
	with pytest.raises(ApiError) as missing:
		svc.delete_saved_filter(db, 1, other.id, saved["id"])
	assert missing.value.code == "OA_FILTER_NOT_FOUND"
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_cartable_board_moves_only_by_referral_action(_plugin):
	db = _session()
	owner = _user(db, "oa-board-owner@example.com", "oa10")
	clerk = _user(db, "oa-board-clerk@example.com", "oa11")
	bid = 1
	unit = svc.create_org_unit(db, bid, {"code": "ops", "name_i18n": {"fa": "عملیات", "en": "Ops"}}, owner.id)
	src = svc.create_position(
		db, bid, {"code": "src", "org_unit_id": unit["id"], "name_i18n": {"fa": "مبدأ", "en": "Source"}, "is_secretariat": True}, owner.id,
	)
	dst = svc.create_position(
		db, bid, {"code": "dst", "org_unit_id": unit["id"], "name_i18n": {"fa": "مقصد", "en": "Target"}}, owner.id,
	)
	svc.assign_position_holder(db, bid, {"position_id": src["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	svc.assign_position_holder(db, bid, {"position_id": dst["id"], "user_id": clerk.id, "is_primary": True}, owner.id)
	draft = svc.create_letter_draft(db, bid, {"subject": "کار برد", "body": "متن محرمانه برد", "letter_kind": "internal"}, owner.id, src["id"])
	registered = svc.register_letter(
		db, bid, draft["id"],
		{"recipients": [{"to_position_id": dst["id"], "kind": "action"}]},
		owner.id, src["id"],
	)
	board = svc.list_cartable_board(db, bid, clerk.id, dst["id"], q="کار برد")
	pending = board["columns"]["pending"]["items"]
	assert any(item["id"] == registered["id"] for item in pending)
	assert all("body" not in item for item in pending)
	referral_id = next(item["referral_id"] for item in pending if item["id"] == registered["id"])
	with pytest.raises(ApiError) as forbidden:
		svc.complete_referral(db, bid, referral_id, {}, owner.id, src["id"])
	assert forbidden.value.code == "OA_REFERRAL_FORBIDDEN"
	still = svc.list_cartable_board(db, bid, clerk.id, dst["id"])
	assert any(item["referral_id"] == referral_id for item in still["columns"]["pending"]["items"])
	svc.complete_referral(db, bid, referral_id, {"note": "انجام شد"}, clerk.id, dst["id"])
	moved = svc.list_cartable_board(db, bid, clerk.id, dst["id"])
	assert all(item["referral_id"] != referral_id for item in moved["columns"]["pending"]["items"])
	assert any(item["referral_id"] == referral_id for item in moved["columns"]["done"]["items"])
	assert moved["columns"]["done"]["total"] >= 1
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_personal_desk_is_limited_to_the_acting_position(_plugin):
	db = _session()
	owner = _user(db, "oa-desk-owner@example.com", "oa12")
	clerk = _user(db, "oa-desk-clerk@example.com", "oa13")
	bid = 1
	unit = svc.create_org_unit(db, bid, {"code": "desk", "name_i18n": {"fa": "میز", "en": "Desk"}}, owner.id)
	src = svc.create_position(
		db, bid, {"code": "from", "org_unit_id": unit["id"], "name_i18n": {"fa": "فرستنده", "en": "From"}, "is_secretariat": True}, owner.id,
	)
	dst = svc.create_position(
		db, bid, {"code": "to", "org_unit_id": unit["id"], "name_i18n": {"fa": "گیرنده", "en": "To"}}, owner.id,
	)
	svc.assign_position_holder(db, bid, {"position_id": src["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	svc.assign_position_holder(db, bid, {"position_id": dst["id"], "user_id": clerk.id, "is_primary": True}, owner.id)
	late = svc.create_letter_draft(db, bid, {"subject": "کار معوق میز", "body": "نباید در میز بیاید", "letter_kind": "internal"}, owner.id, src["id"])
	late_reg = svc.register_letter(
		db, bid, late["id"],
		{"recipients": [{"to_position_id": dst["id"], "kind": "action", "due_at": "2020-01-01"}]},
		owner.id, src["id"], calendar_type="gregorian",
	)
	soon = svc.create_letter_draft(db, bid, {"subject": "کار نزدیک", "letter_kind": "internal"}, owner.id, src["id"])
	svc.register_letter(
		db, bid, soon["id"],
		{"recipients": [{"to_position_id": dst["id"], "kind": "action", "due_at": "2099-01-01"}]},
		owner.id, src["id"], calendar_type="gregorian",
	)
	tracked = svc.create_letter_draft(db, bid, {"subject": "پیگیری فرستنده", "letter_kind": "internal"}, owner.id, src["id"])
	tracked_reg = svc.register_letter(db, bid, tracked["id"], {}, owner.id, src["id"])
	row = db.query(OaLetter).filter(OaLetter.id == tracked_reg["id"]).one()
	row.follow_up_at = date.today()
	db.commit()

	mine = svc.get_personal_desk(db, bid, clerk.id, dst["id"], horizon_days=7)
	assert any(item["letter_id"] == late_reg["id"] for item in mine["overdue"])
	assert all(item["letter_id"] != late_reg["id"] for item in mine["due_soon"])
	assert all("body" not in item for item in mine["overdue"])
	assert mine["counts"]["overdue"] >= 1
	sender = svc.get_personal_desk(db, bid, owner.id, src["id"])
	assert all(item["letter_id"] != late_reg["id"] for item in sender["overdue"])
	assert any(item["letter_id"] == tracked_reg["id"] for item in sender["follow_ups"])
	db.close()
