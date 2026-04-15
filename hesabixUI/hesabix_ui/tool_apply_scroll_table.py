# One-off: add SingleChildScrollView + expandBodyHeightToFitRows to list/report pages.
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent / "lib" / "pages"

pat_exp = re.compile(
    r"(\n            )Expanded\(\n              child: Padding\(\n                padding: const EdgeInsets\.all\(8\.0\),\n                child: DataTableWidget<Map<String, dynamic>>\(",
    re.MULTILINE,
)
rep_exp = (
    r"\1SingleChildScrollView(\n              child: Padding(\n"
    r"                padding: const EdgeInsets.all(8.0),\n"
    r"                child: DataTableWidget<Map<String, dynamic>>("
)

pat10 = re.compile(
    r"(\n          )Expanded\(\n            child: Padding\(\n              padding: const EdgeInsets\.all\(8\.0\),\n              child: DataTableWidget<Map<String, dynamic>>\(",
    re.MULTILINE,
)
rep10 = (
    r"\1SingleChildScrollView(\n            child: Padding(\n"
    r"              padding: const EdgeInsets.all(8.0),\n"
    r"              child: DataTableWidget<Map<String, dynamic>>("
)

pat_exp2 = re.compile(
    r"(\n          )Expanded\(\n            child: DataTableWidget<Map<String, dynamic>>\(",
    re.MULTILINE,
)
rep_exp2 = r"\1SingleChildScrollView(\n            child: DataTableWidget<Map<String, dynamic>>("

pat_w = re.compile(
    r"(\n          )Expanded\(\n            child: DataTableWidget<WarrantyCode>\(",
    re.MULTILINE,
)
rep_w = r"\1SingleChildScrollView(\n            child: DataTableWidget<WarrantyCode>("

pat_op = re.compile(
    r"(\n            )Expanded\(\n              child: DataTableWidget<Map<String, dynamic>>\(",
    re.MULTILINE,
)
rep_op = r"\1SingleChildScrollView(\n              child: DataTableWidget<Map<String, dynamic>>("

# inventory_stock uses EdgeInsets.all(isMobile ? 4.0 : 8.0)
pat_inv = re.compile(
    r"(\n            )Expanded\(\n              child: Padding\(\n                padding: EdgeInsets\.all\(isMobile \? 4\.0 : 8\.0\),\n                child: DataTableWidget<Map<String, dynamic>>\(",
    re.MULTILINE,
)
rep_inv = (
    r"\1SingleChildScrollView(\n              child: Padding(\n"
    r"                padding: EdgeInsets.all(isMobile ? 4.0 : 8.0),\n"
    r"                child: DataTableWidget<Map<String, dynamic>>("
)


def process_file(path: Path) -> bool:
    t = path.read_text(encoding="utf-8")
    if "DataTableWidget" not in t:
        return False
    orig = t
    t = pat_exp.sub(rep_exp, t)
    t = pat10.sub(rep10, t)
    t = pat_exp2.sub(rep_exp2, t)
    t = pat_w.sub(rep_w, t)
    t = pat_op.sub(rep_op, t)
    t = pat_inv.sub(rep_inv, t)
    if t == orig:
        return False
    path.write_text(t, encoding="utf-8")
    return True


def main() -> None:
    changed = []
    for f in sorted(ROOT.rglob("*.dart")):
        if f.name == "example_usage.dart":
            continue
        try:
            if process_file(f):
                rel = str(f.relative_to(ROOT.parent))
                changed.append(rel)
        except Exception as e:  # noqa: BLE001
            print("ERR", f, e)
    print("changed", len(changed))
    for c in changed:
        print(c)


if __name__ == "__main__":
    main()
