// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {LinearIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/LinearIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";

import {LinearCurveBase} from "./LinearBase.sol";

contract TestLinearIncreasingPopulateHistory is LinearCurveBase {
    function setUp() public override {
        super.setUp();
        //
    }
    // in the case of no history, should simply return the empty point and an index of 1
    function testNoHistoryNoScheduleStartingAtZero() public {
        (GlobalPoint memory point, uint index) = curve.populateHistory();

        // expect that nothing is written
        assertEq(point.coefficients[0], 0);
        assertEq(point.coefficients[1], 0);
        assertEq(index, 1);
    }

    // if we have no history we start at the timestamp
    function testNoHistoryStartingAtTimestamp(uint32 _warp) public {
        vm.warp(_warp);
        (GlobalPoint memory point, uint index) = curve.populateHistory();

        // expect that nothing is written
        assertEq(point.coefficients[0], 0);
        assertEq(point.coefficients[1], 0);
        assertEq(index, 1);
    }

    // in the case of no history we will return nothing unless exactly on thhe boundary
    function testNoHistorySingleSchedule(uint32 _warp) public {
        uint interval = clock.checkpointInterval();
        vm.assume(_warp >= interval);

        vm.warp(_warp);

        console.log("_warp: %s", _warp);

        // fetch the next interval
        uint48 priorInterval = uint48(clock.epochNextCheckpointTs()) -
            uint48(clock.checkpointInterval());

        console.log("priorInterval: %s", priorInterval);

        // write a scheduled point
        curve.writeSchedule(priorInterval, [int256(1000), int256(2), int256(0)]);

        // populate the history
        (GlobalPoint memory point, uint index) = curve.populateHistory();

        // expect that nothing is written
        assertEq(point.coefficients[0], 0);
        assertEq(point.coefficients[1], 0);
        assertEq(index, 1);
    }

    // test writing a global point while we're at it
    function testWritePointIndex1() public {}

    // correctly writes a single backfilled point with a scheduled curve change
    function testHistorySingleSchedule() public {
        //
    }

    function testMultipleEmptyIntervals() public {}

    // works if the schedulled change is negative

    // works if the schedulled change is positive

    // works exactly on the interval as expected

    // works a complex case of 2 weeks of history + 2 weeks of future and correctly aggregates

    /// updating the global history with the token

    // reverts when increasing is true (this sucks)

    // cannot apply an update if the point hasn't happened yet

    // the last point must be caught up

    // correctly removes the tokens accrued voting power to the global point at the correct time

    // if the user is reducing, this reduction is added back in

    // same with the slope
}
