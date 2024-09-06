// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

library EpochDurationLib {
    uint256 internal constant EPOCH_DURATION = 2 weeks;
    uint256 internal constant DEPOSIT_INTERVAL = 1 weeks;
    uint256 internal constant MAXTIME = 4 * 365 * 86400;

    function epochStart(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            return timestamp - (timestamp % EPOCH_DURATION);
        }
    }

    function epochNext(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            return epochStart(timestamp) + EPOCH_DURATION;
        }
    }

    function epochVoteStart(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            return epochStart(timestamp) + 1 hours;
        }
    }

    function epochVoteEnd(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            return epochStart(timestamp) + (EPOCH_DURATION / 2) - 1 hours;
        }
    }

    /// aligns the timestamp to the next deposit interval
    function epochNextDeposit(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            // Calculate the remaining time within the current interval
            uint256 elapsed = timestamp % DEPOSIT_INTERVAL;

            // Calculate time left until the next interval
            uint256 timeUntilNextInterval = DEPOSIT_INTERVAL - elapsed;

            // Move to the start of the next interval
            return timestamp + timeUntilNextInterval;
        }
    }

    function votingActive(uint256 timestamp) internal pure returns (bool) {
        bool afterVoteStart = timestamp >= epochVoteStart(timestamp);
        bool beforeVoteEnd = timestamp < epochVoteEnd(timestamp);
        return afterVoteStart && beforeVoteEnd;
    }
}
