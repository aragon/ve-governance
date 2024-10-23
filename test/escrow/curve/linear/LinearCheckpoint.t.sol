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
    // wait until end of max period
    // user 1 exits at week interval
    // user 3 exits same time
    // so: deposit 1m starting @ week 2
    // deposit 1m starting @ week 3
    // deposit 1m starting @ week 5
    // a spreadsheet of the voting power w. visuals is here:
    // https://docs.google.com/spreadsheets/d/1KLoo1vBZDvYRwcUKfomZhfT4fiANEEWqm092efuaacg/edit?usp=sharing
    function testCheckpoint() public {
        uint shane = 1;
        uint matt = 2;
        uint phil = 3;

        LockedBalance memory shaneLastLock;
        LockedBalance memory mattLastLock;

        vm.warp(1 weeks + 1 days);

        // get the next cp interval
        uint48 nextInterval = uint48(clock.epochNextCheckpointTs());

        shaneLastLock = LockedBalance({start: nextInterval, amount: 1_000_000e18});

        curve.unsafeCheckpoint(shane, LockedBalance(0, 0), shaneLastLock);

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

        mattLastLock = LockedBalance({start: nextInterval, amount: 500_000e18});

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

        mattLastLock = LockedBalance({start: nextInterval, amount: 1_000_000e18});

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
            // GlobalPoint memory p4 = curve.pointHistory(4);
            // assertEq(p4.ts, 0, "point 4 should not exist");
            //
            // point 5 should be written
            GlobalPoint memory p5 = curve.pointHistory(5);

            assertEq(p5.ts, block.timestamp, "point 5 should be at current time");

            // the slope should be 3x 1m
            int slope = curve.getCoefficients(3_000_000e18)[1];
            assertEq(p5.coefficients[1] / 1e18, slope, "slope should be the result of 3m ether");

            // we should be able to sum the user biases to get to the total
            uint shaneBias = curve.getBias(3 weeks, 1_000_000e18);
            uint mattBias = curve.getBias(2 weeks, 1_000_000e18);
            uint philBias = curve.getBias(0, 1_000_000e18);

            assertEq(uint(p5.coefficients[0]) / 1e18, shaneBias + mattBias + philBias);

            // sanity check from excel: should be ~3,048,077
            assertGt(uint(p5.coefficients[0]) / 1e18, 3_048_076e18, "bias p5 sanity check");
            assertLt(uint(p5.coefficients[0]) / 1e18, 3_048_078e18, "bias p5 sanity check");
        }

        // user 1 reduces later in the same block to 0.5m
        curve.unsafeCheckpoint(
            1,
            shaneLastLock,
            LockedBalance({start: shaneLastLock.start, amount: 500_000e18})
        );
        {
            // we should not have changed the index
            assertEq(curve.latestPointIndex(), 5, "index should be 5");

            // point 5 should be the same ts
            GlobalPoint memory p5 = curve.pointHistory(5);
            assertEq(p5.ts, block.timestamp, "point 5 should be at current time");

            // point 5 slope has decreased by 500k worth
            int expSlope = curve.getCoefficients(2_500_000e18)[1];
            int k500Slope = curve.getCoefficients(500_000e18)[1];
            assertEq(p5.coefficients[1] / 1e18, expSlope, "slope should be 2.5m");
            // point 5 bias is same as before -500k voting power accumulated
            // TODO think deeply about this - is it correct that it's a straight reduction
            // or should there bshaneNewBiascumulation?

            uint shaneNewBias = curve.getBias(3 weeks, 500_000e18);
            uint mattBias = curve.getBias(2 weeks, 1_000_000e18);
            uint philBias = curve.getBias(0, 1_000_000e18);
            uint newBias = shaneNewBias + mattBias + philBias;

            assertEq(uint(p5.coefficients[0]) / 1e18, newBias, "bias should be og bias - 500k");

            // the scheduled changes to the curve at the original end have been increased accordingly
            assertEq(
                curve.scheduledCurveChanges(shaneLastLock.start + curve.maxTime())[1],
                -k500Slope // was a million, now 500k
            );
        }

        // user 2 exits mid week
        vm.warp(5 weeks + 3 days);

        curve.unsafeCheckpoint(
            2,
            mattLastLock,
            LockedBalance({start: mattLastLock.start, amount: 0})
        );

        {
            //  assert a point written at ts
            assertEq(curve.latestPointIndex(), 6, "index should be 6");
            GlobalPoint memory p6 = curve.pointHistory(6);
            assertEq(p6.ts, block.timestamp, "point 6 should be at current time");

            // check basically the above
            // point 6 slope decreased by a milly
            int expSlope = curve.getCoefficients(1_500_000e18)[1];
            assertEq(p6.coefficients[1] / 1e18, expSlope, "slope should be 1.5m");

            // point 6 bias should be just be shane's half and phils
            uint shaneNewBias = curve.getBias(3 weeks + 3 days, 500_000e18);
            uint philBias = curve.getBias(3 days, 1_000_000e18);

            assertEq(
                uint(p6.coefficients[0]) / 1e18,
                shaneNewBias + philBias,
                "bias should be shane and phil"
            );

            // the scheduled changes to the curve at the original end have been increased accordingly
            assertEq(
                curve.scheduledCurveChanges(mattLastLock.start + curve.maxTime())[1],
                0 // was a million, now 0
            );
        }

        // wait until end of max period - we should now see that voting power has capped off for shane and phil
        // shane should have maxxed out 2y from his first withdrawal, there's a gap where phil will still
        // increase so let's inspect that
        vm.warp(2 weeks + curve.maxTime());
        curve.unsafeManualCheckpoint();
        {
            // last cp was 6
            // we've advanced 104 - 3 weeks from last CP (101)
            // +6 = 107
            assertEq(curve.latestPointIndex(), 107, "index should be 107");

            // should have sparse array from 7 to 106
            for (uint i = 7; i < 107; i++) {
                assertGt(curve.pointHistory(i).ts, 0, "point should not be empty");
                // assertEq(curve.pointHistory(i).ts, 0, "point should be empty");
            }

            // fetch the latest point
            GlobalPoint memory p107 = curve.pointHistory(107);

            assertEq(p107.ts, block.timestamp, "point 107 should be at current time");
            // expect the slope has now DECREASED as we've hit shane's max

            assertEq(
                p107.coefficients[1] / 1e18,
                curve.getCoefficients(1_000_000e18)[1],
                "slope should have now removed shane's deposit"
            );

            // we would expect shane's bias to be the maxxed
            uint shaneExpBias = curve.getBias(curve.maxTime(), 500_000e18);

            // phil deposited at 5 weeks, so he should still be increasing
            uint philBias = curve.getBias(curve.maxTime() - 3 weeks, 1_000_000e18);

            uint expectedBias = shaneExpBias + philBias;
            assertEq(
                uint(p107.coefficients[0]) / 1e18,
                expectedBias,
                "bias of max shane and <max phil"
            );
        }

        // move forward 3 weeks and 1 day. The curve is now static
        vm.warp(5 weeks + 1 days + curve.maxTime());
        curve.unsafeManualCheckpoint();

        {
            // point will be 111
            assertEq(curve.latestPointIndex(), 111, "index should be 111");

            // sparse check, up to 110 b/c that's the scheduled change
            // for (uint i = 108; i < 110; i++) {
            //     assertEq(curve.pointHistory(i).ts, 0, "point should be empty");
            // }
            //
            // fetch the latest points
            GlobalPoint memory p110 = curve.pointHistory(110);

            // p110 should be at the week interval
            assertEq(
                p110.ts,
                5 weeks + curve.maxTime(),
                "point 110 should be at the week interval"
            );

            // expect the slope to be zero
            assertEq(p110.coefficients[1] / 1e18, 0, "no further changes should be happening");

            GlobalPoint memory p111 = curve.pointHistory(111);

            assertEq(p111.ts, block.timestamp, "point 111 should be at current time");

            // expect the slope is now zero
            assertEq(p111.coefficients[1] / 1e18, 0, "no further changes should be happening");

            // we would expect shane's bias to be the maxxed
            uint shaneExpBias = curve.getBias(curve.maxTime(), 500_000e18);

            // phil deposited at 5 weeks, so he should still be increasing
            uint philBias = curve.getBias(curve.maxTime(), 1_000_000e18);

            uint expectedBias = shaneExpBias + philBias;
            assertEq(
                uint(p111.coefficients[0]) / 1e18,
                expectedBias,
                "bias of max shane and max phil"
            );

            // double check both biases are equal
            assertEq(p110.coefficients[0], p111.coefficients[0], "both biases should be equal");
        }

        // exit both parties and see that the curve is emptied
        curve.unsafeCheckpoint(
            shane,
            LockedBalance({start: shaneLastLock.start, amount: 500_000e18}),
            LockedBalance({start: shaneLastLock.start, amount: 0})
        );
        curve.unsafeCheckpoint(
            phil,
            LockedBalance({start: 5 weeks, amount: 1_000_000e18}),
            LockedBalance({start: 5 weeks, amount: 0})
        );
        {
            // we expect the checkpoint hasn't increased
            assertEq(curve.latestPointIndex(), 111, "index should be 111");

            // fetch the latest point
            GlobalPoint memory p111 = curve.pointHistory(111);

            //slope and bias should be zero
            assertEq(p111.coefficients[1] / 1e18, 0, "slope should be zero");
            assertEq(p111.coefficients[0] / 1e18, 0, "bias should be zero");
        }

        // lets query total supply
        {
            // at week 1, I expect nothing
            uint totalVotingPower = curve.supplyAt(1 weeks);

            assertEq(totalVotingPower, 0, "total voting power should be 0");

            // at week 2, I expect 1m
            totalVotingPower = curve.supplyAt(2 weeks);

            assertEq(totalVotingPower, 1_000_000e18, "total voting power should be 1m");

            // at week 2.5 I expect shane + 0.5 of a week
            totalVotingPower = curve.supplyAt(2 weeks + 3 days);

            assertEq(
                totalVotingPower,
                curve.getBias(3 days, 1_000_000e18),
                "total voting power should be 1m + 0.5w"
            );

            // at week 3, I expect shane + matt
            totalVotingPower = curve.supplyAt(3 weeks);

            uint shaneBias = curve.getBias(1 weeks, 1_000_000e18);
            uint mattBias = curve.getBias(0, 1_000_000e18);

            assertEq(totalVotingPower, shaneBias + mattBias, "total voting power w3");

            // at week 4 I expect shane + 2 weeks, matt + 1 week

            totalVotingPower = curve.supplyAt(4 weeks);

            shaneBias = curve.getBias(2 weeks, 1_000_000e18);
            mattBias = curve.getBias(1 weeks, 1_000_000e18);

            assertEq(totalVotingPower, shaneBias + mattBias, "total voting power w4");

            // at week 5 I expect shane + 3 weeks, matt + 2 weeks, phil + 0 weeks

            totalVotingPower = curve.supplyAt(5 weeks);

            // shane reduced!
            shaneBias = curve.getBias(3 weeks, 500_000e18);
            mattBias = curve.getBias(2 weeks, 1_000_000e18);
            uint philBias = curve.getBias(0, 1_000_000e18);

            assertEq(totalVotingPower, shaneBias + mattBias + philBias, "total voting power w5");

            // at week 5.5 I expect shane + 3.5 weeks, matt + 2.5 weeks, phil + 0.5 weeks

            totalVotingPower = curve.supplyAt(5 weeks + 2 days);

            shaneBias = curve.getBias(3 weeks + 2 days, 500_000e18);
            mattBias = curve.getBias(2 weeks + 2 days, 1_000_000e18);
            philBias = curve.getBias(2 days, 1_000_000e18);

            assertEq(totalVotingPower, shaneBias + mattBias + philBias, "total voting power w5.5");

            // at 5.5 (4 days) expect the exit to have kicked in for matt

            totalVotingPower = curve.supplyAt(5 weeks + 4 days);

            shaneBias = curve.getBias(3 weeks + 4 days, 500_000e18);
            mattBias = 0;
            philBias = curve.getBias(4 days, 1_000_000e18);

            assertEq(totalVotingPower, shaneBias + mattBias + philBias, "total voting power w5.5");

            // at week 106 I expect shane maxed out, phil at max - 3 weeks

            totalVotingPower = curve.supplyAt(106 weeks);

            shaneBias = curve.getBias(curve.maxTime(), 500_000e18);
            philBias = curve.getBias(curve.maxTime() - 3 weeks, 1_000_000e18);

            assertEq(totalVotingPower, shaneBias + philBias, "total voting power w106");

            // at week 106.5 I expect shane maxed out, phil at max - 2.5 weeks

            totalVotingPower = curve.supplyAt(106 weeks + 3 days);

            shaneBias = curve.getBias(curve.maxTime(), 500_000e18);
            philBias = curve.getBias(curve.maxTime() - 2 weeks - 4 days, 1_000_000e18);

            assertEq(totalVotingPower, shaneBias + philBias, "total voting power w106.5");

            // at week 109 + 1 day - 1 I expect shane maxed out, phil maxed out

            totalVotingPower = curve.supplyAt(109 weeks + 1 days - 1);

            shaneBias = curve.getBias(curve.maxTime(), 500_000e18);
            philBias = curve.getBias(curve.maxTime(), 1_000_000e18);

            assertEq(totalVotingPower, shaneBias + philBias, "total voting power w109 + 1 day - 1");

            // at week 109 + 1 day I expect zero

            totalVotingPower = curve.supplyAt(109 weeks + 1 days);

            assertEq(totalVotingPower, 0, "total voting power w109 + 1 day");
        }
    }
}
