pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {QuadraticCurveBase} from "./QuadraticCurveBase.t.sol";
import {Clock, QuadraticIncreasingEscrow, ILockedBalanceIncreasing, IVotingEscrowIncreasing as IVotingEscrow, IEscrowCurveIncreasing as IEscrowCurve} from "../../../versions.sol";

contract TestQuadraticIncreasingCurve is QuadraticCurveBase {
    function test_votingPowerComputesCorrect() public {
        /**
            Period	Result
          1	1
          2	1.428571429
          3	2.142857143
          4	3.142857143
          5	4.428571429
          6	6
         */
        uint256 amount = 100e18;

        int256[3] memory coefficients = curve.getCoefficients(100e18);

        uint256 const = uint256(coefficients[0]);
        uint256 linear = uint256(coefficients[1]);
        uint256 quadratic = uint256(coefficients[2]);

        assertEq(const, amount);

        console.log("Coefficients: %st^2 + %st + %s", quadratic, linear, const);

        for (uint i; i <= 12; i++) {
            uint period = 2 weeks * i;
            console.log(
                "Period: %d Voting Power      : %s",
                i,
                curve.getBias(period, 100e18) / 1e18
            );
            console.log(
                "Period: %d Voting Power Bound: %s",
                i,
                curve.getBias(period, 100e18) / 1e18
            );
            console.log("Period: %d Voting Power Raw: %s\n", i, curve.getBias(period, 100e18));
        }

        // uncomment to see the full curve
        // for (uint i; i <= 14 * 6; i++) {
        //     uint day = i * 1 days;
        //     uint week = day / 7 days;
        //     uint period = day / 2 weeks;

        //     console.log("[Day: %d | Week %d | Period %d]", i, week, period);
        //     console.log("Voting Power        : %s", curve.getBias(day, 100e18) / 1e18);
        //     console.log("Voting Power (raw): %s\n", curve.getBias(day, 100e18));
        // }
    }

    // write a new checkpoint
    /*
     * for the 1000 tokens (Python)  (extend to 1bn with more zeros)


0                              Voting Power: 1000000000000000013287555072
1 minute                       Voting Power: 1000028935185185204573569024
1 hour                         Voting Power: 1001736111111111215570485248
1 day                          Voting Power: 1041666666666666806493577216
WARMUP_PERIOD (3 days)         Voting Power: 1124999999999999980588761088
WARMUP_PERIOD + 1s             Voting Power: 1125000482253086386699632640
1 week                         Voting Power: 1291666666666666878534942720
1 period (2 weeks)             Voting Power: 1583333333333333468904423424
2 periods (2 * PERIOD)         Voting Power: 2166666666666666924521291776
3 periods (3 * PERIOD)         Voting Power: 2749999999999999830382346240
4 periods (4 * PERIOD)         Voting Power: 3333333333333333560877121536
PERIOD_END (12 * PERIOD)       Voting Power: 8000000000000000106300440576
     

0                              Voting Power: 420690000000000000000
1 minute                       Voting Power: 420702172743055572992
1 hour                         Voting Power: 421420364583333330944
1 day                          Voting Power: 438218750000000008192
WARMUP_PERIOD (3 days)         Voting Power: 473276250000000024576
WARMUP_PERIOD + 1s             Voting Power: 473276452879050866688
1 week                         Voting Power: 543391250000000057344
1 period (2 weeks)             Voting Power: 666092500000000049152
2 periods (2 * PERIOD)         Voting Power: 911495000000000163840
3 periods (3 * PERIOD)         Voting Power: 1156897500000000016384
4 periods (4 * PERIOD)         Voting Power: 1402300000000000131072
PERIOD_END (12 * PERIOD)       Voting Power: 3365520000000000000000

*/
    function testWritesCheckpoint() public {
        uint tokenIdFirst = 1;
        uint tokenIdSecond = 2;
        uint208 depositFirst = 420.69e18;
        uint208 depositSecond = 1_000_000_000e18;
        uint start = 52 weeks;

        // initial conditions, no balance
        assertEq(curve.votingPowerAt(tokenIdFirst, 0), 0, "Balance before deposit");

        vm.warp(start);
        vm.roll(420);

        // still no balance
        assertEq(curve.votingPowerAt(tokenIdFirst, 0), 0, "Balance before deposit");

        escrow.checkpoint(
            tokenIdFirst,
            LockedBalance(0, 0),
            LockedBalance(depositFirst, uint48(block.timestamp))
        );
        escrow.checkpoint(
            tokenIdSecond,
            LockedBalance(0, 0),
            LockedBalance(depositSecond, uint48(block.timestamp))
        );

        // check the token point is registered
        IEscrowCurve.TokenPoint memory tokenPoint = curve.tokenPointHistory(tokenIdFirst, 1);
        assertEq(tokenPoint.bias, depositFirst, "Bias is incorrect");
        assertEq(tokenPoint.checkpointTs, block.timestamp, "CP Timestamp is incorrect");
        assertEq(tokenPoint.writtenTs, block.timestamp, "Written Timestamp is incorrect");

        // balance now is zero but Warm up
        assertEq(curve.votingPowerAt(tokenIdFirst, 0), 0, "Balance after deposit before warmup");
        assertEq(curve.isWarm(tokenIdFirst), false, "Not warming up");

        // wait for warmup
        vm.warp(block.timestamp + curve.warmupPeriod());
        assertEq(curve.votingPowerAt(tokenIdFirst, 0), 0, "Balance after deposit before warmup");
        assertEq(curve.isWarm(tokenIdFirst), false, "Not warming up");
        assertEq(curve.isWarm(tokenIdSecond), false, "Not warming up II");

        // warmup complete
        vm.warp(block.timestamp + 1);

        // warp to the start of period 2
        vm.warp(start + clock.epochDuration());
        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            666092499999616779456,
            "Balance incorrect after p1"
        );

        assertEq(
            curve.votingPowerAt(tokenIdSecond, block.timestamp),
            1583333333332422400000000000,
            "Balance incorrect after p1 II"
        );

        uint256 expectedMaxI = 3365519999995401353472;
        uint256 expectedMaxII = 7999999999989068800000000000;

        // warp to the final period
        // TECHNICALLY, this should round to a whole max
        // but FP arithmetic has a small rounding error and it finishes just below
        vm.warp(start + clock.epochDuration() * 12);
        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            expectedMaxI,
            "Balance incorrect after max"
        );
        assertEq(
            curve.votingPowerAt(tokenIdSecond, block.timestamp),
            expectedMaxII,
            "Balance incorrect after max II "
        );

        // warp to the future and balance should be the same
        vm.warp(520 weeks);
        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            expectedMaxI,
            "Balance incorrect after 10 years"
        );
    }
}
