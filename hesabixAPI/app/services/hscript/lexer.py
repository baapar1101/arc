"""Lexer با پشتیبانی Indent/Dedent شبیه Python."""

from __future__ import annotations

from typing import Any

from app.services.hscript.errors import SecurityErrorHS, SyntaxErrorHS
from app.services.hscript.tokens import KEYWORDS, Token, TokenType


class Lexer:
	def __init__(self, source: str, *, max_source_bytes: int = 100_000):
		encoded = source.encode("utf-8")
		if len(encoded) > max_source_bytes:
			raise SecurityErrorHS(f"اندازه اسکریپت از سقف {max_source_bytes} بایت بیشتر است")
		# کاراکترهای خطرناک کنترل
		if "\x00" in source:
			raise SecurityErrorHS("کاراکتر null در سورس مجاز نیست")
		self.source = source.replace("\r\n", "\n").replace("\r", "\n")
		self.pos = 0
		self.line = 1
		self.column = 1
		self.tokens: list[Token] = []
		self.indent_stack: list[int] = [0]
		self.at_line_start = True

	def tokenize(self) -> list[Token]:
		while not self._is_at_end():
			if self.at_line_start:
				self._handle_indent()
				if self._is_at_end():
					break
				if self._peek() == "\n":
					self._advance()
					continue
				self.at_line_start = False
			self._scan_token()
		while len(self.indent_stack) > 1:
			self.indent_stack.pop()
			self.tokens.append(Token(TokenType.DEDENT, None, self.line, self.column))
		self.tokens.append(Token(TokenType.EOF, None, self.line, self.column))
		return self.tokens

	def _handle_indent(self) -> None:
		spaces = 0
		while self._peek() in (" ", "\t"):
			ch = self._advance()
			spaces += 4 if ch == "\t" else 1
		# خط خالی یا فقط کامنت
		if self._peek() in ("\n", "") or self._peek() == "#":
			return
		current = self.indent_stack[-1]
		if spaces == current:
			return
		if spaces > current:
			self.indent_stack.append(spaces)
			self.tokens.append(Token(TokenType.INDENT, spaces, self.line, 1))
			return
		while spaces < self.indent_stack[-1]:
			self.indent_stack.pop()
			self.tokens.append(Token(TokenType.DEDENT, None, self.line, 1))
		if spaces != self.indent_stack[-1]:
			raise SyntaxErrorHS("تورفتگی نامعتبر", line=self.line, column=1)

	def _scan_token(self) -> None:
		ch = self._advance()
		if ch == " ":
			return
		if ch == "\t":
			return
		if ch == "#":
			while self._peek() not in ("\n", ""):
				self._advance()
			return
		if ch == "\n":
			self.tokens.append(Token(TokenType.NEWLINE, "\n", self.line - 1, self.column))
			self.at_line_start = True
			return

		line, col = self.line, self.column - 1
		if ch == "+":
			self.tokens.append(Token(TokenType.PLUS, "+", line, col))
		elif ch == "-":
			self.tokens.append(Token(TokenType.MINUS, "-", line, col))
		elif ch == "*":
			self.tokens.append(Token(TokenType.STAR, "*", line, col))
		elif ch == "/":
			self.tokens.append(Token(TokenType.SLASH, "/", line, col))
		elif ch == "%":
			self.tokens.append(Token(TokenType.PERCENT, "%", line, col))
		elif ch == "(":
			self.tokens.append(Token(TokenType.LPAREN, "(", line, col))
		elif ch == ")":
			self.tokens.append(Token(TokenType.RPAREN, ")", line, col))
		elif ch == "[":
			self.tokens.append(Token(TokenType.LBRACK, "[", line, col))
		elif ch == "]":
			self.tokens.append(Token(TokenType.RBRACK, "]", line, col))
		elif ch == "{":
			self.tokens.append(Token(TokenType.LBRACE, "{", line, col))
		elif ch == "}":
			self.tokens.append(Token(TokenType.RBRACE, "}", line, col))
		elif ch == ",":
			self.tokens.append(Token(TokenType.COMMA, ",", line, col))
		elif ch == ":":
			self.tokens.append(Token(TokenType.COLON, ":", line, col))
		elif ch == ".":
			self.tokens.append(Token(TokenType.DOT, ".", line, col))
		elif ch == "=":
			if self._match("="):
				self.tokens.append(Token(TokenType.EQEQ, "==", line, col))
			else:
				self.tokens.append(Token(TokenType.EQ, "=", line, col))
		elif ch == "!":
			if self._match("="):
				self.tokens.append(Token(TokenType.NE, "!=", line, col))
			else:
				raise SyntaxErrorHS("انتظار '!='", line=line, column=col)
		elif ch == "<":
			if self._match("="):
				self.tokens.append(Token(TokenType.LE, "<=", line, col))
			else:
				self.tokens.append(Token(TokenType.LT, "<", line, col))
		elif ch == ">":
			if self._match("="):
				self.tokens.append(Token(TokenType.GE, ">=", line, col))
			else:
				self.tokens.append(Token(TokenType.GT, ">", line, col))
		elif ch in ('"', "'"):
			self._string(ch, line, col)
		elif ch.isdigit():
			self._number(ch, line, col)
		elif ch.isalpha() or ch == "_":
			self._identifier(ch, line, col)
		else:
			raise SyntaxErrorHS(f"کاراکتر غیرمجاز: {ch!r}", line=line, column=col)

	def _string(self, quote: str, line: int, col: int) -> None:
		chars: list[str] = []
		while not self._is_at_end() and self._peek() != quote:
			ch = self._advance()
			if ch == "\n":
				raise SyntaxErrorHS("رشته چندخطی مجاز نیست", line=line, column=col)
			if ch == "\\":
				esc = self._advance()
				mapping = {"n": "\n", "t": "\t", "\\": "\\", "'": "'", '"': '"'}
				if esc not in mapping:
					raise SyntaxErrorHS(f"escape غیرمجاز: \\{esc}", line=line, column=col)
				chars.append(mapping[esc])
			else:
				chars.append(ch)
		if self._is_at_end():
			raise SyntaxErrorHS("رشته بسته نشده", line=line, column=col)
		self._advance()  # closing quote
		self.tokens.append(Token(TokenType.STRING, "".join(chars), line, col))

	def _number(self, first: str, line: int, col: int) -> None:
		num = first
		while self._peek().isdigit():
			num += self._advance()
		if self._peek() == "." and self._peek_next().isdigit():
			num += self._advance()
			while self._peek().isdigit():
				num += self._advance()
			self.tokens.append(Token(TokenType.NUMBER, float(num), line, col))
		else:
			self.tokens.append(Token(TokenType.NUMBER, int(num), line, col))

	def _identifier(self, first: str, line: int, col: int) -> None:
		ident = first
		while self._peek().isalnum() or self._peek() == "_":
			ident += self._advance()
		# کلمات ممنوعه شبیه پایتون که عمداً پشتیبانی نمی‌شوند
		forbidden = {
			"import", "from", "class", "global", "nonlocal", "lambda",
			"try", "except", "finally", "raise", "with", "as", "assert",
			"async", "await", "yield", "del", "exec", "eval", "__import__",
		}
		if ident in forbidden:
			raise SecurityErrorHS(f"کلمه کلیدی ممنوع: {ident}", line=line, column=col)
		tt = KEYWORDS.get(ident, TokenType.IDENT)
		value: Any = ident
		if tt == TokenType.TRUE:
			value = True
		elif tt == TokenType.FALSE:
			value = False
		elif tt == TokenType.NULL:
			value = None
		self.tokens.append(Token(tt, value, line, col))

	def _advance(self) -> str:
		ch = self.source[self.pos]
		self.pos += 1
		if ch == "\n":
			self.line += 1
			self.column = 1
		else:
			self.column += 1
		return ch

	def _match(self, expected: str) -> bool:
		if self._peek() == expected:
			self._advance()
			return True
		return False

	def _peek(self) -> str:
		if self._is_at_end():
			return ""
		return self.source[self.pos]

	def _peek_next(self) -> str:
		if self.pos + 1 >= len(self.source):
			return ""
		return self.source[self.pos + 1]

	def _is_at_end(self) -> bool:
		return self.pos >= len(self.source)
