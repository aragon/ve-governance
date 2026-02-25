pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IClock} from "@clock/IClock.sol";
import {QuadraticCurveBase} from "./QuadraticCurveBase.t.sol";
import {
    Clock,
    QuadraticIncreasingEscrow,
    ILockedBalanceIncreasing,
    IVotingEscrowIncreasing as IVotingEscrow,
    IEscrowCurveIncreasing as IEscrowCurve
} from "../../../versions.sol";

contract TestQuadraticIncreasingCurve is QuadraticCurveBase {
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

    function testWritesCheckpoint() public {
        uint tokenIdFirst = 1;
        uint tokenIdSecond = 2;
        uint208 depositFirst = 420.69e18;
        uint208 depositSecond = 1_000_000_000e18;
        uint start = 52 weeks + 1 hours;

        // initial conditions, no balance
        assertEq(curve.votingPowerAt(tokenIdFirst, 0), 0, "Balance before deposit");

        vm.warp(start);

        // still no balance
        assertEq(curve.votingPowerAt(tokenIdFirst, 0), 0, "Balance before deposit");

        uint256 checkpointTs = clock.epochNextCheckpointIn();
        uint256 writtenTs = block.timestamp;

        escrow.checkpoint(
            tokenIdFirst,
            LockedBalance(0, 0),
            LockedBalance(depositFirst, uint48(checkpointTs))
        );
        escrow.checkpoint(
            tokenIdSecond,
            LockedBalance(0, 0),
            LockedBalance(depositSecond, uint48(checkpointTs))
        );

        // check the token point is registered
        IEscrowCurve.TokenPoint memory tokenPoint = curve.tokenPointHistory(tokenIdFirst, 1);
        assertEq(tokenPoint.bias, depositFirst, "Bias is incorrect");
        assertEq(tokenPoint.checkpointTs, checkpointTs, "CP Timestamp is incorrect");
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
            curve.getBias(block.timestamp - checkpointTs, depositFirst),
            "Balance incorrect after warmup"
        );
        assertEq(curve.isWarm(tokenIdFirst), true, "Still warming up");

        assertEq(
            curve.votingPowerAt(tokenIdSecond, block.timestamp),
            curve.getBias(block.timestamp - checkpointTs, depositSecond),
            "Balance incorrect after warmup II"
        );

        // warp to the start of period 2
        vm.warp(start + clock.epochDuration());
        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            curve.getBias(block.timestamp - checkpointTs, depositFirst),
            "Balance incorrect after p1"
        );

        uint256 endTs = getEndTimestamp(checkpointTs, writtenTs);

        uint256 expectedMaxI = curve.getBias(endTs - checkpointTs, depositFirst);
        uint256 expectedMaxII = curve.getBias(endTs - checkpointTs, depositSecond);

        if (endTs >= writtenTs + curve.warmupPeriod() + 1) {
            // warp to the final period
            // TECHNICALLY, this should round to a whole max
            // but FP arithmetic has a small rounding error and it finishes just below
            vm.warp(endTs);
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

    function test_votingPowerComputesCorrectWithSeasons() public {
        uint tokenIdFirst = 1;
        uint tokenIdSecond = 2;
        uint208 depositFirst = 420.69e18;
        uint208 depositSecond = 1_000_000_000e18;
        uint start = 52 weeks + 1 hours;

        vm.warp(start);

        uint256 checkpointTs = clock.epochNextCheckpointIn();
        uint256 writtenTs = block.timestamp;

        escrow.checkpoint(
            tokenIdFirst,
            LockedBalance(0, 0),
            LockedBalance(depositFirst, uint48(checkpointTs))
        );
        escrow.checkpoint(
            tokenIdSecond,
            LockedBalance(0, 0),
            LockedBalance(depositSecond, uint48(checkpointTs))
        );

        // wait for warmup
        vm.warp(block.timestamp + curve.warmupPeriod() + 1);

        // warp to the start of period 2
        vm.warp(start + clock.epochDuration());

        uint256 endTs = getEndTimestamp(checkpointTs, writtenTs);

        uint256 expectedMaxI = curve.getBias(endTs - checkpointTs, depositFirst);
        uint256 expectedMaxII = curve.getBias(endTs - checkpointTs, depositSecond);
        
        vm.warp(endTs + 1);

        clock.newSeason();

        if (endTs >= writtenTs + curve.warmupPeriod() + 1) {
            // balance should be still the same
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

            // warp to the next epoch (start of season 1)
            vm.warp(block.timestamp + clock.epochNextCheckpointIn());

            uint256 seasonWeekStartTs = block.timestamp;

            assertEq(
                curve.votingPowerAt(tokenIdFirst, block.timestamp),
                depositFirst,
                "Balance incorrect after season reset"
            );
            assertEq(
                curve.votingPowerAt(tokenIdSecond, block.timestamp),
                depositSecond,
                "Balance incorrect after season reset II"
            );

            vm.warp(block.timestamp + clock.epochDuration());

            assertEq(
                curve.votingPowerAt(tokenIdFirst, block.timestamp),
                curve.getBias(block.timestamp - weekStartTs(seasonWeekStartTs), depositFirst),
                "Balance incorrect after p1"
            );

            vm.warp(block.timestamp + clock.epochDuration());

            // Simulate a beginWithdrawal checkpoint
            uint256 checkpointClearTime = IClock(clock).epochNextCheckpointTs();
            escrow.checkpoint(
                tokenIdFirst,
                LockedBalance(0, 0),
                LockedBalance(0, checkpointClearTime.toUint48())
            );

            assertEq(
                curve.votingPowerAt(tokenIdFirst, block.timestamp),
                curve.getBias(block.timestamp - weekStartTs(seasonWeekStartTs), depositFirst),
                "Voting power should be the same after beginWithdrawal"
            );

            clock.newSeason();

            vm.warp(block.timestamp + clock.epochDuration());

            assertEq(
                curve.votingPowerAt(tokenIdFirst, block.timestamp),
                0,
                "Voting power should be after withdrawal"
            );
        }
    }
}
