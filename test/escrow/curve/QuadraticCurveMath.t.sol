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

        int256[4] memory coefficients = curve.getCoefficients(100e18);

        uint256 const = uint256(coefficients[0]);
        uint256 linear = uint256(coefficients[1]);
        uint256 quadratic = uint256(coefficients[2]);
        uint256 cubic = uint256(coefficients[3]);

        assertEq(const, amount);
        assertEq(cubic, 0);

        console.log("Coefficients: %st^2 + %st + %s", quadratic, linear, const);

        for (uint i; i <= 6; i++) {
            uint period = 2 weeks * i;
            console.log(
                "Period: %d Voting Power      : %s",
                i,
                curve.getBiasUnbound(period, 100e18) / 1e18
            );
            console.log(
                "Period: %d Voting Power Bound: %s",
                i,
                curve.getBias(period, 100e18) / 1e18
            );
            console.log(
                "Period: %d Voting Power Raw: %s\n",
                i,
                curve.getBiasUnbound(period, 100e18)
            );
        }

        // uncomment to see the full curve
        // for (uint i; i <= 14 * 6; i++) {
        //     uint day = i * 1 days;
        //     uint week = day / 7 days;
        //     uint period = day / 2 weeks;

        //     console.log("[Day: %d | Week %d | Period %d]", i, week, period);
        //     console.log("Voting Power        : %s", curve.getBiasUnbound(day, 100e18) / 1e18);
        //     console.log("Voting Power (bound): %s\n", curve.getBias(day, 100e18, 600e18) / 1e18);
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
        assertEq(userPoint.ts, block.timestamp, "Timestamp is incorrect");
        assertEq(userPoint.blk, block.number, "Block is incorrect");

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
        // excel:      449.206279600000000000
        // PRB:        449.206254284606635092
        // solmate:    449.206254284606635132
        // for context that's 1/10k of a token
        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            449206254284606635132,
            "Balance incorrect after warmup"
        );
        assertEq(curve.isWarm(tokenIdFirst), true, "Still warming up");

        // excel:     106.7784543000000000000000000
        // PRB:       106.7784483312193384896522473
        // solmate:   106.7784483312193384992025326
        assertEq(
            curve.votingPowerAt(tokenIdSecond, block.timestamp),
            1067784483312193384992025326,
            "Balance incorrect after warmup II"
        );

        // warp to the start of period 2
        vm.warp(start + curve.period());
        // excel:     600.985714300000000000
        // PRB:       600.985163959347100568
        // solmate:   600.985163959347101852
        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            600985163959347101852,
            "Balance incorrect after p1"
        );

        // warp to the final period
        // TECHNICALLY, this should finish at exactly 5 periods but
        // 30 seconds off is okay
        vm.warp(start + curve.period() * 5 + 30);
        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            6 * depositFirst,
            "Balance incorrect after p6"
        );
        assertEq(
            curve.votingPowerAt(tokenIdSecond, block.timestamp),
            6 * depositSecond,
            "Balance incorrect after p6 II "
        );

        // warp to the future and balance should be the same
        vm.warp(520 weeks);
        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            6 * depositFirst,
            "Balance incorrect after 10 years"
        );
    }
}
