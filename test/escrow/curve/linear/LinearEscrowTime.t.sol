// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {LinearIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/LinearIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";

import {LinearCurveBase} from "./LinearBase.sol";

contract TestLinearIncreasingTime is LinearCurveBase {
    // bounded since lock start

    // before the lock starts - return 0
    function testFuzzBeforeLockStartReturnZero(uint start, uint timestamp) public view {
        vm.assume(start > timestamp);
        assertEq(curve.boundedTimeSinceLockStart(start, timestamp), 0);
    }

    // between lock starting and max time - return the correct amount
    function testFuzzBetweenLockStartAndMaxTime(uint start, uint timestamp) public view {
        vm.assume(start <= timestamp);
        vm.assume(timestamp <= curve.maxTime());
        assertEq(curve.boundedTimeSinceLockStart(start, timestamp), timestamp - start);
    }

    // after max time - return max
    function testFuzzAfterMaxTime(uint start, uint timestamp) public view {
        vm.assume(start <= timestamp);
        vm.assume(timestamp - start >= curve.maxTime());
        assertEq(curve.boundedTimeSinceLockStart(start, timestamp), curve.maxTime());
    }

    // bounded since checkpoint

    // if checkpoint < start, revert
    function testFuzzCheckpointBeforeStartRevert(
        uint start,
        uint128 checkpoint,
        uint timestamp
    ) public {
        vm.assume(checkpoint < start);
        vm.expectRevert(InvalidCheckpoint.selector);
        curve.boundedTimeSinceCheckpoint(start, checkpoint, timestamp);
    }

    // before the checkpoint - return 0
    function testFuzzBeforeCheckpointReturnZero(
        uint start,
        uint128 checkpoint,
        uint timestamp
    ) public view {
        vm.assume(checkpoint >= start);
        vm.assume(checkpoint > timestamp);
        assertEq(curve.boundedTimeSinceCheckpoint(start, checkpoint, timestamp), 0);
    }

    // before the lock starts - return 0
    function testFuzzBeforeLockStartReturnZero(
        uint start,
        uint128 checkpoint,
        uint timestamp
    ) public view {
        vm.assume(checkpoint >= start);
        vm.assume(start > timestamp);
        assertEq(curve.boundedTimeSinceLockStart(start, timestamp), 0);
    }

    // if checkpoint and start are the same and less than max time, return the same value
    function testFuzzCheckpointAndStartSameAndLessThanMaxTime(
        uint128 checkpoint,
        uint timestamp
    ) public view {
        vm.assume(checkpoint <= timestamp);
        vm.assume(timestamp <= curve.maxTime());
        uint start = checkpoint;
        assertEq(
            curve.boundedTimeSinceCheckpoint(start, checkpoint, timestamp),
            timestamp - checkpoint
        );
        assertEq(
            curve.boundedTimeSinceLockStart(checkpoint, timestamp),
            curve.boundedTimeSinceCheckpoint(start, checkpoint, timestamp)
        );
    }

    // if checkpoint after start and before max time since start, return time since checkpoint
    // bounding on uints to play nicely w. overflow
    function testFuzzCheckpointAfterStartAndBeforeMaxTimeSinceStart(
        uint120 start,
        uint128 checkpoint,
        uint120 timestamp
    ) public view {
        // start ----- checkpoint ----- timestamp ==== max
        vm.assume(timestamp <= uint(start) + curve.maxTime());
        vm.assume(checkpoint > start);
        vm.assume(timestamp >= checkpoint);

        assertEq(
            curve.boundedTimeSinceCheckpoint(start, checkpoint, timestamp),
            timestamp - checkpoint
        );
    }

    // if checkpoint after start and after max time since start, return max time since start
    function testFuzzCheckpointAfterMaxSinceStart(
        uint120 start,
        uint128 checkpoint,
        uint120 timestamp
    ) public view {
        // start ----- checkpoint ==== max ----- timestamp
        vm.assume(timestamp >= uint(start) + curve.maxTime());
        vm.assume(checkpoint > start);
        vm.assume(timestamp >= checkpoint);

        uint secondsBetweenStartAndCheckpoint = checkpoint - start;
        // assume the cp is not really far from the start
        vm.assume(secondsBetweenStartAndCheckpoint <= curve.maxTime());

        // therefore we'd assume the curve can keep increasing up to max - differential
        uint maxTimeSubStartToCheckpoint = curve.maxTime() - secondsBetweenStartAndCheckpoint;

        assertEq(
            curve.boundedTimeSinceCheckpoint(start, checkpoint, timestamp),
            maxTimeSubStartToCheckpoint
        );
    }

    // if checkpoint after max time since start, return 0
    function testFuzzCheckpointAfterMaxSinceStartReturnZero(
        uint120 start,
        uint128 checkpoint,
        uint120 timestamp
    ) public view {
        // start ==== max ----- checkpoint ----- timestamp
        vm.assume(checkpoint > start);
        vm.assume(checkpoint >= uint(start) + curve.maxTime());
        vm.assume(timestamp >= checkpoint);

        assertEq(curve.boundedTimeSinceCheckpoint(start, checkpoint, timestamp), 0);
    }
}
