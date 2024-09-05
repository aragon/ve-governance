// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import "forge-std/Test.sol"; // Assuming you're using Foundry for testing
import "@libs/EpochDurationLib.sol";

contract EpochDurationLibTest is Test {
    using EpochDurationLib for uint256;

    // Helper function to warp time for fuzzing
    function _warpTo(uint64 _warp) internal {
        vm.warp(_warp);
    }

    function testEpochStart(uint64 _warp) public {
        _warpTo(_warp); // Warp to fuzzed timestamp
        uint256 timestamp = block.timestamp;
        uint256 epochStart = EpochDurationLib.epochStart(timestamp);

        // The epoch start should be aligned to the start of the period
        assertEq(epochStart, timestamp - (timestamp % EpochDurationLib.EPOCH_DURATION));
    }

    function testEpochNext(uint64 _warp) public {
        _warpTo(_warp); // Warp to fuzzed timestamp
        uint256 timestamp = block.timestamp;
        uint256 nextEpoch = EpochDurationLib.epochNext(timestamp);

        // Next epoch should start at the current epoch start + 2 weeks
        uint256 expectedNextEpoch = EpochDurationLib.epochStart(timestamp) + EpochDurationLib.EPOCH_DURATION;
        assertEq(nextEpoch, expectedNextEpoch);
    }

    function testEpochVoteStart(uint64 _warp) public {
        _warpTo(_warp); // Warp to fuzzed timestamp
        uint256 timestamp = block.timestamp;
        uint256 voteStart = EpochDurationLib.epochVoteStart(timestamp);

        // Vote start should be the start of the epoch + 1 hour
        uint256 expectedVoteStart = EpochDurationLib.epochStart(timestamp) + 1 hours;
        assertEq(voteStart, expectedVoteStart);
    }

    function testEpochVoteEnd(uint64 _warp) public {
        _warpTo(_warp); // Warp to fuzzed timestamp
        uint256 timestamp = block.timestamp;
        uint256 voteEnd = EpochDurationLib.epochVoteEnd(timestamp);

        // Vote end should be the start of the epoch + half the epoch duration - 1 hour
        uint256 expectedVoteEnd = EpochDurationLib.epochStart(timestamp) +
            (EpochDurationLib.EPOCH_DURATION / 2) -
            1 hours;
        assertEq(voteEnd, expectedVoteEnd);
    }

    function testVotingActiveDuringVotePeriod(uint64 _warp, uint32 _voting) public {
        vm.assume(_voting < 1 weeks - 1 hours); // Ensure voting period is less than a week
        _warpTo(_warp); // Warp to fuzzed timestamp
        uint256 timestamp = block.timestamp;
        uint256 voteStart = EpochDurationLib.epochVoteStart(timestamp);

        // Simulate a time during the voting period
        uint256 voteActiveTimestamp = voteStart + _voting;
        bool isVotingActive = EpochDurationLib.votingActive(voteActiveTimestamp);

        assertTrue(isVotingActive);
    }

    function testVotingActiveOutsideVotePeriod(uint64 _warp) public {
        _warpTo(_warp); // Warp to fuzzed timestamp
        uint256 timestamp = block.timestamp;
        uint256 voteEnd = EpochDurationLib.epochVoteEnd(timestamp);

        // Simulate a time after the voting period has ended
        uint256 afterVoteTimestamp = voteEnd + 1 hours;
        bool isVotingActive = EpochDurationLib.votingActive(afterVoteTimestamp);

        assertFalse(isVotingActive);
    }

    function testVotingNotActiveBeforeVoteStart(uint64 _warp) public {
        _warpTo(_warp); // Warp to fuzzed timestamp
        uint256 timestamp = block.timestamp;
        uint256 voteStart = EpochDurationLib.epochVoteStart(timestamp);

        // Simulate a time before the voting period starts
        uint256 beforeVoteStartTimestamp = voteStart - 1 hours;
        bool isVotingActive = EpochDurationLib.votingActive(beforeVoteStartTimestamp);

        assertFalse(isVotingActive);
    }
}
