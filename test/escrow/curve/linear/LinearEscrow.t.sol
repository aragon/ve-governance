// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {LinearIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/LinearIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";

import {LinearCurveBase} from "./LinearBase.sol";
contract TestLinearIncreasingCurve is LinearCurveBase {
    /// checkpoint

    // check the token id must be passed

    // check we can't support and inreasing curve

    // check we can't support same deposits

    /// writing the point

    // overwrites the last point if the timestamp is the same

    // correctly writes a new point if the timestamp is different

    /// putting it together

    // complex state with a couple of user points written over time - check that supply can be checked

    function test_votingPowerComputesCorrect() public view {
        uint256 amount = 100e18;

        int256[3] memory coefficients = curve.getCoefficients(100e18);

        uint256 const = uint256(coefficients[0]);
        uint256 linear = uint256(coefficients[1]);
        uint256 quadratic = uint256(coefficients[2]);

        assertEq(const, amount);
        //
        // console.log("Coefficients: %st^2 + %st + %s", quadratic, linear, const);
        //
        // for (uint i; i <= 53; i++) {
        //     uint period = 2 weeks * i;
        //     console.log(
        //         "Period: %d Voting Power      : %s",
        //         i,
        //         curve.getBias(period, 100e18) / 1e18
        //     );
        //     console.log(
        //         "Period: %d Voting Power Bound: %s",
        //         i,
        //         curve.getBias(period, 100e18) / 1e18
        //     );
        //     console.log("Period: %d Voting Power Raw: %s\n", i, curve.getBias(period, 100e18));
        // }

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
     * 0                              Voting Power: 1000000000000000000000
     * 1 minute                       Voting Power: 1000000953907203932160
     * 1 hour                         Voting Power: 1000057234432234487808
     * 1 day                          Voting Power: 1001373626373626396672
     * WARMUP_PERIOD (3 days)         Voting Power: 1004120879120879058944
     * WARMUP_PERIOD + 1s             Voting Power: 1004120895019332534272
     * 1 week                         Voting Power: 1009615384615384645632
     * 1 period (2 weeks)             Voting Power: 1019230769230769160192
     * 10 periods (10 * PERIOD)       Voting Power: 1192307692307692388352
     * 50% periods (26 * PERIOD)      Voting Power: 1500000000000000000000
     * 35 periods (35 * PERIOD)       Voting Power: 1673076923076923097088
     * PERIOD_END (26 * PERIOD)       Voting Power: 2000000000000000000000
     
     * for the 420.69 tokens (Python)
     * 0                              Voting Power: 420690000000000000000
     * 1 minute                       Voting Power: 420690401299221577728
     * 1 hour                         Voting Power: 420714077953296695296
     * 1 day                          Voting Power: 421267870879120883712
     * WARMUP_PERIOD (3 days)         Voting Power: 422423612637362651136
     * WARMUP_PERIOD + 1s             Voting Power: 422423619325683040256
     * 1 week                         Voting Power: 424735096153846120448
     * 1 period (2 weeks)             Voting Power: 428780192307692306432
     * 10 periods (10 * PERIOD)       Voting Power: 501591923076923064320
     * 50% periods (26 * PERIOD)      Voting Power: 631035000000000032768
     * 35 periods (35 * PERIOD)       Voting Power: 703846730769230856192
     * PERIOD_END (26 * PERIOD)       Voting Power: 841380000000000000000
     */
    function testWritesCheckpointLinear() public {
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

        // warp to the start of period 2
        vm.warp(start + clock.epochDuration());
        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            428780192307461588352,
            "Balance incorrect after p1"
        );

        uint256 expectedMaxI = 841379999988002594304;
        uint256 expectedMaxII = 1999999999971481600000000000;

        // warp to the final period
        // TECHNICALLY, this should round to a whole max
        // but FP arithmetic has a small rounding error and it finishes just below
        vm.warp(start + clock.epochDuration() * 52);
        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            expectedMaxI,
            "Balance incorrect after pend"
        );
        assertEq(
            curve.votingPowerAt(tokenIdSecond, block.timestamp),
            expectedMaxII,
            "Balance incorrect after pend II "
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
