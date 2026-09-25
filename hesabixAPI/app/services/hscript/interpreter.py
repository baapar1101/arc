"""مفسر امن HScript روی AST سفید — بدون eval پایتون."""

from __future__ import annotations

import operator
import time
from typing import Any

from app.services.hscript import ast_nodes as ast
from app.services.hscript.errors import (
	NameErrorHS,
	ResourceLimitErrorHS,
	RuntimeErrorHS,
	SecurityErrorHS,
	TypeErrorHS,
)
from app.services.hscript.limits import ResourceLimits
from app.services.hscript.values import HFunction, HModule, HTable


class _ReturnSignal(Exception):
	def __init__(self, value: Any):
		self.value = value


class _BreakSignal(Exception):
	pass


class _ContinueSignal(Exception):
	pass


class Interpreter:
	def __init__(
		self,
		*,
		globals_env: dict[str, Any],
		limits: ResourceLimits | None = None,
	):
		self.limits = limits or ResourceLimits.default()
		self.globals = globals_env
		self.locals: dict[str, Any] = {}
		self.steps = 0
		self.call_depth = 0
		self.started_at = time.monotonic()
		self.function_defs = 0

	def run(self, module: ast.Module) -> None:
		self._exec_block(module.body, self.globals)

	# --- exec ---

	def _exec_block(self, body: list[Any], env: dict[str, Any]) -> None:
		for stmt in body:
			self._exec_stmt(stmt, env)

	def _exec_stmt(self, stmt: Any, env: dict[str, Any]) -> None:
		self._tick(stmt)
		if isinstance(stmt, ast.Assign):
			if stmt.target.startswith("_"):
				raise SecurityErrorHS("نام متغیر با _ مجاز نیست", line=stmt.line, column=stmt.column)
			env[stmt.target] = self._eval(stmt.value, env)
			return
		if isinstance(stmt, ast.ExprStmt):
			self._eval(stmt.value, env)
			return
		if isinstance(stmt, ast.If):
			if self._truthy(self._eval(stmt.test, env)):
				self._exec_block(stmt.body, env)
			elif stmt.orelse:
				self._exec_block(stmt.orelse, env)
			return
		if isinstance(stmt, ast.For):
			iterable = self._eval(stmt.iter, env)
			self._iterate(iterable, stmt.target, stmt.body, env, line=stmt.line)
			return
		if isinstance(stmt, ast.While):
			count = 0
			while self._truthy(self._eval(stmt.test, env)):
				count += 1
				if count > self.limits.max_loop_iterations:
					raise ResourceLimitErrorHS("سقف تکرار while", line=stmt.line, column=stmt.column)
				try:
					self._exec_block(stmt.body, env)
				except _BreakSignal:
					break
				except _ContinueSignal:
					continue
			return
		if isinstance(stmt, ast.FunctionDef):
			self.function_defs += 1
			if self.function_defs > self.limits.max_function_defs:
				raise ResourceLimitErrorHS("تعداد توابع بیش از حد", line=stmt.line)
			# closure از کپی سطحی env فعلی
			closure = dict(env)
			env[stmt.name] = HFunction(
				name=stmt.name,
				params=list(stmt.params),
				body=stmt.body,
				closure=closure,
				line=stmt.line,
			)
			return
		if isinstance(stmt, ast.Return):
			val = None if stmt.value is None else self._eval(stmt.value, env)
			raise _ReturnSignal(val)
		if isinstance(stmt, ast.Pass):
			return
		if isinstance(stmt, ast.Break):
			raise _BreakSignal()
		if isinstance(stmt, ast.Continue):
			raise _ContinueSignal()
		raise RuntimeErrorHS(f"دستور پشتیبانی‌نشده: {type(stmt).__name__}", line=getattr(stmt, "line", None))

	def _iterate(self, iterable: Any, target: str, body: list[Any], env: dict[str, Any], *, line: int) -> None:
		if isinstance(iterable, HTable):
			seq = iterable.rows
		elif isinstance(iterable, (list, tuple)):
			seq = list(iterable)
		elif isinstance(iterable, dict):
			seq = list(iterable.keys())
		elif isinstance(iterable, str):
			seq = list(iterable)
		else:
			raise TypeErrorHS("شیء قابل پیمایش نیست", line=line)
		if len(seq) > self.limits.max_loop_iterations:
			raise ResourceLimitErrorHS("تعداد تکرار for بیش از حد", line=line)
		for item in seq:
			env[target] = item
			try:
				self._exec_block(body, env)
			except _BreakSignal:
				break
			except _ContinueSignal:
				continue

	# --- eval ---

	def _eval(self, node: Any, env: dict[str, Any]) -> Any:
		self._tick(node)
		if isinstance(node, ast.Literal):
			return node.value
		if isinstance(node, ast.Name):
			return self._lookup(node.id, env, line=node.line, column=node.column)
		if isinstance(node, ast.UnaryOp):
			return self._eval_unary(node, env)
		if isinstance(node, ast.BinOp):
			return self._eval_binop(node, env)
		if isinstance(node, ast.BoolOp):
			return self._eval_boolop(node, env)
		if isinstance(node, ast.Compare):
			return self._eval_compare(node, env)
		if isinstance(node, ast.Attribute):
			return self._eval_attr(node, env)
		if isinstance(node, ast.Subscript):
			return self._eval_subscript(node, env)
		if isinstance(node, ast.Call):
			return self._eval_call(node, env)
		if isinstance(node, ast.ListExpr):
			elts = [self._eval(e, env) for e in node.elts]
			if len(elts) > self.limits.max_list_size:
				raise ResourceLimitErrorHS("اندازه لیست بیش از حد", line=node.line)
			return elts
		if isinstance(node, ast.DictExpr):
			if len(node.keys) > self.limits.max_dict_size:
				raise ResourceLimitErrorHS("اندازه dict بیش از حد", line=node.line)
			out: dict[Any, Any] = {}
			for k_n, v_n in zip(node.keys, node.values):
				k = self._eval(k_n, env)
				if not isinstance(k, (str, int, float, bool)) and k is not None:
					raise TypeErrorHS("کلید dict باید ساده باشد", line=node.line)
				out[k] = self._eval(v_n, env)
			return out
		raise RuntimeErrorHS(f"عبارت پشتیبانی‌نشده: {type(node).__name__}", line=getattr(node, "line", None))

	def _lookup(self, name: str, env: dict[str, Any], *, line: int | None, column: int | None) -> Any:
		if name.startswith("__"):
			raise SecurityErrorHS(f"دسترسی به '{name}' ممنوع است", line=line, column=column)
		if name in env:
			return env[name]
		if name in self.globals:
			return self.globals[name]
		raise NameErrorHS(f"نام تعریف‌نشده: {name}", line=line, column=column)

	def _eval_unary(self, node: ast.UnaryOp, env: dict[str, Any]) -> Any:
		v = self._eval(node.operand, env)
		if node.op == "not":
			return not self._truthy(v)
		if node.op == "-":
			if isinstance(v, (int, float)) and not isinstance(v, bool):
				return -v
			raise TypeErrorHS("عملگر - فقط برای عدد", line=node.line)
		if node.op == "+":
			if isinstance(v, (int, float)) and not isinstance(v, bool):
				return +v
			raise TypeErrorHS("عملگر + فقط برای عدد", line=node.line)
		raise RuntimeErrorHS(f"عملگر یگانه ناشناخته: {node.op}", line=node.line)

	def _eval_binop(self, node: ast.BinOp, env: dict[str, Any]) -> Any:
		left = self._eval(node.left, env)
		right = self._eval(node.right, env)
		op = node.op
		try:
			if op == "+":
				if isinstance(left, str) or isinstance(right, str):
					result = str(left) + str(right)
					if len(result) > self.limits.max_string_size:
						raise ResourceLimitErrorHS("رشته خیلی طولانی", line=node.line)
					return result
				if isinstance(left, list) and isinstance(right, list):
					result = left + right
					if len(result) > self.limits.max_list_size:
						raise ResourceLimitErrorHS("لیست خیلی بزرگ", line=node.line)
					return result
				return left + right
			if op == "-":
				return left - right
			if op == "*":
				if isinstance(left, str) and isinstance(right, int):
					if right < 0 or right > 10_000 or len(left) * right > self.limits.max_string_size:
						raise ResourceLimitErrorHS("تکرار رشته بیش از حد", line=node.line)
					return left * right
				if isinstance(right, str) and isinstance(left, int):
					if left < 0 or left > 10_000 or len(right) * left > self.limits.max_string_size:
						raise ResourceLimitErrorHS("تکرار رشته بیش از حد", line=node.line)
					return right * left
				return left * right
			if op == "/":
				if right == 0:
					raise RuntimeErrorHS("تقسیم بر صفر", line=node.line)
				return left / right
			if op == "%":
				if right == 0:
					raise RuntimeErrorHS("مانده بر صفر", line=node.line)
				return left % right
		except ResourceLimitErrorHS:
			raise
		except Exception as exc:
			raise TypeErrorHS(f"عملگر {op} روی انواع نامعتبر", line=node.line) from exc
		raise RuntimeErrorHS(f"عملگر ناشناخته: {op}", line=node.line)

	def _eval_boolop(self, node: ast.BoolOp, env: dict[str, Any]) -> Any:
		if node.op == "and":
			val: Any = True
			for v in node.values:
				val = self._eval(v, env)
				if not self._truthy(val):
					return val
			return val
		if node.op == "or":
			val = False
			for v in node.values:
				val = self._eval(v, env)
				if self._truthy(val):
					return val
			return val
		raise RuntimeErrorHS(f"عملگر منطقی ناشناخته: {node.op}", line=node.line)

	def _eval_compare(self, node: ast.Compare, env: dict[str, Any]) -> bool:
		left = self._eval(node.left, env)
		ops_map = {
			"==": operator.eq,
			"!=": operator.ne,
			"<": operator.lt,
			"<=": operator.le,
			">": operator.gt,
			">=": operator.ge,
		}
		for op, comp_node in zip(node.ops, node.comparators):
			right = self._eval(comp_node, env)
			fn = ops_map.get(op)
			if fn is None:
				raise RuntimeErrorHS(f"مقایسه ناشناخته: {op}", line=node.line)
			try:
				ok = bool(fn(left, right))
			except Exception as exc:
				raise TypeErrorHS("مقایسه نامعتبر", line=node.line) from exc
			if not ok:
				return False
			left = right
		return True

	def _eval_attr(self, node: ast.Attribute, env: dict[str, Any]) -> Any:
		if node.attr.startswith("_"):
			raise SecurityErrorHS(f"ویژگی '{node.attr}' ممنوع است", line=node.line, column=node.column)
		obj = self._eval(node.value, env)
		if isinstance(obj, HModule):
			return obj.get_attr(node.attr, line=node.line)
		if isinstance(obj, HTable):
			method = getattr(obj, node.attr, None)
			if callable(method) and not node.attr.startswith("_"):
				return method
			raise SecurityErrorHS(f"متد جدول نامعتبر: {node.attr}", line=node.line)
		if isinstance(obj, dict):
			if node.attr in obj:
				return obj[node.attr]
			raise NameErrorHS(f"کلید '{node.attr}' در dict نیست", line=node.line)
		raise SecurityErrorHS(f"دسترسی ویژگی روی {type(obj).__name__} مجاز نیست", line=node.line)

	def _eval_subscript(self, node: ast.Subscript, env: dict[str, Any]) -> Any:
		obj = self._eval(node.value, env)
		index = self._eval(node.index, env)
		try:
			if isinstance(obj, dict):
				return obj[index]
			if isinstance(obj, (list, str, tuple)):
				return obj[index]
			if isinstance(obj, HTable):
				return obj.rows[index]
		except (KeyError, IndexError, TypeError) as exc:
			raise RuntimeErrorHS("اندیس نامعتبر", line=node.line) from exc
		raise TypeErrorHS("شیء قابل اندیس‌گذاری نیست", line=node.line)

	def _eval_call(self, node: ast.Call, env: dict[str, Any]) -> Any:
		func = self._eval(node.func, env)
		args = [self._eval(a, env) for a in node.args]
		kwargs = {k: self._eval(v, env) for k, v in node.keywords.items()}
		# مسدود کردن kwargs خطرناک
		for k in kwargs:
			if k.startswith("_") or k in {"db", "session", "request", "app", "settings", "env"}:
				raise SecurityErrorHS(f"آرگومان ممنوع: {k}", line=node.line)

		if isinstance(func, HFunction):
			return self._call_user_fn(func, args, kwargs, line=node.line)
		if callable(func):
			try:
				return func(*args, **kwargs)
			except (SecurityErrorHS, ResourceLimitErrorHS, TypeErrorHS, RuntimeErrorHS, NameErrorHS):
				raise
			except TypeError as exc:
				raise TypeErrorHS(str(exc), line=node.line) from exc
			except Exception as exc:
				raise RuntimeErrorHS(f"خطا در فراخوانی: {exc}", line=node.line) from exc
		raise TypeErrorHS("شیء قابل فراخوانی نیست", line=node.line)

	def _call_user_fn(self, fn: HFunction, args: list[Any], kwargs: dict[str, Any], *, line: int) -> Any:
		if kwargs:
			raise TypeErrorHS("توابع کاربر فقط آرگومان موقعیتی می‌پذیرند", line=line)
		if len(args) != len(fn.params):
			raise TypeErrorHS(f"تابع {fn.name} انتظار {len(fn.params)} آرگومان دارد", line=line)
		self.call_depth += 1
		if self.call_depth > self.limits.max_call_depth:
			raise ResourceLimitErrorHS("عمق فراخوانی بیش از حد", line=line)
		local_env = dict(fn.closure)
		for p, a in zip(fn.params, args):
			local_env[p] = a
		try:
			self._exec_block(fn.body, local_env)
			return None
		except _ReturnSignal as ret:
			return ret.value
		finally:
			self.call_depth -= 1

	def _truthy(self, value: Any) -> bool:
		if value is None or value is False:
			return False
		if value is True:
			return True
		if isinstance(value, (int, float)) and value == 0:
			return False
		if isinstance(value, (str, list, dict, tuple, HTable)) and len(value) == 0:
			return False
		return True

	def _tick(self, node: Any) -> None:
		self.steps += 1
		if self.steps > self.limits.max_steps:
			raise ResourceLimitErrorHS(
				"سقف گام‌های اجرا",
				line=getattr(node, "line", None),
				column=getattr(node, "column", None),
			)
		elapsed_ms = (time.monotonic() - self.started_at) * 1000
		if elapsed_ms > self.limits.max_execution_ms:
			raise ResourceLimitErrorHS(
				"زمان اجرا بیش از حد",
				line=getattr(node, "line", None),
				column=getattr(node, "column", None),
			)
