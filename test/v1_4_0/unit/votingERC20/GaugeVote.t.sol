pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

// aragon contracts
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/src/MultisigSetup.sol";

import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
import {MockDAOFactory} from "@mocks/osx/MockDAOFactory.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

import "@helpers/OSxHelpers.sol";

import {GaugeVotingBase} from "./GaugeVotingBase.sol";

contract TestGaugeVoteWithERC20 is GaugeVotingBase {
    uint256[] ids;
    GaugeVote[] votes;

    address owner = address(0x420);
    uint256 lockDeposit = 1000 ether;
    uint256 tokenId;
    address gauge = address(0x777);

    uint time;

    function _increaseTime(uint _by) internal {
        time += _by;
        vm.warp(time);
    }

    function setUp() public override {
        super.setUp();

        // reset clock
        vm.warp(0);
        time = block.timestamp;

        // mint underlying
        votingToken.mint(owner, lockDeposit);

        vm.startPrank(owner);
        {
            votingToken.delegate(owner);
        }
        vm.stopPrank();

        // activate cp & warp to an active window
        _increaseTime(2 weeks + 1 hours + 1);

        assertEq(votingToken.getVotes(owner), lockDeposit);
        assertTrue(voter.votingActive(), "voting should be active");

        // create a gauge
        voter.createGauge(gauge, "metadata");
    }

    function testFuzz_cannotVoteOutsideVotingWindow(uint256 _time) public {
        // warp to a random time
        vm.warp(_time);

        // should now be inactive (we don't test this part herewe have the epoch logic tests)
        vm.assume(!voter.votingActive());

        // try to vote
        vm.expectRevert(VotingInactive.selector);
        voter.vote(votes);
    }

    function testFuzz_cannotResetInDistributionPeriod() public {
        // create the vote
        votes.push(GaugeVote(1, gauge));

        // vote
        vm.startPrank(owner);
        {
            voter.vote(votes);
        }
        vm.stopPrank();

        // check the vote
        assertEq(voter.isVoting(owner), true);

        // warp to the next distribution period
        _increaseTime(1 weeks);
        vm.assume(!voter.votingActive());

        // try to reset
        vm.startPrank(owner);
        {
            vm.expectRevert(VotingInactive.selector);
            voter.reset();
        }
        vm.stopPrank();
    }

    // can't vote if you have zero voting power
    function testCannotVoteIfYouHaveZeroVotingPower() public {
        address person = address(0x69);

        vm.startPrank(person);
        {
            assertEq(votingToken.getVotes(person), 0);
            vm.expectRevert(NoVotingPower.selector);
            voter.vote(votes);
        }
        vm.stopPrank();
    }

    function testCannotVoteWithNoVotes() public {
        // try to vote with no votes
        vm.expectRevert(NoVotes.selector);
        vm.prank(owner);
        voter.vote(votes);
    }

    function testCannotVoteForInactiveGauge() public {
        // deactivate the gauge
        voter.deactivateGauge(gauge);

        // create the vote
        votes.push(GaugeVote(lockDeposit, gauge));

        // try to vote
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(GaugeInactive.selector, gauge));
        voter.vote(votes);
    }

    function testCannotVoteForNonExistentGauge() public {
        address notAGauge = address(0x69);
        // create the vote
        votes.push(GaugeVote(lockDeposit, notAGauge));

        // try to vote
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(GaugeDoesNotExist.selector, notAGauge));
        voter.vote(votes);
    }

    function testCannotVoteWithZeroVotes() public {
        // create the vote
        votes.push(GaugeVote(0, gauge));

        // try to vote
        vm.prank(owner);
        vm.expectRevert(NoVotes.selector);
        voter.vote(votes);
    }

    function cannotDoubleVote() public {
        // create the vote
        votes.push(GaugeVote(lockDeposit, gauge));
        votes.push(GaugeVote(lockDeposit, gauge));

        vm.expectRevert(DoubleVote.selector);
        voter.vote(votes);
    }

    function testSingleVote(uint128 _weight) public {
        vm.assume(_weight > 0);

        // create the vote
        votes.push(GaugeVote(_weight, gauge));

        uint votingPower = votingToken.getVotes(owner);

        // vote
        vm.startPrank(owner);
        {
            vm.expectEmit(true, true, true, true);
            emit Voted({
                voter: owner,
                gauge: gauge,
                epoch: voter.epochId(),
                votingPowerCastForGauge: votingPower,
                totalVotingPowerInGauge: votingPower,
                totalVotingPowerInContract: votingPower,
                timestamp: block.timestamp
            });
            voter.vote(votes);
        }
        vm.stopPrank();

        // check the vote
        assertEq(voter.isVoting(owner), true);
        assertEq(voter.gaugesVotedFor(owner).length, 1);
        assertEq(voter.gaugesVotedFor(owner)[0], gauge);
        assertEq(voter.votes(owner, gauge), votingPower);
        assertEq(voter.usedVotingPower(owner), votingPower);

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

        uint votingPower = votingToken.getVotes(owner);

        vm.startPrank(owner);
        {
            voter.vote(votes);
        }
        vm.stopPrank();

        // overflow math
        uint weight0256 = uint256(_weight0);
        uint weight1256 = uint256(_weight1);
        uint expectedVotesForGauge = (weight0256 * votingPower) / (weight0256 + weight1256);
        uint expectedVotesForNewGauge = (weight1256 * votingPower) / (weight0256 + weight1256);

        uint expectedTotalVotes = expectedVotesForGauge + expectedVotesForNewGauge;
        assertApproxEqAbs(voter.usedVotingPower(owner), expectedTotalVotes, 2);

        // check the vote
        assertEq(voter.isVoting(owner), true);
        assertEq(voter.gaugesVotedFor(owner).length, 2);
        assertEq(voter.gaugesVotedFor(owner)[0], gauge);
        assertEq(voter.gaugesVotedFor(owner)[1], newGauge);
        assertApproxEqAbs(voter.votes(owner, gauge), expectedVotesForGauge, 2);
        assertApproxEqAbs(voter.votes(owner, newGauge), expectedVotesForNewGauge, 2);
        assertApproxEqAbs(voter.usedVotingPower(owner), expectedTotalVotes, 2);

        // global state
        assertApproxEqAbs(voter.totalVotingPowerCast(), expectedTotalVotes, 2);
        assertApproxEqAbs(voter.gaugeVotes(gauge), expectedVotesForGauge, 2);
        assertApproxEqAbs(voter.gaugeVotes(newGauge), expectedVotesForNewGauge, 2);
    }

    function testManualResets() public {
        // vote
        votes.push(GaugeVote(1000, gauge));

        uint votingPower = votingToken.getVotes(owner);

        // vote then reset
        vm.startPrank(owner);
        {
            voter.vote(votes);

            // reset
            vm.expectEmit(true, true, true, true);
            emit Reset({
                voter: owner,
                gauge: gauge,
                epoch: voter.epochId(),
                votingPowerRemovedFromGauge: votingPower,
                totalVotingPowerInGauge: 0,
                totalVotingPowerInContract: 0,
                timestamp: block.timestamp
            });
            voter.reset();
        }
        vm.stopPrank();

        // check the vote
        assertEq(voter.isVoting(owner), false);
        assertEq(voter.gaugesVotedFor(owner).length, 0);
        assertEq(voter.votes(owner, gauge), 0);
        assertEq(voter.usedVotingPower(owner), 0);

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
            voter.vote(votes);

            // change vote
            GaugeVote[] memory newVotes = new GaugeVote[](1);
            newVotes[0] = GaugeVote(100, gauge);

            // more voting power
            vm.warp(block.timestamp + 1 days);

            // vote again clears the votes
            voter.vote(newVotes);
        }
        vm.stopPrank();

        uint newVotingPower = votingToken.getVotes(owner);

        // check the vote
        assertEq(voter.isVoting(owner), true);
        assertEq(voter.gaugesVotedFor(owner).length, 1);
        assertEq(voter.gaugesVotedFor(owner)[0], gauge);
        assertEq(voter.votes(owner, gauge), newVotingPower);
        assertEq(voter.usedVotingPower(owner), newVotingPower);

        // global state
        assertEq(voter.totalVotingPowerCast(), newVotingPower);
        assertEq(voter.gaugeVotes(gauge), newVotingPower);
    }

    function testCanVoteForMultiple() public {
        // create a second gauge
        address gauge2 = address(0x69);
        voter.createGauge(gauge2, "metadata");

        // jump 2 weeks so that we have voting power
        vm.warp(block.timestamp + 2 weeks);

        uint votingPower = votingToken.getVotes(owner);
        assertGt(votingPower, 0);

        // vote multiple
        votes.push(GaugeVote(50, gauge));
        votes.push(GaugeVote(100, gauge2));

        vm.prank(owner);
        voter.vote(votes);

        // we expect the vote for the first token to be 50/150 of the total voting power
        // and the second to be 100/150 of the total voting power

        uint expectedVotesForGauge = (50 * votingPower) / (50 + 100);
        uint expectedVotesForGauge2 = (100 * votingPower) / (50 + 100);

        // check the vote
        assertEq(voter.isVoting(owner), true);
        assertEq(voter.gaugesVotedFor(owner).length, 2);
        assertEq(voter.gaugesVotedFor(owner)[0], gauge);
        assertEq(voter.gaugesVotedFor(owner)[1], gauge2);
        assertApproxEqAbs(voter.votes(owner, gauge), expectedVotesForGauge, 2);
        assertApproxEqAbs(voter.votes(owner, gauge2), expectedVotesForGauge2, 2);
        assertApproxEqAbs(
            voter.usedVotingPower(owner),
            voter.votes(owner, gauge) + voter.votes(owner, gauge2),
            2
        );
    }

    // test the event logs: person A votes, person B votes => B's event correctly distinguishes between the two
    // then A resets, leaving B's vote in place from the logs
    function test2PeopleVoteEvents() public {
        address personA = address(0xc0ffee);
        address personB = address(0xbabe);

        address gauge2 = address(0x69);
        voter.createGauge(gauge2, "metadata");

        votes.push(GaugeVote(25, gauge));
        votes.push(GaugeVote(75, gauge2));

        // create lock for A
        votingToken.mint(personA, 1000 ether);
        vm.startPrank(personA);
        {
            votingToken.delegate(personA);
        }
        vm.stopPrank();

        // create lock for B
        votingToken.mint(personB, 1000 ether);
        vm.startPrank(personB);
        {
            votingToken.delegate(personB);
        }
        vm.stopPrank();

        // jump 2 weeks so that we have voting power
        vm.warp(block.timestamp + 2 weeks);

        uint aVotingPower = votingToken.getVotes(personA);
        uint bVotingPower = votingToken.getVotes(personB);

        assertGt(aVotingPower, 0);
        assertGt(bVotingPower, 0);

        // vote for A then vote for B
        vm.prank(personA);
        voter.vote(votes);

        uint256 expectedBVotingPowerGauge0 = (75 * bVotingPower) / 100;
        uint256 expectedAVotingPowerGauge0 = (25 * aVotingPower) / 100;
        uint256 expectedBVotingPowerGauge1 = (25 * bVotingPower) / 100;
        uint256 expectedAVotingPowerGauge1 = (75 * aVotingPower) / 100;

        // flip the votes
        votes[0] = GaugeVote(75, gauge);
        votes[1] = GaugeVote(25, gauge2);

        uint epoch = voter.epochId();
        // same vote for b
        vm.startPrank(personB);
        {
            vm.expectEmit(true, true, true, true);
            emit Voted({
                voter: personB,
                gauge: gauge,
                epoch: epoch,
                votingPowerCastForGauge: expectedBVotingPowerGauge0,
                totalVotingPowerInGauge: expectedBVotingPowerGauge0 + expectedAVotingPowerGauge0,
                totalVotingPowerInContract: expectedBVotingPowerGauge0 + aVotingPower,
                timestamp: block.timestamp
            });
            vm.expectEmit(true, true, true, true);
            emit Voted({
                voter: personB,
                gauge: gauge2,
                epoch: epoch,
                votingPowerCastForGauge: expectedBVotingPowerGauge1,
                totalVotingPowerInGauge: expectedBVotingPowerGauge1 + expectedAVotingPowerGauge1,
                totalVotingPowerInContract: bVotingPower + aVotingPower,
                timestamp: block.timestamp
            });

            voter.vote(votes);
        }
        vm.stopPrank();

        // go back and reset A to check
        vm.startPrank(personA);
        {
            vm.expectEmit(true, true, true, true);
            emit Reset({
                voter: personA,
                gauge: gauge,
                epoch: epoch,
                votingPowerRemovedFromGauge: expectedAVotingPowerGauge0,
                totalVotingPowerInGauge: expectedBVotingPowerGauge0,
                totalVotingPowerInContract: bVotingPower + expectedAVotingPowerGauge1,
                timestamp: block.timestamp
            });

            vm.expectEmit(true, true, true, true);
            emit Reset({
                voter: personA,
                gauge: gauge2,
                epoch: epoch,
                votingPowerRemovedFromGauge: expectedAVotingPowerGauge1,
                totalVotingPowerInGauge: expectedBVotingPowerGauge1,
                totalVotingPowerInContract: bVotingPower,
                timestamp: block.timestamp
            });

            voter.reset();
        }
        vm.stopPrank();
    }
}
