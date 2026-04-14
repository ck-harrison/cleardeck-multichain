---
name: Pending Bugs and Issues
description: Known bugs and incomplete work items as of 2026-03-31
type: project
---

## Critical Bugs
1. **Deposit modal freeze on ETH table**: "Cannot access 'Se' before initialization" — Svelte 5 temporal dead zone error. The $derived or $effect declarations have a circular or out-of-order reference. Needs reordering of reactive declarations in DepositModal.svelte.

2. **ETH table shows ICP balance label**: The table balance badge shows "ICP" instead of "ETH" in some contexts.

3. **ETH table min_buy_in too high**: Currently 0.01 ETH, Christopher wants 0.001 ETH. Need to update icp.yaml init_args and redeploy/reinstall the canister.

## Open Security Items (from SECURITY_AUDIT.md)
4. **Unbounded wait calls** (P0 #5): `Call::unbounded_wait` to history/ledger canisters means if the target hangs, the canister cannot be stopped or upgraded.

5. **Deposit amount overflow silenced** (P0 #7): `try_into().unwrap_or(0)` silently converts overflows to 0.

6. **post_upgrade panic too aggressive** (P1 #11): If deserialization fails, upgrade is rejected. Consider graceful degradation.

7. **EVM RPC inconsistent provider handling** (P2 #14): Accepts first successful provider in `Inconsistent` case.

8. **Stale PENDING_DEPOSITS cleanup** (P2 #15): Async timeouts leave pending flags forever.

9. **Inconsistent fee handling** (P2 #16): Mix of `fee: None` and `fee: Some(...)`.

10. **ICP deposit uses legacy query_blocks** (P2 #18): Should migrate to ICRC-3.

11. **Migrate to ic-stable-structures** (P2 #12): `pre_upgrade` heap serialization will hit instruction limit at scale.

## Incomplete Features
12. **Sidebar collapse reset**: When profile sidebar collapses, shown addresses and polling should reset.

13. **Bust animations**: Fireworks.svelte and RainCloud.svelte need mainnet testing.

14. **ckETH arrival detection**: Progress indicator / ckETH polling UI needs end-to-end testing.

## Recently Fixed (2026-03-30/31)
- ✅ VERIFIED_DEPOSITS pruning deposit replay exploit (E1)
- ✅ ckBTC sweep failure fund recovery (E2)
- ✅ Anonymous principal rejection on all state-mutating functions
- ✅ Saturating arithmetic on all balance operations
- ✅ inspect_message guard
- ✅ created_at_time on all ICRC transfers
- ✅ EVM RPC cycles bumped to 10B
- ✅ WithdrawalGuard / DogeWithdrawalGuard reentrancy prevention
- ✅ ckBTC owner parameter and subaccount derivation
- ✅ Schema versioning on PersistentState
- ✅ BTC withdrawals implemented
- ✅ Rate limiting on all endpoints
- ✅ Frontend CSP headers
- ✅ dfx → icp-cli migration complete

**How to apply:** Address items 1-3 (critical bugs) before adding new features. Items 4-11 are lower priority security hardening.
