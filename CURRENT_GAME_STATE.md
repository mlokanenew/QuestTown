# QuestTown Current Game State

This document describes the game as it exists in the repo today.

It is intentionally not a design wish list.
It is a snapshot of:

- what the game currently does
- what it does not yet do
- the main design choices behind the current implementation
- the current runtime/data architecture

## High-Level Summary

QuestTown is currently a small autonomous town-builder prototype in Godot 4.

The player:
- places and upgrades three buildings
- watches autonomous adventurers arrive
- lets those adventurers choose quests on their own
- sees them leave town, resolve quests off-screen, return, spend gold in town, and feed the town economy

The prototype is already playable in a simple loop and is testable in headless mode through both scripted scenarios and an Ollama-driven LLM harness.

## Current Play Loop

The loop currently works like this:

1. Start with town gold
2. Place Tavern, Weapon Shop, and Temple
3. Upgrade those buildings up to level 3
4. Adventurers spawn automatically once a Tavern exists
5. Quest offers appear automatically based on building state
6. Adventurers choose quests automatically
7. Adventurers leave town and travel off-screen
8. Quests resolve in simulation
9. Adventurers return richer, more experienced, and sometimes injured
10. Adventurers spend gold at town services
11. Town gold increases from those service purchases
12. Player reinvests gold into more upgrades

## What The Game Currently Does

### Buildings

Implemented buildings:
- Tavern
- Weapon Shop
- Temple

Implemented building behavior:
- only one instance of each building type can exist
- each building starts at level 1
- each building upgrades to level 3
- building placement spends town gold
- building upgrades spend town gold
- building definitions are data-driven from `data/buildings.json`
- building effects influence spawn support, quest generation, success, survival, recovery, and service income

Implemented building presentation:
- imported 3D building meshes are now used for the three core buildings
- Tavern uses imported `Inn`
- Weapon Shop uses imported `Blacksmith`
- Temple uses imported `Bell_Tower`
- build buttons have icons

### Adventurers

Implemented adventurer behavior:
- adventurers arrive automatically if a Tavern exists
- current active cap is low and controlled by support level
- base support is 4 active heroes
- Tavern support increases this up to 5 in practice
- heroes have names, career, stats, XP, gold, health, and state
- heroes can be clicked in the world to inspect details

Implemented hero state flow:
- arriving
- idling / in town
- departing for quest
- on quest
- returning
- recovering

Implemented hero data:
- `career_id`
- `career`
- `career_archetype`
- `quest_bias`
- `service_bias`
- `career_tags`
- `skill_ids`
- `skill_names`
- level / XP
- gold
- health / max health
- compact stat block

### Careers and Skills

Implemented now:
- the game uses a curated runtime subset of imported WFRP-inspired careers
- heroes are created from data-driven careers
- skills are data-driven and shown in the hero panel
- imported source tables exist in `godot_data/wfrp_db`

Current limitation:
- the full imported career/skill dataset is not yet the live runtime source of truth
- the game still uses a smaller shaped subset in `data/`

### Quests

Implemented quest behavior:
- quest offers are generated automatically
- available quests depend on building levels
- heroes choose quests autonomously
- career/archetype biases influence quest choice
- quest resolution is simulated off-screen
- quests award hero gold and XP
- failed quests can injure heroes
- heroes level up over time

Implemented current quest pool:
- Clear Wolves from the Road
- Escort Merchant Cart
- Hunt Forest Beast
- Investigate Old Shrine
- Drive Off Bandits

Implemented quest controls:
- quest templates can be enabled/disabled from the UI
- the player does not assign heroes manually

### Economy

Implemented economy rules:
- town gold is not passively generated
- town gold increases only when heroes spend money in town
- heroes spend on:
  - tavern lodging
  - weapon shop gear
  - temple healing
  - temple blessings

Implemented support effects:
- weapon shop purchases improve quest readiness
- temple blessings improve survival support
- temple healing/recovery reduces downtime
- tavern lodging feeds town income and acts as part of the town stay loop

### Save / Load

Implemented now:
- save current town state to `user://questtown_save.json`
- load the saved town state back into the running game
- save/load is exposed in the UI
- keyboard shortcuts:
  - `F5` save
  - `F9` load
- save/load also works through the headless command layer

Persisted state includes:
- town gold
- buildings
- heroes
- quests
- quest filter state
- events
- next IDs
- selected system state needed for spawn/quest continuation

### Building Placement

Implemented placement improvements:
- live ghost preview follows the cursor
- ghost uses the real building scene
- footprint preview shows building size
- preview turns green/red for valid vs blocked placement
- right-click cancels placement
- `Esc` cancels placement

### UI

Implemented UI:
- gold display
- build buttons
- upgrade buttons
- save/load buttons
- quest filter panel
- current quest offers panel
- event log
- hero inspection panel
- status/help line for save/load and placement controls

### Testing

Implemented test coverage:
- headless scripted scenario testing
- headless command server
- world snapshot serialization
- Ollama-driven LLM testing

Verified current scenario coverage includes:
- phase 1 building placement and upgrades
- duplicate placement failures
- insufficient gold failures
- quest generation and resolution
- economy/service loop
- save/load roundtrip
- full MVP loop

## What The Game Does Not Yet Do

### Gameplay Features Not Yet Implemented

Not yet implemented:
- direct hero inventory management
- explicit item ownership as a meaningful system
- equipment item tables as a live gameplay source
- permanent death
- factions
- politics
- social identity systems
- staffing / townsfolk economy
- tactical combat
- overworld map travel UI
- deep quest chains
- branching quest outcomes
- advanced town simulation outside the three core buildings

### Data Integration Not Yet Finished

Not yet fully integrated:
- full 113 imported careers as runtime gameplay data
- full 47 imported skills as runtime gameplay data
- imported characteristics as the runtime stat source
- imported equipment tables as canonical item/service tables
- OCR review workflow integrated into runtime tooling

### Presentation Not Yet Finished

Not yet polished:
- final UI theme pass
- richer world decoration across the whole map
- stronger building-specific VFX/audio feedback
- more intentional terrain/road layout
- deeper save/load UX

## Key Design Choices

### 1. Simulation First, Presentation Second

The game is built around a plain-data simulation state rather than scene nodes being the source of truth.

This keeps:
- headless testing possible
- serialization manageable
- LLM-driven tests possible
- gameplay logic decoupled from rendering

### 2. Runtime Tables Stay Small and Game-Shaped

Imported WFRP data is treated as source/reference input.

The live game consumes normalized QuestTown-friendly runtime tables in `data/`.

This avoids:
- leaking OCR mess directly into gameplay
- tying systems to unstable source formats
- making the prototype harder to iterate on

### 3. Minimal Autonomous Loop Over Manual Control

The player currently does not micromanage heroes.

The game focuses on:
- town-building choices
- support infrastructure
- economy feedback

This keeps the prototype aligned with the core fantasy:
"build the town and let adventurers use it."

### 4. Headless Verification Is A First-Class Requirement

The architecture intentionally supports:
- command-driven simulation
- JSON world snapshots
- scenario assertions
- LLM-guided playtests

This is a core implementation choice, not a side tool.

## Current System Architecture

### Core Runtime State

`GameState`
- single source of truth for world state
- stores buildings, heroes, quests, gold, events, and runtime counters
- emits signals for presentation and reload behavior

### Simulation Systems

`SimulationRoot`
- owns and steps the simulation systems
- exposes the public simulation API
- exports/imports save data

`BuildingSystem`
- placement rules
- occupancy rules
- upgrade rules
- building queries

`SpawnSystem`
- handles hero arrival timing and active-cap checks

`HeroSystem`
- handles hero movement and state transitions
- manages arrival, departure, return, and recovery flow

`QuestSystem`
- generates offers
- assigns quests
- resolves quests
- applies XP/level/recovery outcomes

`EconomySystem`
- handles in-town hero spending
- transfers hero gold into town gold
- applies service-driven quest support and healing logic

`WorldSnapshot`
- serializes sim state for headless testing and external inspection

### Presentation Layer

`world.gd`
- binds simulation to UI and scene behavior

`BuildManager`
- placement preview and player placement input

`BuildingPresenter`
- spawns building scene instances from sim state

`HeroPresenter`
- spawns and animates hero visuals from sim state

`EventLog`
- converts sim events into readable UI text

### Control / Tooling Layer

`CommandServer`
- headless JSON command interface over TCP

`ScenarioRunner`
- scripted scenario execution for regression tests

`llm_driver.py`
- Python driver that runs headless Godot and uses Ollama models to issue commands
- includes fallback logic so tests stay dependable when the model drifts

`SaveSystem`
- writes and reads save files for the current simulation state

## Current Data Layout

### Runtime Data

Used directly by gameplay:
- `data/buildings.json`
- `data/careers.json`
- `data/skills.json`
- `data/quests.json`
- `data/hero_names.json`

### Source / Imported Data

Stored as reference input:
- `godot_data/wfrp_db/careers.json`
- `godot_data/wfrp_db/skills.json`
- `godot_data/wfrp_db/characteristics.json`
- `godot_data/wfrp_db/equipment.json`
- manifest / OCR review metadata

### Imported External Scaffolding / Assets

Starter scaffolding:
- `ImportedSWArch/Starter-Kit-City-Builder-main/...`

Imported assets:
- `ImportedAssets/Buildings/...`
- `ImportedAssets/kenney_*`
- other imported packs currently available for future use

## Current Known Limitations

These are important current caveats:

- the upgrade-cost indexing currently uses the next-level entry cost, which affects expected gold totals
- the LLM harness still relies heavily on deterministic fallback logic
- the LLM driver currently uses a fixed TCP port, so parallel LLM runs conflict
- save/load is functional but not yet a polished user-facing save-slot system
- imported source data has not yet been fully transformed into live runtime tables

## Current Repo State Summary

Right now the repo contains:

- a playable autonomous town loop
- headless regression coverage
- LLM-driven test coverage
- imported source/reference WFRP tables
- starter-kit-inspired placement/save-load improvements
- imported 3D building art integrated into the core building scenes

## Recommended Immediate Next Steps

Most valuable next steps from here:

1. Fix the upgrade-cost indexing bug so build/upgrade pricing matches the design data cleanly
2. Expand runtime careers/skills from the imported source tables through a proper transform pipeline
3. Convert imported equipment into canonical runtime service/item tables
4. Improve the UI/theme pass using the imported UI art packs
5. Extend save/load and LLM harness coverage as more systems come online
