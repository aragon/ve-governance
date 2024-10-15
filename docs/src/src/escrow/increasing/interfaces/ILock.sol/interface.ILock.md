# ILock
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/ILock.sol)

**Inherits:**
[IWhitelist](/src/escrow/increasing/interfaces/ILock.sol/interface.IWhitelist.md)


## Functions
### escrow

Address of the escrow contract that holds underyling assets


```solidity
function escrow() external view returns (address);
```

## Errors
### OnlyEscrow

```solidity
error OnlyEscrow();
```

