pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {CurveBase} from "./CurveBase.t.sol";
import {
    IClock,
    Clock,
    Curve,
    ILockedBalanceIncreasing,
    IVotingEscrowIncreasing as IVotingEscrow,
    IEscrowCurveIncreasing as IEscrowCurve
} from "../../../versions.sol";

contract TestIncreasingCurve is CurveBase {
    using SafeCast for uint256;

    function test_votingPowerComputesCorrect() public view {
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

    /**


==== VP for 1000000000 ====
0                              Voting Power: 1000000000000000013287555072 | 1000000000 | 1.00x
1 minute                       Voting Power: 1000000953907203852728270848 | 1000000954 | 1.00x
1 hour                         Voting Power: 1000057234432234502899105792 | 1000057234 | 1.00x
1 day                          Voting Power: 1001373626373626389575237632 | 1001373626 | 1.00x
WARMUP_PERIOD (3 days)         Voting Power: 1004120879120879142150602752 | 1004120879 | 1.00x
WARMUP_PERIOD + 1s             Voting Power: 1004120895019332532602667008 | 1004120895 | 1.00x
1 week                         Voting Power: 1009615384615384647301332992 | 1009615385 | 1.01x
1 period (2 weeks)             Voting Power: 1019230769230769143876157440 | 1019230769 | 1.02x
2 periods (2 * PERIOD)         Voting Power: 1038461538461538549342666752 | 1038461538 | 1.04x
3 periods (3 * PERIOD)         Voting Power: 1057692307692307679931269120 | 1057692308 | 1.06x
4 periods (4 * PERIOD)         Voting Power: 1076923076923076947958824960 | 1076923077 | 1.08x
END @ 104 weeks (52 * PERIOD)  Voting Power: 2000000000000000026575110144 | 2000000000 | 2.00x

==== Changing amount to 420.69 ====
0                              Voting Power: 420690000000000000000 | 421 | 1.00x
1 minute                       Voting Power: 420690401299221577728 | 421 | 1.00x
1 hour                         Voting Power: 420714077953296695296 | 421 | 1.00x
1 day                          Voting Power: 421267870879120883712 | 421 | 1.00x
WARMUP_PERIOD (3 days)         Voting Power: 422423612637362651136 | 422 | 1.00x
WARMUP_PERIOD + 1s             Voting Power: 422423619325683040256 | 422 | 1.00x
1 week                         Voting Power: 424735096153846120448 | 425 | 1.01x
1 period (2 weeks)             Voting Power: 428780192307692306432 | 429 | 1.02x
2 periods (2 * PERIOD)         Voting Power: 436870384615384678400 | 437 | 1.04x
3 periods (3 * PERIOD)         Voting Power: 444960576923076919296 | 445 | 1.06x
4 periods (4 * PERIOD)         Voting Power: 453050769230769225728 | 453 | 1.08x
END @ 104 weeks (52 * PERIOD)  Voting Power: 841380000000000000000 | 841 | 2.00x

**/
    function testWritesCheckpoint() public {
        uint tokenIdFirst = 1;
        uint tokenIdSecond = 2;
        uint208 depositFirst = 420.69e18;
        uint208 depositSecond = 1_000_000_000e18;
        
        // add + 1seconds so it doesn't get to 
        // be exact checkpointInterval.
        uint start = 52 weeks + 1 hours;

        // initial conditions, no balance
        assertEq(curve.votingPowerAt(tokenIdFirst, 0), 0, "Balance before deposit");

        vm.warp(start);

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

        assertEq(curve.isWarm(tokenIdFirst), true, "Not warming up");
        
        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            422423619325633557508,
            "Balance incorrect after warmup"
        );
        assertEq(curve.isWarm(tokenIdFirst), true, "Still warming up");

        assertEq(
            curve.votingPowerAt(tokenIdSecond, block.timestamp),
            1004120895019214998000000000,
            "Balance incorrect after warmup II"
        );

        uint256 expectedMaxI = 841379999988002594304;
        uint256 expectedMaxII = 1999999999971481600000000000;

        // warp to the final period
        // TECHNICALLY, this should finish at exactly max
        // but FP arithmetic has a small rounding error
        vm.warp(start + clock.epochDuration() * 52);
        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            expectedMaxI,
            "Balance incorrect after p6"
        );
        assertEq(
            curve.votingPowerAt(tokenIdSecond, block.timestamp),
            expectedMaxII,
            "Balance incorrect after p6 II "
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
