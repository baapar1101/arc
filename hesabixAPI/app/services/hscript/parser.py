"""Parser بازگشتی برای زیرمجموعهٔ شبه‌پایتون HScript."""

from __future__ import annotations

from typing import Any, Optional

from app.services.hscript import ast_nodes as ast
from app.services.hscript.errors import SyntaxErrorHS
from app.services.hscript.tokens import Token, TokenType


class Parser:
	def __init__(self, tokens: list[Token]):
		self.tokens = tokens
		self.current = 0

	def parse(self) -> ast.Module:
		body: list[Any] = []
		self._skip_newlines()
		while not self._check(TokenType.EOF):
			body.append(self._statement())
			self._skip_newlines()
		return ast.Module(body=body, line=1, column=1)

	def _statement(self) -> Any:
		if self._check(TokenType.IF):
			return self._if_stmt()
		if self._check(TokenType.FOR):
			return self._for_stmt()
		if self._check(TokenType.WHILE):
			return self._while_stmt()
		if self._check(TokenType.DEF):
			return self._def_stmt()
		if self._check(TokenType.RETURN):
			return self._return_stmt()
		if self._check(TokenType.PASS):
			tok = self._advance()
			self._consume_newline_or_dedent_end()
			return ast.Pass(line=tok.line, column=tok.column)
		if self._check(TokenType.BREAK):
			tok = self._advance()
			self._consume_newline_or_dedent_end()
			return ast.Break(line=tok.line, column=tok.column)
		if self._check(TokenType.CONTINUE):
			tok = self._advance()
			self._consume_newline_or_dedent_end()
			return ast.Continue(line=tok.line, column=tok.column)
		# assign or expr
		if self._check(TokenType.IDENT) and self._check_next(TokenType.EQ):
			return self._assign_stmt()
		expr = self._expression()
		self._consume_newline_or_dedent_end()
		return ast.ExprStmt(value=expr, line=expr.line, column=expr.column)

	def _assign_stmt(self) -> ast.Assign:
		name_tok = self._consume(TokenType.IDENT, "انتظار نام متغیر")
		eq = self._consume(TokenType.EQ, "انتظار '='")
		value = self._expression()
		self._consume_newline_or_dedent_end()
		return ast.Assign(target=str(name_tok.value), value=value, line=name_tok.line, column=name_tok.column)

	def _if_stmt(self) -> ast.If:
		tok = self._consume(TokenType.IF, "انتظار if")
		test = self._expression()
		self._consume(TokenType.COLON, "انتظار ':' بعد از if")
		self._consume(TokenType.NEWLINE, "انتظار خط جدید بعد از ':'")
		body = self._block()
		orelse: list[Any] = []
		if self._match(TokenType.ELIF):
			# تبدیل elif به if تو در تو در orelse
			# بعد از match، current روی توکن بعد از ELIF است — باید expression بخوانیم
			# اما _match قبلاً ELIF را خورده؛ پس مثل if ادامه می‌دهیم با ساخت If تو در تو
			self.current -= 1  # برگرداندن ELIF برای reuse با _if_like
			orelse = [self._elif_chain()]
		elif self._match(TokenType.ELSE):
			self._consume(TokenType.COLON, "انتظار ':' بعد از else")
			self._consume(TokenType.NEWLINE, "انتظار خط جدید")
			orelse = self._block()
		return ast.If(test=test, body=body, orelse=orelse, line=tok.line, column=tok.column)

	def _elif_chain(self) -> ast.If:
		tok = self._consume(TokenType.ELIF, "انتظار elif")
		test = self._expression()
		self._consume(TokenType.COLON, "انتظار ':'")
		self._consume(TokenType.NEWLINE, "انتظار خط جدید")
		body = self._block()
		orelse: list[Any] = []
		if self._match(TokenType.ELIF):
			self.current -= 1
			orelse = [self._elif_chain()]
		elif self._match(TokenType.ELSE):
			self._consume(TokenType.COLON, "انتظار ':'")
			self._consume(TokenType.NEWLINE, "انتظار خط جدید")
			orelse = self._block()
		return ast.If(test=test, body=body, orelse=orelse, line=tok.line, column=tok.column)

	def _for_stmt(self) -> ast.For:
		tok = self._consume(TokenType.FOR, "انتظار for")
		target = self._consume(TokenType.IDENT, "انتظار نام متغیر حلقه")
		self._consume(TokenType.IN, "انتظار in")
		iterable = self._expression()
		self._consume(TokenType.COLON, "انتظار ':'")
		self._consume(TokenType.NEWLINE, "انتظار خط جدید")
		body = self._block()
		return ast.For(target=str(target.value), iter=iterable, body=body, line=tok.line, column=tok.column)

	def _while_stmt(self) -> ast.While:
		tok = self._consume(TokenType.WHILE, "انتظار while")
		test = self._expression()
		self._consume(TokenType.COLON, "انتظار ':'")
		self._consume(TokenType.NEWLINE, "انتظار خط جدید")
		body = self._block()
		return ast.While(test=test, body=body, line=tok.line, column=tok.column)

	def _def_stmt(self) -> ast.FunctionDef:
		tok = self._consume(TokenType.DEF, "انتظار def")
		name = self._consume(TokenType.IDENT, "انتظار نام تابع")
		self._consume(TokenType.LPAREN, "انتظار '('")
		params: list[str] = []
		if not self._check(TokenType.RPAREN):
			params.append(str(self._consume(TokenType.IDENT, "انتظار پارامتر").value))
			while self._match(TokenType.COMMA):
				params.append(str(self._consume(TokenType.IDENT, "انتظار پارامتر").value))
		self._consume(TokenType.RPAREN, "انتظار ')'")
		self._consume(TokenType.COLON, "انتظار ':'")
		self._consume(TokenType.NEWLINE, "انتظار خط جدید")
		body = self._block()
		return ast.FunctionDef(name=str(name.value), params=params, body=body, line=tok.line, column=tok.column)

	def _return_stmt(self) -> ast.Return:
		tok = self._consume(TokenType.RETURN, "انتظار return")
		value = None
		if not self._check(TokenType.NEWLINE) and not self._check(TokenType.DEDENT) and not self._check(TokenType.EOF):
			value = self._expression()
		self._consume_newline_or_dedent_end()
		return ast.Return(value=value, line=tok.line, column=tok.column)

	def _block(self) -> list[Any]:
		self._consume(TokenType.INDENT, "انتظار تورفتگی")
		body: list[Any] = []
		while not self._check(TokenType.DEDENT) and not self._check(TokenType.EOF):
			self._skip_newlines()
			if self._check(TokenType.DEDENT) or self._check(TokenType.EOF):
				break
			body.append(self._statement())
			self._skip_newlines()
		self._consume(TokenType.DEDENT, "انتظار پایان بلوک")
		if not body:
			raise SyntaxErrorHS("بلوک خالی مجاز نیست؛ از pass استفاده کنید", line=self._peek().line, column=self._peek().column)
		return body

	# --- expressions ---

	def _expression(self) -> Any:
		return self._or()

	def _or(self) -> Any:
		expr = self._and()
		while self._match(TokenType.OR):
			right = self._and()
			if isinstance(expr, ast.BoolOp) and expr.op == "or":
				expr.values.append(right)
			else:
				expr = ast.BoolOp(op="or", values=[expr, right], line=expr.line, column=expr.column)
		return expr

	def _and(self) -> Any:
		expr = self._not()
		while self._match(TokenType.AND):
			right = self._not()
			if isinstance(expr, ast.BoolOp) and expr.op == "and":
				expr.values.append(right)
			else:
				expr = ast.BoolOp(op="and", values=[expr, right], line=expr.line, column=expr.column)
		return expr

	def _not(self) -> Any:
		if self._match(TokenType.NOT):
			tok = self._previous()
			operand = self._not()
			return ast.UnaryOp(op="not", operand=operand, line=tok.line, column=tok.column)
		return self._comparison()

	def _comparison(self) -> Any:
		expr = self._term()
		ops: list[str] = []
		comps: list[Any] = []
		while True:
			if self._match(TokenType.EQEQ):
				ops.append("==")
				comps.append(self._term())
			elif self._match(TokenType.NE):
				ops.append("!=")
				comps.append(self._term())
			elif self._match(TokenType.LT):
				ops.append("<")
				comps.append(self._term())
			elif self._match(TokenType.LE):
				ops.append("<=")
				comps.append(self._term())
			elif self._match(TokenType.GT):
				ops.append(">")
				comps.append(self._term())
			elif self._match(TokenType.GE):
				ops.append(">=")
				comps.append(self._term())
			else:
				break
		if ops:
			return ast.Compare(left=expr, ops=ops, comparators=comps, line=expr.line, column=expr.column)
		return expr

	def _term(self) -> Any:
		expr = self._factor()
		while True:
			if self._match(TokenType.PLUS):
				op = "+"
			elif self._match(TokenType.MINUS):
				op = "-"
			else:
				break
			right = self._factor()
			expr = ast.BinOp(left=expr, op=op, right=right, line=expr.line, column=expr.column)
		return expr

	def _factor(self) -> Any:
		expr = self._unary()
		while True:
			if self._match(TokenType.STAR):
				op = "*"
			elif self._match(TokenType.SLASH):
				op = "/"
			elif self._match(TokenType.PERCENT):
				op = "%"
			else:
				break
			right = self._unary()
			expr = ast.BinOp(left=expr, op=op, right=right, line=expr.line, column=expr.column)
		return expr

	def _unary(self) -> Any:
		if self._match(TokenType.MINUS):
			tok = self._previous()
			return ast.UnaryOp(op="-", operand=self._unary(), line=tok.line, column=tok.column)
		if self._match(TokenType.PLUS):
			tok = self._previous()
			return ast.UnaryOp(op="+", operand=self._unary(), line=tok.line, column=tok.column)
		return self._call_attr()

	def _call_attr(self) -> Any:
		expr = self._primary()
		while True:
			if self._match(TokenType.LPAREN):
				args, kwargs = self._arguments()
				self._consume(TokenType.RPAREN, "انتظار ')'")
				expr = ast.Call(func=expr, args=args, keywords=kwargs, line=expr.line, column=expr.column)
			elif self._match(TokenType.DOT):
				attr = self._consume(TokenType.IDENT, "انتظار نام ویژگی")
				expr = ast.Attribute(value=expr, attr=str(attr.value), line=expr.line, column=expr.column)
			elif self._match(TokenType.LBRACK):
				index = self._expression()
				self._consume(TokenType.RBRACK, "انتظار ']'")
				expr = ast.Subscript(value=expr, index=index, line=expr.line, column=expr.column)
			else:
				break
		return expr

	def _arguments(self) -> tuple[list[Any], dict[str, Any]]:
		args: list[Any] = []
		kwargs: dict[str, Any] = {}
		if self._check(TokenType.RPAREN):
			return args, kwargs
		while True:
			if self._check(TokenType.IDENT) and self._check_next(TokenType.EQ):
				key = str(self._advance().value)
				self._consume(TokenType.EQ, "انتظار '='")
				kwargs[key] = self._expression()
			else:
				if kwargs:
					raise SyntaxErrorHS("آرگومان موقعیتی بعد از نام‌دار مجاز نیست", line=self._peek().line, column=self._peek().column)
				args.append(self._expression())
			if not self._match(TokenType.COMMA):
				break
		return args, kwargs

	def _primary(self) -> Any:
		if self._match(TokenType.NUMBER):
			tok = self._previous()
			return ast.Literal(value=tok.value, line=tok.line, column=tok.column)
		if self._match(TokenType.STRING):
			tok = self._previous()
			return ast.Literal(value=tok.value, line=tok.line, column=tok.column)
		if self._match(TokenType.TRUE) or self._match(TokenType.FALSE) or self._match(TokenType.NULL):
			tok = self._previous()
			return ast.Literal(value=tok.value, line=tok.line, column=tok.column)
		if self._match(TokenType.IDENT):
			tok = self._previous()
			return ast.Name(id=str(tok.value), line=tok.line, column=tok.column)
		if self._match(TokenType.LPAREN):
			expr = self._expression()
			self._consume(TokenType.RPAREN, "انتظار ')'")
			return expr
		if self._match(TokenType.LBRACK):
			tok = self._previous()
			elts: list[Any] = []
			if not self._check(TokenType.RBRACK):
				elts.append(self._expression())
				while self._match(TokenType.COMMA):
					if self._check(TokenType.RBRACK):
						break
					elts.append(self._expression())
			self._consume(TokenType.RBRACK, "انتظار ']'")
			return ast.ListExpr(elts=elts, line=tok.line, column=tok.column)
		if self._match(TokenType.LBRACE):
			tok = self._previous()
			keys: list[Any] = []
			vals: list[Any] = []
			if not self._check(TokenType.RBRACE):
				keys.append(self._expression())
				self._consume(TokenType.COLON, "انتظار ':' در dict")
				vals.append(self._expression())
				while self._match(TokenType.COMMA):
					if self._check(TokenType.RBRACE):
						break
					keys.append(self._expression())
					self._consume(TokenType.COLON, "انتظار ':' در dict")
					vals.append(self._expression())
			self._consume(TokenType.RBRACE, "انتظار '}'")
			return ast.DictExpr(keys=keys, values=vals, line=tok.line, column=tok.column)
		tok = self._peek()
		raise SyntaxErrorHS(f"عبارت غیرمنتظره: {tok.type.name}", line=tok.line, column=tok.column)

	# --- helpers ---

	def _consume_newline_or_dedent_end(self) -> None:
		if self._check(TokenType.NEWLINE):
			self._advance()
			return
		if self._check(TokenType.DEDENT) or self._check(TokenType.EOF):
			return
		# اجازه پایان فایل بدون newline
		if self._check(TokenType.ELIF) or self._check(TokenType.ELSE):
			return
		raise SyntaxErrorHS("انتظار پایان دستور (خط جدید)", line=self._peek().line, column=self._peek().column)

	def _skip_newlines(self) -> None:
		while self._match(TokenType.NEWLINE):
			pass

	def _match(self, t: TokenType) -> bool:
		if self._check(t):
			self._advance()
			return True
		return False

	def _consume(self, t: TokenType, message: str) -> Token:
		if self._check(t):
			return self._advance()
		tok = self._peek()
		raise SyntaxErrorHS(message, line=tok.line, column=tok.column)

	def _check(self, t: TokenType) -> bool:
		return self._peek().type == t

	def _check_next(self, t: TokenType) -> bool:
		if self.current + 1 >= len(self.tokens):
			return False
		return self.tokens[self.current + 1].type == t

	def _advance(self) -> Token:
		if not self._is_at_end():
			self.current += 1
		return self._previous()

	def _previous(self) -> Token:
		return self.tokens[self.current - 1]

	def _peek(self) -> Token:
		return self.tokens[self.current]

	def _is_at_end(self) -> bool:
		return self._peek().type == TokenType.EOF
