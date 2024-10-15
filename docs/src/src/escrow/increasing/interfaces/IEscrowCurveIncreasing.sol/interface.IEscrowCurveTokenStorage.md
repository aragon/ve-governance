# IEscrowCurveTokenStorage
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/IEscrowCurveIncreasing.sol)


## Structs
### TokenPoint
Captures the shape of the user's voting curve at a specific point in time

*Coefficients are stored in the following order: [constant, linear, quadratic]
and not all coefficients are used for all curves.*


```solidity
struct TokenPoint {
    uint256 bias;
    uint128 checkpointTs;
    uint128 writtenTs;
    int256[3] coefficients;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`bias`|`uint256`|The y intercept of the user's voting curve at the given time|
|`checkpointTs`|`uint128`|The checkpoint when the user voting curve is/was/will be updated|
|`writtenTs`|`uint128`|The timestamp at which we locked the checkpoint|
|`coefficients`|`int256[3]`|The coefficients of the curve, supports up to quadratic curves.|

