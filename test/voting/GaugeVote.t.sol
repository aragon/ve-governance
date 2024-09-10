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

    address owner = address(0x420);
    uint256 lockDeposit = 1000 ether;
    uint256 tokenId;
    address gauge = address(0x420);

    function setUp() public override {
        super.setUp();

        // reset clock
        vm.warp(0);

        // means we have voting power
        curve.setWarmupPeriod(0);

        // mint underlying and stake
        token.mint(owner, lockDeposit);
        vm.startPrank(owner);
        {
            token.approve(address(escrow), lockDeposit);
            tokenId = escrow.createLock(lockDeposit);
        }
        vm.stopPrank();

        // warp to an active window
        vm.warp(1 hours);
        assertGt(escrow.votingPower(tokenId), 0);
        assertTrue(voter.votingActive(), "voting should be active");

        // create a gauge
        voter.createGauge(gauge, "metadata");
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

    // can't vote if you don't own the token
    function testCannotVoteIfYouDontOwnTheToken() public {
        // try to vote as this address (not the holder)
        vm.expectRevert(NotApprovedOrOwner.selector);
        voter.vote(tokenId, votes);
    }

    function testCannotResetIFYouDontOwnTheToken() public {
        // make the vote
        votes.push(GaugeVote(lockDeposit, gauge));
        vm.prank(owner);
        voter.vote(tokenId, votes);

        // try to reset as this address (not the holder)
        vm.expectRevert(NotApprovedOrOwner.selector);
        voter.reset(tokenId);
    }

    // can't vote if you have zero voting power
    function testCannotVoteIfYouHaveZeroVotingPower() public {
        curve.setWarmupPeriod(1000 weeks);

        // create a second lock
        token.mint(owner, lockDeposit);
        vm.startPrank(owner);
        {
            token.approve(address(escrow), lockDeposit);
            uint256 newTokenId = escrow.createLock(lockDeposit);
            assertEq(escrow.votingPower(newTokenId), 0);
            vm.expectRevert(NoVotingPower.selector);
            voter.vote(newTokenId, votes);
        }
        vm.stopPrank();
    }

    function testCannotVoteWithNoVotes() public {
        // try to vote with no votes
        vm.expectRevert(NoVotes.selector);
        vm.prank(owner);
        voter.vote(tokenId, votes);
    }

    function testCannotVoteForInactiveGauge() public {
        // deactivate the gauge
        voter.deactivateGauge(gauge);

        // create the vote
        votes.push(GaugeVote(lockDeposit, gauge));

        // try to vote
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(GaugeInactive.selector, gauge));
        voter.vote(tokenId, votes);
    }

    function testCannotVoteForNonExistentGauge() public {
        address notAGauge = address(0x69);
        // create the vote
        votes.push(GaugeVote(lockDeposit, notAGauge));

        // try to vote
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(GaugeDoesNotExist.selector, notAGauge));
        voter.vote(tokenId, votes);
    }

    function testCannotVoteWithZeroVotes() public {
        // create the vote
        votes.push(GaugeVote(0, gauge));

        // try to vote
        vm.prank(owner);
        vm.expectRevert(NoVotes.selector);
        voter.vote(tokenId, votes);
    }

    function testCannotVoteWithVotesSoSmallTheyRoundToZero() public {
        // need to have very low voting power or very high weights

        // make a second gauge
        address gauge2 = address(0x69);
        voter.createGauge(gauge2, "metadata");

        // create a new lock w. 1 wei
        token.mint(owner, 1);
        uint256 newTokenId;
        vm.startPrank(owner);
        {
            token.approve(address(escrow), 1);
            newTokenId = escrow.createLock(1);
            // warp 2 weeks
            vm.warp(block.timestamp + 2 weeks);
            assertEq(escrow.votingPower(newTokenId), 1);

            // make the vote: split the 1 wei into 2 votes
            votes.push(GaugeVote(1, gauge));
            votes.push(GaugeVote(1, gauge2));

            // try to vote
            vm.expectRevert(NoVotes.selector);
            voter.vote(newTokenId, votes);
        }
        vm.stopPrank();
    }

    function cannotDoubleVote() public {
        // create the vote
        votes.push(GaugeVote(lockDeposit, gauge));
        votes.push(GaugeVote(lockDeposit, gauge));

        vm.expectRevert(DoubleVote.selector);
        voter.vote(tokenId, votes);
    }

    function testSingleVote(uint128 _weight) public {
        vm.assume(_weight > 0);

        // create the vote
        votes.push(GaugeVote(_weight, gauge));

        uint votingPower = escrow.votingPower(tokenId);

        // vote
        vm.startPrank(owner);
        {
            vm.expectEmit(true, true, true, true);
            emit Voted({
                voter: owner,
                gauge: gauge,
                epoch: voter.epochId(),
                tokenId: tokenId,
                votingPower: votingPower,
                totalVotingPower: votingPower,
                timestamp: block.timestamp
            });
            voter.vote(tokenId, votes);
        }
        vm.stopPrank();

        // check the vote
        assertEq(voter.isVoting(tokenId), true);
        assertEq(voter.gaugesVotedFor(tokenId).length, 1);
        assertEq(voter.gaugesVotedFor(tokenId)[0], gauge);
        assertEq(voter.votes(tokenId, gauge), votingPower);
        assertEq(voter.usedVotingPower(tokenId), votingPower);

        // global state
        assertEq(voter.totalVotingPowerCast(), votingPower);
        assertEq(voter.gaugeVotes(gauge), votingPower);
    }

    // 32 bit integers mean we don't round to zero
    function testFuzz_vote(uint32 _weight0, uint32 _weight1) public {
        vm.assume(_weight0 > 0 && _weight1 > 0);
        // setup 2 gauges
        address newGauge = address(0x69);
        voter.createGauge(newGauge, "metadata");

        // no need to create a random lock as it's already a large complex number
        // do a random allocation of weights

        // create the vote
        votes.push(GaugeVote(_weight0, gauge));
        votes.push(GaugeVote(_weight1, newGauge));

        uint votingPower = escrow.votingPower(tokenId);

        vm.startPrank(owner);
        {
            voter.vote(tokenId, votes);
        }
        vm.stopPrank();

        // overflow math
        uint weight0256 = uint256(_weight0);
        uint weight1256 = uint256(_weight1);
        uint expectedVotesForGauge = (weight0256 * votingPower) / (weight0256 + weight1256);
        uint expectedVotesForNewGauge = (weight1256 * votingPower) / (weight0256 + weight1256);

        uint expectedTotalVotes = expectedVotesForGauge + expectedVotesForNewGauge;
        assertApproxEqAbs(voter.usedVotingPower(tokenId), expectedTotalVotes, 1);

        // check the vote
        assertEq(voter.isVoting(tokenId), true);
        assertEq(voter.gaugesVotedFor(tokenId).length, 2);
        assertEq(voter.gaugesVotedFor(tokenId)[0], gauge);
        assertEq(voter.gaugesVotedFor(tokenId)[1], newGauge);
        assertEq(voter.votes(tokenId, gauge), expectedVotesForGauge);
        assertEq(voter.votes(tokenId, newGauge), expectedVotesForNewGauge);
        assertEq(voter.usedVotingPower(tokenId), expectedTotalVotes);

        // global state
        assertEq(voter.totalVotingPowerCast(), expectedTotalVotes);
        assertEq(voter.gaugeVotes(gauge), expectedVotesForGauge);
        assertEq(voter.gaugeVotes(newGauge), expectedVotesForNewGauge);
    }

    function testManualResets() public {
        // vote
        votes.push(GaugeVote(1000, gauge));

        uint votingPower = escrow.votingPower(tokenId);

        // vote then reset
        vm.startPrank(owner);
        {
            voter.vote(tokenId, votes);

            // reset
            vm.expectEmit(true, true, true, true);
            emit Reset({
                voter: owner,
                gauge: gauge,
                epoch: voter.epochId(),
                tokenId: tokenId,
                votingPower: votingPower,
                totalVotingPower: 0,
                timestamp: block.timestamp
            });
            voter.reset(tokenId);
        }
        vm.stopPrank();

        // check the vote
        assertEq(voter.isVoting(tokenId), false);
        assertEq(voter.gaugesVotedFor(tokenId).length, 0);
        assertEq(voter.votes(tokenId, gauge), 0);
        assertEq(voter.usedVotingPower(tokenId), 0);

        // global state
        assertEq(voter.totalVotingPowerCast(), 0);
        assertEq(voter.gaugeVotes(gauge), 0);
    }

    function testVotingResets() public {
        // create a second gauge
        address gauge2 = address(0x69);
        voter.createGauge(gauge2, "metadata");

        votes.push(GaugeVote(25, gauge));
        votes.push(GaugeVote(75, gauge2));

        // vote then revote
        vm.startPrank(owner);
        {
            voter.vote(tokenId, votes);

            // change vote
            GaugeVote[] memory newVotes = new GaugeVote[](1);
            newVotes[0] = GaugeVote(100, gauge);

            // more voting power
            vm.warp(block.timestamp + 1 days);

            // vote again clears the votes
            voter.vote(tokenId, newVotes);
        }
        vm.stopPrank();

        uint newVotingPower = escrow.votingPower(tokenId);

        // check the vote
        assertEq(voter.isVoting(tokenId), true);
        assertEq(voter.gaugesVotedFor(tokenId).length, 1);
        assertEq(voter.gaugesVotedFor(tokenId)[0], gauge);
        assertEq(voter.votes(tokenId, gauge), newVotingPower);
        assertEq(voter.usedVotingPower(tokenId), newVotingPower);

        // global state
        assertEq(voter.totalVotingPowerCast(), newVotingPower);
        assertEq(voter.gaugeVotes(gauge), newVotingPower);
    }

    function testCanVoteForMultiple() public {
        uint secondDeposit = 500 ether;

        // create a second gauge
        address gauge2 = address(0x69);
        voter.createGauge(gauge2, "metadata");

        // create a second lock
        token.mint(owner, secondDeposit);
        uint tokenIdNew;
        vm.startPrank(owner);

        {
            token.approve(address(escrow), secondDeposit);
            tokenIdNew = escrow.createLock(secondDeposit);
        }
        vm.stopPrank();

        // jump 2 weeks so that we have voting power
        vm.warp(block.timestamp + 2 weeks);

        assertGt(escrow.votingPower(tokenIdNew), 0);

        // get all the token Ids for the user
        uint256[] memory tokens = escrow.ownedTokens(owner);

        vm.prank(owner);
        escrow.setApprovalForAll(address(voter), true);

        uint vp0 = escrow.votingPower(tokens[0]);
        uint vp1 = escrow.votingPower(tokens[1]);

        uint totalVotingPower = escrow.votingPowerForAccount(owner);
        assertEq(totalVotingPower, vp0 + vp1);

        // vote multiple
        votes.push(GaugeVote(50, gauge));
        votes.push(GaugeVote(100, gauge2));

        vm.prank(owner);
        voter.voteMultiple(tokens, votes);

        // we expect the vote for the first token to be 50/150 of the total voting power
        // and the second to be 100/150 of the total voting power

        uint expectedVotesForGauge = (50 * vp0) / (50 + 100);
        uint expectedVotesForGauge2 = (100 * vp1) / (50 + 100);

        // check the vote
        assertEq(voter.isVoting(tokenId), true);
        assertEq(voter.gaugesVotedFor(tokenId).length, 2);
        assertEq(voter.gaugesVotedFor(tokenId)[0], gauge);
        assertEq(voter.gaugesVotedFor(tokenId)[1], gauge2);
        assertEq(voter.votes(tokenId, gauge), expectedVotesForGauge);
        assertEq(voter.votes(tokenIdNew, gauge2), expectedVotesForGauge2);
    }
}
