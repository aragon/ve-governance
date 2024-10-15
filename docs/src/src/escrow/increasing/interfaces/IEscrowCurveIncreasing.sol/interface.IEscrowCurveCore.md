# IEscrowCurveCore
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/IEscrowCurveIncreasing.sol)

**Inherits:**
[IEscrowCurveErrorsAndEvents](/src/escrow/increasing/interfaces/IEscrowCurveIncreasing.sol/interface.IEscrowCurveErrorsAndEvents.md)


## Functions
### votingPowerAt

Get the current voting power for `_tokenId`

*Adheres to the ERC20 `balanceOf` interface for Aragon compatibility
Fetches last token point prior to a certain timestamp, then walks forward to timestamp.*


```solidity
function votingPowerAt(uint256 _tokenId, uint256 _t) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokenId`|`uint256`|NFT for lock|
|`_t`|`uint256`|Epoch time to return voting power at|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Token voting power|


### supplyAt

Calculate total voting power at some point in the past


```solidity
function supplyAt(uint256 _t) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_t`|`uint256`|Time to calculate the total voting power at|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Total voting power at that time|


### checkpoint

Writes a snapshot of voting power at the current epoch


```solidity
function checkpoint(
    uint256 _tokenId,
    ILockedBalanceIncreasing.LockedBalance memory _oldLocked,
    ILockedBalanceIncreasing.LockedBalance memory _newLocked
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokenId`|`uint256`|Snapshot a specific token|
|`_oldLocked`|`ILockedBalanceIncreasing.LockedBalance`|The token's previous locked balance|
|`_newLocked`|`ILockedBalanceIncreasing.LockedBalance`|The token's new locked balance|


