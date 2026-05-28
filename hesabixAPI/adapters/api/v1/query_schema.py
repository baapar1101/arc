"""
GET /query-schema/{entity} — کاتالوگ فیلتر برای کلاینت و AI (فاز ۱۲.۳).
"""
from __future__ import annotations

from typing import Any, Dict, List

from fastapi import APIRouter, Depends, Path

from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import success_response, ApiError
from app.services.ai.ai_query_filter_catalog import list_catalog_entities
from app.services.ai.ai_query_filter_service import entity_query_schema_for_ai

router = APIRouter(prefix="/query-schema", tags=["جستجو و فیلتر"])


@router.get(
	"",
	summary="فهرست entityهای دارای schema جستجو",
	description="نام entityهایی که برای `GET /query-schema/{entity}` پشتیبانی می‌شود.",
)
async def list_query_schema_entities(
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	return success_response(
		data={"entities": list_catalog_entities()},
		message="QUERY_SCHEMA_ENTITIES",
	)


@router.get(
	"/{entity}",
	summary="اسکیمای فیلتر و جستجو برای یک entity",
	description=(
		"فیلدهای قابل فیلتر، عملگرها، search_fields پیش‌فرض و مثال JSON. "
		"همان دادهٔ `list_queryable_fields` در AI."
	),
)
async def get_query_schema(
	entity: str = Path(..., description="مثلاً invoice, person, product, document, check"),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	try:
		schema = entity_query_schema_for_ai(entity)
	except ValueError as exc:
		raise ApiError("UNKNOWN_ENTITY", str(exc), http_status=404) from exc
	return success_response(data=schema, message="QUERY_SCHEMA")
