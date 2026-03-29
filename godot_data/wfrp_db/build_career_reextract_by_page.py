from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent.parent
DB_ROOT = ROOT / "godot_data" / "wfrp_db"
CAREERS_REVIEW_PATH = DB_ROOT / "careers_reextract_candidates.json"
CONTENT_LIST_PATH = (
    ROOT
    / "warhammer_out"
    / "Warhammer Fantasy Roleplay 2nd edition"
    / "ocr"
    / "Warhammer Fantasy Roleplay 2nd edition_content_list.json"
)
OCR_PAGE_DIR = ROOT / "ocr_deepseek_careers"
OUT_JSON_PATH = DB_ROOT / "careers_reextract_by_page.json"
OUT_MD_PATH = DB_ROOT / "careers_reextract_by_page.md"


def recommended_strategy(page_idx: int) -> tuple[str, list[str]]:
    if page_idx == 61:
        return (
            "crop_bottom_career_block",
            [
                "This page mixes the Advanced Careers table and a single career block.",
                "Use a bottom-half crop for the career itself; full-page OCR is secondary.",
                "Adjacent-page spreads are optional, not primary.",
            ],
        )

    return (
        "crop_each_career_block",
        [
            "This page uses the standard two-career layout.",
            "Re-extract the top and bottom career blocks separately with overlap.",
            "Adjacent-page spreads are optional fallback only if a line still truncates.",
        ],
    )


def main() -> int:
    candidates = json.loads(CAREERS_REVIEW_PATH.read_text(encoding="utf-8"))
    content = json.loads(CONTENT_LIST_PATH.read_text(encoding="utf-8"))
    deepseek_pages = {
        int(path.stem[1:])
        for path in OCR_PAGE_DIR.glob("p*.md")
        if path.stem[1:].isdigit()
    }

    grouped: dict[int, list[dict]] = {}
    for row in candidates:
        name = row["career_name"]
        pattern = re.compile(re.escape(name), re.I)
        hits = [
            item["page_idx"]
            for item in content
            if 31 <= item["page_idx"] <= 87 and pattern.search(item.get("text", ""))
        ]
        if not hits:
            continue
        page_idx = min(hits)
        grouped.setdefault(page_idx, []).append(row)

    rows = []
    for page_idx in sorted(grouped):
        strategy, notes = recommended_strategy(page_idx)
        rows.append(
            {
                "page_idx": page_idx,
                "page_image": f"ocr_target_pages/p{page_idx:03d}.png",
                "deepseek_page_done": page_idx in deepseek_pages,
                "recommended_strategy": strategy,
                "join_adjacent_pages_primary": False,
                "careers": sorted(grouped[page_idx], key=lambda row: row["career_name"]),
                "notes": notes,
            }
        )

    OUT_JSON_PATH.write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    lines = [
        "# Career Re-Extraction By Page",
        "",
        "All remaining bad careers are on pages already processed by DeepSeek.",
        "The main recommendation is to crop career blocks rather than re-run full pages.",
        "",
    ]
    for row in rows:
        lines.append(f"## Page {row['page_idx']}")
        lines.append(f"- Source image: `{row['page_image']}`")
        lines.append(f"- DeepSeek full-page OCR already done: `{str(row['deepseek_page_done']).lower()}`")
        lines.append(f"- Recommended strategy: `{row['recommended_strategy']}`")
        lines.append(f"- Join adjacent pages as primary tactic: `{str(row['join_adjacent_pages_primary']).lower()}`")
        lines.append("- Careers:")
        for career in row["careers"]:
            lines.append(f"  - {career['career_name']}: {'; '.join(career['reasons'])}")
        lines.append("- Notes:")
        for note in row["notes"]:
            lines.append(f"  - {note}")
        lines.append("")

    OUT_MD_PATH.write_text("\n".join(lines), encoding="utf-8")
    print(
        json.dumps(
            {
                "page_groups": len(rows),
                "output_json": str(OUT_JSON_PATH),
                "output_md": str(OUT_MD_PATH),
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
