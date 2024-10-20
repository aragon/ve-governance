pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {LinearIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/LinearIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";

import {LinearCurveBase} from "./LinearBase.sol";

contract TestLinearIncreasingCheckpoint is LinearCurveBase {
    function testDepositSingleUser() public {
        // test 1 user and see that it maxes out

        vm.warp(1 weeks + 1 days);

        curve.unsafeCheckpoint(
            1,
            LockedBalance(0, 0),
            LockedBalance({start: 2 weeks, amount: 1000 ether})
        );

        // wait until the end of the week
        vm.warp(2 weeks);

        curve.unsafeManualCheckpoint();

        assertEq(curve.latestPointIndex(), 1, "index should be 1");

        vm.warp(2 weeks + curve.maxTime());

        curve.unsafeManualCheckpoint();

        assertEq(
            curve.latestPointIndex(),
            curve.maxTime() / 1 weeks + 1,
            "index should be maxTime / 1 weeks, 1 indexed"
        );

        vm.warp(2 weeks + curve.maxTime() + 10 weeks);

        curve.unsafeManualCheckpoint();

        assertEq(
            curve.latestPointIndex(),
            curve.maxTime() / 1 weeks + 11,
            "index should be maxTime / 1 weeks, 1 indexed + 10"
        );

        // check that most of the array is sparse
        for (uint i = 0; i < curve.maxTime() / 1 weeks + 11; i++) {
            if (i == 1 || i == 2 || i == 105) {
                continue;
            } else {
                assertEq(curve.pointHistory(i).ts, 0, "point should be empty");
            }
        }
    }
    function testDepositTwoUsers() public {
        // test 1 user and see that it maxes out

        vm.warp(1 weeks + 1 days);

        curve.unsafeCheckpoint(
            1,
            LockedBalance(0, 0),
            LockedBalance({start: 2 weeks, amount: 1000 ether})
        );

        // wait until the end of the week
        vm.warp(2 weeks);

        curve.unsafeManualCheckpoint();

        assertEq(curve.latestPointIndex(), 1, "index should be 1");

        vm.warp(2 weeks + 1 days);

        curve.unsafeCheckpoint(
            2,
            LockedBalance(0, 0),
            LockedBalance({start: 3 weeks, amount: 1000 ether})
        );

        vm.warp(2 weeks + curve.maxTime());

        curve.unsafeManualCheckpoint();

        assertEq(
            curve.latestPointIndex(),
            curve.maxTime() / 1 weeks + 2,
            "index should be maxTime / 1 weeks, 1 indexed"
        );

        vm.warp(2 weeks + curve.maxTime() + 10 weeks);

        curve.unsafeManualCheckpoint();

        assertEq(
            curve.latestPointIndex(),
            curve.maxTime() / 1 weeks + 12,
            "index should be maxTime / 1 weeks, 1 indexed + 10"
        );

        // check that most of the array is sparse
        // for (uint i = 0; i < curve.maxTime() / 1 weeks + 11; i++) {
        //     if (i == 1 || i == 2 || i == 105) {
        //         continue;
        //     } else {
        //         assertEq(curve.pointHistory(i).ts, 0, "point should be empty");
        //     }
        // }
    }
    // test a single deposit happening in the future
    // followed by manual checkpoint before and after the scheduled increase

    // test a multi user case:
    // 3 users random smashes of populate history
    // user 1 deposits 1m ether a couple days into week 1
    // call just after E0W
    // user 2 deposits 0.5m ether a couple days into week 2, then changes mind to 1m
    // user 3 deposits 1m ether exactly on week 5
    // user 1 reduces later in the same block to 0.5m
    // user 2 exits mid week
    // user 1 reduces later mid week
    // wait until end of max period
    // user 1 exits at week interval
    // user 3 exits same time
    function testCheckpoint() public {
        uint shane = 1;
        uint matt = 2;
        uint phil = 3;

        vm.warp(1 weeks + 1 days);

        // get the next cp interval
        uint48 nextInterval = uint48(clock.epochNextCheckpointTs());

        curve.unsafeCheckpoint(
            shane,
            LockedBalance(0, 0),
            LockedBalance({start: nextInterval, amount: 1_000_000e18})
        );

        {
            int slope = curve.getCoefficients(1_000_000e18)[1];

            // assertions:
            // current index still 0
            // scheduled curve changes written correctly to the future
            assertEq(curve.latestPointIndex(), 0, "index should be zero");
            assertEq(curve.scheduledCurveChanges(nextInterval)[0], 1_000_000e18);
            assertEq(curve.scheduledCurveChanges(nextInterval)[1], slope);

            // and in the future
            assertEq(curve.scheduledCurveChanges(nextInterval + curve.maxTime())[0], 0);
            assertEq(curve.scheduledCurveChanges(nextInterval + curve.maxTime())[1], -slope);
        }

        // move a couple days forward and check a manual populate doesn't work
        vm.warp(1 weeks + 5 days);
        curve.unsafeManualCheckpoint();

        {
            int slope = curve.getCoefficients(1_000_000e18)[1];

            // assertions:
            // current index still 0
            // scheduled curve changes written correctly to the future
            assertEq(curve.latestPointIndex(), 0, "index should be zero");
            assertEq(curve.scheduledCurveChanges(nextInterval)[0], 1_000_000e18);
            assertEq(curve.scheduledCurveChanges(nextInterval)[1], slope);

            // and in the future
            assertEq(curve.scheduledCurveChanges(nextInterval + curve.maxTime())[0], 0);
            assertEq(curve.scheduledCurveChanges(nextInterval + curve.maxTime())[1], -slope);
        }

        // cross the start date and do the second deposit
        vm.warp(2 weeks + 3 days);

        uint48 prevInterval = nextInterval;
        nextInterval = uint48(clock.epochNextCheckpointTs());

        curve.unsafeCheckpoint(
            matt,
            LockedBalance(0, 0),
            LockedBalance({start: nextInterval, amount: 500_000e18})
        );

        {
            // assertions:
            int baseSlope = curve.getCoefficients(1_000_000e18)[1];
            int changeInSlope = curve.getCoefficients(500_000e18)[1];
            uint expTotalVP = curve.getBias(3 days, 1_000_000e18);
            // current index is 2
            // todo: think about this as there should ideally be nothing written
            // if the only change is a schedulled one
            assertEq(curve.latestPointIndex(), 2, "index should be 2");

            // the first point has been applied at the prev interval
            GlobalPoint memory p0 = curve.pointHistory(0);
            assertEq(p0.ts, 0, "should not have written to 0th index");

            GlobalPoint memory p1 = curve.pointHistory(1);
            assertEq(p1.ts, prevInterval, "should have written to 1st index");

            assertEq(
                p1.coefficients[0] / 1e18,
                1_000_000e18,
                "should have written bias to 1st index"
            );
            assertEq(
                p1.coefficients[1] / 1e18,
                baseSlope,
                "should have written slope to 1st index"
            );

            GlobalPoint memory p2 = curve.pointHistory(2);

            // expect the coeff1 is the same and the bias is interpolated over 3 days
            assertEq(p2.ts, block.timestamp, "point 2 should be at current time");
            assertEq(p2.coefficients[1] / 1e18, baseSlope, "slope should be the same");
            assertEq(uint(p2.coefficients[0]) / 1e18, expTotalVP, "bias should be interpolated");

            // scheduled increases at the end of the week
            assertEq(curve.scheduledCurveChanges(nextInterval)[0], 500_000e18);
            assertEq(curve.scheduledCurveChanges(nextInterval)[1], changeInSlope);

            // scheduled decreases at the maxTime
            assertEq(curve.scheduledCurveChanges(nextInterval + curve.maxTime())[0], 0);
            assertEq(
                curve.scheduledCurveChanges(nextInterval + curve.maxTime())[1],
                -changeInSlope
            );
        }

        // user changes their mind to 1m
        curve.unsafeCheckpoint(
            matt,
            LockedBalance({start: nextInterval, amount: 500_000e18}),
            LockedBalance({start: nextInterval, amount: 1_000_000e18})
        );

        {
            // assertions:
            int baseSlope = curve.getCoefficients(1_000_000e18)[1];
            int changeInSlope = curve.getCoefficients(1_000_000e18)[1];
            uint expTotalVP = curve.getBias(3 days, 1_000_000e18);

            // current index is 2
            assertEq(curve.latestPointIndex(), 2, "index should be 2");

            // the first point has been applied at the prev interval
            GlobalPoint memory p0 = curve.pointHistory(0);
            assertEq(p0.ts, 0, "should not have written to 0th index");

            GlobalPoint memory p1 = curve.pointHistory(1);
            assertEq(p1.ts, prevInterval, "should have written to 1st index");

            assertEq(
                p1.coefficients[0] / 1e18,
                1_000_000e18,
                "should have written bias to 1st index"
            );
            assertEq(
                p1.coefficients[1] / 1e18,
                baseSlope,
                "should have written slope to 1st index"
            );

            GlobalPoint memory p2 = curve.pointHistory(2);

            // expect the coeff1 is the same and the bias is interpolated over 3 days
            assertEq(p2.ts, block.timestamp, "point 2 should be at current time");
            assertEq(p2.coefficients[1] / 1e18, baseSlope, "slope should be the same");
            assertEq(uint(p2.coefficients[0]) / 1e18, expTotalVP, "bias should be interpolated");

            // scheduled increases at the end of the week
            assertEq(curve.scheduledCurveChanges(nextInterval)[0], 1_000_000e18);
            assertEq(curve.scheduledCurveChanges(nextInterval)[1], changeInSlope);

            // scheduled decreases at the maxTime
            assertEq(curve.scheduledCurveChanges(nextInterval + curve.maxTime())[0], 0);
            assertEq(
                curve.scheduledCurveChanges(nextInterval + curve.maxTime())[1],
                -changeInSlope
            );
        }

        // user 3 deposits 1m ether exactly on week 5
        vm.warp(5 weeks);

        prevInterval = nextInterval;
        nextInterval = uint48(block.timestamp);
        curve.unsafeCheckpoint(
            phil,
            LockedBalance(0, 0),
            LockedBalance({start: nextInterval, amount: 1_000_000e18})
        );
        {
            // assertions:
            assertEq(curve.latestPointIndex(), 5, "index should be 5");

            // point 3 is when the prior deposit gets applied
            GlobalPoint memory p3 = curve.pointHistory(3);
            assertEq(p3.ts, prevInterval, "point 3 should be recorded at the prevInterval");
            // the slope should be the result of 2m ether now activated
            int slopeP3 = curve.getCoefficients(2_000_000e18)[1];
            assertEq(p3.coefficients[1] / 1e18, slopeP3, "slope should be the result of 2m ether");

            // the bias should be: 1m with 1 week of accrued voting power PLUS the extra m deposited
            // but with no accrued voting power on the extra m
            uint expBiasP3 = curve.getBias(1 weeks, 1_000_000e18) + 1_000_000e18;

            // sanity check this should be ~2.009 (according to python)
            assertLt(expBiasP3, 2_010_000e18, "bias should be under 2.01m");
            assertGt(expBiasP3, 2_009_000e18, "bias should be over 2.009m");

            assertEq(
                uint(p3.coefficients[0]) / 1e18,
                expBiasP3,
                "bias should be the sum of 1m and 2m"
            );

            // point 4 should be skipped
            GlobalPoint memory p4 = curve.pointHistory(4);
            assertEq(p4.ts, 0, "point 4 should not exist");

            // point 5 should be written
            GlobalPoint memory p5 = curve.pointHistory(5);

            assertEq(p5.ts, block.timestamp, "point 5 should be at current time");

            // the slope should be 3x 1m
            int slope = curve.getCoefficients(3_000_000e18)[1];
            assertEq(p5.coefficients[1] / 1e18, slope, "slope should be the result of 3m ether");

            // the bias should be 1m for 1 week (w2 -> w3)
            // 2m for 2 weeks (w3 -> w5)
            //           // + 1m new
            //           uint expBiasP5 = (curve.getBias(1 weeks, 1_000_000e18) - 1_000_000e18) + // marginal contribution of first deposit
            //               // marginal contribution of first + second deposit
            // // not sure this is correct
            //               (curve.getBias(2 weeks, 2_000_000e18) - 2_000_000e18) +
            //               // base qty in the contracts
            //               3_000_000e18;
            //
            //           assertEq(uint(p5.coefficients[0]) / 1e18, expBiasP5);
            //
            // we can calculate this another way:
            // evaluate the curve over the first week
            // then take the end state of that curve as the deposit for the next 2 weeks
            // then add that to the 1m
            uint w2To3 = curve.getBias(1 weeks, 1_000_000e18);
            console.log("w2To3", w2To3 + 1_000_000e18);
            uint w3To5 = curve.getBias(2 weeks, w2To3 + 1_000_000e18);
            console.log("w3To5", w3To5 + 1_000_000e18);
            uint w5 = w3To5 + 1_000_000e18;
            assertEq(uint(p5.coefficients[0]) / 1e18, w5);
        }
    }
}
