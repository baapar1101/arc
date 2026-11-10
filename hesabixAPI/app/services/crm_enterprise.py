"""قواعد سازمان فروش: پیش‌بینی، سهمیه، دیده شدن رکورد و چرخه مدیر."""
from __future__ import annotations

from collections import defaultdict
from decimal import Decimal, ROUND_HALF_UP
from typing import Any

FORECAST_CATEGORIES = ("pipeline", "best_case", "commit", "closed", "omitted")
OPEN_FORECAST_CATEGORIES = ("pipeline", "best_case", "commit")


def money(value: Any) -> Decimal:
    if value is None or value == "":
        return Decimal("0.00")
    return Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def effective_forecast(*, closed: bool, is_win: bool, is_lost: bool, probability: int | None, override: str | None) -> str:
    if closed and is_win:
        return "closed"
    if closed and is_lost:
        return "omitted"
    if closed:
        return "omitted"
    if override in OPEN_FORECAST_CATEGORIES:
        return str(override)
    score = int(probability or 0)
    if score >= 70:
        return "commit"
    if score >= 40:
        return "best_case"
    return "pipeline"


def quota_progress(target: Any, won: Any) -> dict[str, Any]:
    goal = money(target)
    achieved = money(won)
    if goal <= 0:
        return {"target": float(goal), "won": float(achieved), "percent": None, "remaining": None}
    percent = int(round((achieved / goal) * 100))
    return {
        "target": float(goal),
        "won": float(achieved),
        "percent": min(percent, 999),
        "remaining": float(money(goal - achieved)),
    }


def person_belongs_to_organization(billing_person_id: int, contact_ids: set[int] | list[int], person_id: int) -> bool:
    return int(person_id) == int(billing_person_id) or int(person_id) in {int(item) for item in contact_ids}


def manager_link_creates_cycle(links: list[tuple[int, int]], manager_id: int, member_id: int) -> bool:
    if int(manager_id) == int(member_id):
        return True
    children: dict[int, set[int]] = defaultdict(set)
    for manager, member in links:
        children[int(manager)].add(int(member))
    stack = [int(member_id)]
    seen: set[int] = set()
    while stack:
        node = stack.pop()
        if node == int(manager_id):
            return True
        if node in seen:
            continue
        seen.add(node)
        stack.extend(children.get(node, ()))
    return False


def descendant_ids(links: list[tuple[int, int]], manager_id: int) -> list[int]:
    children: dict[int, list[int]] = defaultdict(list)
    for manager, member in links:
        children[int(manager)].append(int(member))
    found: list[int] = []
    stack = list(children.get(int(manager_id), []))
    seen: set[int] = set()
    while stack:
        node = stack.pop()
        if node in seen:
            continue
        seen.add(node)
        found.append(node)
        stack.extend(children.get(node, []))
    return found


def record_access(
    *,
    enforced: bool,
    is_owner: bool,
    user_id: int,
    assigned_to: int | None,
    created_by: int | None,
    acl_access: str | None,
    manages_assignee: bool,
    queue_member: bool,
) -> str:
    if not enforced or is_owner:
        return "edit"
    if user_id in {assigned_to, created_by} or manages_assignee:
        return "edit"
    if acl_access == "edit":
        return "edit"
    if acl_access == "view" or (queue_member and assigned_to is None):
        return "view"
    return "none"
