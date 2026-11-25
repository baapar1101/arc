"""پس از قطعی‌شدن حواله انبار، موجودی متصل را به ووکامرس (ArcWOC) پوش می‌کند."""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Set

from sqlalchemy import event
from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)

_ORIGIN_KEY = "arcwoc_origin"
_ORIGIN_WC_PUSH = "wc_stock_push"
_SESSION_QUEUE_KEY = "woocommerce_stock_push_queue"
_SESSION_LISTENER_KEY = "woocommerce_stock_push_listener"
_SESSION_OWNERS_KEY = "woocommerce_stock_push_transaction_owners"
_SESSION_COMMITTED_KEY = "woocommerce_stock_push_committed_savepoints"


def schedule_woocommerce_stock_push_after_warehouse_post(
	db: Session,
	*,
	business_id: int,
	warehouse_document_id: int,
	product_ids: List[int],
	extra_info: Optional[Dict[str, Any]] = None,
) -> None:
	"""صف‌بندی پوش؛ فقط بعد از commit نشست اجرا می‌شود تا گزارش موجودی، حواله را ببیند."""
	if not product_ids:
		return

	info = extra_info if isinstance(extra_info, dict) else {}
	if str(info.get(_ORIGIN_KEY) or "") == _ORIGIN_WC_PUSH:
		# جلوگیری از حلقه: این حواله خودش از تغییر موجودی ووکامرس آمده است.
		return

	clean_ids = sorted({int(x) for x in product_ids if x is not None and int(x) > 0})
	if not clean_ids:
		return

	queue: List[Dict[str, Any]] = db.info.setdefault(_SESSION_QUEUE_KEY, [])
	queue.append(
		{
			"business_id": int(business_id),
			"warehouse_document_id": int(warehouse_document_id),
			"product_ids": clean_ids,
		}
	)
	owners = db.info.setdefault(_SESSION_OWNERS_KEY, {})
	owners[id(queue[-1])] = db.get_nested_transaction() or db.get_transaction()
	_ensure_commit_listener(db)


def _clear_pending_stock_pushes(session: Session) -> None:
	"""Clear transaction data; listeners remain attached for Session reuse."""
	session.info.pop(_SESSION_QUEUE_KEY, None)
	session.info.pop(_SESSION_OWNERS_KEY, None)
	session.info.pop(_SESSION_COMMITTED_KEY, None)


def _discard_stock_push_scope(session: Session, transaction: Any) -> None:
	"""A rolled-back savepoint also owns messages from committed descendants."""
	queue = session.info.get(_SESSION_QUEUE_KEY, [])
	if not queue:
		return
	owners = session.info.get(_SESSION_OWNERS_KEY, {})
	kept = []
	for payload in queue:
		owner = owners.get(id(payload))
		while owner is not None and owner is not transaction:
			owner = owner.parent
		if owner is transaction:
			owners.pop(id(payload), None)
		else:
			kept.append(payload)
	session.info[_SESSION_QUEUE_KEY] = kept


def _ensure_commit_listener(db: Session) -> None:
	if db.info.get(_SESSION_LISTENER_KEY):
		return
	db.info[_SESSION_LISTENER_KEY] = True

	def _after_commit(session: Session) -> None:
		if session.in_nested_transaction():
			session.info.setdefault(_SESSION_COMMITTED_KEY, set()).add(session.get_nested_transaction())
			return
		payloads = list(session.info.pop(_SESSION_QUEUE_KEY, []) or [])
		_clear_pending_stock_pushes(session)
		for payload in payloads:
			try:
				_execute_stock_push(payload)
			except Exception as exc:  # noqa: BLE001 — نباید پست حواله را بشکنند
				logger.warning(
					"woocommerce_stock_push_failed business_id=%s wh_id=%s err=%s",
					payload.get("business_id"),
					payload.get("warehouse_document_id"),
					exc,
					exc_info=True,
				)

	def _after_transaction_end(session: Session, transaction: Any) -> None:
		if transaction.parent is None:
			# Includes root rollback/close; sending belongs only to after_commit.
			_clear_pending_stock_pushes(session)
		elif transaction.nested:
			committed = session.info.get(_SESSION_COMMITTED_KEY, set())
			if transaction in committed:
				committed.discard(transaction)
			else:
				_discard_stock_push_scope(session, transaction)

	# once=True would consume the listener on the first nested commit.
	event.listen(db, "after_commit", _after_commit)
	event.listen(db, "after_transaction_end", _after_transaction_end)


def _execute_stock_push(payload: Dict[str, Any]) -> None:
	from adapters.db.session import SessionLocal
	from app.core.woocommerce_plugin_dependency import check_woocommerce_plugin_active
	from app.services import woocommerce_integration_service as wc_svc

	business_id = int(payload["business_id"])
	product_ids = list(payload.get("product_ids") or [])
	wh_id = int(payload.get("warehouse_document_id") or 0)

	db = SessionLocal()
	try:
		if not check_woocommerce_plugin_active(db, business_id):
			return
		# اگر پل پیکربندی نشده، بی‌صدا رد شو.
		try:
			store, token = wc_svc._load_bridge_credentials(db, business_id)  # noqa: SLF001
		except Exception:
			return
		if not store or not token:
			return

		settings = wc_svc.get_settings(db, business_id)
		# پیش‌فرض: پوش فعال است مگر صریحاً خاموش شده باشد.
		if settings.get("push_stock_to_wc_on_warehouse_post") is False:
			return

		body = {
			"source": "hesabix_push",
			"product_ids": product_ids,
			"warehouse_document_id": wh_id,
		}
		result = wc_svc.post_control_stock_pull_run(db, business_id, body)
		logger.info(
			"woocommerce_stock_push_ok business_id=%s wh_id=%s updated=%s",
			business_id,
			wh_id,
			(result or {}).get("updated"),
		)
	except Exception as exc:  # noqa: BLE001
		logger.warning(
			"woocommerce_stock_push_exec_failed business_id=%s wh_id=%s err=%s",
			business_id,
			wh_id,
			exc,
			exc_info=True,
		)
	finally:
		db.close()


def collect_product_ids_from_warehouse_lines(lines: Any) -> List[int]:
	ids: Set[int] = set()
	if not lines:
		return []
	for ln in lines:
		pid = getattr(ln, "product_id", None)
		if pid is None and isinstance(ln, dict):
			pid = ln.get("product_id")
		try:
			i = int(pid) if pid is not None else 0
		except (TypeError, ValueError):
			i = 0
		if i > 0:
			ids.add(i)
	return sorted(ids)
