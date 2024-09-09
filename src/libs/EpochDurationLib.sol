// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

library EpochDurationLib {
    uint256 internal constant EPOCH_DURATION = 2 weeks;
    uint256 internal constant DEPOSIT_INTERVAL = 1 weeks;
    uint256 internal constant VOTE_DURATION = 1 weeks;
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

    /// @notice Number of seconds until the next deposit interval (relative)
    function epochNextDepositIn(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            uint256 elapsed = elapsedInEpoch(timestamp);
            // elapsed > deposit interval, then subtract the interval
            if (elapsed > DEPOSIT_INTERVAL) elapsed -= DEPOSIT_INTERVAL;
            if (elapsed == 0) return 0;
            else return DEPOSIT_INTERVAL - elapsed;
        }
    }

    /// @notice Timestamp of the next deposit interval (absolute)
    function epochNextDepositTs(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            return timestamp + epochNextDepositIn(timestamp);
        }
    }
}
