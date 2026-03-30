# QuestTown UI Refresh Brief

This brief translates the current UI direction into implementation-ready screen targets for the first-hour MVP.

The target style is:

- Darkest Dungeon clarity and compartmentalised mission-management structure
- Civilization VI polish, warmth, optimism, icon treatment, and material richness
- no grimdark, blood, horror, red-black oppression, or muddy gothic heaviness

## Global Direction

### Visual Thesis

QuestTown should feel like a bright, premium fantasy strategy game built from parchment, enamel, carved stone, brass trims, and heraldic icon rows, with disciplined hierarchy and a warm town-building mood.

### Content Plan

- hero: large playable town view with a strong resource line and clean interaction anchors
- support: selected building and quest details framed as focused management spaces
- detail: logs, roster, status notes, and costs in compact secondary regions
- final CTA: every major panel ends in one clear action, not a wall of buttons

### Interaction Thesis

- drawer and panel motion should slide with weight, not pop abruptly
- selected panels should brighten and sharpen while background UI slightly recedes
- hover and selection states should use Civ-like enamel glow and brass emphasis, not oversized scaling

## Design Tokens

### Palette

- deep civic blue: headers, active highlights, quest emphasis
- warm cream parchment: main text surfaces
- brass gold: primary actions, cost framing, selected accents
- stone grey: panel structure and neutral separators
- soft teal / jewel green: positive output, readiness, healing
- muted ember orange: warnings, risk, blocked actions

### Materials

- parchment interiors for content blocks
- carved stone outer shells for primary containers
- brass borders and dividers for key actions
- painted icon medallions for building and quest symbols
- restrained ornament only at panel edges and section headers

### Typography

- display face: elegant fantasy serif for panel titles and building / quest names
- utility face: clean strategy UI sans for body, labels, costs, status rows

### Motion

- 180-240ms slide/fade for drawers and inspectors
- 120-160ms button press/hover response
- staggered list reveal for quest cards and activity rows

## Screen 1: Building Management Panel

### Visual Thesis

One central management panel should feel like a civic ledger desk placed over the world, with a strong illustrated building header, bright action rows, and obvious "produce or upgrade" choice framing.

### Content Plan

- hero: illustrated building banner with name, crest, and current level
- support: current action block plus one output action and one upgrade action
- detail: short effect text, projected upgrade benefit, and local status notes
- final CTA: confirm / cancel row anchored at the bottom

### Interaction Thesis

- selecting a building should open the panel as a center-right sheet with a short slide and shadow settle
- switching between output and upgrade mode should animate only the action block, not redraw the whole panel
- projected upgrade benefits should animate in as a comparison row, not appear as a long paragraph

### Layout Structure

- header band:
  - building illustration / icon
  - building name
  - level and current tier title
- current state panel:
  - current action
  - current output stock / progress
  - one-sentence explanation of what the building is doing now
- output action block:
  - icon
  - output name
  - short effect line
  - projected result
- upgrade action block:
  - next tier name
  - projected effect change
  - gold cost
  - time cost
- status notes strip:
  - last output finished
  - blocked reasons
  - "ready", "working", or "waiting for gold"
- action footer:
  - primary confirm button
  - secondary cancel / close button

### Implementation Notes

- move building inspection away from the current plain right-column label stack
- treat current action, output action, and upgrade action as distinct regions
- costs need icon-led framing, not plain label text
- building-specific output verbs must be visible without expanding details

## Screen 2: Main Town Screen

### Visual Thesis

The town view should read like a premium strategy board: large, calm, warm, and easy to scan, with UI pinned around the edges instead of crowding the middle.

### Content Plan

- hero: large isometric town field with buildings and autonomous heroes
- support: top HUD for resources and macro state
- detail: edge-mounted build / quest / selected info regions
- final CTA: clear next action through building placement or quest management

### Interaction Thesis

- edge panels should feel docked and retractable, not like floating windows
- the town view should remain visually dominant while side panels collapse into tabs
- the roster strip and event feed should animate gently rather than flashing or blinking

### Layout Structure

- top HUD:
  - gold
  - hero count / active expeditions
  - time speed
  - town health summary
- left build rail:
  - vertical icon-first building actions
  - one-click access to build modes
  - save/load separated from build actions
- bottom roster strip:
  - autonomous adventurer portraits
  - level / wound state pips
  - current activity micro-label
- compact quest pocket:
  - active quest count
  - one-click open to full quest flow
- compact event feed:
  - 2-3 recent lines
  - expandable archive mode
- selected inspector:
  - building or hero summary with one dominant action

### Implementation Notes

- keep at least 70% of the viewport for the town itself
- use one stronger world-lighting pass so the town reads as prosperous
- replace plain button rows with icon-led rails and inspector actions
- the town feed should visually distinguish arrival, quest, spend, heal, and upgrade events

## Screen 3: Quest Selector And Quest Detail Flow

### Visual Thesis

Quest selection should feel like opening a mission board in a noble hall: dramatic, legible, and consequential, but still bright and orderly.

### Content Plan

- hero: left quest list with clear card hierarchy
- support: right detail panel with rewards, risks, and suitability
- detail: item / requirement rows and likely adventurer fit
- final CTA: make available / pin / accept action

### Interaction Thesis

- selecting a quest card should drive a shared-focus transition into the detail panel
- risk and reward icons should reveal in a clean row rather than stacked paragraphs
- likely party suitability should behave like an evaluation summary, not a spreadsheet

### Layout Structure

- left quest column:
  - quest cards with title, risk badge, reward preview, and requirement hint
- right detail panel:
  - quest title
  - one-paragraph summary
  - reward row
  - XP row
  - risk row
  - requirement row
  - likely interested adventurers / suitability callout
- bottom action row:
  - primary action
  - secondary pin / close action

### Implementation Notes

- the current quest drawer should evolve into a list-detail mission flow
- quest cards need stronger difficulty and flavour identity
- the detail panel should expose likely interested heroes and why
- icon rows should cover gold, XP, wound risk, death risk placeholder, and recommended support

## Immediate UI Build Slices

1. Replace the current selected-building panel with the new building management sheet
2. Recompose the main town shell around a stronger HUD, roster strip, and docked edge panels
3. Replace the quest drawer with a true list-detail quest selector flow
4. Add shared UI theme tokens for parchment, brass, blue enamel, and panel spacing
5. Add motion polish for panel open/close, selection emphasis, and quest card transitions
