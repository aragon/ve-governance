pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {QuadraticIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/QuadraticIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";

import {QuadraticCurveBase} from "./QuadraticCurveBase.t.sol";

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
    function testWritesCheckpoint() public {
        uint tokenIdFirst = 1;
        uint tokenIdSecond = 2;
        uint depositFirst = 420.69e18;
        uint depositSecond = 1_000_000_000e18;
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
            LockedBalance(depositFirst, block.timestamp)
        );
        escrow.checkpoint(
            tokenIdSecond,
            LockedBalance(0, 0),
            LockedBalance(depositSecond, block.timestamp)
        );

        // check the user point is registered
        IEscrowCurve.UserPoint memory userPoint = curve.userPointHistory(tokenIdFirst, 1);
        assertEq(userPoint.bias, depositFirst, "Bias is incorrect");
        assertEq(userPoint.checkpointTs, block.timestamp, "CP Timestamp is incorrect");
        assertEq(userPoint.writtenTs, block.timestamp, "Written Timestamp is incorrect");

        // balance now is zero but Warm up
        assertEq(curve.votingPowerAt(tokenIdFirst, 0), 0, "Balance after deposit before warmup");
        assertEq(curve.isWarm(tokenIdFirst), false, "Not warming up");

        // wait for warmup
        vm.warp(block.timestamp + curve.warmupPeriod() - 1);
        assertEq(curve.votingPowerAt(tokenIdFirst, 0), 0, "Balance after deposit before warmup");
        assertEq(curve.isWarm(tokenIdFirst), false, "Not warming up");
        assertEq(curve.isWarm(tokenIdSecond), false, "Not warming up II");

        // warmup complete
        vm.warp(block.timestamp + 1);

        // excel:               449.206158900000000000
        // solmate:             449.206133622001394300
        // python:              449.206158892128337920
        // solmate (xmulx):     449.206133622001394304
        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            449206133622001394304,
            "Balance incorrect after warmup"
        );
        assertEq(curve.isWarm(tokenIdFirst), true, "Still warming up");

        // excel:     1_067_784_257_000000000000000000
        // solmate:   1_067_784_196_491481599990798396
        // python:    1_067_784_256_559766801878089728
        // solmate2:  1_067_784_196_491481600000000000
        assertEq(
            curve.votingPowerAt(tokenIdSecond, block.timestamp),
            1067784196491481600000000000,
            "Balance incorrect after warmup II"
        );

        // warp to the start of period 2
        vm.warp(start + clock.epochDuration());
        // excel:     600.985714300000000000
        // PRB:       600.985163959347100568
        // solmate:   600.985163959347101852
        // python :   600.985714285714341888
        // solmate2:  600.985163959347101952
        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            600985163959347101952,
            "Balance incorrect after p1"
        );

        uint256 expectedMaxI = 2524126241845405205760;
        uint256 expectedMaxII = 5999967296216704000000000000;

        // warp to the final period
        // TECHNICALLY, this should finish at exactly 5 periodd and 6 * voting power
        // but FP arithmetic has a small rounding error
        vm.warp(start + clock.epochDuration() * 5);
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
