# IWithdrawalQueue
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol)

**Inherits:**
[IWithdrawalQueueErrors](/src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol/interface.IWithdrawalQueueErrors.md), [IWithdrawalQueueEvents](/src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol/interface.IWithdrawalQueueEvents.md)


## Functions
### beginWithdrawal

Enters a tokenId into the withdrawal queue by transferring to this contract and creating a ticket.

*The user must not have active votes in the voter contract.*


```solidity
function beginWithdrawal(uint256 _tokenId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokenId`|`uint256`|The tokenId to begin withdrawal for. Will be transferred to this contract before burning.|


### queue

Address of the contract that manages exit queue logic for withdrawals


```solidity
function queue() external view returns (address);
```

