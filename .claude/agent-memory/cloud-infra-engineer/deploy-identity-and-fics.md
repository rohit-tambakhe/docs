---
name: deploy-identity-and-fics
description: The Azure deploy identity (AZURE_CLIENT_ID) is an App Registration with no Graph rights; how its GitHub OIDC FICs are structured
metadata:
  type: project
---

The `AZURE_CLIENT_ID` GitHub secret on every RST-Holdings repo is an **App Registration** (not a managed identity): `github-actions-routeplane`, appId `4423dde5-6104-407a-86a6-7c84462aec7d`, objectId `ff21fc0c-ee02-4055-9a7a-19c336442ceb`, tenant `22574ded-4abf-4989-b019-d546c0a1285f`, subscription `1b9b8e29-3b03-4751-b46b-51ed4f8a64da`. There are **zero user-assigned managed identities** in the tenant — all CI/CD auth is this one app via OIDC FICs.

Its RBAC: **Contributor** on the subscription + **Storage Blob Data Contributor** on `strprouteplanetf` (tfstate). Its Graph rights: **NONE** — no `Application.ReadWrite.*`, not an owner of its own app, no directory role. So the deploy SP **cannot manage `azuread_*` (Graph/Entra) resources**; anything that creates FICs/app config must be a one-time admin bootstrap, not a pipeline apply.

FIC pattern on the app is **flexible (claims-matching) credentials** with `*` wildcards, e.g. `repo:RST-Holdings/*:ref:refs/heads/main`, `:ref:refs/tags/*`, and (added 2026-06-09) `repo:RST-Holdings/infrastructure-live:environment:*` for cell-matrix CD's environment-scoped deploy legs. Requires azuread provider >= 3.7 (`azuread_application_flexible_federated_identity_credential`). Codified in `infrastructure-live/identity/` (state key `identity.terraform.tfstate`).

The repo owner (Rohit.Tambakhe@live.com) is **Global Administrator** on the tenant — so the user can run the admin bootstrap applies that the pipeline SP cannot.

**Why:** the cell-matrix CD refactor scopes deploy jobs to GitHub `environment:` (dev/prod/staging/dedicated from cells.json), changing the OIDC subject; the privilege split makes FIC management a deliberate out-of-pipeline step.
**How to apply:** when adding identity/FIC/Graph Terraform, put it in its own root + state key and flag it as admin-bootstrap (cannot run through deploy.yml). For ARM-only resources, the pipeline SP is fine. See [[infra-state-and-roots]].
