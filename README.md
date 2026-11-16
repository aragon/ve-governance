# Polaris ve-governance

This repository is Polaris's fork of [Aragon's ve-governance](https://github.com/aragon/ve-governance). Polaris uses it for vePOLAR: holders lock POLAR in an escrow and receive an NFT for each lock. The lock's voting power lets them vote in the Polaris DAO, and earns them a share of the protocol's interest.

This README primarily describes what Polaris changed relative to Aragon. It assumes the reader is already familiar with Aragon's ve contracts: the escrow, curve, lock NFT, clock and `EscrowIVotesAdapter`. For Aragon's original documentation, see the [upstream README](https://github.com/aragon/ve-governance/blob/develop/README.md).

The main changes are:

1. Voting power decreases linearly to zero at the end of each lock, instead of increasing over time.
2. Every change takes effect at the next weekly checkpoint, not at the current block time.
3. Locks can be extended, topped up and made permanent. There is no exit queue, cooldown or warmup.
4. Rewards are paid onchain in each Polaris branch's debt asset, through a new `RewardsDistributor`.
5. The lock NFT has onchain artwork.
6. After deployment, no address holds the admin or upgrade roles, so the governance contracts cannot be reconfigured or upgraded.

## Contents

1. [Scope](#1-scope)
2. [Timing: the next weekly checkpoint](#2-timing-the-next-weekly-checkpoint)
3. [Voting power curve](#3-voting-power-curve)
4. [Lock lifecycle](#4-lock-lifecycle)
5. [Delegation and voting](#5-delegation-and-voting)
6. [Rewards](#6-rewards)
7. [Lock NFT artwork](#7-lock-nft-artwork)
8. [Deployment and permissions](#8-deployment-and-permissions)
9. [Development](#9-development)

---

## 1. Scope

Polaris's changes are on the `develop-polaris` branch. This branch was created from Aragon's `develop` at commit `408ad14`, on 25 February 2026.

### Contracts that Polaris deploys

| Contract | Source | Relative to Aragon | Onchain form |
|---|---|---|---|
| `VotingEscrowDecreasing` | [src/escrow/VotingEscrowDecreasing.sol](src/escrow/VotingEscrowDecreasing.sol) | New | Proxy (UUPS) |
| `LinearDecreasingCurve` | [src/curve/LinearDecreasingCurve.sol](src/curve/LinearDecreasingCurve.sol) | New | Proxy (UUPS) |
| `EscrowIVotesAdapterDecreasing` | [src/delegation/EscrowIVotesAdapterDecreasing.sol](src/delegation/EscrowIVotesAdapterDecreasing.sol) | New, adapted from Aragon's `EscrowIVotesAdapter` | Proxy (UUPS) |
| `DelegationHelper` | [src/delegation/DelegationHelper.sol](src/delegation/DelegationHelper.sol) | Modified: adds `updateDelegateVotes` | Inherited by the adapter |
| `ClockV1_2_0` | [src/clock/Clock_v1_2_0.sol](src/clock/Clock_v1_2_0.sol) | Modified: adds `nextCheckpointTs` | Proxy (UUPS) |
| `LockV1_2_0` | [src/lock/Lock_v1_2_0.sol](src/lock/Lock_v1_2_0.sol) | Modified: adds onchain artwork | Proxy (UUPS) |
| `CurveConstantLib` | [src/libs/CurveConstantLibDecreasing.sol](src/libs/CurveConstantLibDecreasing.sol) | New | Library, used at deployment |
| `RewardsDistributor` | [src/rewards/RewardsDistributor.sol](src/rewards/RewardsDistributor.sol) | New | Regular contract, one per Polaris branch |
| `RewardsClaimAggregator` | [src/rewards/RewardsClaimAggregator.sol](src/rewards/RewardsClaimAggregator.sol) | New | Regular contract |
| `TokenVoting` | Polaris's fork of Aragon's token-voting plugin | Modified: adds a maximum proposal duration | Proxy (UUPS) |

Section 8 explains why none of the proxies can be upgraded after deployment.

### New contracts that Polaris does not deploy

These contracts are in the repository but are not part of the Polaris deployment:

- `AddressGaugeVoterDecreasing`. Polaris has no gauge voting, so the escrow's `voter` is never set.
- `GaugesDaoFactoryDecreasing`. Polaris deploys with its own scripts instead (section 8).
- `GaugeVoterSetupDecreasing`. The Polaris deploy scripts import contract types from this file, but do not use the setup itself.

The increasing contracts and the older versions (`v1_0_0` to `v1_4_0`) are unchanged from Aragon.

---

## 2. Timing: the next weekly checkpoint

Polaris records every change to voting power at the start of the next week, while Aragon records changes at the current time or the start of the current week. Sections 3 to 6 all depend on this rule.

### When a change is recorded

The clock has a checkpoint interval of one week and an epoch of two weeks. Checkpoints are whole multiples of one week, counted from the Unix epoch. The Unix epoch was a Thursday at 00:00 UTC, so every checkpoint is also a Thursday at 00:00 UTC.

`ClockV1_2_0.nextCheckpointTs()` rounds the current time up to the next checkpoint. If the current time is exactly a checkpoint, it returns the current time.

The escrow, the curve and the delegation adapter record every change at `nextCheckpointTs()`. This covers:

- creating, topping up, extending and merging locks
- making a lock permanent, or ending a permanent lock
- delegating, undelegating and transferring locks

A change has no effect on voting power at any time before the checkpoint where it is recorded.

For example: Alice creates a lock on a Monday at 10:00 UTC. The lock is recorded at the following Thursday 00:00 UTC. Between Monday 10:00 and Thursday 00:00, `votingPowerAt` returns 0 for her lock. The lock also adds nothing to the total supply or to any delegate during that time.

### How Aragon differs

- Aragon's v1.2+ escrow records a new lock at the start of the current week. The lock therefore counts for a week that has already begun.
- Aragon's adapter records delegate changes at `block.timestamp`.

### Effects of this rule

Voting power in the past cannot change. A change made at time `now` is recorded at `nextCheckpointTs(now)`, which is never earlier than `now`. So the voting power at any time before `now` is final.

New locks and delegations do not count for a proposal that already exists. TokenVoting takes its snapshot at `block.timestamp - 1` when a proposal is created. A lock or delegation made after that time is recorded later than the snapshot, so it does not count.

A new lock earns no rewards for the week in which it is created. The `RewardsDistributor` shares each week's rewards pro-rata to voting power at the start of that week (section 6). A lock created during the week has no voting power at that time.

---

## 3. Voting power curve

### Formula

Voting power falls linearly from its starting value to zero at the end of the lock. This is in contrast to Aragon's increasing curve, which rises.

The maximum lock time is `maxTime = MAX_EPOCHS × epochDuration = 104 × 2 weeks = 208 weeks`, which is about four years. The constants are in [CurveConstantLibDecreasing.sol](src/libs/CurveConstantLibDecreasing.sol).

For a non-permanent lock with amount `A` that ends at time `end`:

```
votingPower(t) = A × (end − t) / maxTime     before end
votingPower(t) = 0                           at end and after
```

A lock's starting voting power therefore depends on its duration. For example:

- A 208-week lock starts at the full amount `A`.
- A 52-week lock starts at `A × 52 / 208`, which is 25% of `A`.

If Alice locks 1,000 POLAR for 104 weeks on a Monday, the lock is recorded at the following Thursday. On that Thursday her voting power is `1,000 × 104 / 208 = 500`. It then falls by about 4.8 each week, and reaches zero 104 weeks later.

### "Virtual start" lock implementation

Under the hood, the curve treats every lock as a maximum-length lock. To do this, the escrow stores a virtual start date instead of the real one:

```
virtualStart = recordedStart + duration − maxTime
end          = virtualStart + maxTime = recordedStart + duration
```

`recordedStart` is the checkpoint at which the lock was recorded. For a 208-week lock, the virtual start equals the recorded start. For a shorter lock, the virtual start is in the past. The diagram at the top of [VotingEscrowDecreasing.sol](src/escrow/VotingEscrowDecreasing.sol) shows this.

In `locked(tokenId)`, the `start` field holds the virtual start, not the time the lock was created. The escrow stores `recordedStart` separately, in its internal `LockedBalanceDecreasing` struct. `getVirtualStart(recordedStart, duration)` returns the virtual start for a given recorded start and duration.

### Permanent locks

A lock with `start == 0` is permanent. Its voting power stays at `A` and does not decrease. Section 4 describes how a lock becomes permanent and how it stops being permanent.

### Rounding

The escrow rounds every deposit down to a multiple of 125,798,400 wei, which is about 1.26e-10 tokens. This number is `maxTime` in seconds. The rounding applies to `createLock`, `createLockFor`, `increaseAmount` and `split`. Only the rounded amount is transferred from the caller, and the remainder stays in their wallet. A deposit smaller than 125,798,400 wei reverts with `ZeroAmount`.

Because every locked amount `A` is a multiple of `maxTime`, voting power falls by exactly `A / maxTime` per second, with no remainder. It therefore reaches exactly zero at `end`. Voting power is also exactly additive. For example, if lock X has 30 voting power and lock Y has 70 at some time, a delegate holding both has exactly 100. The delegation adapter relies on this, because it adds and removes single locks from a delegate's total.

Voting power is computed in two places. The curve computes each lock's voting power and the total voting power. The delegation adapter computes each delegate's voting power. Both also round each lock's amount down in the same way before computing voting power. Since the stored amounts are already multiples, this has no effect. `withdraw` returns the locked amount.

### Points and slope changes

The curve does not store voting power for every moment. It stores points, and computes voting power from them. A point has three fields:

- `writtenTs` is the checkpoint at which the point was recorded.
- `bias` is the voting power at `writtenTs`.
- `slope` is how fast that voting power changes per second. It is negative for a normal lock, and zero for a permanent lock.

After a point, voting power changes in a straight line: `bias + slope × (t − writtenTs)`. It never goes below zero. Internally, `bias` and `slope` are stored scaled by 1e18.

The curve keeps two histories of points:

- Each lock has its own history of token points. Each time the lock is created or changed, the curve adds a point to that lock's history, describing its voting power from the next checkpoint onward. If the lock changes again before that checkpoint, the curve overwrites that point instead of adding another. The same change also updates the global history, described below. `votingPowerAt(tokenId, t)` takes the lock's last point at or before `t`, and extends it in a straight line to `t`.

- The global history describes the voting power of all locks together. A global point's `bias` is the total voting power, and its `slope` is the sum of the slopes of all locks that have not ended yet. `supplyAt(t)` takes the last global point at or before `t`, and extends it to `t`.

Extending a global point in a straight line only works while every lock in the total keeps falling. When a lock reaches its end, its voting power is zero and stops falling. Its slope must then be removed from the total slope. Slope changes record when this happens.

`slopeChanges` maps a time to the combined slope of all locks that end at that time. Each time a lock is created or changed, the curve removes the lock's old slope from its old end time, and adds its new slope at its new end time. Every lock ends on a checkpoint, because both `recordedStart` and the duration are whole weeks. So slope changes only happen at checkpoints.

When the global history is extended, it moves forward one week at a time. At each week, it removes the slopes stored in `slopeChanges` for that week.

For example, lock X ends at week 10 and lock Y ends at week 20. Until week 10, the total voting power falls at the combined rate of X and Y. At week 10, X's slope is removed, so the total falls at Y's rate only. At week 20, Y's slope is removed too. The total then stays constant, at the voting power of any permanent locks.

The delegation adapter uses the same structure for delegates. Each delegate has their own history of points and their own map of slope changes. A delegate's points describe the combined voting power of all locks delegated to them.

### Total supply and long gaps

When the curve records a change, it first brings the global history up to the change's checkpoint. It moves forward from the last global point one week at a time, applies each week's slope changes, and stores a global point for each week. Aragon's `LinearIncreasingCurve` also tracks slope changes. The difference is that Polaris records the points at the next checkpoint.

The update loop stops after 255 weeks. If the history has not been updated for longer than that, the curve applies the remaining time in one linear step. This is correct because every slope change is at most `maxTime` (208 weeks) after the last stored point, so the loop has already applied all of them. `initialize` requires `maxTime ≤ 255 × checkpointInterval`, so this condition always holds.

---

## 4. Lock lifecycle

Aragon's increasing escrow has a warmup period, an exit queue with a cooldown, and optional exit fees. Polaris's escrow has none of these. The owner withdraws a lock directly once it has expired.

### Creating a lock

`createLock(value, duration)` and `createLockFor(value, duration, to)` have these rules:

- `duration` must be a whole number of weeks, from one week to 208 weeks.
- The escrow rounds `value` down to a multiple of 125,798,400 wei (section 3), and transfers only the rounded amount. The rounded amount must be non-zero and at least `minDeposit`, which Polaris sets to 1 wei. So the smallest possible lock is 125,798,400 wei.
- The caller pays the tokens. With `createLockFor`, the NFT goes to `to`. Anyone can create a lock for any address.
- The lock is recorded at the next checkpoint (section 2).
- If the new owner has set a delegate, the lock is delegated to that address automatically (section 5).

The locked token must have 18 decimals and must not charge a fee on transfer.

### Changing a lock

The owner of a lock, or an address approved for its NFT, can change it. Each change takes effect at the next checkpoint.

| Function | Effect | Conditions |
|---|---|---|
| `increaseAmount(tokenId, value)` | Adds `value`, rounded down to a multiple of 125,798,400 wei. The remainder stays with the caller. The end date does not change. | The rounded `value` must be non-zero. The lock must not be expired at the next checkpoint. Permanent locks are allowed. |
| `increaseUnlockTime(tokenId, duration)` | Sets the new end to `nextCheckpointTs() + duration`. | The lock must not be permanent, and must not be expired at the next checkpoint. The new end must be later than the current end. |
| `lockPermanent(tokenId)` | Makes the lock permanent, by setting `start = 0`. Its voting power then stays constant. | The lock must not already be permanent, and must not be expired at the next checkpoint. |
| `unlockPermanent(tokenId)` | Turns a permanent lock back into a 208-week lock, starting at the next checkpoint. | The lock must be permanent. |

`unlockPermanent` always starts a full 208-week lock. Without this rule, a holder could keep full voting power while permanent, and then switch to a short lock in order to leave quickly.

Aragon's increasing escrow has none of these four functions.

### Merging and splitting

`merge(from, to)` has these rules:

- Both locks must have the same owner. The caller must be the owner, or be approved for both NFTs.
- Both locks must have the same `start`. Since `start` is the virtual start, two locks with the same `start` also have the same end date. Two permanent locks can merge, because both have `start == 0`.
- The `from` NFT is burned, and its amount is added to `to`.

Aragon also allows two locks to merge once both have reached maturity. Polaris only allows merging when `start` is equal.

`split` exists, but only whitelisted accounts can use it. Polaris does not whitelist any account and cannot add one after deployment (section 8). Splitting is therefore disabled.

### Expiry and withdrawal

A lock has expired once its end time has been reached. At the end time itself, the lock already counts as expired.The escrow checks this at two different times:

- `increaseAmount`, `increaseUnlockTime`, `lockPermanent` and `delegate(uint256[])` check whether the lock has expired at the next checkpoint (`isLockExpiredAtNextCheckpoint`).
- `withdraw` checks whether the lock has expired at the current time (`isLockCurrentlyExpired`).

As a result, a lock cannot be changed, delegated by token ID, or withdrawn during the last week before it ends. For example, if a lock ends on a Thursday at 00:00 UTC, the next checkpoint during the seven days before that time is the end itself. So the lock already counts as expired for changes and delegation, but `withdraw` still reverts. The owner can withdraw from the end time onward.

`withdraw(tokenId)` has these rules:

- The lock must have expired at the current time.
- The caller must be the owner or an approved address. The caller receives the tokens.
- The NFT is burned, and the lock is removed from its delegate.

A permanent lock never expires. To withdraw it, the owner must first call `unlockPermanent`, and then wait 208 weeks.

### Transfers

Lock NFTs can be transferred to any address. This is enabled at deployment and cannot be disabled afterwards (section 8). As in Aragon, a transfer moves the lock's delegation. The lock is removed from the sender's delegate, and added to the receiver's delegate if the receiver has set one.

---

## 5. Delegation and voting

### What is the same as Aragon

`EscrowIVotesAdapterDecreasing` keeps the interface and behaviour of Aragon's `EscrowIVotesAdapter`:

- `delegate(address)` delegates all of the caller's locks to one address.
- `delegate(uint256[])` and `undelegate(uint256[])` add or remove specific locks for the caller's current delegate.
- `setAutoDelegationDisabled` stops `delegate(address)` from delegating the caller's locks.
- `getVotes`, `getPastVotes`, `getPastTotalSupply` and `delegates` implement OpenZeppelin's `IVotes`. The adapter also implements ERC-6372. Its `clock()` returns `block.timestamp`, and `CLOCK_MODE()` returns `"mode=timestamp"`.
- `delegateBySig` is not supported and reverts.
- Anyone can call `checkpointTransition(delegatee, n)` to update a delegate's history in steps.

Polaris grants `DELEGATION_TOKEN_ROLE` to every address, so anyone can call all of the delegation functions.

### Voting requires delegation

TokenVoting counts an account's votes with `getPastVotes`, which only includes locks delegated to that account. A holder who has not delegated their locks, even to themselves, has no votes.

Undelegated locks still count in `getPastTotalSupply`, which returns the escrow's total voting power. TokenVoting measures minimum participation against this total.

### What Polaris changed

1. Delegate history points are recorded at the _next_ checkpoint (section 2). Aragon records them at `block.timestamp`. The adapter computes each lock's voting power at the next checkpoint, using `elapsed = nextCheckpoint − virtualStart`.
2. A delegate's voting power falls as their delegated locks decrease. Each delegated lock adds a slope change at its end time, in the same way as the curve's global history.
3. When a delegated lock changes, the delegate's voting power is updated. `DelegationHelper.updateDelegateVotes` is new. The escrow calls it from `increaseAmount`, `increaseUnlockTime`, `lockPermanent` and `unlockPermanent`. If the lock is delegated, the delegate's history removes the old lock and adds the changed one.
4. `delegate(uint256[])` reverts with `LockExpired` for a lock that has expired at the next checkpoint. `delegate(address)` does not check expiry. It delegates every lock the caller owns, and an expired lock adds zero voting power.
5. Each delegate's history uses the same 255-week loop as the curve, and the same single linear step for any remaining time. `initialize` requires `maxTime ≤ 255 × checkpointInterval`.

### TokenVoting settings

Polaris uses its fork of Aragon's token-voting plugin, with the adapter as its voting token. The fork adds a maximum proposal duration. The settings are in `script/launch/*.json` in the Polaris repository, with one file per network. The table shows the values in `mainnet.json`:

| Setting | Value |
|---|---|
| Voting mode | Standard |
| Support threshold | 50% |
| Minimum participation | 4% |
| Minimum duration | 1 week |
| Maximum duration | 4 weeks |
| Minimum voting power to create a proposal | 10,000 |
| Minimum approvals | 0 |

Anyone can execute a proposal that has passed. Only accounts with the minimum voting power above can create proposals. This is checked by a `VotingPowerCondition`.

---

## 6. Rewards

Aragon's contracts assume that rewards are distributed offchain. Polaris adds an onchain `RewardsDistributor`, based on Curve's fee distributor and Velodrome's `RewardsDistributor`.

### Deployment

- Polaris deploys one `RewardsDistributor` for each branch. Each distributor pays that branch's debt asset. All of them read voting power from the same escrow.
- The distributor is a regular contract with no admin functions, so it cannot be changed after deployment.
- Its `rewardsSender` is the branch's `PrimaryInterestRouter`, in the Polaris repository. The router sends the distributor a share of the branch's primary interest. The Polaris core contracts require this share to be at least 20%.

### How rewards are assigned to weeks

The router transfers the debt asset to the distributor, and then calls `checkpointToken()` in the same transaction. Only `rewardsSender` can call `checkpointToken`.

`checkpointToken` finds the amount received since its last call, which is the current balance minus the balance it last recorded. It assigns that amount to weeks as follows:

- If the previous payment arrived in the same week, the whole amount is added to the current week.
- Otherwise, the amount is split evenly across each week after the previous payment's week, up to and including the current week. The split covers at most 208 weeks.

For example, a payment arrives in week 10, and the next payment arrives in week 13. The second payment is split equally between weeks 11, 12 and 13.

The router runs on every interest payment, so every CDP operation that pays interest also calls `checkpointToken`. A revert in `checkpointToken` would make those CDP operations revert too.

### How rewards are claimed

For each week `w` that has ended, a lock earns:

```
reward(w) = tokensPerInterval[w] × votingPowerAt(lock, w) / totalVotingPowerAt(w)
```

Both voting powers are read at the start of week `w`. Weeks with zero total voting power are skipped.

- `claim(tokenId)` claims up to 52 weeks in one call. If more weeks are unclaimed, the caller can call it again. `claim(tokenId, receiver, maxIntervals)` lets the caller choose the receiver and the number of weeks.
- The caller must be the owner of the lock, or be approved for it.
- Rewards are computed from each lock's own voting power. Delegating a lock does not change who receives its rewards.
- When a lock NFT is transferred, its unclaimed rewards stay with it, and the new owner can claim them.

`RewardsClaimAggregator` claims from several distributors in one call, for example from every branch. Each distributor checks that its caller is approved for the lock. So the owner must first approve the aggregator for their NFTs. The aggregator sends the rewards to the account that called it.

---

## 7. Lock NFT artwork

The lock NFT generates its metadata onchain:

- `tokenURI` reads the lock's amount and current voting power from the escrow. It passes them to a descriptor contract by calling `renderLock(tokenId, amount, votingPower)`.
- If no descriptor is set, `tokenURI` returns an empty string.
- `setDescriptor` changes the descriptor. It requires the new `LOCK_NFT_ART_UPDATE_ROLE`, which the DAO holds. Governance can therefore change the artwork through a proposal.
- Polaris uses `PolarisNFTDescriptor` from the Polaris repository. The Polaris core NFTs use the same descriptor.

The new `descriptor` storage variable reduced the storage gap from 48 to 47 slots.

---

## 8. Deployment and permissions

### Scripts

Polaris does not use Aragon's factory. It deploys with two scripts in the Polaris repository:

- `script/AragonDeployer.s.sol` deploys the DAO, clock, escrow, curve, lock NFT, adapter, TokenVoting plugin and `RewardsClaimAggregator`, and then sets all permissions.
- `script/DeployPolaris.s.sol` deploys one `RewardsDistributor` for each branch.

The DAO is Polaris's Stewardship. The Polaris core contracts use the DAO's address as their Stewardship address. A change to Polaris parameters therefore needs a proposal that passes in TokenVoting and executes through the DAO.

### Parameters

| Parameter | Value |
|---|---|
| Locked token | POLAR |
| `minDeposit` | 1 wei. Deposits are rounded down first, so the smallest lock is 125,798,400 wei. |
| `maxTime` | 208 weeks |
| Checkpoint interval | 1 week |
| Epoch | 2 weeks |
| Lock NFT name and symbol | "Voting Escrow", "VE" |

### Permissions after deployment

The deploy script grants these permissions:

- TokenVoting can execute actions on the DAO.
- Anyone can execute a proposal that has passed.
- Anyone with at least the minimum voting power can create a proposal.
- Every address has `DELEGATION_TOKEN_ROLE` on the adapter.
- The DAO has `LOCK_NFT_ART_UPDATE_ROLE` on the lock NFT.

During deployment, the deployer holds some admin roles, for example to link the contracts and to enable lock transfers. It revokes them afterwards. The script then checks that neither the deployer nor the DAO holds any of these:

- `ROOT_PERMISSION`, `UPGRADE_DAO_PERMISSION`, `SET_METADATA_PERMISSION`, `SET_TRUSTED_FORWARDER_PERMISSION`, `REGISTER_STANDARD_CALLBACK_PERMISSION` and `VALIDATE_SIGNATURE_PERMISSION` on the DAO
- `ESCROW_ADMIN_ROLE`, `PAUSER_ROLE` and `SWEEPER_ROLE` on the escrow
- `CURVE_ADMIN_ROLE` on the curve
- `DELEGATION_ADMIN_ROLE` on the adapter
- `CLOCK_ADMIN_ROLE` on the clock
- `LOCK_ADMIN_ROLE` on the lock NFT
- `UPDATE_VOTING_SETTINGS_PERMISSION` on TokenVoting

The script does not grant these roles to any other address either.

In a standard Aragon setup, the DAO holds `ROOT_PERMISSION` on itself, so governance can grant and revoke permissions. In Polaris, no address holds it, so no permission can be granted after deployment. This has the following effects:

- The escrow, curve, adapter, clock and lock NFT are UUPS proxies, but none of them can be upgraded.
- None of them can be paused.
- The escrow's settings are fixed. `minDeposit` stays at 1 wei, splitting stays disabled, and no voter can be set.
- Nobody can call `sweep` or `sweepNFT` on the escrow.
- Lock transfers stay enabled for every address.
- The TokenVoting settings cannot change.

The DAO can still execute proposals, which is how it acts as Polaris's Stewardship. It can also change the lock NFT artwork.

---

## 9. Development

### Setup

Install [Foundry](https://getfoundry.sh/). Some tasks also use [GNU Make](https://www.gnu.org/software/make/).

```sh
forge build
```

### Tests

The tests for the Polaris contracts are in `test/v1_4_0_decreasing`.

```sh
# Unit and integration tests for the decreasing contracts
forge test --match-path "test/v1_4_0_decreasing/{unit,integration}/**/*.sol"

# Invariant tests for the decreasing contracts
forge test --match-path "test/v1_4_0_decreasing/invariant/**/*.sol"

# Unit and integration tests for all versions, including Aragon's
make test-ui
```

These commands do not run the fork test in `test/v1_4_0_decreasing/fork`.

### Further reading

- Aragon's [upstream README](https://github.com/aragon/ve-governance/blob/develop/README.md) covers the original contracts, the factory and Aragon's deployment process.
- Aragon's [curve design notes](https://github.com/jordaniza/ve-explainer/blob/main/README.md) explain the general approach to escrow curves.
