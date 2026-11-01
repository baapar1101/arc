"""گیت لایسنس، گردش نامه سمت‌محور و ابزارهای MCP اتوماسیون اداری."""
from __future__ import annotations

import re
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from adapters.db.models.file_storage import FileStorage
from adapters.db.models.office_automation import (
	OaAuditLog,
	OaDelegation,
	OaLetter,
	OaLetterAttachment,
	OaLetterLink,
	OaLetterNumberCounter,
	OaOrgUnit,
	OaParaph,
	OaPosition,
	OaPositionHolder,
	OaReferral,
	OaSettings,
)
from adapters.db.models.user import User
from adapters.db.session import Base
from adapters.db.seed_data.notification_event_types_seed import OFFICE_AUTOMATION_EVENT_CODES
from app.core.office_automation_plugin_dependency import PLUGIN_CODE, check_office_automation_plugin_active
from app.core.responses import ApiError
from app.services import office_automation_service as svc
from app.services.ai.ai_tool_manifest import get_manifest_entry


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


OA_TOOLS = (
	"get_oa_dashboard",
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
			OaLetter.__table__,
			OaLetterNumberCounter.__table__,
			OaReferral.__table__,
			OaParaph.__table__,
			OaLetterAttachment.__table__,
			OaLetterLink.__table__,
			OaAuditLog.__table__,
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
