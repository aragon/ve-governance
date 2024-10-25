// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {LinearIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/LinearIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";

import {LinearCurveBase} from "./LinearBase.sol";
contract TestLinearVotingPower is LinearCurveBase {
    // returns zero by default
    function testGetVotingPowerReturnsZero(uint _tokenId, uint _t) public view {
        assertEq(curve.votingPowerAt(_tokenId, _t), 0);
    }

    // for a token within warmup, returns zero
    // set a random warmup
    // write the point at ts = 1
    // move to 1 second before
    // vp == 0
    function testGetVotingPowerReturnsZeroForWarmup(uint48 _warmup) public {
        vm.assume(_warmup > 1);
        vm.assume(_warmup < type(uint48).max);

        curve.setWarmupPeriod(_warmup);

        TokenPoint memory point = curve.previewPoint(10); // real point
        point.writtenTs = 1;
        point.checkpointTs = 1;

        // write a point
        curve.writeNewTokenPoint(1, point, 1);

        // check the voting power
        vm.warp(_warmup + point.writtenTs);
        assertEq(curve.votingPowerAt(1, block.timestamp), 0);

        // after warmup, return gt 0
        vm.warp(_warmup + point.writtenTs + 1);
        assertGt(curve.votingPowerAt(1, block.timestamp), 0);
    }

    // maxes correctly
    // set a lock start of 1
    // set point
    // point voting power at max should be max && gt 0
    // at 2*max same
    // with low amounts the amount doesn't increase
    function testTokenMaxesAtMaxTime() public {
        uint208 amount = 1e18;
        uint128 start = 1;
        uint max = start + curve.maxTime();

        escrow.setLockedBalance(1, LockedBalance({start: uint48(start), amount: amount}));

        TokenPoint memory point = curve.previewPoint(amount); // real point
        point.checkpointTs = start;

        // write a point
        curve.writeNewTokenPoint(1, point, 1);

        // warp to max time
        vm.warp(max - 1);

        uint votingPowerPreMax = curve.votingPowerAt(1, block.timestamp);

        vm.warp(max);

        uint votingPowerAtMax = curve.votingPowerAt(1, block.timestamp);

        vm.warp(max + 1);

        uint votingPowerPostMax = curve.votingPowerAt(1, block.timestamp);

        assertGt(votingPowerPreMax, 0);
        assertGt(votingPowerAtMax, votingPowerPreMax);
        assertEq(votingPowerAtMax, votingPowerPostMax);
    }

    // for a token w. 2 points

    // if the first point is in warmup returns zero
    function testIfFirstPointInWarmupReturnsZero() public {
        uint208 amount = 1e18;
        uint48 warmup = 100;

        curve.setWarmupPeriod(warmup);

        // write 2 points: p1 at 1, p2 after warmup
        TokenPoint memory p1 = curve.previewPoint(amount);
        TokenPoint memory p2 = curve.previewPoint(amount);

        p1.writtenTs = 1;
        p1.checkpointTs = 1;

        p2.writtenTs = warmup + 1;
        p2.checkpointTs = warmup + 1;

        curve.writeNewTokenPoint(1, p1, 1);
        curve.writeNewTokenPoint(1, p2, 2);

        vm.warp(warmup);
        assertEq(curve.votingPowerAt(1, block.timestamp), 0);
    }

    // if the second point was written lt warmup seconds ago, but p1 outside warmup, returns postive
    function testIfFirstPointOutsideWarmupSecondPointInsideWarmupReturnsPositive() public {
        uint208 amount = 1e18;
        uint48 warmup = 100;

        curve.setWarmupPeriod(warmup);

        // write 2 points: p1 at 1, p2 after warmup
        TokenPoint memory p1 = curve.previewPoint(amount);
        TokenPoint memory p2 = curve.previewPoint(amount);

        p1.writtenTs = 1;
        p1.checkpointTs = 1;

        p2.writtenTs = warmup - 1;
        p2.checkpointTs = warmup - 1;

        curve.writeNewTokenPoint(1, p1, 1);
        curve.writeNewTokenPoint(1, p2, 2);

        vm.warp(warmup + p1.writtenTs + 1);
        assertGt(curve.votingPowerAt(1, block.timestamp), 0);
    }

    // for 2 points, correctly calulates the bias based on latest point

    // for 2 points, correctly maxes the bias at the original lock start
    function test2PointsMaxesCorrectlySameAmount() public {
        uint208 amount = 1e18;
        uint48 start = 1;
        uint48 max = start + curve.maxTime();

        // original start is at 1
        escrow.setLockedBalance(1, LockedBalance({start: start, amount: amount}));

        TokenPoint memory p1 = curve.previewPoint(amount); // real point
        TokenPoint memory p2 = curve.previewPoint(amount); // real point

        p1.checkpointTs = start;
        p2.checkpointTs = 1000;

        // write a point
        curve.writeNewTokenPoint(1, p1, 1);
        curve.writeNewTokenPoint(1, p2, 2);

        // warp to max time
        vm.warp(max - 1);

        uint votingPowerPreMax = curve.votingPowerAt(1, block.timestamp);

        vm.warp(max);

        uint votingPowerAtMax = curve.votingPowerAt(1, block.timestamp);

        vm.warp(max + 1);

        uint votingPowerPostMax = curve.votingPowerAt(1, block.timestamp);

        assertGt(votingPowerPreMax, 0);
        assertGt(votingPowerAtMax, votingPowerPreMax, "votingPowerAtMax > votingPowerPreMax");
        assertEq(votingPowerAtMax, votingPowerPostMax, "votingPowerAtMax == votingPowerPostMax");
    }

    // in the event that you have 2 points but the second point
    // is after the first, which is synced to the lock start:
    // the max should be based on the lock start
    // but the coefficients[0] of the second point is based on the
    // evaluated bias of the first point at the second point's checkpoint
    // this means second point should only keep accruing voting power
    // for the duration of the lock start
    // an example:
    // I lock 100 tokens and they double after 2 years and don't keep increasing
    // I drop to 50 tokens at half a year
    // At t = 12 months - 1 second I'm at 150 tokens
    // At t = 12 months I'm at: 75 tokens
    // I don't then restart the max from 12 months, I start the max from
    // the original lock start meaning I increase from 75 to 100
    // over the next 12 months
    function test2PointsMaxesCorrectlyDiffAmount() public {
        uint208 amount = 100e18;
        uint amount2 = 50e18;
        uint48 start = 1;
        uint48 max = start + curve.maxTime(); // 2y

        // original start is at 1
        escrow.setLockedBalance(1, LockedBalance({start: start, amount: amount}));

        TokenPoint memory p1 = curve.previewPoint(amount); // real point
        TokenPoint memory p2 = curve.previewPoint(amount2); //

        p1.checkpointTs = start;
        p2.checkpointTs = start + 52 weeks;

        // overwrite the bias at the checkpoint with the bias evaluated at 52 weeks
        p2.coefficients[0] = curve.getBiasUnbound(52 weeks, amount2);

        // write a point
        curve.writeNewTokenPoint(1, p1, 1);
        curve.writeNewTokenPoint(1, p2, 2);

        // warp to max time
        vm.warp(max - 1);

        uint votingPowerPreMax = curve.votingPowerAt(1, block.timestamp);

        vm.warp(max);

        uint votingPowerAtMax = curve.votingPowerAt(1, block.timestamp);

        vm.warp(max + 1);

        uint votingPowerPostMax = curve.votingPowerAt(1, block.timestamp);

        assertGt(votingPowerPreMax, 0);
        assertGt(votingPowerAtMax, votingPowerPreMax, "vp @ max > vp @ max - 1");
        assertEq(votingPowerPostMax, votingPowerAtMax, "vp @ max == vp @ max + 1");

        assertEq(
            votingPowerPostMax,
            curve.getBias(curve.maxTime(), amount2),
            "vp @ max == bias @ max for the lower amount"
        );
        // check history is preserved
        assertEq(
            curve.votingPowerAt(1, start + 26 weeks),
            curve.getBias(26 weeks, amount),
            "vp @ 26 weeks"
        );
        // after increase
        assertEq(
            curve.votingPowerAt(1, start + 75 weeks),
            curve.getBias(75 weeks, amount2),
            "vp @ 39 weeks"
        );
    }
}
