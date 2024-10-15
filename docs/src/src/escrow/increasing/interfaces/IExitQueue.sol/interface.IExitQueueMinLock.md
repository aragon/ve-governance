# IExitQueueMinLock
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/IExitQueue.sol)

**Inherits:**
[IExitMinLockCooldownErrorsAndEvents](/src/escrow/increasing/interfaces/IExitQueue.sol/interface.IExitMinLockCooldownErrorsAndEvents.md)


## Functions
### minLock

minimum time from the original lock date before one can enter the queue


```solidity
function minLock() external view returns (uint48);
```

### setMinLock

The exit queue manager can set the minimum lock time


```solidity
function setMinLock(uint48 _cooldown) external;
```

