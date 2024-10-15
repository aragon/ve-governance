# QuadraticIncreasingEscrow
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/QuadraticIncreasingEscrow.sol)

**Inherits:**
IEscrowCurve, [IClockUser](/src/clock/IClock.sol/interface.IClockUser.md), ReentrancyGuard, DaoAuthorizable, UUPSUpgradeable

SPDX-License-Identifier: MIT


## State Variables
### CURVE_ADMIN_ROLE
Administrator role for the contract


```solidity
bytes32 public constant CURVE_ADMIN_ROLE = keccak256("CURVE_ADMIN_ROLE");
```


### escrow
The VotingEscrow contract address


```solidity
address public escrow;
```


### clock
The Clock contract address


```solidity
address public clock;
```


### tokenPointIntervals
tokenId => point epoch: incremented on a per-tokenId basis


```solidity
mapping(uint256 => uint256) public tokenPointIntervals;
```


### warmupPeriod
The warmup period for the curve


```solidity
uint48 public warmupPeriod;
```


### _tokenPointHistory
*tokenId => tokenPointIntervals => TokenPoint*

*The Array is fixed so we can write to it in the future
This implementation means that very short intervals may be challenging*


```solidity
mapping(uint256 => TokenPoint[1_000_000_000]) internal _tokenPointHistory;
```


### SHARED_QUADRATIC_COEFFICIENT
*precomputed coefficients of the quadratic curve*


```solidity
int256 private constant SHARED_QUADRATIC_COEFFICIENT = CurveConstantLib.SHARED_QUADRATIC_COEFFICIENT;
```


### SHARED_LINEAR_COEFFICIENT

```solidity
int256 private constant SHARED_LINEAR_COEFFICIENT = CurveConstantLib.SHARED_LINEAR_COEFFICIENT;
```


### SHARED_CONSTANT_COEFFICIENT

```solidity
int256 private constant SHARED_CONSTANT_COEFFICIENT = CurveConstantLib.SHARED_CONSTANT_COEFFICIENT;
```


### MAX_EPOCHS

```solidity
uint256 private constant MAX_EPOCHS = CurveConstantLib.MAX_EPOCHS;
```


### __gap
*gap for upgradeable contract*


```solidity
uint256[45] private __gap;
```


## Functions
### constructor


```solidity
constructor();
```

### initialize


```solidity
function initialize(address _escrow, address _dao, uint48 _warmupPeriod, address _clock) external initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_escrow`|`address`|VotingEscrow contract address|
|`_dao`|`address`||
|`_warmupPeriod`|`uint48`||
|`_clock`|`address`||


### _getQuadraticCoeff


```solidity
function _getQuadraticCoeff(uint256 amount) internal pure returns (int256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`int256`|The coefficient for the quadratic term of the quadratic curve, for the given amount|


### _getLinearCoeff


```solidity
function _getLinearCoeff(uint256 amount) internal pure returns (int256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`int256`|The coefficient for the linear term of the quadratic curve, for the given amount|


### _getConstantCoeff

*In this case, the constant term is 1 so we just case the amount*


```solidity
function _getConstantCoeff(uint256 amount) public pure returns (int256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`int256`|The constant coefficient of the quadratic curve, for the given amount|


### _getCoefficients

*The coefficients are returned in the order [constant, linear, quadratic]*


```solidity
function _getCoefficients(uint256 amount) public pure returns (int256[3] memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`int256[3]`|The coefficients of the quadratic curve, for the given amount|


### getCoefficients

*The coefficients are returned in the order [constant, linear, quadratic]
and are converted to regular 256-bit signed integers instead of their fixed-point representation*


```solidity
function getCoefficients(uint256 amount) public pure returns (int256[3] memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`int256[3]`|The coefficients of the quadratic curve, for the given amount|


### getBias

Returns the bias for the given time elapsed and amount, up to the maximum time


```solidity
function getBias(uint256 timeElapsed, uint256 amount) public view returns (uint256);
```

### _getBias


```solidity
function _getBias(uint256 timeElapsed, int256[3] memory coefficients) internal view returns (uint256);
```

### _maxTime


```solidity
function _maxTime() internal view returns (uint256);
```

### previewMaxBias


```solidity
function previewMaxBias(uint256 amount) external view returns (uint256);
```

### setWarmupPeriod


```solidity
function setWarmupPeriod(uint48 _warmupPeriod) external auth(CURVE_ADMIN_ROLE);
```

### isWarm

Returns whether the NFT is warm


```solidity
function isWarm(uint256 tokenId) public view returns (bool);
```

### _isWarm


```solidity
function _isWarm(TokenPoint memory _point) public view returns (bool);
```

### tokenPointHistory

Returns the TokenPoint at the passed interval


```solidity
function tokenPointHistory(uint256 _tokenId, uint256 _tokenInterval) external view returns (TokenPoint memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokenId`|`uint256`|The NFT to return the TokenPoint for|
|`_tokenInterval`|`uint256`|The epoch to return the TokenPoint at|


### _getPastTokenPointInterval

Binary search to get the token point interval for a token id at or prior to a given timestamp
Once we have the point, we can apply the bias calculation to get the voting power.

*If a token point does not exist prior to the timestamp, this will return 0.*


```solidity
function _getPastTokenPointInterval(uint256 _tokenId, uint256 _timestamp) internal view returns (uint256);
```

### votingPowerAt


```solidity
function votingPowerAt(uint256 _tokenId, uint256 _t) external view returns (uint256);
```

### supplyAt

[NOT IMPLEMENTED] Calculate total voting power at some point in the past

*This function will be implemented in a future version of the contract*


```solidity
function supplyAt(uint256) external pure returns (uint256);
```

### checkpoint

A checkpoint can be called by the VotingEscrow contract to snapshot the user's voting power


```solidity
function checkpoint(
    uint256 _tokenId,
    IVotingEscrow.LockedBalance memory _oldLocked,
    IVotingEscrow.LockedBalance memory _newLocked
) external nonReentrant;
```

### _checkpoint

Record gper-user data to checkpoints. Used by VotingEscrow system.

*Curve finance style but just for users at this stage*


```solidity
function _checkpoint(
    uint256 _tokenId,
    IVotingEscrow.LockedBalance memory,
    IVotingEscrow.LockedBalance memory _newLocked
) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokenId`|`uint256`|NFT token ID.|
|`<none>`|`IVotingEscrow.LockedBalance`||
|`_newLocked`|`IVotingEscrow.LockedBalance`|New locked amount / end lock time for the user|


### implementation

Returns the address of the implementation contract in the [proxy storage slot](https://eips.ethereum.org/EIPS/eip-1967) slot the [UUPS proxy](https://eips.ethereum.org/EIPS/eip-1822) is pointing to.


```solidity
function implementation() public view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the implementation contract.|


### _authorizeUpgrade

Internal method authorizing the upgrade of the contract via the [upgradeability mechanism for UUPS proxies](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable) (see [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822)).


```solidity
function _authorizeUpgrade(address) internal virtual override auth(CURVE_ADMIN_ROLE);
```

## Errors
### OnlyEscrow

```solidity
error OnlyEscrow();
```

