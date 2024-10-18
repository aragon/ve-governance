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

    // in the case of no history we will return nothing unless exactly on the boundary
    function testNoHistorySingleSchedule(uint32 _warp) public {
        uint interval = clock.checkpointInterval();
        vm.assume(_warp >= interval);
        vm.warp(_warp);

        uint48 priorInterval = uint48(clock.epochNextCheckpointTs()) -
            uint48(clock.checkpointInterval());

        // write a scheduled point
        curve.writeSchedule(priorInterval, [int256(1000), int256(2), int256(0)]);

        // populate the history
        (GlobalPoint memory point, uint index) = curve.populateHistory();

        // if we have a scheduled write exactly now, we should have the
        // point written to memory but not storage as we have to add the user data later
        if (priorInterval == _warp) {
            assertEq(point.coefficients[0], 1000);
            assertEq(point.coefficients[1], 2);
            assertEq(index, 1);
            assertEq(curve.pointHistory(1).coefficients[0], 0);
        }
        // otherwise expect nothing
        else {
            assertEq(point.coefficients[0], 0);
            assertEq(point.coefficients[1], 0);
            assertEq(index, 1);
            assertEq(curve.pointHistory(1).coefficients[0], 0);
        }
    }

    //
    // function testFuzz_writeSameIdxDiffTs(GlobalPoint memory point, uint idx) public {
    //     vm.assume(idx > 0);
    //     vm.assume(point.ts < type(uint).max);
    //
    //     // write an existing point
    //     curve.writeNewGlobalPoint(point, idx);
    //
    //     // vary the ts
    //     uint oldTs = point.ts;
    //     point.ts = oldTs + 1;
    //
    //     // write the new point
    //     curve.writeNewGlobalPoint(point, idx);
    //
    //     // expected - overwritten due to the idx
    //     assertEq(curve.pointHistory(idx).ts, oldTs + 1);
    // }

    function testOverwritePoint() public {}
    // correctly writes a single backfilled point with a scheduled curve change
    function testHistorySingleSchedule() public {
        //
    }

    function testMultipleEmptyIntervals() public {}

    // writing on the exact date of a scheduled change behaves as expected

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

    // fetches latest point
    // if not hte last point, the last point is at block.timetamp
    // if point is empty, returns empty point at interval 0
    // if no changes, returns the current index
    // if no changes and has a last point, returns it
    // it will happen if:
    // -- scheduled, not current increase (new deposit)
    // -- no scheduled changes have occured meaning the glboalPoint is empty
    // this is equivalent to
}
