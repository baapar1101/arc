"""نسخه قفل‌شده، درگاه، موازی، تایمر و SLA فرآیند انسانی."""
from __future__ import annotations

import copy
from datetime import datetime, timedelta
from unittest.mock import patch

import pytest

from adapters.db.models.oa_process import OaProcessInstance, OaProcessTask, OaProcessToken, OaProcessVersion
from app.core.responses import ApiError
from app.services import oa_process_runtime as proc
from app.services import office_automation_service as oa
from tests.test_office_automation_plugin import _session, _user


def _org(db):
	owner = _user(db, "proc-owner@example.com", "p1")
	clerk = _user(db, "proc-clerk@example.com", "p2")
	other = _user(db, "proc-other@example.com", "p3")
	bid = 1
	unit = oa.create_org_unit(db, bid, {"code": "flow", "name_i18n": {"fa": "جریان", "en": "Flow"}}, owner.id)
	src = oa.create_position(db, bid, {"code": "lead", "org_unit_id": unit["id"], "name_i18n": {"fa": "مسئول", "en": "Lead"}, "is_secretariat": True}, owner.id)
	worker = oa.create_position(db, bid, {"code": "work", "org_unit_id": unit["id"], "name_i18n": {"fa": "کارشناس", "en": "Worker"}}, owner.id)
	boss = oa.create_position(db, bid, {"code": "boss", "org_unit_id": unit["id"], "name_i18n": {"fa": "مدیر", "en": "Boss"}}, owner.id)
	oa.assign_position_holder(db, bid, {"position_id": src["id"], "user_id": owner.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, bid, {"position_id": worker["id"], "user_id": clerk.id, "is_primary": True}, owner.id)
	oa.assign_position_holder(db, bid, {"position_id": boss["id"], "user_id": other.id, "is_primary": True}, owner.id)
	return owner, clerk, other, bid, src, worker, boss


def _approval_graph(worker_id, boss_id):
	return {
		"nodes": [
			{"id": "start", "type": "start"},
			{
				"id": "review",
				"type": "user_task",
				"name": "بررسی نسخه یک",
				"assignee_position_id": worker_id,
				"sla_hours": 4,
				"escalate_position_id": boss_id,
				"form": [{"key": "decision", "label": "تصمیم", "type": "text", "required": True}],
			},
			{"id": "gate", "type": "exclusive", "field": "decision"},
			{"id": "end_yes", "type": "end"},
			{"id": "end_no", "type": "end"},
		],
		"edges": [
			{"from": "start", "to": "review"},
			{"from": "review", "to": "gate"},
			{"from": "gate", "to": "end_yes", "when": "approve"},
			{"from": "gate", "to": "end_no", "default": True},
		],
	}


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_process_instance_stays_on_published_snapshot(_plugin):
	db = _session()
	owner, clerk, _other, bid, src, worker, boss = _org(db)
	draft = proc.save_process_draft(db, bid, owner.id, {"code": "approval", "name": "تصویب", "graph": _approval_graph(worker["id"], boss["id"])})
	version = proc.publish_process(db, bid, owner.id, draft["id"])
	assert version["version_no"] == 1
	started = proc.start_process(db, bid, owner.id, src["id"], version["id"])
	assert started["status"] == "running"
	assert started["tasks"][0]["name"] == "بررسی نسخه یک"
	row = db.query(OaProcessVersion).filter(OaProcessVersion.id == version["id"]).one()
	mutated = copy.deepcopy(row.graph)
	mutated["nodes"][1]["name"] = "نسخه عوض‌شده"
	mutated["nodes"][1]["assignee_position_id"] = boss["id"]
	row.graph = mutated
	db.commit()
	proc.save_process_draft(db, bid, owner.id, {"code": "approval", "name": "تصویب", "graph": _approval_graph(boss["id"], worker["id"])})
	second = proc.publish_process(db, bid, owner.id, draft["id"])
	assert second["version_no"] == 2
	instance = db.query(OaProcessInstance).filter(OaProcessInstance.id == started["id"]).one()
	assert instance.version_id == version["id"]
	assert instance.graph_snapshot["nodes"][1]["name"] == "بررسی نسخه یک"
	with pytest.raises(ApiError) as forbidden:
		proc.complete_process_task(db, bid, owner.id, src["id"], started["tasks"][0]["id"], {"decision": "approve"})
	assert forbidden.value.code == "OA_PROCESS_TASK_FORBIDDEN"
	with pytest.raises(ApiError) as missing:
		proc.complete_process_task(db, bid, clerk.id, worker["id"], started["tasks"][0]["id"], {})
	assert missing.value.code == "OA_PROCESS_FORM_REQUIRED"
	done = proc.complete_process_task(db, bid, clerk.id, worker["id"], started["tasks"][0]["id"], {"decision": "approve"})
	assert done["status"] == "completed"
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_parallel_join_waits_and_sla_escalates_once(_plugin):
	db = _session()
	owner, clerk, other, bid, src, worker, boss = _org(db)
	graph = {
		"nodes": [
			{"id": "start", "type": "start"},
			{"id": "split", "type": "parallel_split"},
			{"id": "a", "type": "user_task", "name": "الف", "assignee_position_id": worker["id"], "sla_hours": 1, "escalate_position_id": boss["id"], "form": []},
			{"id": "b", "type": "user_task", "name": "ب", "assignee_position_id": src["id"], "form": []},
			{"id": "join", "type": "parallel_join"},
			{"id": "end", "type": "end"},
		],
		"edges": [
			{"from": "start", "to": "split"},
			{"from": "split", "to": "a"},
			{"from": "split", "to": "b"},
			{"from": "a", "to": "join"},
			{"from": "b", "to": "join"},
			{"from": "join", "to": "end"},
		],
	}
	draft = proc.save_process_draft(db, bid, owner.id, {"code": "parallel", "name": "موازی", "graph": graph})
	version = proc.publish_process(db, bid, owner.id, draft["id"])
	started = proc.start_process(db, bid, owner.id, src["id"], version["id"])
	assert len(started["tasks"]) == 2
	first = proc.complete_process_task(db, bid, clerk.id, worker["id"], next(t["id"] for t in started["tasks"] if t["name"] == "الف"), {})
	assert first["status"] == "running"
	task = db.query(OaProcessTask).filter(OaProcessTask.name == "ب").one()
	second = proc.complete_process_task(db, bid, owner.id, src["id"], task.id, {})
	assert second["status"] == "completed"

	late = db.query(OaProcessTask).filter(OaProcessTask.name == "الف").one()
	late.status = "open"
	late.due_at = datetime.utcnow() - timedelta(hours=2)
	late.escalated_at = None
	late.assignee_position_id = worker["id"]
	db.commit()
	moved = proc.escalate_overdue_tasks(db, bid)
	assert moved["escalated"] == 1
	again = proc.escalate_overdue_tasks(db, bid)
	assert again["escalated"] == 0
	assert db.query(OaProcessTask).filter(OaProcessTask.id == late.id).one().assignee_position_id == boss["id"]
	assert proc.list_my_process_tasks(db, bid, other.id, boss["id"])
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_timer_and_subprocess_resume_parent(_plugin):
	db = _session()
	owner, _clerk, _other, bid, src, worker, _boss = _org(db)
	child_graph = {
		"nodes": [{"id": "start", "type": "start"}, {"id": "end", "type": "end"}],
		"edges": [{"from": "start", "to": "end"}],
	}
	child_draft = proc.save_process_draft(db, bid, owner.id, {"code": "child", "name": "فرزند", "graph": child_graph})
	child = proc.publish_process(db, bid, owner.id, child_draft["id"])
	parent_graph = {
		"nodes": [
			{"id": "start", "type": "start"},
			{"id": "wait", "type": "timer", "hours": 2},
			{"id": "sub", "type": "subprocess", "version_id": child["id"]},
			{"id": "end", "type": "end"},
		],
		"edges": [
			{"from": "start", "to": "wait"},
			{"from": "wait", "to": "sub"},
			{"from": "sub", "to": "end"},
		],
	}
	parent_draft = proc.save_process_draft(db, bid, owner.id, {"code": "parent", "name": "والد", "graph": parent_graph})
	parent = proc.publish_process(db, bid, owner.id, parent_draft["id"])
	started = proc.start_process(db, bid, owner.id, src["id"], parent["id"])
	assert started["status"] == "running"
	token = db.query(OaProcessToken).filter(OaProcessToken.instance_id == started["id"], OaProcessToken.wait_kind == "timer").one()
	token.resume_at = datetime.utcnow() - timedelta(minutes=1)
	db.commit()
	assert proc.advance_due_timers(db, bid)["advanced"] == 1
	instance = db.query(OaProcessInstance).filter(OaProcessInstance.id == started["id"]).one()
	assert instance.status == "completed"
	assert db.query(OaProcessInstance).filter(OaProcessInstance.parent_instance_id == instance.id).count() == 1
	db.close()


@patch("app.services.office_automation_service.check_office_automation_plugin_active", return_value=True)
def test_designer_layout_survives_publish_and_exclusive_needs_one_default(_plugin):
	db = _session()
	owner, _clerk, _other, bid, src, worker, boss = _org(db)
	graph = _approval_graph(worker["id"], boss["id"])
	graph["nodes"][0]["x"] = 48
	graph["nodes"][0]["y"] = 96
	draft = proc.save_process_draft(db, bid, owner.id, {"code": "designed", "name": "طراحی‌شده", "graph": graph})
	listed = proc.list_process_definitions(db, bid)
	assert listed[0]["id"] == draft["id"]
	assert listed[0]["graph"]["nodes"][0]["x"] == 48
	version = proc.publish_process(db, bid, owner.id, draft["id"])
	started = proc.start_process(db, bid, owner.id, src["id"], version["id"])
	instance = db.query(OaProcessInstance).filter(OaProcessInstance.id == started["id"]).one()
	assert instance.graph_snapshot["nodes"][0]["x"] == 48
	broken = _approval_graph(worker["id"], boss["id"])
	broken["edges"] = [edge for edge in broken["edges"] if not edge.get("default")]
	broken["edges"].append({"from": "gate", "to": "end_no", "when": "reject"})
	with pytest.raises(ApiError) as missing_default:
		proc.save_process_draft(db, bid, owner.id, {"code": "designed", "name": "طراحی‌شده", "graph": broken})
	assert missing_default.value.code == "OA_PROCESS_GRAPH_INVALID"
	db.close()
