from __future__ import annotations

from typing import Any, Dict, List, Optional, Set, Type

from sqlalchemy.orm import Query

from adapters.api.v1.schemas import QueryInfo
from app.services.sort_resolution import effective_sort_specs


def apply_sqlalchemy_order_from_query_dict(
	q: Query,
	model_class: Type[Any],
	query_dict: Dict[str, Any],
	*,
	allowed_columns: Optional[Set[str]] = None,
	fallback_column: str = "created_at",
	default_sort_desc: bool = True,
	tie_breaker_column: Optional[str] = "id",
) -> Query:
	"""
	مرتب‌سازی روی یک Query معمولی SQLAlchemy از کلیدهای sort / sort_by / sort_desc در dict.

	- اگر sort معتبر باشد، اولویت با آن است؛ وگرنه sort_by تک‌ستونه (سازگار با قبل).
	- ستون‌های ناموجود روی مدل نادیده گرفته می‌شوند.
	- در انتها در صورت وجود، tie_breaker_column به‌صورت صعودی برای پایداری صفحه‌بندی اضافه می‌شود.
	"""
	raw_sort = query_dict.get("sort")
	sort_list = raw_sort if isinstance(raw_sort, list) else None
	try:
		qi = QueryInfo.model_validate({
			"take": int(query_dict.get("take", 20) or 20),
			"skip": int(query_dict.get("skip", 0) or 0),
			"sort_by": query_dict.get("sort_by"),
			"sort_desc": bool(query_dict.get("sort_desc", default_sort_desc)),
			"sort": sort_list,
		})
	except Exception:
		qi = QueryInfo(
			take=20,
			skip=0,
			sort_by=query_dict.get("sort_by"),
			sort_desc=bool(query_dict.get("sort_desc", default_sort_desc)),
		)

	specs = effective_sort_specs(
		qi,
		allowed=allowed_columns,
		default_when_empty=None,
	)
	if not specs:
		fb = query_dict.get("sort_by") or fallback_column
		if isinstance(fb, str) and fb.strip():
			specs = [(fb.strip(), bool(query_dict.get("sort_desc", default_sort_desc)))]
		else:
			specs = [(fallback_column, default_sort_desc)]

	clauses: List[Any] = []
	for name, desc in specs:
		if not hasattr(model_class, name):
			continue
		col = getattr(model_class, name)
		clauses.append(col.desc() if desc else col.asc())

	if not clauses:
		fc = getattr(model_class, fallback_column, None)
		if fc is not None:
			clauses.append(fc.desc() if default_sort_desc else fc.asc())

	if tie_breaker_column and hasattr(model_class, tie_breaker_column):
		last_name = specs[-1][0] if specs else None
		if last_name != tie_breaker_column:
			tb = getattr(model_class, tie_breaker_column)
			clauses.append(tb.asc())

	if clauses:
		return q.order_by(*clauses)
	return q
