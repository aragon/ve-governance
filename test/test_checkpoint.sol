pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {QuadraticIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/QuadraticIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {Test} from "forge-std/Test.sol";
import {SafeCastUpgradeable as SafeCast} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {CurveConstantLib} from "@libs/CurveConstantLib.sol";
import {Clock} from "../src/clock/Clock.sol";

contract TestCheckpoint is Test {
    using SafeCast for uint256;

    uint208 internal TOKEN_10K = 1e22;
    uint208 internal TOKEN_5K = 5e21;

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
    

    // 1. Deposit 10k where `startTime` rounds to prev week start.
    //    1.a check that totalSupply is 0 before depositTime.
    //    1.b check that totalSupply is 10k + slope * (depositTime - startTime) at `depositTime`.
    //    1.c check that totalSupply at `depositTime + 2 days` is equal to 10k + slope * (depositTime + 2 days - startTime)
    // 2. Deposit another 10k where `depositTime` is the same as before.
    //    2.a check that totalSupply is still 0 before the `depositTime`.
    //    2.b check that toalSupply at depositTime is 2 * (10k + slope * (depositTime - startTime))
    //    2.c check that totalSupply at `depositTime + 2 days` is equal to  2 * (10k + slope * (depositTime + 2 days - startTime))
    // 3. Deposit another 10k where `depositTime` is in the next week and startTime of this is next week exactly.
    //    3.a check that totalSupply at thirdDepositTime - 1 is not including the third deposit's calculation.
    //    3.b check that totalSupply at `thirdDepositTime` is  TOKEN_10K * 2 + 2 * slope * (thirdDepositTime - startTime) + TOKEN_10K + slope * (thirdDepositTime - newStartTime)
    function test_1() public {
        uint256 firstDepositTime = block.timestamp;
        uint256 startTime = (firstDepositTime / WEEK) * WEEK;        
        uint256 endTime = startTime + MAX_TIME;
        uint256 twoDaysAfterFirstDeposit = firstDepositTime + 2 days;

        uint256 slope = TOKEN_10K / MAX_TIME;

        // Deposit 10k token.
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(TOKEN_10K, startTime.toUint48(), endTime.toUint48())
        );

        assertEq(b.supplyAt(firstDepositTime - 1), 0);
        assertEq(b.supplyAt(firstDepositTime), TOKEN_10K + slope * (firstDepositTime - startTime));
        assertEq(
            b.supplyAt(twoDaysAfterFirstDeposit), 
            TOKEN_10K + slope * (twoDaysAfterFirstDeposit - startTime)
        );

        // Deposit another 10k at `firstDepositTime`, which must create a new `UserPoint` 
        // which includes previous deposit's bias and slope as well.
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(TOKEN_10K, startTime.toUint48(), endTime.toUint48())
        );

        assertEq(b.supplyAt(firstDepositTime - 1), 0);
        assertEq(b.supplyAt(firstDepositTime), TOKEN_10K * 2 + 2 * slope * (firstDepositTime - startTime));
        assertEq(
            b.supplyAt(twoDaysAfterFirstDeposit), 
            TOKEN_10K * 2 + 2 * slope * (twoDaysAfterFirstDeposit - startTime)
        );
        
        uint256 thirdDepositTime = firstDepositTime + WEEK;
        vm.warp(thirdDepositTime);
        uint256 newStartTime = (thirdDepositTime / WEEK) * WEEK;      
        uint256 newEndTime = newStartTime + MAX_TIME;
        
        // Deposit again 10k
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(TOKEN_10K, newStartTime.toUint48(), newEndTime.toUint48())
        );

        // supply before third deposit must not include third deposit.
        assertEq(
            b.supplyAt(thirdDepositTime - 1), 
            TOKEN_10K * 2 + 2 * slope * (thirdDepositTime - 1 - startTime) 
        );

        assertEq(
            b.supplyAt(thirdDepositTime), 
            TOKEN_10K * 2 + 2 * slope * (thirdDepositTime - startTime) + TOKEN_10K + slope * (thirdDepositTime - newStartTime)
        );
    }

    // // 1. Deposit 10k at `depositTime = block.timestamp`
    // //    1.a check that totalSupply at `endTime - 10` and `endTime - 5` are different and increasing.
    // //    1.b check that whatever totalSupply is at `endTime`, it stays the same at `endTime + x`.
    function test_2() public {
        uint256 firstDepositTime = block.timestamp;
        uint256 startTime = (firstDepositTime / WEEK) * WEEK;        
        uint256 endTime = startTime + MAX_TIME;

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
    }

    // 1. Deposit 10k at `startTime`
    // 2. Deposit 10k at `newStartTime = startTime + WEEK`.
    //    2.a check that `newStartTime - 1`, totalSupply is 10k + (10k / MAX_TIME) * (newStartTime - 1 - startTime)
    //    2.b check that totalSupply is 0 at `newStartTime`.
    // 3. Deposit 10k again at `newStartTime = startTime + WEEK`
    //    3.a see below what we test...
    function test_3() public {
        uint256 firstDepositTime = block.timestamp;
        uint256 startTime = (firstDepositTime / WEEK) * WEEK;        
        uint256 endTime = startTime + MAX_TIME;
        uint256 slope = TOKEN_10K / MAX_TIME;

        // Deposit 10k token
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(TOKEN_10K, startTime.toUint48(), endTime.toUint48())
        );

        uint256 newDepositTime = firstDepositTime + WEEK;
        vm.warp(newDepositTime);
        uint256 newStartTime = (newDepositTime / WEEK) * WEEK;        
        uint256 newEndTime = newStartTime + MAX_TIME;
        
        // Deposit 0 token
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(0, newStartTime.toUint48(), newEndTime.toUint48())
        );

        assertEq(
            b.supplyAt(newDepositTime - 1),
            TOKEN_10K + slope * (newDepositTime - 1 - startTime)
        );

        assertEq(b.supplyAt(newDepositTime), 0);

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
            TOKEN_10K + slope * (endTime + 1 - newStartTime)
        );
    }


    // 1. Deposit 50. 
    // 2. deposit 30.
    // 2. Deposit 0.
    // 3. see if it succeeds
    function test_4() public {
        uint256 firstDepositTime = block.timestamp;
        uint256 startTime = (firstDepositTime / WEEK) * WEEK;        
        uint256 endTime = startTime + MAX_TIME;
        uint256 slope = 50e18 / MAX_TIME;

        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(50e18, startTime.toUint48(), endTime.toUint48())
        );

        uint256 newDepositTime = firstDepositTime + WEEK;
        vm.warp(newDepositTime);
        uint256 newStartTime = (newDepositTime / WEEK) * WEEK;        
        uint256 newEndTime = newStartTime + MAX_TIME;
        uint256 newSlope = 30e18 / MAX_TIME;

        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(30e18, newStartTime.toUint48(), newEndTime.toUint48()) 
        );

        assertEq(
            b.supplyAt(newDepositTime), 
            50e18 + slope * (block.timestamp - startTime) + 30e18 + newSlope * (block.timestamp - newStartTime)
        );

        newDepositTime = newDepositTime + 20 minutes;
        vm.warp(newDepositTime);
        newStartTime = (newDepositTime / WEEK) * WEEK;        
        newEndTime = newStartTime + MAX_TIME;
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(0, newStartTime.toUint48(), newEndTime.toUint48())
        );

        assertEq(b.supplyAt(newDepositTime), 0);
    }

    // NOTE: on the 2nd deposit, end date doesn't change..
    // 1. Deposit 50
    // 2. Deposit 30
    // 3. deposit 0
    // 3. see if it succeeds
    function test_5() public {
        uint256 firstDepositTime = block.timestamp;
        uint256 startTime = (firstDepositTime / WEEK) * WEEK;        
        uint256 endTime = startTime + MAX_TIME;
        uint256 slope = 50e18 / MAX_TIME;

        // Deposit 50 token
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(50e18, startTime.toUint48(), endTime.toUint48())
        );

        uint256 newDepositTime = firstDepositTime + WEEK;
        vm.warp(newDepositTime);
        uint256 newStartTime = (newDepositTime / WEEK) * WEEK;        
        uint256 newEndTime = newStartTime + MAX_TIME;
        uint256 newSlope = 30e18 / MAX_TIME;
        
        // Deposit 30 token
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(30e18, newStartTime.toUint48(), endTime.toUint48()) 
        );

        assertEq(
            b.supplyAt(newDepositTime), 
            50e18 + slope * (block.timestamp - startTime) + 30e18 + newSlope * (block.timestamp - newStartTime)
        );

        newDepositTime = newDepositTime + 20 minutes;
        vm.warp(newDepositTime);
        newStartTime = (newDepositTime / WEEK) * WEEK;        
        newEndTime = newStartTime + MAX_TIME;
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(0, newStartTime.toUint48(), newEndTime.toUint48())
        );

        assertEq(b.supplyAt(newDepositTime), 0);
    }


    function test_gas1() public {
        uint256 depositTime = block.timestamp;
        uint256 startTime = (depositTime / WEEK) * WEEK;        
        uint256 endTime = startTime + MAX_TIME;
        uint256 slope = TOKEN_10K / MAX_TIME;

        uint g1 = gasleft();
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(TOKEN_10K, startTime.toUint48(), endTime.toUint48())
        );

        uint g2 = gasleft();

        console.log("very first checkpoint gas cost", g1 - g2);

        // change `2` to 3,4, 5, 6 to test the gas.
        depositTime = depositTime + 5 weeks;
        startTime = (depositTime / WEEK) * WEEK;     
        endTime = startTime + MAX_TIME;
        vm.warp(depositTime);
        g1 = gasleft();
        b.checkpoint(
            1, 
            lockedBalance(0, 0, 0),
            lockedBalance(TOKEN_10K, startTime.toUint48(), endTime.toUint48())
        );
        g2 = gasleft();
        console.log("some time after gas cost", g1 - g2);

        // 2 weeks - 213475
        // 3 weeks - 261048
        // 4 weeks - 308621
        // 5 weeks - 356194

        // This gas costs give us the following useful information.

        // If Jordan locks token at `t1`, it matters when the next user decides to lock. The way checkpoints work
        // is when tx occurs, first it finds lastPoint stored in checkpoints and from that point to the new point, it stores
        // stuff in every week between those intervals. If no lock occured during a long time(let's say in 100 weeks), nobody locked.
        // and now, someone locks. What this means is when this lock tx occurs, it must update the storage 100 times. as we see above,
        // 5 weeks of update costs 310519, 6 weeks - 358094. So it's like 40,000 GAS per week.
        // To make this system work efficiently, each week, one lock should occur so that users distribute gas costs between them.
    }
}


