# Routeplane Agent Swarm

A team of specialized, PhD-caliber subagents for the Routeplane meta-repo. They live at the **root** `.claude/agents/` so each is available across every sub-repo (`routeplane/`, `infrastructure-live/`, `terraform-modules/`, `docs/`).

These are persistent [Claude Code subagent](https://docs.claude.com/en/docs/claude-code/sub-agents) definitions — invocable any session by name or via auto-routing on their `description`.

## Roster

| Agent | Lane | Primary repos |
|---|---|---|
| `rust-gateway-engineer` | Axum + Tokio data plane — proxy orchestrator, `Provider` trait, `models.rs` translation, guardrails, auth, observability, async/tail-latency, SRE reliability | `routeplane/` |
| `cloud-infra-engineer` | Azure Container Apps (scale-to-zero), ACR, Log Analytics, OIDC, Terraform modules + live wiring, deploy target (terraform-apply), FinOps | `terraform-modules/`, `infrastructure-live/`, `common-actions/` |
| `cicd-architect` | Delivery pipeline across the multi-repo org — GitHub Actions topology, reusable workflows in `common-actions/`, software supply-chain integrity (SLSA / SBOM / signing, pinned actions), progressive delivery + rollback, quality gates, DORA | `common-actions/`, every repo's `.github/` |
| `agentic-security-engineer` | The moat — MCP gateway, agent governance, threat detection (injection/exfil/jailbreak), PII/guardrails, sovereign data-residency routing, DPDP | `routeplane/`, `docs/` |
| `provider-integrations-dx` | LLM provider adapters, OpenAI-compat contract fidelity, SSE streaming, SDK/CI/DX ergonomics | `routeplane/` |
| `applied-ai-researcher` | Model routing/selection, semantic caching, security ML, eval harnesses / LLM-as-judge, cost/quality/latency Pareto | `routeplane/`, `docs/` |
| `ai-product-researcher` | Competitive analysis, positioning/feature-matrix, India-first/DPDP GTM, roadmap, PRDs, ADRs | `docs/` |

## Handoffs & seams

The agents are designed to interlock; each one names its counterparts so Claude can chain or delegate across lanes. Most edges are two-way collaborations (`↔`); a couple are one-way thematic dependencies (`→`).

| Seam | What flows across it |
|---|---|
| `ai-product-researcher` ↔ `applied-ai-researcher` | Product asks "is this feasible, and where's the cost/quality frontier?"; applied returns measured numbers and a buildable recommendation that product turns into a bet. |
| `applied-ai-researcher` ↔ `agentic-security-engineer` | The detector-quality bar. Applied trains and measures the injection/exfil/PII classifiers; security sets the operating point, threat coverage, and the hot-path false-positive/latency budget they must hit. |
| `applied-ai-researcher` ↔ `rust-gateway-engineer` | Applied validates a technique (routing, caching) in a prototype; gateway lands it as the production hot-path implementation. |
| `agentic-security-engineer` ↔ `rust-gateway-engineer` | Security specs the controls (guardrails, auth, tool mediation); gateway integrates them on the hot path without wrecking tail latency. |
| `agentic-security-engineer` ↔ `provider-integrations-dx` | Cross-provider tool-call / function-calling semantics — where security's tool-mediation meets provider-translation fidelity. |
| `provider-integrations-dx` ↔ `rust-gateway-engineer` | The streaming/translation seam: provider-integrations owns chunk-shape + OpenAI-compat fidelity; gateway owns backpressure + async mechanics. |
| `cloud-infra-engineer` ↔ `rust-gateway-engineer` | Gateway builds the binary; cloud-infra deploys and runs it on ACA and owns the FinOps/ADR for any cost-adding choice. |
| `agentic-security-engineer` ↔ `cloud-infra-engineer` | Sovereign routing: security defines the residency correctness property; cloud-infra builds the per-region environments that enforce it. |
| `provider-integrations-dx` → `ai-product-researcher` | Keeps the "faithful multi-provider fidelity" best-of-breed pillar that product sells actually true. |
| `cloud-infra-engineer` → `ai-product-researcher` | Serverless / scale-to-zero unit economics are the cost structure product positions as "frugality is strategy." |
| `cicd-architect` ↔ `cloud-infra-engineer` | The deploy boundary: cicd owns the pipeline and artifact integrity up to the deploy invocation; cloud-infra owns the Azure/Terraform target and the terraform-apply. Co-own `common-actions/`. |
| `cicd-architect` ↔ `rust-gateway-engineer` / `provider-integrations-dx` | Their `cargo` / `wiremock` / `proptest` verification becomes the *required* merge gates cicd enforces. |
| `cicd-architect` ↔ `applied-ai-researcher` | Applied's eval harnesses become CI regression gates for routing/guardrail quality. |
| `cicd-architect` ↔ `agentic-security-engineer` | Build-time vs runtime trust: cicd owns supply-chain integrity (SLSA/SBOM/signing) and secret-in-CI hygiene; security owns runtime/data-plane trust boundaries. |
| `cicd-architect` → `ai-product-researcher` | Fast, safe delivery (DORA) is what lets product actually ship the roadmap. |

Two structural facts worth holding:

- **`rust-gateway-engineer` is the convergence point.** Security's controls, applied-AI's routing/caching, and provider-integrations' translation all become running code on its hot path. A cross-lane change usually lands here last.
- **Sovereign routing is a three-agent triangle.** `agentic-security-engineer` defines it as a correctness property → `cloud-infra-engineer` builds the per-region enforcement → `ai-product-researcher` sells it as the DPDP wedge. Touch one and you implicate the other two.

## MCP context per agent

Each agent's `tools:` frontmatter grants a scoped, **read/navigation** subset of the relevant MCP servers (mutations go through the agents' own `Edit`/`Write`/`Bash`). MCP tool grants must be listed individually — no wildcards.

| Agent | context7 (live docs) | serena (semantic code nav) | github (repos/PRs/issues) |
|---|:---:|:---:|:---:|
| `rust-gateway-engineer` | ✅ | ✅ | ✅ |
| `provider-integrations-dx` | ✅ | ✅ | ✅ |
| `agentic-security-engineer` | ✅ | ✅ | ✅ + `run_secret_scanning` |
| `applied-ai-researcher` | ✅ | ✅ | ✅ |
| `cloud-infra-engineer` | ✅ | — | ✅ |
| `cicd-architect` | ✅ | — | ✅ + `run_secret_scanning` |
| `ai-product-researcher` | ✅ | — | ✅ |

- **context7** — up-to-date library/API docs (`resolve-library-id`, `query-docs`). Granted to all.
- **serena** — symbol-level code navigation (`find_symbol`, `find_referencing_symbols`, `get_diagnostics_for_file`, …, plus `activate_project`). Granted to the code-touching agents only; the infra (HCL), CI/CD (YAML), and product (prose) agents skip it.
- **github** — read/search tools (`search_code`, `pull_request_read`, `list_issues`, …). Granted to all; the security and cicd agents also get `run_secret_scanning`.
- Gmail / Calendar / Drive are intentionally **not** granted — not dev context.

> The MCP servers must be connected in the session for these grants to resolve; the agent file only grants *permission* to use them.

## Model & effort

Every agent is pinned to `model: claude-opus-4-8` with `effort: high` — the deepest-reasoning configuration, chosen because these are specialist roles doing threat modeling, systems design, and strategy where reasoning quality dominates.

- **Pinned, not aliased.** `claude-opus-4-8` is the full model ID, so behavior doesn't drift when the floating `opus` alias later moves to a newer model. Override per session with the `CLAUDE_CODE_SUBAGENT_MODEL` env var when you need to.
- **Cost tension with frugality.** Opus-4.8-at-`high` is the most expensive combination, which sits against the ~$1,000 frugality constraint below. For agents that auto-route frequently or run proactively on every diff or roadmap nudge, consider dropping `effort` to `medium` (or the model to `sonnet`) for routine passes and reserving Opus-high for deep work.

## Persistent memory

Every agent carries `memory: project`, so each gets a version-controlled knowledge directory at `.claude/agent-memory/<agent-name>/` that survives across sessions. The agents are prompted to consult it before work and update it after — an institutional knowledge base that compounds:

| Agent | What it accumulates |
|---|---|
| `agentic-security-engineer` | Threat patterns, false-positive catalog, detector tuning |
| `applied-ai-researcher` | Eval results, baselines, what's been tried and what failed |
| `ai-product-researcher` | Competitive-intel log, positioning decisions |
| `rust-gateway-engineer` | Codepaths, concurrency gotchas, architectural decisions |
| `provider-integrations-dx` | Per-provider quirks and the capability map |
| `cloud-infra-engineer` | Infra patterns, cost baselines, plan/apply history |

Because the scope is `project`, these directories are **checked into version control** and shared with the team. The trade-off: six `MEMORY.md` files to keep curated. Claude loads the first ~200 lines / 25 KB of each into context, so prune one when it grows noisy. Use `local` scope (uncommitted) for any agent whose notes shouldn't be shared.

## Using the swarm

- **Auto-route:** just describe a task — the matching `description` triggers delegation.
- **Explicit:** "Use the `agentic-security-engineer` to threat-model the MCP gateway."
- **Parallel:** name several in one message and Claude can fan them out, e.g. "Have `ai-product-researcher` scope the routing wedge while `applied-ai-researcher` prototypes the policy and `rust-gateway-engineer` plans the hot-path integration." Note the limits: Claude decides foreground vs background per task, subagents can't spawn other subagents, and each returns its result into the main context — so for *sustained* parallelism beyond a few independent one-shots, reach for [agent teams](https://docs.claude.com/en/docs/claude-code/sub-agents) rather than this swarm.

## Conventions

**Universal — every agent:**
- Read `CLAUDE.md` + relevant `docs/` first; honor the canonical-doc-per-topic rule and write an ADR for major architectural or product shifts.
- **Never** add `Co-Authored-By` / AI-authorship trailers to commits or PRs. Commit only when asked, inside the relevant sub-repo (changes don't span repos).
- Deliverables are decisions or evidence with receipts; state assumptions and residual uncertainty plainly.

**Where it applies — domain-scoped, not universal:**
- **Frugality (~$1,000 budget; serverless / scale-to-zero / in-memory by default)** — a hard design constraint for `rust-gateway-engineer`, `applied-ai-researcher`, and `cloud-infra-engineer`; a positioning theme for `ai-product-researcher`.
- **OIDC-only auth, no long-lived secrets** — enforced by `cloud-infra-engineer` and `cicd-architect` (the two places CI auth happens), reinforced by the security agent's secrets hygiene; not a product/applied concern.
- **`x-routeplane-*` / `rp_` branding is load-bearing** — the three `routeplane/` agents (`rust-gateway-engineer`, `provider-integrations-dx`, `agentic-security-engineer`).

## Maintenance

Subagent `tools:` lists require explicit `mcp__<server>__<tool>` identifiers (no wildcards). When a new serena/github tool ships that an agent should use, add it by name to that agent's `tools:` line. When you add or rename an agent, update the **Roster**, **Handoffs**, and **MCP context** tables together, and make sure any new cross-lane reference is named from *both* sides — the agents route off each other's names.