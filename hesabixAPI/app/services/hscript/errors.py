"""خطاهای ساختاریافته HScript (برای UI و AI)."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Optional


@dataclass
class HScriptError(Exception):
	"""خطای زمان ترجمه/اجرای HScript."""

	code: str
	message: str
	line: Optional[int] = None
	column: Optional[int] = None
	hint: Optional[str] = None
	doc_id: Optional[str] = None
	details: dict[str, Any] = field(default_factory=dict)

	def __str__(self) -> str:  # pragma: no cover - convenience
		loc = ""
		if self.line is not None:
			loc = f" (line {self.line}"
			if self.column is not None:
				loc += f", col {self.column}"
			loc += ")"
		return f"[{self.code}] {self.message}{loc}"

	def to_dict(self) -> dict[str, Any]:
		return {
			"code": self.code,
			"message": self.message,
			"line": self.line,
			"column": self.column,
			"hint": self.hint,
			"doc_id": self.doc_id,
			"details": self.details or {},
		}


class SyntaxErrorHS(HScriptError):
	def __init__(self, message: str, *, line: int | None = None, column: int | None = None, **kwargs: Any):
		super().__init__(code="E001_SYNTAX", message=message, line=line, column=column, doc_id="hscript.errors.E001", **kwargs)


class NameErrorHS(HScriptError):
	def __init__(self, message: str, *, line: int | None = None, column: int | None = None, **kwargs: Any):
		super().__init__(code="E010_NAME", message=message, line=line, column=column, doc_id="hscript.errors.E010", **kwargs)


class TypeErrorHS(HScriptError):
	def __init__(self, message: str, *, line: int | None = None, column: int | None = None, **kwargs: Any):
		super().__init__(code="E020_TYPE", message=message, line=line, column=column, doc_id="hscript.errors.E020", **kwargs)


class SecurityErrorHS(HScriptError):
	def __init__(self, message: str, *, line: int | None = None, column: int | None = None, **kwargs: Any):
		super().__init__(
			code="E030_SECURITY",
			message=message,
			line=line,
			column=column,
			doc_id="hscript.errors.E030",
			hint="عملیات غیرمجاز در sandbox مسدود شد.",
			**kwargs,
		)


class ResourceLimitErrorHS(HScriptError):
	def __init__(self, message: str, *, line: int | None = None, column: int | None = None, **kwargs: Any):
		super().__init__(
			code="E050_RESOURCE_LIMIT",
			message=message,
			line=line,
			column=column,
			doc_id="hscript.errors.E050",
			hint="محدودیت منابع اجرا؛ اسکریپت را ساده‌تر یا فیلتر کنید.",
			**kwargs,
		)


class RuntimeErrorHS(HScriptError):
	def __init__(self, message: str, *, line: int | None = None, column: int | None = None, **kwargs: Any):
		super().__init__(code="E040_RUNTIME", message=message, line=line, column=column, doc_id="hscript.errors.E040", **kwargs)
