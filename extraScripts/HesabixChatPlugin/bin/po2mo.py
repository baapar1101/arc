#!/usr/bin/env python3
"""
مبدل PO → MO (GNU) برای فایل‌های افزونه؛ بدون وابستگی.
"""
import re
import struct
import sys
from pathlib import Path


def _unescape_one(s: str) -> str:
    return (
        s.replace("\\\\", "\\")
        .replace('\\"', '"')
        .replace("\\n", "\n")
        .replace("\\t", "\t")
    )


def _collect_quoted_parts(after_kw: str) -> list[str]:
    return [
        _unescape_one(m.group("s"))
        for m in re.finditer(
            r'"(?P<s>(?:\\.|[^"\\])*)"', after_kw
        )
    ]


def _read_string_continuation(lines: list[str], start: int) -> tuple[str, int]:
    """
    خط start باید با msgid یا msgstr شروع شود. مقدار کامل رشته و ایندکس خط بعد از بلوک.
    """
    line = lines[start]
    for kw in ("msgid ", "msgstr "):
        if line.lstrip().startswith(kw):
            after = line.split(kw, 1)[1]
            segs: list[str] = []
            segs.extend(_collect_quoted_parts(after))
            nxt = start + 1
            while nxt < len(lines):
                s = lines[nxt].lstrip()
                if s.startswith('"'):
                    segs.extend(_collect_quoted_parts(s))
                    nxt += 1
                else:
                    break
            return "".join(segs), nxt
    return "", start + 1


def parse_po(text: str) -> list[tuple[bytes, bytes]]:
    lines: list[str] = []
    for raw in text.splitlines():
        t = raw.strip()
        if t.startswith("#") or t == "":
            continue
        lines.append(raw)
    out: list[tuple[bytes, bytes]] = []
    i = 0
    while i < len(lines):
        if not lines[i].lstrip().startswith("msgid "):
            i += 1
            continue
        msgid, j = _read_string_continuation(lines, i)
        if j >= len(lines) or not lines[j].lstrip().startswith("msgstr "):
            i += 1
            continue
        msgstr, k = _read_string_continuation(lines, j)
        out.append((msgid.encode("utf-8"), msgstr.encode("utf-8")))
        i = k
    return out


def build_mo(entries: list[tuple[bytes, bytes]]) -> bytes:
    pairs = sorted(entries, key=lambda p: p[0])
    n = len(pairs)
    o_table_off = 7 * 4
    t_table_off = o_table_off + 8 * n
    str_start = t_table_off + 8 * n
    o_keys: list[tuple[int, int]] = []
    t_keys: list[tuple[int, int]] = []
    blob = b""
    # طول و بایت رشته بدون تغییری که Python gettext (و C) انتظار دارند: بدون nul اضافه
    # در بافر و با mlen=0 فقط برای msgid هدر
    pos = str_start
    for k, v in pairs:
        o_keys.append((len(k), pos))
        if k:
            blob += k
            pos += len(k)
    for k, v in pairs:
        t_keys.append((len(v), pos))
        if v:
            blob += v
            pos += len(v)
    o_tab = b"".join(struct.pack("<II", a, b) for a, b in o_keys)
    t_tab = b"".join(struct.pack("<II", a, b) for a, b in t_keys)
    header = struct.pack(
        "<7I",
        0x950412DE,
        0,
        n,
        o_table_off,
        t_table_off,
        0,
        0,
    )
    out = header + o_tab + t_tab + blob
    # مفسر gettext پایتون به شرط mend < buflen نیاز دارد (نه ==)
    return out + b"\0"


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: po2mo.py <file.po> [out.mo]", file=sys.stderr)
        return 1
    po_path = Path(sys.argv[1])
    mo_path = Path(sys.argv[2]) if len(sys.argv) > 2 else po_path.with_suffix(".mo")
    text = po_path.read_text(encoding="utf-8")
    entries = parse_po(text)
    if not entries:
        print("No entries in", po_path, file=sys.stderr)
        return 1
    mo_path.write_bytes(build_mo(entries))
    print("Wrote", mo_path, "({} entries)".format(len(entries)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
