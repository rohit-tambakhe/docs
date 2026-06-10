---
name: cd-pipeline-cosign-gate
description: CD verify gate uses cosign keyless Binary-Authorization; known cosign verify-attestation payload-print hang and its fix
metadata:
  type: project
---

infrastructure-live `cd.yml` has a `verify` job (cosign keyless Binary-Authorization gate) → `discover` (reads cell manifest) → `deploy` matrix (one leg per enabled cell: pool-free, pool-std, dev; each maps to a GitHub Environment). The gate verifies signature + SLSA `slsaprovenance` + SBOM `spdxjson` attestations against the routeplane CI signer identity (`.../ci.yml@refs/heads/main`, issuer `token.actions.githubusercontent.com`). Signing side is common-actions `cosign-sign-attest`; verify side is `cosign-verify`. cosign v2.4.1 (pinned in both).

**Resolved 2026-06-09:** the verify gate hung ~6 min with zero output and had NEVER succeeded. Root cause (NOT TUF/Sigstore reachability — that was the wrong hypothesis): `cosign verify-attestation --type spdxjson` prints the ~77KB SBOM payload as a single line; the GitHub runner's per-line secret scan (actions/runner#1031) chokes on the giant line for >8 min (sigstore/cosign#3602). Fix: `--output-file` on both verify-attestation calls routes the payload to a file instead of the live log. After fix, verify completes in ~5s.

**Why:** binary authorization is part of the agentic-security moat — the deploy gate must fail closed but actually complete.

**How to apply:**
- If a cosign `verify-attestation` step hangs silently in CI, suspect the payload-print hang, not the network. Confirm by isolating each verify into its own step (a stalled COMPOSITE step buffers + loses all output on SIGKILL, so you see nothing).
- Keep `--output-file`; never "fix" a cosign hang with `--insecure-ignore-tlog`/`--insecure-ignore-sct` (that weakens the gate).
- Defense-in-depth kept in cosign-verify: pinned cosign-release, bounded `cosign initialize`, and `timeout --kill-after` around every cosign call (cosign's own `--timeout` does NOT bound TUF init).

See [[onedrive-drift]].
