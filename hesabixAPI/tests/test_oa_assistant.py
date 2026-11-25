"""تأیید سروری عمل پرریسک، پیشنهاد ارجاع و پیش‌نویس منتشرنشده."""
from __future__ import annotations

from unittest.mock import patch

import pytest

from adapters.db.models.oa_mcp_confirmation import OaMcpConfirmation
from adapters.db.models.oa_process import OaProcessVersion
from adapters.db.models.office_automation import OaReferral
from app.core.responses import ApiError
from app.services import oa_assistant_service as assistant
from app.services import oa_mcp_confirmation as gate
from app.services import office_automation_service as oa
from app.services.ai.ai_mcp_service import prepare_mcp_tool_arguments
from tests.test_office_automation_plugin import _session, _user


class _Fn:
	def __init__(self, risk: str):
		self.category = "office_automation"
		self.risk_level = risk


class _Reg:
	def __init__(self, risk: str = "high"):
		self.risk = risk

	def get_function(self, name):
		return _Fn(self.risk)


def test_sensitive_call_waits_for_app_approval_and_ignores_argument_flag():
	db = _session()
	user = _user(db, "confirm@example.com", "c1")
	other = _user(db, "other-confirm@example.com", "c2")
	args = {"letter_id": 4, "as_position_id": 9, "approve_writes": True}
	cleaned = prepare_mcp_tool_arguments(args, business_id=1)
	assert "approve_writes" not in cleaned
	held = gate.gate_sensitive_oa_call(
		db, _Reg(), "sign_oa_letter", cleaned, user_id=user.id, business_id=1, connection_id=3,
	)
	assert held["error"] == "OA_CONFIRMATION_REQUIRED"
	assert db.query(OaMcpConfirmation).filter(OaMcpConfirmation.status == "consumed").count() == 0
	with pytest.raises(ApiError) as channel:
		gate.decide_confirmation(db, 1, user.id, held["confirmation_id"], accept=True, via_mcp=True)
	assert channel.value.code == "OA_CONFIRMATION_CHANNEL"
	with pytest.raises(ApiError) as stranger:
		gate.decide_confirmation(db, 1, other.id, held["confirmation_id"], accept=True)
	assert stranger.value.code == "OA_CONFIRMATION_NOT_FOUND"
	approved = gate.decide_confirmation(db, 1, user.id, held["confirmation_id"], accept=True)
	assert approved["status"] == "approved"
	mismatch = gate.gate_sensitive_oa_call(
		db, _Reg(), "sign_oa_letter", {"letter_id": 5, "as_position_id": 9},
		user_id=user.id, business_id=1, connection_id=3, confirmation_id=held["confirmation_id"],
	)
	assert mismatch["error"] == "OA_CONFIRMATION_MISMATCH"
	ready = gate.gate_sensitive_oa_call(
		db, _Reg(), "sign_oa_letter", cleaned,
		user_id=user.id, business_id=1, connection_id=3, confirmation_id=held["confirmation_id"],
	)
	assert ready is None
	row = db.query(OaMcpConfirmation).filter(OaMcpConfirmation.id == held["confirmation_id"]).one()
	assert row.status == "consumed"
	again = gate.gate_sensitive_oa_call(
		db, _Reg(), "sign_oa_letter", cleaned,
		user_id=user.id, business_id=1, connection_id=3, confirmation_id=held["confirmation_id"],
	)
	assert again["error"] == "OA_CONFIRMATION_CLOSED"
	plain = gate.gate_sensitive_oa_call(
		db, _Reg("medium"), "add_oa_paraph", {"letter_id": 4}, user_id=user.id, business_id=1, connection_id=3,
	)
	assert plain["error"] == "OA_CONFIRMATION_REQUIRED"
	read = gate.gate_sensitive_oa_call(
		db, _Reg("safe"), "list_oa_letters", {"as_position_id": 9}, user_id=user.id, business_id=1, connection_id=3,
	)
	assert read is None
	secret = gate.gate_sensitive_oa_call(
		db, _Reg("medium"), "create_oa_letter_draft",
		{"as_position_id": 9, "payload": {"confidentiality": "secret", "subject": "محرمانه"}},
		user_id=user.id, business_id=1, connection_id=3,
	)
	assert secret["error"] == "OA_CONFIRMATION_REQUIRED"
	assert "subject" not in secret["summary"]
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_suggestion_does_not_refer_and_text_draft_is_not_published(_plugin):
	db = _session()
	owner = _user(db, "sugg-owner@example.com", "s1")
	clerk = _user(db, "sugg-clerk@example.com", "s2")
	bid = 1
	unit = oa.create_org_unit(db, bid, {"code": "hq", "name_i18n": {"fa": "ستاد", "en": "HQ"}}, owner.id)
	mgr = oa.create_position(db, bid, {"code": "mgr", "org_unit_id": unit["id"], "name_i18n": {"fa": "مدیر", "en": "Manager"}, "is_secretariat": True}, owner.id)
	exp = oa.create_position(db, bid, {"code": "exp", "org_unit_id": unit["id"], "name_i18n": {"fa": "کارشناس", "en": "Expert"}}, owner.id)
	oa.assign_position_holder(db, bid, {"position_id": mgr["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, bid, {"position_id": exp["id"], "user_id": clerk.id, "is_primary": True}, owner.id)
	draft = oa.create_letter_draft(db, bid, {"subject": "اقدام", "letter_kind": "internal"}, owner.id, mgr["id"])
	registered = oa.register_letter(
		db, bid, draft["id"],
		{"recipients": [{"to_position_id": exp["id"], "kind": "action"}]},
		owner.id, mgr["id"],
	)
	before = db.query(OaReferral).filter(OaReferral.letter_id == registered["id"]).count()
	suggested = assistant.suggest_referral(db, bid, clerk.id, exp["id"], registered["id"])
	assert suggested["applied"] is False
	assert any(item["reason"] == "return_to_sender" and item["to_position_id"] == mgr["id"] for item in suggested["suggestions"])
	assert db.query(OaReferral).filter(OaReferral.letter_id == registered["id"]).count() == before
	created = assistant.draft_process_from_text(
		db, bid, owner.id,
		{"code": "review_flow", "name": "بررسی", "text": f"بررسی | {exp['id']} | 4\n# یادداشت\n"},
	)
	assert created["published_versions"] == 0
	assert created["step_count"] == 1
	assert db.query(OaProcessVersion).count() == 0
	with pytest.raises(ApiError) as bad:
		assistant.draft_process_from_text(db, bid, owner.id, {"code": "bad_flow", "text": "فقط نام"})
	assert bad.value.code == "OA_PROCESS_TEXT_INVALID"
	db.close()
