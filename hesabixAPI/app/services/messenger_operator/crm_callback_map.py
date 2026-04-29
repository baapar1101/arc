# noqa: D100
from __future__ import annotations


def crm_callback_data_to_command(parts: list[str]) -> str | None:
	"""تبدیل callback دکمه‌های crm:* به دستور متنی فلو اپراتور."""
	if not parts:
		return None
	head = parts[0]
	aliases = {
		"start": "/crmchat",
		"help": "/crmhelp",
		"list": "/list",
		"more": "/more",
		"hist": "/history",
		"cancel": "/cancel",
		"exit": "/exit",
		"stat": "/status",
	}
	if head in aliases:
		return aliases[head]
	if head == "biz" and len(parts) >= 2 and str(parts[1]).isdigit():
		return f"/biz {parts[1]}"
	if head == "open" and len(parts) >= 2 and str(parts[1]).isdigit():
		return f"/open {parts[1]}"
	if head == "pb" and len(parts) >= 2 and str(parts[1]).isdigit():
		return f"/bizpick {parts[1]}"
	return None
