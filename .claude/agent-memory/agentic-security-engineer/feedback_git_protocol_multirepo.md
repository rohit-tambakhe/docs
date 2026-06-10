---
name: git-protocol-multirepo
description: Multi-repo workspace git protocol; conventional commits; never add AI-authorship trailers
metadata:
  type: feedback
---

The top-level dir is a meta-repo of several independently-versioned git repos mapping to GitHub org `RST-Holdings` (routeplane, docs, common-actions, infrastructure-live, terraform-modules, routeplane-skills). Commits operate INSIDE the relevant subdir — changes never span repos.

**How to apply:**
- `cd` into the subdir, `git fetch origin`, branch ONLY off origin/main: `git checkout -b <branch> origin/main`. Never pipe `git checkout` (masks failures).
- Conventional Commits (`feat:`/`fix:`/`chore:`/`docs:`). Each sub-repo uses release-please (Conventional Commits → SemVer).
- HARD RULE: never add a `Co-Authored-By` / AI-authorship trailer to commits or PR bodies. Plain messages only.
- common-actions is SHA-pinned by consumers. After merging a common-actions fix to its main, bump the consumer's pin to the new SHA (mirror existing style: `@<sha> # main @ <date>`) — the fix doesn't take effect until the pin is bumped. common-actions required check is `actionlint` (lints workflows by default, NOT composite action.yml files — a composite-action edit passes actionlint fine).
- infra-live required checks: `actionlint`/`Terraform`/`iac-scan`/`secret-scan`. Poll `gh pr view --json mergeStateStatus,statusCheckRollup`; merge when CLEAN.
- gh is authed as rohit-tambakhe with admin:org + repo + workflow scopes.

See [[onedrive-drift]].
