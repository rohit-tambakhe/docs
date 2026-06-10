---
name: infra-state-and-roots
description: infrastructure-live Terraform roots and their separate azurerm state keys; which are pipeline-applied vs admin-bootstrap
metadata:
  type: project
---

`infrastructure-live` has multiple Terraform roots, each with its own key in the single tfstate account `rg-routeplane-tfstate` / `strprouteplanetf` (container `tfstate`), all azurerm + OIDC:
- `routeplane/dev` → `dev.terraform.tfstate` — gateway infra (RG, ACR, log analytics, aca_env, aca). **Auto-applied** by deploy.yml on push to main (the privilege-less deploy SP can do this — it's all `azurerm_*`/ARM). The aca module ignores image drift so apply never reverts a CD-deployed digest.
- `routeplane/prod`, `routeplane/staging` — sibling env roots.
- `github/` → `github.terraform.tfstate` — branch-protection / ruleset-as-code via the `integrations/github` provider, authed by a GitHub App **installation token** (App `CD_APP_ID`=4000764, `routeplane-cd-dispatch`), not a PAT.
- `identity/` → `identity.terraform.tfstate` (added 2026-06-09) — GitHub OIDC FICs on the deploy App Registration. **azuread_* / Graph → admin-bootstrap only**, cannot run through the pipeline (see [[deploy-identity-and-fics]]).

CD vs infra are disjoint pipelines: `deploy.yml` = infra PR/plan/dev-apply (never deploys an image); `cd.yml` = verify-once-then-fan-out-digest to cells via `az containerapp update` (ADR-008 / ADR-013). Cell fan-out source of truth is `routeplane/cells/cells.json` (cell_name, app, resource_group, **environment** [the GitHub Environment = OIDC subject scope], tier, region, enabled).

**Why:** separate state keys isolate blast radius (a ruleset or FIC apply can never touch gateway infra); the pipeline-vs-admin split follows the deploy SP's permission boundary.
**How to apply:** pick the root by resource type — ARM resource → pipeline-applied env root; Graph/identity → `identity/` admin-bootstrap. Pooled prod cells (pool-free/pool-std) ACA apps did not exist as of 2026-06-09 despite `enabled:true` in cells.json — a deploy of them fails at `az containerapp update` (not OIDC).
