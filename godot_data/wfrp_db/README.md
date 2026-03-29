# WFRP Godot Database

Generated from the OCR markdown export of the *Warhammer Fantasy Roleplay 2nd Edition* core book.

## Files

- `characteristics.json`
  - Characteristic definitions, racial generation formulas, starting wounds, and starting fate points.
- `skills.json`
  - Skill records with type, linked characteristic, description, and related talents.
- `careers.json`
  - Career records with profile advances plus OCR-preserved `*_raw` fields for skills, talents, trappings, entries, and exits.
- `equipment.json`
  - Structured table dumps for weapons, armour, transport, services, and special equipment, plus weapon quality rules.
- `wfrp_database_manifest.json`
  - Source metadata and parsing notes.
- `WfrpDatabase.gd`
  - Minimal Godot loader for the JSON files.

## Godot Use

```gdscript
var db := WfrpDatabase.load_all()
var careers: Array = db["careers"]
var skills: Array = db["skills"]
```

## OCR Notes

- `ocr_review_required = true` marks entries that should be checked before final UI or balancing work.
- Career and skill names have been normalized for readability, but many body fields intentionally preserve OCR wording in `*_raw` text.
- Equipment is exported table-first because the OCR damaged several row boundaries. It is usable for ingestion, but some rows still need manual cleanup.

## Recommended Next Pass

1. Normalize career `skills_raw`, `talents_raw`, `career_entries_raw`, and `career_exits_raw` into arrays.
2. Split `equipment.json` tables into canonical item records with stable IDs, costs, encumbrance, availability, and combat stats.
3. Add source page references for every record so UI and debugging can link back to the book.
