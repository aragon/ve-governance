# IGaugeVote
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/voting/ISimpleGaugeVoter.sol)


## Structs
### TokenVoteData
*this changes so we need an historic snapshot*


```solidity
struct TokenVoteData {
    mapping(address => uint256) votes;
    address[] gaugesVotedFor;
    uint256 usedVotingPower;
    uint256 lastVoted;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`votes`|`mapping(address => uint256)`|gauge => votes cast at that time|
|`gaugesVotedFor`|`address[]`|array of gauges we have active votes for|
|`usedVotingPower`|`uint256`|total voting power used at the time of the vote|
|`lastVoted`|`uint256`|is the last time the user voted|

### GaugeVote

```solidity
struct GaugeVote {
    uint256 weight;
    address gauge;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`weight`|`uint256`|proportion of voting power the token will allocate to the gauge. Will be normalised.|
|`gauge`|`address`|address of the gauge to vote for|

