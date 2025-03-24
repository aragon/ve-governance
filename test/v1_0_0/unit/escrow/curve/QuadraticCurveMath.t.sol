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

==== VP for 1000000000 ====
0                              Voting Power: 1000000000000000013287555072 | 1000000000 | 1.00x
1 minute                       Voting Power: 1000057870370370395859582976 | 1000057870 | 1.00x
1 hour                         Voting Power: 1003472222222222280414461952 | 1003472222 | 1.00x
1 day                          Voting Power: 1083333333333333324821692416 | 1083333333 | 1.08x
WARMUP_PERIOD (3 days)         Voting Power: 1249999999999999947889967104 | 1250000000 | 1.25x
WARMUP_PERIOD + 1s             Voting Power: 1250000964506172760111710208 | 1250000965 | 1.25x
1 week                         Voting Power: 1583333333333333468904423424 | 1583333333 | 1.58x
1 period (2 weeks)             Voting Power: 2166666666666666924521291776 | 2166666667 | 2.17x
2 periods (2 * PERIOD)         Voting Power: 3333333333333333560877121536 | 3333333333 | 3.33x
3 periods (3 * PERIOD)         Voting Power: 4499999999999999922355044352 | 4500000000 | 4.50x
4 periods (4 * PERIOD)         Voting Power: 5666666666666667383344594944 | 5666666667 | 5.67x
PERIOD_END (6 * PERIOD)        Voting Power: 8000000000000000106300440576 | 8000000000 | 8.00x

==== Changing amount to 420.69 ====
0                              Voting Power: 420690000000000000000 | 421 | 1.00x
1 minute                       Voting Power: 420714345486111145984 | 421 | 1.00x
1 hour                         Voting Power: 422150729166666727424 | 422 | 1.00x
1 day                          Voting Power: 455747499999999950848 | 456 | 1.08x
WARMUP_PERIOD (3 days)         Voting Power: 525862499999999983616 | 526 | 1.25x
WARMUP_PERIOD + 1s             Voting Power: 525862905758101798912 | 526 | 1.25x
1 week                         Voting Power: 666092500000000049152 | 666 | 1.58x
1 period (2 weeks)             Voting Power: 911495000000000163840 | 911 | 2.17x
2 periods (2 * PERIOD)         Voting Power: 1402300000000000131072 | 1402 | 3.33x
3 periods (3 * PERIOD)         Voting Power: 1893105000000000098304 | 1893 | 4.50x
4 periods (4 * PERIOD)         Voting Power: 2383910000000000065536 | 2384 | 5.67x
PERIOD_END (6 * PERIOD)        Voting Power: 3365520000000000000000 | 3366 | 8.00x

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
            911494999999742425536,
            "Balance incorrect after p1"
        );

        assertEq(
            curve.votingPowerAt(tokenIdSecond, block.timestamp),
            2166666666666054400000000000,
            "Balance incorrect after p1 II"
        );

        uint256 expectedMaxI = 3365519999998454553216;
        uint256 expectedMaxII = 7999999999996326400000000000;

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
