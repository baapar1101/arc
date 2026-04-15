"""Add expandBodyHeightToFitRows before config closing when followed by @override Widget build."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent / "lib" / "pages"

PAT = re.compile(
    r"(      defaultSortDesc: (?:true|false),\n)(    \);\n  \}\n\n  @override\n  Widget build\(BuildContext context\) \{)",
    re.MULTILINE,
)


def main() -> None:
    for path in sorted(ROOT.rglob("*.dart")):
        raw = path.read_text(encoding="utf-8")
        if "expandBodyHeightToFitRows" in raw:
            continue
        if "DataTableWidget" not in raw:
            continue
        m = PAT.search(raw)
        if not m:
            continue
        new_raw = PAT.sub(
            r"\1      expandBodyHeightToFitRows: true,\n\2",
            raw,
            count=1,
        )
        if new_raw != raw:
            path.write_text(new_raw, encoding="utf-8")
            print(path.relative_to(ROOT.parent))


if __name__ == "__main__":
    main()
