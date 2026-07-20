"""توکن‌های Lexer برای HScript."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, auto
from typing import Any, Optional


class TokenType(Enum):
	# literals
	NUMBER = auto()
	STRING = auto()
	TRUE = auto()
	FALSE = auto()
	NULL = auto()
	IDENT = auto()

	# keywords
	IF = auto()
	ELIF = auto()
	ELSE = auto()
	FOR = auto()
	IN = auto()
	WHILE = auto()
	DEF = auto()
	RETURN = auto()
	AND = auto()
	OR = auto()
	NOT = auto()
	PASS = auto()
	BREAK = auto()
	CONTINUE = auto()

	# symbols
	PLUS = auto()
	MINUS = auto()
	STAR = auto()
	SLASH = auto()
	PERCENT = auto()
	EQ = auto()
	EQEQ = auto()
	NE = auto()
	LT = auto()
	LE = auto()
	GT = auto()
	GE = auto()
	LPAREN = auto()
	RPAREN = auto()
	LBRACK = auto()
	RBRACK = auto()
	LBRACE = auto()
	RBRACE = auto()
	COMMA = auto()
	COLON = auto()
	DOT = auto()
	NEWLINE = auto()
	INDENT = auto()
	DEDENT = auto()
	EOF = auto()


KEYWORDS = {
	"if": TokenType.IF,
	"elif": TokenType.ELIF,
	"else": TokenType.ELSE,
	"for": TokenType.FOR,
	"in": TokenType.IN,
	"while": TokenType.WHILE,
	"def": TokenType.DEF,
	"return": TokenType.RETURN,
	"and": TokenType.AND,
	"or": TokenType.OR,
	"not": TokenType.NOT,
	"True": TokenType.TRUE,
	"False": TokenType.FALSE,
	"None": TokenType.NULL,
	"pass": TokenType.PASS,
	"break": TokenType.BREAK,
	"continue": TokenType.CONTINUE,
}


@dataclass
class Token:
	type: TokenType
	value: Any
	line: int
	column: int
