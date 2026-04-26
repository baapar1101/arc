# noqa: D100
"""دسترسی‌های ریزدانهٔ چت وب CRM + سازگاری با crm.view / crm.write قدیمی."""

from __future__ import annotations

from typing import Any, Dict


def check_crm_web_chat_capability(permissions: Dict[str, Any], capability: str) -> bool:
	"""
	capability: view | reply | manage_widgets | edit_conversations | delete_messages
	- view: crm_web_chat.view یا crm.view (یا read قدیمی)
	- بقیه: crm_web_chat.<capability> یا crm.write
	"""
	if not permissions:
		return False
	p = permissions
	cw = p.get("crm_web_chat")
	if not isinstance(cw, dict):
		cw = {}
	crm_ = p.get("crm")
	if not isinstance(crm_, dict):
		crm_ = {}
	if capability == "view":
		return bool(cw.get("view") is True or crm_.get("view") is True or crm_.get("read") is True)
	if capability in ("reply", "manage_widgets", "edit_conversations", "delete_messages"):
		return bool(cw.get(capability) is True or crm_.get("write") is True)
	return False
