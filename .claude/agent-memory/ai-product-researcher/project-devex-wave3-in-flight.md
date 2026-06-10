---
name: project-devex-wave3-in-flight
description: DevEx truth-refresh landed (docs PR #17, 2026-06-10); wave 3 (ruleset import/apply, solo-operator params, auto-merge flip, routeplane PR #38 gates) still in flight
metadata:
  type: project
---

As of 2026-06-10 the docs canon (branching-and-devex.md, ADR-012, devsecops-pipeline.md, ADR-008) was trued up to implemented reality via docs PR #17 (branch `docs/devex-truth-refresh`), including two ratified ADR-012 amendments: (a) OpenFeature-SHAPED local trait instead of the OpenFeature Rust SDK; (b) solo-operator trunk parameters (0 approvals, no codeowner gate, ZERO bypass actors).

**Why:** ending doc drift; amendment (b) was deliberately ratified in docs BEFORE the infrastructure-live apply that makes it live.

**How to apply:** treat these as still in flight (verify live state before claiming done): the Terraform import/apply of the six hand-created `main-trunk-protection` rulesets (live ones still have 1 review + OrganizationAdmin always-bypass), `github/` root wiring into deploy.yml, the `allow_auto_merge` flip (false on all six repos), required-check promotions (routeplane deps-audit/branch-name, docs `lint`), and routeplane PR #38 (secret-scan/workflow-lint/codeowners gates). Also note: infra PRs now DO run a founder-ratified read-only `-lock=false` plan preview on same-repo PRs (infrastructure-live PR #23) — do not describe the PR path as strictly credential-free.
