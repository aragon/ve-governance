pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";
import {ExitQueueBase, DaoUnauthorized} from "./ExitQueueBase.sol";

contract DynamicExitQueueExitTest is ExitQueueBase {
    function setUp() public override {
        super.setUp();
        vm.warp(2);
        queue.setMinLock(1);
        queue.setFixedExitFeePercent(1000, 86400, true); // 10% fee, 1 day cooldown, early exit allowed
    }

    /// @notice Test successful queue exit
    function test_SuccessfulQueueExit() public {
        address ticketHolder = makeAddr("ticketHolder");
        uint256 tokenId = 1;

        // Mock escrow setup - need to be past minLock (strictly greater than)
        escrow.setMockLockedBalance(100e18, block.timestamp - 2);

        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit ExitQueuedV2(tokenId, ticketHolder, uint48(block.timestamp));

        // Queue exit from escrow
        vm.prank(address(escrow));
        queue.queueExit(tokenId, ticketHolder);

        // Verify ticket creation
        TicketV2 memory ticket = queue.queue(tokenId);
        assertEq(ticket.holder, ticketHolder);
        assertEq(ticket.queuedAt, block.timestamp);
        assertEq(queue.ticketHolder(tokenId), ticketHolder);
    }

    /// @notice Test queue exit authorization
    function test_QueueExitAuthorization() public {
        address ticketHolder = makeAddr("ticketHolder");
        uint256 tokenId = 1;

        // Mock escrow setup - need to be past minLock (strictly greater than)
        escrow.setMockLockedBalance(100e18, block.timestamp - 2);

        // Attempt to queue exit from non-escrow address
        vm.expectRevert(OnlyEscrow.selector);
        queue.queueExit(tokenId, ticketHolder);
    }

    /// @notice Test queue exit validation - zero address
    function test_QueueExitValidation_ZeroAddress() public {
        uint256 tokenId = 1;

        // Mock escrow setup - need to be past minLock (strictly greater than)
        escrow.setMockLockedBalance(100e18, block.timestamp - 2);

        // Attempt to queue exit with zero address
        vm.prank(address(escrow));
        vm.expectRevert(ZeroAddress.selector);
        queue.queueExit(tokenId, address(0));
    }

    /// @notice Test queue exit validation - already queued
    function test_QueueExitValidation_AlreadyQueued() public {
        address ticketHolder = makeAddr("ticketHolder");
        uint256 tokenId = 1;

        // Mock escrow setup - need to be past minLock (strictly greater than)
        escrow.setMockLockedBalance(100e18, block.timestamp - 2);

        // Queue exit first time
        vm.prank(address(escrow));
        queue.queueExit(tokenId, ticketHolder);

        // Attempt to queue exit again
        vm.prank(address(escrow));
        vm.expectRevert(AlreadyQueued.selector);
        queue.queueExit(tokenId, ticketHolder);
    }

    /// @notice Test queue exit validation - minLock not reached
    function test_QueueExitValidation_MinLockNotReached() public {
        address ticketHolder = makeAddr("ticketHolder");
        uint256 tokenId = 1;
        uint48 minLock = 86400; // 1 day

        vm.warp(minLock);

        // Set higher minLock
        queue.setMinLock(minLock);

        // Mock escrow to return lock start time such that minLock period hasn't elapsed
        // Now need to be 1 second more than minLock to pass, so test with exactly minLock
        uint48 lockStart = uint48(block.timestamp - minLock);
        escrow.setMockLockedBalance(100e18, lockStart);

        // Calculate expected minLockTime
        uint48 expectedMinLockTime = lockStart + minLock;

        // Attempt to queue exit at exactly minLock boundary (should fail now)
        vm.prank(address(escrow));
        vm.expectRevert(
            abi.encodeWithSelector(
                MinLockNotReached.selector,
                tokenId,
                minLock,
                expectedMinLockTime
            )
        );
        queue.queueExit(tokenId, ticketHolder);
    }

    /// @notice Test queue exit validation - minLock boundary (now requires > not >=)
    function test_QueueExitValidation_MinLockBoundary() public {
        address ticketHolder = makeAddr("ticketHolder");
        uint256 tokenId = 1;
        uint48 minLock = 86400; // 1 day

        vm.warp(minLock + 1); // Move forward 1 second

        // Set minLock
        queue.setMinLock(minLock);

        // Mock escrow to return lock start time exactly at minLock boundary
        uint48 lockStart = uint48(block.timestamp - minLock - 1); // 1 second past minLock
        escrow.setMockLockedBalance(100e18, lockStart);

        // Should succeed when > minLock
        vm.prank(address(escrow));
        queue.queueExit(tokenId, ticketHolder);

        // Verify ticket creation
        TicketV2 memory ticket = queue.queue(tokenId);
        assertEq(ticket.holder, ticketHolder);
        assertEq(ticket.queuedAt, block.timestamp);
    }

    /// @notice Test that exactly at minLock boundary fails
    function test_QueueExitValidation_ExactMinLockBoundaryFails() public {
        address ticketHolder = makeAddr("ticketHolder");
        uint256 tokenId = 1;
        uint48 minLock = 86400; // 1 day

        vm.warp(minLock);

        // Set minLock
        queue.setMinLock(minLock);

        // Mock escrow to return lock start time exactly at minLock boundary
        uint48 lockStart = uint48(block.timestamp - minLock);
        escrow.setMockLockedBalance(100e18, lockStart);

        // Should fail at exactly minLock boundary
        vm.prank(address(escrow));
        vm.expectRevert(
            abi.encodeWithSelector(
                MinLockNotReached.selector,
                tokenId,
                minLock,
                lockStart + minLock
            )
        );
        queue.queueExit(tokenId, ticketHolder);
    }

    /// @notice Test successful exit
    function test_SuccessfulExit() public {
        address ticketHolder = makeAddr("ticketHolder");
        uint256 tokenId = 1;
        uint256 lockedAmount = 100e18;

        // Mock escrow setup - need to be past minLock (strictly greater than)
        escrow.setMockLockedBalance(lockedAmount, block.timestamp - 2);

        // Queue exit
        vm.prank(address(escrow));
        queue.queueExit(tokenId, ticketHolder);

        // Fast forward past minCooldown
        vm.warp(block.timestamp + 1);

        // Calculate expected fee
        uint256 expectedFee = queue.calculateFee(tokenId);

        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit Exit(tokenId, expectedFee);

        // Exit from escrow
        vm.prank(address(escrow));
        uint256 returnedFee = queue.exit(tokenId);

        // Verify fee returned
        assertEq(returnedFee, expectedFee);

        // Verify ticket is cleared
        TicketV2 memory ticket = queue.queue(tokenId);
        assertEq(ticket.holder, address(0));
        assertEq(ticket.queuedAt, 0);
    }

    /// @notice Test exit authorization
    function test_ExitAuthorization() public {
        address ticketHolder = makeAddr("ticketHolder");
        uint256 tokenId = 1;

        // Mock escrow setup - need to be past minLock (strictly greater than)
        escrow.setMockLockedBalance(100e18, block.timestamp - 2);

        // Queue exit
        vm.prank(address(escrow));
        queue.queueExit(tokenId, ticketHolder);

        // Fast forward past minCooldown
        vm.warp(block.timestamp + 1);

        // Attempt to exit from non-escrow address
        vm.expectRevert(OnlyEscrow.selector);
        queue.exit(tokenId);
    }

    /// @notice Test exit validation - cannot exit
    function test_ExitValidation_CannotExit() public {
        address ticketHolder = makeAddr("ticketHolder");
        uint256 tokenId = 1;

        // Mock escrow setup - need to be past minLock (strictly greater than)
        escrow.setMockLockedBalance(100e18, block.timestamp - 2);

        // Queue exit
        vm.prank(address(escrow));
        queue.queueExit(tokenId, ticketHolder);

        // Attempt to exit immediately (before minCooldown)
        vm.prank(address(escrow));
        vm.expectRevert(CannotExit.selector);
        queue.exit(tokenId);
    }

    /// @notice Test exit fee calculation consistency with fuzz testing
    function test_ExitFeeCalculationConsistency(uint208 lockedAmount, uint256 timeOffset) public {
        lockedAmount = uint208(bound(lockedAmount, 1e18, 1e30)); // Cap at reasonable value
        timeOffset = bound(timeOffset, 86401, 259200); // Between minCooldown+1 and 3 days

        address ticketHolder = makeAddr("ticketHolder");

        // Configure dynamic fee system for more interesting fee calculations
        queue.setDynamicExitFeePercent(500, 3000, 172800, 86400); // 5% to 30%, 2 day cooldown, 1 day minCooldown

        // Mock escrow setup - need to be past minLock (strictly greater than)
        escrow.setMockLockedBalance(lockedAmount, block.timestamp - 2);

        // Queue exit
        uint256 queueTime = block.timestamp;
        vm.prank(address(escrow));
        queue.queueExit(1, ticketHolder);

        // Warp to test time
        vm.warp(queueTime + timeOffset);

        // Calculate expected fee
        uint256 expectedFee = queue.calculateFee(1);

        // Exit and capture returned fee
        vm.prank(address(escrow));
        uint256 returnedFee = queue.exit(1);

        // Verify consistency
        assertEq(returnedFee, expectedFee, "Returned fee should match calculateFee result");

        // Test bounds and properties
        assertLe(returnedFee, (lockedAmount * 3000) / 10000, "Fee should not exceed max 30%");
        assertGe(returnedFee, (lockedAmount * 500) / 10000, "Fee should be at least min 5%");
        assertLe(returnedFee, lockedAmount, "Fee should not exceed locked amount");
    }
}

contract DynamicExitQueueQueueExitTest is ExitQueueBase {
    function setUp() public override {
        super.setUp();
        vm.warp(2);
        queue.setMinLock(1);
        queue.setFixedExitFeePercent(1000, 86400, true);
    }

    /// @notice Test queue exit with different ticket holders
    function testFuzz_QueueExitWithDifferentTicketHolders(address ticketHolder) public {
        vm.assume(ticketHolder != address(0));
        uint256 tokenId = 1;

        // Mock escrow setup - need to be past minLock (strictly greater than)
        escrow.setMockLockedBalance(100e18, block.timestamp - 2);

        // Queue exit
        vm.prank(address(escrow));
        queue.queueExit(tokenId, ticketHolder);

        // Verify ticket holder
        assertEq(queue.ticketHolder(tokenId), ticketHolder);

        TicketV2 memory ticket = queue.queue(tokenId);
        assertEq(ticket.holder, ticketHolder);
    }

    /// @notice Test queue exit with different token IDs
    function testFuzz_QueueExitWithDifferentTokenIds(uint256 tokenId) public {
        address ticketHolder = makeAddr("ticketHolder");

        // Mock escrow setup - need to be past minLock (strictly greater than)
        escrow.setMockLockedBalance(100e18, block.timestamp - 2);

        // Queue exit
        vm.prank(address(escrow));
        queue.queueExit(tokenId, ticketHolder);

        // Verify ticket creation
        TicketV2 memory ticket = queue.queue(tokenId);
        assertEq(ticket.holder, ticketHolder);
        assertEq(ticket.queuedAt, block.timestamp);
    }

    /// @notice Test queue exit timing precision
    function test_QueueExitTimingPrecision() public {
        address ticketHolder = makeAddr("ticketHolder");
        uint256 tokenId = 1;

        // Mock escrow setup - need to be past minLock (strictly greater than)
        escrow.setMockLockedBalance(100e18, block.timestamp - 2);

        uint256 queueTime = block.timestamp;

        // Queue exit
        vm.prank(address(escrow));
        queue.queueExit(tokenId, ticketHolder);

        // Verify exact timestamp
        TicketV2 memory ticket = queue.queue(tokenId);
        assertEq(ticket.queuedAt, queueTime);
    }

    /// @notice Test multiple queue exits for different tokens
    function test_MultipleQueueExitsForDifferentTokens() public {
        address ticketHolder1 = makeAddr("ticketHolder1");
        address ticketHolder2 = makeAddr("ticketHolder2");

        // Mock escrow setup - need to be past minLock (strictly greater than)
        escrow.setMockLockedBalance(100e18, block.timestamp - 2);

        uint256 queueTime = block.timestamp;

        // Queue exit for token 1
        vm.prank(address(escrow));
        queue.queueExit(1, ticketHolder1);

        // Advance time slightly
        vm.warp(block.timestamp + 10);

        // Queue exit for token 2
        vm.prank(address(escrow));
        queue.queueExit(2, ticketHolder2);

        // Verify both tickets
        TicketV2 memory ticket1 = queue.queue(1);
        TicketV2 memory ticket2 = queue.queue(2);

        assertEq(ticket1.holder, ticketHolder1);
        assertEq(ticket1.queuedAt, queueTime);
        assertEq(ticket2.holder, ticketHolder2);
        assertEq(ticket2.queuedAt, queueTime + 10);
    }

    function testFuzz_QueueExitWithVariousMinLockPeriods(uint48 minLock) public {
        minLock = uint48(bound(minLock, 1, type(uint48).max - 2));
        address ticketHolder = makeAddr("ticketHolder");
        uint256 tokenId = 1;
        vm.warp(minLock + 2); // Start at a time that allows for proper testing

        queue.setMinLock(minLock);

        uint48 lockStart = uint48(block.timestamp - minLock - 2); // Set lock start appropriately
        escrow.setMockLockedBalance(100e18, lockStart);

        uint48 minLockEnd = lockStart + minLock;

        // Test at exactly minLock boundary (should fail)
        vm.warp(minLockEnd);
        vm.expectRevert(
            abi.encodeWithSelector(MinLockNotReached.selector, tokenId, minLock, minLockEnd)
        );
        vm.prank(address(escrow));
        queue.queueExit(tokenId, ticketHolder);

        // Test at 1 second past minLock boundary (should succeed)
        vm.warp(minLockEnd + 1);
        vm.prank(address(escrow));
        queue.queueExit(tokenId, ticketHolder);

        TicketV2 memory ticket = queue.queue(tokenId);
        assertEq(ticket.holder, ticketHolder);
        assertEq(ticket.queuedAt, minLockEnd + 1);
    }
}

