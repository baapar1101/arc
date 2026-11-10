"""پیشنهاد ارجاع و پیش‌نویس فرآیند از متن. هیچ‌کدام ارجاع یا نسخه منتشرشده نمی‌سازند."""
from __future__ import annotations

import re

from sqlalchemy.orm import Session

from adapters.db.models.oa_process import OaProcessVersion
from adapters.db.models.office_automation import OaLetter, OaPosition, OaReferral
from app.core.responses import ApiError
from app.services import oa_process_runtime as proc
from app.services.office_automation_service import _can_view_letter, resolve_acting_position

_STEP = re.compile(r"^(?P<name>.+?)\s*\|\s*(?P<pid>\d+)\s*(?:\|\s*(?P<hours>\d+))?\s*$")


def suggest_referral(db: Session, business_id: int, user_id: int, position_id: int, letter_id: int, *, is_admin: bool = False) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="view")
	letter = db.query(OaLetter).filter(OaLetter.id == letter_id, OaLetter.business_id == business_id).first()
	if letter is None or not _can_view_letter(db, letter, user_id, is_admin):
		raise ApiError("OA_LETTER_FORBIDDEN", "You cannot view this letter.", http_status=403)
	before = db.query(OaReferral).filter(OaReferral.letter_id == letter.id).count()
	suggestions = []
	seen = set()

	def add(target_id: int, reason: str, kind: str) -> None:
		if target_id == position.id or target_id in seen:
			return
		target = db.query(OaPosition).filter(OaPosition.id == target_id, OaPosition.business_id == business_id, OaPosition.is_active.is_(True)).first()
		if target is None:
			return
		seen.add(target_id)
		suggestions.append({"to_position_id": target_id, "kind": kind, "reason": reason})

	open_refs = (
		db.query(OaReferral)
		.filter(
			OaReferral.letter_id == letter.id,
			OaReferral.to_position_id == position.id,
			OaReferral.status.in_(("pending", "seen")),
		)
		.order_by(OaReferral.id.desc())
		.all()
	)
	for ref in open_refs:
		add(ref.from_position_id, "return_to_sender", "return")
	if letter.secretariat_id:
		clerks = (
			db.query(OaPosition)
			.filter(
				OaPosition.business_id == business_id,
				OaPosition.is_active.is_(True),
				OaPosition.is_secretariat.is_(True),
				OaPosition.secretariat_id == letter.secretariat_id,
			)
			.order_by(OaPosition.id)
			.all()
		)
		for clerk in clerks:
			add(clerk.id, "secretariat", "action")
	after = db.query(OaReferral).filter(OaReferral.letter_id == letter.id).count()
	if after != before:
		raise ApiError("OA_REFERRAL_UNEXPECTED", "Suggestion must not create a referral.", http_status=500)
	return {"letter_id": letter.id, "applied": False, "suggestions": suggestions[:8]}


def draft_process_from_text(db: Session, business_id: int, user_id: int, payload: dict, lang: str = "fa") -> dict:
	code = str(payload.get("code") or "").strip()
	name = str(payload.get("name") or "").strip() or code
	text = str(payload.get("text") or "")
	steps = []
	for raw in text.splitlines():
		line = raw.strip()
		if not line or line.startswith("#"):
			continue
		match = _STEP.match(line)
		if match is None:
			raise ApiError("OA_PROCESS_TEXT_INVALID", "Each step must be 'name | position_id'.", http_status=400)
		steps.append(
			{
				"name": match.group("name").strip()[:200],
				"assignee_position_id": int(match.group("pid")),
				"sla_hours": int(match.group("hours")) if match.group("hours") else None,
			}
		)
	if not steps:
		raise ApiError("OA_PROCESS_TEXT_INVALID", "At least one step is required.", http_status=400)
	nodes = [{"id": "start", "type": "start"}]
	edges = []
	previous = "start"
	for index, step in enumerate(steps, start=1):
		node_id = f"task_{index}"
		node = {
			"id": node_id,
			"type": "user_task",
			"name": step["name"],
			"assignee_position_id": step["assignee_position_id"],
			"form": [{"key": "note", "label": step["name"], "type": "text", "required": False}],
		}
		if step["sla_hours"]:
			node["sla_hours"] = step["sla_hours"]
		nodes.append(node)
		edges.append({"from": previous, "to": node_id})
		previous = node_id
	nodes.append({"id": "end", "type": "end"})
	edges.append({"from": previous, "to": "end"})
	saved = proc.save_process_draft(
		db,
		business_id,
		user_id,
		{"code": code, "name_i18n": {"fa": name, "en": name}, "graph": {"nodes": nodes, "edges": edges}},
		lang=lang,
	)
	versions = db.query(OaProcessVersion).filter(OaProcessVersion.definition_id == saved["id"]).count()
	return {"definition": saved, "published_versions": versions, "step_count": len(steps)}
