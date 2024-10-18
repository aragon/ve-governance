// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {LinearIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/LinearIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";

import {LinearCurveBase} from "./LinearBase.sol";

contract TestLinearIncreasingScheduleChanges is LinearCurveBase {
    /// get latest point

    // test no prior history, no schedulling - returns CI 0, empty point with block.ts

    function testGetLatestPointNoPriorNoSchedule(uint32 warp) public {
        vm.warp(warp);
        GlobalPoint memory point = curve.getLatestGlobalPoint();

        assertEq(point.ts, block.timestamp, "ts");
        assertEq(point.bias, 0, "bias");
        assertEq(point.coefficients[0], 0, "coeff0");
        assertEq(point.coefficients[1], 0, "coeff1");
    }

    // no prior history, but a scheduled change in the future - returns a point w. ts
    function testGetLatestPointNoPriorFutureSchedule(uint48 warp) public {
        vm.assume(warp < type(uint48).max);
        vm.warp(warp);
        curve.writeEarliestScheduleChange(warp + 1);
        GlobalPoint memory point = curve.getLatestGlobalPoint();

        assertEq(point.ts, block.timestamp, "ts");
        assertEq(point.bias, 0, "bias");
        assertEq(point.coefficients[0], 0, "coeff0");
        assertEq(point.coefficients[1], 0, "coeff1");
    }

    // no prior history, but a scheduled change in the past - returns a point w. the scheduled change
    function testGetLatestPointNoPriorPastSchedule(uint48 warp) public {
        vm.assume(warp > 1); // schedulling at zero throws it off
        vm.warp(warp);
        curve.writeEarliestScheduleChange(warp - 1);
        GlobalPoint memory point = curve.getLatestGlobalPoint();

        assertEq(point.ts, warp - 1, "ts");
        assertEq(point.bias, 0, "bias");
        assertEq(point.coefficients[0], 0, "coeff0");
        assertEq(point.coefficients[1], 0, "coeff1");
    }

    // if there's a point index - return the point @ the index
    function testGetLatestPointWithPrior(uint48 warp) public {
        vm.assume(warp > 0);
        vm.warp(warp);
        curve.writeNewGlobalPoint(GlobalPoint(1, warp - 1, [int(1), int(2), int(0)]), 123);
        GlobalPoint memory point = curve.getLatestGlobalPoint();

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
    function testNoHistorySingleIterationInPast(uint48 warp) public {
        // get the interval
        uint48 interval = uint48(clock.checkpointInterval());

        vm.assume(warp > interval); // avoid zero rounding
        vm.assume(warp <= type(uint40).max); // avoid overflow

        // get the nearest interval point to warp
        uint48 schedulePast = warp - (warp % interval);
        console.log("schedulePast", schedulePast);

        // write an earliest change
        curve.writeEarliestScheduleChange(schedulePast);

        // write a scheduled change for the same time

        curve.writeSchedule(schedulePast, [int(1e18), int(2e18), int(0)]);

        // populate the history
        vm.warp(warp);
        (GlobalPoint memory point, uint index) = curve.populateHistory();

        // assertEq(index, 1, "index");
        assertEq(point.ts, warp, "ts");
        console.log("warp - schedulePast", warp - schedulePast);
        // ingnore the bias for now
        // assertEq(point.bias, 1, "bias");
        // coeff 1 should be 1 interval of accumulated bias PLUS the initial deposit
        // i.e I deposit 1 token, slope is 2, I should have 1 token + slope*interval

        uint expectedBias = curve.getBias(warp - schedulePast, 2e18) + 1e18;
        assertEq(uint(point.coefficients[0]), expectedBias, "coeff0");
        // assertEq(point.coefficients[1], 2, "coeff1");
    }
    // no prior + earlest schedule in the past (multiple interation) return point + schedule and current index is multi-looped

    /// prior history

    // no earliest schedule: irrelevant

    // schedule before point.ts, not applied

    // schedule between point.ts + ts, appied (also check equality)

    // schedule after point.ts, not appied

    /// multiple iterations and gaps

    // only writes a point if there are changes
    // - test bias
    // - test coeff
    // - test both

    // doesn't write a point w/o change

    /// MATH

    // correct aggregation in a 3 point case

    /// exploits

    // calling twice in same block doesn't double write history
}
