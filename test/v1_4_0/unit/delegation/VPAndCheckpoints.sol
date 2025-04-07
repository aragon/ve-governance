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
        dg.delegate(alice);

        uint256 start = weekStartTs(block.timestamp);
        uint256 amount = 10;

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
        dg.delegate(alice);

        uint256 amount1 = 10;
        uint256 amount2 = 25;
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
        dg.delegate(alice);

        // Delegate first token
        uint256 amount1 = 10;
        uint256 start1 = weekStartTs(block.timestamp);
        uint256 start1Ts = block.timestamp;
        _mockLocked(singleId[0], amount1, start1);

        dg.delegate(singleId);

        // warp time to future so another token
        // gets delegated at a later timestamp
        vm.warp(block.timestamp + 3 weeks);

        // Delegate second token
        uint256 amount2 = 25;
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
        dg.delegate(alice);

        uint256 amount1 = 10;
        uint256 start1 = weekStartTs(block.timestamp);
        uint256 start1Ts = block.timestamp;
        _mockLocked(singleId[0], amount1, start1);

        dg.delegate(singleId);

        dg.undelegate(singleId);

        // asserts latest global point.
        assertGlobalPoint(alice, 2, 0, 0, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                     getPastVotes, getVotes
    //////////////////////////////////////////////////////////////*/

    function test_VotingPowersSingleToken() public {
        dg.delegate(alice);

        uint256 amount = 10;
        _mockLocked(singleId[0], 10, weekStartTs(block.timestamp));
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
        dg.delegate(alice);

        uint256 amount1 = 10;
        uint256 amount2 = 25;
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

    function test_TransitionCheckpoints() public {
        dg.delegate(alice);

        uint256 amount = 10;
        uint256 start = weekStartTs(block.timestamp);

        _mockLocked(singleId[0], amount, start);
        dg.delegate(singleId);

        vm.warp(block.timestamp + maxTime + 1 weeks);

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
}
