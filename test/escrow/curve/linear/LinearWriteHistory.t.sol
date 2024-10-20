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
    // in the case of no history, should simply return the empty point and an index of 0
    // if we have no history we start at the timestamp
    function testNoHistoryStartingAtTimestamp(uint32 _warp) public {
        vm.warp(_warp);
        (GlobalPoint memory point, uint index) = curve.populateHistory();

        // the point should be empty
        assertEq(point.ts, block.timestamp);
        assertEq(point.coefficients[0], 0);
        assertEq(point.coefficients[1], 0);

        // nothing written
        assertEq(curve.pointHistory(1).ts, 0);
        assertEq(curve.pointHistory(0).ts, 0); // can't be accessed but hey
        assertEq(index, 0);
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
            assertEq(point.coefficients[0], 1000, "coeff0 exact");
            assertEq(point.coefficients[1], 2, "coeff1 exact");
            assertEq(index, 1, "index exact");
            assertEq(curve.pointHistory(1).coefficients[0], 0, "ph exact");
        }
        // otherwise expect nothing
        else {
            assertEq(point.coefficients[0], 0, "coeff0 @ warp");
            assertEq(point.coefficients[1], 0, "coeff1 @ warp");
            assertEq(index, 0, "index @ warp");
            assertEq(curve.pointHistory(1).coefficients[0], 0, "ph @ warp");
        }
    }

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

        // get the nearest interval point to warp
        uint48 schedulePast = 1 weeks;

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

    // test that we can taper off a schedule by pairing it to a decrease in the future
    function testDecreasingSchedule() public {
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

        // write a drop off after 4 weeks
        // this is essentially a maxing out of voting power across both points
        curve.writeSchedule(
            4 weeks,
            [int(0), -tokenPointPreview.coefficients[1] - globalPrev.coefficients[1], int(0)]
        );

        // warp after
        vm.warp(4 weeks + 1 days);

        // fetch the history from populate
        (GlobalPoint memory point, uint index) = curve.populateHistory();

        // we expect to return 5 (3 weeks + index 1 + the 1 day
        assertEq(index, 5);
        assertEq(point.ts, block.timestamp);

        GlobalPoint memory p1 = curve.pointHistory(1);
        GlobalPoint memory p2 = curve.pointHistory(2);
        GlobalPoint memory p3 = curve.pointHistory(3);
        GlobalPoint memory p4 = curve.pointHistory(4);
        GlobalPoint memory p5 = curve.pointHistory(5);

        // point 1 should just be the first global point we wrote
        assertEq(p1.ts, 1 weeks, "p1.ts != 1 weeks");
        assertEq(p1.coefficients[0], globalPrev.coefficients[0], "p1.coefficients[0]");
        assertEq(p1.coefficients[1], globalPrev.coefficients[1], "p1.coefficients[1]");

        // point 2 should be at 2 weeks, the coeff 0 is p1 evaluated for 1 week
        assertEq(p2.ts, 2 weeks, "p2.ts != 2 weeks");

        uint expectedCoeff0p2 = curve.getBias(1 weeks, 10e18) + 1e18; // add the deposit amount from the scheduled change
        assertEq(uint(p2.coefficients[0]) / 1e18, expectedCoeff0p2, "p2.coefficients[0]");

        // the slope will be the addition of both coefficient[1]
        assertEq(
            p2.coefficients[1],
            globalPrev.coefficients[1] + tokenPointPreview.coefficients[1],
            "p2.coefficients[1]"
        );

        // point 3 is zero as sparse
        assertEq(p3.ts, 0);

        // point 4 should be written but the coefficients should now stop increasing
        assertEq(p4.ts, 4 weeks, "p4.ts != 4 weeks");
        assertEq(p4.coefficients[1], 0, "p4.coefficients[1] != 0");

        // the bias should be p2 -> p4 evalulated
        // should be total of both for respective periods
        uint expectedCoeff0p4 = curve.getBias(3 weeks, 10e18) + curve.getBias(2 weeks, 1e18);
        assertEq(uint(p4.coefficients[0]) / 1e18, expectedCoeff0p4, "p4.coefficients[0]");

        // point 5 should not be written as no changes
        assertEq(p5.ts, 0, "p5.ts != block.timestamp");

        // last point in memory should be same as point 4
        assertEq(point.ts, block.timestamp, "point.ts != block.timestamp");
        assertEq(point.coefficients[0], p4.coefficients[0], "point.coefficients[0]");
        assertEq(point.coefficients[1], p4.coefficients[1], "point.coefficients[1]");
    }
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
