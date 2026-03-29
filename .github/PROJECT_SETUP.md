# QuestTown GitHub Project Setup

This repo is structured to use GitHub Projects v2 plus Issues as the source of truth for planning and execution.

## Recommended Project Shape

- One user-level GitHub Project for `QuestTown Development`
- Issues for all work items
- Epic issues for large slices
- Task issues for concrete implementation work
- A board view grouped by `Status`
- A table view for backlog grooming
- An optional roadmap or iteration view later

## Project Fields

Create these fields in the GitHub Project:

- `Status`: single select
  - `Backlog`
  - `Ready`
  - `In Progress`
  - `Review / Test`
  - `Done`
- `Priority`: single select
  - `P0`
  - `P1`
  - `P2`
- `Area`: single select
  - `Simulation`
  - `Buildings`
  - `Adventurers`
  - `Quests`
  - `UI`
  - `Save/Load`
  - `Tests`
- `Size`: single select
  - `XS`
  - `S`
  - `M`
  - `L`
- `Milestone / Slice`: text or single select
  - `Foundation`
  - `First Playable`
  - `Quest Loop`
  - `Data Integration`

## Views

- `Board`: group by `Status`
- `Backlog Table`: sort by `Priority`, then `Size`
- `Roadmap`: optional once date fields or iterations are in use

## Automations

Turn on these Project workflows:

- auto-add new issues from `mlokanenew/QuestTown`
- set `Status = Backlog` for new items
- archive items when `Status = Done`

This repo also contains `.github/workflows/add-to-project.yml`.
To enable it:

1. Create the GitHub Project manually in the GitHub UI.
2. Add repository variable `GITHUB_PROJECT_URL` with the full project URL.
3. Add repository secret `PROJECT_AUTOMATION_TOKEN`.
4. Give that token:
   - `Contents: Read & write`
   - `Issues: Read & write`
   - `Pull requests: Read & write`
   - `Metadata: Read`
   - user-level or organization-level `Projects` access, depending on where the project lives

## Assistant Workflow

- move the next actionable item to `Ready`
- branch from the linked issue
- implement the task
- open a PR referencing the issue
- move the issue to `Review / Test`
- when merged, close the issue and move it to `Done`

## Current Limitation

The PAT available in local automation can create and update Issues, but it currently cannot call the `createProjectV2` API. The live Project still needs to be created with a token that has GitHub Projects permission.
