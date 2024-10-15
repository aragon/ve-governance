# IExitQueue
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/IExitQueue.sol)

**Inherits:**
[IExitQueueErrorsAndEvents](/src/escrow/increasing/interfaces/IExitQueue.sol/interface.IExitQueueErrorsAndEvents.md), [ITicket](/src/escrow/increasing/interfaces/IExitQueue.sol/interface.ITicket.md), [IExitQueueFee](/src/escrow/increasing/interfaces/IExitQueue.sol/interface.IExitQueueFee.md), [IExitQueueCooldown](/src/escrow/increasing/interfaces/IExitQueue.sol/interface.IExitQueueCooldown.md), [IExitQueueMinLock](/src/escrow/increasing/interfaces/IExitQueue.sol/interface.IExitQueueMinLock.md)


## Functions
### queue

tokenId => Ticket


```solidity
function queue(uint256 _tokenId) external view returns (Ticket memory);
```

### queueExit

queue an exit for a given tokenId, granting the ticket to the passed holder


```solidity
function queueExit(uint256 _tokenId, address _ticketHolder) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokenId`|`uint256`|the tokenId to queue an exit for|
|`_ticketHolder`|`address`|the address that will be granted the ticket|


### exit

exit the queue for a given tokenId. Requires the cooldown period to have passed


```solidity
function exit(uint256 _tokenId) external returns (uint256 exitAmount);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`exitAmount`|`uint256`|the amount of tokens that can be withdrawn|


### canExit


```solidity
function canExit(uint256 _tokenId) external view returns (bool);
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
|`<none>`|`address`|the ticket holder for a given tokenId|


