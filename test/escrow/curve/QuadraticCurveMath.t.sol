pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {QuadraticIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/QuadraticIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";

import {QuadraticCurveBase} from "./QuadraticCurveBase.t.sol";

contract TestQuadraticIncreasingCurve is QuadraticCurveBase {
    function test_votingPowerComputesCorrect() public {
        uint256 amount = 100e18;

        int256[3] memory coefficients = curve.getCoefficients(100e18);

        uint256 const = uint256(coefficients[0]);
        uint256 linear = uint256(coefficients[1]);
        uint256 quadratic = uint256(coefficients[2]);

        assertEq(const, amount);

        console.log("Coefficients: %st^2 + %st + %s", quadratic, linear, const);

        for (uint i; i <= 52 * 3 + 2; i++) {
            uint period = 1 weeks * i;
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

        // excel:              420.6904013
        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            420690414675862320286,
            "Balance incorrect after warmup"
        );
        assertEq(curve.isWarm(tokenIdFirst), true, "Still warming up");

        // excel:    1000000.954
        assertEq(
            curve.votingPowerAt(tokenIdSecond, block.timestamp),
            1000000985704110676000000000,
            "Balance incorrect after warmup II"
        );

        // warp to the start of period 2
        vm.warp(start + clock.epochDuration());
        // excel:     436.8703846
        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            436870384614923176704,
            "Balance incorrect after p1"
        );

        // check at 6 months
        vm.warp(start + 26 weeks);
        // excel:     631.035
        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            631034999994001297152,
            "Balance incorrect after p1"
        );

        // check at 2 years
        vm.warp(start + 104 weeks);
        // excel:     1262.07
        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            1262069999976005188608,
            "Balance incorrect after p1"
        );

        // 1682.76
        uint256 expectedMaxI = 1682759999964007782912;
        // 4000000
        uint256 expectedMaxII = 3999999999914444800000000000;

        // warp to the final period
        // TECHNICALLY, this should finish at exactly 5 periodd and 6 * voting power
        // but FP arithmetic has a small rounding error
        vm.warp(start + 3 * 52 weeks);
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
