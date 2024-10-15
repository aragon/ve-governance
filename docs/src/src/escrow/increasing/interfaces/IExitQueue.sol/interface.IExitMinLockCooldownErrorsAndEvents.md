# IExitMinLockCooldownErrorsAndEvents
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/IExitQueue.sol)


## Events
### MinLockSet

```solidity
event MinLockSet(uint48 minLock);
```

## Errors
### MinLockOutOfBounds

```solidity
error MinLockOutOfBounds();
```

### MinLockNotReached

```solidity
error MinLockNotReached(uint256 tokenId, uint48 minLock, uint48 earliestExitDate);
```

