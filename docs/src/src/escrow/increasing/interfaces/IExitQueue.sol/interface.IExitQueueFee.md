# IExitQueueFee
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/IExitQueue.sol)

**Inherits:**
[IExitQueueFeeErrorsAndEvents](/src/escrow/increasing/interfaces/IExitQueue.sol/interface.IExitQueueFeeErrorsAndEvents.md)


## Functions
### feePercent

optional fee charged for exiting the queue


```solidity
function feePercent() external view returns (uint256);
```

### setFeePercent

The exit queue manager can set the fee


```solidity
function setFeePercent(uint256 _fee) external;
```

### withdraw

withdraw accumulated fees


```solidity
function withdraw(uint256 _amount) external;
```

