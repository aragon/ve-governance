// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {LinearIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/LinearIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";

import {LinearCurveBase} from "./LinearBase.sol";
contract TestLinearIncreasingCurveTokenCheckpoint is LinearCurveBase {
    // new deposit - returns initial point starting in future and empty old, ti == 1
    function testTokenCheckpointNewDepositSchedule() public {
        vm.warp(100);

        LockedBalance memory lock = LockedBalance({start: 101, amount: 1e18});

        (TokenPoint memory oldPoint, TokenPoint memory newPoint) = curve.tokenCheckpoint(1, lock);

        assertEq(newPoint.coefficients[0] / 1e18, 1e18);
        assertEq(newPoint.coefficients[1], curve.previewPoint(1e18).coefficients[1]);
        assertEq(newPoint.checkpointTs, 101);
        assertEq(newPoint.writtenTs, 100);

        assertEq(oldPoint.coefficients[0], 0);
        assertEq(oldPoint.coefficients[1], 0);
        assertEq(oldPoint.checkpointTs, 0);
        assertEq(oldPoint.writtenTs, 0);

        // token interval == 1
        assertEq(curve.tokenPointIntervals(1), 1);
        assertEq(curve.tokenPointHistory(1, 1).checkpointTs, 101);
    }

    // first write after start - returns point evaluated since start and empty old, ti == 1
    function testTokenCheckpointFirstWriteAfterStart() public {
        vm.warp(200);

        LockedBalance memory lock = LockedBalance({start: 101, amount: 1e18});

        (TokenPoint memory oldPoint, TokenPoint memory newPoint) = curve.tokenCheckpoint(1, lock);

        uint expectedBias = curve.getBias(block.timestamp - lock.start, 1e18);

        assertEq(uint(newPoint.coefficients[0]) / 1e18, expectedBias);
        assertEq(newPoint.coefficients[1], curve.previewPoint(1e18).coefficients[1]);
        assertEq(newPoint.checkpointTs, block.timestamp);
        assertEq(newPoint.writtenTs, block.timestamp);

        assertEq(oldPoint.coefficients[0], 0);
        assertEq(oldPoint.coefficients[1], 0);
        assertEq(oldPoint.checkpointTs, 0);
        assertEq(oldPoint.writtenTs, 0);

        // token interval == 1
        assertEq(curve.tokenPointIntervals(1), 1);
        assertEq(curve.tokenPointHistory(1, 1).checkpointTs, block.timestamp);
    }

    // old point, reverts if the old cpTs > newcpTs
    function testRevertIfNewBeforeOldPointSchedule() public {
        vm.warp(100);
        // checkpoint old point in future
        LockedBalance memory oldLock = LockedBalance({start: 200, amount: 1e18});

        curve.tokenCheckpoint(1, oldLock);

        // checkpoint new point less in the future
        LockedBalance memory newLock = LockedBalance({start: 101, amount: 1e18});

        vm.expectRevert(InvalidCheckpoint.selector);
        curve.tokenCheckpoint(1, newLock);
    }

    function testRevertIfNewBeforeOldInProgress() public {
        vm.warp(100);
        // checkpoint old  in the future
        LockedBalance memory oldLock = LockedBalance({start: 101, amount: 1e18});

        curve.tokenCheckpoint(1, oldLock);

        // checkpoint new point now
        LockedBalance memory newLock = LockedBalance({
            start: uint48(block.timestamp),
            amount: 1e18
        });

        vm.expectRevert(InvalidCheckpoint.selector);
        curve.tokenCheckpoint(1, newLock);
    }

    // old point yet to start, new point yet to start, overwrites
    function testOverwritePointIfBothScheduledAtSameTime() public {
        vm.warp(100);

        LockedBalance memory oldLock = LockedBalance({start: 101, amount: 1e18});
        curve.tokenCheckpoint(1, oldLock);

        LockedBalance memory newLock = LockedBalance({start: 101, amount: 2e18});

        (TokenPoint memory oldPoint, TokenPoint memory newPoint) = curve.tokenCheckpoint(
            1,
            newLock
        );

        assertEq(newPoint.coefficients[0] / 1e18, 2e18);
        assertEq(newPoint.coefficients[1], curve.previewPoint(2e18).coefficients[1]);
        assertEq(newPoint.checkpointTs, 101);
        assertEq(newPoint.writtenTs, 100);

        assertEq(oldPoint.coefficients[0] / 1e18, 1e18);
        assertEq(oldPoint.coefficients[1], curve.previewPoint(1e18).coefficients[1]);
        assertEq(oldPoint.checkpointTs, 101);
        assertEq(oldPoint.writtenTs, 100);

        // token interval == 1
        assertEq(curve.tokenPointIntervals(1), 1);
        assertEq(curve.tokenPointHistory(1, 1).checkpointTs, 101);
        assertEq(curve.tokenPointHistory(1, 1).coefficients[0] / 1e18, 2e18);
    }

    // old point started, write a new point before the max, correctly writes w. correct bias
    function testWriteNewPoint() public {
        vm.warp(100);

        // write a point
        LockedBalance memory oldLock = LockedBalance({start: 200, amount: 1e18});
        curve.tokenCheckpoint(1, oldLock);

        // fast forward after starting
        vm.warp(300);

        // write another point which is a reduction
        LockedBalance memory reducedLock = LockedBalance({start: 200, amount: 0.5e18});
        (TokenPoint memory oldPoint, TokenPoint memory newPoint) = curve.tokenCheckpoint(
            1,
            reducedLock
        );

        // check the bias and slope correct
        uint expectedBias = curve.getBias(100, 0.5e18);
        assertEq(uint(newPoint.coefficients[0]) / 1e18, expectedBias);
        assertEq(newPoint.coefficients[1], curve.previewPoint(0.5e18).coefficients[1]);
        assertEq(newPoint.checkpointTs, 300);
        assertEq(newPoint.writtenTs, 300);

        // token interval == 2
        assertEq(curve.tokenPointIntervals(1), 2);
        assertEq(curve.tokenPointHistory(1, 2).checkpointTs, 300);
        assertEq(uint(curve.tokenPointHistory(1, 2).coefficients[0]) / 1e18, expectedBias);

        // exit

        vm.warp(400);
        LockedBalance memory exitLock = LockedBalance({start: 200, amount: 0});
        (TokenPoint memory exitOldPoint, TokenPoint memory exitPoint) = curve.tokenCheckpoint(
            1,
            exitLock
        );

        // check zero
        assertEq(exitPoint.coefficients[0], 0);
        assertEq(exitPoint.coefficients[1], 0);
        assertEq(exitPoint.checkpointTs, 400);
        assertEq(exitPoint.writtenTs, 400);

        // token interval == 3
        assertEq(curve.tokenPointIntervals(1), 3);
        assertEq(curve.tokenPointHistory(1, 3).checkpointTs, 400);
        assertEq(exitPoint.coefficients[0], 0);
    }

    // maxes out correctly single
    function testMultipleCheckpointMaxesBias() public {
        vm.warp(1 weeks);

        uint48 start = 2 weeks;
        // scheduled start
        LockedBalance memory lock = LockedBalance({start: start, amount: 1e18});
        curve.tokenCheckpoint(1, lock);

        // fast forward to max time + start + 10 weeks
        vm.warp(start + curve.maxTime() + 10 weeks);

        // write a new point w. 50%
        LockedBalance memory reducedLock = LockedBalance({start: start, amount: 0.5e18});

        (TokenPoint memory oldPoint, TokenPoint memory newPoint) = curve.tokenCheckpoint(
            1,
            reducedLock
        );

        // expect the times to be correct but the bias should be the max of the 0.5e18
        uint expectedBias = curve.getBias(curve.maxTime(), 0.5e18);

        assertEq(uint(newPoint.coefficients[0]) / 1e18, expectedBias);
        assertEq(newPoint.coefficients[1], curve.previewPoint(0.5e18).coefficients[1]);
        assertEq(newPoint.checkpointTs, start + curve.maxTime() + 10 weeks);
        assertEq(newPoint.writtenTs, start + curve.maxTime() + 10 weeks);
    }
}
