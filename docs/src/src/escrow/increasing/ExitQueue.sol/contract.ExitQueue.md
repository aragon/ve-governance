# ExitQueue
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/ExitQueue.sol)

**Inherits:**
[IExitQueue](/src/escrow/increasing/interfaces/IExitQueue.sol/interface.IExitQueue.md), [IClockUser](/src/clock/IClock.sol/interface.IClockUser.md), DaoAuthorizable, UUPSUpgradeable

SPDX-License-Identifier: MIT

Token IDs associated with an NFT are given a ticket when they are queued for exit.
After a cooldown period, the ticket holder can exit the NFT.


## State Variables
### QUEUE_ADMIN_ROLE
role required to manage the exit queue


```solidity
bytes32 public constant QUEUE_ADMIN_ROLE = keccak256("QUEUE_ADMIN");
```


### WITHDRAW_ROLE
role required to withdraw tokens from the escrow contract


```solidity
bytes32 public constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");
```


### MAX_FEE_PERCENT
*10_000 = 100%*


```solidity
uint16 private constant MAX_FEE_PERCENT = 10_000;
```


### feePercent
the fee percent charged on withdrawals


```solidity
uint256 public feePercent;
```


### escrow
address of the escrow contract


```solidity
address public escrow;
```


### clock
clock contract for epoch duration


```solidity
address public clock;
```


### cooldown
time in seconds between exit and withdrawal


```solidity
uint48 public cooldown;
```


### minLock
minimum time from the original lock date before one can enter the queue


```solidity
uint48 public minLock;
```


### _queue
tokenId => Ticket


```solidity
mapping(uint256 => Ticket) internal _queue;
```


### __gap

```solidity
uint256[46] private __gap;
```


## Functions
### constructor


```solidity
constructor();
```

### initialize


```solidity
function initialize(
    address _escrow,
    uint48 _cooldown,
    address _dao,
    uint256 _feePercent,
    address _clock,
    uint48 _minLock
) external initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_escrow`|`address`|address of the escrow contract where tokens are stored|
|`_cooldown`|`uint48`|time in seconds between exit and withdrawal|
|`_dao`|`address`|address of the DAO that will be able to set the queue|
|`_feePercent`|`uint256`||
|`_clock`|`address`||
|`_minLock`|`uint48`||


### onlyEscrow


```solidity
modifier onlyEscrow();
```

### setCooldown

The exit queue manager can set the cooldown period


```solidity
function setCooldown(uint48 _cooldown) external auth(QUEUE_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_cooldown`|`uint48`|time in seconds between exit and withdrawal|


### _setCooldown


```solidity
function _setCooldown(uint48 _cooldown) internal;
```

### setFeePercent

The exit queue manager can set the fee percent


```solidity
function setFeePercent(uint256 _feePercent) external auth(QUEUE_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_feePercent`|`uint256`|the fee percent charged on withdrawals|


### _setFeePercent


```solidity
function _setFeePercent(uint256 _feePercent) internal;
```

### setMinLock

The exit queue manager can set the minimum lock time

*Min 1 second to prevent single block deposit-withdrawal attacks*


```solidity
function setMinLock(uint48 _minLock) external auth(QUEUE_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_minLock`|`uint48`|the minimum time from the original lock date before one can enter the queue|


### _setMinLock


```solidity
function _setMinLock(uint48 _minLock) internal;
```

### withdraw

withdraw staked tokens sent as part of fee collection to the caller

*The caller must be authorized to withdraw by the DAO*


```solidity
function withdraw(uint256 _amount) external auth(WITHDRAW_ROLE);
```

### queueExit

queue an exit for a given tokenId, granting the ticket to the passed holder

*we don't check that the ticket holder is the caller
this is because the escrow contract is the only one that can queue an exit
and we leave that logic to the escrow contract*


```solidity
function queueExit(uint256 _tokenId, address _ticketHolder) external onlyEscrow;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokenId`|`uint256`|the tokenId to queue an exit for|
|`_ticketHolder`|`address`|the address that will be granted the ticket|


### nextExitDate

Returns the next exit date for a ticket

*The next exit date is the later of the cooldown expiry and the next checkpoint*


```solidity
function nextExitDate() public view returns (uint256);
```

### exit

Exits the queue for that tokenID.

*The holder is not checked. This is left up to the escrow contract to manage.*


```solidity
function exit(uint256 _tokenId) external onlyEscrow returns (uint256 fee);
```

### calculateFee

Calculate the exit fee for a given tokenId


```solidity
function calculateFee(uint256 _tokenId) public view returns (uint256);
```

### canExit

*If the admin chages the cooldown, this will affect all ticket holders. We may not want this.*


```solidity
function canExit(uint256 _tokenId) public view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|true if the tokenId corresponds to a valid ticket and the cooldown period has passed|


### ticketHolder


```solidity
function ticketHolder(uint256 _tokenId) external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|holder of a ticket for a given tokenId|


### queue


```solidity
function queue(uint256 _tokenId) external view override returns (Ticket memory);
```

### timeToMinLock


```solidity
function timeToMinLock(uint256 _tokenId) public view returns (uint48);
```

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
function _authorizeUpgrade(address) internal virtual override auth(QUEUE_ADMIN_ROLE);
```

