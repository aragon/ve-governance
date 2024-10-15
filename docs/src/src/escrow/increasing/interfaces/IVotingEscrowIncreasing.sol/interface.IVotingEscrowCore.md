# IVotingEscrowCore
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol)

**Inherits:**
[ILockedBalanceIncreasing](/src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol/interface.ILockedBalanceIncreasing.md), [IVotingEscrowCoreErrors](/src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol/interface.IVotingEscrowCoreErrors.md), [IVotingEscrowCoreEvents](/src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol/interface.IVotingEscrowCoreEvents.md)


## Functions
### token

Address of the underying ERC20 token.


```solidity
function token() external view returns (address);
```

### lockNFT

Address of the lock receipt NFT.


```solidity
function lockNFT() external view returns (address);
```

### totalLocked

Total underlying tokens deposited in the contract


```solidity
function totalLocked() external view returns (uint256);
```

### locked

Get the raw locked balance for `_tokenId`


```solidity
function locked(uint256 _tokenId) external view returns (LockedBalance memory);
```

### createLock

Deposit `_value` tokens for `msg.sender`


```solidity
function createLock(uint256 _value) external returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_value`|`uint256`|Amount to deposit|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|TokenId of created veNFT|


### createLockFor

Deposit `_value` tokens for `_to`


```solidity
function createLockFor(uint256 _value, address _to) external returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_value`|`uint256`|Amount to deposit|
|`_to`|`address`|Address to deposit|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|TokenId of created veNFT|


### withdraw

Withdraw all tokens for `_tokenId`


```solidity
function withdraw(uint256 _tokenId) external;
```

### isApprovedOrOwner

helper utility for NFT checks


```solidity
function isApprovedOrOwner(address spender, uint256 tokenId) external view returns (bool);
```

