pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";
import {ExitQueueBase, DaoUnauthorized, ITicketV2} from "./ExitQueueBase.sol";

contract ExitQueueFeeSystemChangesTest is ExitQueueBase {
    function setUp() public override {
        super.setUp();
        vm.warp(1);
        queue.setMinLock(1);
        escrow.setMockLockedBalance(100e18, block.timestamp - 1);
    }

    /// @notice Test that changing fee percentage doesn't affect existing tickets
    function test_ChangingFeePercent_ExistingTicketsUnaffected() public {
        // Step 1: Configure fixed fee system with 10% fee
        uint256 originalFee = 1000; // 10%
        uint48 cooldown = 86400; // 1 day
        queue.setFixedExitFeePercent(originalFee, cooldown, true);

        // Step 2: Queue exit with original fee
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));
        
        // Verify ticket has original fee and calculate expected fee
        TicketV2 memory ticket = queue.queue(1);
        assertEq(ticket.feePercent, originalFee);
        assertEq(ticket.minFeePercent, originalFee);
        
        uint256 expectedFee = (100e18 * originalFee) / 10000;
        assertEq(queue.calculateFee(1), expectedFee);

        // Step 3: Change fee to 20%
        uint256 newFee = 2000; // 20%
        queue.setFixedExitFeePercent(newFee, cooldown, true);

        // Step 4: Verify old ticket still uses original 10% fee
        assertEq(queue.calculateFee(1), expectedFee);
        
        // Step 5: Verify that the global fee parameters have changed
        assertEq(queue.feePercent(), newFee);
        assertEq(queue.minFeePercent(), newFee);
        
        // Step 6: Also verify the ticket's stored parameters haven't changed
        TicketV2 memory unchangedTicket = queue.queue(1);
        assertEq(unchangedTicket.feePercent, originalFee);
        assertEq(unchangedTicket.minFeePercent, originalFee);
    }

    /// @notice Test that changing min cooldown doesn't affect existing tickets
    function test_ChangingMinCooldown_ExistingTicketsUnaffected() public {
        // Step 1: Configure dynamic fee system with 1 day min cooldown
        uint256 minFee = 500; // 5%
        uint256 maxFee = 2000; // 20%
        uint48 cooldown = 259200; // 3 days
        uint48 originalMinCooldown = 86400; // 1 day
        queue.setDynamicExitFeePercent(minFee, maxFee, cooldown, originalMinCooldown);

        // Step 2: Queue exit with original min cooldown
        uint256 queueTime = block.timestamp;
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));
        
        // Verify ticket has original min cooldown and calculate expected fee at min cooldown
        TicketV2 memory ticket = queue.queue(1);
        assertEq(ticket.minCooldown, originalMinCooldown);
        
        // Step 3: Warp to min cooldown and check fee (should be max fee)
        vm.warp(queueTime + originalMinCooldown);
        uint256 expectedMaxFee = (100e18 * maxFee) / 10000;
        assertEq(queue.calculateFee(1), expectedMaxFee);
        
        // Step 4: Change min cooldown to 2 days
        uint48 newMinCooldown = 172800; // 2 days
        queue.setDynamicExitFeePercent(minFee, maxFee, cooldown, newMinCooldown);

        // Step 5: Verify old ticket can still exit and fee is unchanged
        assertTrue(queue.canExit(1));
        assertEq(queue.calculateFee(1), expectedMaxFee);
        
        // Step 6: Verify global min cooldown has changed
        assertEq(queue.minCooldown(), newMinCooldown);
        
        // Step 7: Verify ticket still has original min cooldown and fee parameters
        TicketV2 memory unchangedTicket = queue.queue(1);
        assertEq(unchangedTicket.minCooldown, originalMinCooldown);
        assertEq(unchangedTicket.feePercent, maxFee);
        assertEq(unchangedTicket.minFeePercent, minFee);
    }

    /// @notice Test that changing cooldown doesn't affect existing tickets
    function test_ChangingCooldown_ExistingTicketsUnaffected() public {
        // Step 1: Configure dynamic fee system with 3 day cooldown
        uint256 minFee = 500; // 5%
        uint256 maxFee = 2000; // 20%
        uint48 originalCooldown = 259200; // 3 days
        uint48 minCooldown = 86400; // 1 day
        queue.setDynamicExitFeePercent(minFee, maxFee, originalCooldown, minCooldown);

        // Step 2: Queue exit with original cooldown
        uint256 queueTime = block.timestamp;
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));
        
        // Verify ticket has original cooldown
        TicketV2 memory ticket = queue.queue(1);
        assertEq(ticket.cooldown, originalCooldown);
        
        // Step 3: Calculate fee at halfway point
        uint256 halfwayTime = minCooldown + (originalCooldown - minCooldown) / 2;
        vm.warp(queueTime + halfwayTime);
        uint256 halfwayFee = queue.calculateFee(1);
        
        // Verify fee is between min and max (dynamic decay)
        assertLt(halfwayFee, (100e18 * maxFee) / 10000);
        assertGt(halfwayFee, (100e18 * minFee) / 10000);
        
        // Step 4: Change cooldown to 5 days
        uint48 newCooldown = 432000; // 5 days
        queue.setDynamicExitFeePercent(minFee, maxFee, newCooldown, minCooldown);
        
        // Step 5: Verify old ticket fee calculation is unchanged
        assertEq(queue.calculateFee(1), halfwayFee);
        
        // Step 6: Verify that isCool() still uses original cooldown
        assertFalse(queue.isCool(1)); // Not cool yet at halfway point
        vm.warp(queueTime + originalCooldown);
        assertTrue(queue.isCool(1)); // Cool after original cooldown
        
        // Step 7: Verify fee is now at minimum
        uint256 minFeeAmount = (100e18 * minFee) / 10000;
        assertEq(queue.calculateFee(1), minFeeAmount);
        
        // Step 8: Verify ticket still has original cooldown parameter
        TicketV2 memory unchangedTicket = queue.queue(1);
        assertEq(unchangedTicket.cooldown, originalCooldown);
        
        // Step 9: Verify global cooldown has changed
        assertEq(queue.cooldown(), newCooldown);
    }

    /// @notice Test that ticket state is properly cleared after exit
    function test_TicketStateClearedAfterExit() public {
        // Step 1: Configure dynamic fee system
        uint256 minFee = 500; // 5%
        uint256 maxFee = 2000; // 20%
        uint48 cooldown = 259200; // 3 days
        uint48 minCooldown = 86400; // 1 day
        queue.setDynamicExitFeePercent(minFee, maxFee, cooldown, minCooldown);

        // Step 2: Queue exit
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));
        
        // Verify ticket exists with correct parameters
        TicketV2 memory ticket = queue.queue(1);
        assertEq(ticket.holder, address(this));
        assertEq(ticket.feePercent, maxFee);
        assertEq(ticket.minFeePercent, minFee);
        assertEq(ticket.cooldown, cooldown);
        assertEq(ticket.minCooldown, minCooldown);
        assertGt(ticket.slope, 0);
        assertGt(ticket.queuedAt, 0);
        
        // Step 3: Wait for min cooldown and exit
        vm.warp(block.timestamp + minCooldown);
        vm.prank(address(escrow));
        queue.exit(1);
        
        // Step 4: Verify ticket is completely cleared
        TicketV2 memory clearedTicket = queue.queue(1);
        assertEq(clearedTicket.holder, address(0));
        assertEq(clearedTicket.queuedAt, 0);
        assertEq(clearedTicket.feePercent, 0);
        assertEq(clearedTicket.minFeePercent, 0);
        assertEq(clearedTicket.cooldown, 0);
        assertEq(clearedTicket.minCooldown, 0);
        assertEq(clearedTicket.slope, 0);
        
        // Step 5: Verify canExit and isCool return false for cleared ticket
        assertFalse(queue.canExit(1));
        assertFalse(queue.isCool(1));
        
        // Step 6: Verify ticketHolder returns zero address
        assertEq(queue.ticketHolder(1), address(0));
    }
}