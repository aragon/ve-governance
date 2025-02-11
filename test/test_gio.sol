pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {QuadraticIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/QuadraticIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {Test} from "forge-std/Test.sol";
import {SafeCastUpgradeable as SafeCast} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {CurveConstantLib} from "@libs/CurveConstantLib.sol";
import {Clock} from "../src/clock/Clock.sol";

contract TestQuadraticIncreasingCurve is Test {
    using SafeCast for uint256;

    uint208 internal TOKEN_10K = 1e22;
    uint256 internal WEEK = 604800;
    uint256 internal DAY = 86400;

    QuadraticIncreasingEscrow internal b;
    Clock internal c;
    uint256 MAX_TIME = CurveConstantLib.MAX_TIME;

    function lockedBalance(uint208 amount, uint48 start, uint48 end) public pure returns(ILockedBalanceIncreasing.LockedBalance memory){
        return ILockedBalanceIncreasing.LockedBalance(amount, start, end);
    }

    function setUp() public {
        b = new QuadraticIncreasingEscrow();
        c = new Clock();
    }

    // 1. Deposit 10k where `startTime` rounds to next week start.
    //    1.a check that totalSupply is 0 before this `startTime`.
    //    1.b check that totalSupply is 10k at `startTime`.
    //    1.c check that totalSupply at `startTime + 2 days` is equal to 10k + (10k/MAX_TIME) * 2 days
    // 2. Deposit another 10k where `startTime` is the same as before.
    //    2.a check that totalSupply is still 0 before the `startTime`.
    //    2.b check that toalSupply is 10k * 2 at `startTime`.
    //    2.c check that totalSupply at `startTime + 2 days` is equal to 10k * 2 + 2 * (10k/MAX_TIME) * 2 days
    // 3. Deposit another 10k where `startTime` is `startTime + WEEK`.
    //    3.a check that totalSupply is the same at `ts` as before since the newest deposit happened after `ts`.
    //    3.b check that totalSupply at `newStartTime` is 10k * 2 + 2 * (10k/MAX_TIME) * (newStartTime - startTime) + 10k
    function test_1() public {
        uint256 startTime = c.epochNextCheckpointTs();
        uint256 endTime = (startTime / CurveConstantLib.WEEK) * CurveConstantLib.WEEK + MAX_TIME;

        uint256 ts = startTime + 2 days;

        // Deposit 10k token at `startTime`
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(TOKEN_10K, startTime.toUint48(), endTime.toUint48())
        );

        assertEq(b.supplyAt(startTime - 1), 0);
        assertEq(b.supplyAt(startTime), TOKEN_10K);
        assertEq(
            b.supplyAt(ts), 
            TOKEN_10K + (TOKEN_10K / MAX_TIME) * (ts - startTime)
        );

        // Deposit another 10k at `startTime`, which must create a new `UserPoint` 
        // which includes previous deposit's bias and slope as well.
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(TOKEN_10K, startTime.toUint48(), endTime.toUint48())
        );

        assertEq(b.supplyAt(startTime - 1), 0);
        assertEq(b.supplyAt(startTime), TOKEN_10K * 2);
        assertEq(
            b.supplyAt(ts), 
            TOKEN_10K * 2 + 2 * (TOKEN_10K / MAX_TIME) * (ts - startTime)
        );

        uint256 newStartTime = startTime + WEEK;
        uint256 newEndTime = (newStartTime / CurveConstantLib.WEEK) * CurveConstantLib.WEEK + MAX_TIME;

        // Deposit again 10k
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(TOKEN_10K, newStartTime.toUint48(), newEndTime.toUint48())
        );

        // This must be the same as previously since we deposited the latest 10k after this timestamp.
        assertEq(
            b.supplyAt(ts), 
            TOKEN_10K * 2 + 2 * (TOKEN_10K / MAX_TIME) * (ts - startTime)
        );

        // Check supply at `newStartTime`
        assertEq(
            b.supplyAt(newStartTime), 
            TOKEN_10K * 2 + 2 * (TOKEN_10K / MAX_TIME) * (newStartTime - startTime) + TOKEN_10K
        );
    }

    // 1. Deposit 10k at `startTime`
    //    1.a check that totalSupply at `endTime - 10` and `endTime - 5` are different and increasing.
    //    1.b check that whatever totalSupply is at `endTime`, it stays the same at `endTime + x`.
    // 2. Deposit 10k at `startTime + WEEK`.
    //    2.a check that total supply only includes the first deposit in calculation at `startTime + 2 days` since the second deposit happened after that.
    //    2.b check that at `endTime` of first deposit, totalSupply includes both of the deposits in calculation.
    //    2.c check that at `endTime` and `endTime + 10`, totalSupply includes both of the deposits in calculation, but such that first deposit's calculation is the same in both.
    function test_2() public {
        uint256 startTime = c.epochNextCheckpointTs();
        uint256 endTime = (startTime / CurveConstantLib.WEEK) * CurveConstantLib.WEEK + MAX_TIME;

        // Deposit 10k token at `startTime`
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(TOKEN_10K, startTime.toUint48(), endTime.toUint48())
        );

        uint256 a1 = b.supplyAt(endTime - 10);
        uint256 b1 = b.supplyAt(endTime - 5);
        assertGt(b1, a1);

        uint256 c1 = b.supplyAt(endTime);
        uint256 c2 = b.supplyAt(endTime + 10);
        uint256 c3 = b.supplyAt(endTime + 300000);
        assertEq(c1, c2);
        assertEq(c2, c3);

        // Deposit 10k token at `startTime + WEEK`
        uint256 newStartTime = startTime + WEEK;
        uint256 newEndTime = (newStartTime / CurveConstantLib.WEEK) * CurveConstantLib.WEEK + MAX_TIME;

        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(TOKEN_10K, newStartTime.toUint48(), newEndTime.toUint48())
        );

        // Check that between `startTime` and `newStartTime`, it only 
        // includes first 10k deposits in calculation for totalSupply
        assertEq(
            b.supplyAt(startTime + 2 days), 
            TOKEN_10K + (TOKEN_10K / MAX_TIME) * 2 days
        );


        uint256 firstDepositBiasAtEndTime = TOKEN_10K + (TOKEN_10K / MAX_TIME) * (endTime - startTime);
        uint256 secondDepositBiasAtEndTime = TOKEN_10K + (TOKEN_10K / MAX_TIME) * (endTime - newStartTime);
        assertEq(
            b.supplyAt(endTime),
            firstDepositBiasAtEndTime + secondDepositBiasAtEndTime
        );

        assertEq(
            b.supplyAt(endTime + 3000),
            firstDepositBiasAtEndTime + secondDepositBiasAtEndTime + (TOKEN_10K / MAX_TIME) * (endTime + 3000 - endTime)
        );
    }

    // 1. Deposit 10k at `startTime`
    // 2. Deposit 10k at `newStartTime = startTime + WEEK`.
    //    2.a check that `newStartTime - 1`, totalSupply is 10k + (10k / MAX_TIME) * (newStartTime - 1 - startTime)
    //    2.b check that totalSupply is 0 at `newStartTime`.
    // 3. Deposit 10k again at `newStartTime = startTime + WEEK`
    //    3.a see below what we test...
    function test_3() public {
        uint256 startTime = c.epochNextCheckpointTs();
        uint256 endTime = (startTime / CurveConstantLib.WEEK) * CurveConstantLib.WEEK + MAX_TIME;

        // Deposit 10k token at `startTime`
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(TOKEN_10K, startTime.toUint48(), endTime.toUint48())
        );

        uint256 newStartTime = startTime + WEEK;
        uint256 newEndTime = (newStartTime / CurveConstantLib.WEEK) * CurveConstantLib.WEEK + MAX_TIME;

        // Deposit 10k token at `newStartTime`
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(0, newStartTime.toUint48(), newEndTime.toUint48())
        );

        assertEq(
            b.supplyAt(newStartTime - 1),
            TOKEN_10K + (TOKEN_10K / MAX_TIME) * (newStartTime - 1 - startTime)
        );

        assertEq(b.supplyAt(newStartTime), 0);

        // Deposit 10k token at `newStartTime`
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(TOKEN_10K, newStartTime.toUint48(), newEndTime.toUint48())
        );

        // when we deposited 0 above, `slopeChanges` must have updated to remove 
        // that slope from it. Otherwise, below will fail.
        assertEq(
            b.supplyAt(endTime + 1),
            TOKEN_10K + (TOKEN_10K / MAX_TIME) * (endTime + 1 - newStartTime)
        );
    }


    function test_gas1() public {
        uint256 startTime = c.epochNextCheckpointTs();
        uint256 endTime = (startTime / CurveConstantLib.WEEK) * CurveConstantLib.WEEK + MAX_TIME;

        uint g1 = gasleft();
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(TOKEN_10K, startTime.toUint48(), endTime.toUint48())
        );

        uint g2 = gasleft();

        console.log("very first checkpoint gas cost", g1 - g2);

        // change this and max_time to test the gas..
        startTime = startTime + 8 weeks;
        endTime = (startTime / CurveConstantLib.WEEK) * CurveConstantLib.WEEK + MAX_TIME;
        vm.warp(startTime);
        g1 = gasleft();
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(TOKEN_10K, startTime.toUint48(), endTime.toUint48())
        );
        g2 = gasleft();
        console.log("some time after gas cost", g1 - g2);

        // 5 weeks - 310519
        // 6 weeks - 358094
        // 7 weeks - 405669
        // 8 weeks - 453244

        // This gas costs give us the following useful information.

        // If Jordan locks token at `t1`, it matters when the next user decides to lock. The way checkpoints work
        // is when tx occurs, first it finds lastPoint stored in checkpoints and from that point to the new point, it stores
        // stuff in every week between those intervals. If no lock occured during a long time(let's say in 100 weeks), nobody locked.
        // and now, someone locks. What this means is when this lock tx occurs, it must update the storage 100 times. as we see above,
        // 5 weeks of update costs 310519, 6 weeks - 358094. So it's like 40,000 GAS per week.
        // To make this system work efficiently, each week, one lock should occur so that users distribute gas costs between them.
    }
}


