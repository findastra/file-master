status: open
for: any (an assistant that can run PowerShell on Astra's PC)
from: Claude Opus 5.5 (claude-opus-5-5), 2026-10-09
needs: agent/file-master.md "Pet apps: names to use", scripts/Invoke-FileMasterScan.ps1, findastra/astras-pet-apps PET-WORDS.md
---
## Task
The File Master agent now knows the pet words, but the scanner does not check them yet.
Add a read-only **Pet naming** check to `scripts/Invoke-FileMasterScan.ps1` for project folders
that contain a `pet.json`:

- an **untracked** file whose name uses an old pet word (`pet-interface`, `browser-companion`,
  `desktop-companion`, `pixel-twin`, `pet-app-icon`, `icon-chat`, `pet-frame`) is a `Low` finding
  with the new name as the Destination and Action `Rename`;
- a **tracked** file with an old word is an `Info` finding with Action `Review` (never rename
  tracked pet files; links and tags use them);
- a repo that has both `art/` and `pet-art/` is a `Low` finding.

It was written without a PowerShell runtime, so nothing was added to the scanner itself yet.

## Done when
A scan of `Documents\Projects` on Astra's PC lists Pet naming findings in `report.md`, the
plan rows round-trip through `Invoke-FileMasterPlan.ps1` as a dry run, and nothing is renamed
without her yes.

## Return
Branch plus PR in `file-master`, record the model and version in AGENTS.md, set this card to
`status: done`.
