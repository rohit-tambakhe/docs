# AI Gateway — End-to-End Design Specification

> **Author:** Rohit Tambakhe  
> **Version:** 1.0  
> **Date:** June 2026  
> **Status:** Draft — Active Development

---

## Table of Contents

1. [Product Vision & Principles](#1-product-vision--principles)
2. [System Architecture Overview](#2-system-architecture-overview)
3. [Component Design Specifications](#3-component-design-specifications)
   - 3.1 [API Proxy Engine](#31-api-proxy-engine)
   - 3.2 [Routing & Load Balancer](#32-routing--load-balancer)
   - 3.3 [Semantic Cache Layer](#33-semantic-cache-layer)
   - 3.4 [Virtual Key Manager](#34-virtual-key-manager)
   - 3.5 [Guardrails Engine](#35-guardrails-engine)
   - 3.6 [Observability Pipeline](#36-observability-pipeline)
   - 3.7 [Prompt Registry](#37-prompt-registry)
   - 3.8 [Agent Tracing & Policy Engine](#38-agent-tracing--policy-engine)
   - 3.9 [Budget & FinOps Engine](#39-budget--finops-engine)
   - 3.10 [Control Plane API](#310-control-plane-api)
4. [Data Models](#4-data-models)
5. [API Specification](#5-api-specification)
6. [Multi-Tenancy Design](#6-multi-tenancy-design)
7. [Security Architecture](#7-security-architecture)
8. [Deployment Architecture](#8-deployment-architecture)
9. [Observability Stack Design](#9-observability-stack-design)
10. [Technology Stack](#10-technology-stack)
11. [Performance Targets & SLOs](#11-performance-targets--slos)
12. [Phase Roadmap & Feature Gates](#12-phase-roadmap--feature-gates)
13. [Database Schema](#13-database-schema)
14. [Configuration Schema (GitOps)](#14-configuration-schema-gitops)
15. [Zero-Cost Infrastructure Specification](#15-zero-cost-infrastructure-specification)

---

## 1. Product Vision & Principles

### Vision Statement

> A GitOps-native, Kubernetes-first, SRE-grade AI control plane — the enforcement point for every AI transaction in the enterprise.

### Product Positioning

The AI Gateway sits at **Layer 3** of the AI stack:

```
Layer 5 │  AI Applications          (Copilots, agents, chatbots, RAG pipelines)
Layer 4 │  AI Orchestration         (LangChain, LlamaIndex, CrewAI, AutoGen)
Layer 3 │  ► AI GATEWAY ◄           ← This product
Layer 2 │  Model APIs               (OpenAI, Anthropic, Gemini, Bedrock, Mistral)
Layer 1 │  Compute / Hardware       (NVIDIA GPUs, TPUs, hyperscaler data centres)
```

It is **not** a hardware/compute product. It is middleware — a software control plane that normalises, routes, governs, and observes every LLM API call in an organisation.

### Design Principles

| # | Principle | Implication |
|---|-----------|-------------|
| 1 | **Transparency-first** | Zero-overhead pass-through by default; all features opt-in |
| 2 | **Provider-agnostic** | No lock-in to any single LLM provider |
| 3 | **GitOps-native** | Every config change is a git commit; no click-ops in production |
| 4 | **SRE-grade reliability** | P99 latency overhead < 10ms; 99.99% gateway uptime SLO |
| 5 | **Security by design** | Least-privilege, zero-trust, full audit trail |
| 6 | **Cost-first observability** | Every token attributed to a team, project, and use case |
| 7 | **Agentic-ready** | Designed for multi-agent call graphs, not just single-turn requests |

---

## 2. System Architecture Overview

### High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                          CLIENT APPLICATIONS                        │
│  (Python SDK / Node SDK / REST / LangChain / OpenAI-compat client)  │
└─────────────────────────┬───────────────────────────────────────────┘
                          │ HTTPS / gRPC
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         INGRESS LAYER                               │
│              Traefik / Caddy   (TLS termination, rate limiting)     │
└─────────────────────────┬───────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      GATEWAY CORE (Go)                              │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐   │
│  │  Auth &      │  │  Request     │  │   Guardrails Engine      │   │
│  │  VKey Mgr    │  │  Normaliser  │  │   (Input / Output)       │   │
│  └──────┬───────┘  └──────┬───────┘  └────────────┬─────────────┘   │
│         │                 │                       │                 │
│  ┌──────▼─────────────────▼───────────────────────▼──────────────┐  │
│  │                   ROUTING ENGINE                              │  │
│  │    fallback │ cost-based │ latency-based │ load-balanced      │  │
│  └──────┬────────────────────────────────────────────────────────┘  │
│         │                                                           │
│  ┌──────▼───────────────────────────────────────────────────────┐   │
│  │                  SEMANTIC CACHE LAYER                        │   │
│  │             Redis (exact) + pgvector (semantic)              │   │
│  └──────┬───────────────────────────────────────────────────────┘   │
│         │  Cache miss                                               │
└─────────┼───────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     PROVIDER ADAPTERS                               │
│                                                                     │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐   │
│  │ Anthropic│ │  OpenAI  │ │  Gemini  │ │  Bedrock │ │  Ollama  │   │
│  │ Adapter  │ │ Adapter  │ │ Adapter  │ │ Adapter  │ │ Adapter  │   │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘   │
│   + Mistral  + Cohere  + Azure OpenAI  + Custom endpoints           │
└─────────────────────────────────────────────────────────────────────┘
          │
          ▼ (response path)
┌─────────────────────────────────────────────────────────────────────┐
│                   OBSERVABILITY PIPELINE                            │
│                                                                     │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │  Async event bus (buffered channel)                         │   │
│   │  → Token counter → Cost calculator → Latency recorder       │   │
│   │  → Trace exporter (OTLP) → Log writer (Loki)                │   │
│   └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      DATA LAYER                                     │
│                                                                     │
│  PostgreSQL (config, keys, prompts)  │  Redis (cache, rate limits)  │
│  ClickHouse (analytics, usage)       │  Vault (provider secrets)    │
└─────────────────────────────────────────────────────────────────────┘
```

### Control Plane vs. Data Plane

| Plane | Components | Latency Sensitivity | Persistence |
|-------|-----------|--------------------| ------------|
| **Data Plane** | Proxy engine, routing, cache, guardrails | Extremely high (P99 < 10ms overhead) | Stateless |
| **Control Plane** | Dashboard, config API, budget engine, key manager | Low | Stateful (PostgreSQL) |
| **Analytics Plane** | Observability pipeline, ClickHouse, Grafana | Async / best-effort | Append-only |

---

## 3. Component Design Specifications

### 3.1 API Proxy Engine

**Language:** Go  
**Framework:** Standard `net/http` + custom middleware chain  
**Protocol support:** REST (HTTP/1.1, HTTP/2), SSE (streaming), WebSocket (future)

#### Middleware Chain (ordered)

```
Request →
  [1] TLS termination (Traefik/Caddy, upstream)
  [2] Request ID injection           (X-Request-ID header)
  [3] Virtual key authentication     (Bearer token lookup → tenant context)
  [4] Rate limit check               (Redis token bucket per vkey)
  [5] Budget check                   (Postgres: remaining tokens for this period)
  [6] Input guardrails               (PII scan, injection detect, topic filter)
  [7] Request normalisation          (provider-agnostic schema)
  [8] Cache lookup                   (Redis exact → pgvector semantic)
  [9] Routing decision               (select provider + model)
 [10] Provider adapter call          (HTTP to upstream LLM API)
 [11] Output guardrails              (toxicity, hallucination score, format check)
 [12] Cache write (async)            (store response if cacheable)
 [13] Observability event emit (async)(token count, cost, latency → event bus)
 [14] Response                       (stream or buffer to client)
← Response
```

#### Key Interfaces

```go
// Core proxy interface
type ProxyHandler interface {
    Handle(ctx context.Context, req *NormalisedRequest) (*NormalisedResponse, error)
}

// Provider adapter interface
type ProviderAdapter interface {
    Name() string
    Call(ctx context.Context, req *NormalisedRequest) (*NormalisedResponse, error)
    Stream(ctx context.Context, req *NormalisedRequest) (<-chan StreamChunk, error)
    TokenCount(req *NormalisedRequest) (int, error)
    Models() []ModelInfo
}

// Middleware interface
type Middleware func(next ProxyHandler) ProxyHandler
```

#### Streaming Design

- Server-Sent Events (SSE) passed through transparently
- Token counting on stream completion (last chunk carries `usage` block)
- Observability event emitted post-stream, not mid-stream
- Backpressure handled via buffered channels (size: 256)

---

### 3.2 Routing & Load Balancer

**Design:** Pluggable strategy pattern

#### Routing Strategies

```go
type RoutingStrategy string

const (
    StrategyFallback      RoutingStrategy = "fallback"       // ordered list, fail through
    StrategyCostOptimal   RoutingStrategy = "cost-optimal"   // cheapest model meeting quality SLA
    StrategyLatencyBased  RoutingStrategy = "latency-based"  // lowest P50 last-5-min
    StrategyLoadBalanced  RoutingStrategy = "round-robin"    // across provider accounts
    StrategyWeighted      RoutingStrategy = "weighted"       // explicit weight distribution
    StrategyModelRouter   RoutingStrategy = "model-router"   // semantic routing (future)
)
```

#### Fallback Chain Specification

```yaml
# Example routing config
routing:
  strategy: fallback
  targets:
    - provider: anthropic
      model: claude-sonnet-4-6
      weight: 1
      timeout_ms: 30000
    - provider: openai
      model: gpt-4o
      weight: 1
      timeout_ms: 30000
      condition: on_error  # activate on 5xx or timeout from primary
    - provider: gemini
      model: gemini-2.0-flash
      weight: 1
      timeout_ms: 20000
      condition: on_error
  retry:
    max_attempts: 3
    backoff: exponential
    base_delay_ms: 100
    max_delay_ms: 5000
    jitter: true
```

#### Health Tracking

- Per-provider circuit breaker (half-open after 30s, closed after 3 successes)
- Rolling 60-second error rate window
- P50/P95 latency tracked per provider per model (in-memory, Redis-backed)
- Health state exported as Prometheus metrics

---

### 3.3 Semantic Cache Layer

**Two-tier design:**

| Tier | Store | Match Type | TTL | Hit Rate Target |
|------|-------|-----------|-----|----------------|
| L1 — Exact | Redis | SHA-256 of normalised prompt | Configurable (default: 1h) | ~30% |
| L2 — Semantic | pgvector (PostgreSQL) | Cosine similarity ≥ threshold | Configurable (default: 24h) | ~65% combined |

#### Cache Key Construction

```
exact_key   = SHA256(model + messages_json + temperature + top_p)
semantic_key = embed(last_user_message)  [1536-dim vector via text-embedding-3-small]
```

#### Semantic Cache Flow

```
1. Compute embedding of incoming request (last user turn)
2. Query pgvector: SELECT * FROM cache WHERE (1 - (embedding <=> $1)) > threshold
3. If hit: return cached response, emit cache_hit event
4. If miss: forward to provider, store (embedding + response) async
```

#### Cache Configuration

```yaml
cache:
  enabled: true
  l1_exact:
    ttl_seconds: 3600
    max_entries: 100000
  l2_semantic:
    enabled: true
    similarity_threshold: 0.95   # 0.0–1.0, higher = stricter match
    ttl_seconds: 86400
    embedding_model: text-embedding-3-small
    embedding_provider: openai
  bypass_on:
    - temperature_gt: 0.0        # don't cache non-deterministic requests
    - stream: true               # streaming requests bypass cache by default
    - header: "X-No-Cache: true"
```

---

### 3.4 Virtual Key Manager

**Purpose:** Issue scoped API keys to teams/projects. Provider keys never leave Vault.

#### Key Hierarchy

```
Organisation
  └── Workspace (e.g. "team-platform", "project-search")
        └── Virtual Key
              ├── allowed_providers: [anthropic, openai]
              ├── allowed_models: [claude-*, gpt-4o]
              ├── rate_limit: 1000 RPM
              ├── monthly_budget_usd: 500
              ├── guardrail_profile: "pii-strict"
              └── metadata: { team: "platform", cost_center: "CC-042" }
```

#### Key Lifecycle

```
CREATE → ACTIVE → [SUSPENDED] → ROTATED → REVOKED
                      ↑               |
                  (over budget)    (new key issued,
                                    old key 30-day grace)
```

#### Key Format

```
vk-<workspace_id>-<random_32_bytes_base58>
Example: vk-ws_prod_platform-4xKj9mNpQr8vYz3wA1bCdEfGhJkL
```

---

### 3.5 Guardrails Engine

**Design:** Layered classifier pipeline, pluggable per virtual key / workspace

#### Input Guardrails

| Guardrail | Implementation | Latency Target | Default |
|-----------|---------------|---------------|---------|
| PII Detection | Presidio (Microsoft OSS) | < 5ms | Off |
| Prompt Injection | Custom classifier + regex ruleset | < 3ms | On |
| Topic Blocker | Embedding similarity against blocked topics | < 8ms | Off |
| Jailbreak Detection | Fine-tuned binary classifier | < 5ms | On |
| Token Pre-check | tiktoken count before dispatch | < 1ms | On |
| Custom Regex | User-defined patterns | < 1ms | Off |

#### Output Guardrails

| Guardrail | Implementation | Latency Target | Default |
|-----------|---------------|---------------|---------|
| Toxicity Scoring | Detoxify or Perspective API | < 10ms | Off |
| PII in Response | Presidio scan on output | < 5ms | Off |
| Format Validation | JSON schema / regex | < 2ms | Off |
| Hallucination Score | Groundedness check vs. context | < 20ms | Off |
| Sensitive Data Mask | Pattern-based redaction | < 2ms | Off |

#### Guardrail Profile Schema

```yaml
guardrail_profile:
  id: pii-strict
  input:
    pii_detection:
      enabled: true
      action: block       # block | redact | warn
      entities: [PERSON, EMAIL, PHONE, SSN, CREDIT_CARD]
    injection_detection:
      enabled: true
      action: block
      sensitivity: high   # low | medium | high
    topic_blocker:
      enabled: true
      blocked_topics:
        - competitor_products
        - legal_advice
      action: block
  output:
    pii_in_response:
      enabled: true
      action: redact
    format_validation:
      enabled: false
      schema: null
```

---

### 3.6 Observability Pipeline

**Design:** Async event bus — zero impact on request latency

#### Event Schema

```go
type RequestEvent struct {
    // Identity
    RequestID      string    `json:"request_id"`
    TraceID        string    `json:"trace_id"`   // W3C TraceContext
    SpanID         string    `json:"span_id"`
    AgentRunID     string    `json:"agent_run_id,omitempty"`

    // Tenant
    WorkspaceID    string    `json:"workspace_id"`
    VirtualKeyID   string    `json:"virtual_key_id"`
    ProjectTag     string    `json:"project_tag"`
    CostCenter     string    `json:"cost_center"`

    // Request
    Provider       string    `json:"provider"`
    Model          string    `json:"model"`
    InputTokens    int       `json:"input_tokens"`
    OutputTokens   int       `json:"output_tokens"`
    CachedTokens   int       `json:"cached_tokens"`

    // Performance
    LatencyMs      int64     `json:"latency_ms"`
    TTFB_Ms        int64     `json:"ttfb_ms"`    // time to first byte
    Streaming      bool      `json:"streaming"`
    CacheHit       string    `json:"cache_hit"`  // "none" | "exact" | "semantic"

    // Cost
    InputCostUSD   float64   `json:"input_cost_usd"`
    OutputCostUSD  float64   `json:"output_cost_usd"`
    TotalCostUSD   float64   `json:"total_cost_usd"`

    // Status
    StatusCode     int       `json:"status_code"`
    ErrorCode      string    `json:"error_code,omitempty"`
    GuardrailHit   string    `json:"guardrail_hit,omitempty"`

    Timestamp      time.Time `json:"timestamp"`
}
```

#### Pipeline Architecture

```
Request completion
      │
      ▼
[Buffered Channel]  ──overflow──▶  [Drop + increment dropped_events_total metric]
      │
      ▼ (goroutine pool, 8 workers)
[Event Processor]
      │
      ├──▶ [Budget Deductor]       → PostgreSQL (UPDATE remaining_budget)
      ├──▶ [ClickHouse Writer]     → Batch insert (1000 events or 1s, whichever first)
      ├──▶ [Prometheus Counters]   → In-process metrics
      └──▶ [OTLP Trace Exporter]  → Jaeger / Tempo
```

#### Prometheus Metrics Exposed

```
# Request counters
ai_gateway_requests_total{provider, model, workspace, status}
ai_gateway_tokens_total{provider, model, workspace, type}  # type=input|output|cached
ai_gateway_cost_usd_total{provider, model, workspace}

# Latency
ai_gateway_request_duration_ms{provider, model, workspace, quantile}
ai_gateway_ttfb_ms{provider, model, quantile}

# Cache
ai_gateway_cache_hits_total{type}  # type=exact|semantic
ai_gateway_cache_size{tier}        # tier=l1|l2

# Circuit breaker
ai_gateway_circuit_breaker_state{provider}  # 0=closed, 1=half-open, 2=open

# Budget
ai_gateway_budget_remaining_usd{workspace}
ai_gateway_budget_utilisation_pct{workspace}
```

---

### 3.7 Prompt Registry

**Purpose:** Version-controlled, deployable prompt templates

#### Prompt Object

```go
type Prompt struct {
    ID          string            `json:"id"`           // slug: "customer-support-v2"
    WorkspaceID string            `json:"workspace_id"`
    Name        string            `json:"name"`
    Description string            `json:"description"`
    Version     int               `json:"version"`
    Status      PromptStatus      `json:"status"`       // draft | staging | production
    Template    string            `json:"template"`     // Handlebars/Jinja2 template
    Variables   []PromptVariable  `json:"variables"`
    ModelHints  ModelHints        `json:"model_hints"`  // preferred provider/model
    Tags        []string          `json:"tags"`
    CreatedBy   string            `json:"created_by"`
    CreatedAt   time.Time         `json:"created_at"`
    PromotedAt  *time.Time        `json:"promoted_at,omitempty"`
}

type PromptStatus string
const (
    Draft      PromptStatus = "draft"
    Staging    PromptStatus = "staging"
    Production PromptStatus = "production"
    Archived   PromptStatus = "archived"
)
```

#### Promotion Flow

```
draft → staging → production
          ↑
    (requires: test suite pass + manual approval via API/UI)
```

#### A/B Testing

```yaml
ab_test:
  id: support-prompt-ab-001
  prompt_a: customer-support-v2   # 70% traffic
  prompt_b: customer-support-v3   # 30% traffic
  split: [70, 30]
  metric: user_satisfaction_score
  min_samples: 500
  status: active
```

---

### 3.8 Agent Tracing & Policy Engine

**Purpose:** First-class support for multi-agent call graphs

#### Trace Context Model

```
AgentRun
  ├── run_id: "run_abc123"
  ├── root_task: "process customer refund request #45821"
  ├── initiated_by: workspace_id / user_id
  │
  ├── Span[0]: orchestrator_plan          (1 LLM call)
  │     └── tool_use: fetch_order_details (1 tool call)
  │
  ├── Span[1]: sub_agent_eligibility_check (2 LLM calls)
  │     ├── tool_use: check_policy_db
  │     └── tool_use: get_customer_tier
  │
  ├── Span[2]: sub_agent_refund_execute    (1 LLM call)
  │     └── tool_use: issue_refund         (requires human approval if > $500)
  │
  └── Span[3]: orchestrator_summarise      (1 LLM call)
```

#### MCP Gateway (Tool Access Control)

```yaml
mcp_policy:
  workspace: ws_prod_support
  allowed_servers:
    - url: https://internal-crm.company.com/mcp
      tools: [get_customer, get_order, check_policy]    # explicit allowlist
      rate_limit: 100/min
    - url: https://payments.company.com/mcp
      tools: [issue_refund]
      requires_approval: true                           # human-in-the-loop gate
      approval_threshold_usd: 500
  denied_servers:
    - "*"  # default-deny anything not explicitly listed
```

#### Agent Policy Engine

```yaml
agent_policy:
  id: support-agent-policy
  max_iterations: 20          # kill runaway agents
  max_cost_per_run_usd: 2.00  # circuit breaker
  max_tokens_per_run: 50000
  allowed_models: [claude-*, gpt-4o]
  human_approval_required:
    - action_type: financial_transaction
      threshold_usd: 500
    - action_type: data_deletion
    - action_type: external_api_write
  audit_level: full           # none | summary | full
```

---

### 3.9 Budget & FinOps Engine

**Purpose:** Cost attribution and chargeback at business-process level

#### Budget Hierarchy

```
Organisation  ($50,000/month hard cap)
  └── Division: Engineering       ($30,000)
        ├── Workspace: platform   ($10,000)
        │     ├── Project: search-ai    ($3,000)
        │     └── Project: rec-engine  ($7,000)
        └── Workspace: data       ($20,000)

  └── Division: Support           ($20,000)
        └── Workspace: cx-agents  ($20,000)
```

#### Budget Enforcement Modes

| Mode | Behaviour | Use Case |
|------|-----------|---------|
| `hard` | Block requests when budget exhausted | Production safety |
| `soft` | Allow but alert at 80%, 95%, 100% | Dev / experimental |
| `notify-only` | Never block, always alert | Budget visibility only |

#### Chargeback Export Schema

```json
{
  "period": "2026-06",
  "generated_at": "2026-07-01T00:00:00Z",
  "entries": [
    {
      "cost_center": "CC-042",
      "team": "platform-engineering",
      "project": "search-ai",
      "total_cost_usd": 2847.32,
      "breakdown": {
        "anthropic": { "input_tokens": 45000000, "output_tokens": 12000000, "cost_usd": 1923.00 },
        "openai":    { "input_tokens": 12000000, "output_tokens":  3000000, "cost_usd":  924.32 }
      },
      "cache_savings_usd": 340.10,
      "requests_total": 284721,
      "agents_runs_total": 1203
    }
  ]
}
```

---

### 3.10 Control Plane API

**Design:** RESTful, JSON, OpenAPI 3.1 spec  
**Auth:** Bearer token (admin JWT) or Virtual Key with `admin` scope  
**Base URL:** `https://gateway.yourcompany.com/api/v1`

#### Endpoint Groups

| Group | Prefix | Description |
|-------|--------|-------------|
| Proxy | `/v1/` | OpenAI-compatible LLM proxy endpoints |
| Keys | `/api/v1/keys` | Virtual key CRUD |
| Workspaces | `/api/v1/workspaces` | Workspace management |
| Routing | `/api/v1/routing` | Routing config CRUD |
| Prompts | `/api/v1/prompts` | Prompt registry |
| Guardrails | `/api/v1/guardrails` | Guardrail profile management |
| Budget | `/api/v1/budgets` | Budget config and usage |
| Analytics | `/api/v1/analytics` | Usage queries |
| Agents | `/api/v1/agents` | Agent run history, policy |
| Health | `/healthz`, `/readyz` | Kubernetes probes |

---

## 4. Data Models

### Core Entities (PostgreSQL)

```sql
-- Workspaces (tenants)
CREATE TABLE workspaces (
    id              TEXT PRIMARY KEY,   -- ws_<nanoid>
    org_id          TEXT NOT NULL,
    name            TEXT NOT NULL,
    slug            TEXT UNIQUE NOT NULL,
    plan            TEXT NOT NULL DEFAULT 'free',  -- free | pro | enterprise
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Virtual Keys
CREATE TABLE virtual_keys (
    id              TEXT PRIMARY KEY,   -- vk_<nanoid>
    workspace_id    TEXT REFERENCES workspaces(id),
    name            TEXT NOT NULL,
    key_hash        TEXT UNIQUE NOT NULL,  -- bcrypt hash of the key
    key_prefix      TEXT NOT NULL,         -- first 12 chars (for display)
    allowed_providers  TEXT[] DEFAULT '{}',
    allowed_models     TEXT[] DEFAULT '{}',
    rate_limit_rpm  INTEGER DEFAULT 1000,
    monthly_budget_usd DECIMAL(12,4),
    guardrail_profile_id TEXT,
    metadata        JSONB DEFAULT '{}',
    status          TEXT DEFAULT 'active',  -- active | suspended | revoked
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    last_used_at    TIMESTAMPTZ
);

-- Provider Credentials (pointer to Vault path)
CREATE TABLE provider_credentials (
    id              TEXT PRIMARY KEY,
    workspace_id    TEXT REFERENCES workspaces(id),
    provider        TEXT NOT NULL,      -- anthropic | openai | gemini | ...
    vault_path      TEXT NOT NULL,      -- e.g. secret/ws_abc/anthropic
    alias           TEXT,               -- friendly name
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Routing Configs
CREATE TABLE routing_configs (
    id              TEXT PRIMARY KEY,
    workspace_id    TEXT REFERENCES workspaces(id),
    name            TEXT NOT NULL,
    strategy        TEXT NOT NULL,
    targets         JSONB NOT NULL,
    retry_config    JSONB,
    is_default      BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Prompts
CREATE TABLE prompts (
    id              TEXT PRIMARY KEY,   -- slug: my-prompt
    workspace_id    TEXT REFERENCES workspaces(id),
    version         INTEGER NOT NULL DEFAULT 1,
    status          TEXT NOT NULL DEFAULT 'draft',
    template        TEXT NOT NULL,
    variables       JSONB DEFAULT '[]',
    model_hints     JSONB DEFAULT '{}',
    tags            TEXT[] DEFAULT '{}',
    created_by      TEXT,
    promoted_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(id, version)
);

-- Budget Periods
CREATE TABLE budget_periods (
    id              TEXT PRIMARY KEY,
    workspace_id    TEXT REFERENCES workspaces(id),
    period_start    DATE NOT NULL,
    period_end      DATE NOT NULL,
    budget_usd      DECIMAL(12,4) NOT NULL,
    spent_usd       DECIMAL(12,4) DEFAULT 0,
    mode            TEXT DEFAULT 'soft',  -- hard | soft | notify-only
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);
```

### Analytics Schema (ClickHouse)

```sql
CREATE TABLE request_events (
    request_id       String,
    trace_id         String,
    agent_run_id     String DEFAULT '',
    workspace_id     String,
    virtual_key_id   String,
    cost_center      String DEFAULT '',
    project_tag      String DEFAULT '',
    provider         LowCardinality(String),
    model            LowCardinality(String),
    input_tokens     UInt32,
    output_tokens    UInt32,
    cached_tokens    UInt32,
    latency_ms       UInt32,
    ttfb_ms          UInt32,
    streaming        UInt8,
    cache_hit        LowCardinality(String),
    input_cost_usd   Float64,
    output_cost_usd  Float64,
    total_cost_usd   Float64,
    status_code      UInt16,
    error_code       String DEFAULT '',
    guardrail_hit    String DEFAULT '',
    timestamp        DateTime64(3)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (workspace_id, timestamp)
TTL timestamp + INTERVAL 2 YEAR;
```

---

## 5. API Specification

### Proxy Endpoints (OpenAI-Compatible)

```
POST /v1/chat/completions     → Chat inference (compatible with all OpenAI clients)
POST /v1/completions          → Legacy text completion
POST /v1/embeddings           → Embedding generation
POST /v1/images/generations   → Image generation (routes to DALL-E, Imagen, Stable Diffusion)
GET  /v1/models               → List available models across all connected providers
```

#### Request Augmentation Headers

```
X-Gateway-Workspace:    <workspace_id>         # override workspace from vkey
X-Gateway-Project:      <project_tag>           # cost attribution tag
X-Gateway-Routing:      <routing_config_id>     # override default routing
X-Gateway-Prompt-ID:    <prompt_id>:<version>   # use registered prompt
X-Gateway-Agent-Run:    <agent_run_id>          # link to agent trace
X-No-Cache: true                                # bypass semantic cache
X-Stream-Usage: true                            # include token usage in stream
```

### Control Plane Endpoints (Selection)

```
# Virtual Keys
POST   /api/v1/keys                → Create virtual key
GET    /api/v1/keys                → List keys (workspace-scoped)
GET    /api/v1/keys/:id            → Get key details
PATCH  /api/v1/keys/:id            → Update key (rate limit, budget, status)
DELETE /api/v1/keys/:id            → Revoke key
POST   /api/v1/keys/:id/rotate     → Rotate (issue new, grace-period old)

# Analytics
GET /api/v1/analytics/usage        → Token/cost usage (filters: period, workspace, model)
GET /api/v1/analytics/latency      → Latency percentiles (P50/P95/P99 by provider/model)
GET /api/v1/analytics/cache        → Cache hit rates, savings
GET /api/v1/analytics/errors       → Error rates by provider
GET /api/v1/analytics/chargeback   → Chargeback export (CSV/JSON)

# Agent Runs
GET /api/v1/agents/runs            → List agent runs
GET /api/v1/agents/runs/:run_id    → Full call graph for a run
GET /api/v1/agents/runs/:run_id/cost → Total cost breakdown for a run
```

---

## 6. Multi-Tenancy Design

### Isolation Model

| Layer | Isolation Mechanism |
|-------|-------------------|
| **Network** | Single ingress, workspace resolved from virtual key |
| **Data (config)** | Row-level security in PostgreSQL (`workspace_id = current_workspace()`) |
| **Data (analytics)** | ClickHouse partitioned by `workspace_id`; queries always filter by it |
| **Secrets** | Per-workspace Vault path (`secret/<workspace_id>/`) |
| **Rate limits** | Per-virtual-key Redis token buckets (namespaced by `vk_<id>`) |
| **Cache** | Redis keys namespaced: `cache:<workspace_id>:<hash>` |

### Deployment Modes

| Mode | Use Case | Config |
|------|---------|--------|
| **Multi-tenant SaaS** | Startups / SMBs | Single cluster, all workspaces shared |
| **Dedicated VPC** | Mid-market | Gateway deployed in customer's AWS/GCP/Azure VPC |
| **Air-gapped on-prem** | Regulated enterprise | Helm chart deployed to customer's existing EKS/OpenShift |
| **Single-tenant Kubernetes** | Maximum isolation | Separate namespace + network policy per tenant |

---

## 7. Security Architecture

### Authentication Flow

```
Client request
  │  Authorization: Bearer vk-ws_prod_platform-4xKj9mNp...
  ▼
[Auth Middleware]
  1. Extract key from header
  2. Hash with SHA-256 (constant-time)
  3. Lookup in Redis cache (5min TTL to avoid DB hit per request)
  4. If miss: query PostgreSQL virtual_keys WHERE key_hash = $1
  5. Validate: status=active, not expired, rate limit not exceeded
  6. Inject workspace context into request context
  7. Continue to next middleware
```

### Secrets Management (Vault Integration)

```
Gateway reads provider API keys from Vault at request time:
  vault read secret/<workspace_id>/<provider>/api_key

Keys are cached in-process for 60 seconds (configurable).
Gateway never logs, stores, or returns provider keys.
Vault audit log captures every key access.
```

### Network Security

```yaml
# Kubernetes NetworkPolicy — gateway pods
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ai-gateway-netpol
spec:
  podSelector:
    matchLabels:
      app: ai-gateway
  policyTypes: [Ingress, Egress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-system      # only from Traefik
      ports: [{port: 8080}]
  egress:
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except: [10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16]  # no internal routing except:
    - to:
        - podSelector:
            matchLabels:
              app: redis                # allow Redis
        ports: [{port: 6379}]
    - to:
        - podSelector:
            matchLabels:
              app: postgresql
        ports: [{port: 5432}]
    - to:
        - podSelector:
            matchLabels:
              app: vault
        ports: [{port: 8200}]
```

### Threat Model

| Threat | Mitigation |
|--------|------------|
| API key leakage | Keys stored as bcrypt hash; prefix-only displayed after creation |
| Prompt injection | Input guardrail, injection classifier, jailbreak detector |
| Provider key theft | Keys in Vault, never in env vars, never logged |
| Data exfiltration via LLM | Output PII guardrail, response logging off by default |
| Runaway agent cost | Per-run token budget, cost circuit breaker |
| DDoS / abuse | Rate limiting at Redis layer (token bucket), Traefik rate limiting |
| Tenant data leak | Row-level security, Redis key namespacing, ClickHouse workspace filter |
| MCP tool injection | Explicit allowlist, denied-by-default MCP policy |

---

## 8. Deployment Architecture

### Kubernetes Manifest Structure

```
k8s/
├── base/
│   ├── gateway/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── hpa.yaml
│   │   ├── pdb.yaml
│   │   └── configmap.yaml
│   ├── postgresql/
│   ├── redis/
│   ├── clickhouse/
│   ├── vault/
│   └── observability/
│       ├── prometheus-stack/
│       ├── loki/
│       └── tempo/
├── overlays/
│   ├── dev/      (k3d local)
│   ├── staging/  (OCI ARM k3s)
│   └── prod/     (customer environment)
└── charts/       (packaged Helm chart for enterprise deployment)
```

### Gateway Deployment Spec

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ai-gateway
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0    # zero-downtime deployments
  selector:
    matchLabels:
      app: ai-gateway
  template:
    spec:
      containers:
        - name: gateway
          image: registry.gitlab.com/yourorg/ai-gateway:latest
          ports:
            - containerPort: 8080   # proxy
            - containerPort: 9090   # metrics
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 512Mi
          readinessProbe:
            httpGet:
              path: /readyz
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 30
          env:
            - name: VAULT_ADDR
              value: http://vault:8200
            - name: VAULT_TOKEN
              valueFrom:
                secretKeyRef:
                  name: vault-token
                  key: token
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: gateway-secrets
                  key: database-url
            - name: REDIS_URL
              valueFrom:
                secretKeyRef:
                  name: gateway-secrets
                  key: redis-url
```

### HPA Configuration

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ai-gateway-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ai-gateway
  minReplicas: 3
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
    - type: Pods
      pods:
        metric:
          name: ai_gateway_requests_in_flight
        target:
          type: AverageValue
          averageValue: "500"
```

---

## 9. Observability Stack Design

### Grafana Dashboard Layout

```
Dashboard: AI Gateway Overview
├── Row 1: Traffic & Availability
│   ├── [Stat]  Requests/sec (last 5min)
│   ├── [Stat]  P99 Latency (last 5min)
│   ├── [Stat]  Error Rate %
│   └── [Stat]  Cache Hit Rate %
│
├── Row 2: Cost & Tokens
│   ├── [Timeseries]  Cost by Provider (USD/hour)
│   ├── [Timeseries]  Tokens/min by Model
│   ├── [Bar Gauge]   Budget Utilisation by Workspace
│   └── [Stat]        Cache Savings USD (current month)
│
├── Row 3: Provider Health
│   ├── [State Timeline]  Circuit Breaker States (all providers)
│   ├── [Heatmap]        Latency distribution by Provider
│   └── [Timeseries]     Error rate by Provider
│
└── Row 4: Agentic Runs
    ├── [Table]    Recent Agent Runs (cost, duration, status)
    ├── [Stat]     Avg Cost per Agent Run
    └── [Timeseries] Agent run throughput
```

### Alerting Rules

```yaml
groups:
  - name: ai-gateway.critical
    rules:
      - alert: GatewayHighErrorRate
        expr: rate(ai_gateway_requests_total{status=~"5.."}[5m]) / rate(ai_gateway_requests_total[5m]) > 0.05
        for: 2m
        labels: { severity: critical }
        annotations:
          summary: "Gateway error rate > 5% for 2 minutes"

      - alert: ProviderCircuitOpen
        expr: ai_gateway_circuit_breaker_state{} == 2
        for: 1m
        labels: { severity: warning }
        annotations:
          summary: "Circuit breaker OPEN for provider {{ $labels.provider }}"

      - alert: WorkspaceBudgetNearLimit
        expr: (ai_gateway_budget_remaining_usd / ai_gateway_budget_total_usd) < 0.10
        for: 5m
        labels: { severity: warning }
        annotations:
          summary: "Workspace {{ $labels.workspace_id }} is at 90%+ budget"

      - alert: GatewayP99LatencyHigh
        expr: histogram_quantile(0.99, rate(ai_gateway_request_duration_ms_bucket[5m])) > 5000
        for: 5m
        labels: { severity: warning }
        annotations:
          summary: "Gateway P99 latency > 5s"
```

---

## 10. Technology Stack

### Core Services

| Component | Technology | Rationale |
|-----------|------------|-----------|
| **Gateway Engine** | Go 1.22+ | Performance, goroutine concurrency, small binary |
| **Control Plane API** | Go + Chi router | Consistent language, fast JSON, OpenAPI gen |
| **Primary Database** | PostgreSQL 16 + pgvector | ACID, vector search for semantic cache |
| **Cache / Rate Limits** | Redis 7 (Valkey OSS) | Atomic operations, TTL, Lua scripting |
| **Analytics Database** | ClickHouse 24 | Columnar, 10B row/s scan, cheap storage |
| **Secrets** | HashiCorp Vault OSS | Industry standard, dynamic secrets, audit |
| **Ingress** | Traefik 3 | Native k8s, auto-TLS, middleware plugins |

### Observability

| Component | Technology |
|-----------|------------|
| Metrics | Prometheus + kube-state-metrics |
| Dashboards | Grafana 11 |
| Logs | Grafana Loki + Promtail |
| Traces | Grafana Tempo + OTLP |
| Alerting | Grafana Alertmanager → PagerDuty / Slack |

### CI/CD

| Component | Technology |
|-----------|------------|
| Source Control | GitLab.com |
| CI/CD | GitLab CI + self-hosted runner |
| Container Registry | GitLab Container Registry |
| IaC | Terraform + Terragrunt |
| GitOps | ArgoCD |
| Local Dev | k3d + Tilt |
| Load Testing | k6 |

### SDK Support (Phase 2)

| Language | Package | Notes |
|----------|---------|-------|
| Python | `ai-gateway-py` | Drop-in `openai` client replacement |
| TypeScript | `ai-gateway-ts` | Full type safety, streaming support |
| Go | `ai-gateway-go` | Native client |

---

## 11. Performance Targets & SLOs

### Gateway Overhead SLOs

| Metric | Target | Alert Threshold |
|--------|--------|----------------|
| Added latency P50 | < 2ms | > 5ms |
| Added latency P99 | < 10ms | > 25ms |
| Gateway availability | 99.99% | < 99.9% |
| Cache lookup P99 | < 5ms | > 15ms |
| Auth middleware P99 | < 2ms | > 8ms |

### Throughput Targets (per gateway pod)

| Workload | Target |
|----------|--------|
| Non-streaming requests | 5,000 RPS |
| Streaming requests (concurrent) | 500 concurrent streams |
| Embedding requests | 10,000 RPS |

### Scalability

- Horizontal scaling via HPA (3 → 20 pods)
- Redis Cluster for cache scale-out
- ClickHouse replication for analytics HA
- PostgreSQL read replicas for control plane scale

---

## 12. Phase Roadmap & Feature Gates

### Phase Overview

| Phase | Timeline | Gate | Key Deliverable |
|-------|----------|------|----------------|
| **Phase 0** | Weeks 1–2 | — | Go skeleton, single provider, request logging |
| **Phase 1** | Weeks 3–12 | Alpha | Multi-provider, fallback routing, exact cache, virtual keys |
| **Phase 2** | Months 3–6 | Beta | Semantic cache, guardrails, prompt registry, budget engine |
| **Phase 3** | Months 6–18 | GA | Multi-tenancy, SSO/RBAC, SOC 2, VPC deployment mode |
| **Phase 4** | Months 12–24 | Enterprise | Agent tracing, MCP gateway, policy engine, FinOps chargeback |

### Feature Flags (Runtime)

```yaml
features:
  semantic_cache:         enabled: false   # enable when pgvector is ready
  guardrails_output:      enabled: false   # compute cost, opt-in only
  agent_tracing:          enabled: false   # Phase 4
  mcp_gateway:            enabled: false   # Phase 4
  chargeback_export:      enabled: false   # Phase 3
  model_regression_tests: enabled: false   # Phase 3
```

---

## 13. Database Schema

> Full schemas are in `/db/migrations/`. Abbreviated reference below.

### Key Migration Files

```
db/migrations/
├── 001_create_workspaces.sql
├── 002_create_virtual_keys.sql
├── 003_create_provider_credentials.sql
├── 004_create_routing_configs.sql
├── 005_create_prompts.sql
├── 006_create_budget_periods.sql
├── 007_create_guardrail_profiles.sql
├── 008_create_agent_policies.sql
├── 009_add_pgvector_extension.sql
├── 010_create_semantic_cache.sql
└── 011_create_audit_log.sql
```

### Audit Log Schema

```sql
CREATE TABLE audit_log (
    id              BIGSERIAL PRIMARY KEY,
    workspace_id    TEXT,
    actor_id        TEXT,           -- user or service account
    actor_type      TEXT,           -- human | service
    action          TEXT NOT NULL,  -- key.create | routing.update | budget.modify
    resource_type   TEXT,
    resource_id     TEXT,
    old_value       JSONB,
    new_value       JSONB,
    ip_address      INET,
    user_agent      TEXT,
    timestamp       TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 14. Configuration Schema (GitOps)

All gateway configuration is expressible as YAML and stored in git. ArgoCD reconciles changes to the cluster.

### Full Workspace Config Example

```yaml
# workspaces/prod-platform.yaml
apiVersion: gateway.yourdomain.com/v1
kind: GatewayWorkspace
metadata:
  name: prod-platform
spec:
  slug: prod-platform
  plan: enterprise
  
  providers:
    - name: anthropic
      vaultPath: secret/prod-platform/anthropic
    - name: openai
      vaultPath: secret/prod-platform/openai

  routing:
    default:
      strategy: fallback
      targets:
        - provider: anthropic
          model: claude-sonnet-4-6
        - provider: openai
          model: gpt-4o
          condition: on_error
      retry:
        maxAttempts: 3
        backoff: exponential

  cache:
    exact:
      ttlSeconds: 3600
    semantic:
      enabled: true
      threshold: 0.95
      ttlSeconds: 86400

  guardrails:
    profile: pii-strict
    input:
      injectionDetection: true
      piiDetection:
        enabled: true
        action: block
    output:
      toxicityScore:
        enabled: false

  budget:
    monthly:
      limitUsd: 10000
      mode: soft
      alerts: [0.7, 0.9, 1.0]

  rateLimits:
    default: 1000rpm
    perVirtualKey: true

  agentPolicy:
    maxIterations: 20
    maxCostPerRunUsd: 2.00
    humanApprovalRequired:
      - actionType: financial_transaction
        thresholdUsd: 500
```

---

## 15. Zero-Cost Infrastructure Specification

### Oracle Cloud Always Free Allocation

| Resource | Spec | Role in Stack |
|----------|------|--------------|
| ARM Compute (A1) | 4 OCPU / 24GB RAM | Primary k3s node (gateway + control plane + observability) |
| AMD Micro VM #1 | 1 OCPU / 1GB RAM | k3s worker node |
| AMD Micro VM #2 | 1 OCPU / 1GB RAM | k3s worker node / dedicated DB node |
| Autonomous DB #1 | PostgreSQL-compat | Primary config + analytics DB |
| Autonomous DB #2 | PostgreSQL-compat | Read replica / dev environment DB |
| Block Storage | 200GB | PVCs for Redis AOF, ClickHouse data, Vault storage |
| Outbound Transfer | 10TB/month | API traffic — sufficient for heavy load testing |
| Static Public IP | 1 free | Domain → Traefik ingress |

### Cluster Topology (Free Tier)

```
┌─────────────────────────────────────────────────────────┐
│               k3s Cluster (3 nodes, $0/month)           │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │  Node 1: OCI ARM A1 (4c/24GB)  — Control Plane  │    │
│  │    • ai-gateway (3 replicas)                    │    │
│  │    • ai-gateway-control-plane (1 replica)       │    │
│  │    • Prometheus + Grafana + Loki                │    │
│  │    • Tempo (tracing)                            │    │
│  │    • Vault OSS                                  │    │
│  │    • ArgoCD                                     │    │
│  └─────────────────────────────────────────────────┘    │
│                                                         │
│  ┌──────────────────────┐  ┌──────────────────────┐     │
│  │  Node 2: AMD Micro   │  │ Node 3: AMD Micro    │     │
│  │  Redis (primary)     │  │ PostgreSQL (primary) │     │
│  │  ClickHouse (data)   │  │ ClickHouse (meta)    │     │
│  └──────────────────────┘  └──────────────────────┘     │
└─────────────────────────────────────────────────────────┘
```

### GitLab CI Pipeline (Self-Hosted Runner)

```yaml
# .gitlab-ci.yml
stages: [lint, test, build, deploy]

variables:
  IMAGE: registry.gitlab.com/${CI_PROJECT_PATH}:${CI_COMMIT_SHA}

lint:
  stage: lint
  script:
    - golangci-lint run ./...
    - go vet ./...

test:
  stage: test
  script:
    - go test -race -coverprofile=coverage.out ./...
    - go tool cover -func=coverage.out
  coverage: '/total:\s+\(statements\)\s+(\d+\.\d+)%/'

build:
  stage: build
  script:
    - docker build -t $IMAGE .
    - docker push $IMAGE

deploy-staging:
  stage: deploy
  environment: staging
  script:
    - kubectl set image deployment/ai-gateway gateway=$IMAGE -n gateway
    - kubectl rollout status deployment/ai-gateway -n gateway
  only: [main]
```

### Local Dev Environment

```bash
# One-time setup
brew install k3d tilt go

# Start local cluster
k3d cluster create ai-gateway --agents 2 --port "8080:80@loadbalancer"

# Start dev loop (code change → rebuild → redeploy in ~10s)
tilt up

# Load test (simulate 500 concurrent users)
k6 run --vus 500 --duration 60s scripts/load-test.js
```

### Cost Trajectory

| Stage | Monthly Cost | Milestone |
|-------|-------------|-----------|
| Pre-launch (OCI free) | $0 | Build, test, demo |
| Beta (OCI free + domain) | ~$12/year | First 10 customers |
| First customer | ~$12/month (Hetzner 3-node) | Revenue > hosting |
| 10 customers | ~$50/month (Hetzner + managed DB) | Self-funding |
| 50+ customers | AWS/GCP with credits | Series A territory |

---

*End of Document*

---

> **Next Steps:**  
> 1. Scaffold Go project with middleware chain (Phase 0)  
> 2. Apply Oracle Cloud Always Free account  
> 3. Apply AWS Activate Founders ($1,000 credit, no VC required)  
> 4. Register GitLab repo and configure self-hosted runner on OCI ARM  
> 5. Stand up k3s + ArgoCD for GitOps-driven deployments
