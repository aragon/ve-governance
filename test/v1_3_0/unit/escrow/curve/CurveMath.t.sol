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

    function testWritesCheckpoint() public {
        uint tokenIdFirst = 1;
        uint tokenIdSecond = 2;
        uint208 depositFirst = 420.69e18;
        uint208 depositSecond = 1_000_000_000e18;

        // add + 1seconds so it doesn't get to
        // be exact checkpointInterval.
        uint256 start = 52 weeks + 1 hours;

        uint256 checkpointTs = weekStartTs(start);
       

        // initial conditions, no balance
        // always warm
        assertEq(curve.votingPowerAt(tokenIdFirst, 0), 0, "Balance before deposit");

        assertEq(curve.isWarm(tokenIdFirst), true, "Not warming up");
        assertEq(curve.isWarm(tokenIdSecond), true, "Not warming up");

        vm.warp(start);

        // still no balance
        assertEq(curve.votingPowerAt(tokenIdFirst, 0), 0, "Balance before deposit");
        
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
        assertEq(
            tokenPoint.bias,
            bias(depositFirst, block.timestamp - checkpointTs),
            "Bias is incorrect"
        );
        assertEq(tokenPoint.checkpointTs, checkpointTs, "CP Timestamp is incorrect");
        assertEq(tokenPoint.writtenTs, writtenTs, "Written Timestamp is incorrect");

        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            bias(depositFirst, block.timestamp - checkpointTs),
            "Balance incorrect after deposit"
        );

        vm.warp(block.timestamp + 3 days + 1);

        assertEq(
            curve.votingPowerAt(tokenIdFirst, block.timestamp),
            bias(depositFirst, block.timestamp - checkpointTs),
            "Balance incorrect after 3 days"
        );
        assertEq(curve.isWarm(tokenIdFirst), true, "Still warming up");

        assertEq(
            curve.votingPowerAt(tokenIdSecond, block.timestamp),
            bias(depositSecond, block.timestamp - checkpointTs),
            "Balance incorrect after warmup II"
        );

        uint256 endTs = getEndTimestamp(checkpointTs, writtenTs);

        uint256 expectedMaxI = bias(depositFirst, maxTime);
        uint256 expectedMaxII = bias(depositSecond, maxTime);

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
