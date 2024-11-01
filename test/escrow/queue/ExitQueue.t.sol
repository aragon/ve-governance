pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {IExitQueue, ExitQueue} from "@escrow/ExitQueue.sol";
import {ITicket} from "@escrow-interfaces/IExitQueue.sol";
import {ExitQueueBase} from "./ExitQueueBase.sol";

contract TestExitQueue is ExitQueueBase, ITicket {
    // test inital state - escrow, queue, cooldown is set in constructor + dao
    function testFuzz_initialState(
        address _escrow,
        uint16 _fee,
        uint48 _cooldown,
        address _clock,
        uint48 _minLock
    ) public {
        vm.assume(_fee <= 10_000);
        vm.assume(_minLock > 0);
        DAO dao_ = createTestDAO(address(this));
        queue = _deployExitQueue(
            address(_escrow),
            _cooldown,
            address(dao_),
            _fee,
            _clock,
            _minLock
        );
        assertEq(queue.escrow(), _escrow);
        assertEq(queue.cooldown(), _cooldown);
        assertEq(queue.minLock(), _minLock);
        assertEq(address(queue.dao()), address(dao_));
        assertEq(queue.feePercent(), _fee);
    }

    function testFuzz_canUpdateMinLock(uint48 _minLock) public {
        vm.assume(_minLock > 0);
        vm.expectEmit(false, false, false, true);
        emit MinLockSet(_minLock);
        queue.setMinLock(_minLock);
        assertEq(queue.minLock(), _minLock);

        // test that the minLock cannot be set to 0
        vm.expectRevert(MinLockOutOfBounds.selector);
        queue.setMinLock(0);
    }

    function testOnlyManagerCanUpdateMinLock(address _notThis) public {
        vm.assume(_notThis != address(this));
        bytes memory data = abi.encodeWithSelector(
            DaoUnauthorized.selector,
            address(dao),
            address(queue),
            _notThis,
            queue.QUEUE_ADMIN_ROLE()
        );
        vm.expectRevert(data);
        vm.prank(_notThis);
        queue.setMinLock(123);
    }

    function testFuzz_canUpdateFee(uint16 _fee) public {
        vm.assume(_fee <= 10_000);
        vm.expectEmit(false, false, true, false);
        emit FeePercentSet(_fee);
        queue.setFeePercent(_fee);
        assertEq(queue.feePercent(), _fee);
    }

    function testOnlyManagerCanUpdateFee(address _notThis) public {
        vm.assume(_notThis != address(this));
        bytes memory data = abi.encodeWithSelector(
            DaoUnauthorized.selector,
            address(dao),
            address(queue),
            _notThis,
            queue.QUEUE_ADMIN_ROLE()
        );
        vm.expectRevert(data);
        vm.prank(_notThis);
        queue.setFeePercent(0);
    }

    // test the exit queue manager can udpdate the cooldown && emits event
    function testFuzz_canUpdateCooldown(uint48 _cooldown) public {
        vm.expectEmit(false, false, false, true);
        emit CooldownSet(_cooldown);
        queue.setCooldown(_cooldown);
        assertEq(queue.cooldown(), _cooldown);
    }

    function testOnlyManagerCanUpdateCooldown(address _notThis) public {
        vm.assume(_notThis != address(this));
        bytes memory data = abi.encodeWithSelector(
            DaoUnauthorized.selector,
            address(dao),
            address(queue),
            _notThis,
            queue.QUEUE_ADMIN_ROLE()
        );
        vm.expectRevert(data);
        vm.prank(_notThis);
        queue.setCooldown(0);
    }

    // test only the escrow can call stateful functions
    function testFuzz_onlyEscrowCanCall(address _notEscrow) public {
        vm.assume(_notEscrow != address(escrow));
        bytes memory err = abi.encodeWithSelector(OnlyEscrow.selector);

        vm.startPrank(_notEscrow);
        {
            vm.expectRevert(err);
            queue.exit(0);

            vm.expectRevert(err);
            queue.queueExit(0, address(this));
        }

        vm.stopPrank();
    }

    // test queuing the ticket older reverts if address == 0
    function testQueueRevertZeroAddress() public {
        bytes memory err = abi.encodeWithSelector(ZeroAddress.selector);
        vm.expectRevert(err);
        vm.prank(address(escrow));
        queue.queueExit(0, address(0));
    }

    // test can't double queue the same token
    function testFuzzCannotDoubleQueueSameToken(address _holder, address _otherHolder) public {
        vm.assume(_holder != address(0));
        vm.assume(_otherHolder != address(0));

        vm.startPrank(address(escrow));
        {
            queue.queueExit(0, _holder);
            bytes memory err = abi.encodeWithSelector(AlreadyQueued.selector);
            vm.expectRevert(err);
            queue.queueExit(0, _holder);

            // other holder same issue
            vm.expectRevert(err);
            queue.queueExit(0, _otherHolder);
        }
        vm.stopPrank();
    }

    // test emits a queued event and writes to state
    function testFuzz_canQueue(uint256 _tokenId, address _ticketHolder, uint32 _warp) public {
        vm.assume(_ticketHolder != address(0));
        vm.assume(_warp > 0); // any time other than genesis
        vm.warp(_warp);
        // if there are less than cooldown seconds left, exit date is end of the
        // week, else it's now + cooldown
        uint expectedExitDate;
        uint remainingSecondsBeforeNextCP = 1 weeks - (block.timestamp % 1 weeks);

        if (queue.cooldown() < remainingSecondsBeforeNextCP) {
            expectedExitDate = block.timestamp + remainingSecondsBeforeNextCP;
        } else {
            expectedExitDate = block.timestamp + queue.cooldown();
        }

        vm.expectEmit(true, true, false, true);
        emit ExitQueued(_tokenId, _ticketHolder, expectedExitDate);
        vm.prank(address(escrow));
        queue.queueExit(_tokenId, _ticketHolder);
        assertEq(queue.ticketHolder(_tokenId), _ticketHolder);
        assertEq(queue.queue(_tokenId).exitDate, expectedExitDate);
    }

    // test can exit updates only after the cooldown period
    function testFuzz_canExit(uint48 _cooldown) public {
        vm.assume(_cooldown > 0);
        vm.warp(1);

        queue.setCooldown(_cooldown);

        // this will trigger a 0,0 locked balance
        uint256 tokenId = 420;

        vm.prank(address(escrow));
        queue.queueExit(tokenId, address(this));

        assertFalse(queue.canExit(tokenId));

        vm.warp(queue.nextExitDate());
        assertFalse(queue.canExit(tokenId));

        vm.warp(queue.nextExitDate() + 1);
        assertTrue(queue.canExit(tokenId));
    }

    // test that changing the cooldown doesn't affect the current ticket holders
    function testChangingCooldownDoesntAffectCurrentHolders() public {
        // set the lock to start at 1 week
        escrow.setMockLockedBalance(100e18, 1 weeks);

        // warp to first week - this is the min lock period as the lock starts week aligned
        vm.warp(1 weeks);

        // set a cooldown to 3 days
        queue.setCooldown(3 days);

        // warp to almost the end of the upcoming week - this means we wont snap to the next week
        // but we can actually test the cooldown
        vm.warp(1 weeks + 6 days);

        // queue a ticket
        vm.prank(address(escrow));
        queue.queueExit(1, address(this));

        // check the ticket
        Ticket memory ticket = queue.queue(1);
        // ticket should be in 3 days from now
        assertEq(ticket.exitDate, 2 weeks + 2 days);

        // change the cooldown to 1 day
        queue.setCooldown(1 weeks + 1 days);

        // warp to total of 2 days in the future
        vm.warp(block.timestamp + 2 days);

        // should still not be able to exit
        assertFalse(queue.canExit(1));

        // warp to 3 days
        vm.warp(block.timestamp + 1 days);

        // should not be able to exit
        assertFalse(queue.canExit(1));

        // warp to 3d + 1
        vm.warp(block.timestamp + 1);

        assertTrue(queue.canExit(1));

        // change the cooldown to 5 days
        queue.setCooldown(5 days);

        // should still be able to exit
        assertTrue(queue.canExit(1));
    }

    // test can exit and this resets the ticket
    function testFuzz_canExitAndResetsTicket(address _holder) public {
        vm.assume(_holder != address(0));
        vm.warp(1 weeks);

        uint time = block.timestamp;
        // set the lock to start at 1 week
        escrow.setMockLockedBalance(100e18, 1 weeks);

        // warp to almost the end of the upcoming week - this means we wont snap to the next week
        // but we can actually test the cooldown
        vm.warp(2 weeks - 1);

        queue.setCooldown(100);

        uint256 _tokenId = 420;

        vm.prank(address(escrow));
        queue.queueExit(_tokenId, _holder);

        vm.warp(2 weeks + 99);

        vm.expectRevert(CannotExit.selector);
        vm.prank(address(escrow));
        queue.exit(_tokenId);

        vm.warp(2 weeks + 100);

        vm.expectEmit(true, false, false, true);
        emit Exit(_tokenId, 0);
        vm.prank(address(escrow));
        queue.exit(_tokenId);

        assertEq(queue.ticketHolder(_tokenId), address(0));
        assertEq(queue.queue(_tokenId).exitDate, 0);

        vm.expectRevert(CannotExit.selector);
        vm.prank(address(escrow));
        queue.exit(_tokenId);
    }

    function testUUPSUpgrade() public {
        address newImpl = address(new ExitQueue());
        queue.upgradeTo(newImpl);
        assertEq(queue.implementation(), newImpl);

        bytes memory err = _authErr(address(1), address(queue), queue.QUEUE_ADMIN_ROLE());
        vm.prank(address(1));
        vm.expectRevert(err);
        queue.upgradeTo(newImpl);
    }
}
