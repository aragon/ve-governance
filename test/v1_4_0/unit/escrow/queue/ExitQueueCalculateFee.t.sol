pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";
import {ExitQueueBase, DaoUnauthorized} from "./ExitQueueBase.sol";

contract DynamicExitQueueCalculateFeeTest is ExitQueueBase {
    function setUp() public override {
        super.setUp();
        vm.warp(1);
        queue.setMinLock(1);
    }

    /// @notice Test calculate fee with no ticket
    function test_CalculateFeeWithNoTicket() public view {
        uint256 fee = queue.calculateFee(999);
        assertEq(fee, 0);
    }

    /// @notice Test calculate fee with zero balance
    function test_CalculateFeeWithZeroBalance() public {
        queue.setDynamicExitFeePercent(1000, 5000, 86400, 43200);

        escrow.setMockLockedBalance(0, block.timestamp - 1);

        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        vm.expectRevert(NoLockBalance.selector);
        queue.calculateFee(1);
    }

    /// @notice Test calculate fee with valid conditions
    function test_CalculateFeeWithValidConditions() public {
        queue.setDynamicExitFeePercent(1000, 5000, 86400, 43200);

        uint256 lockedAmount = 1000000;
        escrow.setMockLockedBalance(lockedAmount, block.timestamp - 1);

        uint256 queueTime = block.timestamp;
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        // At minCooldown - should pay max fee
        vm.warp(queueTime + 43200);
        uint256 expectedFee = (lockedAmount * 5000) / 10000;
        assertEq(queue.calculateFee(1), expectedFee);

        // At cooldown - should pay min fee
        vm.warp(queueTime + 86400);
        expectedFee = (lockedAmount * 1000) / 10000;
        assertEq(queue.calculateFee(1), expectedFee);

        // After cooldown - should pay min fee
        vm.warp(queueTime + 100000);
        expectedFee = (lockedAmount * 1000) / 10000;
        assertEq(queue.calculateFee(1), expectedFee);
    }

    /// @notice Test calculate fee precision and rounding
    function test_CalculateFeePrecisionAndRounding() public {
        queue.setDynamicExitFeePercent(1000, 5000, 86400, 43200);

        // Test with very small locked amounts
        escrow.setMockLockedBalance(1, block.timestamp - 1);

        uint256 queueTime = block.timestamp;
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        vm.warp(queueTime + 43200);
        uint256 fee = queue.calculateFee(1);
        assertEq(fee, uint(1 * 5000) / 10000);

        // Test with locked amount = 2
        escrow.setMockLockedBalance(2, block.timestamp - 1);

        vm.warp(queueTime + 43200);
        fee = queue.calculateFee(1);
        assertEq(fee, uint(2 * 5000) / 10000);

        // Test with locked amount = 99
        escrow.setMockLockedBalance(99, block.timestamp - 1);

        vm.warp(queueTime + 43200);
        fee = queue.calculateFee(1);
        assertEq(fee, uint(99 * 5000) / 10000);

        // Test with very large locked amount
        uint256 largeAmount = type(uint208).max / 10000;
        escrow.setMockLockedBalance(largeAmount, block.timestamp - 1);

        vm.warp(queueTime + 43200);
        fee = queue.calculateFee(1);
        assertEq(fee, (largeAmount * 5000) / 10000);
    }

    /// @notice Test calculate fee with different fee systems
    function test_CalculateFeeWithDifferentFeeSystems() public {
        uint256 lockedAmount = 1000000;
        escrow.setMockLockedBalance(lockedAmount, block.timestamp - 1);

        uint256 queueTime = block.timestamp;

        // Test with dynamic fee system
        queue.setDynamicExitFeePercent(1000, 5000, 86400, 43200);

        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        vm.warp(queueTime + 43200);
        uint256 dynamicFee = queue.calculateFee(1);
        assertEq(dynamicFee, (lockedAmount * 5000) / 10000);

        // Test with tiered fee system
        queue.setTieredExitFeePercent(1000, 5000, 86400, 43200);

        // Need to create a new ticket for the new fee system
        vm.prank(address(escrow));
        queue.queueExit(2, address(this));

        uint256 tieredFee = queue.calculateFee(2);
        assertEq(tieredFee, (lockedAmount * 5000) / 10000);

        // Test with fixed fee system (early exit allowed)
        queue.setFixedExitFeePercent(3000, 86400, true);

        // Need to create a new ticket for the new fee system
        vm.prank(address(escrow));
        queue.queueExit(3, address(this));

        uint256 fixedFee = queue.calculateFee(3);
        assertEq(fixedFee, (lockedAmount * 3000) / 10000);

        // Test with fixed fee system (early exit disabled)
        queue.setFixedExitFeePercent(2000, 86400, false);

        // Need to create a new ticket for the new fee system
        vm.prank(address(escrow));
        queue.queueExit(4, address(this));

        uint256 fixedNoEarlyFee = queue.calculateFee(4);
        assertEq(fixedNoEarlyFee, (lockedAmount * 2000) / 10000);
    }

    /// @notice Test calculate fee with fractional amounts
    function test_CalculateFeeWithFractionalAmounts() public {
        queue.setDynamicExitFeePercent(3333, 6666, 86400, 43200);

        uint256 lockedAmount = 1000007;
        escrow.setMockLockedBalance(lockedAmount, block.timestamp - 1);

        uint256 queueTime = block.timestamp;
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        vm.warp(queueTime + 43200);
        uint256 fee = queue.calculateFee(1);
        uint256 expectedFee = (lockedAmount * 6666) / 10000;
        assertEq(fee, expectedFee);
    }

    /// @notice Test calculate fee during decay period
    function test_CalculateFeeDuringDecayPeriod() public {
        queue.setDynamicExitFeePercent(1000, 5000, 86400, 43200);

        uint256 lockedAmount = 1000000;
        escrow.setMockLockedBalance(lockedAmount, block.timestamp - 1);

        uint256 queueTime = block.timestamp;
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        // Test at various points during decay
        vm.warp(queueTime + 43200 + 10800); // 25% into decay period
        uint256 fee = queue.calculateFee(1);
        assertLt(fee, (lockedAmount * 5000) / 10000);
        assertGt(fee, (lockedAmount * 1000) / 10000);

        vm.warp(queueTime + 43200 + 21600); // 50% into decay period
        fee = queue.calculateFee(1);
        assertApproxEqRel(fee, (lockedAmount * 3000) / 10000, 0.01e18);

        vm.warp(queueTime + 43200 + 32400); // 75% into decay period
        fee = queue.calculateFee(1);
        assertLt(fee, (lockedAmount * 3000) / 10000);
        assertGt(fee, (lockedAmount * 1000) / 10000);
    }

    /// @notice Test calculate fee with no overflow
    function test_CalculateFeeNoOverflow() public {
        queue.setDynamicExitFeePercent(0, 10000, 86400, 43200);

        uint256 maxSafeAmount = type(uint208).max / 10000;
        escrow.setMockLockedBalance(maxSafeAmount, block.timestamp - 1);

        uint256 queueTime = block.timestamp;
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        vm.warp(queueTime + 43200);
        uint256 fee = queue.calculateFee(1);
        assertEq(fee, maxSafeAmount);
    }
}
