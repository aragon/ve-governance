pragma solidity ^0.8.17;

import {ExitQueueBase, DaoUnauthorized} from "./ExitQueueBase.sol";

contract DynamicExitQueueTieredFeeTest is ExitQueueBase {
    function setUp() public override {
        super.setUp();
        vm.warp(1);
        queue.setMinLock(1);
    }

    /// @notice Test valid tiered fee configuration
    function testFuzz_ValidTieredFeeConfiguration(
        uint256 _baseFeePercent,
        uint256 _earlyFeePercent,
        uint48 _cooldown,
        uint48 _minCooldown
    ) public {
        // Bound inputs within valid ranges
        _baseFeePercent = bound(_baseFeePercent, 0, 9999);
        _earlyFeePercent = bound(_earlyFeePercent, _baseFeePercent + 1, 10000);
        vm.assume(_cooldown > 0);
        _minCooldown = uint48(bound(_minCooldown, 0, _cooldown - 1));

        // Configure tiered fee system
        queue.setTieredExitFeePercent(_baseFeePercent, _earlyFeePercent, _cooldown, _minCooldown);

        // Assert state variables match input parameters
        assertEq(queue.feePercent(), _earlyFeePercent);
        assertEq(queue.minFeePercent(), _baseFeePercent);
        assertEq(queue.cooldown(), _cooldown);
        assertEq(queue.minCooldown(), _minCooldown);
        assertEq(queue.slope(), 0);
    }

    /// @notice Test tiered fee validation - fee bounds
    function test_TieredFeeValidation_FeeBounds() public {
        // Test baseFeePercent = 10001
        vm.expectRevert(abi.encodeWithSelector(FeePercentTooHigh.selector, 10000));
        queue.setTieredExitFeePercent(10001, 5000, 86400, 43200);

        // Test earlyFeePercent = 10001
        vm.expectRevert(abi.encodeWithSelector(FeePercentTooHigh.selector, 10000));
        queue.setTieredExitFeePercent(5000, 10001, 86400, 43200);
    }

    /// @notice Test tiered fee validation - fee relationship
    function test_TieredFeeValidation_FeeRelationship() public {
        // Test earlyFeePercent == baseFeePercent
        vm.expectRevert(InvalidFeeParameters.selector);
        queue.setTieredExitFeePercent(3000, 3000, 86400, 43200);

        // Test earlyFeePercent < baseFeePercent
        vm.expectRevert(InvalidFeeParameters.selector);
        queue.setTieredExitFeePercent(3000, 2000, 86400, 43200);
    }

    /// @notice Test tiered fee validation - cooldown relationship
    function test_TieredFeeValidation_CooldownRelationship() public {
        // Test cooldown == minCooldown
        vm.expectRevert(CooldownTooShort.selector);
        queue.setTieredExitFeePercent(1000, 3000, 86400, 86400);

        // Test cooldown < minCooldown
        vm.expectRevert(CooldownTooShort.selector);
        queue.setTieredExitFeePercent(1000, 3000, 43200, 86400);
    }

    /// @notice Test ExitFeePercentAdjusted event emission for tiered fee
    function test_ExitFeePercentAdjustedEvent_TieredFee() public {
        uint256 baseFeePercent = 1000;
        uint256 earlyFeePercent = 3000;
        uint48 cooldown = 604800; // 7 days
        uint48 minCooldown = 86400; // 1 day

        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit ExitFeePercentAdjusted(
            earlyFeePercent,
            baseFeePercent,
            0,
            minCooldown,
            ExitFeeType.Tiered
        );

        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);
    }

    /// @notice Test getTimeBasedFee for tiered fee system
    function test_GetTimeBasedFeeForTieredFeeSystem() public {
        uint256 baseFeePercent = 1000;
        uint256 earlyFeePercent = 3000;
        uint48 cooldown = 604800; // 7 days
        uint48 minCooldown = 86400; // 1 day

        // Configure tiered fee system
        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);

        // Test timeElapsed = 0 (before minCooldown)
        assertEq(queue.getTimeBasedFee(0), 3000, "0");

        // Test timeElapsed = minCooldown (exactly at boundary)
        assertEq(queue.getTimeBasedFee(86400), 3000, "1 day");

        // Test timeElapsed just at cooldown
        assertEq(queue.getTimeBasedFee(604800), 3000, "7 days");

        // Test timeElapsed > (exactly after boundary)
        assertEq(queue.getTimeBasedFee(604801), 1000, "7 days + 1 second");

        // Test timeElapsed beyond cooldown
        assertEq(queue.getTimeBasedFee(1000000), 1000, "> 7 days + 1 second");
    }

    /// @notice Test tiered fee system behavior with active tickets
    function test_TieredFeeSystemBehaviorWithActiveTickets() public {
        uint256 baseFeePercent = 1000;
        uint256 earlyFeePercent = 3000;
        uint48 cooldown = 604800; // 7 days
        uint48 minCooldown = 86400; // 1 day

        // Configure tiered fee system
        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);

        // Mock escrow setup
        escrow.setMockLockedBalance(100e18, block.timestamp - 1);

        uint queueTime = block.timestamp;
        // Queue exit
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        // Should not be able to exit immediately (before minCooldown)
        assertFalse(queue.canExit(1));

        // Should pay early fee during early exit period
        vm.warp(queueTime + minCooldown + 1);
        assertTrue(queue.canExit(1));
        assertEq(queue.calculateFee(1), (100e18 * earlyFeePercent) / 10000);

        // Should still pay early fee just before cooldown
        vm.warp(queueTime + cooldown);
        assertEq(queue.calculateFee(1), (100e18 * earlyFeePercent) / 10000);

        // Should pay base fee after cooldown
        vm.warp(queueTime + cooldown + 1);
        assertEq(queue.calculateFee(1), (100e18 * baseFeePercent) / 10000);
    }

    /// @notice Test tiered fee system with zero minCooldown
    function test_TieredFeeSystemWithZeroMinCooldown() public {
        uint256 baseFeePercent = 500;
        uint256 earlyFeePercent = 2000;
        uint48 cooldown = 86400; // 1 day
        uint48 minCooldown = 0;

        // Configure tiered fee system with zero minCooldown
        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);

        // Mock escrow setup
        escrow.setMockLockedBalance(100e18, block.timestamp - 1);

        uint queueTime = block.timestamp;
        // Queue exit
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        // Should be able to exit after 1 second
        vm.warp(queueTime + 1);
        assertTrue(queue.canExit(1), "Exit should be allowed immediately");

        // Should pay early fee
        assertEq(queue.calculateFee(1), (100e18 * earlyFeePercent) / 10000);

        // Should pay base fee after cooldown
        vm.warp(queueTime + cooldown + 1);
        assertEq(queue.calculateFee(1), (100e18 * baseFeePercent) / 10000);
    }

    /// @notice Test tiered fee system with maximum fee difference
    function test_TieredFeeSystemWithMaximumFeeDifference() public {
        uint256 baseFeePercent = 0;
        uint256 earlyFeePercent = 10000;
        uint48 cooldown = 86400; // 1 day
        uint48 minCooldown = 43200; // 12 hours

        // Configure tiered fee system with maximum fee difference
        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);

        // Mock escrow setup
        escrow.setMockLockedBalance(100e18, block.timestamp - 1);

        uint queueTime = block.timestamp;
        // Queue exit
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        // Should pay 100% fee during early exit period
        vm.warp(queueTime + minCooldown + 1);
        assertEq(queue.calculateFee(1), 100e18);

        // Should pay 0% fee after cooldown
        vm.warp(queueTime + cooldown + 1);
        assertEq(queue.calculateFee(1), 0);
    }

    /// @notice Test tiered fee system with minimal fee difference
    function test_TieredFeeSystemWithMinimalFeeDifference() public {
        uint256 baseFeePercent = 9999;
        uint256 earlyFeePercent = 10000;
        uint48 cooldown = 86400; // 1 day
        uint48 minCooldown = 43200; // 12 hours

        // Configure tiered fee system with minimal fee difference
        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);

        // Mock escrow setup
        escrow.setMockLockedBalance(100e18, block.timestamp - 1);

        uint queueTime = block.timestamp;
        // Queue exit
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        // Should pay 100% fee during early exit period
        vm.warp(queueTime + minCooldown + 1);
        assertEq(queue.calculateFee(1), 100e18);

        // Should pay 99.99% fee after cooldown
        vm.warp(queueTime + cooldown + 1);
        assertEq(queue.calculateFee(1), (100e18 * 9999) / 10000);
    }

    /// @notice Test isCool function with tiered fee system
    function test_IsCoolFunctionWithTieredFeeSystem() public {
        uint256 baseFeePercent = 1000;
        uint256 earlyFeePercent = 3000;
        uint48 cooldown = 604800; // 7 days
        uint48 minCooldown = 86400; // 1 day

        // Configure tiered fee system
        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);

        // Mock escrow setup
        escrow.setMockLockedBalance(100e18, block.timestamp - 1);

        uint queueTime = block.timestamp;
        // Queue exit
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        // Should not be cool before cooldown
        assertFalse(queue.isCool(1));

        // Should not be cool at cooldown boundary
        vm.warp(queueTime + cooldown);
        assertFalse(queue.isCool(1));

        // Should be cool after cooldown
        vm.warp(queueTime + cooldown + 1);
        assertTrue(queue.isCool(1));
    }

    /// @notice Test tiered fee system boundary conditions
    function test_TieredFeeSystemBoundaryConditions() public {
        uint256 baseFeePercent = 1000;
        uint256 earlyFeePercent = 3000;
        uint48 cooldown = 604800; // 7 days
        uint48 minCooldown = 86400; // 1 day

        // Configure tiered fee system
        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);

        // Test exactly at minCooldown timestamp
        assertEq(queue.getTimeBasedFee(minCooldown), earlyFeePercent);

        // Test one second before cooldown
        assertEq(queue.getTimeBasedFee(cooldown - 1), earlyFeePercent);

        // Test exactly at cooldown timestamp
        assertEq(queue.getTimeBasedFee(cooldown), earlyFeePercent);

        // Test one second after cooldown
        assertEq(queue.getTimeBasedFee(cooldown + 1), baseFeePercent);
    }

    /// @notice Test tiered fee system state consistency after multiple reconfigurations
    function test_TieredFeeSystemStateConsistencyAfterReconfigurations() public {
        // Initial configuration
        queue.setTieredExitFeePercent(1000, 3000, 86400, 43200);
        assertEq(queue.feePercent(), 3000);
        assertEq(queue.minFeePercent(), 1000);
        assertEq(queue.cooldown(), 86400);
        assertEq(queue.minCooldown(), 43200);
        assertEq(queue.slope(), 0);

        // Reconfigure with different parameters
        queue.setTieredExitFeePercent(500, 2000, 172800, 86400);
        assertEq(queue.feePercent(), 2000);
        assertEq(queue.minFeePercent(), 500);
        assertEq(queue.cooldown(), 172800);
        assertEq(queue.minCooldown(), 86400);
        assertEq(queue.slope(), 0);

        // Reconfigure with edge case parameters
        queue.setTieredExitFeePercent(0, 10000, 604800, 0);
        assertEq(queue.feePercent(), 10000);
        assertEq(queue.minFeePercent(), 0);
        assertEq(queue.cooldown(), 604800);
        assertEq(queue.minCooldown(), 0);
        assertEq(queue.slope(), 0);
    }
}
