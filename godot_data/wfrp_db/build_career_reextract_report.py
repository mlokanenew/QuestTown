from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent
CAREERS_PATH = ROOT / "careers.json"
OUT_JSON_PATH = ROOT / "careers_reextract_candidates.json"
OUT_MD_PATH = ROOT / "careers_reextract_candidates.md"


def has_suspicious_text(value: str) -> bool:
    markers = [
        "<table>",
        "<|ref|>",
        "<|det|>",
        "![](images/",
        "Advance Scheme",
        "Career:",
    ]
    if any(marker in value for marker in markers):
        return True
    if re.search(r"[A-Za-z]{1,2}\s[A-Za-z]{1,2}\s[A-Za-z]{1,2}", value):
        return True
    return False


def build_reasons(career: dict) -> list[str]:
    reasons: list[str] = []

    if not career.get("description") or has_suspicious_text(career["description"]):
        reasons.append("description missing or still OCR-damaged")

    for field, label in [
        ("skills", "skills"),
        ("talents", "talents"),
        ("trappings", "trappings"),
        ("career_entries", "career entries"),
        ("career_exits", "career exits"),
    ]:
        items = career.get(field, [])
        if not items:
            reasons.append(f"{label} missing")
            continue
        joined = ", ".join(items)
        if has_suspicious_text(joined):
            reasons.append(f"{label} still OCR-damaged")

    if not reasons:
        reasons.append("manual review recommended")

    return reasons


def main() -> int:
    careers = json.loads(CAREERS_PATH.read_text(encoding="utf-8"))
    flagged = []
    for career in careers:
        if not career.get("ocr_review_required"):
            continue
        flagged.append(
            {
                "career_id": career["id"],
                "career_name": career["name"],
                "reasons": build_reasons(career),
            }
        )

    OUT_JSON_PATH.write_text(json.dumps(flagged, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    lines = [
        "# Careers Needing OCR Re-Extraction",
        "",
        f"Total flagged careers: {len(flagged)}",
        "",
    ]
    for row in flagged:
        lines.append(f"- {row['career_name']}: {'; '.join(row['reasons'])}")

    OUT_MD_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"flagged_count": len(flagged), "output_json": str(OUT_JSON_PATH), "output_md": str(OUT_MD_PATH)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
