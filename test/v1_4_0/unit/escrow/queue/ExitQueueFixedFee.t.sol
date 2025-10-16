pragma solidity ^0.8.17;

import {ExitQueueBase, DaoUnauthorized} from "./ExitQueueBase.sol";

contract DynamicExitQueueFixedFeeTest is ExitQueueBase {
    function setUp() public override {
        super.setUp();
        vm.warp(1);
        queue.setMinLock(1);
    }

    /// @notice Test valid fixed fee configuration with early exit allowed
    function testFuzz_ValidFixedFeeConfigurationWithEarlyExitAllowed(
        uint256 _feePercent
    ) public {
        // Bound inputs
        _feePercent = bound(_feePercent, 0, 10000);

        // Configure fixed fee system with early exit allowed (cooldown = 0)
        queue.setFixedExitFeePercent(_feePercent, 0);

        // Assert state variables match input parameters
        assertEq(queue.feePercent(), _feePercent);
        assertEq(queue.minFeePercent(), _feePercent);
        assertEq(queue.cooldown(), 0);
        assertEq(queue.minCooldown(), 0);
        assertEq(queue.slope(), 0);
    }

    /// @notice Test valid fixed fee configuration with early exit disabled
    function testFuzz_ValidFixedFeeConfigurationWithEarlyExitDisabled(
        uint256 _feePercent,
        uint48 _cooldown
    ) public {
        // Bound inputs
        _feePercent = bound(_feePercent, 0, 10000);

        // Configure fixed fee system with early exit disabled
        queue.setFixedExitFeePercent(_feePercent, _cooldown);

        // Assert state variables match input parameters
        assertEq(queue.feePercent(), _feePercent);
        assertEq(queue.minFeePercent(), _feePercent);
        assertEq(queue.cooldown(), _cooldown);
        assertEq(queue.minCooldown(), _cooldown);
        assertEq(queue.slope(), 0);
    }

    /// @notice Test fixed fee validation - fee bounds
    function test_FixedFeeValidation_FeeBounds() public {
        // Test feePercent = 10001
        vm.expectRevert(abi.encodeWithSelector(FeePercentTooHigh.selector, 10000));
        queue.setFixedExitFeePercent(10001, 0);
    }

    /// @notice Test ExitFeePercentAdjusted event emission for fixed fee with early exit
    function test_ExitFeePercentAdjustedEvent_FixedFeeWithEarlyExit() public {
        uint256 feePercent = 2000;

        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit ExitFeePercentAdjusted(feePercent, feePercent, 0, ExitFeeType.Fixed);

        queue.setFixedExitFeePercent(feePercent, 0);
    }

    /// @notice Test ExitFeePercentAdjusted event emission for fixed fee without early exit
    function test_ExitFeePercentAdjustedEvent_FixedFeeWithoutEarlyExit() public {
        uint256 feePercent = 1500;
        uint48 cooldown = 172800; // 2 days

        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit ExitFeePercentAdjusted(feePercent, feePercent, cooldown, ExitFeeType.Fixed);

        queue.setFixedExitFeePercent(feePercent, cooldown);
    }

    /// @notice Test getTimeBasedFee for fixed fee system
    function test_GetTimeBasedFeeForFixedFeeSystem() public {
        uint256 feePercent = 2000;
        uint48 cooldown = 86400; // 1 day

        // Configure fixed fee system
        queue.setFixedExitFeePercent(feePercent, cooldown);

        // Test with various timeElapsed values
        assertEq(queue.getTimeBasedFee(0), 2000);
        assertEq(queue.getTimeBasedFee(86400), 2000); // at cooldown
        assertEq(queue.getTimeBasedFee(172800), 2000); // beyond cooldown
        assertEq(queue.getTimeBasedFee(1000000), 2000); // far beyond cooldown
    }

    /// @notice Test fixed fee system behavior with early exit allowed
    function test_FixedFeeSystemBehaviorWithEarlyExitAllowed() public {
        uint256 feePercent = 1000;

        // Configure fixed fee system with early exit allowed
        queue.setFixedExitFeePercent(feePercent, 0);

        // Mock escrow setup
        escrow.setMockLockedBalance(100e18, block.timestamp - 1);

        // Queue exit (should succeed immediately since minCooldown = 0)
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        // Should be able to exit after 1 second
        vm.warp(block.timestamp + 1);
        assertTrue(queue.canExit(1));

        // Fee should be consistent regardless of timing
        assertEq(queue.calculateFee(1), (100e18 * feePercent) / 10000);

        // Fast forward and test again
        vm.warp(block.timestamp + 86400);
        assertEq(queue.calculateFee(1), (100e18 * feePercent) / 10000);
    }

    /// @notice Test fixed fee system behavior with early exit disabled
    function test_FixedFeeSystemBehaviorWithEarlyExitDisabled() public {
        uint256 feePercent = 1500;
        uint48 cooldown = 172800; // 2 days

        // Configure fixed fee system with early exit disabled
        queue.setFixedExitFeePercent(feePercent, cooldown);

        // Mock escrow setup
        uint lockTime = block.timestamp - 1;
        escrow.setMockLockedBalance(100e18, lockTime);

        // Queue exit
        uint queueTime = block.timestamp;
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        // Should not be able to exit immediately
        assertFalse(queue.canExit(1), "immediate exit should not be allowed");

        vm.warp(queueTime + cooldown - 1);
        assertFalse(queue.canExit(1), "exit should not be allowed before cooldown ends");

        vm.warp(block.timestamp + 1);
        assertTrue(queue.canExit(1), "exit should be allowed after cooldown ends");

        // Fee should be consistent
        assertEq(queue.calculateFee(1), (100e18 * feePercent) / 10000);
    }

    /// @notice Test fixed fee system with zero fee
    function test_FixedFeeSystemWithZeroFee() public {
        // Configure fixed fee system with zero fee
        queue.setFixedExitFeePercent(0, 0);

        // Mock escrow setup
        escrow.setMockLockedBalance(100e18, block.timestamp - 1);

        // Queue exit
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        // Fee should be zero
        assertEq(queue.calculateFee(1), 0);
        assertEq(queue.getTimeBasedFee(0), 0);
        assertEq(queue.getTimeBasedFee(86400), 0);
    }

    /// @notice Test Case B: cooldown > 0, fee = 0 - must wait for no fee exit
    function test_MustWaitForNoFeeExit_CooldownGt0_Fee0() public {
        uint48 cooldown = 86400; // 1 day
        
        // Configure fixed fee system with cooldown > 0 but fee = 0
        queue.setFixedExitFeePercent(0, cooldown);
        
        // Verify configuration
        assertEq(queue.feePercent(), 0);
        assertEq(queue.cooldown(), cooldown);
        assertEq(queue.minCooldown(), cooldown);
        
        // Mock escrow setup
        escrow.setMockLockedBalance(100e18, block.timestamp - 1);
        
        // Queue exit
        uint256 queueTime = block.timestamp;
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));
        
        // Should NOT be able to exit immediately
        assertFalse(queue.canExit(1), "Should not be able to exit immediately");
        
        // Still can't exit before cooldown
        vm.warp(queueTime + cooldown - 1);
        assertFalse(queue.canExit(1), "Should not be able to exit before cooldown");
        
        // Can exit after cooldown
        vm.warp(queueTime + cooldown);
        assertTrue(queue.canExit(1), "Should be able to exit after cooldown");
        
        // Fee should still be zero after waiting
        assertEq(queue.calculateFee(1), 0);
        
        // Exit and verify no fee
        vm.prank(address(escrow));
        uint256 returnedFee = queue.exit(1);
        assertEq(returnedFee, 0, "No fee should be charged");
    }

    /// @notice Test fixed fee system with maximum fee
    function test_FixedFeeSystemWithMaximumFee() public {
        // Configure fixed fee system with maximum fee
        queue.setFixedExitFeePercent(10000, 0);

        // Mock escrow setup
        escrow.setMockLockedBalance(100e18, block.timestamp - 1);

        // Queue exit
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        // Fee should be entire locked amount
        assertEq(queue.calculateFee(1), 100e18);
        assertEq(queue.getTimeBasedFee(0), 10000);
        assertEq(queue.getTimeBasedFee(86400), 10000);
    }

    /// @notice Test fixed fee system with zero cooldown
    function test_FixedFeeSystemWithZeroCooldown() public {
        uint256 feePercent = 500;

        // Configure fixed fee system with zero cooldown and early exit allowed
        queue.setFixedExitFeePercent(feePercent, 0);

        assertEq(queue.cooldown(), 0);
        assertEq(queue.minCooldown(), 0);

        // Configure fixed fee system with zero cooldown and early exit disabled
        queue.setFixedExitFeePercent(feePercent, 0);

        assertEq(queue.cooldown(), 0);
        assertEq(queue.minCooldown(), 0);
    }

    /// @notice Test isCool function with fixed fee system
    function test_IsCoolFunctionWithFixedFeeSystem() public {
        uint256 feePercent = 1000;
        uint48 cooldown = 86400; // 1 day

        // Configure fixed fee system
        queue.setFixedExitFeePercent(feePercent, cooldown);

        // Mock escrow setup
        escrow.setMockLockedBalance(100e18, block.timestamp - 1);

        uint queueTime = block.timestamp;
        // Queue exit
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        // Should not be cool initially
        assertFalse(queue.isCool(1), "should not be cool before cooldown");

        vm.warp(queueTime + cooldown - 1);
        assertFalse(queue.isCool(1), "should not be cool before cooldown ends");

        // Should be cool after cooldown
        vm.warp(block.timestamp + 1);
        assertTrue(queue.isCool(1), "should be cool after cooldown ends");
    }

    /// @notice Test fixed fee system state consistency after multiple reconfigurations
    function test_FixedFeeSystemStateConsistencyAfterReconfigurations() public {
        // Initial configuration
        queue.setFixedExitFeePercent(1000, 0);
        assertEq(queue.feePercent(), 1000);
        assertEq(queue.minFeePercent(), 1000);
        assertEq(queue.minCooldown(), 0);

        // Reconfigure with different parameters
        queue.setFixedExitFeePercent(2000, 172800);
        assertEq(queue.feePercent(), 2000);
        assertEq(queue.minFeePercent(), 2000);
        assertEq(queue.cooldown(), 172800);
        assertEq(queue.minCooldown(), 172800);

        // Reconfigure again
        queue.setFixedExitFeePercent(500, 0);
        assertEq(queue.feePercent(), 500);
        assertEq(queue.minFeePercent(), 500);
        assertEq(queue.cooldown(), 0);
        assertEq(queue.minCooldown(), 0);
        assertEq(queue.slope(), 0);
    }
}