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

import {EpochDurationLib} from "@libs/EpochDurationLib.sol";
import {IEscrowCurveUserStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {IWithdrawalQueueErrors} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {IGaugeVote} from "src/voting/ISimpleGaugeVoter.sol";
import {VotingEscrow, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, ISimpleGaugeVoterSetupParams} from "src/voting/SimpleGaugeVoterSetup.sol";

import {GaugeVotingBase} from "./GaugeVotingBase.sol";

contract TestGaugeTime is GaugeVotingBase {
    function setUp() public override {
        super.setUp();
        vm.warp(0);
    }

    function nextDeposit() public view returns (uint256) {
        return EpochDurationLib.epochNextDepositTs(block.timestamp);
    }

    function testEpochTimess() public {
        for (uint i = 0; i < 10; ++i) {
            uint start = block.timestamp;

            // start
            assertEq(voter.epochId(), i);
            assertEq(voter.epochStart(), block.timestamp);
            assertEq(voter.epochVoteStart(), block.timestamp + 1 hours);
            assertEq(voter.epochVoteEnd(), block.timestamp + 1 weeks - 1 hours);
            assertEq(voter.votingActive(), false);
            assertEq(nextDeposit(), block.timestamp);

            // +1hr: voting starts
            vm.warp(start + 1 hours);

            assertEq(voter.epochId(), i);
            assertEq(voter.epochStart(), block.timestamp + 2 weeks - 1 hours);
            assertEq(voter.epochVoteStart(), block.timestamp);
            assertEq(voter.epochVoteEnd(), block.timestamp + 1 weeks - 2 hours);
            assertEq(voter.votingActive(), true);
            assertEq(nextDeposit(), block.timestamp + 1 weeks - 1 hours);

            // +1 week - 1 hours: voting ends
            vm.warp(start + 1 weeks - 1 hours);

            assertEq(voter.epochId(), i);
            assertEq(voter.epochStart(), block.timestamp + 1 weeks + 1 hours);
            assertEq(voter.epochVoteStart(), block.timestamp + 1 weeks + 2 hours);
            assertEq(voter.epochVoteEnd(), block.timestamp);
            assertEq(voter.votingActive(), false);
            assertEq(nextDeposit(), block.timestamp + 1 hours);

            // +1 week: next deposit opens
            vm.warp(start + 1 weeks);
            assertEq(voter.epochId(), i);
            assertEq(voter.epochStart(), block.timestamp + 1 weeks);
            assertEq(voter.epochVoteStart(), block.timestamp + 1 weeks + 1 hours);
            assertEq(voter.epochVoteEnd(), block.timestamp);
            assertEq(voter.votingActive(), false);
            assertEq(nextDeposit(), block.timestamp);

            // whole of next week calculates correctly

            vm.warp(start + 1 weeks + 3 days);

            assertEq(voter.epochId(), i);
            assertEq(voter.epochStart(), block.timestamp + 4 days);
            assertEq(voter.epochVoteStart(), block.timestamp + 4 days + 1 hours);
            assertEq(voter.epochVoteEnd(), block.timestamp);
            assertEq(voter.votingActive(), false);
            assertEq(nextDeposit(), block.timestamp + 4 days);

            // +1 week + 2 hours: next epoch starts
            vm.warp(start + 2 weeks);
        }
    }
}
