# Audit 3 Notes

This document covers the scope of the third Audit of the Aragon VE Governance repo.

## Background

Aragon released our VE Governance plugin in October 2024. Since then we've deployed it across several large projects such as ModeDAO, PufferDAO, BedrockDAO and more.

This release adds a number of powerful new features that lay the framework for deeper ecosystem integrations:

1. Onchain Total Voting Power Tracking

Adds full Curve-finance style checkpointing of total voting power to the escrow curve, allowing direct onchain queries from a single `supplyAt` view function. This unlocks full onchain governance using vetoes and quorums.

2. IVotes-compatable delegation

We allow address-address delegation of voting power, which in turn exposes an IVotes compatible interface for voting. This allows the Aragon Voting Escrow contracts to be interchanged with a vanilla ERC20Votes token, or used in the same context.

3. Address-based Gauge Voter

Similar to the above, the Aragon Gauge voter now supports Addresses instead of tokenIDs. This allows the existing system to work, via the delegation mechanism, or the use of other ERC20 voting tokens to be used in gauge voting.

4. Improved multitenant versioning, deploys and upgrades.

A lot of work has been done to allow us to manange the different implementations of client contracts, within the same repo.

## Audit Scope

Excluded files have previously been audited, although we have renamed some of the files for consistency. There are a set of contracts that implement "seasons" which is a separate, standalone feature we do not wish to audit at this moment.

The following files can be considered as part of the audit:

| Contract Group | Contract Name                       | In Scope | Details                  |
| -------------- | ----------------------------------- | -------- | ------------------------ |
| `clock`        | Clock_v1_2_0.sol                    | ✅       | Versioned implementation |
| `clock`        | IClock_v1_2_0.sol                   | ✅       | Interface                |
| `curve`        | LinearIncreasingCurve.sol           | ✅       | Main curve logic         |
| `curve`        | LinearIncreasingCurveNoSupply.sol   | ✅       | Variant without supply   |
| `curve`        | IEscrowCurveIncreasing_v1_2_0.sol   | ✅       | Interface                |
| `delegation`   | EscrowIVotesAdapter.sol             | ✅       | IVotes adapter           |
| `delegation`   | IEscrowIVotesAdapter.sol            | ✅       | Interface                |
| `escrow`       | VotingEscrowIncreasing_v1_2_0.sol   | ✅       | Versioned implementation |
| `escrow`       | IVotingEscrowIncreasing_v1_2_0.sol  | ✅       | Interface                |
| `factory`      | GaugesDaoFactory.sol                | ✅       | Base factory             |
| `factory`      | GaugesDaoFactory_v1_1_0.sol         | ✅       | Versioned implementation |
| `factory`      | GaugesDaoFactory_v1_2_0.sol         | ✅       | Versioned implementation |
| `factory`      | GaugesDaoFactory_v1_3_0.sol         | ✅       | Versioned implementation |
| `factory`      | UpgradeFactory_v1_0_0\_\_v1_3_0.sol | ✅       | Upgrade utility          |
| `lock`         | Lock_v1_2_0.sol                     | ✅       | Versioned implementation |
| `setup`        | GaugeVoterSetup_v1_1_0.sol          | ✅       | Versioned setup          |
| `setup`        | GaugeVoterSetup_v1_2_0.sol          | ✅       | Versioned setup          |
| `setup`        | GaugeVoterSetup_v1_3_0.sol          | ✅       | Versioned setup          |
| `voting`       | AddressGaugeVoter.sol               | ✅       | Address-based voter      |
| `voting`       | IAddressGaugeVoter.sol              | ✅       | Interface                |

The following files are not in scope:

| Contract Group | Contract Name                      | In Scope | Details                    |
| -------------- | ---------------------------------- | -------- | -------------------------- |
| `clock`        | Clock.sol                          | ❌       | Core clock contract        |
| `clock`        | ClockSeason.sol                    | ❌       | Season-specific logic      |
| `clock`        | IClock.sol                         | ❌       | Interface                  |
| `clock`        | IClockSeason.sol                   | ❌       | Interface                  |
| `curve`        | QuadraticIncreasingCurve.sol       | ❌       | Quadratic variant          |
| `curve`        | QuadraticIncreasingCurveSeason.sol | ❌       | Season-specific variant    |
| `curve`        | IEscrowCurveIncreasing.sol         | ❌       | Interface                  |
| `escrow`       | VotingEscrowIncreasing.sol         | ❌       | Main escrow contract       |
| `escrow`       | IVotingEscrowIncreasing.sol        | ❌       | Interface                  |
| `factory`      | GaugesDaoFactorySeason.sol         | ❌       | Season-specific            |
| `libs`         | CurveConstantLib.sol               | ❌       | Math/constants lib         |
| `libs`         | ProxyLib.sol                       | ❌       | Proxy utilities            |
| `libs`         | SignedFixedPointMathLib.sol        | ❌       | Math lib                   |
| `lock`         | Lock.sol                           | ❌       | Main lock contract         |
| `lock`         | ILock.sol                          | ❌       | Interface                  |
| `lock`         | IERC721EMB.sol                     | ❌       | ERC721 interface extension |
| `queue`        | ExitQueue.sol                      | ❌       | Queue implementation       |
| `queue`        | IExitQueue.sol                     | ❌       | Interface                  |
| `setup`        | GaugeVoterSetup.sol                | ❌       | Setup logic                |
| `setup`        | GaugeVoterSetupSeason.sol          | ❌       | Season-specific setup      |
| `voting`       | TokenGaugeVoter.sol                | ❌       | Token-based voter          |
| `voting`       | TokenGaugeVoterSeason.sol          | ❌       | Season-specific logic      |
| `voting`       | TokenGaugeVoter_v1_1_0.sol         | ❌       | Versioned implementation   |
| `voting`       | IGaugeVoter.sol                    | ❌       | Interface                  |
| `voting`       | ITokenGaugeVoter.sol               | ❌       | Interface                  |

## Understanding Versioned changes

Aragon uses a version system within the above repo that allows us to manage client deployments with different builds. Below are the changes version to version in each contract. When determining an audit quote we kindly request that the LoC figure takes into account the diffs between contracts, and are happy to provide said diffs if neccessary. Where logical, we provide named versions of the contracts, but a version number is used to denote compatible versions of the same contract.

For the Setup contracts, Gauge DAO Factories and the Deploy/Upgrade scripts, incremental versions simply denote bundles of contracts that are deployed together, specifically:

- Base: TokenGaugeVoter, Escrow Contract w. QuadraticIncreasingCurve (no onchain supply tracking), no merge, split nor delegation.
- 1.1.0: Only change is the 1.1.0 of the voting contract which allows exits during voting windows
- 1.2.0: Deploys Linear Escrow Curve with Merge and Split but without on chain checkpointing/total supply tracking, AddressGaugeVoter and delegation support, locks now start at current week instead of upcoming week
- 1.3.0: Above but with onchain total supply in the Curve.

## List of tricky/hidden details

### isWarm

In the contracts, we use `isWarm` function which either returns false or true. This is needed inside `votingPower` functions
because if `isWarm` returns false, `votingPower` must be 0 even though user holds some power > 0.

It's important to look how `isWarm` worked in previous version and how it works now, especially since we also want to support
upgrading(via UUPS pattern) from previous to new version.

**Previus version:**

when the lock was created, its `checkpointTs` used to be next week's start timestamp. The function looked as:

```js
function isWarm(uint256 tokenId) public view returns (bool) {
  uint256 interval = _getPastTokenPointInterval(tokenId, block.timestamp);
  TokenPoint memory point = _tokenPointHistory[tokenId][interval];
  if (point.bias == 0) return false;
  else return _isWarm(point);
}

function _isWarm(TokenPoint memory _point) public view returns (bool) {
  return block.timestamp > _point.writtenTs + warmupPeriod;
}
```

One thing to note here is `_getPastTokenPointInterval` which still does binary search on `checkpointTs` and not on `writtenTs`.
So if `checkpointTs` > `block.timestamp`, it will return 0 immediatelly as `point.bias == 0` since no point would be found.

After that, `_isWarm` still does the logic on `writtenTs`.

**New version:**

When the lock is created, `checkpointTs` is stored as current week's start timestamp.

---

Main thing is that there might be locks already created with old contracts and then, contracts get upgraded to newever versions.
Our goal is:

> voting power for any user that called before the upgrade and after the upgrade for the same timestamp should always return
> the same result. Otherwise, it feels logically incorrect for Alice to get voting power as 50 and suddenly 0 as contract was
> upgraded or vice versa.

It might make more sense to look into [this](https://gist.github.com/novaknole/e330a69cdc8f572d8541cb18e28ca664) and what
led to our current code.

### votingPowerAt.

Once you look into the `votingPowerAt` code in both previous and new versions, you will realize that in new version, function
got much more complex. This is due to the following fact:

In prev version, when lock was created, we stored `bias = amount` and `checkpointTs = nextWeekStartTs`, whereas in new version,
we store: `bias = amount + slope * (block.timestamp - currentWeekStartTs)` and `checkpointTs = currentWeekStartTs`.

This means that:

- when we want to calculate votingPower, we need to figure out time that is remaining between writtenTs and maxTime. Why ? because
  bias already stores that voting power already calculated between `writtenTs` and `currentWeekStartTs`, so we shouldn't count
  it, if we did, we would include that part in double.
- We also have that check:

```js
if (lastPoint.checkpointTs > lastPoint.writtenTs) {
  lastPoint.writtenTs = lastPoint.checkpointTs;
}
```

This check is for those locks(points) that were created before contracts were upgraded - i.e we need to treat those locks
the same way as new locks. To do that, we make `writtenTs` and `checkpointTs` equal. Why ? because for those locks, `bias`
would already be stored as `amount` directly(without any extra time calculation), hence if we make these two timestamps equal,
it's as if such locks had occured at exactly week start intervals. In such cases, bias would also be stored as amount. Look at
it this way: in new version, if locks get created at exactly week intervals, that means writtenTs = checkpointTs for those
and bias that we would store would be: `amount + slope * (block.timestamp - currentWeekStartTs) = amount`.

### Checkpoint functions in Curve

The checkpoint functions as they are written in new versions are solely due to the reasons to allow `totalSupply` functionality.
Writing such code allows us to have `totalSupply` to work confidently without having an edge case of revert(due to gas).

In case you have questions about this, it's better to ask us directly and we answer one by one.

### Delegations

Users can delegate their vp to other users. This is done in `EscrowIVotesAdapter`. The emphasis I want to make is that,
once token gets transfered/minted/burnt, it's important to update delegation balances. For this, we're using `moveDelegateVotes`
function in EscrowIVotesAdapter. The flow looks like as:

transfer/mint/burnt occurs inside `Lock` contract. (in new versions, it's `Lock_v1_2_0`). `_transfer` hook in this contract
calls `moveDelegateVotes` on the Escrow contract which then calls `moveDelegateVotes` on EscrowIVotesAdapter. Once delegation
balances are updated, it calls back escrow which calls `AddressGaugeVoter`.

The reason why so many calls occur is because we wanted Escrow to be a middle man(connector to all other contracts) - i.e
single point of truth.

`AddressGaugeVoter` is a contract where people can vote to gauges with their voting power. In order to do that, they first
need to delegate either to themselves or others inside EscrowIVotesAdapter. This is to ensure that if user voted to gauge
with vp = 1000 and then he got undelegated and now left with 500 token, we will update that gauge's vote by that user with 500.

## Understanding the contract flow

Please see the [README.md](https://github.com/aragon/ve-governance/blob/audit-3/scope/README.md#contracts-overview) for specifics

![image](https://github.com/user-attachments/assets/476f4c08-4673-4ff4-b98e-f3ecaf404c06)
