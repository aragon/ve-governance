# IClock
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/clock/IClock.sol)


## Functions
### epochDuration


```solidity
function epochDuration() external pure returns (uint256);
```

### checkpointInterval


```solidity
function checkpointInterval() external pure returns (uint256);
```

### voteDuration


```solidity
function voteDuration() external pure returns (uint256);
```

### voteWindowBuffer


```solidity
function voteWindowBuffer() external pure returns (uint256);
```

### currentEpoch


```solidity
function currentEpoch() external view returns (uint256);
```

### resolveEpoch


```solidity
function resolveEpoch(uint256 timestamp) external pure returns (uint256);
```

### elapsedInEpoch


```solidity
function elapsedInEpoch() external view returns (uint256);
```

### resolveElapsedInEpoch


```solidity
function resolveElapsedInEpoch(uint256 timestamp) external pure returns (uint256);
```

### epochStartsIn


```solidity
function epochStartsIn() external view returns (uint256);
```

### resolveEpochStartsIn


```solidity
function resolveEpochStartsIn(uint256 timestamp) external pure returns (uint256);
```

### epochStartTs


```solidity
function epochStartTs() external view returns (uint256);
```

### resolveEpochStartTs


```solidity
function resolveEpochStartTs(uint256 timestamp) external pure returns (uint256);
```

### votingActive


```solidity
function votingActive() external view returns (bool);
```

### resolveVotingActive


```solidity
function resolveVotingActive(uint256 timestamp) external pure returns (bool);
```

### epochVoteStartsIn


```solidity
function epochVoteStartsIn() external view returns (uint256);
```

### resolveEpochVoteStartsIn


```solidity
function resolveEpochVoteStartsIn(uint256 timestamp) external pure returns (uint256);
```

### epochVoteStartTs


```solidity
function epochVoteStartTs() external view returns (uint256);
```

### resolveEpochVoteStartTs


```solidity
function resolveEpochVoteStartTs(uint256 timestamp) external pure returns (uint256);
```

### epochVoteEndsIn


```solidity
function epochVoteEndsIn() external view returns (uint256);
```

### resolveEpochVoteEndsIn


```solidity
function resolveEpochVoteEndsIn(uint256 timestamp) external pure returns (uint256);
```

### epochVoteEndTs


```solidity
function epochVoteEndTs() external view returns (uint256);
```

### resolveEpochVoteEndTs


```solidity
function resolveEpochVoteEndTs(uint256 timestamp) external pure returns (uint256);
```

### epochNextCheckpointIn


```solidity
function epochNextCheckpointIn() external view returns (uint256);
```

### resolveEpochNextCheckpointIn


```solidity
function resolveEpochNextCheckpointIn(uint256 timestamp) external pure returns (uint256);
```

### epochNextCheckpointTs


```solidity
function epochNextCheckpointTs() external view returns (uint256);
```

### resolveEpochNextCheckpointTs


```solidity
function resolveEpochNextCheckpointTs(uint256 timestamp) external pure returns (uint256);
```

