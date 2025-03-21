Options available to us

1. pullAt -

We currently store

```solidity
struct Checkpoint {
    uint256 timestamp;
    uint256 balance;
}

mapping(address => Checkpoint[]) public delegateCheckpoints;
```

Pull at would retroactively insert a checkpoint at the timestamp `_at`, which would be at the index in between `a` and `b`. This can be efficiently found using a binary search.

We could do something like:

```solidity
struct DelegationHistory {
    uint256 timestamp;
    address delegatee;
}

mapping(uint256 => DelegationHistory) public delegationHistories;
```

Thus, the pullAt command must do the following:

-> fetch the history of delegation (the closest delegation checkpoint BEFORE the `_at` timestamp)
-> check that the closest delegation matches the destination for the pull
-> if it does, we need to then find the delegate checkpoint at the time

```solidity
function _updateDelegateBalanceAt(
  address _delegate,
  function(uint256, uint256) view returns (uint256) _op,
  uint256 _delta,
  uint256 _at
) internal {
  uint256 currentBalance = 0;

  uint256 length = delegateCheckpoints[_delegate].length;
  if (length != 0) {
    currentBalance = delegateCheckpoints[_delegate][length - 1].balance;
  }

  // Store a new checkpoint
  delegateCheckpoints[_delegate].push(
    Checkpoint(block.timestamp, _op(currentBalance, _delta))
  );
}
```

2. Self delegation - is it required
