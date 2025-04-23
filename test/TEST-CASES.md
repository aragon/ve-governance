# Test Cases

This document aims to detail the list of test cases I would expect to see, by contract and in totality.

We go through this in the following way:

1. We review the contracts line by line, writing out the expected cases
2. We think about the e2e test cases we wish to test
3. We check line coverage of the existing test suite to review
4. We finally review the existing cases to see what is covered

At the end, the result should be a list of priority tests that have yet to be written which, ideally, should be grouped into 'need to do before audit' and 'can wait until after audit'.

## Contracts line-by-line

### Clock

- Tests for prevCheckpointTs and the resolve functions
- Test breaking the unchecked blocks
- Ensure view functions all are consistent pre and post upgrade
- Review the audit finding from the guest auditors who say the clock contract is broken

### Curve

- Check pre and post upgrade that the curve coefficient getters return the same value for existing state
- Check pre and post upgrade that the curve coefficient getters return the same value for new state created with the same value as existing state

- Check the bounded elapsed max time for all values of elapsed
- ensure the preview max bias is consistent with the bias of the same amount at max lock
- Ensure all public state variables and view fns return the same values pre and post upgrade
- Ensure the bias is the same over the lifecycle of a tokenId, pre and post upgrade, all the way to maturity

- Ensure all administrative and privileged functions (inc. checkpointing) have the correpsonding access controls

- Warmups, ensure that warmups are consistent across the token lifecycle:
  - CreateLock
  - Merge
  - Split
  - EnterWithdrawalQueue
  - Exit
  - Delegations
- Specifically:

  - warmup is respected in all cases
  - restrictions or non restrictions apply - can merge, split be used to circumvent a warmup
  - should not be possible to cooldown and warmup at the same time

- compare a pre and post upgrade token in warmup. It should remain
- create a token in the same block pre and post upgrade. The new one will not be in warmup the old one will. Think about if this is a problem for us.

- Decide on the mechanisms between delegations and warmups. Should delegations be allowed during a warmup, if not, should we allow atomic delegation. If warmups are min 1 second, this prevents this.

- Differential test the voting power results using a min % deviation from the python implementaion or some multiple https://book.getfoundry.sh/forge/differential-ffi-testing

- basics of vp across life cycle:

  - non existant tid returns 0
  - burned tid returns 0
  - in warmup returns 0
  - Single point tokenId non mature
  - Single point tokenId mature (
  - Multi-point tokenId non mature
  - Multi-point tokenId mature
  - The above is best done at creation, 1s before maturity, at maturity, 1s after maturity
  - sum of vp is unchanged during merge and split and after repeated merge/splits

- SupplyAt

  - Test multiple tokens going through life cycle.
  - At all stages, the invariant must hold: for loop of all voting power = supplyAt
  - So say 5 or 6 tokens:
    - start w. create lock
    - then create a second
    - merge one
    - create a third
    - split one
    - enter w/d
    - hold for maturity
    - burn regular
    - burn merge
    - burn remaining return to zero

- internals (global points and slope changes)

  - check old state is cleared - cannot reuse stale state
  - check slopeChanges correctly removed
  - check globalpoints update correctly
  - check writtenTs ans checkpointTs updates correctly @ all stages of multi-token lifecycle: create, merge, split, exit, burn

- Run a fork test using an existing client

## Delegation

- Check a situation if/when the maxTime could deviate between the curve and the delegation
- Partial delegation not possible:
  - 1 token delgated to someone else
  - After merging
  - After splitting
- Check calling delegate w. tokenIds vs. w. address
- Delegation w. Merge, split, warmup and the exit queue
- Check # delegated tokens updates correctly during merge and split
- Check a simple delegation - self delegation == voting power for the lifetime of a single lock
- Check self delegation w. merge, same deal
- Check self delegation w. split, same deal
- Check a complex delegation for multiple delegates
- Check extreme case, in a situation where all parties delegate to one user, totalSupply == totalDelegatedBalance

- Check partial delegations and that these sum correctly
- Try and break split delegation somehow - Transfers, burns, merges, splits.
- Check numberOfDelegatedTokens correctly decrements during the full lifecycle

- test gas limit # tokens before we can no longer auto delegate

## Escrow

- Can Ivotesadapter be updated?
- Should we call it canSplit?
- Natspec on the isVoting is wrong

- test isVoting with nonexistant tokenId

- createLockFor dust attack for delegation

- Merge:

  - Must own both veNFTs
  - TBD: can the user merge if they don't own `to`?
  - Merge must be either mature or same start date
  - Merging leaves TS unchanged
  - Merging leaves warmup unchanged
  - Can you merge in warmup?
  - Merged token retains delegation
  - Burned token is removed from delegation
  - Burned token is removed from delegatedTokenCount

- Split
  - Split leaves TS unchanged
  - Cannot split unless WL
  - Cannot split below min
  - Cannot split above amount
  - Split tokens retain delegation
  - burned tokenn removed from delegation
  - splitting tokens increaes the delegatedTokenCount

## factory

Test the upgrade factory

## Lock

- Test the lock for mint, burn and transfer
- Test transfers w. whitelisting in and out of SC

## Voter

- Test voting self delegated
  - single token
  - multi token
- Test voting other delegated
- Test someone exits and vp moved
- Test someone changes delegate
- Test all delegations removed from a voting delegate
- Test voting via a proxy
- Test resetting via a proxy
- Test the event logs for reset and vote if called part of a transfer or delegation hook
- Test delegating from self to self
- Test with a vanilla ERC20Votes token
