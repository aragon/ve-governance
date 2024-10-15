# IExitQueueFeeErrorsAndEvents
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/IExitQueue.sol)


## Events
### Withdraw

```solidity
event Withdraw(address indexed to, uint256 amount);
```

### FeePercentSet

```solidity
event FeePercentSet(uint256 feePercent);
```

## Errors
### FeeTooHigh

```solidity
error FeeTooHigh(uint256 maxFee);
```

