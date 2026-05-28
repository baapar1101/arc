"""
پچ OpenAPI — یکسان‌سازی requestBody endpointهای لیست با QueryInfo / DocumentListQuery (فاز ۱۲).
"""
from __future__ import annotations

import copy
import logging
from typing import Any, Dict, List, Tuple

logger = logging.getLogger(__name__)

# (path suffix, method, schema ref name)
# مسیرها در OpenAPI با prefix /api/v1 هستند
# fallback وقتی operationId در OPERATION_ID_SCHEMA نیست
LIST_ENDPOINT_SCHEMAS: List[Tuple[str, str, str]] = [
	("/businesses/{business_id}/persons", "post", "QueryInfo"),
	("/businesses/{business_id}/bank-accounts", "post", "QueryInfo"),
	("/businesses/{business_id}/cash-registers", "post", "QueryInfo"),
	("/businesses/{business_id}/petty-cash", "post", "QueryInfo"),
	("/businesses/{business_id}/documents", "post", "DocumentListQuery"),
	("/businesses/{business_id}/receipts-payments", "post", "DocumentListQuery"),
	("/businesses/{business_id}/expense-income", "post", "DocumentListQuery"),
	("/businesses/{business_id}/transfers", "post", "DocumentListQuery"),
	("/kardex/businesses/{business_id}/lines", "post", "KardexListQuery"),
]

# operationId → schema (دقیق‌تر از path وقتی چند operation روی یک path است)
OPERATION_ID_SCHEMA: Dict[str, str] = {
	"get_persons_endpoint": "QueryInfo",
	"list_checks_endpoint": "DocumentListQuery",
	"list_bank_accounts_endpoint": "QueryInfo",
	"list_cash_registers_endpoint": "QueryInfo",
	"list_petty_cash_endpoint": "QueryInfo",
	"list_documents_endpoint": "DocumentListQuery",
	"list_receipts_payments_endpoint": "DocumentListQuery",
	"list_expense_income_endpoint": "DocumentListQuery",
	"list_transfers_endpoint": "DocumentListQuery",
	"search_invoices_endpoint": "InvoiceListQuery",
	"search_products_endpoint": "QueryInfo",
	"list_kardex_lines_endpoint": "KardexListQuery",
	"search_warehouse_docs": "WarehouseDocListQuery",
}


def _request_body_ref(schema_name: str) -> Dict[str, Any]:
	return {
		"required": True,
		"content": {
			"application/json": {
				"schema": {"$ref": f"#/components/schemas/{schema_name}"},
			}
		},
	}


def apply_list_query_openapi_patch(openapi_schema: Dict[str, Any]) -> None:
	"""جایگزینی requestBodyهای generic با $ref به QueryInfo و مدل‌های مشتق."""
	paths = openapi_schema.get("paths") or {}
	patched = 0

	for path, methods in paths.items():
		for method, details in methods.items():
			if method not in ("get", "post", "put", "delete", "patch"):
				continue
			op_id = details.get("operationId") or ""
			schema_name = OPERATION_ID_SCHEMA.get(op_id)
			if not schema_name:
				for suffix, m, name in LIST_ENDPOINT_SCHEMAS:
					if m == method and path.endswith(suffix):
						# products و warehouse هر دو /business/{id}/search — با operationId تفکیک شد
						if suffix == "/business/{business_id}/search" and op_id not in (
							"search_products_endpoint",
							"search_invoices_endpoint",
							"search_warehouse_docs",
						):
							continue
						schema_name = name
						break
			if not schema_name:
				continue
			details["requestBody"] = _request_body_ref(schema_name)
			patched += 1

	if patched:
		logger.debug("OpenAPI list query patch applied to %s operations", patched)
