---
name: Pending Bugs and Issues
description: Known bugs and incomplete work items as of 2026-03-19
type: project
---

## Critical Bugs
1. **Deposit modal freeze on ETH table**: "Cannot access 'Se' before initialization" — Svelte 5 temporal dead zone error. The $derived or $effect declarations have a circular or out-of-order reference. Needs reordering of reactive declarations in DepositModal.svelte.

2. **ETH table shows ICP balance label**: The table balance badge shows "ICP" instead of "ETH" in some contexts.

3. **ETH table min_buy_in too high**: Currently 0.01 ETH, Christopher wants 0.001 ETH. Need to update icp.yaml init_args and redeploy/reinstall the canister.

## Incomplete Features
4. **Sidebar collapse reset**: When profile sidebar collapses, shown addresses and polling should reset. Not yet implemented.

5. **Bust animations**: Fireworks.svelte and RainCloud.svelte components were created and added to PokerTable.svelte, but not yet tested on mainnet. Need to verify they trigger correctly when a player goes bust in heads-up.

6. **ckETH arrival detection**: The progress indicator / ckETH polling UI in the sidebar is implemented but wasn't fully tested end-to-end because the sweep succeeded before the UI was deployed.

7. **CSS for progress indicator**: The eth-progress-section, progress bar, step indicators, and "Why the wait?" box styles may be incomplete in DepositModal.svelte.

**How to apply:** Start the next session by addressing items 1-3 (critical bugs) before adding new features.
