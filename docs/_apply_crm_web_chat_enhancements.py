#!/usr/bin/env python3
"""
One-shot patch for CRM web chat metadata (visitor IP + device_type).

1) hesabixAPI/app/services/crm_chat_service.py — extra_metadata on conversation dict,
   start_conversation_public(..., client_ip=, device_type=), meta on insert.
2) hesabixAPI/adapters/api/v1/public/crm_chat_public.py — get_client_ip + pass-through.

Schema (CrmChatConversationStartPublic.device_type) should already exist.

Run from repo root:
  sudo python3 docs/_apply_crm_web_chat_enhancements.py
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def patch_service() -> None:
	svc = ROOT / "hesabixAPI" / "app" / "services" / "crm_chat_service.py"
	t = svc.read_text(encoding="utf-8")
	if '"extra_metadata": c.extra_metadata' not in t:
		t = t.replace(
			'\t\t"page_url": c.page_url,\n\t\t"lead_id": c.lead_id,',
			'\t\t"page_url": c.page_url,\n\t\t"extra_metadata": c.extra_metadata if c.extra_metadata else {},\n\t\t"lead_id": c.lead_id,',
			1,
		)
	if "client_ip: Optional[str] = None" not in t:
		t = t.replace(
			"\tpage_url: Optional[str],\n\torigin_header: Optional[str],\n) -> Dict[str, Any]:\n\tw = get_widget_by_public_key",
			"\tpage_url: Optional[str],\n\torigin_header: Optional[str],\n\tclient_ip: Optional[str] = None,\n"
			"\tdevice_type: Optional[str] = None,\n) -> Dict[str, Any]:\n\tw = get_widget_by_public_key",
			1,
		)
	if "\tmeta: Dict[str, Any] = {}\n" not in t:
		t = t.replace(
			"\tvisitor_token = secrets.token_urlsafe(32)\n\tth = _hash_visitor_token(visitor_token)\n\n\tc = CrmChatConversation(",
			"\tvisitor_token = secrets.token_urlsafe(32)\n\tth = _hash_visitor_token(visitor_token)\n\n\tmeta: Dict[str, Any] = {}\n"
			'\traw_ip = (client_ip or "").strip().split("%")[0].strip()\n\tif raw_ip:\n\t\tmeta["visitor_ip"] = raw_ip[:45]\n'
			'\tdt = (device_type or "").strip().lower()\n\tif dt in ("mobile", "tablet", "desktop"):\n\t\tmeta["device_type"] = dt\n\n'
			"\tc = CrmChatConversation(",
			1,
		)
		t = t.replace(
			"\t\tpage_url=(page_url or None) if page_url else None,\n\t\tlast_message_at=None,\n\t)",
			"\t\tpage_url=(page_url or None) if page_url else None,\n\t\tlast_message_at=None,\n\t\textra_metadata=meta if meta else None,\n\t)",
			1,
		)
	svc.write_text(t, encoding="utf-8")
	print("patched", svc)


def patch_public_router() -> None:
	pub = ROOT / "hesabixAPI" / "adapters" / "api" / "v1" / "public" / "crm_chat_public.py"
	pt = pub.read_text(encoding="utf-8")
	if "from app.core.rate_limiter import get_client_ip" not in pt:
		pt = pt.replace(
			"from app.core.responses import ApiError, format_datetime_fields, success_response\n",
			"from app.core.rate_limiter import get_client_ip\nfrom app.core.responses import ApiError, format_datetime_fields, success_response\n",
			1,
		)
	if "device_type=body.device_type" not in pt:
		pt = pt.replace(
			"\t\t\tpage_url=body.page_url,\n\t\t\torigin_header=_origin(request),\n\t\t)",
			"\t\t\tpage_url=body.page_url,\n\t\t\torigin_header=_origin(request),\n"
			"\t\t\tclient_ip=get_client_ip(request),\n\t\t\tdevice_type=body.device_type,\n\t\t)",
			1,
		)
	pub.write_text(pt, encoding="utf-8")
	print("patched", pub)


if __name__ == "__main__":
	patch_service()
	patch_public_router()
