pragma solidity ^0.8.17;

import {ExitQueueBase, DaoUnauthorized} from "./ExitQueueBase.sol";

contract TieredFeeSystemTest is ExitQueueBase {
    /// @notice Test valid tiered fee configuration with fuzz testing
    function testFuzzValidTieredFeeConfiguration(
        uint16 baseFeePercent,
        uint16 earlyFeePercent,
        uint48 cooldown,
        uint48 minCooldown
    ) public {
        // Bound inputs within valid ranges
        baseFeePercent = uint16(bound(baseFeePercent, 0, 9999));
        earlyFeePercent = uint16(bound(earlyFeePercent, baseFeePercent + 1, 10000));
        minCooldown = uint48(bound(minCooldown, 0, type(uint48).max - 1));
        cooldown = uint48(bound(cooldown, minCooldown + 1, type(uint48).max));

        // Configure tiered fee system
        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);

        // Verify state variables
        assertEq(queue.feePercent(), earlyFeePercent);
        assertEq(queue.minFeePercent(), baseFeePercent);
        assertEq(queue.cooldown(), cooldown);
        assertEq(queue.minCooldown(), minCooldown);
        assertEq(queue.slope(), 0);
    }

    /// @notice Test tiered fee configuration emits correct event
    function testTieredFeeConfigurationEmitsEvent() public {
        uint256 baseFeePercent = 1000;
        uint256 earlyFeePercent = 3000;
        uint48 cooldown = 604800; // 7 days
        uint48 minCooldown = 86400; // 1 day

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

    /// @notice Test tiered fee validation - baseFeePercent too high
    function testTieredFeeValidationBaseFeePercentTooHigh() public {
        uint256 baseFeePercent = 10001;
        uint256 earlyFeePercent = 10001;
        uint48 cooldown = 604800;
        uint48 minCooldown = 86400;

        vm.expectRevert(abi.encodeWithSelector(FeePercentTooHigh.selector, 10000));
        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);
    }

    /// @notice Test tiered fee validation - earlyFeePercent too high
    function testTieredFeeValidationEarlyFeePercentTooHigh() public {
        uint256 baseFeePercent = 1000;
        uint256 earlyFeePercent = 10001;
        uint48 cooldown = 604800;
        uint48 minCooldown = 86400;

        vm.expectRevert(abi.encodeWithSelector(FeePercentTooHigh.selector, 10000));
        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);
    }

    /// @notice Test tiered fee validation - both fees too high
    function testTieredFeeValidationBothFeesTooHigh() public {
        uint256 baseFeePercent = 10001;
        uint256 earlyFeePercent = 10002;
        uint48 cooldown = 604800;
        uint48 minCooldown = 86400;

        vm.expectRevert(abi.encodeWithSelector(FeePercentTooHigh.selector, 10000));
        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);
    }

    /// @notice Test tiered fee validation - earlyFeePercent equals baseFeePercent
    function testTieredFeeValidationEarlyFeeEqualsBaseFee() public {
        uint256 baseFeePercent = 2000;
        uint256 earlyFeePercent = 2000;
        uint48 cooldown = 604800;
        uint48 minCooldown = 86400;

        vm.expectRevert(InvalidFeeParameters.selector);
        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);
    }

    /// @notice Test tiered fee validation - earlyFeePercent less than baseFeePercent
    function testTieredFeeValidationEarlyFeeLessThanBaseFee() public {
        uint256 baseFeePercent = 3000;
        uint256 earlyFeePercent = 2000;
        uint48 cooldown = 604800;
        uint48 minCooldown = 86400;

        vm.expectRevert(InvalidFeeParameters.selector);
        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);
    }

    /// @notice Test tiered fee validation - cooldown equals minCooldown
    function testTieredFeeValidationCooldownEqualsMinCooldown() public {
        uint256 baseFeePercent = 1000;
        uint256 earlyFeePercent = 3000;
        uint48 cooldown = 86400;
        uint48 minCooldown = 86400;

        vm.expectRevert(CooldownTooShort.selector);
        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);
    }

    /// @notice Test tiered fee validation - cooldown less than minCooldown
    function testTieredFeeValidationCooldownLessThanMinCooldown() public {
        uint256 baseFeePercent = 1000;
        uint256 earlyFeePercent = 3000;
        uint48 cooldown = 86400;
        uint48 minCooldown = 172800; // 2 days

        vm.expectRevert(CooldownTooShort.selector);
        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);
    }

    /// @notice Test getTimeBasedFee for tiered fee system
    function testGetTimeBasedFeeForTieredSystem() public {
        uint256 baseFeePercent = 1000;
        uint256 earlyFeePercent = 3000;
        uint48 cooldown = 604800; // 7 days
        uint48 minCooldown = 86400; // 1 day

        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);

        // Test timeElapsed = 0
        assertEq(queue.getTimeBasedFee(0), 3000);

        // Test timeElapsed = minCooldown (1 day)
        assertEq(queue.getTimeBasedFee(86400), 3000);

        // Test timeElapsed = cooldown - 1 (just before 7 days)
        assertEq(queue.getTimeBasedFee(604799), 3000);

        // Test timeElapsed = cooldown (exactly 7 days)
        assertEq(queue.getTimeBasedFee(604800), 1000);

        // Test timeElapsed > cooldown (beyond 7 days)
        assertEq(queue.getTimeBasedFee(1000000), 1000);
    }

    /// @notice Test tiered fee system with minimum values
    function testTieredFeeSystemMinimumValues() public {
        uint256 baseFeePercent = 0;
        uint256 earlyFeePercent = 1;
        uint48 cooldown = 1;
        uint48 minCooldown = 0;

        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);

        assertEq(queue.feePercent(), 1);
        assertEq(queue.minFeePercent(), 0);
        assertEq(queue.cooldown(), 1);
        assertEq(queue.minCooldown(), 0);
        assertEq(queue.slope(), 0);
    }

    /// @notice Test tiered fee system with maximum values
    function testTieredFeeSystemMaximumValues() public {
        uint256 baseFeePercent = 9999;
        uint256 earlyFeePercent = 10000;
        uint48 cooldown = type(uint48).max;
        uint48 minCooldown = type(uint48).max - 1;

        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);

        assertEq(queue.feePercent(), 10000);
        assertEq(queue.minFeePercent(), 9999);
        assertEq(queue.cooldown(), type(uint48).max);
        assertEq(queue.minCooldown(), type(uint48).max - 1);
        assertEq(queue.slope(), 0);
    }

    /// @notice Test tiered fee system with realistic values
    function testTieredFeeSystemRealisticValues() public {
        uint256 baseFeePercent = 500; // 5%
        uint256 earlyFeePercent = 2000; // 20%
        uint48 cooldown = 2592000; // 30 days
        uint48 minCooldown = 86400; // 1 day

        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);

        // Test various time points
        assertEq(queue.getTimeBasedFee(0), 2000);
        assertEq(queue.getTimeBasedFee(86400), 2000); // At minCooldown
        assertEq(queue.getTimeBasedFee(1296000), 2000); // 15 days - still early
        assertEq(queue.getTimeBasedFee(2591999), 2000); // Just before cooldown
        assertEq(queue.getTimeBasedFee(2592000), 500); // At cooldown
        assertEq(queue.getTimeBasedFee(5184000), 500); // 60 days - beyond cooldown
    }

    /// @notice Test tiered fee system authorization
    function testTieredFeeSystemRequiresQueueAdminRole() public {
        // Remove admin role from this contract
        dao.revoke({
            _who: address(this),
            _where: address(queue),
            _permissionId: queue.QUEUE_ADMIN_ROLE()
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(queue),
                address(this),
                queue.QUEUE_ADMIN_ROLE()
            )
        );
        queue.setTieredExitFeePercent(1000, 3000, 604800, 86400);
    }

    /// @notice Test tiered fee system boundary conditions
    function testTieredFeeSystemBoundaryConditions() public {
        uint256 baseFeePercent = 1000;
        uint256 earlyFeePercent = 3000;
        uint48 cooldown = 604800;
        uint48 minCooldown = 86400;

        queue.setTieredExitFeePercent(baseFeePercent, earlyFeePercent, cooldown, minCooldown);

        // Test exactly at cooldown boundary
        assertEq(queue.getTimeBasedFee(cooldown), baseFeePercent);

        // Test one second before cooldown
        assertEq(queue.getTimeBasedFee(cooldown - 1), earlyFeePercent);

        // Test one second after cooldown
        assertEq(queue.getTimeBasedFee(cooldown + 1), baseFeePercent);

        // Test exactly at minCooldown boundary
        assertEq(queue.getTimeBasedFee(minCooldown), earlyFeePercent);

        // Test one second before minCooldown
        assertEq(queue.getTimeBasedFee(minCooldown - 1), earlyFeePercent);

        // Test one second after minCooldown
        assertEq(queue.getTimeBasedFee(minCooldown + 1), earlyFeePercent);
    }

    /// @notice Test multiple tiered fee system configurations
    function testMultipleTieredFeeSystemConfigurations() public {
        // First configuration
        queue.setTieredExitFeePercent(500, 2000, 604800, 86400);
        assertEq(queue.feePercent(), 2000);
        assertEq(queue.minFeePercent(), 500);
        assertEq(queue.slope(), 0);

        // Second configuration
        queue.setTieredExitFeePercent(1000, 5000, 1209600, 172800);
        assertEq(queue.feePercent(), 5000);
        assertEq(queue.minFeePercent(), 1000);
        assertEq(queue.slope(), 0);

        // Third configuration
        queue.setTieredExitFeePercent(0, 10000, 2592000, 0);
        assertEq(queue.feePercent(), 10000);
        assertEq(queue.minFeePercent(), 0);
        assertEq(queue.slope(), 0);
    }
}
