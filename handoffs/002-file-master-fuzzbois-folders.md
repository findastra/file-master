status: open
for: file-master (any assistant that can run PowerShell on Astra's PC)
from: Claude Opus 5.5 (claude-opus-5-5), 2026-10-09
needs: agent/file-master.md, findastra/fuzzbois, findastra/fuzzboi-friend
---
## Task
Two Fuzzboi projects changed on 2026-10-09. Audit the PC folders and write **unapproved plan
rows** for Astra. Never delete, and move nothing until she approves.

- `C:\Users\audra\Documents\Projects\fuzzbois` is **not a git checkout**. It holds
  `fuzzbois-20261005T034609Z-1-001.zip`, `fuzzboi-696969.png` and `fuzzboi-834975.png`. The real
  project is the public repo `findastra/fuzzbois` (website <https://findastra.github.io/fuzzbois/>).
  Compare the zip's contents with the repo: is anything in it missing from GitHub?
- New pet app `findastra/fuzzboi-friend` (website <https://findastra.github.io/fuzzboi-friend/>)
  has no folder on the PC yet. Proposed home: `Documents\Projects\fuzzboi-friend`.

Plan rows to propose (each with its blocker written down):
1. Keep the two PNGs and the zip somewhere Astra chooses (they may be her friend's Fuzzbois or
   source exports), then turn `Projects\fuzzbois` into a clone of `findastra/fuzzbois`.
2. Clone `findastra/fuzzboi-friend` to `Projects\fuzzboi-friend`.

Before touching either folder, check no program is running from it (`Get-CimInstance
Win32_Process`, look for the folder in each command line).

## Done when
The plan rows are in the File Master's plan for Astra to approve, and the zip comparison is noted.

## Return
Write the results to `handoffs/results/002-fuzzbois-folders.md` (model name and version at the
top), set `status: done`, and commit on a branch.
