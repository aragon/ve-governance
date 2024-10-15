# IGaugeVoterEvents
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/voting/ISimpleGaugeVoter.sol)


## Events
### Voted

```solidity
event Voted(
    address indexed voter,
    address indexed gauge,
    uint256 indexed epoch,
    uint256 tokenId,
    uint256 votingPowerCastForGauge,
    uint256 totalVotingPowerInGauge,
    uint256 totalVotingPowerInContract,
    uint256 timestamp
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`voter`|`address`||
|`gauge`|`address`||
|`epoch`|`uint256`||
|`tokenId`|`uint256`||
|`votingPowerCastForGauge`|`uint256`|votes cast by this token for this gauge in this vote|
|`totalVotingPowerInGauge`|`uint256`|total voting power in the gauge at the time of the vote, after applying the vote|
|`totalVotingPowerInContract`|`uint256`|total voting power in the contract at the time of the vote, after applying the vote|
|`timestamp`|`uint256`||

### Reset

```solidity
event Reset(
    address indexed voter,
    address indexed gauge,
    uint256 indexed epoch,
    uint256 tokenId,
    uint256 votingPowerRemovedFromGauge,
    uint256 totalVotingPowerInGauge,
    uint256 totalVotingPowerInContract,
    uint256 timestamp
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`voter`|`address`||
|`gauge`|`address`||
|`epoch`|`uint256`||
|`tokenId`|`uint256`||
|`votingPowerRemovedFromGauge`|`uint256`|votes removed by this token for this gauge, at the time of this rest|
|`totalVotingPowerInGauge`|`uint256`|total voting power in the gauge at the time of the reset, after applying the reset|
|`totalVotingPowerInContract`|`uint256`|total voting power in the contract at the time of the reset, after applying the reset|
|`timestamp`|`uint256`||

