# ClearDeck Poker — Security Assessment Report

**Date**: 2026-04-04
**Scope**: All backend canisters (`table_canister`, `lobby_canister`, `history_canister`) and frontend (`cleardeck_frontend`)
**Methodology**: ICP Security Skills framework with risk matrix (Likelihood × Impact)
**Assessor**: Claude (Opus 4.6)

---

## Executive Summary

ClearDeck Poker is a multi-chain poker application running on the Internet Computer Protocol (ICP) that holds real user funds in ICP, ckBTC, ckETH, and DOGE. The codebase demonstrates strong security fundamentals: saturating arithmetic on all balance operations, reentrancy guards on withdrawals, comprehensive anonymous caller rejection, proper caller capture before async boundaries, and deposit replay prevention with watermarking.

**7 findings** passed the 5-question filter. The most critical is a panic in ETH withdrawal signing that could trap a canister mid-withdrawal after funds have been deducted.

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 1 |
| Medium   | 4 |
| Low      | 2 |

---

## Risk Matrix

| **Likelihood / Impact** | **Severe** | **Major** | **Moderate** | **Minor** |
|--------------------------|-----------|-----------|-------------|-----------|
| **Highly Likely**        | Critical  | High      | High        | Medium    |
| **Likely**               | High      | High      | Medium      | Medium    |
| **Possible**             | High      | Medium    | Medium      | Low       |
| **Unlikely**             | Medium    | Medium    | Low         | Low       |

---

## Findings

### F-1: Panic in ETH y-parity Calculation Can Trap Canister Mid-Withdrawal

- **Vulnerability**: Unrecoverable trap during ETH transaction signing
- **Vulnerability Type**: Security — Fund Safety
- **Severity**: **High**
  - **Likelihood**: Possible — Requires specific ECDSA signature output where y-parity cannot be determined; rare but not impossible with threshold ECDSA
  - **Impact**: Severe — User's ETH balance has already been deducted before the signing call; a trap here means funds are lost with no automatic recovery path
  - **Recoverability**: Very Difficult (requires admin intervention to manually credit balance)
  - **Impacted Asset Category**: Essential (user funds)
- **Source Location**: `src/table_canister/src/lib.rs:5618`
- **Line Content**: `panic!("unable to determine y parity")`
- **Description**: During `sweep_eth_to_cketh()`, the user's balance is deducted before the async ECDSA signing call. After signing returns, `y_parity()` is computed on the signature. If this computation fails, `panic!()` traps the canister. Because the balance deduction already occurred and no recovery mechanism exists for this specific failure mode (unlike ckBTC which has `FAILED_CKBTC_SWEEPS`), the user's funds are effectively lost.
- **Recommendation**: Replace the `panic!()` with a `Result` return. On y-parity failure, refund the user's balance using `saturating_add` and return an error. Consider adding a `FAILED_ETH_SWEEPS` recovery mechanism analogous to `FAILED_CKBTC_SWEEPS`.

---

### F-2: `claim_external_deposit()` Has No Rate Limiting

- **Vulnerability**: Missing rate limit on deposit claim function
- **Vulnerability Type**: Security — Denial of Service
- **Severity**: **Medium**
  - **Likelihood**: Likely — No barrier to repeated calls; any authenticated user can invoke at will
  - **Impact**: Moderate — Each call triggers an inter-canister `icrc1_balance_of` + potential `icrc1_transfer`, consuming cycles. Sustained abuse could exhaust the canister's cycle balance.
  - **Attack Cost**: Free
  - **Attack Complexity**: Straightforward
  - **Privileges Required**: Low (any authenticated principal)
- **Source Location**: `src/table_canister/src/lib.rs:1506`
- **Line Content**: `pub async fn claim_external_deposit() -> Result<u64, String> {`
- **Description**: Unlike `notify_deposit()` which enforces `MAX_DEPOSIT_VERIFICATIONS_PER_MINUTE` (5/min), `claim_external_deposit()` has no rate limiting. Each invocation makes 1-2 inter-canister calls to the ledger, burning cycles. An attacker could call this in a tight loop to drain canister cycles.
- **Recommendation**: Apply the same `DEPOSIT_RATE_LIMITS` check used by `notify_deposit()` (lines 1144-1169).

---

### F-3: `buy_in()`, `reload()`, and `cash_out()` Lack Rate Limiting

- **Vulnerability**: Missing rate limits on chip management functions
- **Vulnerability Type**: Security — Denial of Service
- **Severity**: **Medium**
  - **Likelihood**: Possible — Requires authenticated user; functions modify shared game state
  - **Impact**: Moderate — Rapid-fire calls could create excessive state churn and log noise; `cash_out()` modifies balances
  - **Privileges Required**: Low (any seated player)
- **Source Location**: `src/table_canister/src/lib.rs:1961` (`buy_in`), `src/table_canister/src/lib.rs:2065` (`reload`), `src/table_canister/src/lib.rs:2136` (`cash_out`)
- **Line Content**: `pub fn buy_in(amount: u64) -> Result<String, String> {`
- **Description**: These three functions handle chip movement between the user's balance and the table. While they don't make inter-canister calls (no cycle drain), unrestricted calls could cause excessive state mutations. `buy_in` and `reload` have game-state guards (must be between hands), but `cash_out` can be called freely.
- **Recommendation**: Apply `check_rate_limit()` at the entry point of each function, consistent with the pattern used by `player_action()` and `withdraw()`.

---

### F-4: `pre_upgrade()` Silently Fails on Serialization Error (Lobby & History)

- **Vulnerability**: Silent data loss on canister upgrade
- **Vulnerability Type**: Security — Data Integrity
- **Severity**: **Medium**
  - **Likelihood**: Unlikely — Serialization failure requires corrupted state or instruction limit exceeded
  - **Impact**: Severe — All canister state (table registry, player profiles, hand history) lost on upgrade; `post_upgrade()` will panic but the data is already gone from stable memory
  - **Recoverability**: Very Difficult (state unrecoverable if stable memory write fails)
  - **Impacted Asset Category**: Essential (lobby: table registry + player profiles; history: all hand records + shuffle proofs)
- **Source Location**: `src/lobby_canister/src/lib.rs:953`, `src/history_canister/src/lib.rs:540`
- **Line Content**: `ic_cdk::println!("ERROR: Failed to save state: {:?}", e);`
- **Description**: In both the lobby and history canisters, `pre_upgrade()` catches serialization errors and logs them but allows the upgrade to proceed. If stable memory write fails, the old state is wiped and the new `post_upgrade()` will either panic (history) or restore empty state (lobby). The table canister correctly handles this by also logging but the risk is the same. Panicking in `pre_upgrade()` would reject the upgrade and preserve the running canister's state.
- **Recommendation**: Change `pre_upgrade()` in both canisters to `panic!()` on serialization failure, which rejects the upgrade and preserves the currently-running canister state. This is safer than proceeding with empty stable memory.

---

### F-5: `update_table_name()` Accepts Unbounded Input

- **Vulnerability**: No input validation on table name
- **Vulnerability Type**: Security — Denial of Service
- **Severity**: **Medium**
  - **Likelihood**: Possible — Requires admin access (reduces likelihood)
  - **Impact**: Moderate — Admin could store arbitrarily large strings in canister heap, approaching memory limits; also returned in all `get_tables()` queries, inflating response sizes
  - **Privileges Required**: High (admin only)
- **Source Location**: `src/lobby_canister/src/lib.rs:626`
- **Line Content**: `table.name = name;`
- **Description**: The `update_table_name()` function accepts a `String` parameter with no length validation and stores it directly. While restricted to admin callers (reducing exploitation likelihood), a compromised admin key or input error could store multi-megabyte strings. All table listing queries would then return bloated responses.
- **Recommendation**: Add a length check: `if name.len() > 100 { return Err("Name too long") }`.

---

### F-6: Lobby Canister Missing `inspect_message` Guard

- **Vulnerability**: No ingress-level anonymous caller filtering
- **Vulnerability Type**: Security — Defense in Depth
- **Severity**: **Low**
  - **Likelihood**: Possible — Anonymous calls to update functions are individually rejected, but ingress processing still consumes cycles
  - **Impact**: Minor — Each rejected anonymous call still costs cycles for message processing before the function-level check rejects it
  - **Privileges Required**: None
- **Source Location**: `src/lobby_canister/src/lib.rs` (absent)
- **Line Content**: N/A (missing implementation)
- **Description**: The table canister implements `inspect_message()` to reject anonymous callers at ingress, before message execution begins. The lobby and history canisters lack this guard. While individual functions reject anonymous callers, the canister still pays cycles to deserialize and begin executing the call before rejection.
- **Recommendation**: Add `#[ic_cdk::inspect_message]` to both lobby and history canisters with the same anonymous rejection pattern used in the table canister (lines 800-806).

---

### F-7: History Canister `get_admin()` Exposes Admin Principal

- **Vulnerability**: Admin identity disclosed via public query
- **Vulnerability Type**: Security — Information Disclosure
- **Severity**: **Low**
  - **Likelihood**: Highly Likely — Public query, no access control
  - **Impact**: Minor — Reveals the admin principal, which could be used for targeted social engineering or to identify the controller for governance attacks, but the principal alone does not grant any access
  - **Privileges Required**: None
  - **Discoverability**: Public
- **Source Location**: `src/lobby_canister/src/lib.rs:174-177`
- **Line Content**: `pub fn get_admin() -> Option<Principal> {`
- **Description**: The `get_admin()` query returns the admin principal to any caller. While this doesn't directly compromise security (knowing a principal doesn't grant access), it unnecessarily exposes operational information.
- **Recommendation**: Either remove this query or restrict it to controller-only access. If needed for the frontend, the frontend already knows the admin from deployment.

---

## Positive Findings (Verified Controls)

The following security controls were verified as correctly implemented:

| Control | Status | Evidence |
|---------|--------|----------|
| **Saturating arithmetic** on all balance ops | ✅ Verified | All `BALANCES`, `DOGE_BALANCES`, stat counters use `saturating_add`/`saturating_sub` |
| **Caller capture before await** | ✅ Verified | All 20+ async functions capture `ic_cdk::api::msg_caller()` as first operation |
| **Reentrancy guards** on withdrawals | ✅ Verified | `WithdrawalGuard` (line 1756) and `DogeWithdrawalGuard` (line 1786) with `Drop` cleanup |
| **Deposit replay prevention** | ✅ Verified | `VERIFIED_DEPOSITS` + `MIN_VERIFIED_BLOCK_INDEX` watermark (line 488) |
| **PENDING_DEPOSITS** concurrency guard | ✅ Verified | Prevents double-crediting during async verification (line 1191) |
| **Anonymous caller rejection** | ✅ Verified | 21 update functions + `inspect_message` in table canister |
| **Admin access control** | ✅ Verified | All 8 admin functions check `require_controller()` |
| **Rate limiting** on critical paths | ✅ Verified | `player_action` (10/s), `notify_deposit` (5/min), `heartbeat` (2/s), `withdraw` (60s cooldown) |
| **Withdrawal cooldown** | ✅ Verified | 60-second cooldown between ICP withdrawals (line 1840) |
| **ckBTC sweep failure recovery** | ✅ Verified | `FAILED_CKBTC_SWEEPS` + `retry_ckbtc_sweep()` endpoint |
| **DOGE UTXO deduplication** | ✅ Verified | `DOGE_CREDITED_UTXOS` prevents double-crediting (line 6108) |
| **Query result capping** | ✅ Verified | Leaderboard (100), hand history (100) capped to prevent response bloat |
| **Schema versioning** | ✅ Verified | `CURRENT_SCHEMA_VERSION` in `PersistentState` for upgrade compatibility |
| **post_upgrade panic on failure** | ✅ Verified | All three canisters panic if state restoration fails |
| **Username validation** | ✅ Verified | 3-20 chars, ASCII alphanumeric + underscore, reserved name check |
| **Hand record validation** | ✅ Verified | Players 1-10, actions ≤ 1000 |
| **Shuffle proof verification** | ✅ Verified | SHA-256 verification of shuffle seeds in history canister |
| **EVM RPC cycles** | ✅ Verified | 10B cycles allocated, matching canister requirements |
| **ECDSA signing cycles** | ✅ Verified | 26.15B cycles for threshold ECDSA operations |

---

## Architecture Notes

- **No inter-canister calls** in lobby or history canisters — minimal attack surface
- **Table canister** makes ~20 types of inter-canister calls (ledger queries, ICRC transfers, ECDSA signing, EVM RPC, ckBTC minter, Dogecoin canister)
- **Bounded wait** used for history recording and deposit verification; **unbounded calls** used for transfers and minter interactions
- **Thread-local state** with periodic cleanup (every 60s via `periodic_cleanup()`) prevents unbounded growth of rate limit maps and pending state
- **DISPLAY_NAMES** pruned when exceeding 200 entries (removes zero-balance, non-seated players)

---

## Remediation Status

All 7 findings have been remediated:

| Finding | Status | Fix |
|---------|--------|-----|
| F-1: ETH y-parity panic | ✅ Fixed | `y_parity()` returns `Result<u64, String>` instead of panicking; caller propagates error via `?` |
| F-2: Rate limit `claim_external_deposit()` | ✅ Fixed | Added `DEPOSIT_RATE_LIMITS` check (5/min/user), same pattern as `notify_deposit()` |
| F-3: Rate limit `buy_in`/`reload`/`cash_out` | ✅ Fixed | Added `check_rate_limit()` call (10/sec/user) to all three functions |
| F-4: `pre_upgrade()` panic on failure | ✅ Fixed | Both lobby and history now `panic!()` on save failure, rejecting the upgrade |
| F-5: Validate table name length | ✅ Fixed | Added `new_name.len() > 100` check in `update_table_name()` |
| F-6: `inspect_message` in lobby/history | ✅ Fixed | Added `#[ic_cdk::inspect_message]` rejecting anonymous callers to both canisters |
| F-7: Restrict `get_admin()` | ✅ Fixed | Changed to return `Result`, rejects non-admin/non-controller callers |

---

## Previously Remediated Issues

The following vulnerabilities from the prior security audit (`SECURITY_AUDIT.md`) have been verified as fixed:

- ✅ Deposit replay via VERIFIED_DEPOSITS pruning (E1) — watermark pattern implemented
- ✅ ckBTC sweep failure fund loss (E2) — FAILED_CKBTC_SWEEPS + retry endpoint
- ✅ Anonymous principal rejection on all state-mutating functions
- ✅ Saturating arithmetic on all balance operations
- ✅ `inspect_message` guard (table canister)
- ✅ `created_at_time` on all ICRC transfers
- ✅ EVM RPC cycles bumped to 10B
- ✅ WithdrawalGuard / DogeWithdrawalGuard reentrancy prevention
- ✅ ckBTC owner parameter and subaccount derivation
- ✅ Schema versioning on PersistentState
- ✅ Rate limiting on critical endpoints
- ✅ Frontend CSP headers
