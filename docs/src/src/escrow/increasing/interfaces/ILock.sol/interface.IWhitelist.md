# IWhitelist
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/ILock.sol)

**Inherits:**
[IWhitelistEvents](/src/escrow/increasing/interfaces/ILock.sol/interface.IWhitelistEvents.md), [IWhitelistErrors](/src/escrow/increasing/interfaces/ILock.sol/interface.IWhitelistErrors.md)


## Functions
### setWhitelisted

Set whitelist status for an address


```solidity
function setWhitelisted(address addr, bool isWhitelisted) external;
```

### whitelisted

Check if an address is whitelisted


```solidity
function whitelisted(address addr) external view returns (bool);
```

