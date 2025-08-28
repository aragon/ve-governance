# Bugs

### 1

Ian found the following bug: see [here](https://gist.github.com/i-tozer/902927b4af9902e94655aa176264c91c)

Clearly, the fix is super simple. I want to explain that I arrived at this bug also on my invariant tests, but with
different scenario(i.e underflow error)

- alice creates lock with amount 7225 (tokenId = 3)
- alice creates lcok with amount 100 (tokenId = 4)
- alice sets delegatee address to alice
- alice merges tokenId 3 into 4

When merge occurs, it calls: `_moveDelegateVotes(alice, address(0), 3, LockedBalance(0, 0));`.

> This gets to ivotesAdapter. Checks if (fromDelegatee != address(0)) which holds true because fromDelegatee is Bob.
> and then does `numberOfDelegatedTokens[_from]--;`. Alice doesn't yet have delegated any tokens, so numberOfDelegatedTokens[alice] is 0. It tries to decremenet, hence underflow.

I wrote a simple test for this which fails but in reality, it should NOT fail.

```js
function test_foundBug1() public {
   escrow.enableSplit();
   address alice = address(456);
   address bob = address(876);

   token.transfer(alice, 50e18);

   vm.startPrank(alice);
   token.approve(address(escrow), 50e18);

   uint256 from = escrow.createLock(7225);
   uint256 to = escrow.createLock(100);
   ivotesAdapter.setDelegateAddress(bob);

   escrow.merge(from, to);

   vm.stopPrank();
}
```

### 2

While we fix the above bug as Ian suggested, for many cases, it works, but we still have a bug.

- Jordan creates a lock (tokenId = 1)
- Jordan sets delegatee to Javi
- Jordan transfers the token to Bob

The above fix is not enough, because `locked.amount` will still be non-zero(note that unless it's transfer, that problem would
not occur, because in other cases - merge/split/....), we pass the amounts correctly. So `locked.amount` is not 0, so
it will try to decrement Javi's voting power when in reality, it shouldn't because Jordan didn't delegate that specific token
to Javi. So the fix is `isTokenDelegated(...)` check must be done above before reducing the checkpoint.

### 3

Invariant also found this bug of Ian: https://gist.github.com/i-tozer/6782aeef5730f8d4688be489ae408778

### 4

- Alice creates lock (i.e tokenId = 5)
- Alice calls `setDelegateAddress(Bob)`
- Alice calls split(5) which causes tokenId = 6 to be created. Since Alice already has bob as her delegator, inside `split`, following is called. `_moveDelegateVotes(address(0), owner, newTokenId, LockedBalance(0, 0));`.
  This causes `tokenId = 6` to be set as delegated, but since no balance in `LockedBalance` is set, `delegatee(Bob)` will still have 0 `getPastVotes`.

The issue doesn't occur in a situation where tokenId = 5 was already delegated in a way that its vp was already applied in EscrowIVotesAdapter.

The below test shows this:

```js
function test_foundBug() public {
   escrow.enableSplit();
   address alice = address(456);
   address bob = address(876);

   token.transfer(alice, 50e18);

   vm.startPrank(alice);
   token.approve(address(escrow), 50e18);
   uint256 tokenId = escrow.createLock(50e18);

   ivotesAdapter.setDelegateAddress(bob);
   uint256 newTokenId = escrow.split(tokenId, 10e18);
   vm.stopPrank();

   assertFalse(ivotesAdapter.tokenIsDelegated(tokenId));
   assertTrue(ivotesAdapter.tokenIsDelegated(newTokenId));

   // This shouldn't be printing 0, but it does..
   console.log(ivotesAdapter.getPastVotes(bob, block.timestamp));

   vm.warp(block.timestamp + 1000);

   console.log(ivotesAdapter.getPastVotes(bob, block.timestamp));
}
```

### 5

With the depth of 15 and 256 runs, which is that in each run, all combinations of functions being called will be 15. This didn't find the following problem, which was found though by 1000 runs and 64 depth.

Scenario:

- Alice creates a lock(amount 100) and delegates this lock to bob. (tokenId = 1)
- 270 weeks passes by which is more than maxTime(255).
- Alice creates another lock(tokenId = 2, amount: 200) which automatically delegates this to bob. Bob's `getPastVotes` incorrectly returns after this because of the following code in `_checkpoint`:

```js
uint256 t_i = (lastPointCheckpoint / checkpointInterval) * checkpointInterval;

// Since `_checkpoint` can be called manually due to transition,
// the global point's writtenTs shouldn't be block.timestamp
// by default, but whatever the transition's max week is.
expectedWrittenTs = t_i + _transitionCount * checkpointInterval;
if (expectedWrittenTs > block.timestamp) {
    expectedWrittenTs = block.timestamp;
}

for (uint256 i = 0; i < _transitionCount; ++i) {

  if (t_i == expectedWrittenTs) {
     break;
  }
}

lastPoint.writtenTs = uint48(expectedWrittenTs);
```

When 200's checkpoint is being stored, it first starts from lastPoint which was stored 270 weeks ago. It moves week by week but only for 255 weeks. Once it gets there, `expectedWrittenTs` is that timestamp(`X`) and stored on the new point. Note that this new point also includes bias of 200 as well.

When `getPastVotes` gets called later on, last point it starts to accumulate from is `X` and sums up more things then it should. We agreed that this is not a problem because as long as merge/split/create lock occurs for delegate during 255 weeks, this will not occur.

In Invariant, how do we tell that createLock/merge/split shouldn't occur for the user if the last point of the user is more than 255 weeks ago ? if we allow this to happen, then invariant test will fail for sure. In handler's createLock/merge/split, we can add:

- get last point of the delegatee.
- see how much time passed from its writtenTs to current time and if it's 255 weeks or more, return early and try different fuzz.

What's important is that what if fuzz does the sequence such as:

```
// alice calls createLock = tokenId = 1
// bob delegates to himself
// bob calls createLock = tokenId = 2
// bob calls createLock = tokenId = 3
// merge(2,3) = for this to happen, we wrap to end date for the merge.
// Now, fuzzer wants to get back to Alice, such that alice creates a lock again.
```

If we check how much time is passed and if longer than >255 weeks, we return early, this is not ideal, because we're limiting the fuzzer to check all the cases - if depth is 64 and we end up in such situation as above, fuzzer would return early, giving us the green light that test worked even though it didn't actually check alice anymore. Better way is to use `checkPointTransition`.

Every single time, we call `createLock/merge/split`, we check if delegatee's last point is too old in the past, if so, we transition with 0 amounts and after this we call the `createLock/merge/split`. This doesn't skip the tests in a nutshell which is better.

The below code shows the bug:

```js
function test_omg() public {
  address ff = address(0x000000000000000000000000000000000000000F);
  address aa = address(0x000000000000000000000000000000000000000A);
  address bb = address(0x000000000000000000000000000000000000000b);

  // alice creates a lock(tokenId = 1)
  _approve(aa, 100);
  vm.prank(aa);
  vm.warp(2557953);
  uint256 tokenId1 = escrow.createLock(100);

  // alice delegates to bob(tokenId = 1)
  vm.startPrank(aa);
  ivotesAdapter.setDelegateAddress(bb);
  uint256[] memory ids = new uint256[](1);
  ids[0] = tokenId1;
  ivotesAdapter.delegate(ids);
  vm.stopPrank();

  // so much time passes that it's more than 255 weeks.
  // alice creates a lock again. This results in the below logs to be different when in reality, they must be the same.
  // The reason I already explained.
  _approve(aa, 351);
  vm.warp(193768858);
  vm.prank(aa);
  uint256 tokenId2 = escrow.createLock(351);

  console.log("dasdkaskd ", ivotesAdapter.getPastVotes(bb, block.timestamp)); // prints 759
  console.log("omg ", escrow.votingPower(tokenId1) + escrow.votingPower(tokenId2)); // prints 551
}
```

And before the last `createLock` is called, we can add `_transitionIfTooOld()`:

```js
function _transitionIfTooOld(address _delegatee) private {
  uint256 latestPointIndex = ivotesAdapter.latestPointIndex(_delegatee);

  (, , uint256 writtenTs) = ivotesAdapter.pointHistory(_delegatee, latestPointIndex);
  uint256 lastPointCheckpointDiff = (block.timestamp - writtenTs) / checkpointInterval;
  if (lastPointCheckpointDiff >= 255) {
      ivotesAdapter.checkpointTransition(_delegatee, lastPointCheckpointDiff + 1);
  }
}
```

### 6

Assume someone calls vote whose getVotes is: 79232698352767939063239375289

With the following param:

```js
gaugeVotes[0] = IGaugeVote.GaugeVote(
  1,
  address(0x0000000000000000000000000000000000000016),
);
gaugeVotes[1] = IGaugeVote.GaugeVote(
  18446744073709551613,
  address(0x0000000000000000000000000000000000000014),
);
gaugeVotes[2] = IGaugeVote.GaugeVote(
  7847948105712314,
  address(0x0000000000000000000000000000000000000019),
);
gaugeVotes[3] = IGaugeVote.GaugeVote(
  451357228,
  address(0x0000000000000000000000000000000000000015),
);
```

`_castVote` calculates each gauge's portion as:

```
uint256 _votes = _votesForGauge(_voteWeight, _votingPower);
```

and record it as:

```js
epochGaugeVotes[_epoch][_gauge] += _votes;
epochTotalVotingPowerCast[_epoch] += _votes;
_voteData.usedVotingPower += _votes;
```

Now, assume reset is called which grabs previously stored votes and re-calculates `_votes` so that it does the subtraction. The way it calculates `_votes` is it takes `_voteData.usedVotingpower` and uses it in:

```
uint256 _votes = _votesForGauge(_voteWeight, _voteData.usedVotingpower);
```

and then subtracts \_votes from `epochGaugeVotes` and `epochTotalVotingPowerCast.`

> problem is that when vote was called, usedVotingpower that was stored was not the original votingPower, but less(by 2), because `_votesForGauge` caused some loss because of divisions. When `_reset` is called, it takes the usedVotingPower which was less by 2, and calcultes \_votes with it. Basically, in the end, when resetting must cause epochGaugeVotes and epochTotalVotingPowerCast to be 0, their values are 0.

This basically causes the situation where when there're lots of users that voted and at some point, all reset(i.e could be due to undelegation or withdrawal), `totalPowerCast` could be (let's say 500), when in reality, it must be 0 as no tokens are delegated anymore.

The fix I used is to store the actual voting power in `usedVotingPower` and not the the one that is accumulated by summing up `_votes` of each gauge portion. This way, when `reset` is called, it can calculate each portion exactly as it did when `_vote`.

> Note that with this fix, we don't have the problem as outlined above, but we introduced a different problem, which is that if you now sum up each gauge's votes and also sum up each user's `usedVotingPower`, the deviation will be the same number as it would be in the problem we outlined above(i.e if we didn't use this fix). We need to decide which one to go with.

### Observations

### 1

For more, refer to [here](https://gist.github.com/novaknole/5ae6e9081f9746055c83b78612922287)

Let's take a look at the following [test](https://github.com/aragon/ve-governance/blob/e08bc381c6c36f9026d1df25c5efb75071f353ce/test/v1_3_0/integration/createLock/Supply.t.sol#L60).

The test creates 2 locks with `Lock_1_Amount` and `Lock_2_Amount`. Then it asserts that total Supply must be:

```js
assertEq(
  curve.supplyAt(currentTs),
  uint256(biasFP(totalLockAmount, currentTs - weekStartTs) / 1e18),
);
```

So it grabs the total supply from curve and compares it with the calculation, done in the test. The test succeeds.

> Guide 1: When writing invariant tests, it helps you to think with different mindset - i.e it lets you think in a maximum
> zoomed-out vision of your project, which can help us think more about what invariants should be and so on.

I noticed that we don't have tests which checks that:

```
k1 = escrow.votingPower(1) + escrow.votingPower(2)
k2 = escrow.totalVotingPower();
assertEq(k1, k2);
```

Adding this test causes the fail. See the below code why:

```js
uint256 amount1 = 54092601847792982561127664171;
    uint256 amount2 = 708697749560516675221610389;

    uint256 maxTime = 52 * 2 weeks;

    // These two result a difference by 1.

    function vpIndSum() public view returns(uint256) {
        // Each one is divided by 1e18 and summed up later.
        return (amount1 * 1e18 + (amount1 * (1e18 / maxTime)) * 3601) / 1e18 + (amount2 * 1e18 + (amount2 * (1e18 / maxTime)) * 3601) / 1e18;
    }

    function vpTotal() public view returns(uint256) {
        // the division by 1e18 happens in the end.
        uint256 slope =  amount1 * (1e18 / maxTime) + amount2 * (1e18 / maxTime);
        uint256 bias = amount1 * 1e18 + amount2 * 1e18;

        return (bias + slope * 3601) / 1e18;
    }
```

So we know the reason. The difference between k1 and k2 will be 1. What's interesting is that if there're 3 locks, then we would have:

```js
k1 = escrow.votingPower(1) + escrow.votingPower(2) + escrow.votingPower(3);
k2 = escrow.totalVotingPower();
assertEq(k1, k2);
```

Now, difference will be 2. Basically, the difference between these k1 and k2 will be the number of tokens that exist.

### 2

https://gist.github.com/giorgilagidze/ebc741ae2bf21b4cc85f3bb36ea5ae27 Is a good example of what I will explain.

Since we add the `vote` function which will be called in a sequence, in some cases, it might be called with a fuzzed address
that don't have voting power > 0. This means that `vote` function will revert on AddressGaugeVoter. To avoid revert, we will check if vp is 0, and if so, return early. This is also not a good idea because in the sequence, so many `vote` functions will be wasted. Our goal is to reduce this waste as much as possible.

The better idea is to add a new structure that stores addresses that have vp > 0 and in `vote`, fuzzed address seed will be bound from 0 to the length of this new structure, meaning that waste will be reduced. Clearly, this waste can not be 0, because if `vote` is called first, before any other function, that list will be empty, in which case we also have to return early(i.e waste), but at least, this is better then previous situation.

### 3

```js
AddressGaugeVoter::vote([
  GaugeVote({
    weight: (27070704904783194385675957493799793)[2.707e34],
    gauge: 0x0000000000000000000000000000000000000016,
  }),
  GaugeVote({
    weight: (411336292589958538808381)[4.113e23],
    gauge: 0x0000000000000000000000000000000000000019,
  }),
  GaugeVote({
    weight: (23985956992884719623905694055088222238)[2.398e37],
    gauge: 0x0000000000000000000000000000000000000015,
  }),
  GaugeVote({ weight: 1, gauge: 0x0000000000000000000000000000000000000017 }),
])[delegatecall];
```

This causes `NoVote` because:

```js
function _normalizedWeight(
  uint256 _weight,
  uint256 _totalWeight
) internal view virtual returns (uint256) {
  return (_weight * 10e32) / _totalWeight;
}
```

weight 1 \* 10e32 / totalWeight is 0, hence reverts. Can this situation be desirable ?

## Merge/Split can circumvent minLock when (MAX_EPOCHS \* epochDuration) < minLock

Assume:

- Constant Curve: (MAX_EPOCHS = 0)
- MinLock = 30 days

Giorgi locks Jan 1 100 tokens creates TokenId 1, can beginWithdraw Jan 30

Then creates (on Jan 15) 1000 tokens TokenId 2, can begin withdraw Feb 14th

Merge 2 into 1. Split 1 into 1 & 3, beginWithdraw

Option 1: prevent merge if not @ minLock
Option 2: vKAT create wvKAT -> wrapped w. a minLock
