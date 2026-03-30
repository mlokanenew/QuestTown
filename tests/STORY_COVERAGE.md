# MVP Story Test Coverage

This file maps the MVP user stories on the GitHub Project (`#43` to `#73`) to the automated scenario coverage in [`tests/scenarios`](C:/Users/mloka/Documents/QuestTown/tests/scenarios).

## Coverage Notes

- Most MVP stories are covered by more than one scenario.
- UI-heavy stories are covered indirectly through simulation state, snapshots, and event output because the current automated harness is headless.
- The full playable loop is regression-tested by [`mvp_full_loop.json`](C:/Users/mloka/Documents/QuestTown/tests/scenarios/mvp_full_loop.json) and an LLM-driven pass of the same scenario.

## Story Matrix

| Story | Coverage |
| --- | --- |
| `#43` Town gold and spending feedback | `economy_services_loop.json`, `mvp_building_action_modes.json`, `phase1_insufficient_gold_fails.json` |
| `#44` Auto-arrive a small starter roster | `tavern_spawn.json`, `hero_cap_5.json`, `mvp_career_pool.json`, `mvp_wfrp_career_profiles.json` |
| `#45` Simulation state separated from UI state | `save_load_roundtrip.json` |
| `#46` Every building has a visible current action | `mvp_building_action_modes.json` |
| `#47` Building outputs are distinct and readable | `mvp_building_outputs.json`, `mvp_no_inn_no_quests.json` |
| `#48` Upgrades change what the town can do | `mvp_store_unlocks_herbs.json`, `mvp_temple_unlocks_strange_lights.json`, `mvp_full_loop.json` |
| `#49` Inn generates quests | `mvp_no_inn_no_quests.json`, `mvp_base_inn_quests.json`, `mvp_quest_pool.json` |
| `#50` Adventurers spend money at the Inn | `economy_services_loop.json` |
| `#51` Inn upgrades improve opportunity quality | `mvp_base_inn_quests.json`, `mvp_store_unlocks_herbs.json`, `mvp_temple_unlocks_strange_lights.json` |
| `#52` General Store produces abstract goods | `mvp_building_outputs.json`, `economy_services_loop.json` |
| `#53` Adventurers spend money at the General Store | `economy_services_loop.json` |
| `#54` General Store upgrades improve preparation | `mvp_store_unlocks_herbs.json`, `mvp_success_can_still_wound.json` |
| `#55` Temple outputs minor healing | `mvp_building_outputs.json`, `economy_services_loop.json` |
| `#56` Adventurers pay for healing | `economy_services_loop.json` |
| `#57` Temple upgrades unlock stranger quest support | `mvp_temple_unlocks_strange_lights.json`, `economy_services_loop.json` |
| `#58` Quest log is readable and updates | `mvp_no_inn_no_quests.json`, `mvp_base_inn_quests.json`, `quest_filter_controls.json`, `mvp_quest_pool.json` |
| `#59` Exactly 3 first-hour quest types | `mvp_quest_pool.json` |
| `#60` Building upgrades change which quests can appear | `mvp_base_inn_quests.json`, `mvp_store_unlocks_herbs.json`, `mvp_temple_unlocks_strange_lights.json` |
| `#61` Adventurers choose quests autonomously | `quests_autonomous.json`, `mvp_full_loop.json` |
| `#62` Warrior, Rogue, and Wizard feel distinct | `mvp_career_pool.json`, `mvp_wfrp_career_profiles.json`, `mvp_store_unlocks_herbs.json`, `mvp_temple_unlocks_strange_lights.json` |
| `#63` Quest risk matters | `quests_resolution.json`, `mvp_success_can_still_wound.json` |
| `#64` Adventurers return with gold, XP, and progression | `quests_resolution.json`, `mvp_full_loop.json` |
| `#65` Minor wounds interrupt the loop | `mvp_success_can_still_wound.json`, `economy_services_loop.json` |
| `#66` Returned adventurers feed back into town economy | `economy_services_loop.json`, `mvp_full_loop.json` |
| `#67` Adventurers behave like customers | `economy_services_loop.json` |
| `#68` Each building matters at a different loop moment | `economy_services_loop.json`, `mvp_building_outputs.json`, `mvp_success_can_still_wound.json` |
| `#69` Player chooses upgrade work versus output work | `mvp_building_action_modes.json` |
| `#70` Building panel exposes action, output, and upgrade choices | `mvp_building_action_modes.json`, `mvp_building_outputs.json` |
| `#71` Adventurer panel stays readable and minimal | `mvp_wfrp_career_profiles.json`, `quests_resolution.json` |
| `#72` Event log covers the loop clearly | `mvp_full_loop.json`, `economy_services_loop.json`, `mvp_success_can_still_wound.json` |
| `#73` MVP careers use WFRP starter stats and trappings | `mvp_wfrp_career_profiles.json`, `mvp_career_pool.json` |

## Suite Verification

Latest verification pass:

- All `tests/scenarios/*.json` passed in scripted mode through `tools/llm_driver.py`
- `mvp_full_loop.json` passed in LLM mode with `qwen2.5-coder:7b`
