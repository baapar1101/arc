from __future__ import annotations

from typing import List, Optional, Set, Tuple

from adapters.api.v1.schemas import QueryInfo, SortItem


def effective_sort_specs(
	query_info: QueryInfo,
	*,
	allowed: Optional[Set[str]] = None,
	default_when_empty: Optional[Tuple[str, bool]] = None,
	max_levels: int = 8,
) -> List[Tuple[str, bool]]:
	"""
	تعیین ترتیب نهایی مرتب‌سازی از روی QueryInfo.

	قانون اولویت:
	1) اگر sort ارسال شده و پس از اعتبارسنجی حداقل یک عضو معتبر دارد → همان.
	2) وگرنه اگر sort_by معتبر است → یک سطح از sort_by / sort_desc.
	3) وگرنه اگر default_when_empty داده شده → همان.
	4) در غیر این صورت لیست خالی (بدون مرتب‌سازی اضافه در لایهٔ عمومی).
	"""
	def _is_allowed(name: str) -> bool:
		if not name or not isinstance(name, str):
			return False
		n = name.strip()
		if not n:
			return False
		if allowed is None:
			return True
		return n in allowed

	def _from_sort_list(raw: Optional[List[SortItem]]) -> List[Tuple[str, bool]]:
		if not raw:
			return []
		seen: Set[str] = set()
		out: List[Tuple[str, bool]] = []
		for item in raw[:max_levels]:
			if item is None:
				continue
			by = (item.by or "").strip()
			if not _is_allowed(by):
				continue
			if by in seen:
				continue
			seen.add(by)
			out.append((by, bool(item.desc)))
		return out

	multi = _from_sort_list(getattr(query_info, "sort", None))
	if multi:
		return multi

	sb = query_info.sort_by
	if sb and isinstance(sb, str):
		name = sb.strip()
		if _is_allowed(name):
			return [(name, bool(query_info.sort_desc))]

	if default_when_empty is not None:
		dn, dd = default_when_empty
		if _is_allowed(dn):
			return [(dn, dd)]
	return []
