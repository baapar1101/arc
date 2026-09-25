"""گره‌های AST سفید برای HScript."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Optional


@dataclass
class Node:
	line: int = 1
	column: int = 1


# --- Expressions ---

@dataclass
class Literal(Node):
	value: Any = None


@dataclass
class Name(Node):
	id: str = ""


@dataclass
class UnaryOp(Node):
	op: str = ""
	operand: Any = None


@dataclass
class BinOp(Node):
	left: Any = None
	op: str = ""
	right: Any = None


@dataclass
class BoolOp(Node):
	op: str = ""  # and | or
	values: list[Any] = field(default_factory=list)


@dataclass
class Compare(Node):
	left: Any = None
	ops: list[str] = field(default_factory=list)
	comparators: list[Any] = field(default_factory=list)


@dataclass
class Attribute(Node):
	value: Any = None
	attr: str = ""


@dataclass
class Subscript(Node):
	value: Any = None
	index: Any = None


@dataclass
class Call(Node):
	func: Any = None
	args: list[Any] = field(default_factory=list)
	keywords: dict[str, Any] = field(default_factory=dict)


@dataclass
class ListExpr(Node):
	elts: list[Any] = field(default_factory=list)


@dataclass
class DictExpr(Node):
	keys: list[Any] = field(default_factory=list)
	values: list[Any] = field(default_factory=list)


# --- Statements ---

@dataclass
class Assign(Node):
	target: str = ""
	value: Any = None


@dataclass
class ExprStmt(Node):
	value: Any = None


@dataclass
class If(Node):
	test: Any = None
	body: list[Any] = field(default_factory=list)
	orelse: list[Any] = field(default_factory=list)


@dataclass
class For(Node):
	target: str = ""
	iter: Any = None
	body: list[Any] = field(default_factory=list)


@dataclass
class While(Node):
	test: Any = None
	body: list[Any] = field(default_factory=list)


@dataclass
class FunctionDef(Node):
	name: str = ""
	params: list[str] = field(default_factory=list)
	body: list[Any] = field(default_factory=list)


@dataclass
class Return(Node):
	value: Any = None


@dataclass
class Pass(Node):
	pass


@dataclass
class Break(Node):
	pass


@dataclass
class Continue(Node):
	pass


@dataclass
class Module(Node):
	body: list[Any] = field(default_factory=list)
