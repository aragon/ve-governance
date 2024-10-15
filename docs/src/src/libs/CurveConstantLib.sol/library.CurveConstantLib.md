# CurveConstantLib
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/libs/CurveConstantLib.sol)

SPDX-License-Identifier: MIT

Precomputed coefficients for escrow curve


## State Variables
### SHARED_CONSTANT_COEFFICIENT
*Inital multiplier for the deposit.*


```solidity
int256 internal constant SHARED_CONSTANT_COEFFICIENT = 1e18;
```


### SHARED_LINEAR_COEFFICIENT
*For linear curves that need onchain total supply, the linear coefficient is sufficient to show
the slope of the curve.*


```solidity
int256 internal constant SHARED_LINEAR_COEFFICIENT = 236205593348;
```


### SHARED_QUADRATIC_COEFFICIENT
*Quadratic curves can be defined in the case where supply can be fetched offchain.*


```solidity
int256 internal constant SHARED_QUADRATIC_COEFFICIENT = 0;
```


### MAX_EPOCHS
*the maxiumum number of epochs the cure can keep increasing. See the Clock for the epoch duration.*


```solidity
uint256 internal constant MAX_EPOCHS = 5;
```


