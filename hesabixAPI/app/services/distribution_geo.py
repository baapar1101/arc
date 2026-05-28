"""محاسبات جغرافیایی افزونه پخش."""

from __future__ import annotations

import math
from typing import Any, Optional, Tuple


def _to_float(val: Any) -> Optional[float]:
	if val is None:
		return None
	try:
		return float(val)
	except (TypeError, ValueError):
		return None


def haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	"""فاصلهٔ تقریبی دو نقطه بر حسب متر."""
	r = 6371000.0
	p1, p2 = math.radians(lat1), math.radians(lat2)
	dphi = math.radians(lat2 - lat1)
	dlambda = math.radians(lon2 - lon1)
	a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlambda / 2) ** 2
	return 2 * r * math.asin(math.sqrt(min(1.0, a)))


def person_coords(person: Any) -> Tuple[Optional[float], Optional[float]]:
	return _to_float(getattr(person, "latitude", None)), _to_float(getattr(person, "longitude", None))


def check_geofence(
	person_lat: Optional[float],
	person_lng: Optional[float],
	visit_lat: Optional[float],
	visit_lng: Optional[float],
	radius_meters: int,
	require: bool,
) -> Tuple[bool, Optional[float], str]:
	"""
	برمی‌گرداند: (مجاز, فاصله_متر, پیام)
	اگر geofence غیرفعال باشد همیشه مجاز است.
	"""
	if radius_meters <= 0 or not require:
		return True, None, ""
	if person_lat is None or person_lng is None:
		return False, None, "مشتری مختصات جغرافیایی ندارد."
	if visit_lat is None or visit_lng is None:
		return False, None, "موقعیت ویزیتور ثبت نشده است."
	dist = haversine_meters(person_lat, person_lng, visit_lat, visit_lng)
	if dist > float(radius_meters):
		return False, dist, f"فاصله از مشتری ({int(dist)} متر) بیش از حد مجاز ({radius_meters} متر) است."
	return True, dist, ""
