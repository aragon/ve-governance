# IGaugeVoterErrors
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/voting/ISimpleGaugeVoter.sol)


## Errors
### AlreadyVoted

```solidity
error AlreadyVoted(uint256 tokenId);
```

### VotingInactive

```solidity
error VotingInactive();
```

### NotApprovedOrOwner

```solidity
error NotApprovedOrOwner();
```

### GaugeDoesNotExist

```solidity
error GaugeDoesNotExist(address _pool);
```

### GaugeInactive

```solidity
error GaugeInactive(address _gauge);
```

### DoubleVote

```solidity
error DoubleVote();
```

### NoVotes

```solidity
error NoVotes();
```

### NoVotingPower

```solidity
error NoVotingPower();
```

### NotCurrentlyVoting

```solidity
error NotCurrentlyVoting();
```

