# IExitQueueCoreErrorsAndEvents
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/IExitQueue.sol)

SPDX-License-Identifier: MIT


## Events
### ExitQueued

```solidity
event ExitQueued(uint256 indexed tokenId, address indexed holder, uint256 exitDate);
```

### Exit

```solidity
event Exit(uint256 indexed tokenId, uint256 fee);
```

## Errors
### OnlyEscrow

```solidity
error OnlyEscrow();
```

### AlreadyQueued

```solidity
error AlreadyQueued();
```

### ZeroAddress

```solidity
error ZeroAddress();
```

### CannotExit

```solidity
error CannotExit();
```

### NoLockBalance

```solidity
error NoLockBalance();
```

