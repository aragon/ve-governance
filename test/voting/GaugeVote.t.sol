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

contract TestGaugeVote is GaugeVotingBase {
    uint256[] ids;
    GaugeVote[] votes;

    function setUp() public override {
        super.setUp();
        vm.warp(1); // avoids sentinel value for createdAt
    }

    function testFuzz_cannotVoteOutsideVotingWindow(uint256 time) public {
        // warp to a random time
        vm.warp(time);

        // should now be inactive (we don't test this part herewe have the epoch logic tests)
        vm.assume(!voter.votingActive());

        // try to vote
        vm.expectRevert(VotingInactive.selector);
        voter.vote(0, votes);

        // try to reset
        vm.expectRevert(VotingInactive.selector);
        voter.reset(0);

        // vote multiple
        vm.expectRevert(VotingInactive.selector);
        voter.voteMultiple(ids, votes);
    }
}
