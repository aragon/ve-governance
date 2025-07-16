pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

// aragon contracts
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
import {MockDAOFactory} from "@mocks/osx/MockDAOFactory.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

import "@helpers/OSxHelpers.sol";

import {
    GaugeVotingBase,
    VotingEscrow,
    QuadraticIncreasingEscrow,
    ExitQueue,
    SimpleGaugeVoter,
    SimpleGaugeVoterSetup,
    ISimpleGaugeVoterSetupParams
} from "./GaugeVotingBase.sol";

contract TestGaugeTime is GaugeVotingBase {
    function setUp() public override {
        super.setUp();
        vm.warp(0);
    }

    function nextDeposit() public view returns (uint256) {
        return clock.epochNextCheckpointTs();
    }

    function testEpochTimes() public {
        for (uint i = 0; i < 10; ++i) {
            uint start = block.timestamp;

            // start
            assertEq(clock.elapsedInEpoch(), 0);
            assertEq(voter.epochId(), i);
            assertEq(voter.epochStart(), block.timestamp);
            assertEq(voter.epochVoteStart(), block.timestamp + 1 hours);
            assertEq(voter.epochVoteEnd(), block.timestamp + 1 weeks - 1 hours);
            assertEq(voter.votingActive(), false);
            assertEq(nextDeposit(), block.timestamp + 1 weeks);
            assertEq(clock.epochStartsIn(), 0);

            // +1hr: voting starts
            vm.warp(start + 1 hours);

            assertEq(clock.elapsedInEpoch(), 1 hours);
            assertEq(voter.epochId(), i);
            assertEq(voter.epochStart(), block.timestamp + 2 weeks - 1 hours);
            assertEq(voter.epochVoteStart(), block.timestamp);
            assertEq(voter.epochVoteEnd(), block.timestamp + 1 weeks - 2 hours);
            assertEq(voter.votingActive(), true);
            assertEq(nextDeposit(), block.timestamp + 1 weeks - 1 hours);
            assertEq(clock.epochStartsIn(), 2 weeks - 1 hours);

            // +1 week - 1 hours: voting ends
            vm.warp(start + 1 weeks - 1 hours);

            assertEq(clock.elapsedInEpoch(), 1 weeks - 1 hours);
            assertEq(voter.epochId(), i);
            assertEq(voter.epochStart(), block.timestamp + 1 weeks + 1 hours);
            assertEq(voter.epochVoteStart(), block.timestamp + 1 weeks + 2 hours);
            assertEq(voter.epochVoteEnd(), block.timestamp);
            assertEq(voter.votingActive(), false);
            assertEq(nextDeposit(), block.timestamp + 1 hours);
            assertEq(clock.epochStartsIn(), 1 weeks + 1 hours);

            // +1 week: next deposit opens
            vm.warp(start + 1 weeks);

            assertEq(clock.elapsedInEpoch(), 1 weeks);
            assertEq(voter.epochId(), i);
            assertEq(voter.epochStart(), block.timestamp + 1 weeks);
            assertEq(voter.epochVoteStart(), block.timestamp + 1 weeks + 1 hours);
            assertEq(voter.epochVoteEnd(), block.timestamp);
            assertEq(voter.votingActive(), false);
            assertEq(nextDeposit(), block.timestamp + 1 weeks);
            assertEq(clock.epochStartsIn(), 1 weeks);

            // whole of next week calculates correctly

            vm.warp(start + 1 weeks + 3 days);

            assertEq(clock.elapsedInEpoch(), 1 weeks + 3 days);
            assertEq(voter.epochId(), i);
            assertEq(voter.epochStart(), block.timestamp + 4 days);
            assertEq(voter.epochVoteStart(), block.timestamp + 4 days + 1 hours);
            assertEq(voter.epochVoteEnd(), block.timestamp);
            assertEq(voter.votingActive(), false);
            assertEq(nextDeposit(), block.timestamp + 4 days);
            assertEq(clock.epochStartsIn(), 4 days);

            // +1 week + 2 hours: next epoch starts
            vm.warp(start + 2 weeks);
        }
    }

    function testSeasonTooShort() public {
        uint start = block.timestamp;

        (uint48 seasonStart, uint48 seasonEnd) = clock.currentSeasonTs();
        assertEq(seasonStart, 0);
        assertEq(seasonEnd, 0);
        assertEq(clock.currentSeasonIndex(), 0);

        vm.warp(block.timestamp + 1 hours);

        clock.newSeason();

        assertEq(clock.currentSeasonIndex(), 0);

        // +2 weeks: right on the edge of the min duration
        vm.warp(block.timestamp + 2 weeks - 1 hours - 1);

        assertEq(clock.currentSeasonIndex(), 1);

        // 1 sec too early
        vm.expectRevert(SeasonTooShort.selector);
        clock.newSeason();

        // +1 sec: new season can starts
        vm.warp(block.timestamp + 1);

        clock.newSeason();

        vm.warp(block.timestamp + 1 weeks);

        assertEq(clock.currentSeasonIndex(), 2);

        assertEq(clock.seasonIndexAt(uint48(0)), 0);
        assertEq(clock.seasonIndexAt(uint48(start + 1 hours)), 0);
        assertEq(clock.seasonIndexAt(uint48(start + 1 weeks - 1)), 0);
        assertEq(clock.seasonIndexAt(uint48(start + 1 weeks)), 1);
        assertEq(clock.seasonIndexAt(uint48(start + 3 weeks - 1)), 1);
        assertEq(clock.seasonIndexAt(uint48(start + 3 weeks)), 2);
        assertEq(clock.seasonIndexAt(uint48(block.timestamp)), 2);
    }

    function testSeasonTimes() public {
        uint start = block.timestamp;

        (uint48 seasonStart, uint48 seasonEnd) = clock.seasonTs(0);
        assertEq(seasonStart, 0);
        assertEq(seasonEnd, 0);
        assertEq(clock.currentSeasonIndex(), 0);

        vm.warp(block.timestamp + 1 weeks);

        clock.newSeason();

        assertEq(clock.currentSeasonIndex(), 0);
        (seasonStart, seasonEnd) = clock.seasonTs(0);
        assertEq(seasonStart, 0);
        assertEq(seasonEnd, 2 weeks);

        // +1 week: next season starts
        vm.warp(block.timestamp + 1 weeks);

        assertEq(clock.currentSeasonIndex(), 1);

        (seasonStart, seasonEnd) = clock.seasonTs(1);
        assertEq(seasonStart, 2 weeks);
        assertEq(seasonEnd, 0);

        // +1 week: next season starts
        vm.warp(block.timestamp + 1 weeks);

        clock.newSeason();

        assertEq(clock.currentSeasonIndex(), 1);

        (seasonStart, seasonEnd) = clock.seasonTs(2);
        assertEq(seasonStart, 4 weeks);
        assertEq(seasonEnd, 0);

        vm.warp(block.timestamp + 1 weeks);

        assertEq(clock.seasonIndexAt(uint48(0)), 0);
        assertEq(clock.seasonIndexAt(uint48(start + 2 weeks - 1)), 0);
        assertEq(clock.seasonIndexAt(uint48(start + 2 weeks)), 1);
        assertEq(clock.seasonIndexAt(uint48(start + 4 weeks - 1)), 1);
        assertEq(clock.seasonIndexAt(uint48(start + 4 weeks)), 2);
        assertEq(clock.seasonIndexAt(uint48(block.timestamp)), 2);
    }
}
