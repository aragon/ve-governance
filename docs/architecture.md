# How VE Governance works

This guide follows the contracts selected by [`GaugeVoterSetup_v1_4_0.sol`](../src/setup/GaugeVoterSetup_v1_4_0.sol) and connected by [`GaugesDaoFactory_v1_4_0.sol`](../src/factory/GaugesDaoFactory_v1_4_0.sol). The [version map](versions-and-upgrades.md) covers the older and Season configurations.

## The position and its owner

The escrow holds one configured ERC-20 token. Each deposit creates a position with an amount and recorded start timestamp. The ERC-721 contract `LockV1_2_0` records its owner; the NFT identifier links that ownership to the escrow balance and curve history.

The NFT gives its owner a claim to the underlying tokens under the withdrawal rules. The curve calculates voting power, which the escrow and delegation adapter expose.

`createLockFor(amount, recipient)` pulls tokens from the caller and mints the NFT to the recipient. The recipient must be able to receive an ERC-721 safely. The token must have 18 decimals, and the escrow checks that the amount received equals the amount requested.

Source: [escrow creation and accounting](../src/escrow/VotingEscrowIncreasing_v1_2_0.sol), [NFT minting and transfers](../src/lock/Lock_v1_2_0.sol).

## Voting power grows with the position's age

The v1.4 deployment script passes the same coefficients and maximum epoch count to the curve and delegation adapter. The checked-in [`CurveConstantLib`](../src/libs/CurveConstantLib.sol) supplies a linear curve with a baseline multiplier of 1 and a zero quadratic term.

Ignoring fixed-point rounding, its shape is:

```text
age = min(max(query timestamp - recorded start, 0), maximum growth time)
voting power ≈ deposited amount × (1 + age / maximum growth time)
maximum growth time = 52 × 2 weeks = 104 weeks
```

This formula describes the current linear coefficients for an active position. Checkpoint history accounts for position changes and exits; use contract queries for withdrawn or nonexistent positions.

The recorded start is the beginning of the current weekly checkpoint interval. A new position can therefore have more than the baseline power. The minimum lock requirement also counts from this recorded start, which can precede the deposit transaction.

At maximum voting power, tokens remain in escrow until the holder completes the withdrawal process under the exit ticket's terms.

Holders do not choose an unlock date when creating a position. The creation methods take an amount and, optionally, a recipient. There is no direct top-up or lock-extension method in this escrow: an additional deposit creates a new position, which can be merged with another only when the merge conditions permit it.

[`CurveConstantLibFlat`](../src/libs/CurveConstantLibFlat.sol) supplies flat coefficients. To use them, change how the script constructs the implementations; the v1.4 script currently imports `CurveConstantLib`. Use matching coefficients for the curve and adapter.

The newer linear curve retains a `warmupPeriod` storage field for compatibility, but does not use it as the older quadratic curve's warmup gate. See [migration timing](versions-and-upgrades.md#migration-timing).

Sources: [linear curve](../src/curve/LinearIncreasingCurve.sol), [v1.4 script](../script/deploy/DeployGauges_v1_4_0.s.sol), [curve inspection script](../test/python/crosscheck.py).

## The clock

[`ClockV1_2_0`](../src/clock/Clock_v1_2_0.sol) uses Unix timestamps, with these implementation constants:

| Setting | Value | Meaning |
| --- | --- | --- |
| Epoch duration | 2 weeks | Repeating voting cycle |
| Checkpoint interval | 1 week | Grid used for position starts and accounting |
| Vote duration | 1 week | Nominal first-week voting phase |
| Vote window buffer | 1 hour | Voting starts after the opening boundary and ends before the first week closes |

For an epoch starting at `E`, the voting window is:

```text
E + 1 hour <= timestamp < E + 1 week - 1 hour
```

Epochs follow Unix time independently of deployment and pause state. Use `votingActive()` and the timestamp getters to find the voting window.

An allocation process can operate outside the voting window. It runs separately from the clock, which only calculates timing.

## Delegation

`EscrowIVotesAdapter` aggregates voting power by delegate address. A holder chooses one delegate address for their account. The usual `delegate(address)` path delegates the account's owned positions when auto-delegation is enabled. A holder can self-delegate, select another address, or delegate to the zero address to remove their delegation.

Auto-delegation is enabled by default and takes effect after the account chooses a delegate. Until then, a new lock contributes no delegated votes. The adapter can update delegation as positions are minted, transferred, merged, split, or removed.

Selective token-ID delegation uses `setDelegateAddress`, `delegate(uint256[])`, and `undelegate(uint256[])`. All require `DELEGATION_TOKEN_ROLE`; the token-list methods also check ownership. The v1.4 setup grants this role to the DAO, so these methods require additional permissions for other callers.

The holder keeps the NFT and withdrawal rights when delegating. Voting authority alone gives the delegate no withdrawal rights.

| Adapter method | Meaning |
| --- | --- |
| `getVotes(account)` | Current delegated voting power |
| `getPastVotes(account, timestamp)` | Delegated voting power at a timestamp |
| `getPastTotalSupply(timestamp)` | Total escrow voting power, including undelegated power |
| `balanceOf(account)` | Number of position NFTs owned by the account, not its voting power |
| `clock()` | Current timestamp |
| `CLOCK_MODE()` | Timestamp-based clock declaration |

`delegateBySig` reverts. An IVotes consumer must support timestamp-based snapshots for this adapter.

Source: [adapter](../src/delegation/EscrowIVotesAdapter.sol), [delegation interfaces](../src/delegation/IEscrowIVotesAdapter.sol).

## Gauge voting

A gauge is an address and metadata record identifying an allocation option. Voting records a weight for that address without calling it. The gauge administrator manages these records and their active status.

An address submits relative weights, such as 3 for one gauge and 1 for another. The voter normalizes those weights and allocates approximately 75% and 25% of the address's available voting power, subject to integer rounding. Gauge addresses must exist and be active. Duplicate gauges and weights that round to zero are rejected.

Calling `vote` again replaces the address's previous allocation. A holder can delegate to an address that combines their votes with votes from other holders.

### The hook-enabled configuration

The v1.4 setup initializes `AddressGaugeVoter` with `enableUpdateVotingPowerHook = true`.

- Votes use the delegate's current voting power when cast.
- Allocations persist across epochs in storage bucket `0`.
- A new voting window permits changes; it does not automatically clear the preceding allocation.
- Growth of voting power over time does not continuously increase the stored votes. Recasting during a voting window captures the current power.
- Delegation and position changes reach the voter through the adapter and escrow hook. The hook reduces stored voting power when required; increases do not automatically expand an allocation.
- Reductions can occur outside the voting window. A closed window is not an immutable reward snapshot.

### The hook-disabled configuration

With the hook disabled, `_vote` uses `getPastVotes(account, currentEpochStart())` and stores votes under the current epoch ID. This provides a separate accounting model for a compatible voting token that does not update the voter through transfer or delegation hooks.

Changing the hook setting changes the voting-power source and storage selection. Keep queries consistent with the chosen accounting mode.

Source: [`AddressGaugeVoter`](../src/voting/AddressGaugeVoter.sol). The [integration guide](integration.md#gauge-result-accounting) explains how to consume these results.

## Transfers, merges, and splits

The v1.4 NFT contract initially allows transfers involving the escrow. Other transfers require either a whitelisted endpoint or globally enabled transfers. Transfers update delegated voting-power accounting through the escrow.

A merge requires approval for both positions and a common owner. Their recorded starts must match, or both positions must be past the curve's maturity boundary. Splitting requires the owner to be permitted by the escrow's split whitelist, unless splitting has been enabled globally. Both resulting amounts must meet the minimum deposit.

These operations update delegation in v1.4. Older token-ID voting has different voting locks and reset rules; check the deployed escrow and NFT implementations.

Source: [merge and split logic](../src/escrow/VotingEscrowIncreasing_v1_2_0.sol), [NFT transfer rules](../src/lock/Lock_v1_2_0.sol).

## Withdrawals and fees

Withdrawal has two stages:

1. `beginWithdrawal(tokenId)` checks eligibility, removes the position's voting power, transfers its NFT into escrow custody, and creates a queue ticket for its owner.
2. `withdraw(tokenId)` verifies the caller is the ticket holder and the queue permits an exit, pays any fee to the queue, burns the NFT, and returns the remaining underlying tokens.

The owner must approve the escrow to transfer the NFT before beginning withdrawal. A position cannot begin withdrawal at the timestamp recorded by its same-block withdrawal guard. The minimum lock requirement is checked against `locked.start + minLock`.

The ticket holder can cancel a pending withdrawal to remove the ticket, restore curve accounting, and recover the NFT. Refresh delegation state afterward.

### DynamicExitQueue modes

The v1.4 setup initializes the queue in fixed-fee mode. The queue administrator can select another supported mode for subsequent tickets:

| Mode | Eligible exit | Fee |
| --- | --- | --- |
| Fixed | After the configured wait | Fixed percentage |
| Tiered | After a shorter minimum wait | Higher fee through the full cooldown boundary, lower fee afterward |
| Dynamic | After a shorter minimum wait | Declines linearly from the higher fee to the lower fee across the decay period |

Fees use basis points: 10,000 = 100%, 100 = 1%. Durations use seconds. `minLock` must be nonzero. Dynamic and tiered configurations require the full cooldown to exceed the minimum cooldown and the higher fee to exceed the lower fee.

The ticket snapshots the fee and cooldown parameters when it is queued. Later global fee changes do not rewrite existing tickets. Use the ticket's `canExit(tokenId)` and `calculateFee(tokenId)` results for a withdrawal quote; `getTimeBasedFee(elapsed)` describes the current global settings.

Exit fees accumulate in the queue for collection by a caller with `WITHDRAW_ROLE`. The queue does not distribute them to veNFT holders.

Sources: [escrow exit lifecycle](../src/escrow/VotingEscrowIncreasing_v1_2_0.sol), [dynamic queue](../src/queue/DynamicExitQueue.sol).

## Administration and permissions

OSx permissions connect an authorized caller, a target contract, and a permission ID. The v1.4 setup grants these component roles to the DAO:

| Component | Role | Relevant authority |
| --- | --- | --- |
| Gauge voter | `GAUGE_ADMIN_ROLE` | Manage gauges, pause voting, change adapter and hook settings |
| Gauge voter | `UPGRADE_PLUGIN_PERMISSION_ID` | Authorize voter upgrades |
| Escrow | `ESCROW_ADMIN_ROLE` | Configure permitted component references, minimum deposit, and splitting; authorize upgrades |
| Escrow | `PAUSER_ROLE` | Pause and unpause escrow operations |
| Escrow | `SWEEPER_ROLE` | Recover excess underlying tokens or eligible misplaced NFTs |
| Curve | `CURVE_ADMIN_ROLE` | Authorize curve upgrades |
| Clock | `CLOCK_ADMIN_ROLE` | Authorize clock upgrades |
| Lock NFT | `LOCK_ADMIN_ROLE` | Manage transfer whitelists and authorize NFT upgrades |
| Delegation adapter | `DELEGATION_ADMIN_ROLE` | Pause delegation and authorize adapter upgrades |
| Delegation adapter | `DELEGATION_TOKEN_ROLE` | Use the restricted selective-delegation methods |
| Exit queue | `QUEUE_ADMIN_ROLE` | Configure exit terms and authorize queue upgrades |
| Exit queue | `WITHDRAW_ROLE` | Withdraw collected fees |

The supplied factory installs an OSx multisig to administer the DAO. Governance can change permissions later. The component contracts are upgradeable, so a deployment's control model includes whoever can authorize those upgrades.

The implementation allows some escrow references to be set only once; the voter has an administrative setter. Check the installed revision's setters and upgrade permissions before replacing a component.

Sources: [setup permissions](../src/setup/GaugeVoterSetup_v1_4_0.sol), [factory wiring](../src/factory/GaugesDaoFactory_v1_4_0.sol).
