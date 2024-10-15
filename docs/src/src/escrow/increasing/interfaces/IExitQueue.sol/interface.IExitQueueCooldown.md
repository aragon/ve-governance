# IExitQueueCooldown
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/IExitQueue.sol)

**Inherits:**
[IExitQueueCooldownErrorsAndEvents](/src/escrow/increasing/interfaces/IExitQueue.sol/interface.IExitQueueCooldownErrorsAndEvents.md)


## Functions
### cooldown

time in seconds between exit and withdrawal


```solidity
function cooldown() external view returns (uint48);
```

### setCooldown

The exit queue manager can set the cooldown period


```solidity
function setCooldown(uint48 _cooldown) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_cooldown`|`uint48`|time in seconds between exit and withdrawal|


