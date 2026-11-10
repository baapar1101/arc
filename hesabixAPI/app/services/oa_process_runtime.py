"""Runtime فرآیند انسانی. موتور ورک‌فلو رویدادی را صدا نمی‌زند و نسخه‌اش را عوض نمی‌کند."""
from __future__ import annotations

import copy
import re
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.oa_process import (
	OaProcessDefinition,
	OaProcessInstance,
	OaProcessTask,
	OaProcessToken,
	OaProcessVersion,
)
from adapters.db.models.office_automation import OaPosition
from app.core.responses import ApiError
from app.services.office_automation_service import resolve_acting_position, resolve_i18n

_CODE_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9_]{0,63}$")
_NODE_TYPES = frozenset({"start", "user_task", "exclusive", "parallel_split", "parallel_join", "timer", "subprocess", "end"})
_AUTO_DEPTH = 50
_SUBPROCESS_DEPTH = 5


def _now() -> datetime:
	return datetime.utcnow()


def _plugin(db: Session, business_id: int) -> None:
	from app.services import office_automation_service as oa

	oa._ensure_plugin(db, business_id)


def _nodes(graph: dict) -> Dict[str, dict]:
	out: Dict[str, dict] = {}
	for node in graph.get("nodes") or []:
		if isinstance(node, dict) and node.get("id"):
			out[str(node["id"])] = node
	return out


def _edges(graph: dict) -> List[dict]:
	return [edge for edge in (graph.get("edges") or []) if isinstance(edge, dict)]


def _outgoing(graph: dict, node_id: str) -> List[dict]:
	return [edge for edge in _edges(graph) if str(edge.get("from")) == node_id]


def _incoming(graph: dict, node_id: str) -> List[dict]:
	return [edge for edge in _edges(graph) if str(edge.get("to")) == node_id]


def _position(db: Session, business_id: int, position_id: int) -> OaPosition:
	row = (
		db.query(OaPosition)
		.filter(OaPosition.id == position_id, OaPosition.business_id == business_id, OaPosition.is_active.is_(True))
		.first()
	)
	if row is None:
		raise ApiError("OA_POSITION_NOT_FOUND", "Position was not found.", http_status=404)
	return row


def validate_process_graph(db: Session, business_id: int, graph: dict) -> dict:
	if not isinstance(graph, dict):
		raise ApiError("OA_PROCESS_GRAPH_INVALID", "Process graph must be an object.", http_status=400)
	nodes = _nodes(graph)
	if not nodes:
		raise ApiError("OA_PROCESS_GRAPH_INVALID", "Process graph has no nodes.", http_status=400)
	starts = [node for node in nodes.values() if node.get("type") == "start"]
	ends = [node for node in nodes.values() if node.get("type") == "end"]
	if len(starts) != 1 or not ends:
		raise ApiError("OA_PROCESS_GRAPH_INVALID", "A process needs one start and at least one end.", http_status=400)
	for node_id, node in nodes.items():
		kind = str(node.get("type") or "")
		if kind not in _NODE_TYPES:
			raise ApiError("OA_PROCESS_GRAPH_INVALID", f"Unsupported node type: {kind}", http_status=400)
		outgoing = _outgoing(graph, node_id)
		if kind == "end" and outgoing:
			raise ApiError("OA_PROCESS_GRAPH_INVALID", "End nodes cannot have outgoing edges.", http_status=400)
		if kind != "end" and not outgoing:
			raise ApiError("OA_PROCESS_GRAPH_INVALID", f"Node {node_id} has no outgoing edge.", http_status=400)
		if kind in {"start", "user_task", "timer", "subprocess", "parallel_join"} and len(outgoing) != 1:
			raise ApiError("OA_PROCESS_GRAPH_INVALID", f"Node {node_id} must have one outgoing edge.", http_status=400)
		if kind == "parallel_split" and len(outgoing) < 2:
			raise ApiError("OA_PROCESS_GRAPH_INVALID", "Parallel split needs at least two outgoing edges.", http_status=400)
		if kind == "user_task":
			_position(db, business_id, int(node.get("assignee_position_id") or 0))
			if node.get("escalate_position_id"):
				_position(db, business_id, int(node["escalate_position_id"]))
		if kind == "exclusive":
			if not str(node.get("field") or "").strip():
				raise ApiError("OA_PROCESS_GRAPH_INVALID", "Exclusive gateway needs a field.", http_status=400)
			defaults = [edge for edge in outgoing if edge.get("default") is True]
			if len(defaults) != 1:
				raise ApiError("OA_PROCESS_GRAPH_INVALID", "Exclusive gateway needs exactly one default edge.", http_status=400)
			for edge in outgoing:
				if edge.get("default") is True:
					continue
				if not str(edge.get("when") or "").strip():
					raise ApiError("OA_PROCESS_GRAPH_INVALID", "Exclusive edge needs a when value.", http_status=400)
		if kind == "timer" and int(node.get("hours") or 0) <= 0:
			raise ApiError("OA_PROCESS_GRAPH_INVALID", "Timer hours must be positive.", http_status=400)
		if kind == "subprocess":
			version = _version(db, business_id, int(node.get("version_id") or 0))
			if version.business_id != business_id:
				raise ApiError("OA_PROCESS_VERSION_NOT_FOUND", "Subprocess version was not found.", http_status=404)
		for edge in outgoing:
			if str(edge.get("to")) not in nodes:
				raise ApiError("OA_PROCESS_GRAPH_INVALID", "An edge points at a missing node.", http_status=400)
	return graph


def _version(db: Session, business_id: int, version_id: int) -> OaProcessVersion:
	row = (
		db.query(OaProcessVersion)
		.filter(OaProcessVersion.id == version_id, OaProcessVersion.business_id == business_id)
		.first()
	)
	if row is None:
		raise ApiError("OA_PROCESS_VERSION_NOT_FOUND", "Process version was not found.", http_status=404)
	return row


def _definition_dict(row: OaProcessDefinition, lang: str) -> dict:
	return {
		"id": row.id,
		"code": row.code,
		"name": resolve_i18n(row.name_i18n, lang),
		"graph": row.graph,
		"updated_at": row.updated_at,
	}


def _version_dict(row: OaProcessVersion, lang: str, definition: Optional[OaProcessDefinition] = None) -> dict:
	return {
		"id": row.id,
		"definition_id": row.definition_id,
		"version_no": row.version_no,
		"name": resolve_i18n(definition.name_i18n, lang) if definition is not None else None,
		"published_at": row.published_at,
	}


def save_process_draft(db: Session, business_id: int, user_id: int, payload: dict, lang: str = "fa") -> dict:
	_plugin(db, business_id)
	code = str(payload.get("code") or "").strip()
	if not _CODE_RE.match(code):
		raise ApiError("OA_PROCESS_CODE_INVALID", "Process code is invalid.", http_status=400)
	name = payload.get("name_i18n") if isinstance(payload.get("name_i18n"), dict) else {"fa": str(payload.get("name") or code)}
	graph = validate_process_graph(db, business_id, payload.get("graph") or {})
	row = (
		db.query(OaProcessDefinition)
		.filter(OaProcessDefinition.business_id == business_id, OaProcessDefinition.code == code)
		.first()
	)
	if row is None:
		row = OaProcessDefinition(
			business_id=business_id,
			code=code,
			name_i18n=name,
			graph=copy.deepcopy(graph),
			created_by_user_id=user_id,
			created_at=_now(),
			updated_at=_now(),
		)
		db.add(row)
	else:
		row.name_i18n = name
		row.graph = copy.deepcopy(graph)
		row.updated_at = _now()
	db.commit()
	db.refresh(row)
	return _definition_dict(row, lang)


def publish_process(db: Session, business_id: int, user_id: int, definition_id: int, lang: str = "fa") -> dict:
	_plugin(db, business_id)
	row = (
		db.query(OaProcessDefinition)
		.filter(OaProcessDefinition.id == definition_id, OaProcessDefinition.business_id == business_id)
		.first()
	)
	if row is None:
		raise ApiError("OA_PROCESS_NOT_FOUND", "Process definition was not found.", http_status=404)
	graph = validate_process_graph(db, business_id, copy.deepcopy(row.graph))
	current = (
		db.query(OaProcessVersion.version_no)
		.filter(OaProcessVersion.definition_id == row.id)
		.order_by(OaProcessVersion.version_no.desc())
		.first()
	)
	version = OaProcessVersion(
		business_id=business_id,
		definition_id=row.id,
		version_no=(current[0] if current else 0) + 1,
		graph=graph,
		published_by_user_id=user_id,
		published_at=_now(),
	)
	db.add(version)
	db.commit()
	db.refresh(version)
	return _version_dict(version, lang, row)


def publish_linear_process(db: Session, business_id: int, user_id: int, payload: dict, lang: str = "fa") -> dict:
	assignee = int(payload.get("assignee_position_id") or 0)
	name = str(payload.get("name") or "").strip() or "فرآیند"
	code = str(payload.get("code") or "").strip() or f"linear_{assignee}_{int(_now().timestamp())}"
	label = str(payload.get("form_label") or "").strip()
	form = [{"key": "note", "label": label or "یادداشت", "type": "text", "required": bool(payload.get("form_required", True))}]
	graph = {
		"nodes": [
			{"id": "start", "type": "start"},
			{
				"id": "task",
				"type": "user_task",
				"name": name,
				"assignee_position_id": assignee,
				"sla_hours": int(payload.get("sla_hours") or 0) or None,
				"form": form,
			},
			{"id": "end", "type": "end"},
		],
		"edges": [
			{"from": "start", "to": "task"},
			{"from": "task", "to": "end"},
		],
	}
	saved = save_process_draft(
		db, business_id, user_id, {"code": code, "name_i18n": {"fa": name, "en": name}, "graph": graph}, lang=lang,
	)
	return publish_process(db, business_id, user_id, int(saved["id"]), lang=lang)


def list_process_definitions(db: Session, business_id: int, lang: str = "fa") -> List[dict]:
	_plugin(db, business_id)
	rows = (
		db.query(OaProcessDefinition)
		.filter(OaProcessDefinition.business_id == business_id)
		.order_by(OaProcessDefinition.updated_at.desc(), OaProcessDefinition.id.desc())
		.all()
	)
	return [_definition_dict(row, lang) for row in rows]


def list_process_versions(db: Session, business_id: int, lang: str = "fa") -> List[dict]:
	_plugin(db, business_id)
	rows = (
		db.query(OaProcessVersion, OaProcessDefinition)
		.join(OaProcessDefinition, OaProcessDefinition.id == OaProcessVersion.definition_id)
		.filter(OaProcessVersion.business_id == business_id)
		.order_by(OaProcessVersion.published_at.desc())
		.all()
	)
	return [_version_dict(version, lang, definition) for version, definition in rows]


def _instance_dict(row: OaProcessInstance) -> dict:
	return {
		"id": row.id,
		"version_id": row.version_id,
		"status": row.status,
		"started_at": row.started_at,
		"completed_at": row.completed_at,
	}


def _task_dict(row: OaProcessTask) -> dict:
	return {
		"id": row.id,
		"instance_id": row.instance_id,
		"node_id": row.node_id,
		"name": row.name,
		"assignee_position_id": row.assignee_position_id,
		"status": row.status,
		"form": row.form_schema or [],
		"due_at": row.due_at,
		"escalated_at": row.escalated_at,
		"created_at": row.created_at,
	}


def start_process(
	db: Session,
	business_id: int,
	user_id: int,
	position_id: int,
	version_id: int,
	variables: Optional[dict] = None,
	*,
	lang: str = "fa",
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="refer")
	version = _version(db, business_id, version_id)
	instance = _begin_instance(
		db,
		business_id=business_id,
		version=version,
		variables=variables or {},
		user_id=user_id,
		position_id=position.id,
		depth=0,
	)
	db.commit()
	db.refresh(instance)
	return {**_instance_dict(instance), "tasks": _open_tasks(db, instance.id)}


def _begin_instance(
	db: Session,
	*,
	business_id: int,
	version: OaProcessVersion,
	variables: dict,
	user_id: Optional[int],
	position_id: Optional[int],
	depth: int,
	parent_instance_id: Optional[int] = None,
) -> OaProcessInstance:
	if depth > _SUBPROCESS_DEPTH:
		raise ApiError("OA_PROCESS_SUBPROCESS_DEPTH", "Subprocess nesting is too deep.", http_status=400)
	if not isinstance(variables, dict):
		raise ApiError("OA_PROCESS_VARIABLES_INVALID", "Process variables must be an object.", http_status=400)
	snapshot = copy.deepcopy(version.graph)
	instance = OaProcessInstance(
		business_id=business_id,
		version_id=version.id,
		graph_snapshot=snapshot,
		status="running",
		variables=copy.deepcopy(variables),
		started_by_user_id=user_id,
		started_by_position_id=position_id,
		parent_instance_id=parent_instance_id,
		started_at=_now(),
	)
	db.add(instance)
	db.flush()
	start = next(node for node in _nodes(snapshot).values() if node.get("type") == "start")
	_activate(db, instance, str(start["id"]), depth=0, subprocess_depth=depth)
	return instance


def _activate(db: Session, instance: OaProcessInstance, node_id: str, *, depth: int, subprocess_depth: int) -> None:
	if depth > _AUTO_DEPTH:
		raise ApiError("OA_PROCESS_LOOP", "Automatic process path is too long.", http_status=400)
	if instance.status != "running":
		return
	graph = instance.graph_snapshot
	node = _nodes(graph).get(node_id)
	if node is None:
		raise ApiError("OA_PROCESS_GRAPH_INVALID", "Process snapshot is missing a node.", http_status=400)
	kind = str(node.get("type"))
	if kind in {"start", "exclusive"}:
		_activate(db, instance, _route(instance, node), depth=depth + 1, subprocess_depth=subprocess_depth)
		return
	if kind == "parallel_split":
		for edge in _outgoing(graph, node_id):
			_activate(db, instance, str(edge["to"]), depth=depth + 1, subprocess_depth=subprocess_depth)
		return
	if kind == "user_task":
		_open_task(db, instance, node)
		return
	if kind == "timer":
		_open_wait(db, instance, node, wait_kind="timer", resume_at=_now() + timedelta(hours=int(node["hours"])))
		return
	if kind == "subprocess":
		_open_subprocess(db, instance, node, subprocess_depth)
		return
	if kind == "parallel_join":
		_open_wait(db, instance, node, wait_kind="join")
		_maybe_join(db, instance, node, depth=depth, subprocess_depth=subprocess_depth)
		return
	if kind == "end":
		_mark_token(db, instance, node_id, "done", None)
		_finish_if_idle(db, instance, depth=depth, subprocess_depth=subprocess_depth)
		return
	raise ApiError("OA_PROCESS_GRAPH_INVALID", f"Unsupported node type: {kind}", http_status=400)


def _route(instance: OaProcessInstance, node: dict) -> str:
	graph = instance.graph_snapshot
	outgoing = _outgoing(graph, str(node["id"]))
	if node.get("type") == "start":
		return str(outgoing[0]["to"])
	value = str((instance.variables or {}).get(str(node.get("field") or ""), ""))
	for edge in outgoing:
		if edge.get("default"):
			continue
		if str(edge.get("when", "")) == value:
			return str(edge["to"])
	for edge in outgoing:
		if edge.get("default"):
			return str(edge["to"])
	raise ApiError("OA_PROCESS_GATEWAY_STUCK", "Exclusive gateway has no matching path.", http_status=400)


def _mark_token(db: Session, instance: OaProcessInstance, node_id: str, status: str, wait_kind: Optional[str], **extra) -> OaProcessToken:
	token = OaProcessToken(
		business_id=instance.business_id,
		instance_id=instance.id,
		node_id=node_id,
		status=status,
		wait_kind=wait_kind,
		created_at=_now(),
		**extra,
	)
	db.add(token)
	db.flush()
	return token


def _open_wait(db: Session, instance: OaProcessInstance, node: dict, *, wait_kind: str, resume_at: Optional[datetime] = None) -> OaProcessToken:
	return _mark_token(db, instance, str(node["id"]), "waiting", wait_kind, resume_at=resume_at)


def _open_task(db: Session, instance: OaProcessInstance, node: dict) -> OaProcessTask:
	token = _open_wait(db, instance, node, wait_kind="task")
	hours = int(node.get("sla_hours") or 0)
	task = OaProcessTask(
		business_id=instance.business_id,
		instance_id=instance.id,
		token_id=token.id,
		node_id=str(node["id"]),
		name=str(node.get("name") or node["id"])[:200],
		assignee_position_id=int(node["assignee_position_id"]),
		status="open",
		form_schema=list(node.get("form") or []),
		due_at=_now() + timedelta(hours=hours) if hours > 0 else None,
		created_at=_now(),
	)
	db.add(task)
	db.flush()
	return task


def _open_subprocess(db: Session, instance: OaProcessInstance, node: dict, subprocess_depth: int) -> None:
	version = _version(db, instance.business_id, int(node["version_id"]))
	child = _begin_instance(
		db,
		business_id=instance.business_id,
		version=version,
		variables=copy.deepcopy(instance.variables or {}),
		user_id=instance.started_by_user_id,
		position_id=instance.started_by_position_id,
		depth=subprocess_depth + 1,
		parent_instance_id=instance.id,
	)
	if child.status == "completed":
		_activate(db, instance, str(_outgoing(instance.graph_snapshot, str(node["id"]))[0]["to"]), depth=1, subprocess_depth=subprocess_depth)
		return
	token = _open_wait(db, instance, node, wait_kind="subprocess")
	token.child_instance_id = child.id
	db.flush()


def _maybe_join(db: Session, instance: OaProcessInstance, node: dict, *, depth: int, subprocess_depth: int) -> None:
	needed = len(_incoming(instance.graph_snapshot, str(node["id"])))
	waiting = (
		db.query(OaProcessToken)
		.filter(
			OaProcessToken.instance_id == instance.id,
			OaProcessToken.node_id == str(node["id"]),
			OaProcessToken.status == "waiting",
			OaProcessToken.wait_kind == "join",
		)
		.all()
	)
	if needed < 1 or len(waiting) < needed:
		return
	for token in waiting:
		token.status = "done"
	nxt = str(_outgoing(instance.graph_snapshot, str(node["id"]))[0]["to"])
	_activate(db, instance, nxt, depth=depth + 1, subprocess_depth=subprocess_depth)


def _finish_if_idle(db: Session, instance: OaProcessInstance, *, depth: int, subprocess_depth: int) -> None:
	waiting = (
		db.query(OaProcessToken)
		.filter(OaProcessToken.instance_id == instance.id, OaProcessToken.status == "waiting")
		.count()
	)
	if waiting:
		return
	instance.status = "completed"
	instance.completed_at = _now()
	db.flush()
	parents = (
		db.query(OaProcessToken)
		.filter(OaProcessToken.child_instance_id == instance.id, OaProcessToken.status == "waiting")
		.all()
	)
	for token in parents:
		token.status = "done"
		parent = db.query(OaProcessInstance).filter(OaProcessInstance.id == token.instance_id).one()
		nxt = str(_outgoing(parent.graph_snapshot, token.node_id)[0]["to"])
		_activate(db, parent, nxt, depth=depth + 1, subprocess_depth=subprocess_depth)


def _open_tasks(db: Session, instance_id: int) -> List[dict]:
	rows = (
		db.query(OaProcessTask)
		.filter(OaProcessTask.instance_id == instance_id, OaProcessTask.status == "open")
		.order_by(OaProcessTask.id)
		.all()
	)
	return [_task_dict(row) for row in rows]


def list_my_process_tasks(db: Session, business_id: int, user_id: int, position_id: int) -> List[dict]:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="view")
	rows = (
		db.query(OaProcessTask)
		.filter(
			OaProcessTask.business_id == business_id,
			OaProcessTask.assignee_position_id == position.id,
			OaProcessTask.status == "open",
		)
		.order_by(OaProcessTask.due_at.is_(None), OaProcessTask.due_at, OaProcessTask.id)
		.all()
	)
	return [_task_dict(row) for row in rows]


def complete_process_task(
	db: Session,
	business_id: int,
	user_id: int,
	position_id: int,
	task_id: int,
	form: Optional[dict] = None,
) -> dict:
	position, _kind = resolve_acting_position(db, business_id, user_id, position_id, required_scope="refer")
	task = (
		db.query(OaProcessTask)
		.filter(OaProcessTask.id == task_id, OaProcessTask.business_id == business_id)
		.first()
	)
	if task is None:
		raise ApiError("OA_PROCESS_TASK_NOT_FOUND", "Process task was not found.", http_status=404)
	if task.status != "open":
		raise ApiError("OA_PROCESS_TASK_CLOSED", "Process task is already closed.", http_status=400)
	if task.assignee_position_id != position.id:
		raise ApiError("OA_PROCESS_TASK_FORBIDDEN", "This task belongs to another position.", http_status=403)
	payload = form or {}
	if not isinstance(payload, dict):
		raise ApiError("OA_PROCESS_FORM_INVALID", "Form data must be an object.", http_status=400)
	for field in task.form_schema or []:
		if field.get("required") and not str(payload.get(field.get("key")) or "").strip():
			raise ApiError("OA_PROCESS_FORM_REQUIRED", "A required form field is empty.", http_status=400)
	instance = db.query(OaProcessInstance).filter(OaProcessInstance.id == task.instance_id).one()
	merged = dict(instance.variables or {})
	merged.update({str(k): v for k, v in payload.items()})
	instance.variables = merged
	task.form_data = payload
	task.status = "done"
	task.completed_by_user_id = user_id
	task.completed_at = _now()
	token = db.query(OaProcessToken).filter(OaProcessToken.id == task.token_id).one()
	token.status = "done"
	nxt = str(_outgoing(instance.graph_snapshot, task.node_id)[0]["to"])
	_activate(db, instance, nxt, depth=0, subprocess_depth=0)
	db.commit()
	db.refresh(instance)
	return {**_instance_dict(instance), "tasks": _open_tasks(db, instance.id)}


def advance_due_timers(db: Session, business_id: Optional[int] = None) -> dict:
	now = _now()
	query = db.query(OaProcessToken).filter(
		OaProcessToken.status == "waiting",
		OaProcessToken.wait_kind == "timer",
		OaProcessToken.resume_at.isnot(None),
		OaProcessToken.resume_at <= now,
	)
	if business_id:
		query = query.filter(OaProcessToken.business_id == business_id)
	moved = 0
	for token in query.all():
		token.status = "done"
		instance = db.query(OaProcessInstance).filter(OaProcessInstance.id == token.instance_id).one()
		if instance.status != "running":
			continue
		nxt = str(_outgoing(instance.graph_snapshot, token.node_id)[0]["to"])
		_activate(db, instance, nxt, depth=0, subprocess_depth=0)
		moved += 1
	db.commit()
	return {"advanced": moved}


def escalate_overdue_tasks(db: Session, business_id: Optional[int] = None) -> dict:
	now = _now()
	query = db.query(OaProcessTask).filter(
		OaProcessTask.status == "open",
		OaProcessTask.due_at.isnot(None),
		OaProcessTask.due_at <= now,
		OaProcessTask.escalated_at.is_(None),
	)
	if business_id:
		query = query.filter(OaProcessTask.business_id == business_id)
	moved = 0
	for task in query.all():
		instance = db.query(OaProcessInstance).filter(OaProcessInstance.id == task.instance_id).one()
		node = _nodes(instance.graph_snapshot).get(task.node_id) or {}
		target = node.get("escalate_position_id")
		if not target or int(target) == task.assignee_position_id:
			continue
		task.assignee_position_id = int(target)
		task.escalated_at = now
		moved += 1
	db.commit()
	return {"escalated": moved}
