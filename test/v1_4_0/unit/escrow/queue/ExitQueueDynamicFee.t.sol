pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";
import {ExitQueueBase, DaoUnauthorized} from "./ExitQueueBase.sol";

contract DynamicExitQueueDynamicFeeTest is ExitQueueBase {
    function setUp() public override {
        super.setUp();
        vm.warp(1);
        queue.setMinLock(1);
    }

    /// @notice Test valid dynamic fee configuration
    function testFuzz_ValidDynamicFeeConfiguration(
        uint256 _minFeePercent,
        uint256 _maxFeePercent,
        uint48 _cooldown,
        uint48 _minCooldown
    ) public {
        // Bound inputs within valid ranges
        _minFeePercent = bound(_minFeePercent, 0, 9999);
        _maxFeePercent = bound(_maxFeePercent, _minFeePercent + 1, 10000);
        vm.assume(_cooldown > 0);
        _minCooldown = uint48(bound(_minCooldown, 0, _cooldown - 1));

        // Configure dynamic fee system
        queue.setDynamicExitFeePercent(_minFeePercent, _maxFeePercent, _cooldown, _minCooldown);

        // Assert state variables match input parameters
        assertEq(queue.feePercent(), _maxFeePercent);
        assertEq(queue.minFeePercent(), _minFeePercent);
        assertEq(queue.cooldown(), _cooldown);
        assertEq(queue.minCooldown(), _minCooldown);
    }

    /// @notice Test dynamic fee validation - fee bounds
    function test_DynamicFeeValidation_FeeBounds() public {
        // Test minFeePercent = 10001
        vm.expectRevert(abi.encodeWithSelector(FeePercentTooHigh.selector, 10000));
        queue.setDynamicExitFeePercent(10001, 5000, 86400, 43200);

        // Test maxFeePercent = 10001
        vm.expectRevert(abi.encodeWithSelector(FeePercentTooHigh.selector, 10000));
        queue.setDynamicExitFeePercent(5000, 10001, 86400, 43200);

        // Test both fees > 10000
        vm.expectRevert(abi.encodeWithSelector(FeePercentTooHigh.selector, 10000));
        queue.setDynamicExitFeePercent(10001, 10002, 86400, 43200);
    }

    /// @notice Test dynamic fee validation - fee relationship
    function test_DynamicFeeValidation_FeeRelationship() public {
        // Test maxFeePercent == minFeePercent
        vm.expectRevert(InvalidFeeParameters.selector);
        queue.setDynamicExitFeePercent(3000, 3000, 86400, 43200);

        // Test maxFeePercent < minFeePercent
        vm.expectRevert(InvalidFeeParameters.selector);
        queue.setDynamicExitFeePercent(3000, 2000, 86400, 43200);
    }

    /// @notice Test dynamic fee validation - cooldown relationship
    function test_DynamicFeeValidation_CooldownRelationship() public {
        // Test cooldown == minCooldown
        vm.expectRevert(CooldownTooShort.selector);
        queue.setDynamicExitFeePercent(1000, 3000, 86400, 86400);

        // Test cooldown < minCooldown
        vm.expectRevert(CooldownTooShort.selector);
        queue.setDynamicExitFeePercent(1000, 3000, 43200, 86400);
    }

    /// @notice Test dynamic fee edge cases
    function test_DynamicFeeEdgeCases() public {
        // Test minCooldown = 0, cooldown = 1 (1 second decay)
        queue.setDynamicExitFeePercent(0, 10000, 1, 0);
        assertEq(queue.slope(), (10000 * 1e18) / 10_000);

        // Test very long decay periods
        queue.setDynamicExitFeePercent(1000, 5000, 365 days, 0);
        uint256 expectedSlope = ((uint(5000 - 1000) * 1e18) / uint(365 days)) / 10_000;
        assertEq(queue.slope(), expectedSlope);
    }

    /// @notice Test ExitFeePercentAdjusted event emission for dynamic fee
    function test_ExitFeePercentAdjustedEvent_DynamicFee() public {
        uint256 minFeePercent = 1000;
        uint256 maxFeePercent = 5000;
        uint48 cooldown = 518400; // 6 days
        uint48 minCooldown = 172800; // 2 days

        uint256 expectedSlope = (maxFeePercent - minFeePercent) / (cooldown - minCooldown);

        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit ExitFeePercentAdjusted(maxFeePercent, minFeePercent, minCooldown, ExitFeeType.Dynamic);

        queue.setDynamicExitFeePercent(minFeePercent, maxFeePercent, cooldown, minCooldown);
    }

    /// @notice Test hardcoded dynamic fee scenario 1
    function test_HardcodedDynamicFeeScenario1() public {
        // Configure: minFeePercent = 0, maxFeePercent = 10000, cooldown = 4 weeks, minCooldown = 2 weeks
        uint256 minFeePercent = 0;
        uint256 maxFeePercent = 10000;
        uint48 cooldown = 4 weeks;
        uint48 minCooldown = 2 weeks;

        queue.setDynamicExitFeePercent(minFeePercent, maxFeePercent, cooldown, minCooldown);

        // Test timeElapsed = 0: Assert returns 10000 (100%)
        assertEq(queue.getTimeBasedFee(0), 10000);

        // Test timeElapsed = 2 weeks: Assert returns 10000 (100%)
        assertEq(queue.getTimeBasedFee(2 weeks), 10000);
        assertEq(queue.getTimeBasedFee(2 weeks + 1), 9999);

        // Test timeElapsed = 3 weeks: Assert returns 5000 (50%)
        assertEq(queue.getTimeBasedFee(3 weeks), 5000);

        assertEq(queue.getTimeBasedFee(3.5 weeks), 2500);

        // Test timeElapsed = 4 weeks: Assert returns 0 (0%)
        assertEq(queue.getTimeBasedFee(4 weeks), 0);

        // Test timeElapsed > 4 weeks: Assert returns 0 (0%)
        assertEq(queue.getTimeBasedFee(5 weeks), 0);
    }

    /// @notice Test hardcoded dynamic fee scenario 2
    function test_HardcodedDynamicFeeScenario2() public {
        // Configure: minFeePercent = 1000, maxFeePercent = 2000, cooldown = 1 year, minCooldown = 0
        uint256 minFeePercent = 1000;
        uint256 maxFeePercent = 2000;
        uint48 cooldown = 365 days;
        uint48 minCooldown = 0;

        queue.setDynamicExitFeePercent(minFeePercent, maxFeePercent, cooldown, minCooldown);

        // Test timeElapsed = 0: Assert returns 2000 (20%)
        assertEq(queue.getTimeBasedFee(0), 2000);

        // Test timeElapsed = 1 second: Assert returns < 2000
        uint256 feeAt1Second = queue.getTimeBasedFee(1);
        assertLt(feeAt1Second, 2000);

        // Test timeElapsed = 6 months: Assert returns 1500 (15%)
        assertEq(queue.getTimeBasedFee(182.5 days), 1500);

        // Test timeElapsed = 1 year: Assert returns 1000 (10%)
        assertEq(queue.getTimeBasedFee(365 days), 1000);

        // Test timeElapsed > 1 year: Assert returns 1000 (10%)
        assertEq(queue.getTimeBasedFee(400 days), 1000);
    }

    /// @notice Test getTimeBasedFee for dynamic fee system
    function test_GetTimeBasedFeeForDynamicFeeSystem() public {
        // Configure dynamic system: minFee = 1000, maxFee = 5000, cooldown = 6 days, minCooldown = 2 days
        uint256 minFeePercent = 1000;
        uint256 maxFeePercent = 5000;
        uint48 cooldown = 518400; // 6 days
        uint48 minCooldown = 172800; // 2 days

        queue.setDynamicExitFeePercent(minFeePercent, maxFeePercent, cooldown, minCooldown);

        // Test timeElapsed = 0: Assert returns 5000
        assertEq(queue.getTimeBasedFee(0), 5000);

        // Test timeElapsed = 2 days: Assert returns 5000
        assertEq(queue.getTimeBasedFee(172800), 5000);

        // Test timeElapsed = 3 days: Assert returns approximately 4000
        uint256 feeAt3Days = queue.getTimeBasedFee(259200);
        assertApproxEqAbs(feeAt3Days, 4000, 50);

        // Test timeElapsed = 4 days: Assert returns approximately 3000
        uint256 feeAt4Days = queue.getTimeBasedFee(345600);
        assertApproxEqAbs(feeAt4Days, 3000, 50);

        // Test timeElapsed = 5 days: Assert returns approximately 2000
        uint256 feeAt5Days = queue.getTimeBasedFee(432000);
        assertApproxEqAbs(feeAt5Days, 2000, 50);

        // Test timeElapsed = 6 days: Assert returns 1000
        assertEq(queue.getTimeBasedFee(518400), 1000);

        // Test timeElapsed > 6 days: Assert returns 1000
        assertEq(queue.getTimeBasedFee(1000000), 1000);
    }

    /// @notice Test dynamic fee system boundary conditions
    function test_DynamicFeeSystemBoundaryConditions() public {
        uint256 minFeePercent = 1000;
        uint256 maxFeePercent = 5000;
        uint48 cooldown = 518400; // 6 days
        uint48 minCooldown = 172800; // 2 days

        queue.setDynamicExitFeePercent(minFeePercent, maxFeePercent, cooldown, minCooldown);

        // Test exactly at minCooldown timestamp
        assertEq(
            queue.getTimeBasedFee(minCooldown),
            maxFeePercent,
            "Fee should be max at minCooldown"
        );

        // Test one second before cooldown
        // this suffers from the min precision problem so we used the scale value
        uint256 feeBeforeCooldown = queue.getScaledTimeBasedFee(cooldown - 1);
        assertGt(
            feeBeforeCooldown,
            (minFeePercent * 1e18) / 10_000,
            "Fee should be greater than min before cooldown"
        );
        assertEq(
            queue.getTimeBasedFee(cooldown - 1),
            minFeePercent,
            "Fee should be min before cooldown due to scaling"
        );

        // Test exactly at cooldown timestamp
        assertEq(queue.getTimeBasedFee(cooldown), minFeePercent, "Fee should be min at cooldown");

        // Test one second after cooldown
        assertEq(
            queue.getTimeBasedFee(cooldown + 1),
            minFeePercent,
            "Fee should remain min after cooldown"
        );
    }

    /// @notice Test dynamic fee system precision handling
    function test_DynamicFeeSystemPrecisionHandling() public {
        // Configure system with maximum fee difference and minimum time difference
        uint256 minFeePercent = 0;
        uint256 maxFeePercent = 10000;
        uint48 cooldown = 2;
        uint48 minCooldown = 1;

        queue.setDynamicExitFeePercent(minFeePercent, maxFeePercent, cooldown, minCooldown);

        // Test fee reduction calculation doesn't overflow
        uint256 feeReduction = queue.getTimeBasedFee(1);
        assertEq(feeReduction, maxFeePercent);

        // Test fee reduction doesn't exceed maximum possible reduction
        uint256 feeAfterDecay = queue.getTimeBasedFee(2);
        assertEq(feeAfterDecay, minFeePercent);
    }

    /// @notice Test dynamic fee system with active tickets
    function test_DynamicFeeSystemBehaviorWithActiveTickets() public {
        uint256 minFeePercent = 1000;
        uint256 maxFeePercent = 5000;
        uint48 cooldown = 518400; // 6 days
        uint48 minCooldown = 172800; // 2 days

        queue.setDynamicExitFeePercent(minFeePercent, maxFeePercent, cooldown, minCooldown);

        // Mock escrow setup
        escrow.setMockLockedBalance(100e18, block.timestamp - 1);

        uint queueTime = block.timestamp;
        // Queue exit
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        // Should not be able to exit immediately (before minCooldown)
        assertFalse(queue.canExit(1));

        // Should pay max fee at minCooldown
        vm.warp(queueTime + minCooldown);
        assertTrue(queue.canExit(1));
        assertEq(
            queue.calculateFee(1),
            (100e18 * maxFeePercent) / 10000,
            "Fee should be max at minCooldown"
        );

        vm.warp(queueTime + minCooldown + 1);
        assertLt(
            queue.calculateFee(1),
            (100e18 * maxFeePercent) / 10000,
            "Fee should be less than max after minCooldown"
        );

        // Should pay reduced fee during decay period
        vm.warp(queueTime + minCooldown + (cooldown - minCooldown) / 2);
        uint256 midDecayFee = queue.calculateFee(1);
        assertLt(
            midDecayFee,
            (100e18 * maxFeePercent) / 10000,
            "Mid decay fee should be less than max fee"
        );
        assertGt(
            midDecayFee,
            (100e18 * minFeePercent) / 10000,
            "Mid decay fee should be greater than min fee"
        );

        // Should pay min fee after cooldown
        vm.warp(queueTime + cooldown + 1);
        assertEq(
            queue.calculateFee(1),
            (100e18 * minFeePercent) / 10000,
            "Fee should be min after cooldown"
        );
    }

    /// @notice Test dynamic fee system with zero minCooldown
    function test_DynamicFeeSystemWithZeroMinCooldown() public {
        uint256 minFeePercent = 500;
        uint256 maxFeePercent = 2000;
        uint48 cooldown = 86400; // 1 day
        uint48 minCooldown = 0;

        queue.setDynamicExitFeePercent(minFeePercent, maxFeePercent, cooldown, minCooldown);

        // Mock escrow setup
        escrow.setMockLockedBalance(100e18, block.timestamp - 1);

        uint queueTime = block.timestamp;
        // Queue exit
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        // Should be able to exit immediately and pay max fee
        vm.warp(queueTime + 1);
        assertTrue(queue.canExit(1));
        uint256 immediateFee = queue.calculateFee(1);
        assertLt(immediateFee, (100e18 * maxFeePercent) / 10000);

        // Should pay min fee after cooldown
        vm.warp(queueTime + cooldown + 1);
        assertEq(queue.calculateFee(1), (100e18 * minFeePercent) / 10000);
    }

    /// @notice Test dynamic fee system with maximum fee difference
    function test_DynamicFeeSystemWithMaximumFeeDifference() public {
        uint256 minFeePercent = 0;
        uint256 maxFeePercent = 10000;
        uint48 cooldown = 86400; // 1 day
        uint48 minCooldown = 43200; // 12 hours

        queue.setDynamicExitFeePercent(minFeePercent, maxFeePercent, cooldown, minCooldown);

        // Mock escrow setup
        escrow.setMockLockedBalance(100e18, block.timestamp - 1);

        uint queueTime = block.timestamp;
        // Queue exit
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        // Should pay 100% fee at minCooldown
        vm.warp(queueTime + minCooldown);
        assertEq(queue.calculateFee(1), 100e18);

        // Should pay 50% fee at midpoint
        vm.warp(queueTime + minCooldown + (cooldown - minCooldown) / 2);
        assertApproxEqRel(queue.calculateFee(1), 50e18, 0.001e18);
        // Should pay 0% fee at/after cooldown
        vm.warp(queueTime + cooldown);
        assertEq(queue.calculateFee(1), 0);
    }

    /// @notice Test isCool function with dynamic fee system
    function test_IsCoolFunctionWithDynamicFeeSystem() public {
        uint256 minFeePercent = 1000;
        uint256 maxFeePercent = 5000;
        uint48 cooldown = 518400; // 6 days
        uint48 minCooldown = 172800; // 2 days

        queue.setDynamicExitFeePercent(minFeePercent, maxFeePercent, cooldown, minCooldown);

        // Mock escrow setup
        escrow.setMockLockedBalance(100e18, block.timestamp - 1);

        uint queueTime = block.timestamp;
        // Queue exit
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        // Should not be cool during decay period
        vm.warp(queueTime + minCooldown + 1);
        assertFalse(queue.isCool(1));

        // Should not be cool at cooldown boundary
        vm.warp(queueTime + cooldown - 1);
        assertFalse(queue.isCool(1));

        // Should be cool after cooldown
        vm.warp(queueTime + cooldown);
        assertTrue(queue.isCool(1));
    }

    function expSlope(
        uint256 minFeePercent,
        uint256 maxFeePercent,
        uint48 cooldown,
        uint48 minCooldown
    ) internal pure returns (uint256) {
        return (((maxFeePercent - minFeePercent) * 1e18) / (cooldown - minCooldown)) / 10_000;
    }

    /// @notice Test dynamic fee system state consistency after multiple reconfigurations
    function test_DynamicFeeSystemStateConsistencyAfterReconfigurations() public {
        // Initial configuration
        queue.setDynamicExitFeePercent(1000, 5000, 86400, 43200);
        assertEq(queue.feePercent(), 5000);
        assertEq(queue.minFeePercent(), 1000);
        assertEq(queue.cooldown(), 86400);
        assertEq(queue.minCooldown(), 43200);
        assertEq(queue.slope(), expSlope(1000, 5000, 86400, 43200));

        // Reconfigure with different parameters
        queue.setDynamicExitFeePercent(500, 3000, 172800, 86400);
        assertEq(queue.feePercent(), 3000);
        assertEq(queue.minFeePercent(), 500);
        assertEq(queue.cooldown(), 172800);
        assertEq(queue.minCooldown(), 86400);
        assertEq(queue.slope(), expSlope(500, 3000, 172800, 86400));

        // Reconfigure with edge case parameters
        queue.setDynamicExitFeePercent(0, 10000, 604800, 0);
        assertEq(queue.feePercent(), 10000);
        assertEq(queue.minFeePercent(), 0);
        assertEq(queue.cooldown(), 604800);
        assertEq(queue.minCooldown(), 0);
        assertEq(queue.slope(), expSlope(0, 10000, 604800, 0));
    }

    function testFeeReductionScalesToMinFee() public {
        // Setup: minFee=100 (1%), maxFee=1000 (10%), minCooldown=60, cooldown=300
        queue.setDynamicExitFeePercent(100, 1000, 300, 60);

        uint256 tokenId = 1;
        uint256 lockAmount = 1000e18; // 1000 tokens
        uint lockStart = block.timestamp;

        escrow.setMockLockedBalance(lockAmount, lockStart);

        // Queue exit
        vm.warp(lockStart + 1);
        vm.prank(address(escrow));
        queue.queueExit(tokenId, address(1));

        // Test fee reduction caps at minimum fee
        vm.warp(block.timestamp + 500); // Way past cooldown (300s) - should trigger the >= condition

        // Verify fee percent is minimum (100 basis points = 1%)
        uint256 feePercent = queue.getTimeBasedFee(500);
        assertEq(feePercent, 100, "Fee should be capped at minimum");

        // Verify absolute fee amount is minimum fee applied to lock amount
        uint256 actualFee = queue.calculateFee(tokenId);
        uint256 expectedFee = 10e18; // 1% of 1000 tokens = 10 tokens
        assertEq(
            actualFee,
            expectedFee,
            "Absolute fee should be minimum fee applied to lock amount"
        );
    }
}
