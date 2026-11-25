"""شعبه، نگهداری بدون حذف، تبادل نامه عادی، و جدایی امضای ارائه‌دهنده از امضای تصویری."""
from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch

import pytest

from datetime import date, datetime

from adapters.db.models.crm import Deal
from adapters.db.models.document import Document
from adapters.db.models.file_storage import FileStorage
from adapters.db.models.oa_document import OaDocument
from adapters.db.models.office_automation import OaLetter, OaReferral
from app.services import oa_document_service as docs
from app.core.responses import ApiError
from app.services import oa_enterprise_service as ent
from app.services import office_automation_extended_service as ext
from app.services import office_automation_service as oa
from tests.test_office_automation_plugin import _session, _user


def _org(db, owner, bid, code):
	unit = oa.create_org_unit(db, bid, {"code": code, "name_i18n": {"fa": code, "en": code}}, owner.id)
	branch = ent.create_branch(db, bid, owner.id, {"code": f"b_{code}", "name": code})
	secretariat = ext.create_secretariat(
		db, bid, {"code": f"sec_{code}", "name": code, "branch_id": branch["id"], "is_default": True}, owner.id,
	)
	position = oa.create_position(
		db, bid,
		{"code": f"p_{code}", "org_unit_id": unit["id"], "name_i18n": {"fa": code, "en": code}, "is_secretariat": True, "secretariat_id": secretariat["id"]},
		owner.id,
	)
	oa.assign_position_holder(db, bid, {"position_id": position["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	return branch, position


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_branch_retention_exchange_and_provider_signature(_plugin):
	db = _session()
	owner = _user(db, "ent-owner@example.com", "e1")
	other = _user(db, "ent-other@example.com", "e2")
	branch, position = _org(db, owner, 1, "tehran")
	_target_branch, target_position = _org(db, other, 2, "shiraz")
	ent.save_retention_policy(db, 1, owner.id, {"confidentiality": "normal", "retain_days": 30})
	draft = oa.create_letter_draft(
		db, 1, {"subject": "نامه شعبه", "body": "متن قابل تبادل", "letter_kind": "internal", "letter_date": "2020-01-01"},
		owner.id, position["id"], calendar_type="gregorian",
	)
	registered = oa.register_letter(db, 1, draft["id"], {}, owner.id, position["id"])
	stored = db.query(OaLetter).filter(OaLetter.id == registered["id"]).one()
	assert stored.branch_id == branch["id"]
	assert str(stored.retain_until) == "2020-01-31"
	before = db.query(OaLetter).count()
	marked = ent.mark_due_retention(db, 1)
	assert marked["deleted"] == 0
	assert marked["letters"] == 1
	assert db.query(OaLetter).count() == before
	held = ent.hold_letter_retention(db, 1, owner.id, stored.id)
	assert held["retention_status"] == "held"
	assert held["deleted"] is False
	stored.confidentiality = "secret"
	db.commit()
	with pytest.raises(ApiError) as blocked:
		ent.exchange_letter(db, 1, owner.id, position["id"], stored.id, 2, target_position["id"])
	assert blocked.value.code == "OA_EXCHANGE_FORBIDDEN"
	stored.confidentiality = "normal"
	db.commit()
	sent = ent.exchange_letter(db, 1, owner.id, position["id"], stored.id, 2, target_position["id"])
	assert sent["target_status"] == "draft"
	copy = db.query(OaLetter).filter(OaLetter.id == sent["target_letter_id"]).one()
	assert copy.business_id == 2
	assert copy.body == "متن قابل تبادل"
	assert db.query(OaLetter).filter(OaLetter.id == stored.id).count() == 1
	provider = ent.create_signature_provider(db, 1, owner.id, {"code": "ext", "name": "ارائه‌دهنده"})
	assert provider["assurance"] == "provider_attestation"
	requested = ent.request_qualified_signature(db, 1, owner.id, position["id"], stored.id, provider["id"])
	assert requested["sign_status"] == "none"
	assert requested["image_sign_unchanged"] is True
	listed = ent.list_signature_providers(db, 1)
	assert listed["items"][0]["id"] == provider["id"]
	assert "access_token" not in listed["items"][0]
	policies = ent.list_retention_policies(db, 1)
	assert policies["items"][0]["retain_days"] == 30
	requests = ent.list_letter_qualified_requests(db, 1, owner.id, position["id"], stored.id)
	assert requests["items"][0]["id"] == requested["id"]
	assert requests["items"][0]["live"] is False
	assert requests["items"][0]["sign_status"] == "none"
	done = ent.record_provider_result(db, 1, owner.id, requested["id"], "EXT-100", "completed")
	assert done["qualified_sign_status"] == "completed"
	assert done["sign_status"] == "none"
	assert done["assurance"] == "provider_attestation"
	stranger = _user(db, "ent-stranger@example.com", "e1b")
	outsider = oa.create_position(db, 1, {"code": "p_tehran_out", "org_unit_id": position["org_unit_id"], "name_i18n": {"fa": "بیرون", "en": "Out"}}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": outsider["id"], "user_id": stranger.id, "is_primary": True}, owner.id)
	copies_before = db.query(OaLetter).filter(OaLetter.business_id == 2).count()
	with pytest.raises(ApiError) as unseen:
		ent.exchange_letter(db, 1, stranger.id, outsider["id"], stored.id, 2, target_position["id"])
	assert unseen.value.code == "OA_LETTER_FORBIDDEN"
	assert db.query(OaLetter).filter(OaLetter.business_id == 2, OaLetter.body == "متن قابل تبادل").count() == 1
	assert db.query(OaLetter).filter(OaLetter.business_id == 2).count() == copies_before
	db.close()


class _ProviderHandler(BaseHTTPRequestHandler):
	last_body = None
	last_auth = None
	status_code = 200

	def do_POST(self):
		length = int(self.headers.get("Content-Length") or 0)
		raw = self.rfile.read(length)
		_ProviderHandler.last_body = json.loads(raw.decode("utf-8"))
		_ProviderHandler.last_auth = self.headers.get("Authorization")
		if _ProviderHandler.status_code != 200:
			self.send_response(_ProviderHandler.status_code)
			self.end_headers()
			return
		payload = json.dumps({"external_ref": "LIVE-99", "outcome": "completed"}).encode("utf-8")
		self.send_response(200)
		self.send_header("Content-Type", "application/json")
		self.send_header("Content-Length", str(len(payload)))
		self.end_headers()
		self.wfile.write(payload)

	def log_message(self, fmt, *args):
		return


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_live_provider_response_does_not_complete_image_signature(_plugin):
	db = _session()
	owner = _user(db, "live-owner@example.com", "e3")
	branch, position = _org(db, owner, 1, "live")
	draft = oa.create_letter_draft(
		db, 1, {"subject": "موضوع سری نباید برود", "body": "متن نامه", "letter_kind": "internal"},
		owner.id, position["id"],
	)
	registered = oa.register_letter(db, 1, draft["id"], {}, owner.id, position["id"])
	server = ThreadingHTTPServer(("127.0.0.1", 0), _ProviderHandler)
	thread = threading.Thread(target=server.serve_forever, daemon=True)
	thread.start()
	try:
		_ProviderHandler.status_code = 200
		provider = ent.create_signature_provider(
			db, 1, owner.id,
			{"code": "live", "name": "زنده", "endpoint_url": f"http://127.0.0.1:{server.server_address[1]}/sign", "access_token": "secret-token"},
		)
		assert provider["live"] is True
		assert provider["has_token"] is True
		assert "access_token" not in provider
		done = ent.request_qualified_signature(db, 1, owner.id, position["id"], registered["id"], provider["id"])
		assert done["status"] == "completed"
		assert done["external_ref"] == "LIVE-99"
		assert done["sign_status"] == "none"
		assert done["qualified_sign_status"] == "completed"
		assert done["image_sign_unchanged"] is True
		assert _ProviderHandler.last_auth == "Bearer secret-token"
		assert _ProviderHandler.last_body["letter_id"] == registered["id"]
		assert "body" not in _ProviderHandler.last_body
		assert "subject" not in _ProviderHandler.last_body
		assert "access_token" not in _ProviderHandler.last_body
		with pytest.raises(ApiError) as manual:
			ent.record_provider_result(db, 1, owner.id, done["id"], "FAKE-1", "completed")
		assert manual.value.code == "OA_PROVIDER_REQUEST_CLOSED"
		_ProviderHandler.status_code = 503
		second = oa.create_letter_draft(db, 1, {"subject": "دوم", "letter_kind": "internal"}, owner.id, position["id"])
		second_reg = oa.register_letter(db, 1, second["id"], {}, owner.id, position["id"])
		failed = ent.request_qualified_signature(db, 1, owner.id, position["id"], second_reg["id"], provider["id"])
		assert failed["delivered"] is False
		assert failed["status"] == "awaiting_provider"
		assert failed["sign_status"] == "none"
		with pytest.raises(ApiError) as live:
			ent.record_provider_result(db, 1, owner.id, failed["id"], "FAKE-2", "completed")
		assert live.value.code == "OA_PROVIDER_LIVE"
		still = db.query(OaLetter).filter(OaLetter.id == second_reg["id"]).one()
		assert still.sign_status == "none"
		assert still.qualified_sign_status == "pending"
	finally:
		server.shutdown()
		server.server_close()
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_letter_links_same_business_document_and_deal_without_posting(_plugin):
	from adapters.db.models.business import Business, BusinessField, BusinessType
	from adapters.db.models.business_crm_settings import BusinessCrmSettings
	from adapters.db.models.crm import CrmManagerLink, CrmRecordAcl

	db = _session()
	Document.__table__.create(db.get_bind(), checkfirst=True)
	Deal.__table__.create(db.get_bind(), checkfirst=True)
	Business.__table__.create(db.get_bind(), checkfirst=True)
	BusinessCrmSettings.__table__.create(db.get_bind(), checkfirst=True)
	CrmManagerLink.__table__.create(db.get_bind(), checkfirst=True)
	CrmRecordAcl.__table__.create(db.get_bind(), checkfirst=True)
	owner = _user(db, "link-owner@example.com", "e4")
	reader = _user(db, "link-reader@example.com", "e5")
	db.add(Business(
		id=1, name="کسب پیوند", business_type=BusinessType.COMPANY, business_field=BusinessField.SERVICE, owner_id=owner.id,
	))
	db.commit()
	_branch, position = _org(db, owner, 1, "link")
	draft = oa.create_letter_draft(db, 1, {"subject": "پیوند", "body": "متن ثابت", "letter_kind": "internal"}, owner.id, position["id"])
	registered = oa.register_letter(db, 1, draft["id"], {}, owner.id, position["id"])
	now = datetime.utcnow()
	own_doc = Document(
		code="INV-1", business_id=1, fiscal_year_id=1, currency_id=1, created_by_user_id=owner.id,
		registered_at=now, document_date=date(2026, 1, 2), document_type="invoice", is_proforma=False,
		description="شرح سند", created_at=now, updated_at=now,
	)
	other_doc = Document(
		code="INV-2", business_id=2, fiscal_year_id=1, currency_id=1, created_by_user_id=owner.id,
		registered_at=now, document_date=date(2026, 1, 2), document_type="invoice", is_proforma=False,
		created_at=now, updated_at=now,
	)
	own_deal = Deal(
		business_id=1, person_id=1, process_definition_id=1, stage_id=1, code="D1", title="فرصت داخلی",
		amount=10, created_by_user_id=owner.id, created_at=now, updated_at=now,
	)
	other_deal = Deal(
		business_id=2, person_id=1, process_definition_id=1, stage_id=1, code="D2", title="فرصت دیگر",
		amount=10, created_by_user_id=owner.id, created_at=now, updated_at=now,
	)
	db.add_all([own_doc, other_doc, own_deal, other_deal])
	db.commit()
	with pytest.raises(ApiError) as foreign_doc:
		ent.link_letter_commercial(db, 1, owner.id, position["id"], registered["id"], "document", other_doc.id)
	assert foreign_doc.value.code == "CRM_DOCUMENT_NOT_IN_BUSINESS"
	with pytest.raises(ApiError) as foreign_deal:
		ent.link_letter_commercial(db, 1, owner.id, position["id"], registered["id"], "deal", other_deal.id)
	assert foreign_deal.value.code == "OA_DEAL_NOT_FOUND"
	linked_doc = ent.link_letter_commercial(db, 1, owner.id, position["id"], registered["id"], "document", own_doc.id)
	linked_deal = ent.link_letter_commercial(db, 1, owner.id, position["id"], registered["id"], "deal", own_deal.id)
	assert linked_doc["label"] == "INV-1"
	assert linked_deal["label"] == "فرصت داخلی"
	letter = db.query(OaLetter).filter(OaLetter.id == registered["id"]).one()
	assert letter.body == "متن ثابت"
	assert db.get(Document, own_doc.id).description == "شرح سند"
	assert int(db.get(Deal, own_deal.id).amount) == 10
	listed = ent.list_letter_commercial_links(db, 1, owner.id, position["id"], registered["id"])
	assert {item["target_kind"] for item in listed["items"]} == {"document", "deal"}
	inbox = oa.create_position(
		db, 1,
		{"code": "p_link_read", "org_unit_id": position["org_unit_id"], "name_i18n": {"fa": "خواننده", "en": "Reader"}},
		owner.id,
	)
	oa.assign_position_holder(db, 1, {"position_id": inbox["id"], "user_id": reader.id, "is_primary": True}, owner.id)
	oa.refer_letter(db, 1, registered["id"], {"to_position_id": inbox["id"], "kind": "info"}, owner.id, position["id"])
	db.add(BusinessCrmSettings(business_id=1, record_acl_enabled=True, updated_at=datetime.utcnow()))
	db.commit()
	with pytest.raises(ApiError) as hidden_deal:
		ent.link_letter_commercial(db, 1, reader.id, inbox["id"], registered["id"], "deal", own_deal.id)
	assert hidden_deal.value.code == "NOT_FOUND"
	assert "فرصت داخلی" not in str(hidden_deal.value)
	visible = ent.list_letter_commercial_links(db, 1, reader.id, inbox["id"], registered["id"])
	assert [item["target_kind"] for item in visible["items"]] == ["document"]
	assert "فرصت داخلی" not in json.dumps(visible, ensure_ascii=False)
	assert all(item["target_kind"] != "deal" for item in visible["items"])
	owner_again = ent.list_letter_commercial_links(db, 1, owner.id, position["id"], registered["id"])
	assert {item["target_kind"] for item in owner_again["items"]} == {"document", "deal"}
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_volume_and_performance_skip_letters_the_user_cannot_see(_plugin):
	db = _session()
	owner = _user(db, "rep-owner@example.com", "r1")
	stranger = _user(db, "rep-stranger@example.com", "r2")
	unit = oa.create_org_unit(db, 1, {"code": "rep", "name_i18n": {"fa": "گزارش", "en": "Report"}}, owner.id)
	sec = ext.create_secretariat(db, 1, {"code": "sec_rep", "name": "محرمانه", "is_confidential": True, "is_default": True}, owner.id)
	owner_pos = oa.create_position(
		db, 1,
		{"code": "p_rep", "org_unit_id": unit["id"], "name_i18n": {"fa": "دبیر", "en": "Clerk"}, "is_secretariat": True, "secretariat_id": sec["id"]},
		owner.id,
	)
	stranger_pos = oa.create_position(
		db, 1, {"code": "p_out", "org_unit_id": unit["id"], "name_i18n": {"fa": "بیرون", "en": "Out"}}, owner.id,
	)
	oa.assign_position_holder(db, 1, {"position_id": owner_pos["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": stranger_pos["id"], "user_id": stranger.id, "is_primary": True}, owner.id)
	secret = oa.create_letter_draft(
		db, 1, {"subject": "نامه سری", "letter_kind": "internal", "confidentiality": "secret"}, owner.id, owner_pos["id"],
	)
	secret_reg = oa.register_letter(
		db, 1, secret["id"], {"recipients": [{"to_position_id": owner_pos["id"], "kind": "action"}]}, owner.id, owner_pos["id"],
	)
	normal = oa.create_letter_draft(db, 1, {"subject": "نامه عادی", "letter_kind": "internal"}, owner.id, owner_pos["id"])
	normal_reg = oa.register_letter(
		db, 1, normal["id"], {"recipients": [{"to_position_id": stranger_pos["id"], "kind": "action"}]}, owner.id, owner_pos["id"],
	)
	oa.complete_referral(db, 1, secret_reg["referrals"][0]["id"], {}, owner.id, owner_pos["id"])
	oa.complete_referral(db, 1, normal_reg["referrals"][0]["id"], {}, stranger.id, stranger_pos["id"])
	hidden = ext.volume_report(db, 1, user_id=stranger.id)
	assert sum(hidden["by_kind"].values()) == 1
	full = ext.volume_report(db, 1, user_id=stranger.id, is_admin=True)
	assert sum(full["by_kind"].values()) == 2
	own_perf = ext.performance_report(db, 1, user_id=stranger.id)
	assert sum(item["completed"] for item in own_perf["items"]) == 1
	admin_perf = ext.performance_report(db, 1, user_id=stranger.id, is_admin=True)
	assert sum(item["completed"] for item in admin_perf["items"]) == 2
	assert "subject" not in admin_perf["items"][0]
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_classified_subject_stays_out_of_workflow_and_search_fills_the_page(_plugin):
	import sys
	import types

	payloads = []
	module = types.ModuleType("app.services.workflow.workflow_trigger_service")
	module.trigger_workflows = lambda db, business_id, trigger_type, payload, user_id: payloads.append(dict(payload))
	previous = sys.modules.get(module.__name__)
	sys.modules[module.__name__] = module
	db = _session()
	try:
		_assert_workflow_payload_and_search(db, payloads)
	finally:
		db.close()
		if previous is None:
			sys.modules.pop(module.__name__, None)
		else:
			sys.modules[module.__name__] = previous


def _assert_workflow_payload_and_search(db, payloads):
	owner = _user(db, "flow-owner@example.com", "f1")
	stranger = _user(db, "flow-stranger@example.com", "f2")
	unit = oa.create_org_unit(db, 1, {"code": "flow", "name_i18n": {"fa": "جریان", "en": "Flow"}}, owner.id)
	sec = ext.create_secretariat(db, 1, {"code": "sec_flow", "name": "محرمانه", "is_confidential": True, "is_default": True}, owner.id)
	owner_pos = oa.create_position(
		db, 1,
		{"code": "p_flow", "org_unit_id": unit["id"], "name_i18n": {"fa": "دبیر", "en": "Clerk"}, "is_secretariat": True, "secretariat_id": sec["id"]},
		owner.id,
	)
	stranger_pos = oa.create_position(
		db, 1, {"code": "p_flow_out", "org_unit_id": unit["id"], "name_i18n": {"fa": "بیرون", "en": "Out"}}, owner.id,
	)
	oa.assign_position_holder(db, 1, {"position_id": owner_pos["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": stranger_pos["id"], "user_id": stranger.id, "is_primary": True}, owner.id)
	visible = oa.create_letter_draft(db, 1, {"subject": "نامه قابل دیدن", "letter_kind": "internal"}, owner.id, owner_pos["id"])
	oa.register_letter(
		db, 1, visible["id"], {"recipients": [{"to_position_id": stranger_pos["id"], "kind": "info"}]}, owner.id, owner_pos["id"],
	)
	secret = oa.create_letter_draft(
		db, 1, {"subject": "نامه سری", "body": "بدنه سری", "letter_kind": "internal", "confidentiality": "secret"}, owner.id, owner_pos["id"],
	)
	oa.register_letter(db, 1, secret["id"], {}, owner.id, owner_pos["id"])
	secret_events = [item for item in payloads if item.get("confidentiality") == "secret"]
	normal_events = [item for item in payloads if item.get("subject") == "نامه قابل دیدن"]
	assert secret_events
	assert all(item.get("subject") is None and "body" not in item for item in secret_events)
	assert normal_events
	found = oa.search_letters(db, 1, stranger.id, q="نامه", limit=1)
	assert [item["subject"] for item in found] == ["نامه قابل دیدن"]


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_search_limit_skips_more_than_four_hundred_hidden_letters(_plugin):
	db = _session()
	owner = _user(db, "page-owner@example.com", "g1")
	stranger = _user(db, "page-stranger@example.com", "g2")
	unit = oa.create_org_unit(db, 1, {"code": "page", "name_i18n": {"fa": "صفحه", "en": "Page"}}, owner.id)
	sec = ext.create_secretariat(db, 1, {"code": "sec_page", "name": "محرمانه", "is_confidential": True, "is_default": True}, owner.id)
	owner_pos = oa.create_position(
		db, 1,
		{"code": "p_page", "org_unit_id": unit["id"], "name_i18n": {"fa": "دبیر", "en": "Clerk"}, "is_secretariat": True, "secretariat_id": sec["id"]},
		owner.id,
	)
	stranger_pos = oa.create_position(
		db, 1, {"code": "p_page_out", "org_unit_id": unit["id"], "name_i18n": {"fa": "بیرون", "en": "Out"}}, owner.id,
	)
	oa.assign_position_holder(db, 1, {"position_id": owner_pos["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": stranger_pos["id"], "user_id": stranger.id, "is_primary": True}, owner.id)
	visible = oa.create_letter_draft(db, 1, {"subject": "نامه قابل دیدن", "letter_kind": "internal"}, owner.id, owner_pos["id"])
	oa.register_letter(
		db, 1, visible["id"], {"recipients": [{"to_position_id": stranger_pos["id"], "kind": "info"}]}, owner.id, owner_pos["id"],
	)
	now = datetime.utcnow()
	today = date.today()
	db.add_all(
		[
			OaLetter(
				business_id=1,
				letter_kind="internal",
				status="registered",
				subject="نامه پنهان",
				letter_date=today,
				confidentiality="secret",
				origin_position_id=owner_pos["id"],
				created_by_user_id=owner.id,
				sign_status="none",
				retention_status="none",
				qualified_sign_status="none",
				created_at=now,
				updated_at=now,
			)
			for _index in range(401)
		]
	)
	db.commit()
	found = oa.search_letters(db, 1, stranger.id, q="نامه", limit=1)
	assert [item["subject"] for item in found] == ["نامه قابل دیدن"]
	owner_found = oa.search_letters(db, 1, owner.id, q="نامه", limit=1)
	assert owner_found[0]["subject"] == "نامه پنهان"
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_secretariat_branch_change_reaches_the_next_letter(_plugin):
	db = _session()
	owner = _user(db, "branch-move@example.com", "bm")
	_branch, position = _org(db, owner, 1, "branchmove")
	second = ent.create_branch(db, 1, owner.id, {"code": "b_second", "name": "دوم"})
	secretariat_id = position["secretariat_id"]
	updated = ext.update_secretariat(db, 1, secretariat_id, {"branch_id": second["id"]}, owner.id)
	assert updated["branch_id"] == second["id"]
	draft = oa.create_letter_draft(
		db, 1, {"subject": "نامه شعبه دوم", "letter_kind": "internal", "letter_date": "2020-02-01"},
		owner.id, position["id"], calendar_type="gregorian",
	)
	registered = oa.register_letter(db, 1, draft["id"], {}, owner.id, position["id"])
	stored = db.query(OaLetter).filter(OaLetter.id == registered["id"]).one()
	assert stored.branch_id == second["id"]
	with pytest.raises(ApiError) as missing:
		ext.update_secretariat(db, 1, secretariat_id, {"branch_id": 999999}, owner.id)
	assert missing.value.code == "OA_BRANCH_NOT_FOUND"
	cleared = ext.update_secretariat(db, 1, secretariat_id, {"branch_id": None}, owner.id)
	assert cleared["branch_id"] is None
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_reject_sign_cancel_referral_and_reopen_archive(_plugin):
	db = _session()
	owner = _user(db, "desk-owner@example.com", "desk1")
	clerk = _user(db, "desk-clerk@example.com", "desk2")
	_branch, sender = _org(db, owner, 1, "desksign")
	receiver = oa.create_position(
		db, 1,
		{"code": "p_recv", "org_unit_id": sender["org_unit_id"], "name_i18n": {"fa": "گیرنده", "en": "Receiver"}},
		owner.id,
	)
	oa.assign_position_holder(db, 1, {"position_id": receiver["id"], "user_id": clerk.id, "is_primary": True}, owner.id)
	draft = oa.create_letter_draft(
		db, 1, {"subject": "نامه برای رد امضا", "letter_kind": "internal"}, owner.id, sender["id"],
	)
	ext.start_sign_path(
		db, 1, draft["id"], {"steps": [{"position_id": sender["id"], "is_required": True}]}, owner.id, sender["id"],
	)
	rejected = ext.reject_sign_step(db, 1, draft["id"], {"note": "ناقص"}, owner.id, sender["id"])
	assert rejected["sign_status"] == "rejected"
	assert rejected["qualified_sign_status"] == "none"
	with pytest.raises(ApiError) as again:
		ext.reject_sign_step(db, 1, draft["id"], {}, owner.id, sender["id"])
	assert again.value.code == "OA_SIGN_STEP_NOT_FOUND"
	second = oa.create_letter_draft(
		db, 1, {"subject": "نامه برای لغو", "letter_kind": "internal"}, owner.id, sender["id"],
	)
	registered = oa.register_letter(db, 1, second["id"], {}, owner.id, sender["id"])
	oa.refer_letter(
		db, 1, registered["id"], {"to_position_id": receiver["id"], "kind": "action", "instruction": "اقدام"},
		owner.id, sender["id"],
	)
	open_letter = oa.get_letter(db, 1, registered["id"], owner.id, sender["id"], is_admin=True)
	referral_id = open_letter["referrals"][0]["id"]
	with pytest.raises(ApiError) as stranger:
		ext.cancel_referral(db, 1, referral_id, {}, clerk.id, receiver["id"])
	assert stranger.value.code == "OA_LETTER_FORBIDDEN"
	archived = oa.archive_letter(db, 1, registered["id"], owner.id, sender["id"])
	assert archived["status"] == "archived"
	reopened = ext.unarchive_letter(db, 1, registered["id"], owner.id, sender["id"])
	assert reopened["status"] == "in_circulation"
	assert reopened["archive_folder_id"] is None
	cancelled = ext.cancel_referral(db, 1, referral_id, {"note": "لغو"}, owner.id, sender["id"])
	assert cancelled["referrals"][0]["status"] == "cancelled"
	with pytest.raises(ApiError) as closed:
		ext.cancel_referral(db, 1, referral_id, {}, owner.id, sender["id"])
	assert closed.value.code == "OA_REFERRAL_CLOSED"
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_due_document_stays_when_retention_is_held(_plugin):
	db = _session()
	owner = _user(db, "doc-hold@example.com", "dh")
	_branch, position = _org(db, owner, 1, "dochold")
	db.add(FileStorage(
		id="file-hold",
		original_name="file-hold.txt",
		stored_name="file-hold.txt",
		file_path="/tmp/file-hold.txt",
		file_size=12,
		mime_type="text/plain",
		storage_type="local",
		uploaded_by=owner.id,
		business_id=1,
		module_context="office_automation",
		is_active=True,
		is_temporary=False,
		is_verified=False,
		is_marked_for_deletion=False,
	))
	db.commit()
	created = docs.register_document(
		db, 1, owner.id, position["id"],
		{"title": "سند نگهداری", "confidentiality": "normal", "file_storage_id": "file-hold"},
	)
	row = db.query(OaDocument).filter(OaDocument.id == created["id"]).one()
	row.retain_until = date(2020, 1, 1)
	row.retention_status = "none"
	db.commit()
	before_documents = db.query(OaDocument).count()
	before_files = db.query(FileStorage).count()
	marked = ent.mark_due_retention(db, 1)
	assert marked["documents"] == 1
	assert marked["deleted"] == 0
	assert ent.list_retention_reviews(db, 1)["documents"] == []
	reviews = ent.list_retention_reviews(db, 1, user_id=owner.id)
	assert reviews["documents"][0]["document_id"] == created["id"]
	assert reviews["documents"][0]["title"] == "سند نگهداری"
	assert "search_text" not in reviews["documents"][0]
	held = ent.hold_document_retention(db, 1, owner.id, created["id"])
	assert held["retention_status"] == "held"
	assert held["file_storage_id"] == "file-hold"
	assert held["deleted"] is False
	assert db.query(OaDocument).count() == before_documents
	assert db.query(FileStorage).filter(FileStorage.id == "file-hold").count() == 1
	assert db.query(FileStorage).count() == before_files
	with pytest.raises(ApiError) as again:
		ent.hold_document_retention(db, 1, owner.id, created["id"])
	assert again.value.code == "OA_RETENTION_NOT_DUE"
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_delay_report_limit_skips_hidden_late_referrals(_plugin):
	db = _session()
	owner = _user(db, "delay-owner@example.com", "dy1")
	stranger = _user(db, "delay-stranger@example.com", "dy2")
	unit = oa.create_org_unit(db, 1, {"code": "delay", "name_i18n": {"fa": "تاخیر", "en": "Delay"}}, owner.id)
	sec = ext.create_secretariat(db, 1, {"code": "sec_delay", "name": "محرمانه", "is_confidential": True, "is_default": True}, owner.id)
	owner_pos = oa.create_position(
		db, 1,
		{"code": "p_delay", "org_unit_id": unit["id"], "name_i18n": {"fa": "دبیر", "en": "Clerk"}, "is_secretariat": True, "secretariat_id": sec["id"]},
		owner.id,
	)
	stranger_pos = oa.create_position(
		db, 1, {"code": "p_delay_out", "org_unit_id": unit["id"], "name_i18n": {"fa": "بیرون", "en": "Out"}}, owner.id,
	)
	oa.assign_position_holder(db, 1, {"position_id": owner_pos["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": stranger_pos["id"], "user_id": stranger.id, "is_primary": True}, owner.id)
	visible = oa.create_letter_draft(db, 1, {"subject": "نامه قابل دیدن", "letter_kind": "internal"}, owner.id, owner_pos["id"])
	oa.register_letter(
		db, 1, visible["id"], {"recipients": [{"to_position_id": stranger_pos["id"], "kind": "action"}]}, owner.id, owner_pos["id"],
	)
	visible_ref = db.query(OaReferral).filter(OaReferral.letter_id == visible["id"]).one()
	visible_ref.due_at = date(2020, 6, 1)
	now = datetime.utcnow()
	today = date.today()
	hidden_letters = [
		OaLetter(
			business_id=1,
			letter_kind="internal",
			status="registered",
			subject="نامه پنهان",
			letter_date=today,
			confidentiality="secret",
			origin_position_id=owner_pos["id"],
			created_by_user_id=owner.id,
			sign_status="none",
			retention_status="none",
			qualified_sign_status="none",
			created_at=now,
			updated_at=now,
		)
		for _index in range(201)
	]
	db.add_all(hidden_letters)
	db.flush()
	db.add_all(
		[
			OaReferral(
				business_id=1,
				letter_id=letter.id,
				from_position_id=owner_pos["id"],
				to_position_id=owner_pos["id"],
				from_user_id=owner.id,
				kind="action",
				priority="normal",
				due_at=date(2020, 1, 1),
				status="pending",
				created_at=now,
				updated_at=now,
			)
			for letter in hidden_letters
		]
	)
	db.commit()
	assert ext.delay_report(db, 1)["items"] == []
	found = ext.delay_report(db, 1, user_id=stranger.id, is_admin=False)
	assert [item["subject"] for item in found["items"]] == ["نامه قابل دیدن"]
	admin = ext.delay_report(db, 1, user_id=owner.id, is_admin=True)
	assert admin["items"][0]["subject"] == "نامه پنهان"
	assert admin["total"] == 200
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_cartable_list_keeps_the_subject_and_omits_the_body(_plugin):
	db = _session()
	owner = _user(db, "list-owner@example.com", "lb1")
	clerk = _user(db, "list-clerk@example.com", "lb2")
	_branch, sender = _org(db, owner, 1, "listbody")
	receiver = oa.create_position(
		db, 1,
		{"code": "p_list_in", "org_unit_id": sender["org_unit_id"], "name_i18n": {"fa": "گیرنده", "en": "Inbox"}},
		owner.id,
	)
	oa.assign_position_holder(db, 1, {"position_id": receiver["id"], "user_id": clerk.id, "is_primary": True}, owner.id)
	draft = oa.create_letter_draft(
		db, 1,
		{"subject": "موضوع فهرست", "body": "متن بدنه نباید در فهرست باشد", "letter_kind": "internal"},
		owner.id, sender["id"],
	)
	registered = oa.register_letter(
		db, 1, draft["id"],
		{"recipients": [{"to_position_id": receiver["id"], "kind": "action"}]},
		owner.id, sender["id"],
	)
	stored = db.query(OaLetter).filter(OaLetter.id == registered["id"]).one()
	stored.ai_summary = "خلاصه نباید در فهرست باشد"
	db.commit()
	inbox = oa.list_cartable(db, 1, clerk.id, receiver["id"], folder="inbox")
	assert inbox["items"][0]["subject"] == "موضوع فهرست"
	assert "body" not in inbox["items"][0]
	assert "ai_summary" not in inbox["items"][0]
	sent = oa.list_cartable(db, 1, owner.id, sender["id"], folder="sent")
	assert sent["items"][0]["subject"] == "موضوع فهرست"
	assert "body" not in sent["items"][0]
	opened = oa.get_letter(db, 1, registered["id"], clerk.id, receiver["id"])
	assert opened["body"] == "متن بدنه نباید در فهرست باشد"
	db.close()


class _NoticeCapture:
	calls: list = []

	def __init__(self, db):
		self.db = db

	def send(self, **kwargs):
		_NoticeCapture.calls.append(kwargs)


def test_model_payload_omits_classified_letter_text():
	secret = oa.withhold_classified_text(
		{
			"id": 1,
			"confidentiality": "secret",
			"subject": "موضوع سری",
			"body": "متن سری",
			"tracking_token": "tok",
			"secretariat_number": "SEC-1",
			"paraphs": [{"text": "پاراف سری"}],
			"referrals": [{"instruction": "اقدام سری", "to_position_id": 4}],
			"timeline": [{"summary": "پاراف سری"}],
			"attachments": [{"title": "پیوست سری", "original_name": "قرارداد.pdf", "file_storage_id": "file-1"}],
		}
	)
	assert secret["text_withheld"] is True
	assert secret["subject"] == ""
	assert secret["body"] == ""
	assert secret["paraphs"][0]["text"] == ""
	assert secret["referrals"][0]["instruction"] == ""
	assert secret["referrals"][0]["to_position_id"] == 4
	assert secret["timeline"][0]["summary"] == ""
	assert secret["attachments"][0]["title"] == ""
	assert secret["attachments"][0]["original_name"] == ""
	assert secret["attachments"][0]["file_storage_id"] == "file-1"
	assert secret["secretariat_number"] == "SEC-1"
	assert "tracking_token" not in secret
	linked = oa.withhold_classified_text(
		{
			"confidentiality": "normal",
			"subject": "نامه عادی",
			"links": [{"related_subject": "موضوع سری", "related_number": "SEC-9", "confidentiality": "secret", "related_letter_id": 9}],
		}
	)
	assert linked["subject"] == "نامه عادی"
	assert linked["links"][0]["related_subject"] == ""
	assert linked["links"][0]["related_number"] == "SEC-9"
	assert linked["links"][0]["related_letter_id"] == 9
	normal = oa.withhold_classified_text(
		{"confidentiality": "normal", "subject": "نامه عادی", "body": "متن", "tracking_token": "tok"}
	)
	assert normal["subject"] == "نامه عادی"
	assert normal["body"] == "متن"
	assert "tracking_token" not in normal
	assert "text_withheld" not in normal
	document = oa.withhold_classified_text(
		{"id": 2, "confidentiality": "confidential", "title": "سند سری", "suggestions": [{"suggested_value": "عنوان"}]}
	)
	assert document["title"] == ""
	assert document["suggestions"][0]["suggested_value"] == ""


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_letter_link_hides_a_secret_subject_from_the_other_reader(_plugin):
	db = _session()
	owner = _user(db, "link-owner@example.com", "lk1")
	reader = _user(db, "link-reader@example.com", "lk2")
	unit = oa.create_org_unit(db, 1, {"code": "links", "name_i18n": {"fa": "پیوند", "en": "Links"}}, owner.id)
	sec = ext.create_secretariat(db, 1, {"code": "sec_link", "name": "محرمانه", "is_confidential": True, "is_default": True}, owner.id)
	sender = oa.create_position(
		db, 1,
		{"code": "p_link", "org_unit_id": unit["id"], "name_i18n": {"fa": "دبیر", "en": "Clerk"}, "is_secretariat": True, "secretariat_id": sec["id"]},
		owner.id,
	)
	inbox = oa.create_position(db, 1, {"code": "p_link_in", "org_unit_id": unit["id"], "name_i18n": {"fa": "گیرنده", "en": "Inbox"}}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": sender["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": inbox["id"], "user_id": reader.id, "is_primary": True}, owner.id)
	secret = oa.create_letter_draft(
		db, 1, {"subject": "موضوع سری پیوند", "letter_kind": "internal", "confidentiality": "secret"}, owner.id, sender["id"],
	)
	secret_reg = oa.register_letter(
		db, 1, secret["id"], {"recipients": [{"to_position_id": sender["id"], "kind": "info"}]}, owner.id, sender["id"],
	)
	normal = oa.create_letter_draft(db, 1, {"subject": "نامه عادی پیوند", "letter_kind": "internal"}, owner.id, sender["id"])
	normal_reg = oa.register_letter(
		db, 1, normal["id"], {"recipients": [{"to_position_id": inbox["id"], "kind": "info"}]}, owner.id, sender["id"],
	)
	linked = oa.link_letters(
		db, 1, normal_reg["id"], {"related_letter_id": secret_reg["id"], "link_kind": "related"}, owner.id, sender["id"],
	)
	assert linked["related_letter_id"] == secret_reg["id"]
	with pytest.raises(ApiError) as blocked:
		oa.link_letters(
			db, 1, normal_reg["id"], {"related_letter_id": secret_reg["id"], "link_kind": "related"}, reader.id, inbox["id"],
		)
	assert blocked.value.code == "OA_LETTER_FORBIDDEN"
	visible = oa.get_letter(db, 1, normal_reg["id"], reader.id, inbox["id"])
	assert visible["subject"] == "نامه عادی پیوند"
	assert visible["links"] == []
	assert "موضوع سری پیوند" not in json.dumps(visible, ensure_ascii=False, default=str)
	owner_view = oa.get_letter(db, 1, normal_reg["id"], owner.id, sender["id"])
	assert owner_view["links"][0]["related_subject"] == "موضوع سری پیوند"
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_classified_letter_cannot_become_a_shared_template(_plugin):
	db = _session()
	owner = _user(db, "tpl-owner@example.com", "tp1")
	unit = oa.create_org_unit(db, 1, {"code": "tpls", "name_i18n": {"fa": "قالب", "en": "Templates"}}, owner.id)
	position = oa.create_position(db, 1, {"code": "p_tpl", "org_unit_id": unit["id"], "name_i18n": {"fa": "دبیر", "en": "Clerk"}}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": position["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	secret = oa.create_letter_draft(
		db, 1,
		{"subject": "موضوع سری قالب", "body": "متن سری قالب", "letter_kind": "internal", "confidentiality": "secret"},
		owner.id, position["id"],
	)
	with pytest.raises(ApiError) as from_letter:
		oa.create_letter_template(
			db, 1,
			{"name": "قالب سری", "subject": "موضوع سری قالب", "body": "متن دیگر", "source_letter_id": secret["id"]},
			owner.id,
		)
	assert from_letter.value.code == "OA_CLASSIFIED_EXTERNAL"
	with pytest.raises(ApiError) as copied:
		oa.create_letter_template(db, 1, {"name": "قالب کپی", "body": "متن سری قالب"}, owner.id)
	assert copied.value.code == "OA_CLASSIFIED_EXTERNAL"
	oa.create_letter_draft(
		db, 1,
		{"subject": "موضوع سری بی‌متن", "body": "", "letter_kind": "internal", "confidentiality": "secret"},
		owner.id, position["id"],
	)
	with pytest.raises(ApiError) as titled:
		oa.create_letter_template(db, 1, {"name": "قالب بی‌متن", "subject": "موضوع سری بی‌متن", "body": ""}, owner.id)
	assert titled.value.code == "OA_CLASSIFIED_EXTERNAL"
	shared = oa.create_letter_template(db, 1, {"name": "قالب عادی", "subject": "موضوع عادی", "body": "متن قالب عادی"}, owner.id)
	assert shared["body"] == "متن قالب عادی"
	with pytest.raises(ApiError) as edited:
		oa.update_letter_template(db, 1, shared["id"], {"body": "متن سری قالب"}, owner.id)
	assert edited.value.code == "OA_CLASSIFIED_EXTERNAL"
	listed = oa.list_letter_templates(db, 1)
	assert [item["body"] for item in listed] == ["متن قالب عادی"]
	assert "متن سری قالب" not in json.dumps(listed, ensure_ascii=False)
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_classified_letter_is_not_auto_referred(_plugin):
	db = _session()
	owner = _user(db, "rule-owner@example.com", "ru1")
	clerk = _user(db, "rule-clerk@example.com", "ru2")
	stranger = _user(db, "rule-stranger@example.com", "ru3")
	unit = oa.create_org_unit(db, 1, {"code": "rules", "name_i18n": {"fa": "قواعد", "en": "Rules"}}, owner.id)
	sec = ext.create_secretariat(db, 1, {"code": "sec_rule", "name": "محرمانه", "is_confidential": True, "is_default": True}, owner.id)
	sender = oa.create_position(
		db, 1,
		{"code": "p_rule", "org_unit_id": unit["id"], "name_i18n": {"fa": "دبیر", "en": "Clerk"}, "is_secretariat": True, "secretariat_id": sec["id"]},
		owner.id,
	)
	inbox = oa.create_position(db, 1, {"code": "p_rule_in", "org_unit_id": unit["id"], "name_i18n": {"fa": "کارتابل", "en": "Inbox"}}, owner.id)
	outsider = oa.create_position(db, 1, {"code": "p_rule_out", "org_unit_id": unit["id"], "name_i18n": {"fa": "بیرون", "en": "Outside"}}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": sender["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": inbox["id"], "user_id": clerk.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": outsider["id"], "user_id": stranger.id, "is_primary": True}, owner.id)
	folder = ext.save_archive_folder(db, 1, {"code": "auto_box", "name_i18n": {"fa": "خودکار", "en": "Auto"}}, owner.id)
	ext.save_cartable_rule(
		db, 1,
		{
			"name": "ارجاع خودکار",
			"position_id": inbox["id"],
			"actions": {"mark_seen": True, "auto_archive_folder_id": folder["id"], "auto_refer_to": outsider["id"]},
		},
		owner.id,
	)
	secret = oa.create_letter_draft(
		db, 1,
		{"subject": "نامه سری قاعده", "body": "متن سری قاعده", "letter_kind": "internal", "confidentiality": "secret"},
		owner.id, sender["id"],
	)
	secret_reg = oa.register_letter(
		db, 1, secret["id"], {"recipients": [{"to_position_id": inbox["id"], "kind": "action"}]}, owner.id, sender["id"],
	)
	secret_row = db.query(OaLetter).filter(OaLetter.id == secret_reg["id"]).one()
	assert secret_row.status == "in_circulation"
	assert secret_row.archive_folder_id is None
	seen = db.query(OaReferral).filter(OaReferral.letter_id == secret_reg["id"], OaReferral.to_position_id == inbox["id"]).one()
	assert seen.status == "seen"
	assert db.query(OaReferral).filter(OaReferral.letter_id == secret_reg["id"], OaReferral.to_position_id == outsider["id"]).count() == 0
	with pytest.raises(ApiError) as blocked:
		oa.get_letter(db, 1, secret_reg["id"], stranger.id, outsider["id"])
	assert blocked.value.code == "OA_LETTER_FORBIDDEN"
	normal = oa.create_letter_draft(
		db, 1, {"subject": "نامه عادی قاعده", "body": "متن عادی قاعده", "letter_kind": "internal"}, owner.id, sender["id"],
	)
	normal_reg = oa.register_letter(
		db, 1, normal["id"], {"recipients": [{"to_position_id": inbox["id"], "kind": "action"}]}, owner.id, sender["id"],
	)
	normal_row = db.query(OaLetter).filter(OaLetter.id == normal_reg["id"]).one()
	assert normal_row.status == "archived"
	assert normal_row.archive_folder_id == folder["id"]
	opened = oa.get_letter(db, 1, normal_reg["id"], stranger.id, outsider["id"])
	assert opened["subject"] == "نامه عادی قاعده"
	assert opened["body"] == "متن عادی قاعده"
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_letter_actions_require_view_and_signers_can_open(_plugin):
	from adapters.db.models.office_automation import OaDispatch, OaParaph

	db = _session()
	owner = _user(db, "view-owner@example.com", "vw1")
	clerk = _user(db, "view-clerk@example.com", "vw2")
	stranger = _user(db, "view-stranger@example.com", "vw3")
	unit = oa.create_org_unit(db, 1, {"code": "views", "name_i18n": {"fa": "مشاهده", "en": "View"}}, owner.id)
	sec = ext.create_secretariat(db, 1, {"code": "sec_view", "name": "محرمانه", "is_confidential": True, "is_default": True}, owner.id)
	sender = oa.create_position(
		db, 1,
		{"code": "p_view", "org_unit_id": unit["id"], "name_i18n": {"fa": "دبیر", "en": "Clerk"}, "is_secretariat": True, "secretariat_id": sec["id"]},
		owner.id,
	)
	inbox = oa.create_position(db, 1, {"code": "p_view_in", "org_unit_id": unit["id"], "name_i18n": {"fa": "امضا", "en": "Sign"}}, owner.id)
	outsider = oa.create_position(db, 1, {"code": "p_view_out", "org_unit_id": unit["id"], "name_i18n": {"fa": "بیرون", "en": "Outside"}}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": sender["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": inbox["id"], "user_id": clerk.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": outsider["id"], "user_id": stranger.id, "is_primary": True}, owner.id)
	secret = oa.create_letter_draft(
		db, 1,
		{"subject": "نامه سری اقدام", "body": "متن سری اقدام", "letter_kind": "internal", "confidentiality": "secret"},
		owner.id, sender["id"],
	)
	ext.start_sign_path(db, 1, secret["id"], {"steps": [{"position_id": inbox["id"], "is_required": True}]}, owner.id, sender["id"])
	signer_view = oa.get_letter(db, 1, secret["id"], clerk.id, inbox["id"])
	assert signer_view["subject"] == "نامه سری اقدام"
	assert signer_view["body"] == "متن سری اقدام"
	with pytest.raises(ApiError) as hidden:
		oa.get_letter(db, 1, secret["id"], stranger.id, outsider["id"])
	assert hidden.value.code == "OA_LETTER_FORBIDDEN"
	registered = oa.register_letter(db, 1, secret["id"], {}, owner.id, sender["id"])
	for action in (
		lambda: oa.refer_letter(db, 1, registered["id"], {"to_position_id": outsider["id"]}, stranger.id, outsider["id"]),
		lambda: oa.archive_letter(db, 1, registered["id"], stranger.id, outsider["id"]),
		lambda: oa.add_paraph(db, 1, registered["id"], {"text": "پاراف بیگانه"}, stranger.id, outsider["id"]),
		lambda: ext.dispatch_letter(db, 1, registered["id"], {"to_position_id": outsider["id"]}, stranger.id, outsider["id"]),
		lambda: ext.send_letter_email(db, 1, registered["id"], {"to_email": "out@example.com"}, stranger.id, outsider["id"]),
	):
		with pytest.raises(ApiError) as blocked:
			action()
		assert blocked.value.code == "OA_LETTER_FORBIDDEN"
	row = db.query(OaLetter).filter(OaLetter.id == registered["id"]).one()
	assert row.status == "registered"
	assert row.body == "متن سری اقدام"
	assert db.query(OaReferral).filter(OaReferral.letter_id == registered["id"]).count() == 0
	assert db.query(OaParaph).filter(OaParaph.letter_id == registered["id"]).count() == 0
	assert db.query(OaDispatch).filter(OaDispatch.letter_id == registered["id"]).count() == 0
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_classified_letter_stays_inside_notifications_and_exports(_plugin):
	db = _session()
	owner = _user(db, "quiet-owner@example.com", "q1")
	clerk = _user(db, "quiet-clerk@example.com", "q2")
	unit = oa.create_org_unit(db, 1, {"code": "quiet", "name_i18n": {"fa": "محرمانه", "en": "Quiet"}}, owner.id)
	sec = ext.create_secretariat(
		db, 1, {"code": "sec_quiet", "name": "محرمانه", "is_confidential": True, "is_default": True}, owner.id,
	)
	sender = oa.create_position(
		db, 1,
		{"code": "p_quiet", "org_unit_id": unit["id"], "name_i18n": {"fa": "دبیر", "en": "Clerk"}, "is_secretariat": True, "secretariat_id": sec["id"]},
		owner.id,
	)
	receiver = oa.create_position(
		db, 1, {"code": "p_quiet_in", "org_unit_id": unit["id"], "name_i18n": {"fa": "گیرنده", "en": "Inbox"}}, owner.id,
	)
	oa.assign_position_holder(db, 1, {"position_id": sender["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": receiver["id"], "user_id": clerk.id, "is_primary": True}, owner.id)
	secret = oa.create_letter_draft(
		db, 1,
		{"subject": "موضوع سری", "body": "متن سری", "letter_kind": "internal", "confidentiality": "secret"},
		owner.id, sender["id"],
	)
	normal = oa.create_letter_draft(
		db, 1, {"subject": "نامه عادی", "body": "متن عادی", "letter_kind": "internal"}, owner.id, sender["id"],
	)
	_NoticeCapture.calls = []
	import sys
	import types

	notice = types.ModuleType("app.services.notification_service")
	notice.NotificationService = _NoticeCapture
	previous_notice = sys.modules.get(notice.__name__)
	sys.modules[notice.__name__] = notice
	try:
		_run_classified_notices(db, owner, sender, receiver, clerk, secret, normal)
	finally:
		if previous_notice is None:
			sys.modules.pop(notice.__name__, None)
		else:
			sys.modules[notice.__name__] = previous_notice
		db.close()


def _run_classified_notices(db, owner, sender, receiver, clerk, secret, normal):
	secret_reg = oa.register_letter(
		db, 1, secret["id"],
		{"recipients": [{"to_position_id": receiver["id"], "kind": "action"}]},
		owner.id, sender["id"],
	)
	normal_reg = oa.register_letter(
		db, 1, normal["id"],
		{"recipients": [{"to_position_id": receiver["id"], "kind": "action"}]},
		owner.id, sender["id"],
	)
	ext.dispatch_letter(db, 1, secret_reg["id"], {"to_position_id": receiver["id"]}, owner.id, sender["id"])
	ext._notify_letter_event(db, 1, db.query(OaLetter).filter(OaLetter.id == secret_reg["id"]).one(), "office_automation.letter_followup_due", user_ids=[clerk.id])
	secret_calls = [call for call in _NoticeCapture.calls if call["context"]["letter_id"] == secret_reg["id"]]
	assert len(secret_calls) >= 3
	for call in secret_calls:
		assert call["context"]["subject"] == ""
		assert call["context"]["number"] == ""
		assert call["preferred_channels"] == ["inapp"]
		assert "موضوع سری" not in json.dumps(call, ensure_ascii=False)
		assert "متن سری" not in json.dumps(call, ensure_ascii=False)
	normal_calls = [call for call in _NoticeCapture.calls if call["context"]["letter_id"] == normal_reg["id"]]
	assert any(call["context"]["subject"] == "نامه عادی" and "sms" in call["preferred_channels"] and "email" in call["preferred_channels"] for call in normal_calls)
	with pytest.raises(ApiError) as mailed:
		ext.send_letter_email(db, 1, secret_reg["id"], {"to_email": "out@example.com"}, owner.id, sender["id"])
	assert mailed.value.code == "OA_CLASSIFIED_EXTERNAL"
	with pytest.raises(ApiError) as exported:
		ext.export_ece(db, 1, secret_reg["id"], owner.id, sender["id"])
	assert exported.value.code == "OA_CLASSIFIED_EXTERNAL"
	with pytest.raises(ApiError) as summarized:
		ext.summarize_letter(db, 1, secret_reg["id"], owner.id, sender["id"])
	assert summarized.value.code == "OA_CLASSIFIED_EXTERNAL"
	stored = db.query(OaLetter).filter(OaLetter.id == secret_reg["id"]).one()
	assert not stored.ai_summary
	assert stored.body == "متن سری"
	from adapters.db.models.office_automation import OaEceMessage, OaMailboxMessage
	assert db.query(OaEceMessage).count() == 0
	assert db.query(OaMailboxMessage).count() == 0
	opened = oa.get_letter(db, 1, secret_reg["id"], owner.id, sender["id"])
	assert opened["body"] == "متن سری"
	assert opened["subject"] == "موضوع سری"


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_ece_list_hides_letters_the_reader_cannot_open(_plugin):
	from adapters.db.models.office_automation import OaEceMessage

	db = _session()
	owner = _user(db, "ece-owner@example.com", "ec1")
	reader = _user(db, "ece-reader@example.com", "ec2")
	unit = oa.create_org_unit(db, 1, {"code": "ecebox", "name_i18n": {"fa": "ECE", "en": "ECE"}}, owner.id)
	sec = ext.create_secretariat(db, 1, {"code": "sec_ece", "name": "محرمانه", "is_confidential": True, "is_default": True}, owner.id)
	sender = oa.create_position(
		db, 1,
		{"code": "p_ece", "org_unit_id": unit["id"], "name_i18n": {"fa": "دبیر", "en": "Clerk"}, "is_secretariat": True, "secretariat_id": sec["id"]},
		owner.id,
	)
	inbox = oa.create_position(db, 1, {"code": "p_ece_in", "org_unit_id": unit["id"], "name_i18n": {"fa": "گیرنده", "en": "Inbox"}}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": sender["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": inbox["id"], "user_id": reader.id, "is_primary": True}, owner.id)
	secret = oa.create_letter_draft(
		db, 1, {"subject": "موضوع سری ECE", "body": "متن سری ECE", "letter_kind": "internal", "confidentiality": "secret"}, owner.id, sender["id"],
	)
	secret_reg = oa.register_letter(db, 1, secret["id"], {}, owner.id, sender["id"])
	normal = oa.create_letter_draft(db, 1, {"subject": "نامه عادی ECE", "letter_kind": "internal"}, owner.id, sender["id"])
	normal_reg = oa.register_letter(
		db, 1, normal["id"], {"recipients": [{"to_position_id": inbox["id"], "kind": "info"}]}, owner.id, sender["id"],
	)
	now = datetime.utcnow()
	db.add(OaEceMessage(
		business_id=1, letter_id=normal_reg["id"], direction="out", status="exported",
		receipt_number="رسید عادی", xml_content="متن عادی نباید در فهرست باشد", created_at=now,
	))
	db.commit()
	for index in range(101):
		db.add(OaEceMessage(
			business_id=1, letter_id=secret_reg["id"], direction="out", status="exported",
			receipt_number=f"رسید سری {index}", xml_content="متن سری ECE", created_at=now,
		))
	db.commit()
	assert ext.list_ece_messages(db, 1) == []
	visible = ext.list_ece_messages(db, 1, user_id=reader.id)
	assert [item["receipt_number"] for item in visible] == ["رسید عادی"]
	assert visible[0]["letter_id"] == normal_reg["id"]
	assert "xml_content" not in visible[0]
	dumped = json.dumps(visible, ensure_ascii=False, default=str)
	assert "متن سری ECE" not in dumped
	assert "موضوع سری ECE" not in dumped
	assert "رسید سری" not in dumped
	owner_rows = ext.list_ece_messages(db, 1, user_id=owner.id)
	assert len(owner_rows) == 100
	assert owner_rows[0]["receipt_number"].startswith("رسید سری")
	assert "xml_content" not in owner_rows[0]
	assert "متن سری ECE" not in json.dumps(owner_rows, ensure_ascii=False, default=str)
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_provider_signature_stays_inside_the_letter_the_user_can_see(_plugin):
	from adapters.db.models.oa_enterprise import OaQualifiedSignRequest

	db = _session()
	owner = _user(db, "sig-owner@example.com", "sg1")
	stranger = _user(db, "sig-stranger@example.com", "sg2")
	unit = oa.create_org_unit(db, 1, {"code": "signs", "name_i18n": {"fa": "امضا", "en": "Sign"}}, owner.id)
	sec = ext.create_secretariat(db, 1, {"code": "sec_sig", "name": "محرمانه", "is_confidential": True, "is_default": True}, owner.id)
	sender = oa.create_position(
		db, 1,
		{"code": "p_sig", "org_unit_id": unit["id"], "name_i18n": {"fa": "دبیر", "en": "Clerk"}, "is_secretariat": True, "secretariat_id": sec["id"]},
		owner.id,
	)
	outsider = oa.create_position(db, 1, {"code": "p_sig_out", "org_unit_id": unit["id"], "name_i18n": {"fa": "بیرون", "en": "Out"}}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": sender["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": outsider["id"], "user_id": stranger.id, "is_primary": True}, owner.id)
	provider = ent.create_signature_provider(db, 1, owner.id, {"code": "manual_sig", "name": "دستی"})
	normal = oa.create_letter_draft(db, 1, {"subject": "نامه عادی امضا", "letter_kind": "internal"}, owner.id, sender["id"])
	normal_reg = oa.register_letter(db, 1, normal["id"], {}, owner.id, sender["id"])
	secret = oa.create_letter_draft(
		db, 1, {"subject": "نامه سری امضا", "body": "متن سری امضا", "letter_kind": "internal", "confidentiality": "secret"}, owner.id, sender["id"],
	)
	secret_reg = oa.register_letter(db, 1, secret["id"], {}, owner.id, sender["id"])
	with pytest.raises(ApiError) as blocked:
		ent.request_qualified_signature(db, 1, stranger.id, outsider["id"], normal_reg["id"], provider["id"])
	assert blocked.value.code == "OA_LETTER_FORBIDDEN"
	with pytest.raises(ApiError) as classified:
		ent.request_qualified_signature(db, 1, owner.id, sender["id"], secret_reg["id"], provider["id"])
	assert classified.value.code == "OA_CLASSIFIED_EXTERNAL"
	assert db.query(OaQualifiedSignRequest).count() == 0
	secret_row = db.query(OaLetter).filter(OaLetter.id == secret_reg["id"]).one()
	normal_row = db.query(OaLetter).filter(OaLetter.id == normal_reg["id"]).one()
	assert secret_row.qualified_sign_status in (None, "none")
	assert normal_row.qualified_sign_status in (None, "none")
	assert secret_row.sign_status in (None, "none")
	opened = ent.request_qualified_signature(db, 1, owner.id, sender["id"], normal_reg["id"], provider["id"])
	assert opened["delivered"] is False
	assert opened["sign_status"] in (None, "none")
	assert db.query(OaQualifiedSignRequest).count() == 1
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_registration_cannot_lower_confidentiality(_plugin):
	db = _session()
	owner = _user(db, "rank-owner@example.com", "rk1")
	stranger = _user(db, "rank-stranger@example.com", "rk2")
	unit = oa.create_org_unit(db, 1, {"code": "ranks", "name_i18n": {"fa": "سطح", "en": "Rank"}}, owner.id)
	sec = ext.create_secretariat(db, 1, {"code": "sec_rank", "name": "محرمانه", "is_confidential": True, "is_default": True}, owner.id)
	sender = oa.create_position(
		db, 1,
		{"code": "p_rank", "org_unit_id": unit["id"], "name_i18n": {"fa": "دبیر", "en": "Clerk"}, "is_secretariat": True, "secretariat_id": sec["id"]},
		owner.id,
	)
	outsider = oa.create_position(db, 1, {"code": "p_rank_out", "org_unit_id": unit["id"], "name_i18n": {"fa": "بیرون", "en": "Out"}}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": sender["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, 1, {"position_id": outsider["id"], "user_id": stranger.id, "is_primary": True}, owner.id)
	secret = oa.create_letter_draft(
		db, 1,
		{"subject": "نامه سری ثبت", "body": "متن سری ثبت", "letter_kind": "internal", "confidentiality": "secret"},
		owner.id, sender["id"],
	)
	with pytest.raises(ApiError) as lowered:
		oa.register_letter(
			db, 1, secret["id"], {"confidentiality": "normal", "body": "متن لو رفته"}, owner.id, sender["id"],
		)
	assert lowered.value.code == "OA_CLASSIFIED_EXTERNAL"
	with pytest.raises(ApiError) as stepped:
		oa.register_letter(db, 1, secret["id"], {"confidentiality": "confidential"}, owner.id, sender["id"])
	assert stepped.value.code == "OA_CLASSIFIED_EXTERNAL"
	row = db.query(OaLetter).filter(OaLetter.id == secret["id"]).one()
	assert row.status == "draft"
	assert row.confidentiality == "secret"
	assert row.body == "متن سری ثبت"
	assert row.secretariat_number is None
	with pytest.raises(ApiError) as hidden:
		oa.get_letter(db, 1, secret["id"], stranger.id, outsider["id"])
	assert hidden.value.code == "OA_LETTER_FORBIDDEN"
	registered = oa.register_letter(db, 1, secret["id"], {}, owner.id, sender["id"])
	assert registered["confidentiality"] == "secret"
	assert registered["status"] == "registered"
	assert registered["body"] == "متن سری ثبت"
	other = oa.create_letter_draft(
		db, 1,
		{"subject": "پیش‌نویس قابل کاهش", "body": "متن اولیه", "letter_kind": "internal", "confidentiality": "secret"},
		owner.id, sender["id"],
	)
	edited = oa.update_letter_draft(db, 1, other["id"], {"confidentiality": "normal"}, owner.id, sender["id"])
	assert edited["confidentiality"] == "normal"
	assert edited["status"] == "draft"
	opened = oa.register_letter(db, 1, other["id"], {}, owner.id, sender["id"])
	assert opened["confidentiality"] == "normal"
	assert opened["body"] == "متن اولیه"
	db.close()
