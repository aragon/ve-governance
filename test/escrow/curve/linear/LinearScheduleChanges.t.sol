// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {LinearIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/LinearIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";

import {LinearCurveBase} from "./LinearBase.sol";

contract TestLinearIncreasingScheduleChanges is LinearCurveBase {
    /// get or write latest point

    // test no prior history, no schedulling - returns CI 0, empty point with block.ts
    function testGetLatestPointNoPriorNoSchedule(uint32 warp) public {
        vm.warp(warp);
        GlobalPoint memory point = curve.getLatestGlobalPointOrWriteFirstPoint();

        assertEq(point.ts, block.timestamp, "ts");
        assertEq(point.bias, 0, "bias");
        assertEq(point.coefficients[0], 0, "coeff0");
        assertEq(point.coefficients[1], 0, "coeff1");

        // check nothing written
        assertEq(curve.pointHistory(1).ts, 0, "ts");
    }

    // no prior history, but a scheduled change in the future - returns a point w. ts
    function testGetLatestPointNoPriorFutureSchedule(uint48 warp) public {
        vm.assume(warp < type(uint48).max);
        vm.warp(warp);
        curve.writeEarliestScheduleChange(warp + 1);
        GlobalPoint memory point = curve.getLatestGlobalPointOrWriteFirstPoint();

        assertEq(point.ts, block.timestamp, "ts");
        assertEq(point.bias, 0, "bias");
        assertEq(point.coefficients[0], 0, "coeff0");
        assertEq(point.coefficients[1], 0, "coeff1");

        // check nothing written
        assertEq(curve.pointHistory(1).ts, 0, "ts");
    }

    // no prior history, but a scheduled change in the past - returns a point w. the scheduled change
    // and writes the point
    function testGetLatestPointNoPriorPastSchedule(uint48 warp) public {
        vm.assume(warp > 1); // schedulling at zero throws it off
        vm.warp(warp);
        curve.writeEarliestScheduleChange(warp - 1);
        curve.writeSchedule(warp - 1, [int(1), int(2), int(0)]);
        GlobalPoint memory point = curve.getLatestGlobalPointOrWriteFirstPoint();

        assertEq(point.ts, warp - 1, "ts");
        assertEq(point.bias, 0, "bias"); // TODO
        assertEq(point.coefficients[0], 1, "coeff0");
        assertEq(point.coefficients[1], 2, "coeff1");

        // check we have written
        GlobalPoint memory pointFromHistory = curve.pointHistory(1);

        assertEq(pointFromHistory.ts, warp - 1, "ts");
        assertEq(pointFromHistory.bias, 0, "bias"); // TODO
        assertEq(pointFromHistory.coefficients[0], 1, "coeff0");
        assertEq(pointFromHistory.coefficients[1], 2, "coeff1");
    }

    // if there's a point index - return the point @ the index
    function testGetLatestPointWithPrior(uint48 warp) public {
        vm.assume(warp > 0);
        vm.warp(warp);
        curve.writeNewGlobalPoint(GlobalPoint(1, warp - 1, [int(1), int(2), int(0)]), 123);
        GlobalPoint memory point = curve.getLatestGlobalPointOrWriteFirstPoint();

        assertEq(point.ts, warp - 1, "ts");
        assertEq(point.bias, 1, "bias");
        assertEq(point.coefficients[0], 1, "coeff0");
        assertEq(point.coefficients[1], 2, "coeff1");
    }

    /// pop hist

    // no prior no earliest schedule - return empty
    function testPopulateHistoryNoPriorNoSchedule(uint32 warp) public {
        vm.assume(warp > 0);
        vm.warp(warp);
        (GlobalPoint memory point, uint index) = curve.populateHistory();

        assertEq(index, 0, "index");
        assertEq(point.ts, warp, "ts");
        assertEq(point.bias, 0, "bias");
        assertEq(point.coefficients[0], 0, "coeff0");
        assertEq(point.coefficients[1], 0, "coeff1");
    }

    // no prior + earliest schedule in future - return empty
    function testPopulateHistoryNoPriorFutureSchedule(uint48 warp) public {
        vm.assume(warp < type(uint48).max);
        vm.warp(warp);
        curve.writeEarliestScheduleChange(warp + 1);
        (GlobalPoint memory point, uint index) = curve.populateHistory();

        assertEq(index, 0, "index");
        assertEq(point.ts, warp, "ts");
        assertEq(point.bias, 0, "bias");
        assertEq(point.coefficients[0], 0, "coeff0");
        assertEq(point.coefficients[1], 0, "coeff1");
    }

    /// assume here that the scheule + earliest schedules are correct:

    // no prior + earliest schedule in past (single iteration) return the point + the schedule
    // so we need to setup the scheduled changes
    function testNoHistorySingleIterationInPast() public {
        // hardcode a warp, should be lets say 1 week + 1 day
        uint48 warp = 1 weeks + 1 days;
        // get the interval
        uint48 interval = uint48(clock.checkpointInterval());

        vm.assume(warp > interval); // avoid zero rounding
        vm.assume(warp <= type(uint40).max); // avoid overflow
        TokenPoint memory tokenPointPreview = curve.previewPoint(1e18);

        // get the nearest interval point to warp
        uint48 schedulePast = warp - (warp % interval);

        // write an earliest change
        curve.writeEarliestScheduleChange(schedulePast);

        // write a scheduled change for the same time
        curve.writeSchedule(
            schedulePast,
            [tokenPointPreview.coefficients[0], tokenPointPreview.coefficients[1], int(0)]
        );

        // populate the history
        vm.warp(warp);
        (GlobalPoint memory point, uint index) = curve.populateHistory();

        // assertEq(index, 1, "index");
        assertEq(point.ts, warp, "ts");

        // ingnore the bias for now
        // assertEq(point.bias, 1, "bias");
        uint expectedBias = curve.getBias(warp - schedulePast, 1e18);
        assertEq(uint(point.coefficients[0]) / 1e18, expectedBias, "coeff0");
        assertEq(point.coefficients[1], tokenPointPreview.coefficients[1], "coeff1");
        // should have the first index + another loop
        assertEq(index, 2);
    }
    // no prior + earlest schedule in the past (multiple interation) return point + schedule and current index is multi-looped
    function testNoHistoryMultipleIterationInPast() public {
        // hardcode a warp, should be lets say 1 week + 1 day
        uint48 warp = 3 weeks + 1 days;
        // get the interval
        uint48 interval = uint48(clock.checkpointInterval());

        vm.assume(warp > interval); // avoid zero rounding
        vm.assume(warp <= type(uint40).max); // avoid overflow
        TokenPoint memory tokenPointPreview = curve.previewPoint(1e18);

        // check the values of the point
        console.log("preview bias", tokenPointPreview.bias);
        console.log("preview c0", tokenPointPreview.coefficients[0]);
        console.log("preview c1", tokenPointPreview.coefficients[1]);

        // get the nearest interval point to warp
        uint48 schedulePast = 1 weeks;
        console.log("schedulePast", schedulePast);

        // write an earliest change
        curve.writeEarliestScheduleChange(schedulePast);

        // write a scheduled change for the same time
        curve.writeSchedule(
            schedulePast,
            [tokenPointPreview.coefficients[0], tokenPointPreview.coefficients[1], int(0)]
        );

        // populate the history
        vm.warp(warp);
        (GlobalPoint memory point, uint index) = curve.populateHistory();

        // assertEq(index, 1, "index");
        assertEq(point.ts, warp, "ts");

        console.log("warp - schedulePast", warp - schedulePast);
        // ingnore the bias for now
        // assertEq(point.bias, 1, "bias");

        uint expectedBias = curve.getBias(warp - schedulePast, 1e18);
        assertEq(uint(point.coefficients[0] / 1e18), expectedBias, "coeff0");
        assertEq(point.coefficients[1], tokenPointPreview.coefficients[1], "coeff1");
        // 1 at week 1
        // 2 at week 2
        // 3 at week 3
        // 4 at week 3 + 1 day
        assertEq(index, 4);
    }
    /// prior history

    // no earliest schedule but a point will skip the schedule
    // case 1: point.ts == now
    function testPriorHistoryIgnoresEarliestSchedulePresent() public {
        vm.warp(1 weeks + 1 days);
        // write a global point at now
        curve.writeNewGlobalPoint(GlobalPoint(1, block.timestamp, [int(1), int(2), int(0)]), 1);

        // write a schedule
        curve.writeSchedule(1 weeks, [int(9), int(3), int(0)]);
        curve.writeEarliestScheduleChange(1 weeks);

        // fetch the history from populate
        (GlobalPoint memory point, uint index) = curve.populateHistory();

        // we expect to return 1 and ignore the schedule
        assertEq(index, 1);
        assertEq(point.ts, block.timestamp);
        assertEq(point.coefficients[0], 1);
        assertEq(point.coefficients[1], 2);
    }

    // case 2: point.ts < now
    function testPriorHistoryIgnoresEarliestSchedulePast() public {
        vm.warp(1 weeks + 1 days);
        // write a global point at now
        curve.writeNewGlobalPoint(GlobalPoint(1, block.timestamp - 1, [int(1), int(2), int(0)]), 1);

        // write a schedule
        curve.writeSchedule(1 weeks, [int(9), int(3), int(0)]);
        curve.writeEarliestScheduleChange(1 weeks);

        // fetch the history from populate
        (GlobalPoint memory point, uint index) = curve.populateHistory();

        // we expect to return 2 and ignore the schedule
        assertEq(index, 2);
        assertEq(point.ts, block.timestamp);
        // skip [0] as not checking that here
        assertEq(point.coefficients[1], 2);
    }

    // here we test the application of scheduling changes

    // schedule before point.ts, not applied
    function testPriorHistoryIgnoresScheduleBeforeLatestPoint() public {
        vm.warp(1 weeks + 1 days);
        // write a global point at now
        curve.writeNewGlobalPoint(GlobalPoint(1, block.timestamp - 1, [int(1), int(2), int(0)]), 1);

        // write a schedule
        curve.writeSchedule(1 weeks, [int(9), int(3), int(0)]);

        // fetch the history from populate
        (GlobalPoint memory point, uint index) = curve.populateHistory();

        // we expect to return 2 and ignore the schedule
        assertEq(index, 2);
        assertEq(point.ts, block.timestamp);
        // skip [0] as not checking that here
        assertEq(point.coefficients[1], 2);
    }

    // schedule between point.ts + ts, appied (also check equality)
    function testPriorHistoryIncludesScheduleBetweenLatestPointAndNow() public {
        // get a first tokenPoint
        TokenPoint memory globalPrev = curve.previewPoint(10e18);

        // write a global point at w1
        curve.writeNewGlobalPoint(
            GlobalPoint(
                0, // bias
                1 weeks, // ts
                [globalPrev.coefficients[0], globalPrev.coefficients[1], int(0)]
            ),
            1 // index
        );

        // get a token point to be schedulled
        TokenPoint memory tokenPointPreview = curve.previewPoint(1e18);

        // write a scheduled change at the next week
        curve.writeSchedule(
            2 weeks,
            [tokenPointPreview.coefficients[0], tokenPointPreview.coefficients[1], int(0)]
        );

        // warp after
        vm.warp(2 weeks + 1 days);

        // fetch the history from populate
        (GlobalPoint memory point, uint index) = curve.populateHistory();

        // we expect to return 3 and include the schedule
        assertEq(index, 3);
        assertEq(point.ts, block.timestamp);

        // check point 2 is included
        GlobalPoint memory p1 = curve.pointHistory(1);
        GlobalPoint memory p2 = curve.pointHistory(2);
        GlobalPoint memory p3 = curve.pointHistory(3);

        // point 1 should just be the first global point we wrote
        assertEq(p1.ts, 1 weeks);
        assertEq(p1.coefficients[0], globalPrev.coefficients[0]);
        assertEq(p1.coefficients[1], globalPrev.coefficients[1]);

        // point 2 should be at 2 weeks, the coeff 0 is p1 evaluated for 1 week
        assertEq(p2.ts, 2 weeks);

        uint expectedCoeff0p2 = curve.getBias(1 weeks, 10e18) + 1e18; // add the deposit amount from the scheduled change
        assertEq(uint(p2.coefficients[0]) / 1e18, expectedCoeff0p2);

        // the slope will be the addition of both coefficient[1]
        assertEq(
            p2.coefficients[1],
            globalPrev.coefficients[1] + tokenPointPreview.coefficients[1]
        );

        // point 3 should not have been written yet
        assertEq(p3.ts, 0);

        // latest point should be @ ts, same coeff 1, gt coeff 0
        assertEq(point.ts, block.timestamp);
        assertGt(point.coefficients[0], p2.coefficients[0]);
        assertEq(point.coefficients[1], p2.coefficients[1]);
    }

    // schedule after point.ts, not appied
    function testPriorHistoryDoesntIncludeScheduleAfterLatestPoint() public {
        // get a first tokenPoint
        TokenPoint memory globalPrev = curve.previewPoint(10e18);

        // write a global point at w1
        curve.writeNewGlobalPoint(
            GlobalPoint(
                0, // bias
                1 weeks, // ts
                [globalPrev.coefficients[0], globalPrev.coefficients[1], int(0)]
            ),
            1 // index
        );

        // get a token point to be schedulled
        TokenPoint memory tokenPointPreview = curve.previewPoint(1e18);

        // write a scheduled change at the next week
        curve.writeSchedule(
            2 weeks,
            [tokenPointPreview.coefficients[0], tokenPointPreview.coefficients[1], int(0)]
        );

        // warp between
        vm.warp(1 weeks + 1 days);

        // fetch the history from populate
        (GlobalPoint memory point, uint index) = curve.populateHistory();

        // we expect to return 2 and not include the schedule
        assertEq(index, 2);
        assertEq(point.ts, block.timestamp);

        // check point 2 is included
        GlobalPoint memory p1 = curve.pointHistory(1);
        GlobalPoint memory p2 = curve.pointHistory(2);

        // point 1 should just be the first global point we wrote
        assertEq(p1.ts, 1 weeks);
        assertEq(p1.coefficients[0], globalPrev.coefficients[0]);
        assertEq(p1.coefficients[1], globalPrev.coefficients[1]);

        // point 2 should not have been written yet
        assertEq(p2.ts, 0);

        // latest point should be @ ts, same coeff 1, gt coeff 0
        assertEq(point.ts, block.timestamp);
        assertGt(point.coefficients[0], p1.coefficients[0]);
        assertEq(point.coefficients[1], p1.coefficients[1]);
    }

    /// multiple iterations and gaps
    function testMultipleIterationsOnlyWritesIfChanges() public {
        // get a first tokenPoint
        TokenPoint memory globalPrev = curve.previewPoint(10e18);

        // write a global point at w1
        curve.writeNewGlobalPoint(
            GlobalPoint(
                0, // bias
                1 weeks, // ts
                [globalPrev.coefficients[0], globalPrev.coefficients[1], int(0)]
            ),
            1 // index
        );

        // get a token point to be schedulled
        TokenPoint memory tokenPointPreview = curve.previewPoint(1e18);

        // write a scheduled change after a few weeks
        curve.writeSchedule(
            5 weeks,
            [tokenPointPreview.coefficients[0], tokenPointPreview.coefficients[1], int(0)]
        );

        // warp between
        vm.warp(5 weeks + 1);

        // fetch the history from populate
        (GlobalPoint memory point, uint index) = curve.populateHistory();

        // we expect to return index 5
        assertEq(index, 6, "index != 6");
        assertEq(point.ts, 5 weeks + 1, "ts !> 5 weeks");

        // check point 2 is included
        GlobalPoint memory p1 = curve.pointHistory(1);
        GlobalPoint memory p5 = curve.pointHistory(5);
        GlobalPoint memory p6 = curve.pointHistory(6);

        // point 1 should just be the first global point we wrote
        assertEq(p1.ts, 1 weeks);
        assertEq(p1.coefficients[0], globalPrev.coefficients[0]);
        assertEq(p1.coefficients[1], globalPrev.coefficients[1]);

        // point 2 - 4 not written
        for (uint i = 2; i < 5; i++) {
            GlobalPoint memory p = curve.pointHistory(i);
            assertEq(p.ts, 0);
        }

        // point 6 not written
        assertEq(p6.ts, 0);

        // latest point should be @ ts, should be written
        assertEq(p5.ts, 5 weeks, "p5.ts != 5 weeks");

        uint expectedBias = curve.getBias(5 weeks - 1 weeks, 10e18) + 1e18; // add the deposit amount from the scheduled change
        assertEq(
            uint(p5.coefficients[0]) / 1e18,
            expectedBias,
            "p5.coefficients[0] != expectedBias"
        );
        assertEq(
            p5.coefficients[1],
            p1.coefficients[1] + tokenPointPreview.coefficients[1],
            "p5.slope != expected"
        );
    }

    // calling twice in same block doesn't double write history
    function testCallingTwiceInSameBlockDoesntDoubleWrite() public {
        // get a first tokenPoint
        TokenPoint memory globalPrev = curve.previewPoint(10e18);

        // write a global point at w1
        curve.writeNewGlobalPoint(
            GlobalPoint(
                0, // bias
                1 weeks, // ts
                [globalPrev.coefficients[0], globalPrev.coefficients[1], int(0)]
            ),
            1 // index
        );

        // get a token point to be schedulled
        TokenPoint memory tokenPointPreview = curve.previewPoint(1e18);

        // write a scheduled change at the next week
        curve.writeSchedule(
            2 weeks,
            [tokenPointPreview.coefficients[0], tokenPointPreview.coefficients[1], int(0)]
        );

        // warp after
        vm.warp(2 weeks + 1 days);

        // double populate
        curve.populateHistory();
        (GlobalPoint memory point, uint index) = curve.populateHistory();

        // rest is same as the previous test above

        // we expect to return 3 and include the schedule
        assertEq(index, 3);
        assertEq(point.ts, block.timestamp);

        // check point 2 is included
        GlobalPoint memory p1 = curve.pointHistory(1);
        GlobalPoint memory p2 = curve.pointHistory(2);
        GlobalPoint memory p3 = curve.pointHistory(3);

        // point 1 should just be the first global point we wrote
        assertEq(p1.ts, 1 weeks);
        assertEq(p1.coefficients[0], globalPrev.coefficients[0]);
        assertEq(p1.coefficients[1], globalPrev.coefficients[1]);

        // point 2 should be at 2 weeks, the coeff 0 is p1 evaluated for 1 week
        assertEq(p2.ts, 2 weeks);

        uint expectedCoeff0p2 = curve.getBias(1 weeks, 10e18) + 1e18; // add the deposit amount from the scheduled change
        assertEq(uint(p2.coefficients[0]) / 1e18, expectedCoeff0p2);

        // the slope will be the addition of both coefficient[1]
        assertEq(
            p2.coefficients[1],
            globalPrev.coefficients[1] + tokenPointPreview.coefficients[1]
        );

        // point 3 should not have been written yet
        assertEq(p3.ts, 0);

        // latest point should be @ ts, same coeff 1, gt coeff 0
        assertEq(point.ts, block.timestamp);
        assertGt(point.coefficients[0], p2.coefficients[0]);
        assertEq(point.coefficients[1], p2.coefficients[1]);
    }
}
