# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Routeplane is a neutral, multi-provider **AI Gateway + Agentic Security platform** — built **India-first, for the world** (the Sarvam AI playbook; India/DPDP is the go-to-market beachhead, the architecture is global from day one). It is an SRE-grade, OpenAI-compatible proxy in front of many LLM providers, with sovereign (data-residency) routing, full-lifecycle governance/FinOps, and — the moat — agentic security (MCP gateway + agent governance, plus integrated threat detection). What exists today is the high-speed **Data Plane** of a Control Plane / Data Plane split (Control Plane / dashboard not yet built — see `docs/adr/001-...`). The engine is Rust (Axum + Tokio), deployed serverless on Azure Container Apps with scale-to-zero to keep idle cost near $0.

**Read `docs/` before doing product/architecture work** — `docs/README.md` is the index. Canonical artifacts: `docs/product/feature-matrix.md` (positioning + competitive matrix), `docs/architecture/engineering-design.md` (deepest technical design — Rust/ACA), `docs/architecture/functional-spec.md` (data models, API, security), `docs/adr/` (decisions).

## Multi-repo layout (this is a workspace, not one repo)

The top-level directory is a meta-repo containing **several independently-versioned git repos** (each subdir has its own `.git`), mapping to GitHub org `RST-Holdings`. When committing, operate inside the relevant subdir — changes do not span repos. Caveat: the root meta-repo's own `origin` points at a personal `rohit-tambakhe/docs` repo (pushing with org credentials 403s); the real documentation repo is the `docs/` subdir (`RST-Holdings/docs`). The `docs/` remote currently embeds a PAT in `.git/config` — treat as sensitive.

- `routeplane/` — the Rust Data Plane application (the actual gateway). Most code work happens here.
- `docs/` — single source of truth for strategy/architecture/decisions. Structure: `docs/README.md` (index), `docs/product/` (feature-matrix), `docs/architecture/` (functional-spec, engineering-design), `docs/adr/`. One canonical doc per topic — no duplicates. Document every major architectural shift as a new ADR.
- `terraform-modules/` — reusable Azure Terraform modules (`acr`, `aca`, `aca_env`, `log_analytics`), consumed remotely via `git::https://github.com/RST-Holdings/terraform-modules.git//modules/<x>?ref=main`.
- `infrastructure-live/` — environment-specific Terraform that wires the modules together (`infrastructure-live/routeplane/dev/`).
- `common-actions/` — shared composite GitHub Actions (`rust-build/` builds + pushes the Docker image to ACR).
- Root `terraform/`, `k8s/`, `scripts/`, `db/migrations/` are empty placeholders for future phases — ignore unless populated.

## Build, run, test (all from `routeplane/`)

```bash
cargo build --release          # production build (matches Dockerfile, Rust 1.86)
cargo run                      # run locally on PORT (default 8080); needs .env with provider keys
cargo test                     # NOTE: no test suite exists yet — this currently runs 0 tests
cargo test <name>              # (once tests exist) run a single test by name substring
cargo clippy --all-targets     # lint
RUST_LOG=routeplane=debug cargo run   # override log filter
docker build -t routeplane:latest ./routeplane
```

Local run requires a `.env` with `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` (loaded via `dotenvy`), because `configs/keys.json` references them as `env:OPENAI_API_KEY` etc.

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
2. **Proxy handler** (`proxy.rs::chat_completions`) — the orchestrator:
   - **Pre-guardrails**: masks PII in every inbound message (`guardrails.rs`).
   - **Routing + fallback**: reads `x-routeplane-provider` (default `openai`); a comma-separated value like `openai,anthropic` is a **fallback chain** tried in order until one succeeds.
   - Resolves the provider API key from the `VirtualKey`; values prefixed `env:` are read from the process environment.
   - **Post-guardrails**: masks PII in the response.
   - **Records usage** into the observability engine.
   - If all providers fail → 500 with the last error.
3. **Providers** (`providers/`) — each implements the `Provider` trait (`providers/mod.rs`): `async fn chat_completion(request, api_key)`. Each provider **translates the canonical OpenAI-shaped `ChatCompletionRequest`/`ChatCompletionResponse` (`models.rs`) to/from its native API** (e.g. `anthropic.rs` maps to `/v1/messages`, `x-api-key`, `input_tokens`/`output_tokens`). To add a provider: implement the trait, add a field to `AppState`, and add a `match` arm in `proxy.rs`.

`AppState` (in `proxy.rs`) holds one long-lived instance of each provider, the guardrail engine, and the observability engine, shared via `Arc`.

### Other endpoints
- `GET /healthz` → liveness probe.
- `GET /analytics` → dumps recent usage events. Observability (`observability.rs`) is a deliberately frugal **in-memory `VecDeque` of the last 1000 events** — no database during Alpha. This is intentional; do not add a DB dependency without an ADR (Cosmos DB migration is a planned later phase).

## Git conventions

- **Never add AI co-authorship to commits.** Do NOT append `Co-Authored-By: Claude …` (or any AI/assistant) trailer to commit messages or PR descriptions — this is a hard rule for this project. Plain commit messages only.

## Conventions specific to this project

- **Branding is load-bearing**: public headers are `x-routeplane-api-key` and `x-routeplane-provider`; gateway keys use the `rp_` prefix. Keep "Routeplane" branding in user-facing strings.
- **Frugality is a design constraint**, not a nice-to-have: prefer serverless / scale-to-zero / in-memory over always-on infrastructure (~$1,000 budget). Significant cost-adding choices belong in an ADR.
- **Provider request mapping is lossy today** — e.g. Anthropic `max_tokens` is hardcoded to 1024 in `anthropic.rs`. When extending request fields, thread them through `models.rs` *and* each provider's translation.
- Streaming is not yet implemented despite `stream` existing on the request model; responses are buffered.

## CI

- `routeplane/.github/workflows/ci.yml`: on push/PR to `main`, logs into Azure (OIDC) + ACR, then builds & pushes the image via the shared `RST-Holdings/common-actions/rust-build@main` action, tagged with the commit SHA. (No test step — and no tests exist yet; the intended strategy — `wiremock` mock LLM, `sqlx::test`, unit tests — is specced in `docs/architecture/engineering-design.md` §24.)
- `infrastructure-live/.github/workflows/deploy.yml`: Terraform init/plan on PR, auto-apply on push to `main`.
