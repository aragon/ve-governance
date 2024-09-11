/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library EpochDurationLib {
    /// @dev Epoch encompasses a voting and non-voting period
    uint256 internal constant EPOCH_DURATION = 2 weeks;

    /// @dev Checkpoint interval is the time between each voting checkpoint
    uint256 internal constant CHECKPOINT_INTERVAL = 1 weeks;

    /// @dev Voting duration is the time during which votes can be cast
    uint256 internal constant VOTE_DURATION = 1 weeks;

    /// @dev Opens and closes the voting window slightly early to avoid timing attacks
    uint256 internal constant VOTE_WINDOW_OFFSET = 1 hours;

    function currentEpoch(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            return timestamp / EPOCH_DURATION;
        }
    }

    function votingActive(uint256 timestamp) internal pure returns (bool) {
        bool afterVoteStart = timestamp >= epochVoteStartTs(timestamp);
        bool beforeVoteEnd = timestamp < epochVoteEndTs(timestamp);
        return afterVoteStart && beforeVoteEnd;
    }

    function elapsedInEpoch(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            return timestamp % EPOCH_DURATION;
        }
    }

    /// @notice Number of seconds until the start of the next epoch (relative)
    function epochStartsIn(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            uint256 elapsed = elapsedInEpoch(timestamp);
            return (elapsed == 0) ? 0 : EPOCH_DURATION - elapsed;
        }
    }

    /// @notice Timestamp of the start of the next epoch (absolute)
    function epochStartTs(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            return timestamp + epochStartsIn(timestamp);
        }
    }

    /// @notice Number of seconds until voting starts.
    /// @dev If voting is active, returns 0.
    function epochVoteStartsIn(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            uint256 elapsed = elapsedInEpoch(timestamp);

            // if less than the offset has past, return the time until the offset
            if (elapsed < VOTE_WINDOW_OFFSET) {
                return VOTE_WINDOW_OFFSET - elapsed;
            }
            // if voting is active (we are in the voting period) return 0
            else if (elapsed < VOTE_DURATION - VOTE_WINDOW_OFFSET) {
                return 0;
            }
            // else return the time until the next epoch + the offset
            else return epochStartsIn(timestamp) + VOTE_WINDOW_OFFSET;
        }
    }

    /// @notice Timestamp of the start of the next voting period (absolute)
    function epochVoteStartTs(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            return timestamp + epochVoteStartsIn(timestamp);
        }
    }

    /// @notice Number of seconds until the end of the current voting period (relative)
    /// @dev If we are outside the voting period, returns 0
    function epochVoteEndsIn(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            uint256 elapsed = elapsedInEpoch(timestamp);
            uint VOTING_WINDOW = VOTE_DURATION - VOTE_WINDOW_OFFSET;
            // if we are outside the voting period, return 0
            if (elapsed >= VOTING_WINDOW) return 0;
            // if we are in the voting period, return the remaining time
            else return VOTING_WINDOW - elapsed;
        }
    }

    /// @notice Timestamp of the end of the current voting period (absolute)
    function epochVoteEndTs(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            return timestamp + epochVoteEndsIn(timestamp);
        }
    }

    /// @notice Number of seconds until the next checkpoint interval (relative)
    function epochNextCheckpointIn(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            uint256 elapsed = elapsedInEpoch(timestamp);
            // elapsed > deposit interval, then subtract the interval
            if (elapsed > CHECKPOINT_INTERVAL) elapsed -= CHECKPOINT_INTERVAL;
            if (elapsed == 0) return 0;
            else return CHECKPOINT_INTERVAL - elapsed;
        }
    }

    /// @notice Timestamp of the next deposit interval (absolute)
    function epochNextCheckpointTs(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            return timestamp + epochNextCheckpointIn(timestamp);
        }
    }
}
