# Clock
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/clock/Clock.sol)

**Inherits:**
[IClock](/src/clock/IClock.sol/interface.IClock.md), DaoAuthorizable, UUPSUpgradeable

SPDX-License-Identifier: MIT


## State Variables
### CLOCK_ADMIN_ROLE

```solidity
bytes32 public constant CLOCK_ADMIN_ROLE = keccak256("CLOCK_ADMIN_ROLE");
```


### EPOCH_DURATION
*Epoch encompasses a voting and non-voting period*


```solidity
uint256 internal constant EPOCH_DURATION = 2 weeks;
```


### CHECKPOINT_INTERVAL
*Checkpoint interval is the time between each voting checkpoint*


```solidity
uint256 internal constant CHECKPOINT_INTERVAL = 1 weeks;
```


### VOTE_DURATION
*Voting duration is the time during which votes can be cast*


```solidity
uint256 internal constant VOTE_DURATION = 1 weeks;
```


### VOTE_WINDOW_BUFFER
*Opens and closes the voting window slightly early to avoid timing attacks*


```solidity
uint256 internal constant VOTE_WINDOW_BUFFER = 1 hours;
```


### __gap

```solidity
uint256[50] private __gap;
```


## Functions
### constructor


```solidity
constructor();
```

### initialize


```solidity
function initialize(address _dao) external initializer;
```

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
function resolveEpoch(uint256 timestamp) public pure returns (uint256);
```

### elapsedInEpoch


```solidity
function elapsedInEpoch() external view returns (uint256);
```

### resolveElapsedInEpoch


```solidity
function resolveElapsedInEpoch(uint256 timestamp) public pure returns (uint256);
```

### epochStartsIn


```solidity
function epochStartsIn() external view returns (uint256);
```

### resolveEpochStartsIn

Number of seconds until the start of the next epoch (relative)

*If exactly at the start of the epoch, returns 0*


```solidity
function resolveEpochStartsIn(uint256 timestamp) public pure returns (uint256);
```

### epochStartTs


```solidity
function epochStartTs() external view returns (uint256);
```

### resolveEpochStartTs

Timestamp of the start of the next epoch (absolute)


```solidity
function resolveEpochStartTs(uint256 timestamp) public pure returns (uint256);
```

### votingActive


```solidity
function votingActive() external view returns (bool);
```

### resolveVotingActive


```solidity
function resolveVotingActive(uint256 timestamp) public pure returns (bool);
```

### epochVoteStartsIn


```solidity
function epochVoteStartsIn() external view returns (uint256);
```

### resolveEpochVoteStartsIn

Number of seconds until voting starts.

*If voting is active, returns 0.*


```solidity
function resolveEpochVoteStartsIn(uint256 timestamp) public pure returns (uint256);
```

### epochVoteStartTs


```solidity
function epochVoteStartTs() external view returns (uint256);
```

### resolveEpochVoteStartTs

Timestamp of the start of the next voting period (absolute)


```solidity
function resolveEpochVoteStartTs(uint256 timestamp) public pure returns (uint256);
```

### epochVoteEndsIn


```solidity
function epochVoteEndsIn() external view returns (uint256);
```

### resolveEpochVoteEndsIn

Number of seconds until the end of the current voting period (relative)

*If we are outside the voting period, returns 0*


```solidity
function resolveEpochVoteEndsIn(uint256 timestamp) public pure returns (uint256);
```

### epochVoteEndTs


```solidity
function epochVoteEndTs() external view returns (uint256);
```

### resolveEpochVoteEndTs

Timestamp of the end of the current voting period (absolute)


```solidity
function resolveEpochVoteEndTs(uint256 timestamp) public pure returns (uint256);
```

### epochNextCheckpointIn


```solidity
function epochNextCheckpointIn() external view returns (uint256);
```

### resolveEpochNextCheckpointIn

Number of seconds until the next checkpoint interval (relative)

*If exactly at the start of the checkpoint interval, returns 0*


```solidity
function resolveEpochNextCheckpointIn(uint256 timestamp) public pure returns (uint256);
```

### epochNextCheckpointTs


```solidity
function epochNextCheckpointTs() external view returns (uint256);
```

### resolveEpochNextCheckpointTs

Timestamp of the next deposit interval (absolute)


```solidity
function resolveEpochNextCheckpointTs(uint256 timestamp) public pure returns (uint256);
```

### _authorizeUpgrade


```solidity
function _authorizeUpgrade(address) internal override auth(CLOCK_ADMIN_ROLE);
```

### implementation


```solidity
function implementation() external view returns (address);
```

