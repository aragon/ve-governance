# IDynamicVoter
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol)

**Inherits:**
[IDynamicVoterErrors](/src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol/interface.IDynamicVoterErrors.md)


## Functions
### voter

Address of the voting contract.

*We need to ensure votes are not left in this contract before allowing positing changes*


```solidity
function voter() external view returns (address);
```

### curve

Address of the voting Escrow Curve contract that will calculate the voting power


```solidity
function curve() external view returns (address);
```

### votingPower

Get the voting power for _tokenId at the current timestamp

*Returns 0 if called in the same block as a transfer.*


```solidity
function votingPower(uint256 _tokenId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokenId`|`uint256`|.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Voting power|


### votingPowerAt

Get the voting power for _tokenId at a given timestamp


```solidity
function votingPowerAt(uint256 _tokenId, uint256 _t) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokenId`|`uint256`|.|
|`_t`|`uint256`|Timestamp to query voting power|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Voting power|


### votingPowerForAccount

Get the voting power for _account at the current timestamp
Aggregtes all voting power for all tokens owned by the account

*This cannot be used historically without token snapshots*


```solidity
function votingPowerForAccount(address _account) external view returns (uint256);
```

### totalVotingPower

Calculate total voting power at current timestamp


```solidity
function totalVotingPower() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Total voting power at current timestamp|


### totalVotingPowerAt

Calculate total voting power at a given timestamp


```solidity
function totalVotingPowerAt(uint256 _t) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_t`|`uint256`|Timestamp to query total voting power|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Total voting power at given timestamp|


### isVoting

See if a queried _tokenId has actively voted


```solidity
function isVoting(uint256 _tokenId) external view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if voted, else false|


### setVoter

Set the global state voter


```solidity
function setVoter(address _voter) external;
```

