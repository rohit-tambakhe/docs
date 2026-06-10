---
name: openssl-build-env
description: routeplane cargo build needs OPENSSL_* env vars in this sandbox (pkg-config missing); native-tls is the intended TLS backend
metadata:
  type: project
---

Building `routeplane/` in this WSL sandbox fails on `openssl-sys` because `pkg-config` is not installed (no root to apt-install it), even though OpenSSL headers/libs exist.

**Fix (export before any cargo command):**
```
OPENSSL_LIB_DIR=/usr/lib/x86_64-linux-gnu OPENSSL_INCLUDE_DIR=/usr/include OPENSSL_NO_VENDOR=1
```
These let `openssl-sys` locate OpenSSL without pkg-config.

**Why:** reqwest uses native-tls (→ openssl-sys) by default. The Dockerfile (`rust:1.86-slim-bookworm`) installs `pkg-config libssl-dev`, so CI/prod builds are fine — this is a local-sandbox-only gap.

**How to apply:** Do NOT "fix" this by switching reqwest to rustls — native-tls is the intended backend (Dockerfile proves it). Just export the env vars for local cargo build/test/clippy.

Related: [[onedrive-working-tree-reversion]] — repo is under OneDrive; re-verify edits stuck.
