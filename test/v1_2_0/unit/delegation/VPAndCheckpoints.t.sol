pragma solidity ^0.8.17;

import {Base} from "./Base.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

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
        uint256 amount = 10e18;

        _mockLocked(singleId[0], amount, start);
        dg.delegate(singleId);

        assertGlobalPoint(
            alice,
            1,
            biasFP(amount, block.timestamp - start),
            slopeFP(amount),
            block.timestamp
        );
        assertSlopeChange(alice, start + maxTime, amount);
    }

    function test_DelegateMultipleTokens() public {
        dg.setDelegateAddress(alice);

        uint256 amount1 = 10e18;
        uint256 amount2 = 25e18;
        uint256 start = weekStartTs(block.timestamp);

        _mockLocked(multiIds[0], amount1, start);
        _mockLocked(multiIds[1], amount2, start);

        dg.delegate(multiIds);

        assertGlobalPoint(
            alice,
            1,
            biasFP(amount1 + amount2, block.timestamp - start),
            slopeFP(amount1 + amount2),
            block.timestamp
        );
        assertSlopeChange(alice, start + maxTime, amount1 + amount2);
    }

    function test_DelegateSecondTokenAtLaterTimestamp() public {
        dg.setDelegateAddress(alice);

        // Delegate first token
        uint256 amount1 = 10e18;
        uint256 start1 = weekStartTs(block.timestamp);
        uint256 start1Ts = block.timestamp;
        _mockLocked(singleId[0], amount1, start1);

        dg.delegate(singleId);

        // warp time to future so another token
        // gets delegated at a later timestamp
        vm.warp(block.timestamp + 3 weeks);

        // Delegate second token
        uint256 amount2 = 25e18;
        uint256 start2 = weekStartTs(block.timestamp);
        singleId[0] = 2;
        _mockLocked(singleId[0], uint208(amount2), start2);

        dg.delegate(singleId);

        // start asserting
        assertSlopeChange(alice, start1 + maxTime, amount1);
        assertSlopeChange(alice, start2 + maxTime, amount2);

        // asserts previous global point.
        GlobalPoint memory p = dg.pointHistory_(alice, 1);
        assertEq(p.bias, biasFP(amount1, start1Ts - start1));
        assertEq(p.slope, slopeFP(amount1));
        assertEq(p.writtenTs, start1Ts);

        // asserts latest global point.
        assertGlobalPoint(
            alice,
            2,
            biasFP(amount1, block.timestamp - start1) + biasFP(amount2, block.timestamp - start2),
            slopeFP(amount2) + slopeFP(amount1),
            block.timestamp
        );
    }

    function test_UndelegateShouldDecreaseSlopeAndBias() public {
        dg.setDelegateAddress(alice);

        uint256 amount = 10e18;
        uint256 start = weekStartTs(block.timestamp);
        _mockLocked(singleId[0], amount, start);

        dg.delegate(singleId);

        dg.undelegate(singleId);

        // asserts latest global point.
        assertGlobalPoint(alice, 1, 0, 0, block.timestamp);

        // slope must reflect the change as alice was undelegated.
        assertSlopeChange(alice, start + maxTime, 0);
    }

    function test_SlopeChange_WhenDelegationUndelegationOccurs() public {
        address bob = address(123);
        address carol = address(456);
        address alice = address(789);

        uint256 bobAmount = 10e18;
        uint256 carolAmount = 50e18;
        uint256 bobDelegateStart = weekStartTs(block.timestamp);

        // bob delegates to alice amount = 10 and immediatelly undelegates.
        // This should still register slopeChange as 0 on bobDelegateStart + maxTime
        {
            uint256[] memory ids = new uint256[](1);
            ids[0] = 1;
            vm.startPrank(bob);
            _mockLocked(ids[0], bobAmount, bobDelegateStart);
            dg.setDelegateAddress(alice);
            dg.delegate(ids);
            dg.undelegate(ids);
            vm.stopPrank();
        }

        assertSlopeChange(alice, bobDelegateStart + maxTime, 0);
        assertSlopeChange(bob, bobDelegateStart + maxTime, 0);

        vm.warp(block.timestamp + 1 weeks + 1 hours);
        uint256 carolDelegateStart = weekStartTs(block.timestamp);

        // carol delegates to alice amount = 20 which should register slopeChange
        // on carolDelegateStart + maxTime.
        {
            uint256[] memory ids = new uint256[](1);
            ids[0] = 2;
            vm.startPrank(carol);
            _mockLocked(ids[0], carolAmount, carolDelegateStart);
            dg.setDelegateAddress(alice);
            dg.delegate(ids);
            vm.stopPrank();
        }

        assertEq(dg.getVotes(alice), bias(carolAmount, block.timestamp - carolDelegateStart));
        assertSlopeChange(alice, carolDelegateStart + maxTime, carolAmount);

        vm.warp(block.timestamp + 100);
        assertEq(dg.getVotes(alice), bias(carolAmount, block.timestamp - carolDelegateStart));

        // We warp after bob's maxTime. SlopeChange
        // must not include bob's slope as he undelegated it.
        vm.warp(bobDelegateStart + maxTime + 40 minutes);

        if(maxTime != 0) {  
            assertEq(dg.getVotes(alice), bias(carolAmount, block.timestamp - carolDelegateStart));
        }
    }

    /*//////////////////////////////////////////////////////////////
                     getPastVotes, getVotes
    //////////////////////////////////////////////////////////////*/

    function test_VotingPowersSingleToken() public {
        dg.setDelegateAddress(alice);

        uint256 amount = 10e18;
        _mockLocked(singleId[0], amount, weekStartTs(block.timestamp));
        dg.delegate(singleId);

        uint256 expectedVP = bias(amount, block.timestamp - weekStartTs(block.timestamp));

        assertEq(dg.getPastVotes(alice, block.timestamp - 1), 0);

        assertEq(dg.getPastVotes(alice, block.timestamp), expectedVP);
        assertEq(dg.getVotes(alice), expectedVP);

        dg.undelegate(singleId);

        assertEq(dg.getPastVotes(alice, block.timestamp), 0);
        assertEq(dg.getVotes(alice), 0);
    }

    function test_VotingPowersMultipleTokens() public {
        dg.setDelegateAddress(alice);

        uint256 amount1 = 10e18;
        uint256 amount2 = 25e18;
        uint256 start = weekStartTs(block.timestamp);
        _mockLocked(multiIds[0], amount1, start);
        _mockLocked(multiIds[1], amount2, start);
        dg.delegate(multiIds);

        uint256 expectedVPToken1 = bias(amount1, block.timestamp - start);
        uint256 expectedVPToken2 = bias(amount2, block.timestamp - start);
        uint256 total = expectedVPToken1 + expectedVPToken2;
        assertEq(dg.getPastVotes(alice, block.timestamp - 1), 0);

        assertEq(dg.getPastVotes(alice, block.timestamp), total);
        assertEq(dg.getVotes(alice), total);

        dg.undelegate(getIds(multiIds[1]));

        assertEq(dg.getPastVotes(alice, block.timestamp), expectedVPToken1);
        assertEq(dg.getVotes(alice), expectedVPToken1);
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

        uint256 amount = 10e18;
        uint256 start = weekStartTs(block.timestamp);

        _mockLocked(singleId[0], amount, start);
        dg.delegate(singleId);

        uint256 delegateTs = block.timestamp;

        vm.warp(delegateTs + maxTime + 4 weeks);

        // transition checkpoints
        dg.checkpointTransition(alice, 3);

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

        uint256 amount = 10e18;
        uint256 start = weekStartTs(block.timestamp);

        _mockLocked(singleId[0], amount, start);
        dg.delegate(singleId);

        uint256 delegateTs = block.timestamp;

        vm.warp(delegateTs + maxTime + 4 weeks);

        // transition checkpoints
        dg.checkpointTransition(
            alice,
            (block.timestamp - delegateTs + 3 weeks) / checkpointInterval
        );

        uint256 expectedTs = block.timestamp;

        assertGlobalPoint(alice, 2, biasFP(amount, maxTime), 0, expectedTs);
    }

     /*//////////////////////////////////////////////////////////////
                  Same Timestamp Checkpoint Overwrite
    //////////////////////////////////////////////////////////////*/

    /// @notice Tests that multiple delegate/undelegate operations at the same timestamp
    ///         overwrite the same checkpoint instead of creating multiple checkpoints.
    ///         This ensures binary search returns the correct final state.
    function test_SameTimestampCheckpointOverwrite() public {
        dg.setDelegateAddress(alice);

        uint256 amount1 = 10;
        uint256 amount2 = 20;
        uint256 amount3 = 30;
        uint256 start = weekStartTs(block.timestamp);
        uint256 delegateTs = block.timestamp;

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

        // First delegation - creates checkpoint index 1
        dg.delegate(getIds(tokenId1));
        assertEq(dg.latestPointIndex(alice), 1);
        assertEq(dg.getVotes(alice), amount1);

        // Second delegation at same timestamp - should overwrite checkpoint index 1
        dg.delegate(getIds(tokenId2, tokenId3));
        assertEq(dg.latestPointIndex(alice), 1); // Still index 1, not 2
        assertEq(dg.getVotes(alice), amount1 + amount2 + amount3);

        // Undelegate at same timestamp - should still overwrite checkpoint index 1
        dg.undelegate(getIds(tokenId2, tokenId3));
        assertEq(dg.latestPointIndex(alice), 1); // Still index 1, not 3
        assertEq(dg.getVotes(alice), amount1);

        // Verify final state: only token1 is delegated
        uint256 expectedVP = bias(amount1, delegateTs - start);
        assertEq(dg.getVotes(alice), expectedVP);

        // Verify the checkpoint has the correct final values
        GlobalPoint memory p = dg.pointHistory_(alice, 1);
        assertEq(p.writtenTs, delegateTs);
        assertEq(p.bias, biasFP(amount1, delegateTs - start));
        assertEq(p.slope, slopeFP(amount1));
    }

    /// @notice Tests that binary search correctly returns the final checkpoint state
    ///         when querying historical votes after checkpoint overwrite.
    function test_BinarySearchReturnsCorrectStateAfterOverwrite() public {
        dg.setDelegateAddress(alice);

        uint256 amount1 = 10;
        uint256 amount2 = 20;
        uint256 amount3 = 30;
        uint256 start = weekStartTs(block.timestamp);
        uint256 delegateTs = block.timestamp;

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
        uint256 historicalVP = dg.getPastVotes(alice, delegateTs);

        // Should return the final state (only token1 delegated), not inflated value
        uint256 expectedVP = bias(amount1, delegateTs - start);
        assertEq(historicalVP, expectedVP);

        // Verify it's NOT returning the inflated value (all three tokens)
        uint256 inflatedVP = bias(amount1 + amount2 + amount3, delegateTs - start);
        assertTrue(historicalVP != inflatedVP);
    }

    /// @notice Tests that checkpoints at different timestamps still create separate indices.
    function test_DifferentTimestampsCreateSeparateCheckpoints() public {
        dg.setDelegateAddress(alice);

        uint256 amount1 = 10;
        uint256 amount2 = 20;
        uint256 start = weekStartTs(block.timestamp);
        uint256 firstDelegateTs = block.timestamp;

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
        uint256 secondDelegateTs = block.timestamp;

        // Second delegation at timestamp T+1week - should create new checkpoint
        dg.delegate(getIds(tokenId2));
        assertEq(dg.latestPointIndex(alice), 2);

        // Verify both checkpoints exist with correct timestamps
        GlobalPoint memory p1 = dg.pointHistory_(alice, 1);
        GlobalPoint memory p2 = dg.pointHistory_(alice, 2);
        assertEq(p1.writtenTs, firstDelegateTs);
        assertEq(p2.writtenTs, secondDelegateTs);

        // Query historical votes at first timestamp
        uint256 vpAtFirst = dg.getPastVotes(alice, firstDelegateTs);
        assertEq(vpAtFirst, bias(amount1, firstDelegateTs - start));

        // Query votes at second timestamp
        uint256 vpAtSecond = dg.getPastVotes(alice, secondDelegateTs);
        assertEq(vpAtSecond, bias(amount1, secondDelegateTs - start) + bias(amount2, secondDelegateTs - start));
    }
}
