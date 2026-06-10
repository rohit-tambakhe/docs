# Routeplane Workspace

Routeplane is a neutral, multi-provider **AI Gateway + Agentic Security platform** — an SRE-grade,
OpenAI-compatible Rust proxy with sovereign data-residency routing, built India-first for the world.
This directory is the **meta-workspace**: each subdirectory is an **independently versioned git repo**
in the [`RST-Holdings`](https://github.com/RST-Holdings) org. Changes never span repos; commit inside
the repo you changed.

| Repo | What it is |
|------|------------|
| [`routeplane/`](https://github.com/RST-Holdings/routeplane) | The Rust data plane (Axum + Tokio) — a Cargo workspace of six crates. Most code work happens here. |
| [`docs/`](https://github.com/RST-Holdings/docs) | Single source of truth: product strategy, architecture, ADRs (001–019). |
| [`terraform-modules/`](https://github.com/RST-Holdings/terraform-modules) | Reusable Azure + GitHub Terraform modules (`aca`, `acr`, `cell`, `github-repo-ruleset`, …). |
| [`infrastructure-live/`](https://github.com/RST-Holdings/infrastructure-live) | Environment wiring: `routeplane/{dev,staging,prod,cells}` + `github/` (trunk protection as code). Apply is CI's job. |
| [`common-actions/`](https://github.com/RST-Holdings/common-actions) | **The** GitHub Actions library — every piece of CI logic is a composite action here. Workflows stay script-free. |
| [`routeplane-skills/`](https://github.com/RST-Holdings/routeplane-skills) | Claude Code plugin + marketplace: the skills and agent swarm that automate work in this workspace. |

The root meta-repo itself only tracks this README, `CLAUDE.md`, and `.claude/` (the shared
assistant config) — the nested repos are gitignored here and live on their own remotes.

## How the DevEx platform is built

Three layers, all of them code-reviewed and machine-enforced. Decisions live in ADRs; this is the map.

### 1. Trunk protection as code (ADR-012)

Every repo has one protected trunk (`main`) governed by a `main-trunk-protection` **ruleset** that is
**managed by Terraform**, not by the GitHub UI:

- Source: [`infrastructure-live/github/`](https://github.com/RST-Holdings/infrastructure-live/tree/main/github)
  consuming [`terraform-modules/modules/github-repo-ruleset`](https://github.com/RST-Holdings/terraform-modules/tree/main/modules/github-repo-ruleset).
- Guarantees on all six repos: PRs only (no direct push, no force push, **zero bypass actors — admins
  included**), required status checks per repo, strict up-to-date before merge, squash-only with the
  **PR title as the commit message**, linear history, auto-merge enabled, conversation resolution.
- The Terraform applies automatically on every push to `infrastructure-live` `main` and **reconciles
  continuously** — a UI edit to protection or repo merge settings is drift and is reverted by the next
  apply. To change protection, change the code (see Operating, below).
- Current review policy is the ratified **solo-operator amendment** (0 required approvals — checks are
  the gate). **Raise `required_approving_review_count` to 1 the day a second contributor gets write
  access** (one variable in `github/main.tf`).

### 2. CI/CD: script-free workflows + composite actions (ADR-008)

- Workflows contain **no inline logic** — every step `uses:` a composite from `common-actions/`,
  pinned by **full commit SHA** with a version comment. Key gates: `rust-quality` (fmt/clippy/test),
  `cargo-audit-deny`, `rust-coverage`, `gitleaks-scan` (secret scan, full history),
  `branch-name-check` (typed branches), `pr-title-check` (Conventional Commit titles — they become
  the squash commit release-please versions from), `workflow-lint` (actionlint + zizmor),
  `codeowners-check`, `markdown-quality` (docs lint + offline link check),
  `plugin-manifest-validate`, `terraform-checks`, `checkov-scan` / `trivy-config-scan` (IaC),
  `pr-evidence-assemble` + `pr-comment` (the sticky evidence comment on every PR).
- **Releases**: release-please per repo (Conventional Commits → SemVer tag + changelog), minting
  short-lived **GitHub App tokens** (`routeplane-cd-dispatch`) — no PATs anywhere in the platform.
- **Supply chain**: build-once image tagged by commit SHA, Trivy scan, SBOM (syft), cosign
  sign + attest; CD independently `cosign verify`s before deploying. Deploys fan out over the
  machine-readable cell manifest (`infrastructure-live/routeplane/cells/cells.json`) — only cells
  with `enabled: true` (i.e. actually provisioned) are targets.

### 3. The golden path (developer inner loop)

In `routeplane/`: `rust-toolchain.toml` pins the toolchain (1.86), `justfile` gives local/CI parity
(`just ci` runs the exact gate set CI runs), `.pre-commit-config.yaml` catches fmt/clippy/gitleaks/taplo
before push, and `.devcontainer/` provides the reproducible toolchain (with a named volume for
`target/` — important if your checkout lives on a OneDrive/WSL2 mount). Assistant config is
**team-shared**: root and per-repo `CLAUDE.md`, the agent swarm in `.claude/agents/`, and the
`routeplane-skills` plugin, so Claude Code users inherit the full paved road.

## How to operate it

### Onboard (human or intern)

1. Get org membership with **write** (never admin — protection binds everyone anyway) and your own
   credential: a fine-grained PAT or `gh auth login` browser flow. No classic PATs.
2. Clone the repos you need side by side (this meta-layout). For `routeplane/`: open in the
   devcontainer, **or** locally run `just bootstrap` (installs cargo tools, gitleaks, taplo,
   pre-commit hooks for both pre-commit and pre-push stages).
3. `just ci` must pass locally before your first push. Read the repo's `CLAUDE.md` and
   [`docs/architecture/branching-and-devex.md`](https://github.com/RST-Holdings/docs/blob/main/architecture/branching-and-devex.md) —
   it is the canonical operations manual this README summarizes.
4. Claude Code users: `/plugin marketplace add RST-Holdings/routeplane-skills`, then
   `/plugin install routeplane-skills@routeplane-skills`.

### Daily flow

```
git checkout -b feat/<short-desc>     # typed: feat/ fix/ chore/ docs/ infra/  (CI enforces)
…work…  just ci                       # local parity with the PR gates
git push -u origin feat/<short-desc>
gh pr create                          # PR title MUST be a Conventional Commit (CI enforces;
                                      #   it becomes the squash commit + drives SemVer)
gh pr merge --auto --squash           # arm auto-merge; it fires when all gates are green
```

- PR green but `BEHIND`? That's the strict up-to-date rule: `gh pr update-branch <n>`, checks re-run,
  auto-merge fires. This is the known Team-plan serialization tax (no native merge queue).
- Nobody can merge a red PR, and nobody can bypass — don't ask for an override; fix the check.

### The maintenance train: dependabot → release-please (order matters)

Two bots open PRs continuously. The sequence below is the whole trick — get it wrong and you either
cut releases that miss fixes, or churn CI re-running the same checks.

**1. Drain dependabot PRs first, one at a time.**

- Merge order within a repo is serial by construction: strict up-to-date means each merge flips the
  remaining PRs to `BEHIND`. For each green PR: `gh pr update-branch <n>` (or comment
  `@dependabot rebase`), wait for checks, `gh pr merge <n> --auto --squash`. Arming `--auto` on
  several at once is fine — they'll land one per CI cycle.
- **A red dependabot PR is the gates working, not noise.** Diagnose before touching it:
  - `quality`/`coverage` red → the bump likely needs newer rustc than `rust-toolchain.toml` pins
    (e.g. wiremock 0.6.5 needs > 1.86). Don't fix the code — the bump waits for a deliberate
    toolchain upgrade. Close it and add a `dependabot.yml` ignore with a reason comment.
  - `deps-audit` red → cargo-deny policy hit. Read the actual error: a benign ecosystem-transition
    artifact (new transitive crate, relicensed data crate) gets a **narrow, per-crate, commented**
    `deny.toml` exception pushed onto the dependabot branch itself; a real license/advisory problem
    means close the PR with the evidence + `@dependabot ignore this minor version`.
- **Never merge a base-image bump of `rust` in the Dockerfile** — the image moves in lockstep with
  `rust-toolchain.toml` only (both are dependabot-ignored by config; a toolchain upgrade is its own
  deliberate PR touching toolchain + Dockerfile + devcontainer together).
- Cross-repo: if `common-actions` changed, merge it (and its release PR, to cut the tag) **before**
  consumer repos bump their SHA pins to it.

**2. Then merge the release-please PR — last, and only when you mean to ship.**

- release-please refreshes its PR after **every** push to `main`; each dependabot/feature merge
  updates the pending version + changelog. Merging dependabot PRs *after* the release PR means they
  miss the release. So: drain the queue, **wait for the release PR to refresh** (its head SHA
  changes; ~1 min after the last merge), skim the generated changelog, then
  `gh pr merge <n> --auto --squash`.
- Merging it is a **deploy decision, not housekeeping**: tag is cut → publish DAG builds, scans,
  SBOMs, signs, dispatches → CD cosign-verifies and deploys the digest to every cell with
  `enabled: true` in `cells.json` (today: `dev`). Leaving the release PR open is free — it just
  keeps accumulating; there is no need to release after every merge.
- `chore:`/`ci:`/`docs:` merges don't trigger a release PR at all; `fix:` bumps patch, `feat:`
  bumps minor — which is why the `pr-title` gate is required: the PR title *is* the version signal.
- Provisioning a new cell = `terraform apply` its root under
  `infrastructure-live/routeplane/cells/`, then flip its `enabled` in `cells.json`.

### Change the platform itself

- **Trunk protection / required checks**: edit `infrastructure-live/github/main.tf` via PR. Required
  check names must match the **exact CI job names** — a typo silently bricks merging for that repo,
  so verify against a recent run before promoting a new check.
- **New CI gate**: add a composite to `common-actions/` (PR), let consumers pin the new SHA, run it
  non-required for a burn-in week, then promote it to required in `github/main.tf`.
- **New repo**: add it to the `github/main.tf` repo map so it is trunk-protected from birth.
- Anything that adds standing cost or changes architecture: write an ADR in `docs/adr/` first.

### Troubleshooting

| Symptom | Cause / fix |
|---|---|
| PR won't merge, everything green | `mergeStateStatus: BEHIND` → `gh pr update-branch` |
| `pr-title` check red | Title isn't `type(scope): subject` — edit the PR title (check re-runs on edit) |
| `secret-scan` red | gitleaks found a secret-shaped string. If it's a real secret: rotate it, rewrite history. False positive: inline `# gitleaks:allow` on that line — never a path allowlist |
| Edits silently reverting (OneDrive checkouts) | Known WSL2/OneDrive sync issue — re-verify with `git diff` and commit promptly |
| `error: could not lock config file .git/config` | Stale lock from OneDrive sync: remove `.git/config.lock` when no git process is running |
| Local `cargo` can't find OpenSSL | Use the devcontainer, or `OPENSSL_LIB_DIR=/usr/lib/x86_64-linux-gnu OPENSSL_INCLUDE_DIR=/usr/include` |

### Canonical references

[`branching-and-devex.md`](https://github.com/RST-Holdings/docs/blob/main/architecture/branching-and-devex.md)
(operations manual) ·
[`devsecops-pipeline.md`](https://github.com/RST-Holdings/docs/blob/main/architecture/devsecops-pipeline.md)
(CI/CD + supply chain) ·
[`deployment-topology.md`](https://github.com/RST-Holdings/docs/blob/main/architecture/deployment-topology.md)
(cells) ·
[ADR-008](https://github.com/RST-Holdings/docs/blob/main/adr/008-cicd-segregation-and-supply-chain-cd.md) ·
[ADR-012](https://github.com/RST-Holdings/docs/blob/main/adr/012-trunk-based-development-and-entitlement-driven-delivery.md) (incl. the 2026-06-10 amendments) ·
[ADR-013](https://github.com/RST-Holdings/docs/blob/main/adr/013-cell-based-tenancy-and-deployment-topology.md)
