# IEscrowCurveMath
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/IEscrowCurveIncreasing.sol)


## Functions
### getCoefficients

Preview the curve coefficients for curves up to quadratic.

*Not all coefficients are used for all curves*


```solidity
function getCoefficients(uint256 amount) external view returns (int256[3] memory coefficients);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|The amount of tokens to calculate the coefficients for - given a fixed algebraic representation|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`coefficients`|`int256[3]`|in the form [constant, linear, quadratic]|


### getBias

Bias is the token's voting weight


```solidity
function getBias(uint256 timeElapsed, uint256 amount) external view returns (uint256 bias);
```

