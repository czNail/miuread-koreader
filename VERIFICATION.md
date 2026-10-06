# 5.9.0-beta.19 Verification

- `tools/test_beta19_robust_mapping.lua`: locks multi-anchor capture, source-only normalization, coordinate-conflict fail-closed behavior, beta.18 fresh-context retention, and quiet text-anchor UI semantics.
- `tools/verify_590_beta19.py`: release/static verifier for version identity and beta.19 invariants.
- Existing position resolution, open-sync, cloud mirror/freshness, terminal guard, finished resolution, Store repair, beta.17 lifecycle and beta.18 fresh-context protections remain regression-tested.
- Release workflow runs Lua syntax checks and beta.19 verification before tag creation.

## Bookstore (2026-10-06)

- `lua5.1 tools/test_bookstore.lua`: recommendation/similar cursors and response shapes, category hierarchy, API parameters, authoritative membership fallback, existing login recovery for reads, and non-retrying shelf writes with readback recovery.
- `lua5.1 tools/test_bookstore_ui.lua`: cached previous batches, return navigation, similar-session pagination, exclusive primary menus, existing child credential snapshots, shared worker cancellation/context guards, cancelled/stale/cross-account results, idle account-view cleanup, duplicate taps, persistence rollback on failed intent/clear, worker startup failure, and verification-only recovery after a lost callback/restart.
- Both scripts and all plugin Lua syntax pass with Lua 5.1 and LuaJIT 2.1. Existing finished-status, comment-like, cloud-shelf-sort and extension-catalog regressions pass.
- Live unauthenticated reads parsed seven rankings and 22 root categories. Total, rising, new-book, publication category and subcategory batches, including the second total-ranking batch, returned 20 books with advancing cursors.
- Personalized recommendation and authenticated shelf mutation use documented/current Web reader contracts and mocked tests. A real WeRead account write and physical Kindle layout have not been verified in this environment.
