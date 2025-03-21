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

        for (uint i; i <= 6; i++) {
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
0                              Voting Power: 1000000000000000013287555072 (1000000000)
1 minute                       Voting Power: 1000066137566137554101600256 (1000066138)
1 hour                         Voting Power: 1003968253968253973958754304 (1003968254)
1 day                          Voting Power: 1095238095238095344274243584 (1095238095)
WARMUP_PERIOD (3 days)         Voting Power: 1285714285714285731369713664 (1285714286)
WARMUP_PERIOD + 1s             Voting Power: 1285715388007054777427951616 (1285715388)
1 week                         Voting Power: 1666666666666666505560653824 (1666666667)
1 period (2 weeks)             Voting Power: 2333333333333332997833752576 (2333333333)
2 periods (2 * PERIOD)         Voting Power: 3666666666666666807013670912 (3666666667)
3 periods (3 * PERIOD)         Voting Power: 4999999999999999791559868416 (5000000000)
4 periods (4 * PERIOD)         Voting Power: 6333333333333332776106065920 (6333333333)
PERIOD_END (6 * PERIOD)        Voting Power: 8999999999999999844710088704 (9000000000)

==== Changing amount to 420.69 ====
0                              Voting Power: 420690000000000000000 (421)
1 minute                       Voting Power: 420717823412698349568 (421)
1 hour                         Voting Power: 422359404761904775168 (422)
1 day                          Voting Power: 460755714285714341888 (461)
WARMUP_PERIOD (3 days)         Voting Power: 540887142857142829056 (541)
WARMUP_PERIOD + 1s             Voting Power: 540887606580687798272 (541)
1 week                         Voting Power: 701149999999999934464 (701)
1 period (2 weeks)             Voting Power: 981609999999999934464 (982)
2 periods (2 * PERIOD)         Voting Power: 1542529999999999934464 (1543)
3 periods (3 * PERIOD)         Voting Power: 2103449999999999934464 (2103)
4 periods (4 * PERIOD)         Voting Power: 2664369999999999672320 (2664)
PERIOD_END (6 * PERIOD)        Voting Power: 3786210000000000196608 (3786)
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
            981609999999778324416,
            "Balance incorrect after p1"
        );

        assertEq(
            curve.votingPowerAt(tokenIdSecond, block.timestamp),
            2333333333332806400000000000,
            "Balance incorrect after p1 II"
        );

        uint256 expectedMaxI = 3786209999998669946496;
        uint256 expectedMaxII = 8999999999996838400000000000;

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
