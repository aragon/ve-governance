# IEscrowCurveToken
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/IEscrowCurveIncreasing.sol)

**Inherits:**
[IEscrowCurveTokenStorage](/src/escrow/increasing/interfaces/IEscrowCurveIncreasing.sol/interface.IEscrowCurveTokenStorage.md)


## Functions
### tokenPointIntervals

returns the token point at time `timestamp`


```solidity
function tokenPointIntervals(uint256 timestamp) external view returns (uint256);
```

### tokenPointHistory

Returns the TokenPoint at the passed epoch


```solidity
function tokenPointHistory(uint256 _tokenId, uint256 _loc) external view returns (TokenPoint memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokenId`|`uint256`|The NFT to return the TokenPoint for|
|`_loc`|`uint256`|The epoch to return the TokenPoint at|


