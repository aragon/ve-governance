pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {ExitQueueBase, DynamicExitQueue, IDynamicExitQueue, ITicket, ITicketV2} from "./ExitQueueBase.sol";

contract TestExitQueueCancel is ExitQueueBase {
    function setUp() public override {
        super.setUp();
        vm.warp(1);
    }

    function test_CancelExit() public {
        // Setup: Create a lock and queue an exit
        uint256 tokenId = 1;
        address holder = address(this);
        
        // Mock the escrow locked balance - set start time to 0 so it's before current time
        escrow.setMockLockedBalance(100e18, 0);
        
        // Queue an exit as escrow
        vm.prank(address(escrow));
        queue.queueExit(tokenId, holder);
        
        // Verify the ticket exists
        ITicketV2.TicketV2 memory ticket = queue.queue(tokenId);
        assertEq(ticket.holder, holder);
        assertNotEq(ticket.queuedAt, 0);
        assertEq(queue.ticketHolder(tokenId), holder);
        
        // Cancel the exit
        vm.prank(address(escrow));
        vm.expectEmit(true, true, false, true);
        emit ExitCancelled(tokenId, holder);
        queue.cancelExit(tokenId);
        
        // Verify the ticket is cleared
        ticket = queue.queue(tokenId);
        assertEq(ticket.holder, address(0));
        assertEq(ticket.queuedAt, 0);
        assertEq(queue.ticketHolder(tokenId), address(0));
    }

    function testRevert_CancelExitNotEscrow() public {
        // Setup: Create a lock and queue an exit
        uint256 tokenId = 1;
        address holder = address(this);
        
        // Mock the escrow locked balance - set start time to 0 so it's before current time
        escrow.setMockLockedBalance(100e18, 0);
        
        // Queue an exit as escrow
        vm.prank(address(escrow));
        queue.queueExit(tokenId, holder);
        
        // Try to cancel as non-escrow
        vm.expectRevert(OnlyEscrow.selector);
        queue.cancelExit(tokenId);
    }

    function testRevert_CancelExitNotQueued() public {
        // Try to cancel a non-existent exit
        uint256 tokenId = 1;
        
        vm.prank(address(escrow));
        vm.expectRevert(CannotCancelExit.selector);
        queue.cancelExit(tokenId);
    }

    function test_CancelExitMultipleTokens() public {
        // Setup: Create multiple locks and queue exits
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;
        
        address holder1 = address(0x1);
        address holder2 = address(0x2);
        address holder3 = address(0x3);
        
        // Mock the escrow locked balances
        escrow.setMockLockedBalance(100e18, 0);
        
        // Queue exits as escrow
        vm.startPrank(address(escrow));
        queue.queueExit(tokenIds[0], holder1);
        queue.queueExit(tokenIds[1], holder2);
        queue.queueExit(tokenIds[2], holder3);
        vm.stopPrank();
        
        // Cancel the middle exit
        vm.prank(address(escrow));
        vm.expectEmit(true, true, false, true);
        emit ExitCancelled(tokenIds[1], holder2);
        queue.cancelExit(tokenIds[1]);
        
        // Verify only the middle ticket is cleared
        ITicketV2.TicketV2 memory ticket = queue.queue(tokenIds[0]);
        assertEq(ticket.holder, holder1);
        assertNotEq(ticket.queuedAt, 0);
        
        ticket = queue.queue(tokenIds[1]);
        assertEq(ticket.holder, address(0));
        assertEq(ticket.queuedAt, 0);
        
        ticket = queue.queue(tokenIds[2]);
        assertEq(ticket.holder, holder3);
        assertNotEq(ticket.queuedAt, 0);
    }
}