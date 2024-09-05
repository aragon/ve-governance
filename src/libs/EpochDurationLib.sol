// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

library EpochDurationLib {
    uint256 internal constant EPOCH_DURATION = 2 weeks;
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

    function votingActive(uint256 timestamp) internal pure returns (bool) {
        bool afterVoteStart = timestamp >= epochVoteStart(timestamp);
        bool beforeVoteEnd = timestamp < epochVoteEnd(timestamp);
        return afterVoteStart && beforeVoteEnd;
    }
}
