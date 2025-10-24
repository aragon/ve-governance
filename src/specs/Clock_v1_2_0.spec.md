# Clock_v1_2_0.sol Specification

## Summary

The Clock_v1_2_0 contract provides a time-based coordination mechanism for the voting escrow system, managing epochs, voting periods, and checkpoint intervals. It establishes a predictable cadence for governance activities that can be shared and queried across contracts, ensuring that time-dependent activities are handled in a consistent manner.

## Mechanism Explanation

The Clock operates on a fixed schedule based on the Unix timestamp

- **Epochs**: periods that encompass both voting and non-voting phases
- **Voting Periods**: Windows within each epoch when votes can be cast
- **Distribution Periods**: Windows when voting is disabled to allow onchain operations to be performed without new votes coming in.
- **Checkpoint Intervals**: New locks are batched and all begin at these fixed intervals: this allows for efficient total supply checkpointing.
- **Vote Window Buffer**: 1-hour safety margin applied to voting period boundaries

**By default:**

- Epochs are 2 weeks
- Voting periods are 1 week
- Distribution periods are 1 week
- Checkpoint intervals are 1 week
- Buffers are 1 hour

While the current clock assumes the above time intervals, theoretically the system could support a different range.

The timing mechanism ensures:

1. Voting starts 1 hour after epoch begins and ends 1 hour before the 1-week mark
2. All timing calculations are deterministic and can be computed for any timestamp
3. Epoch numbers increment sequentially from Unix epoch start
4. Checkpoint intervals align with weekly boundaries for consistent state updates

## Interface

- `resolve` functions will find a given boundary given a timestamp
- `In` functions will return number of seconds until a given boundary
- `Elapsed` functions will return number of seconds since a given boundary
- `Ts` functions give the timestamp of a boundary

```solidity
interface IClockV1_2_0 {
  /// =========== CONSTANT GETTERS ================

  /// @notice Get the duration of an epoch (2 weeks)
  /// @return Duration in seconds
  function epochDuration() external pure returns (uint256);

  /// @notice Get the checkpoint interval duration (1 week)
  /// @return Duration in seconds
  function checkpointInterval() external pure returns (uint256);

  /// @notice Get the voting period duration (1 week)
  /// @return Duration in seconds
  function voteDuration() external pure returns (uint256);

  /// @notice Get the vote window buffer duration (1 hour)
  /// @return Duration in seconds
  function voteWindowBuffer() external pure returns (uint256);

  // Epoch Functions
  /// @notice Get the current epoch number
  /// @return The epoch number at block.timestamp
  function currentEpoch() external view returns (uint256);

  /// @notice Calculate epoch number for a given timestamp
  /// @param timestamp The timestamp to query
  /// @return The epoch number at the given timestamp
  function resolveEpoch(uint256 timestamp) external pure returns (uint256);

  /// @notice Get seconds elapsed in current epoch
  /// @return Seconds since current epoch start
  function elapsedInEpoch() external view returns (uint256);

  /// @notice Calculate seconds elapsed in epoch for a timestamp
  /// @param timestamp The timestamp to query
  /// @return Seconds since epoch start at given timestamp
  function resolveElapsedInEpoch(
    uint256 timestamp
  ) external pure returns (uint256);

  /// @notice Get seconds until next epoch starts
  /// @return Seconds until next epoch (0 if at epoch boundary)
  function epochStartsIn() external view returns (uint256);

  /// @notice Calculate seconds until next epoch for a timestamp
  /// @param timestamp The timestamp to query
  /// @return Seconds until next epoch at given timestamp
  function resolveEpochStartsIn(
    uint256 timestamp
  ) external pure returns (uint256);

  /// @notice Get timestamp of next epoch start
  /// @return Absolute timestamp of next epoch start
  function epochStartTs() external view returns (uint256);

  /// @notice Calculate timestamp of next epoch start for a timestamp
  /// @param timestamp The timestamp to query
  /// @return Absolute timestamp of next epoch start
  function resolveEpochStartTs(
    uint256 timestamp
  ) external pure returns (uint256);

  // Voting Functions
  /// @notice Check if voting is currently active
  /// @return True if within voting window, false otherwise
  function votingActive() external view returns (bool);

  /// @notice Check if voting would be active at a timestamp
  /// @param timestamp The timestamp to query
  /// @return True if within voting window at timestamp
  function resolveVotingActive(uint256 timestamp) external pure returns (bool);

  /// @notice Get seconds until voting starts
  /// @return Seconds until voting (0 if voting active)
  function epochVoteStartsIn() external view returns (uint256);

  /// @notice Calculate seconds until voting starts for a timestamp
  /// @param timestamp The timestamp to query
  /// @return Seconds until voting at timestamp (0 if voting active)
  function resolveEpochVoteStartsIn(
    uint256 timestamp
  ) external pure returns (uint256);

  /// @notice Get timestamp when voting starts
  /// @return Absolute timestamp of next vote start
  function epochVoteStartTs() external view returns (uint256);

  /// @notice Calculate timestamp when voting starts for a timestamp
  /// @param timestamp The timestamp to query
  /// @return Absolute timestamp of next vote start
  function resolveEpochVoteStartTs(
    uint256 timestamp
  ) external pure returns (uint256);

  /// @notice Get seconds until voting ends
  /// @return Seconds until vote end (0 if outside voting period)
  function epochVoteEndsIn() external view returns (uint256);

  /// @notice Calculate seconds until voting ends for a timestamp
  /// @param timestamp The timestamp to query
  /// @return Seconds until vote end (0 if outside voting period)
  function resolveEpochVoteEndsIn(
    uint256 timestamp
  ) external pure returns (uint256);

  /// @notice Get timestamp when voting ends
  /// @return Absolute timestamp of current vote end
  function epochVoteEndTs() external view returns (uint256);

  /// @notice Calculate timestamp when voting ends for a timestamp
  /// @param timestamp The timestamp to query
  /// @return Absolute timestamp of vote end
  function resolveEpochVoteEndTs(
    uint256 timestamp
  ) external pure returns (uint256);

  // Checkpoint Functions
  /// @notice Get seconds until next checkpoint
  /// @return Seconds until next checkpoint interval
  function epochNextCheckpointIn() external view returns (uint256);

  /// @notice Calculate seconds until next checkpoint for a timestamp
  /// @param timestamp The timestamp to query
  /// @return Seconds until next checkpoint (returns interval if at boundary)
  function resolveEpochNextCheckpointIn(
    uint256 timestamp
  ) external pure returns (uint256);

  /// @notice Get timestamp of next checkpoint
  /// @return Absolute timestamp of next checkpoint
  function epochNextCheckpointTs() external view returns (uint256);

  /// @notice Calculate timestamp of next checkpoint for a timestamp
  /// @param timestamp The timestamp to query
  /// @return Absolute timestamp of next checkpoint
  function resolveEpochNextCheckpointTs(
    uint256 timestamp
  ) external pure returns (uint256);

  /// @notice Get seconds since previous checkpoint
  /// @return Seconds elapsed since last checkpoint
  function epochPrevCheckpointElapsed() external view returns (uint256);

  /// @notice Calculate seconds since previous checkpoint for a timestamp
  /// @param timestamp The timestamp to query
  /// @return Seconds elapsed (0 if at checkpoint boundary)
  function resolveEpochPrevCheckpointElapsed(
    uint256 timestamp
  ) external pure returns (uint256);

  /// @notice Get timestamp of previous checkpoint
  /// @return Absolute timestamp of previous checkpoint
  function epochPrevCheckpointTs() external view returns (uint256);

  /// @notice Calculate timestamp of previous checkpoint for a timestamp
  /// @param timestamp The timestamp to query
  /// @return Absolute timestamp of previous checkpoint
  function resolveEpochPrevCheckpointTs(
    uint256 timestamp
  ) external pure returns (uint256);
}
```
