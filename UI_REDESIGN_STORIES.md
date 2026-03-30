# UI Redesign Stories

This is the execution story set for the full premium UI pass.

It follows the current art direction:
- Civ VI hierarchy for anchoring, grouping, and readable information density
- Majesty 2 ornament for heraldic fantasy trim and more tactile HUD treatment
- cleaner and less cluttered than either reference

It also follows `frontend-skill` directly:
- visual thesis: premium painterly fantasy strategy HUD with one clear visual anchor, calm surfaces, and restrained gold trim
- content plan: town surface first, anchored tools second, quest board as the only dominant overlay, contextual inspector last
- interaction thesis: subtle overlay presence, tactile hover lift, strong selected state, short UI sound feedback on hover/click/accept/ready

## Current Hierarchy Problems

Current issues in the live screen:
- too many regions have similar visual weight, so the town does not win as the centrepiece
- the quest board still behaves like stacked utility panels instead of one dramatic but readable mission sheet
- the bottom adventurer area still reads as repeated widgets rather than one persistent bar
- the right inspector is louder than a secondary contextual panel should be
- iconography and typography are not yet asset-backed and do not read as a finished premium strategy UI
- the current redesign groundwork is mostly code-driven theming; it still needs a proper asset-backed scene recompose

## Asset Inventory

Available local asset packs in [assets](C:/Users/mloka/Documents/QuestTown/assets):
- [kenney_fantasy-ui-borders (1).zip](C:/Users/mloka/Documents/QuestTown/assets/kenney_fantasy-ui-borders%20(1).zip)
- [kenney_ui-pack.zip](C:/Users/mloka/Documents/QuestTown/assets/kenney_ui-pack.zip)
- [kenney_board-game-icons.zip](C:/Users/mloka/Documents/QuestTown/assets/kenney_board-game-icons.zip)
- [game-icons.net.svg.zip](C:/Users/mloka/Documents/QuestTown/assets/game-icons.net.svg.zip)
- [kenney_interface-sounds.zip](C:/Users/mloka/Documents/QuestTown/assets/kenney_interface-sounds.zip)
- [Shikashi's Fantasy Icons Pack.zip](C:/Users/mloka/Documents/QuestTown/assets/Shikashi%27s%20Fantasy%20Icons%20Pack.zip)
- [Shikashi's Fantasy Icons Pack v2.zip](C:/Users/mloka/Documents/QuestTown/assets/Shikashi%27s%20Fantasy%20Icons%20Pack%20v2.zip)

Recommended extraction targets:
- `assets/ui_sources/kenney_fantasy_borders/`
- `assets/ui_sources/kenney_ui_pack/`
- `assets/ui_sources/kenney_board_icons/`
- `assets/ui_sources/game_icons_net/`
- `assets/ui_sources/kenney_interface_sounds/`
- `assets/ui_sources/shikashi_icons/`

## Story Set

### Story UI-001: Import and curate the visual UI kit

As a developer,
I want the relevant border, button, icon, and sound assets extracted into stable source folders,
so that the UI pass uses one coherent library instead of ad-hoc placeholders.

Approach:
- extract the Kenney border pack into `assets/ui_sources/kenney_fantasy_borders/`
- extract the Kenney UI Pack into `assets/ui_sources/kenney_ui_pack/`
- extract Kenney board icons and selected Game-icons.net SVGs into dedicated icon source folders
- extract Kenney interface sounds into `assets/ui_sources/kenney_interface_sounds/`
- create a curated shortlist document or import map so the game only uses one border family, one button family, and one icon family

Primary assets:
- `kenney_fantasy-ui-borders`
- `kenney_ui-pack`
- `kenney_board-game-icons`
- `game-icons.net.svg`
- `kenney_interface-sounds`

Testing approach:
- verify all chosen source assets import cleanly in Godot
- confirm there are no mixed styles in the curated shortlist
- run the game and inspect that no missing resource warnings appear in the Godot output

### Story UI-002: Establish the final typography stack and design tokens

As a player,
I want typography and spacing to feel deliberate and premium,
so that the screen is readable at a glance and no longer looks like debug UI.

Approach:
- add the final heading font and body font into `assets/fonts/`
- use a Cinzel-like engraved serif for headings and an Inter-like sans for body/UI text
- formalize tokens for:
  - background
  - surface-1
  - surface-2
  - border-subtle
  - text-primary
  - text-muted
  - accent
  - warning
  - success
- formalize type roles:
  - screen title
  - panel title
  - quest title
  - section label
  - body
  - metadata / microcopy
- formalize spacing and radius rules

Primary assets:
- final heading font in `assets/fonts/`
- final body font in `assets/fonts/`

Testing approach:
- compare all main panel headings against body copy in one screenshot
- ensure the same type roles are used in top bar, quest board, inspector, and bottom bar
- verify readability at 1920x1080

### Story UI-003: Recompose the world screen around the town as the main visual anchor

As a player,
I want the town to visually dominate the screen,
so that the game feels like a strategy game world first and a UI shell second.

Approach:
- reduce panel footprint and contrast relative to the town
- rebalance top, side, and bottom chrome so the play surface clearly owns the centre
- tune transparency, anchoring, and spacing so the UI feels layered over the world rather than boxed on top of it
- ensure all persistent HUD regions feel anchored to edges, not like floating dashboard cards

Primary assets:
- Kenney fantasy borders only for priority regions
- Kenney UI pack for flatter secondary regions

Testing approach:
- capture a before/after screenshot at the same camera angle
- verify the town remains the first thing seen when the quest board is closed
- verify at least 70% of the viewport still reads as playable world

### Story UI-004: Redesign the top bar as a compact premium command/status rail

As a player,
I want the top bar to feel intentional and polished,
so that gold, status, and speed controls read like a finished strategy HUD.

Approach:
- tighten the vertical footprint
- group gold, town summary, speed controls, and utility actions with clearer spacing
- use restrained gold trim and stronger type hierarchy instead of equal button weight
- add small consistent glyphs for gold, expedition count, and speed if they improve scan speed

Primary assets:
- Kenney UI Pack button shapes
- Kenney board icons or selected Game-icons.net glyphs for gold/speed/summary

Testing approach:
- verify the top bar can be scanned in one glance
- verify selected speed state is immediately obvious
- verify hover/pressed/disabled states are distinct

### Story UI-005: Rebuild the left build rail as a fast-scanning command strip

As a player,
I want the build rail to scan instantly,
so that building actions feel game-like rather than form-like.

Approach:
- convert the current build column into a cleaner icon-led rail
- use one consistent button family from Kenney UI Pack
- show icon, short label, and cost without verbose button copy
- separate build commands from save/load and support commands
- create a strong selected/active build-placement state

Primary assets:
- Kenney UI Pack buttons/tabs
- one icon family from Kenney board icons or Game-icons.net

Testing approach:
- verify all three buildings can be identified by icon and short label
- verify selected build mode is stronger than hover state
- verify disabled/unavailable build states remain readable

### Story UI-006: Turn the quest board into a premium mission sheet

As a player,
I want the quest board to feel like the focal interaction when opened,
so that quest selection feels meaningful and premium rather than like a plain list of boxes.

Approach:
- use ornate Kenney fantasy borders only here as one of the highest-importance surfaces
- add parchment content surfaces within a darker structural frame
- separate quest title, reward, risk, requirements, and likely party into clean rows with stronger hierarchy
- make the main CTA the clearest element on the sheet
- ensure unavailable quests and ready-to-launch quests are visually distinct

Primary assets:
- Kenney Fantasy UI Borders for the outer frame, dividers, and decorative trim
- Kenney UI Pack for CTA/button structure
- selected icon family for reward/risk/requirement rows
- Kenney interface sounds for open, hover, click, accept

Testing approach:
- verify the quest board is the strongest overlay when open
- verify the selected quest can be understood in under 3 seconds
- verify the CTA state clearly distinguishes:
  - ready
  - unavailable
  - disabled
  - warning/risk

### Story UI-007: Rework the right inspector into a narrower contextual sheet

As a player,
I want the inspector to feel calmer and more subordinate,
so that it supports the town view instead of competing with it.

Approach:
- narrow the inspector and reduce its contrast
- reserve ornate trim only for the title area, not every section
- keep summary information at the top and push long detail text into a lower-importance area
- use progress bars, section labels, and lighter dividers instead of repeated card shells

Primary assets:
- Kenney Fantasy UI Borders only for the inspector header/title strip
- Kenney UI Pack for flatter secondary controls and dividers

Testing approach:
- verify the inspector is clearly secondary to the quest board
- verify hero/building selection states are obvious
- verify the panel still reads cleanly when collapsed/expanded

### Story UI-008: Convert the bottom area into a true party / expedition bar

As a player,
I want the bottom bar to feel like one persistent expedition strip,
so that adventurers and expeditions feel integrated into the HUD rather than placed in equal boxes.

Approach:
- replace the current repeated card feeling with a continuous anchored bottom bar
- use a stronger title strip and consistent slot/button rhythm
- support hero selection, expedition status, wound state, and ready state with clear small glyphs and typography
- reserve richer trim here because it is a high-importance persistent surface

Primary assets:
- Kenney Fantasy UI Borders for the bar frame and dividers
- Kenney UI Pack for slot structure
- one icon family for wound/ready/quest states

Testing approach:
- verify roster entries are readable at a glance
- verify selected hero state is obvious
- verify the bar does not overpower the town view

### Story UI-009: Add a consistent icon language and state system

As a player,
I want icons and states to be consistent,
so that I can read available, selected, disabled, warning, and ready conditions instantly.

Approach:
- choose one primary icon family for all gameplay glyphs
- map specific icon treatments to:
  - available
  - selected
  - disabled
  - warning/risk
  - ready to launch
- stop mixing unrelated icon packs within the same screen
- reserve accent color for action/readiness, warning color for risk, and muted treatment for disabled states

Primary assets:
- one chosen set from Kenney board icons or Game-icons.net
- optional Shikashi icons only if a specific fantasy symbol is missing and style can be matched

Testing approach:
- review a single screenshot containing all five states
- verify that state meaning is understandable without reading supporting text

### Story UI-010: Add interface sound design for hover, click, open, accept, and ready

As a player,
I want subtle sound feedback on important UI interactions,
so that the interface feels tactile and finished.

Approach:
- assign hover, click, close/open, confirmation, and ready-state cues from Kenney interface sounds
- keep volumes low and consistent
- apply sounds only to primary interactions and key hover states, not every incidental event

Primary assets:
- `kenney_interface-sounds/Audio/*.ogg`

Testing approach:
- verify sounds play for:
  - hover
  - click
  - quest board open/close
  - accept quest
  - ready-to-launch state
- verify there is no rapid-fire sound spam on repeated hover

### Story UI-011: Add restrained motion and presence polish

As a player,
I want the UI to feel alive but not noisy,
so that interactions have weight and hierarchy.

Approach:
- quest board opens with soft fade/depth motion
- selected states get a small but clear presence change
- hover states get restrained lift/highlight
- panel transitions for collapse/expand should feel anchored, not springy or playful

Primary assets:
- no new art required
- optional interface sounds paired with key motion moments

Testing approach:
- record short clips of:
  - quest board opening
  - hover over build rail
  - selecting a quest
  - selecting a hero from bottom bar
- remove any motion that reads as ornamental rather than useful

### Story UI-012: Visual QA pass against commercial quality bar

As a developer,
I want a final visual QA story,
so that the screen ships as a cohesive premium strategy UI instead of a partially improved prototype.

Approach:
- compare the implemented screen against the target references:
  - Civ VI production/city UI
  - Majesty 2 ornament and fantasy tactility
- remove any remaining equal-weight bordered regions
- cut any filler copy
- tighten spacing, hierarchy, and trim usage after the first full pass

Testing approach:
- take desktop screenshots of:
  - normal town screen
  - building selected
  - quest board open
  - quest selected
  - quest unavailable
  - hover state
  - disabled action
  - ready-to-launch
- judge the screen against this bar:
  - town is still the visual anchor
  - quest board is the dominant overlay
  - inspector is clearly secondary
  - no dashboard-card mosaic feeling remains
  - all states are readable without hunting

## Recommended Execution Order

1. `UI-001` import and curate the asset kit
2. `UI-002` establish typography and tokens
3. `UI-003` recompose the main world layout
4. `UI-004` redesign the top bar
5. `UI-005` rebuild the left rail
6. `UI-006` redesign the quest board
7. `UI-007` calm and tighten the inspector
8. `UI-008` rebuild the bottom party/expedition bar
9. `UI-009` unify iconography and states
10. `UI-010` add interface sound cues
11. `UI-011` add restrained motion and presence
12. `UI-012` do final visual QA and cleanup

## Note On Testing

There is no attached screenshot in this thread, and the current game runs as a native Godot scene rather than a browser surface. So the practical test loop for this pass should be:
- run the live Godot scene
- capture screenshots from the real game window
- inspect the rendered result directly
- use automated regression only to confirm the redesign did not break the sim loop

If GitHub Project access is restored in-shell, these stories should be added as story-only items to the board rather than epics or tasks.
