# ERC20Votes + AddressGaugeVoter `enableUpdateVotingPower` PoC

## Summary

**The feature works.** A standard ERC20Votes token can be modified to integrate with AddressGaugeVoter's `enableUpdateVotingPowerHook`, enabling persistent votes across epochs with automatic downward adjustment on token transfers.

## Architecture

```
ERC20VotesWithGaugeHook (token + ivotesAdapter + escrow)
        │
        │  _afterTokenTransfer()
        │  ──────────────────────►  AddressGaugeVoter.updateVotingPower(from, to)
        │                           │
        │                           ├─ reads getVotes(from) / getVotes(to)
        │                           ├─ if power decreased → auto-recast votes proportionally
        │                           └─ if power increased → no-op (prevents inflation)
        │
        └── implements IVotes (getVotes, getPastVotes, delegates)
```

The token serves three roles simultaneously:
1. **Token** - ERC20 with voting checkpoints
2. **IVotes adapter** - provides `getVotes()` / `getPastVotes()` / `delegates()`
3. **Escrow** - set as the `escrow` address so its calls pass `onlyEscrow`

## Implementation

The only modification needed to a standard OZ `ERC20Votes` token is overriding `_afterTokenTransfer`:

```solidity
function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual override {
    // OZ updates voting power checkpoints first
    super._afterTokenTransfer(from, to, amount);

    if (voter == address(0)) return;

    address fromDelegatee = (from != address(0)) ? delegates(from) : address(0);
    address toDelegatee   = (to != address(0))   ? delegates(to)   : address(0);

    if (fromDelegatee != address(0) || toDelegatee != address(0)) {
        address effFrom = fromDelegatee != address(0) ? fromDelegatee : toDelegatee;
        address effTo   = toDelegatee   != address(0) ? toDelegatee   : fromDelegatee;
        IAddressGaugeVoter(voter).updateVotingPower(effFrom, effTo);
    }
}
```

**Critical detail**: `super._afterTokenTransfer` must be called first so that OZ's `_moveVotingPower` updates the checkpoints *before* the voter reads `getVotes()`. Calling it with amount 0 or after the hook will produce stale reads.

## Initialization

```solidity
AddressGaugeVoter.initialize(
    dao,
    address(token),   // escrow = token (passes onlyEscrow modifier)
    false,            // not paused
    address(clock),
    address(token),   // ivotesAdapter = token (implements IVotes)
    true              // enableUpdateVotingPowerHook = true
);
```

## Behavior When Hook Is Enabled

| Scenario | Behavior |
|---|---|
| Vote once | Votes persist across all future epochs (stored in epoch 0) |
| Transfer tokens (power decreases) | Votes auto-adjust downward proportionally |
| Receive tokens (power increases) | Votes do NOT inflate; user must re-vote to use new power |
| Re-vote | Resets old votes, casts new votes with current `getVotes()` |
| Delegation | Delegatee's votes auto-adjust when delegated power changes |
| Double-voting | Prevented - sender's votes decrease, receiver must vote explicitly |

## Tests Passing

| # | Test | What it proves |
|---|---|---|
| 1 | `test_basicVoting` | Single voter, single gauge, single epoch |
| 2 | `test_votesPersistAcrossEpochs` | Votes in epoch N visible in epoch N+1 |
| 3 | `test_multiVoterMultiGaugeMultiEpoch` | 3 voters, 3 gauges, 3 epochs with vote changes |
| 4 | `test_transferDecreasesVotingPowerAutoAdjusts` | Transfer triggers auto downward adjustment |
| 5 | `test_transferIncreasesVotingPowerNoInflation` | Receiving tokens does NOT inflate votes |
| 6 | `test_revoteAfterPowerIncrease` | Manual re-vote captures increased power |
| 7 | `test_fullScenarioMultiEpochWithTransfers` | Multi-epoch with transfers and new voters |
| 8 | `test_doubleVotingPrevented` | Full transfer + re-vote cannot double-spend |
| 9 | `test_delegationToThirdParty` | Delegation to a third party works correctly |

## Caveats

1. **Token must be upgradeable or new** - Existing immutable ERC20Votes tokens cannot add the hook. This requires either a new deployment or an upgradeable token.

2. **Token is the escrow** - The token address is set as both `escrow` and `ivotesAdapter`. This is unconventional but works because the `onlyEscrow` modifier just checks `msg.sender == escrow`, and transfers originate from the token contract.

3. **Gas overhead** - Every transfer incurs the cost of `updateVotingPower`, which may reset+recast votes for both sender and receiver. For tokens with frequent transfers, this is non-trivial.

4. **Delegation changes** - When delegation (`delegate()`) changes, the ERC20Votes `_delegate` function calls `_moveVotingPower` but does NOT call `_afterTokenTransfer`. The hook only fires on actual token transfers. If delegation changes need to trigger vote updates, `_delegate` would also need to be overridden.

5. **Mint/Burn** - `_mint` and `_burn` do trigger `_afterTokenTransfer` in OZ v4, so minting to or burning from a voting account will correctly trigger the hook.
