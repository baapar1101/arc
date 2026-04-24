"""Insert expandBodyHeightToFitRows into return DataTableConfig<...>(...) blocks (handles Map<String, dynamic>>)."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent / "lib" / "pages"
SKIP_NAMES = {"person_details_dialog.dart", "example_usage.dart"}


def insert_all_expands(text: str) -> tuple[str, int]:
    inserts = 0
    parts: list[str] = []
    pos = 0
    while True:
        m = re.search(r"return\s+DataTableConfig<", text[pos:])
        if not m:
            parts.append(text[pos:])
            break
        abs_m = pos + m.start()
        parts.append(text[pos:abs_m])
        type_start = text.find("DataTableConfig<", abs_m)
        i = type_start + len("DataTableConfig<")
        depth = 1
        open_args = -1
        while i < len(text):
            if text[i] == "<":
                depth += 1
            elif text[i] == ">":
                depth -= 1
                if depth == 0 and i + 1 < len(text) and text[i + 1] == "(":
                    open_args = i + 1
                    break
            i += 1
        if open_args < 0:
            pos = abs_m + 1
            continue
        d = 0
        j = open_args
        close_args = -1
        while j < len(text):
            c = text[j]
            if c == "(":
                d += 1
            elif c == ")":
                d -= 1
                if d == 0:
                    close_args = j
                    break
            j += 1
        if close_args < 0:
            parts.append(text[abs_m:])
            break
        inner = text[open_args + 1 : close_args]
        chunk_before_close = text[abs_m:close_args]
        if "expandBodyHeightToFitRows" not in inner:
            inner_stripped = inner.rstrip()
            sep = "" if inner_stripped.endswith(",") else ","
            parts.append(chunk_before_close + f"{sep}\n      expandBodyHeightToFitRows: true")
            parts.append(text[close_args])  # closing ')'
            inserts += 1
        else:
            parts.append(text[abs_m : close_args + 1])
        pos = close_args + 1
    return "".join(parts), inserts


def process_file(path: Path) -> int:
    if path.name in SKIP_NAMES:
        return 0
    raw = path.read_text(encoding="utf-8")
    if "DataTableWidget" not in raw or "return DataTableConfig" not in raw:
        return 0
    if "expandBodyHeightToFitRows" in raw:
        return 0
    new_raw, n = insert_all_expands(raw)
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
