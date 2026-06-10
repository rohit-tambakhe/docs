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

Two robots open pull requests in these repos. You will see their names as PR authors:

- **Dependabot** proposes updates to things we depend on (Rust crates, GitHub Actions, Docker
  images). Each PR bumps one dependency (or one small group) to a newer version.
- **release-please** keeps **one** PR open per repo, titled like `chore(main): release 0.1.8`.
  That PR is "the next release": it collects everything merged since the last release into a
  changelog. **Merging it publishes a release and deploys it.** Leaving it open costs nothing.

**The rule: handle Dependabot PRs first. Merge the release PR last, and only when you actually
want to ship.** If you merge the release PR first, the dependency updates you merge afterwards
are left out of that release.

#### Handling a Dependabot PR

1. **All checks green?** Merge it:

   ```
   gh pr merge <number> --auto --squash
   ```

   `--auto` means "merge by itself once everything passes" — you don't have to watch it.

2. **GitHub says the branch is out of date / "BEHIND"?** That's normal. Our repos require every PR
   to be re-tested against the newest `main` before merging, and each merge makes the *other* open
   PRs out of date. Fix it with one command, then go back to step 1:

   ```
   gh pr update-branch <number>
   ```

   This means PRs merge **one at a time** — that's by design, not something to work around.

3. **A check is red?** Do **not** merge, and do not assume the robot is right — a red check means
   our safety net caught a problem with the new version. The two common cases:
   - **Build or tests fail** (`quality` / `coverage`): the new version usually needs a newer Rust
     compiler than the one we deliberately pin in `rust-toolchain.toml`. We don't change our code
     to chase a dependency. Close the PR with a comment saying why.
   - **`deps-audit` fails**: the new version pulled in something that violates our license or
     security policy. This needs a maintainer's judgment call — flag it to the CTO rather than
     deciding yourself.
   In both cases the update isn't lost — Dependabot will offer it again later, and a maintainer
   can tell it to stop offering it (an "ignore" rule in `.github/dependabot.yml`).

4. **One hard rule:** never merge an update to the `rust` Docker base image. Our Rust version is
   changed on purpose, in one PR that updates the toolchain file, Dockerfile, and devcontainer
   together — never piecemeal by a robot. (Dependabot is configured not to offer these, but if
   you ever see one, close it.)

#### Cutting a release (merging the release-please PR)

1. Finish merging everything you want in the release (features, fixes, Dependabot PRs).
2. **Wait a minute.** After every merge to `main`, release-please rewrites its PR to include what
   you just merged. Check the PR was just updated before you act on it.
3. Read the changelog in the PR body — that's literally what you're about to release.
4. Merge it the same way: `gh pr merge <number> --auto --squash`.
5. What happens next, automatically: a version tag is created → the image is built, scanned for
   vulnerabilities and secrets, and cryptographically signed → the deploy pipeline verifies that
   signature and rolls the new version out to every environment that's switched on in
   `infrastructure-live/routeplane/cells/cells.json` (today that's just `dev`).

Good to know: the version number comes from PR titles. `fix:` PRs bump 0.1.7 → 0.1.8, `feat:` PRs
bump 0.1.7 → 0.2.0, and `chore:`/`ci:`/`docs:` PRs don't trigger a release at all. That's why the
`pr-title` check is strict about titles.

One ordering rule for maintainers: if you changed `common-actions` (the shared CI building blocks),
merge that repo's PRs and its release first — other repos reference it by exact commit, so it has
to exist before they can point at it.

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
