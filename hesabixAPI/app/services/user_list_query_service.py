from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import String, and_, cast, func, or_, select
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Session

from adapters.api.v1.schemas import FilterItem, QueryInfo, SortItem
from adapters.db.models.api_key import ApiKey
from adapters.db.models.user import User
from app.core.settings import get_settings
from app.services.query_service import QueryBuilder
from app.services.sort_resolution import effective_sort_specs


def _user_full_name_expr():
	"""عبارت SQL برای نام کامل (first + last)."""
	return func.trim(
		func.concat(
			func.coalesce(User.first_name, ""),
			" ",
			func.coalesce(User.last_name, ""),
		)
	)


def _last_login_subquery():
	"""آخرین زمان استفاده از کلید API فعال هر کاربر."""
	return (
		select(
			ApiKey.user_id.label("user_id"),
			func.max(func.coalesce(ApiKey.last_used_at, ApiKey.created_at)).label(
				"last_login_at"
			),
		)
		.where(ApiKey.revoked_at.is_(None))
		.group_by(ApiKey.user_id)
		.subquery("user_last_login")
	)


def _permissions_json():
	return cast(User.app_permissions, JSONB)


def _role_admin_condition():
	return _permissions_json().contains({"superadmin": True})


def _role_operator_condition():
	return and_(
		_permissions_json().contains({"operator": True}),
		~_role_admin_condition(),
	)


def _role_supervisor_condition():
	return and_(
		_permissions_json().contains({"supervisor": True}),
		~_role_admin_condition(),
		~_permissions_json().contains({"operator": True}),
	)


def _role_user_condition():
	perms = _permissions_json()
	return and_(
		~perms.contains({"superadmin": True}),
		~perms.contains({"operator": True}),
		~perms.contains({"supervisor": True}),
	)


def _role_condition_for_value(role: str):
	if role == "admin":
		return _role_admin_condition()
	if role == "operator":
		return _role_operator_condition()
	if role == "supervisor":
		return _role_supervisor_condition()
	if role == "user":
		return _role_user_condition()
	return None


def _build_role_filter(filter_item: FilterItem):
	if filter_item.operator == "=":
		values = [filter_item.value]
	elif filter_item.operator == "in" and isinstance(filter_item.value, list):
		values = filter_item.value
	else:
		return None
	conditions = [_role_condition_for_value(v) for v in values if isinstance(v, str)]
	conditions = [c for c in conditions if c is not None]
	if not conditions:
		return None
	return or_(*conditions) if len(conditions) > 1 else conditions[0]


def _status_active_condition():
	return and_(
		User.is_active.is_(True),
		or_(
			User.email_verified.is_(True),
			User.mobile_verified.is_(True),
		),
	)


def _status_inactive_condition():
	return User.is_active.is_(False)


def _status_suspended_condition():
	"""فعلاً معادل غیرفعال — ستون جداگانه‌ای در DB نیست."""
	return User.is_active.is_(False)


def _status_pending_condition():
	"""کاربر فعال که هنوز ایمیل و موبایل تأیید نشده‌اند."""
	return and_(
		User.is_active.is_(True),
		User.email_verified.is_(False),
		User.mobile_verified.is_(False),
	)


def _build_status_filter(filter_item: FilterItem):
	if filter_item.operator == "=":
		status = filter_item.value
		if status == "active":
			return _status_active_condition()
		if status == "inactive":
			return _status_inactive_condition()
		if status == "suspended":
			return _status_suspended_condition()
		if status == "pending":
			return _status_pending_condition()
		return None

	if filter_item.operator == "in" and isinstance(filter_item.value, list):
		statuses = [s for s in filter_item.value if isinstance(s, str)]
		if not statuses:
			return None
		parts = []
		if "active" in statuses:
			parts.append(_status_active_condition())
		if "inactive" in statuses:
			parts.append(_status_inactive_condition())
		if "suspended" in statuses:
			parts.append(_status_suspended_condition())
		if "pending" in statuses:
			parts.append(_status_pending_condition())
		if not parts:
			return None
		return or_(*parts) if len(parts) > 1 else parts[0]

	return None


def _build_full_name_filter(operator: str, value: Any):
	if value is None or (isinstance(value, str) and not value.strip()):
		return None
	text = str(value).strip()
	full_name = _user_full_name_expr()
	if operator == "=":
		return full_name.ilike(text)
	if operator == "*":
		like = f"%{text}%"
		return or_(
			User.first_name.ilike(like),
			User.last_name.ilike(like),
			full_name.ilike(like),
		)
	if operator == "*?":
		return or_(
			User.first_name.ilike(f"{text}%"),
			User.last_name.ilike(f"{text}%"),
			full_name.ilike(f"{text}%"),
		)
	if operator == "?*":
		return or_(
			User.first_name.ilike(f"%{text}"),
			User.last_name.ilike(f"%{text}"),
			full_name.ilike(f"%{text}"),
		)
	return None


def _build_id_filter(operator: str, value: Any):
	if operator == "=":
		try:
			return User.id == int(value)
		except (TypeError, ValueError):
			return None
	if operator == "*":
		text = str(value).strip()
		if not text:
			return None
		return cast(User.id, String).ilike(f"%{text}%")
	return None


def _coerce_datetime(value: Any) -> datetime | None:
	if value is None:
		return None
	if isinstance(value, datetime):
		return value
	text = str(value).strip()
	if not text:
		return None
	if text.endswith("Z"):
		text = text[:-1] + "+00:00"
	try:
		return datetime.fromisoformat(text)
	except ValueError:
		return None


def _build_last_login_filter(operator: str, value: Any, last_login_sq):
	col = last_login_sq.c.last_login_at
	dt = _coerce_datetime(value)
	if dt is None:
		return None
	if operator == ">=":
		return col >= dt
	if operator == "<":
		return col < dt
	if operator == "<=":
		return col <= dt
	if operator == ">":
		return col > dt
	if operator == "=":
		end = dt + timedelta(days=1)
		return and_(col >= dt, col < end)
	return None


def normalize_user_search_fields(search_fields: list[str] | None) -> list[str] | None:
	if not search_fields:
		return search_fields
	seen: set[str] = set()
	out: list[str] = []
	for field in search_fields:
		if field == "full_name":
			for part in ("first_name", "last_name"):
				if part not in seen:
					seen.add(part)
					out.append(part)
		elif field not in seen:
			seen.add(field)
			out.append(field)
	return out or None


def _prepare_query_info(query_info: QueryInfo) -> QueryInfo:
	updates: dict[str, Any] = {}
	if query_info.search_fields:
		updates["search_fields"] = normalize_user_search_fields(query_info.search_fields)
	if query_info.sort_by == "full_name":
		updates["sort_by"] = None
	if query_info.sort:
		filtered_sort = [
			SortItem(by=s.by, desc=s.desc)
			for s in query_info.sort
			if s.by != "full_name"
		]
		updates["sort"] = filtered_sort or None
	if updates:
		return query_info.model_copy(update=updates)
	return query_info


def _split_filters(
	filters: list[FilterItem] | None,
) -> tuple[list[FilterItem], list[Any], bool]:
	"""فیلترهای مجازی را به شرط SQL تبدیل می‌کند؛ بقیه به QueryBuilder می‌روند."""
	if not filters:
		return [], [], False

	standard: list[FilterItem] = []
	extras: list[Any] = []
	needs_last_login = False

	for f in filters:
		if f.property == "status":
			cond = _build_status_filter(f)
			if cond is not None:
				extras.append(cond)
		elif f.property == "role":
			cond = _build_role_filter(f)
			if cond is not None:
				extras.append(cond)
		elif f.property == "full_name":
			cond = _build_full_name_filter(f.operator, f.value)
			if cond is not None:
				extras.append(cond)
		elif f.property == "id":
			cond = _build_id_filter(f.operator, f.value)
			if cond is not None:
				extras.append(cond)
		elif f.property == "last_login_at":
			needs_last_login = True
		else:
			standard.append(f)

	return standard, extras, needs_last_login


def _resolve_last_login_extras(filters: list[FilterItem], last_login_sq) -> list[Any]:
	out: list[Any] = []
	for f in filters:
		if f.property != "last_login_at":
			continue
		cond = _build_last_login_filter(f.operator, f.value, last_login_sq)
		if cond is not None:
			out.append(cond)
	return out


def _needs_last_login_join(query_info: QueryInfo, has_last_login_filter: bool) -> bool:
	if has_last_login_filter:
		return True
	if query_info.sort_by == "last_login_at":
		return True
	if query_info.sort and any(s.by == "last_login_at" for s in query_info.sort):
		return True
	return False


def _apply_user_sorting(
	builder: QueryBuilder,
	query_info: QueryInfo,
	last_login_sq,
) -> QueryBuilder:
	if query_info.sort:
		specs = [(s.by, s.desc) for s in query_info.sort]
	elif query_info.sort_by:
		specs = [(query_info.sort_by, query_info.sort_desc)]
	else:
		specs = effective_sort_specs(query_info, allowed=None, default_when_empty=None)

	if not specs:
		return builder

	order_parts = []
	for name, desc in specs:
		if name == "full_name":
			expr = _user_full_name_expr()
			order_parts.append(expr.desc() if desc else expr.asc())
		elif name == "last_login_at":
			col = last_login_sq.c.last_login_at
			order_parts.append(col.desc().nullslast() if desc else col.asc().nullsfirst())
		elif hasattr(User, name):
			column = getattr(User, name)
			order_parts.append(column.desc() if desc else column.asc())

	if order_parts:
		builder.stmt = builder.stmt.order_by(*order_parts)
	return builder


def query_users_admin(db: Session, query_info: QueryInfo) -> tuple[list[User], int]:
	"""کوئری لیست مدیریت کاربران با پشتیبانی از فیلدهای مجازی UI."""
	settings = get_settings()
	if query_info.take > settings.max_page_size:
		query_info = query_info.model_copy(update={"take": settings.max_page_size})

	prepared = _prepare_query_info(query_info)
	last_login_sq = _last_login_subquery()
	standard_filters, extras, has_login_filter = _split_filters(prepared.filters)
	extras.extend(_resolve_last_login_extras(prepared.filters or [], last_login_sq))

	needs_login = _needs_last_login_join(query_info, has_login_filter)
	filter_info = prepared.model_copy(update={"filters": standard_filters or None})

	count_builder = QueryBuilder(User, db)
	if needs_login:
		count_builder.stmt = count_builder.stmt.outerjoin(
			last_login_sq, last_login_sq.c.user_id == User.id
		)
	count_builder.apply_filters(filter_info.filters)
	count_builder.apply_search(filter_info.search, filter_info.search_fields)
	for cond in extras:
		count_builder.stmt = count_builder.stmt.where(cond)
	total_count = count_builder.execute_count()

	data_builder = QueryBuilder(User, db)
	if needs_login:
		data_builder.stmt = data_builder.stmt.outerjoin(
			last_login_sq, last_login_sq.c.user_id == User.id
		)
	data_builder.apply_filters(filter_info.filters)
	data_builder.apply_search(filter_info.search, filter_info.search_fields)
	for cond in extras:
		data_builder.stmt = data_builder.stmt.where(cond)
	_apply_user_sorting(data_builder, query_info, last_login_sq)
	data_builder.apply_pagination(prepared.skip, prepared.take)
	results = data_builder.execute()

	return results, total_count
