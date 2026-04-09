# ClearDeck Poker — Changelog

All notable changes to this project are documented here. Each entry explains **what** changed and **why**.

---

## [Unreleased] — 2026-04-08

### Security Assessment Remediation (F-1 through F-7)

Full security assessment performed using ICP Security Skills framework. 7 findings identified and fixed:

**F-1: ETH y-parity panic replaced with Result** (`table_canister/src/lib.rs`)
- **What**: `y_parity()` returned `u64` and called `panic!()` on failure. Changed to return `Result<u64, String>` with `?` propagation at the call site.
- **Why**: A panic during ETH transaction signing would trap the canister mid-withdrawal. By returning an error instead, the caller gets a clean failure and can retry.

**F-2: Rate limit on `claim_external_deposit()`** (`table_canister/src/lib.rs`)
- **What**: Added `DEPOSIT_RATE_LIMITS` check (5 calls/minute/user), same pattern used by `notify_deposit()`.
- **Why**: This function makes 1-2 inter-canister calls per invocation. Without rate limiting, an attacker could call it in a tight loop to drain canister cycles.

**F-3: Rate limit on `buy_in()`, `reload()`, `cash_out()`** (`table_canister/src/lib.rs`)
- **What**: Added `check_rate_limit()` (10 calls/second/user) to all three chip management functions.
- **Why**: These functions modify shared game state. Unrestricted rapid-fire calls could cause excessive state churn. Consistent with the rate limiting on `player_action()` and `withdraw()`.

**F-4: `pre_upgrade()` panics on failure** (`lobby_canister/src/lib.rs`, `history_canister/src/lib.rs`)
- **What**: Changed `pre_upgrade()` from logging errors and continuing to `panic!()` on serialization failure.
- **Why**: If stable memory write fails and the upgrade proceeds, all canister state is lost. Panicking rejects the upgrade and preserves the currently-running canister state. The table canister already had this risk but all three now fail safely.

**F-5: Table name length validation** (`lobby_canister/src/lib.rs`)
- **What**: Added `new_name.len() > 100` check in `update_table_name()`.
- **Why**: The function accepted unbounded strings. A compromised admin key or input error could store multi-megabyte strings that bloat all table listing responses.

**F-6: `inspect_message` added to lobby and history** (`lobby_canister/src/lib.rs`, `history_canister/src/lib.rs`)
- **What**: Added `#[ic_cdk::inspect_message]` that rejects `Principal::anonymous()` at ingress, matching the table canister's existing guard.
- **Why**: Without this, anonymous update calls still consume cycles for message processing before the function-level check rejects them. This saves cycles by rejecting at the ingress layer.

**F-7: `get_admin()` restricted to admin/controller** (`lobby_canister/src/lib.rs`)
- **What**: Changed from public query returning `Option<Principal>` to returning `Result<Option<Principal>, String>`, rejecting non-admin/non-controller callers.
- **Why**: Publicly exposing the admin principal is unnecessary information disclosure that could aid targeted attacks.

---

## 2026-04-04 — Deposit Progress Indicators

**PR #6** (`57f20d1`)

### Added
- **BTC deposit progress**: 4-step tracker (BTC sent -> X/6 confirmations -> ckBTC minted -> Available) with live countdown estimating ~10 min/block.
- **ETH deposit progress**: 3-step tracker (ETH sent -> Ethereum finality -> Available) with ~20 min countdown.
- **DOGE deposit progress**: 3-step tracker (DOGE sent -> confirmations -> Available) with ~6 min countdown.
- Shared CSS system (`.deposit-progress-section`, `.step-dot`, `.deposit-progress-bar`) with currency-colored variants (orange BTC, blue ETH, gold DOGE).
- "Why the wait?" expandable explainers for each currency.

**Why**: Users had no visibility into how long native crypto deposits take. BTC requires 6 confirmations (~60 min), ETH requires Ethereum finality (~20 min), and DOGE requires confirmations (~6 min). Without progress indicators, users thought deposits were broken.

### Fixed
- Stale canister IDs in `+page.svelte` (kpfcd -> hnyty, kggj7 -> he3ye, etc.)
- GitHub URLs updated from JoshDFN to ck-harrison across docs and scripts.

---

## 2026-03-31 — dfx Reference Cleanup

**PR #5** (`14b2cfa`)

### Changed
- Updated deployment warning comments in table and lobby canisters from `dfx` to `icp` commands.
- Updated integration test instructions from `dfx` to `icp` commands.
- Cleaned `.env.example` and `.gitignore` dfx references.

**Why**: After the icp-cli migration (PR #3), several comments and docs still referenced the old `dfx` CLI. This created confusion about which tool to use. Zero `dfx` references remain in source.

---

## 2026-03-30 — Security Audit Hardening + icp-cli Migration

**PR #4** (`71e9a4b`)

### Fixed — Critical
- **E1: Deposit replay exploit** — `VERIFIED_DEPOSITS` pruning (at 10K entries) deleted old block indices without tracking them. An attacker could re-submit a pruned block index and get credited again for free. Added `MIN_VERIFIED_BLOCK_INDEX` watermark that rejects any `block_index <= watermark`.
- **E2: ckBTC sweep fund loss** — If the ckBTC sweep (subaccount -> main account) failed after the minter had already minted, funds were lost with no recovery path. Added `FAILED_CKBTC_SWEEPS` recording and `retry_ckbtc_sweep()` admin endpoint.

### Fixed — Hardening
- Anonymous principal rejection on all 13+ state-mutating functions across all 3 canisters.
- Saturating arithmetic on 6 raw subtraction operations that could underflow.
- Input validation and query result limits (cap 100) on history canister.
- CSP headers and `allow_raw_access: false` on frontend asset canister.
- Frontend migrated to `@icp-sdk/core` submodule imports.

**Why**: A formal security audit identified 18 findings (P0-P2). The two critical exploits (E1, E2) could result in direct fund loss. The hardening items close defense-in-depth gaps.

---

## 2026-03-27 — Migrate from dfx to icp-cli

**PR #3** (`3c8e052`)

### Changed
- Replaced `dfx.json` with `icp.yaml` configuration.
- Frontend packages: `@dfinity/agent` -> `@icp-sdk/core`, added `@icp-sdk/bindgen`.
- `createActor` API updated to use `agentOptions` (host, identity, rootKey) instead of pre-built `HttpAgent`.
- `deploy-production.sh` rewritten for `icp` CLI commands.
- Canister ID mapping moved to `.icp/data/mappings/ic.ids.json`.

### Removed
- `dfx.json`, `canister_ids.json`, `deploy-mainnet.sh` (superseded by `deploy-production.sh`).

**Why**: The `dfx` CLI is being replaced by `icp` CLI across the ICP ecosystem. The new CLI uses YAML config, a recipe system, and an environment model that eliminates `CANISTER_ID_*` env vars in favor of `ic_env` cookies.

---

## 2026-03-24 — Fix ckBTC Deposit Bug

**PR #2** (`ccd8be1`)

### Fixed
- After `update_btc_balance` succeeded, ckBTC was minted to the canister's per-user subaccount but never swept to the main account or credited to the user's `BALANCES`. BTC deposits silently disappeared — funds existed on-chain but were inaccessible in-game.
- Now detects `Minted` UTXOs, transfers ckBTC from subaccount to main account, and credits the user's internal balance.

**Why**: Users depositing BTC saw their funds vanish. The minter was working correctly (ckBTC existed on-chain) but the canister never moved funds from the per-user subaccount to the playable balance.

---

## 2026-03-22 — DOGE Integration + Security Audit (P0/P1/P2)

(`d32f6fe`)

### Added
- **DOGE support**: Native Dogecoin via DFINITY Dogecoin canister + threshold ECDSA. P2PKH address derivation, UTXO deposit detection, signed withdrawals, lobby table, sidebar wallet, deposit/withdraw UI.

### Fixed — P0 (Critical)
- `inspect_message` guard rejecting anonymous callers at ingress.
- `created_at_time` on all ICRC transfers for deduplication.
- `WithdrawalGuard` / `DogeWithdrawalGuard` preventing withdrawal reentrancy.
- `bounded_wait` on inter-canister calls to prevent canister hang.
- EVM RPC cycles bumped to 10B (was insufficient).
- Atomic DOGE withdrawal (deduct before async transfer).
- Deposit overflow: `try_into().unwrap_or(0)` replaced with proper error.

### Fixed — P1
- ckBTC owner set to `canister_self` with per-user subaccounts.
- Schema versioning with `Option<T>` fields for upgrade compatibility.

### Fixed — P2
- EVM RPC provider consensus handling.
- Stale `PENDING_DEPOSITS` cleanup.
- Rate limiting on `withdraw()`.
- Explicit fee handling.
- BTC withdrawals via `retrieve_btc_with_approval`.

**Why**: Security audit identified 18 findings across severity levels. P0 items could cause fund loss or canister bricking. DOGE was added as the third supported chain alongside ICP and BTC/ETH.

---

## 2026-03-18 — Native ETH Deposits

**PR #1** (`9d493a0`)

### Added
- Derive unique Ethereum addresses per user via ICP threshold ECDSA (secp256k1).
- Check ETH balances via EVM RPC canister (`eth_getBalance`).
- Build and sign EIP-1559 transactions to call ckETH helper contract `deposit()`.
- Endpoints: `get_eth_deposit_address()`, `sweep_eth_to_cketh()`.
- Frontend: "Show Address" with copy button, "Check for Deposit" with 2-min polling + auto-sweep, progress indicator during ~20 min ckETH minting.
- Heads-up bust animations (fireworks for winner, rain cloud for loser).
- ETH table configuration in lobby.

**Why**: Users needed to deposit ETH without MetaMask or WalletConnect. ICP's chain fusion (threshold ECDSA + EVM RPC) enables the canister to derive Ethereum addresses and sign transactions directly, giving each user a native ETH deposit address.

---

## 2026-02-24 — Deposit Security Hardening

(`d461846`)

### Fixed
- Replaced insecure `deposit_from_external` with subaccount-based `claim_external_deposit`.
- Added sender verification to `notify_deposit` to prevent front-running.
- Removed `admin_restore_balance` (unnecessary attack surface).
- Anonymous caller checks on all deposit/withdraw functions.
- Saturating arithmetic for all balance operations.
- Rate limiting on `start_new_hand`.

**Why**: The original `deposit_from_external` accepted a `from_principal` parameter and credited the caller, allowing anyone to claim any unverified deposit. The subaccount pattern ties each deposit address cryptographically to a single principal.

---

## 2026-01-28 — OISY Wallet + Initial Fixes

(`6091310`, `dd04b6c`, `5333721`, `2ea291a`)

### Added
- OISY Wallet integration for deposits (popup guidance, auto-disconnect).
- `deposit_from_external` function for OISY deposits (later replaced in 2026-02-24).

### Fixed
- Critical bugs and security issues (initial pass).
- Browser warning removed from `app.html`.
- "Play Now" changed to "View Demo" for legal safety.

**Why**: OISY Wallet was the initial approach for external wallet deposits before the subaccount-based pattern was adopted.

---

## 2026-01-28 — Initial Release

(`f781c7a`)

### Added
- ClearDeck Provably Fair Poker — ICP-based poker with on-chain shuffle verification.
- Table canister (Rust): Texas Hold'em engine, ICP deposits/withdrawals, hand history.
- Lobby canister (Rust): Table registry, player profiles, leaderboard.
- History canister (Rust): Hand storage with SHA-256 shuffle proof verification.
- Frontend (SvelteKit 5): Real-time game UI with Internet Identity authentication.

**Why**: Initial deployment of the provably fair poker platform on the Internet Computer.
