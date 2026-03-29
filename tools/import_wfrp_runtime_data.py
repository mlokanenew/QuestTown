#!/usr/bin/env python3
"""
Generate QuestTown runtime data from godot_data/wfrp_db.

This keeps the gameplay-facing tables compact and normalized while still
letting the repo retain the richer source material for later phases.
"""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT / "godot_data" / "wfrp_db"
DATA_DIR = ROOT / "data"


CANONICAL_SKILL_IDS = {
    "academic_knowledge": "academic_knowledge_various",
    "magical_sense": "magical_sense",
    "pick_lock": "pick_locks",
    "pick_locks": "pick_locks",
    "sleight_of_hand": "sleight_of_hand",
    "speak_arcane_language": "speak_arcane_language",
    "speak_language": "speak_language_various",
    "trade": "trade_various",
    "performer": "performer_various",
    "secret_language": "secret_language_various",
    "secret_signs": "secret_signs",
    "channelling": "channelling",
    "consume_alcohol": "consume_alcohol",
}

ARCHETYPE_KEYWORDS = {
    "faith": {"priest", "initiate", "zealot", "nun", "monk", "templar", "shrine", "theology", "magic", "wizard"},
    "martial": {"soldier", "mercenary", "guard", "watch", "bodyguard", "pit fighter", "knight", "sergeant"},
    "scout": {"hunter", "ranger", "boatman", "fisherman", "fieldwarden", "scout", "tracker"},
    "rogue": {"thief", "burglar", "smuggler", "charlatan", "assassin", "fence", "outlaw", "rogue"},
    "warden": {"roadwarden", "bailiff", "toll", "watchman", "jailer"},
    "runner": {"messenger", "coachman", "courier"},
    "survivor": {"rat catcher", "camp follower", "bone picker", "vagabond", "beggar"},
}

QUEST_BIAS_KEYWORDS = {
    "combat": {"weapon", "fight", "guard", "mercenary", "soldier", "bodyguard", "bounty", "pit fighter", "watch"},
    "beast": {"hunter", "animal", "trap", "survival", "track", "fisherman", "boatman"},
    "spiritual": {"theology", "magic", "priest", "zealot", "initiate", "wizard"},
    "escort": {"roadwarden", "messenger", "coachman", "boatman", "ride", "drive", "navigation"},
    "risky": {"thief", "smuggler", "charlatan", "rogue", "burglar", "assassin"},
    "support": {"heal", "haggle", "gossip", "charm", "trade", "servant"},
}

TAG_KEYWORDS = {
    "frontline": {"soldier", "mercenary", "guard", "bodyguard", "pit fighter"},
    "wilderness": {"hunter", "boatman", "fisherman", "survival", "track"},
    "urban": {"thief", "charlatan", "burglar", "fence", "agitator"},
    "faith": {"priest", "initiate", "theology", "zealot", "magic", "wizard"},
    "support": {"heal", "haggle", "gossip", "trade", "servant"},
    "travel": {"roadwarden", "messenger", "boatman", "navigation", "ride", "drive"},
}


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def save_json(path: Path, payload) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def slugify(text: str) -> str:
    text = text.lower().replace("&", " and ")
    text = re.sub(r"\([^)]*\)", "", text)
    text = re.sub(r"[^a-z0-9]+", "_", text).strip("_")
    return text


def canonical_skill_id(name: str) -> str:
    lowered = name.strip().lower()
    if lowered.startswith("academic knowledge"):
        return CANONICAL_SKILL_IDS["academic_knowledge"]
    if lowered.startswith("speak language"):
        return CANONICAL_SKILL_IDS["speak_language"]
    if lowered.startswith("secret language"):
        return CANONICAL_SKILL_IDS["secret_language"]
    if lowered.startswith("trade"):
        return CANONICAL_SKILL_IDS["trade"]
    if lowered.startswith("performer"):
        return CANONICAL_SKILL_IDS["performer"]
    raw = slugify(name)
    return CANONICAL_SKILL_IDS.get(raw, raw)


def extract_skill_ids(career: dict, available_ids: set[str]) -> list[str]:
    seen: list[str] = []
    for entry in career.get("skills", []):
        parts = re.split(r"\s+or\s+|/", entry)
        for part in parts:
            part = part.strip(" ,.;:-")
            if not part:
                continue
            skill_id = canonical_skill_id(part)
            if skill_id in available_ids and skill_id not in seen:
                seen.append(skill_id)
    return seen


def derive_archetype(career: dict, skill_ids: list[str]) -> str:
    haystack = " ".join(
        [
            career.get("name", "").lower(),
            " ".join(skill_ids),
        ]
    )
    for archetype, keywords in ARCHETYPE_KEYWORDS.items():
        if any(keyword in haystack for keyword in keywords):
            return archetype
    return "commoner"


def derive_quest_bias(career: dict, skill_ids: list[str], archetype: str) -> str:
    name = career.get("name", "").lower()
    if any(keyword in name for keyword in {"messenger", "roadwarden", "coachman", "boatman", "ferryman"}):
        return "escort"
    if any(keyword in name for keyword in {"peasant", "burgher", "servant", "tradesman"}):
        return "local"
    haystack = " ".join(
        [
            name,
            " ".join(skill_ids),
        ]
    )
    for bias, keywords in QUEST_BIAS_KEYWORDS.items():
        if any(keyword in haystack for keyword in keywords):
            return bias
    if archetype == "martial":
        return "combat"
    if archetype == "faith":
        return "spiritual"
    if archetype in {"runner", "warden"}:
        return "escort"
    if archetype in {"scout", "survivor"}:
        return "beast"
    if archetype == "rogue":
        return "risky"
    return "local"


def derive_service_bias(archetype: str) -> str:
    if archetype == "faith":
        return "temple"
    if archetype in {"martial", "scout", "warden"}:
        return "weapons_shop"
    return "tavern"


def derive_tags(career: dict, skill_ids: list[str], archetype: str) -> list[str]:
    haystack = " ".join(
        [
            career.get("name", "").lower(),
            " ".join(skill_ids),
        ]
    )
    tags = [archetype]
    for tag, keywords in TAG_KEYWORDS.items():
        if any(keyword in haystack for keyword in keywords):
            tags.append(tag)
    if career.get("ocr_review_required", False):
        tags.append("ocr_review")
    return tags[:4]


def transform_skills(source_skills: list[dict]) -> list[dict]:
    runtime = []
    for skill in source_skills:
        runtime.append(
            {
                "id": canonical_skill_id(skill.get("name", skill.get("id", ""))),
                "name": skill.get("name", ""),
                "skill_type": skill.get("skill_type", ""),
                "characteristic": skill.get("characteristic", ""),
                "description": skill.get("description", ""),
                "ocr_review_required": skill.get("ocr_review_required", False),
            }
        )
    # de-duplicate canonical variants, preferring the first source entry
    unique = {}
    for skill in runtime:
        unique.setdefault(skill["id"], skill)
    return sorted(unique.values(), key=lambda item: item["id"])


def transform_characteristics(source_characteristics: dict) -> list[dict]:
    return source_characteristics.get("definitions", [])


def transform_careers(source_careers: list[dict], available_skill_ids: set[str]) -> list[dict]:
    runtime = []
    for career in source_careers:
        if career.get("tier") != "basic":
            continue
        skill_ids = extract_skill_ids(career, available_skill_ids)
        archetype = derive_archetype(career, skill_ids)
        runtime.append(
            {
                "id": career.get("id", ""),
                "name": career.get("name", ""),
                "tier": "basic",
                "archetype": archetype,
                "quest_bias": derive_quest_bias(career, skill_ids, archetype),
                "service_bias": derive_service_bias(archetype),
                "trait_tags": derive_tags(career, skill_ids, archetype),
                "skill_ids": skill_ids,
                "description": career.get("description", ""),
                "career_entries": career.get("career_entries", []),
                "career_exits": career.get("career_exits", []),
                "ocr_review_required": career.get("ocr_review_required", False),
            }
        )
    return sorted(runtime, key=lambda item: item["name"])


def main() -> None:
    source_careers = load_json(SOURCE_DIR / "careers.json")
    source_skills = load_json(SOURCE_DIR / "skills.json")
    source_characteristics = load_json(SOURCE_DIR / "characteristics.json")

    runtime_skills = transform_skills(source_skills)
    runtime_characteristics = transform_characteristics(source_characteristics)
    runtime_careers = transform_careers(source_careers, {skill["id"] for skill in runtime_skills})

    save_json(DATA_DIR / "skills.json", runtime_skills)
    save_json(DATA_DIR / "characteristics.json", runtime_characteristics)
    save_json(DATA_DIR / "careers.json", runtime_careers)

    print(
        json.dumps(
            {
                "careers": len(runtime_careers),
                "skills": len(runtime_skills),
                "characteristics": len(runtime_characteristics),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
