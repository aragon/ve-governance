pragma solidity ^0.8.17;

import {Base, EscrowIVotesAdapterA} from "./Base.sol";
import {EscrowIVotesAdapter, CurveConstantLib} from "../../versions.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {console2 as console} from "forge-std/console2.sol";

contract TestVPAndCheckpoints is Base {
    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                      GlobalPoints and SlopeChanges
    //////////////////////////////////////////////////////////////*/

    function test_DelegateSingleToken() public {
        dg.setDelegateAddress(alice);

        uint256 start = weekStartTs(block.timestamp);
        uint256 amount = getFlooredAmount(10e18);

        _mockLocked(singleId[0], amount, start);
        dg.delegate(singleId);

        vm.warp(block.timestamp + 1 weeks);

        assertGlobalPoint(
            alice,
            1,
            biasFP(amount, 0),
            slopeFP(amount),
            start
        );
        assertSlopeChange(alice, start + maxTime, amount);
    }

    function test_DelegateMultipleTokens() public {
        dg.setDelegateAddress(alice);

        uint256 amount1 = getFlooredAmount(10e18);
        uint256 amount2 = getFlooredAmount(25e18);
        uint256 start = weekStartTs(block.timestamp);

        _mockLocked(multiIds[0], amount1, start);
        _mockLocked(multiIds[1], amount2, start);

        dg.delegate(multiIds);

        vm.warp(block.timestamp + 1 weeks);

        assertGlobalPoint(
            alice,
            1,
            biasFP(amount1 + amount2, 0),
            slopeFP(amount1 + amount2),
            start
        );
        assertSlopeChange(alice, start + maxTime, amount1 + amount2);
    }

    function test_DelegateSecondTokenAtLaterTimestamp() public {
        dg.setDelegateAddress(alice);

        // Delegate first token
        uint256 amount1 = getFlooredAmount(10e18);
        uint256 start1 = weekStartTs(block.timestamp);
        _mockLocked(singleId[0], amount1, start1);

        dg.delegate(singleId);

        // warp time to future so another token
        // gets delegated at a later timestamp
        vm.warp(block.timestamp + 3 weeks);

        // Delegate second token
        uint256 amount2 = getFlooredAmount(25e18);
        uint256 start2 = weekStartTs(block.timestamp);
        singleId[0] = 2;
        _mockLocked(singleId[0], uint208(amount2), start2);

        dg.delegate(singleId);

        vm.warp(block.timestamp + 1 weeks);

        // start asserting
        assertSlopeChange(alice, start1 + maxTime, amount1);
        assertSlopeChange(alice, start2 + maxTime, amount2);

        // asserts previous global point.
        GlobalPoint memory p = dg.pointHistory_(alice, 1);
        assertEq(p.bias, biasFP(amount1, 0));
        assertEq(p.slope, slopeFP(amount1));
        assertEq(p.writtenTs, start1);

        // asserts latest global point.
        assertGlobalPoint(
            alice,
            2,
            biasFP(amount1, start2 - start1) + biasFP(amount2, 0),
            slopeFP(amount2) + slopeFP(amount1),
            start2
        );
    }

    function test_UndelegateShouldDecreaseSlopeAndBias() public {
        dg.setDelegateAddress(alice);

        uint256 amount1 = getFlooredAmount(10e18);
        uint256 start1 = weekStartTs(block.timestamp);
        _mockLocked(singleId[0], amount1, start1);

        dg.delegate(singleId);

        dg.undelegate(singleId);

        vm.warp(block.timestamp + 1 weeks);

        // asserts latest global point.
        assertGlobalPoint(alice, 1, 0, 0, start1);
    }

    /*//////////////////////////////////////////////////////////////
                     getPastVotes, getVotes
    //////////////////////////////////////////////////////////////*/

    function test_VotingPowersSingleToken() public {
        dg.setDelegateAddress(alice);

        uint256 amount = getFlooredAmount(10e18);
        uint256 start = weekStartTs(block.timestamp);
        _mockLocked(singleId[0], getFlooredAmount(10e18), start);
        dg.delegate(singleId);

        vm.warp(block.timestamp + 1 weeks);

        uint256 expectedVP = bias(amount, block.timestamp - start);

        assertEq(dg.getPastVotes(alice, block.timestamp - 1 weeks - 1), 0);

        assertEq(dg.getPastVotes(alice, block.timestamp), expectedVP);
        assertEq(dg.getVotes(alice), expectedVP);

        dg.undelegate(singleId);

        vm.warp(block.timestamp + 1 weeks);

        assertEq(dg.getPastVotes(alice, block.timestamp), 0);
        assertEq(dg.getVotes(alice), 0);
    }

    function test_VotingPowersMultipleTokens() public {
        dg.setDelegateAddress(alice);

        uint256 amount1 = getFlooredAmount(10e18);
        uint256 amount2 = getFlooredAmount(25e18);
        uint256 start = weekStartTs(block.timestamp);
        _mockLocked(multiIds[0], amount1, start);
        _mockLocked(multiIds[1], amount2, start);
        dg.delegate(multiIds);

        vm.warp(block.timestamp + 1 weeks);

        uint256 expectedVPToken1 = bias(amount1, block.timestamp - start);
        uint256 expectedVPToken2 = bias(amount2, block.timestamp - start);
        uint256 total = expectedVPToken1 + expectedVPToken2;
        assertEq(dg.getPastVotes(alice, block.timestamp - 1 weeks - 1), 0);

        assertEq(dg.getPastVotes(alice, block.timestamp), total);
        assertApproxEqAbs(dg.getVotes(alice), total, 1e11);

        dg.undelegate(getIds(multiIds[1]));

        vm.warp(block.timestamp + 1 weeks);

        uint256 newExpectedVPToken1 = bias(amount1, block.timestamp - start);
        assertEq(dg.getPastVotes(alice, block.timestamp), newExpectedVPToken1);
        assertApproxEqAbs(dg.getVotes(alice), newExpectedVPToken1, 1e11);
    }

    /*//////////////////////////////////////////////////////////////
                     Transition Checkpoints
    //////////////////////////////////////////////////////////////*/

    function test_shouldRevertIfZeroTransition() public {
        vm.expectRevert(ZeroTransition.selector);
        dg.checkpointTransition(alice, 0);
    }
    
    function test_shouldRevertIfPaused() public {
        dg.pause();

        vm.expectRevert("Pausable: paused");

        // transition checkpoints
        dg.checkpointTransition(alice, 3);
    }

    function test_transitionLessThanCurrentTimestamp() public {
        dg.setDelegateAddress(alice);

        uint256 amount = getFlooredAmount(10e18);
        uint256 start = weekStartTs(block.timestamp);

        _mockLocked(singleId[0], amount, start);
        dg.delegate(singleId);

        uint256 delegateTs = block.timestamp;

        vm.warp(delegateTs + maxTime + 4 weeks);

        // transition checkpoints
        dg.checkpointTransition(alice, 3);

        // TODO: GIORGI problem here
        uint256 expectedTs = start + 3 weeks;

        assertGlobalPoint(
            alice,
            2,
            biasFP(amount, expectedTs - start),
            slopeFP(amount),
            expectedTs
        );
    }

    function test_transitionBiggerThanCurrentTimestamp() public {
        dg.setDelegateAddress(alice);

        uint256 amount = getFlooredAmount(10e18);
        uint256 start = weekStartTs(block.timestamp);

        _mockLocked(singleId[0], amount, start);
        vm.warp(block.timestamp + 1 weeks);

        dg.delegate(singleId);

        uint256 delegateTs = weekStartTs(block.timestamp);

        vm.warp(delegateTs + maxTime + 4 weeks);

        // transition checkpoints
        dg.checkpointTransition(
            alice,
            (block.timestamp - delegateTs + 3 weeks) / checkpointInterval
        );

        uint256 expectedTs = block.timestamp;

        assertGlobalPoint(alice, 2, 0, 0, expectedTs);
    }

    /*//////////////////////////////////////////////////////////////
                     Stale Delegate Checkpoints
    //////////////////////////////////////////////////////////////*/

    function test_StaleDelegate_NewLockDatedAtNextCheckpoint() public {
        dg.setDelegateAddress(alice);

        uint256 permanentId = 1;
        uint256 oldTimedId = 2;
        uint256 newTimedId = 3;
        uint256 permanentAmount = getFlooredAmount(10e18);
        uint256 oldTimedAmount = getFlooredAmount(20e18);
        uint256 newTimedAmount = getFlooredAmount(30e18);
        uint256 staleWeeks = 260;
        uint256 midWeekOffset = 1 days;
        uint256 weeksAfterDelegation = 10;
        _mockVotingPower(newTimedId, 1);

        // Week 0: alice holds a permanent lock and a timed lock that fully decays after maxTime.
        uint256 firstStart = weekStartTs(block.timestamp);
        vm.warp(firstStart);
        _mockLocked(permanentId, permanentAmount, 0);
        _mockLocked(oldTimedId, oldTimedAmount, firstStart);
        dg.delegate(getIds(permanentId, oldTimedId));

        // Leave alice untouched for more than 255 weeks, then delegate a new lock mid-week.
        uint256 delegateTs = firstStart + staleWeeks * checkpointInterval + midWeekOffset;
        uint256 nextCheckpoint = weekStartTs(delegateTs);
        vm.warp(delegateTs);
        _mockLocked(newTimedId, newTimedAmount, nextCheckpoint);
        dg.delegate(getIds(newTimedId));

        // Before the next checkpoint, only the permanent lock counts.
        assertEq(dg.getPastVotes(alice, delegateTs), permanentAmount);

        // From the next checkpoint, the new lock adds its power and decays from that date.
        uint256 laterTs = nextCheckpoint + weeksAfterDelegation * checkpointInterval;
        vm.warp(laterTs);
        assertEq(dg.getPastVotes(alice, nextCheckpoint), permanentAmount + bias(newTimedAmount, 0));
        assertEq(
            dg.getPastVotes(alice, laterTs),
            permanentAmount + bias(newTimedAmount, laterTs - nextCheckpoint)
        );
    }

    function test_StaleDelegate_UndelegationDatedAtNextCheckpoint() public {
        dg.setDelegateAddress(alice);

        uint256 permanentAmount = getFlooredAmount(10e18);
        uint256 staleWeeks = 260;
        uint256 midWeekOffset = 1 days;

        uint256 firstStart = weekStartTs(block.timestamp);
        vm.warp(firstStart);
        _mockLocked(singleId[0], permanentAmount, 0);
        dg.delegate(singleId);

        // Leave alice untouched for more than 255 weeks, then undelegate mid-week.
        uint256 snapshotTs = firstStart + staleWeeks * checkpointInterval;
        uint256 undelegateTs = snapshotTs + midWeekOffset;
        uint256 nextCheckpoint = weekStartTs(undelegateTs);
        vm.warp(undelegateTs);
        dg.undelegate(singleId);

        // The removal takes effect from the next checkpoint, not retroactively.
        assertEq(dg.getPastVotes(alice, snapshotTs), permanentAmount);
        assertEq(dg.getPastVotes(alice, nextCheckpoint), 0);
    }

    function test_StaleDelegate_ManualTransitionJumpsOnlyFromMaxTime() public {
        uint256 oneStep = 1;
        uint256 staleWeeks = 260;
        uint256 midWeekOffset = 1 days;
        uint256 secondPointIndex = 2;
        uint256 maxTimeSteps = maxTime / checkpointInterval;
        uint256 belowMaxTimeSteps = maxTimeSteps - 1;

        // Week 0: create empty records for alice and bob, then leave both untouched.
        uint256 firstStart = weekStartTs(block.timestamp);
        vm.warp(firstStart);
        dg.checkpointTransition(alice, oneStep);
        dg.checkpointTransition(bob, oneStep);

        vm.warp(firstStart + staleWeeks * checkpointInterval + midWeekOffset);
        uint256 nextCheckpoint = weekStartTs(block.timestamp);

        // Fewer steps than maxTime may leave slope changes pending, so the record stops where the loop ends.
        dg.checkpointTransition(alice, belowMaxTimeSteps);
        assertGlobalPoint(alice, secondPointIndex, 0, 0, firstStart + belowMaxTimeSteps * checkpointInterval);

        // Covering maxTime processes every slope change, so the record moves to the next checkpoint.
        dg.checkpointTransition(bob, maxTimeSteps);
        assertGlobalPoint(bob, secondPointIndex, 0, 0, nextCheckpoint);
    }

    function test_InitializeRevertsIfMaxTimeExceedsLoopLimit() public {
        uint256 loopLimit = 255;
        uint256 tooManyEpochs = loopLimit * checkpointInterval / clock.epochDuration() + 1;
        bool startPaused = false;

        (int256 constantCoefficient, int256 linearDenominator, ) = CurveConstantLib.getParams();
        EscrowIVotesAdapterA impl = new EscrowIVotesAdapterA(constantCoefficient, linearDenominator, tooManyEpochs);
        bytes memory initCalldata = abi.encodeCall(
            EscrowIVotesAdapter.initialize,
            (address(dao), address(escrow), address(clock), startPaused)
        );

        // maxTime would be 256 weeks, more than one checkpoint's 255-interval loop can process.
        vm.expectRevert("maxTime exceeds checkpoint loop limit");
        ProxyLib.deployUUPSProxy(address(impl), initCalldata);
    }

    /*//////////////////////////////////////////////////////////////
                  Same Timestamp Checkpoint Overwrite
    //////////////////////////////////////////////////////////////*/

    /// @notice Tests that multiple delegate/undelegate operations at the same timestamp
    ///         overwrite the same checkpoint instead of creating multiple checkpoints.
    ///         This ensures binary search returns the correct final state.
    function test_SameTimestampCheckpointOverwrite() public {
        dg.setDelegateAddress(alice);

        uint256 amount1 = getFlooredAmount(10e18);
        uint256 amount2 = getFlooredAmount(20e18);
        uint256 amount3 = getFlooredAmount(30e18);
        uint256 start = weekStartTs(block.timestamp);

        // Setup three tokens with different amounts
        uint256 tokenId1 = 1;
        uint256 tokenId2 = 2;
        uint256 tokenId3 = 3;

        _mockLocked(tokenId1, amount1, start);
        _mockLocked(tokenId2, amount2, start);
        _mockLocked(tokenId3, amount3, start);
        _mockVotingPower(tokenId1, 1);
        _mockVotingPower(tokenId2, 1);
        _mockVotingPower(tokenId3, 1);

        vm.warp(start);

        // First delegation - creates checkpoint index 1
        dg.delegate(getIds(tokenId1));
        assertEq(dg.latestPointIndex(alice), 1);
        assertApproxEqAbs(dg.getVotes(alice), amount1, 1e11);

        // Second delegation at same timestamp - should overwrite checkpoint index 1
        dg.delegate(getIds(tokenId2, tokenId3));
        assertEq(dg.latestPointIndex(alice), 1); // Still index 1, not 2
        assertApproxEqAbs(dg.getVotes(alice), amount1 + amount2 + amount3, 1e12);

        // Undelegate at same timestamp - should still overwrite checkpoint index 1
        dg.undelegate(getIds(tokenId2, tokenId3));
        assertEq(dg.latestPointIndex(alice), 1); // Still index 1, not 3
        assertApproxEqAbs(dg.getVotes(alice), amount1, 1e11);

        // Verify final state: only token1 is delegated
        uint256 expectedVP = bias(amount1, 0);
        assertEq(dg.getVotes(alice), expectedVP);

        // Verify the checkpoint has the correct final values
        GlobalPoint memory p = dg.pointHistory_(alice, 1);
        assertEq(p.writtenTs, start);
        assertEq(p.bias, biasFP(amount1, 0));
        assertEq(p.slope, slopeFP(amount1));
    }

    /// @notice Tests that binary search correctly returns the final checkpoint state
    ///         when querying historical votes after checkpoint overwrite.
    function test_BinarySearchReturnsCorrectStateAfterOverwrite() public {
        dg.setDelegateAddress(alice);

        uint256 amount1 = getFlooredAmount(10e18);
        uint256 amount2 = getFlooredAmount(20e18);
        uint256 amount3 = getFlooredAmount(30e18);
        uint256 start = weekStartTs(block.timestamp);

        uint256 tokenId1 = 1;
        uint256 tokenId2 = 2;
        uint256 tokenId3 = 3;

        _mockLocked(tokenId1, amount1, start);
        _mockLocked(tokenId2, amount2, start);
        _mockLocked(tokenId3, amount3, start);
        _mockVotingPower(tokenId1, 1);
        _mockVotingPower(tokenId2, 1);
        _mockVotingPower(tokenId3, 1);

        // Multiple operations at same timestamp
        dg.delegate(getIds(tokenId1));
        dg.delegate(getIds(tokenId2, tokenId3));
        dg.undelegate(getIds(tokenId2, tokenId3));

        // Only checkpoint index 1 should exist with final state
        assertEq(dg.latestPointIndex(alice), 1);

        // Move to future and create a new checkpoint to force binary search path
        vm.warp(block.timestamp + 1 weeks);
        dg.checkpointTransition(alice, 1);

        // Now we have checkpoint index 2 at a later timestamp
        assertEq(dg.latestPointIndex(alice), 2);

        // Query historical votes at the original timestamp
        // This will use binary search since we're querying a past timestamp
        uint256 historicalVP = dg.getPastVotes(alice, start);

        // Should return the final state (only token1 delegated), not inflated value
        uint256 expectedVP = bias(amount1, 0);
        assertEq(historicalVP, expectedVP);

        // Verify it's NOT returning the inflated value (all three tokens)
        uint256 inflatedVP = bias(amount1 + amount2 + amount3, 0);
        assertTrue(historicalVP != inflatedVP);
    }

    /// @notice Tests that checkpoints at different timestamps still create separate indices.
    function test_DifferentTimestampsCreateSeparateCheckpoints() public {
        dg.setDelegateAddress(alice);

        uint256 amount1 = getFlooredAmount(10e18);
        uint256 amount2 = getFlooredAmount(20e18);
        uint256 start = weekStartTs(block.timestamp);

        uint256 tokenId1 = 1;
        uint256 tokenId2 = 2;

        _mockLocked(tokenId1, amount1, start);
        _mockLocked(tokenId2, amount2, start);
        _mockVotingPower(tokenId1, 1);
        _mockVotingPower(tokenId2, 1);

        // First delegation at timestamp T
        dg.delegate(getIds(tokenId1));
        assertEq(dg.latestPointIndex(alice), 1);

        // Move to a different timestamp
        vm.warp(block.timestamp + 1 weeks);
        uint256 secondDelegateTs = weekStartTs(block.timestamp);

        // Second delegation at timestamp T+1week - should create new checkpoint
        dg.delegate(getIds(tokenId2));
        assertEq(dg.latestPointIndex(alice), 2);

        // Verify both checkpoints exist with correct timestamps
        GlobalPoint memory p1 = dg.pointHistory_(alice, 1);
        GlobalPoint memory p2 = dg.pointHistory_(alice, 2);
        assertEq(p1.writtenTs, start);
        assertEq(p2.writtenTs, secondDelegateTs);

        // Query historical votes at first timestamp
        uint256 vpAtFirst = dg.getPastVotes(alice, start);
        assertEq(vpAtFirst, bias(amount1, 0));

        // Query votes at second timestamp
        uint256 vpAtSecond = dg.getPastVotes(alice, secondDelegateTs);
        assertEq(vpAtSecond, bias(amount1 + amount2, secondDelegateTs - start));
    }
}
