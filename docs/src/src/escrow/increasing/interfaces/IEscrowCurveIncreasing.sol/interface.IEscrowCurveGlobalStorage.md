# IEscrowCurveGlobalStorage
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/IEscrowCurveIncreasing.sol)

SPDX-License-Identifier: MIT


## Structs
### GlobalPoint
Captures the shape of the aggregate voting curve at a specific point in time

*Coefficients are stored in the following order: [constant, linear, quadratic]
and not all coefficients are used for all curves.*


```solidity
struct GlobalPoint {
    uint128 bias;
    uint256 ts;
    int256[3] coefficients;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`bias`|`uint128`|The y intercept of the aggregate voting curve at the given time|
|`ts`|`uint256`|The timestamp at which the we last updated the aggregate voting curve|
|`coefficients`|`int256[3]`|The coefficients of the aggregated curve, supports up to quadratic curves.|

