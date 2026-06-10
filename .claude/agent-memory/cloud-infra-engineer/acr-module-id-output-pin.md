---
name: acr-module-id-output-pin
description: terraform-modules acr `id` output landed in commit 49c8504; pins before it (e.g. c8a3dcb) break module.acr.id at plan time
metadata:
  type: project
---

The `acr` module's `id` output (scope for the cell's AcrPull grant) was ADDED in
terraform-modules commit `49c85046133879306490d5a5b9ece3fb9081239c`. The prior
commit `c8a3dcbfb005095355ea5880fd048cd05e5ef95a` has only `login_server` /
`admin_username` / `admin_password` outputs. The `cell` module also did not exist
at c8a3dcb — it first appears at 49c8504.

So any env root that pins the acr source at c8a3dcb (or earlier) but references
`acr_id = module.acr.id` fails at PLAN time with "module.acr does not have an
attribute named id" — a latent error that only fires when that root is actually
planned. As of 2026-06-09 all env roots (dev/staging/prod) and the bharat-in cell
pin acr at 49c8504; converged via Task #8.

**Why:** SHA pins drift per-env (CKV_TF_1 forbids ?ref=main); a leaf-output add is
an API change consumers must re-pin onto. **How to apply:** when changing a
terraform-module's outputs, check `git show <sha>:modules/<m>/main.tf` (acr has NO
outputs.tf — outputs live in main.tf) at every consumer's pin before assuming the
output exists; verify outputs at the pin, not at HEAD. See [[infra-state-and-roots]].
