---
name: onedrive-drift
description: OneDrive silently reverts/staleness on working-tree files mid-session; treat git origin as ground truth, not local disk
metadata:
  type: feedback
---

The repo lives under OneDrive (`/mnt/c/Users/rohit/OneDrive/Documents/routeplane`). Local working-tree files can be SILENTLY STALE or reverted mid-session — the local checkout of a file may not match `origin/main`.

**Why:** OneDrive sync races with edits; observed concretely — local `cd.yml` showed pin `fab00c75` + `azure/login@v2.2.0` while `origin/main` actually had `19b5910` + `azure/login@v3.0.0`. Also saw an Edit'd workflow revert to its pre-edit content after pushing.

**How to apply:**
- Treat `git show origin/<branch>:<file>` as ground truth, NOT the local file. Before editing a workflow/action, materialize the authoritative copy first: `git checkout origin/main -- <path>` (or dump to /tmp and rewrite from that).
- After every edit: commit + push promptly, then VERIFY on the remote (`git show origin/<branch>:<file>` or `gh pr diff`), never trust that the local edit "stuck."
- Prefer `sed -i 's|...|...|g'` with `|` delimiter for mechanical edits (robust when Edit fails with "file modified since read").
- Each subdir is its own git repo (remote `RST-Holdings/<name>`). Branch ONLY off `origin/main`: `git checkout -b <branch> origin/main`. Other subdirs carry in-flight feature branches — never commit onto them; restore context by branching fresh off origin/main.

See [[git-protocol-multirepo]].
