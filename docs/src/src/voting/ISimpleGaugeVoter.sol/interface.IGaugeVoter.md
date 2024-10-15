# IGaugeVoter
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/voting/ISimpleGaugeVoter.sol)

**Inherits:**
[IGaugeVoterEvents](/src/voting/ISimpleGaugeVoter.sol/interface.IGaugeVoterEvents.md), [IGaugeVoterErrors](/src/voting/ISimpleGaugeVoter.sol/interface.IGaugeVoterErrors.md), [IGaugeVote](/src/voting/ISimpleGaugeVoter.sol/interface.IGaugeVote.md)


## Functions
### vote

Called by users to vote for pools. Votes distributed proportionally based on weights.


```solidity
function vote(uint256 _tokenId, GaugeVote[] memory _votes) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokenId`|`uint256`|    Id of veNFT you are voting with.|
|`_votes`|`GaugeVote[]`|      Array of votes to be cast, contains gauge address and weight.|


### reset

Called by users to reset voting state. Required when withdrawing or transferring veNFT.


```solidity
function reset(uint256 _tokenId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokenId`|`uint256`|Id of veNFT you are reseting.|


### isVoting

Can be called to check if a token is currently voting


```solidity
function isVoting(uint256 _tokenId) external view returns (bool);
```

