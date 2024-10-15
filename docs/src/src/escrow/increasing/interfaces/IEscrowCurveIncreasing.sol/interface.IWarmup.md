# IWarmup
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/IEscrowCurveIncreasing.sol)

**Inherits:**
[IWarmupEvents](/src/escrow/increasing/interfaces/IEscrowCurveIncreasing.sol/interface.IWarmupEvents.md)


## Functions
### setWarmupPeriod

Set the warmup period for the curve


```solidity
function setWarmupPeriod(uint48 _warmup) external;
```

### warmupPeriod

the warmup period for the curve


```solidity
function warmupPeriod() external view returns (uint48);
```

### isWarm

check if the curve is past the warming period


```solidity
function isWarm(uint256 _tokenId) external view returns (bool);
```

