# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Routeplane is a neutral, multi-provider **AI Gateway + Agentic Security platform** — built **India-first, for the world** (the Sarvam AI playbook; India/DPDP is the go-to-market beachhead, the architecture is global from day one). It is an SRE-grade, OpenAI-compatible proxy in front of many LLM providers, with sovereign (data-residency) routing, full-lifecycle governance/FinOps, and — the moat — agentic security (MCP gateway + agent governance, plus integrated threat detection). What exists today is the high-speed **Data Plane** of a Control Plane / Data Plane split (Control Plane / dashboard not yet built — see `docs/adr/001-...`). The engine is Rust (Axum + Tokio), deployed serverless on Azure Container Apps with scale-to-zero to keep idle cost near $0.

What the Data Plane does today (all implemented in `routeplane/`): OpenAI-compatible `/v1/chat/completions` over **four providers** (OpenAI, Anthropic, Gemini, Azure OpenAI), **streaming (SSE)** as well as buffered, **sovereign/data-residency routing** (PII classification → region-locked provider eligibility), pluggable **routing strategies** (priority/weighted/cost/latency), a lock-free **circuit breaker + latency EWMA** per provider, PII-masking guardrails, virtual-key auth, and in-memory observability.

**Read `docs/` before doing product/architecture work** — `docs/README.md` is the index. Canonical artifacts: `docs/product/feature-matrix.md` (positioning + competitive matrix), `docs/architecture/engineering-design.md` (deepest technical design — Rust/ACA), `docs/architecture/functional-spec.md` (data models, API, security), `docs/architecture/branching-and-devex.md` (trunk-based dev + entitlement delivery), `docs/architecture/deployment-topology.md` (cell-based tenancy + CD fan-out), `docs/adr/` (decisions, currently 001–020), `docs/product/prd/` (PRDs, currently 000–005: thin Control Plane master + sub-PRDs 001–004, agentic-security moat 005).

## Multi-repo layout (this is a workspace, not one repo)

The top-level directory is a meta-repo containing **several independently-versioned git repos** (each subdir has its own `.git`), mapping to GitHub org `RST-Holdings`. When committing, operate inside the relevant subdir — changes do not span repos. Caveat: the root meta-repo's own `origin` points at a personal `rohit-tambakhe/docs` repo (pushing with org credentials 403s); the real documentation repo is the `docs/` subdir (`RST-Holdings/docs`). The `docs/` remote currently embeds a PAT in `.git/config` — treat as sensitive.

- `routeplane/` — the Rust Data Plane application (the actual gateway), itself a **Cargo workspace** of several crates (see below). Most code work happens here.
- `docs/` — single source of truth for strategy/architecture/decisions. Structure: `docs/README.md` (index), `docs/product/` (feature-matrix, `prd/` 000–005, `portkey-parity/` program docs), `docs/architecture/` (functional-spec, engineering-design, devsecops-pipeline, platform-engineering), `docs/adr/`. One canonical doc per topic — no duplicates. Document every major architectural shift as a new ADR.
- `terraform-modules/` — reusable Azure Terraform modules (`acr`, `aca`, `aca_env`, `log_analytics`), consumed remotely via `git::https://github.com/RST-Holdings/terraform-modules.git//modules/<x>?ref=main`.
- `infrastructure-live/` — environment-specific Terraform that wires the modules together (`infrastructure-live/routeplane/dev/`).
- `common-actions/` — shared composite GitHub Actions (`rust-build/` builds + pushes the Docker image to ACR).
- `routeplane-skills/` — the `RST-Holdings/routeplane-skills` Claude plugin/marketplace repo (agent swarm + skills).
- Root `terraform/`, `k8s/`, `scripts/`, `db/migrations/` are empty placeholders for future phases — ignore unless populated.

## The `routeplane/` Cargo workspace (the Data Plane)

`routeplane/Cargo.toml` is a workspace; shared dependency versions live there under `[workspace.dependencies]` and member crates opt in with `<dep> = { workspace = true }`. The members, in dependency order:

- **`crates/types`** (`routeplane_types`) — the canonical, OpenAI-shaped wire models: `ChatCompletionRequest/Response`, `Message`, `Choice`, `Usage`, the streaming types (`ChatCompletionChunk`, `ChunkChoice`, `Delta`), and `Region` (a free-form residency jurisdiction code like `"IN"`). This is the old `models.rs` — extend request/response fields here first, then thread them through each adapter.
- **`crates/adapters`** (`routeplane_adapters`) — the `Provider` trait and one module per provider (`openai`, `anthropic`, `gemini`, `azure_openai`, plus `sse` helpers). Each adapter translates the canonical models to/from its native API. This is the old `providers/`.
- **`crates/residency`** (`routeplane_residency`) — the sovereign-routing engine: `ResidencyEngine::classify` scans text for regulated personal data (Aadhaar/PAN/email/phone today — India/DPDP is "profile #0"), and `required_region` decides whether routing must be region-locked. Globalize by swapping the recognizer set, not the engine.
- **`crates/router`** (`routeplane_router`) — provider selection & resilience, network-free and lock-free: `RoutingStrategy` (Priority/Weighted/Cost/Latency) + `Router::order_candidates` for ordering, and `HealthTracker` = per-provider `CircuitBreaker` (atomic state machine) + `LatencyEwma`. The proxy owns *eligibility*; this crate owns *ordering + health*.
- **`crates/entitlements`** (`routeplane_entitlements`) — the entitlement seam ([ADR-012]): `CapabilitySet = tier_baseline(tier) ∪ overrides − holdbacks`, resolved once at auth into `TenantContext`, gated on the hot path via `capabilities.active(Feature::X)`. How tiers / custom-customer features / dark-launch are expressed — **as config, never branches or forks**. OpenFeature-shaped interface, in-process (no flag server).
- **`crates/routeplane`** (`routeplane`, the binary) — `main.rs` (Axum wiring), `auth.rs`, `guardrails.rs`, `observability.rs`, `proxy.rs` (the orchestrator). `AppState` here holds one long-lived instance of each provider plus the guardrail/observability/residency engines, the `HealthTracker`, and the `Router`, shared via `Arc`.

## Build, run, test (all from `routeplane/`)

```bash
cargo build --release          # production build (matches Dockerfile, Rust 1.86)
cargo run -p routeplane        # run the gateway locally on PORT (default 8080); needs .env with provider keys
cargo test                     # run the whole workspace test suite (unit + wiremock adapter integration tests)
cargo test -p router           # test a single crate
cargo test <name>              # run a single test by name substring
cargo clippy --all-targets     # lint
RUST_LOG=routeplane=debug cargo run -p routeplane   # override log filter
docker build -t routeplane:latest ./routeplane      # build from the repo root
```

Tests exist now (they did not in earlier revisions): inline `#[cfg(test)]` modules cover the circuit breaker, latency EWMA, routing-strategy ordering (with an injectable clock/RNG so there's no time/`rand` flake), residency classification, and chunk serialization. A `wiremock`-backed adapter integration layer (per `docs/architecture/engineering-design.md` §24) exercises all four provider adapters — request/response translation and SSE streaming — with no real network calls.

Local run requires a `.env` with `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` (loaded via `dotenvy`), because `configs/keys.json` references them as `env:OPENAI_API_KEY` etc. Azure OpenAI is configured from env directly: `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_DEPLOYMENT`, `AZURE_OPENAI_API_VERSION` (default `2024-10-21`), `AZURE_OPENAI_REGION` (default `IN`), and `AZURE_OPENAI_API_KEY` (referenced from `keys.json`).

## Infrastructure

```bash
cd infrastructure-live/routeplane/dev
terraform init      # backend is azurerm + OIDC; pulls modules from the terraform-modules repo over git
terraform plan
terraform apply     # CI auto-applies on push to main (see infrastructure-live/.github/workflows/deploy.yml)
```

Terraform state lives in Azure Blob (`rg-routeplane-tfstate` / `strprouteplanetf`). All Azure auth — local and CI — uses **OIDC federated credentials**; never introduce long-lived service principal secrets.

## Request flow (the core of the Data Plane)

A request to `POST /v1/chat/completions` passes through, in order:

1. **Auth middleware** (`auth.rs`) — reads `x-routeplane-api-key`, looks it up in the in-memory `AuthState` (loaded once from `configs/keys.json` at startup), and injects the matched `VirtualKey` into request extensions. Missing/invalid key → 401.
2. **Proxy handler** (`proxy.rs::chat_completions`) — the orchestrator. It owns residency classification and eligibility; it delegates *ordering* to the `router` crate:
   - **Residency classification first** — `ResidencyEngine::classify` runs on the *original* message text **before** PII masking (masking would hide the very PII the classifier looks for). Combined with the `x-routeplane-residency` header, this yields a `required_region` (or `None`).
   - **Pre-guardrails** — masks PII in every inbound message (`guardrails.rs`).
   - **Eligibility** — if a region is required, only providers `is_resident_in(region)` are eligible (a **hard** constraint that overrides the client's `x-routeplane-provider`); if none qualify → **422**. Otherwise eligibility is the client's `x-routeplane-provider` chain (default `openai`; a comma-separated value like `openai,anthropic` is a fallback chain).
   - **Ordering** — `Router::order_candidates` drops circuit-OPEN providers and orders the rest by the `x-routeplane-strategy` header (`priority` default / `weighted` / `cost` / `latency`, case-insensitive).
   - **Attempt loop** — for each ordered candidate: resolve its API key from the `VirtualKey` (values prefixed `env:` are read from the process environment), time the call (feeding the latency EWMA on success *and* failure), record circuit-breaker success/failure, and on success run **post-guardrails** (mask PII in the response) + **record usage** (including the sovereign decision). First success wins; if all fail → **500** with the last error.
   - **Streaming branch** — when `stream: true`, the same eligibility/ordering/circuit/key logic runs, then an OpenAI-compatible `text/event-stream` is served (`data: {chunk}\n\n` … `data: [DONE]`). Fallback is allowed only until the **first chunk** is received; after that the proxy is committed to that provider and a mid-stream error simply ends the SSE response.
3. **Providers** (`crates/adapters`) — each implements the `Provider` trait (`adapters/src/lib.rs`): `chat_completion` (buffered) + `chat_completion_stream` (SSE; the default impl adapts the buffered call into a one-shot stream), plus `resident_regions()` for sovereign eligibility. Each adapter **translates the canonical `routeplane_types` models to/from its native API** (e.g. `anthropic.rs` maps to `/v1/messages`, `x-api-key`, `input_tokens`/`output_tokens`). To add a provider: implement the trait in a new `crates/adapters` module, add a field to `AppState`, add it to the `registry`/`provider_by_name` in `proxy.rs`, and register it in the `HealthTracker` list in `main.rs`. (Use the `routeplane-skills:add-llm-provider` skill — it walks the full path.)

### Request headers (all `x-routeplane-*`)
- `x-routeplane-api-key` — virtual key (required; `rp_`-prefixed).
- `x-routeplane-provider` — provider or comma-separated fallback chain (default `openai`). **Overridden** by sovereign routing when personal data + a residency region are present.
- `x-routeplane-residency` — requested data-residency region (e.g. `IN`); only enforced when the request also carries personal data.
- `x-routeplane-strategy` — `priority` (default) / `weighted` / `cost` / `latency`.

### Other endpoints
- `GET /` → plain-text banner (no auth). `GET /healthz` → liveness probe (no auth — probes must never require a key).
- `GET /analytics` → dumps recent usage events (authed). Observability (`observability.rs`) is a deliberately frugal **in-memory `VecDeque` of the last 1000 events** — no database during Alpha. This is intentional; do not add a DB dependency without an ADR (Cosmos DB migration is a planned later phase).

## Git conventions

- **Never add AI co-authorship to commits.** Do NOT append `Co-Authored-By: Claude …` (or any AI/assistant) trailer to commit messages or PR descriptions — this is a hard rule for this project. Plain commit messages only.
- Each sub-repo uses **release-please** (Conventional Commits → SemVer). Keep commit messages conventional (`feat:`, `fix:`, `chore:`, `docs:` …).

## Conventions specific to this project

- **Branding is load-bearing**: public headers are `x-routeplane-*` (above); gateway keys use the `rp_` prefix. Keep "Routeplane" branding in user-facing strings (e.g. the streaming response echoes `x-routeplane-provider`).
- **Crate boundaries are deliberate**: the proxy decides *who is eligible* (residency/chain); the `router` crate decides *ordering + health*; adapters only *translate*. Keep that separation — don't put network calls or locks in `router`, and don't put routing policy in adapters.
- **Hot path is lock-free**: `CircuitBreaker` and `LatencyEwma` use atomics (with injectable clock/RNG for deterministic tests). Preserve that — no mutex on the request path.
- **Frugality is a design constraint**, not a nice-to-have: prefer serverless / scale-to-zero / in-memory over always-on infrastructure (~$1,000 budget). Significant cost-adding choices belong in an ADR.
- **Provider request mapping is still lossy** — e.g. Anthropic `max_tokens` is hardcoded to 1024 in `anthropic.rs` (buffered and streaming). When extending request fields, thread them through `crates/types` *and* each adapter's translation.
- **Streaming-DLP is best-effort**: post-guardrail PII masking on streamed responses runs per-chunk, so PII spanning a chunk boundary can slip through (a known limitation; the guardrail is deliberately not skipped).

## CI

- `routeplane/.github/workflows/ci.yml`: on push/PR to `main`, logs into Azure (OIDC) + ACR, then builds & pushes the image via the shared `RST-Holdings/common-actions/rust-build@main` action, tagged with the commit SHA. (The workspace test suite — unit tests plus the `wiremock` adapter integration layer per `docs/architecture/engineering-design.md` §24 — gates the pipeline twice: `quality` (fmt+clippy+test) is a required merge check on the zero-bypass ruleset, and the main-push `build` job has `needs: quality`, so a test failure skips the entire image build/sign/dispatch DAG. Verified 2026-06-11.)
- `infrastructure-live/.github/workflows/deploy.yml`: Terraform init/plan on PR, auto-apply on push to `main`.
- All non-trivial CI logic lives in **composite actions** in `common-actions/`; workflows stay script-free (no inline `run:` for real logic).
