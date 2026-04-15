# Add expandBodyHeightToFitRows to each return DataTableConfig<...>(...) block missing it.
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent / "lib" / "pages"


def add_expand_blocks(text: str) -> tuple[str, int]:
    pattern = re.compile(r"return\s+DataTableConfig<[^>]+>\(")
    out: list[str] = []
    pos = 0
    inserts = 0
    for m in pattern.finditer(text):
        out.append(text[pos : m.end()])
        open_paren = m.end() - 1
        depth = 0
        k = open_paren
        while k < len(text):
            ch = text[k]
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    inner = text[open_paren + 1 : k]
                    if "expandBodyHeightToFitRows" not in inner:
                        inner_stripped = inner.rstrip()
                        sep = "" if inner_stripped.endswith(",") else ","
                        out.append(f"{sep}\n      expandBodyHeightToFitRows: true")
                        inserts += 1
                    pos = k + 1
                    break
            k += 1
        else:
            pos = m.end()
            break
    out.append(text[pos:])
    return "".join(out), inserts


def process_file(path: Path) -> int:
    raw = path.read_text(encoding="utf-8")
    if "DataTableWidget" not in raw:
        return 0
    if "expandBodyHeightToFitRows" in raw:
        return 0
    new_raw, n = add_expand_blocks(raw)
    if n:
        path.write_text(new_raw, encoding="utf-8")
    return n


def main() -> None:
    touched: list[str] = []
    for f in sorted(ROOT.rglob("*.dart")):
        try:
            n = process_file(f)
        except Exception as e:  # noqa: BLE001
            print("ERR", f, e)
            continue
        if n:
            touched.append(str(f.relative_to(ROOT.parent)))
    print("files", len(touched))
    for t in touched:
        print(t)


if __name__ == "__main__":
    main()
