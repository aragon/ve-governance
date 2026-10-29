# Integrating VE Governance

Start with the deployed component addresses and implementations. This guide describes the [v1.4 component set](../src/setup/GaugeVoterSetup_v1_4_0.sol); [older configurations](versions-and-upgrades.md) have different voting and withdrawal behavior.

## Discover the component set

The deployment factory exposes `getDeployment()` and `getDeploymentParameters()`. The v1.4 deployment contains the DAO, multisig, gauge-voter plugin repository, and an array of `GaugePluginSet` records. Each set contains the voter, curve, exit queue, escrow, clock, NFT, and delegation adapter for one underlying token.

An organization using two underlying tokens has two independent VE component sets. Configure the escrow address separately from the factory, and keep each token's escrow, adapter, queue, and voter together.

The factory records the original deployment. Read the live contracts for current implementations, permissions, and mutable references.

Source: [factory structs and getters](../src/factory/GaugesDaoFactory_v1_4_0.sol).

## Creating a position

The sequence is:

```text
underlying.approve(escrow, amount)
escrow.createLock(amount)
adapter.delegate(holderAddress)       // self-delegate to vote directly
```

These are separate contract calls unless an integration explicitly batches them. `amount` is in the underlying token's smallest units. Check the token's decimals and the escrow's `minDeposit()` before requesting an approval.

`createLockFor(amount, recipient)` supports deposits on another address's behalf. The caller supplies and approves the tokens; the recipient receives the NFT. For contract recipients, verify ERC-721 receipt support.

Read `locked(tokenId)` for principal and recorded start, `ownedTokens(account)` for owned position IDs, and `votingPower(tokenId)` for current position power. The adapter's `getVotes(account)` gives the power delegated to an address. Label each value according to what it measures.

The position's recorded start is a weekly boundary, which can precede the transaction. Display the transaction time separately if a user needs to know when they deposited.

Source: [escrow interface](../src/escrow/IVotingEscrowIncreasing_v1_2_0.sol), [adapter](../src/delegation/EscrowIVotesAdapter.sol).

## Casting votes

Before submitting a vote, read the voter's pause state, `votingActive()`, the delegate's voting power, and the active gauges. `getAllGauges()` also includes registered gauges that may have been deactivated; check each gauge's status.

Deactivating a gauge prevents new votes for it but does not clear its stored weights. Your allocation policy must specify whether to include those weights in a payout calculation.

The address voter accepts an array of `GaugeVote` records:

```text
[
  { weight: 3, gauge: gaugeA },
  { weight: 1, gauge: gaugeB }
]
```

This assigns approximately three quarters of the address's power to A and one quarter to B. Weights are relative integers; casting them transfers no tokens. Normalization can reject weights that round a gauge allocation to zero. Include each gauge only once.

Calling `vote` replaces the caller's earlier allocation in the active accounting mode. `reset()` removes that allocation during the voting window. With the standard hook-enabled setup, users can leave an allocation in place across epochs and recast when they want to update its weights or include increased voting power.

The delegate submits one vote from their address using delegated power, without a separate vote signature from each NFT owner. Changing delegation can reduce the previous delegate's stored gauge votes.

Sources: [vote structure](../src/voting/IAddressGaugeVoter.sol), [vote validation and reset](../src/voting/AddressGaugeVoter.sol).

## Gauge result accounting

Read `enableUpdateVotingPowerHook()` before interpreting results. The v1.4 setup enables this setting, but it is administratively mutable.

| Question | Hook enabled, as in the v1.4 setup | Hook disabled |
| --- | --- | --- |
| Voting power used for a new vote | Current `getVotes(account)` | `getPastVotes(account, currentEpochStart())` |
| Storage bucket returned by `getWriteEpochId()` | `0` | Current epoch ID |
| Allocation lifetime | Persists until replaced, reset, or reduced | Stored separately for each epoch |
| Delegation or position changes | Escrow hook can reduce stored allocations | Integration relies on the epoch-start snapshot model |

Read `epochGaugeVotes(bucket, gauge)` and `epochTotalVotingPowerCast(bucket)` using the mode's storage bucket. Hook mode uses `0`, including when the wall-clock epoch ID differs. `votes(account, gauge)` selects the correct bucket internally.

Events include a wall-clock epoch identifier even when persistent totals use bucket `0`. An indexer must distinguish event timing from the contract's storage key.

### Defining a reward snapshot

An allocation integration needs to specify:

1. The chain, voter, implementation, hook mode, and block at which results are read.
2. Which gauges qualify, including how deactivation is handled.
3. How weights become entitlements, including rounding, unallocated funds, and zero-vote periods.
4. The reward budget and the contract or process that pays recipients.

In hook mode, voting-power reductions can change totals after the window closes. For a historical snapshot, read at the chosen block or reconstruct state through an indexer. Current storage holds the latest totals.

Your protocol defines its emission schedule, bribe market if any, reward asset, and payout contract.

### Example: allocating one reward budget

Suppose a protocol sets a budget of 10,000 reward tokens for a cycle. Its policy distributes the full budget in proportion to the weights of two eligible gauges at a chosen snapshot block:

| Gauge | Weight at the snapshot | Share | Reward allocation |
| --- | --- | --- | --- |
| A | 300 | 75% | 7,500 tokens |
| B | 100 | 25% | 2,500 tokens |

The integration reads both weights at the same block using the appropriate storage bucket, calculates the allocations, and pays the recipients defined by its policy through a separate distribution process. A gauge address identifies a voting option; the policy must establish who receives its allocation.

This is an illustrative allocation policy. The VE contracts provide the weights; they do not reserve this budget or execute these payouts. Whether votes bind the payout depends on how the protocol implements and controls that distribution process.

## Withdrawal UI

Keep these stages distinct:

| Stage | Read or action |
| --- | --- |
| Check minimum lock age | Queue's `timeToMinLock(tokenId)` and the position's recorded start |
| Authorize custody transfer | Approve the escrow in the lock NFT contract |
| Start withdrawal | Escrow's `beginWithdrawal(tokenId)` |
| Read pending request | Queue's `queue(tokenId)` and `ticketHolder(tokenId)` |
| Quote current fee | Queue's `calculateFee(tokenId)` |
| Check withdrawal eligibility | Queue's `canExit(tokenId)` |
| Complete withdrawal | Escrow's `withdraw(tokenId)` from the ticket holder |
| Cancel request | Escrow's `cancelWithdrawalRequest(tokenId)` from the ticket holder |

Use each ticket's stored terms and fee quote; global settings may have changed since it was queued. Tiered fees stay at the higher rate through equality with `cooldown`. Query `calculateFee` for the current quote.

Starting withdrawal removes voting power immediately. Completing withdrawal burns the NFT and returns principal minus the fee. Refresh delegation and gauge state after either a position change or a cancellation.

Sources: [escrow withdrawal functions](../src/escrow/VotingEscrowIncreasing_v1_2_0.sol), [dynamic queue](../src/queue/DynamicExitQueue.sol).

## Using the IVotes adapter in proposal governance

The adapter exposes current votes, timestamp-based historical votes, and total historical escrow supply. An external proposal system must use a compatible timestamp clock and choose an appropriate snapshot policy.

`getPastTotalSupply` includes voting power that has not been delegated. A quorum based on that supply therefore has a different denominator from a quorum based only on participating or delegated power. The v1.2 no-supply curve does not provide the same total-supply capability as the v1.3 and v1.4 setups.

The adapter's `balanceOf` counts NFTs, and `delegateBySig` reverts. Check whether the consuming plugin supports those behaviors.

To execute proposals, install a proposal plugin and grant it execution authority through governance. The gauge voter only records allocations.

## Integration references

- [Delegation and voting integration tests](../test/v1_4_0/integration/votingWithDelegations/Voting.sol)
- [Position creation tests](../test/v1_4_0/integration/createLock/)
- [Withdrawal integration tests](../test/v1_4_0/integration/withdrawals/)
- [Contract specifications](../src/specs/)
- [Architecture and permissions](architecture.md)
