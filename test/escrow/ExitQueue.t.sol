pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";

import {console2 as console} from "forge-std/console2.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {IExitQueue, ExitQueue} from "@escrow/ExitQueue.sol";
import {IExitQueueEvents, IExitQueueErrors} from "@escrow-interfaces/IExitQueue.sol";

contract TestExitQueue is Test, IExitQueueEvents, IExitQueueErrors {
    ExitQueue queue;
    DAO dao;
    using ProxyLib for address;

    function _deployExitQueue(
        address _escrow,
        uint _cooldown,
        address _dao
    ) public returns (ExitQueue) {
        ExitQueue impl = new ExitQueue();

        bytes memory initCalldata = abi.encodeCall(
            ExitQueue.initialize,
            (_escrow, _cooldown, _dao)
        );
        return ExitQueue(address(impl).deployUUPSProxy(initCalldata));
    }

    function setUp() public {
        dao = createTestDAO(address(this));
        queue = _deployExitQueue(address(this), 0, address(dao));
        dao.grant({
            _who: address(this),
            _where: address(queue),
            _permissionId: queue.QUEUE_ADMIN_ROLE()
        });
    }

    // test inital state - escrow, queue, cooldown is set in constructor + dao
    function testFuzz_initialState(address _escrow, uint256 _cooldown) public {
        DAO dao_ = createTestDAO(address(this));
        queue = _deployExitQueue(address(_escrow), _cooldown, address(dao_));
        assertEq(queue.escrow(), _escrow);
        assertEq(queue.cooldown(), _cooldown);
        assertEq(address(queue.dao()), address(dao_));
    }

    // test the exit queue manager can udpdate the cooldown && emits event
    function testFuzz_canUpdateCooldown(uint256 _cooldown) public {
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
        vm.assume(_notEscrow != address(this));
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
        queue.queueExit(0, address(0));
    }

    // test can't double queue the same token
    function testFuzzCannotDoubleQueueSameToken(address _holder, address _otherHolder) public {
        vm.assume(_holder != address(0));
        vm.assume(_otherHolder != address(0));

        queue.queueExit(0, _holder);
        bytes memory err = abi.encodeWithSelector(AlreadyQueued.selector);
        vm.expectRevert(err);
        queue.queueExit(0, _holder);

        // other holder same issue
        vm.expectRevert(err);
        queue.queueExit(0, _otherHolder);
    }

    // test emits a queued event and writes to state
    function testFuzz_canQueue(uint256 _tokenId, address _ticketHolder, uint32 _warp) public {
        vm.assume(_ticketHolder != address(0));
        vm.warp(_warp);

        vm.expectEmit(true, true, false, true);
        emit ExitQueued(_tokenId, _ticketHolder);
        queue.queueExit(_tokenId, _ticketHolder);
        assertEq(queue.ticketHolder(_tokenId), _ticketHolder);
        assertEq(queue.queue(_tokenId).timestamp, block.timestamp);
    }

    // test can exit updates only after the cooldown period
    function testFuzz_canExit(uint216 _cooldown) public {
        queue.setCooldown(_cooldown);

        uint256 tokenId = 420;
        uint time = block.timestamp;

        queue.queueExit(tokenId, address(this));
        if (_cooldown == 0) {
            assert(queue.canExit(tokenId));
        } else {
            assertFalse(queue.canExit(tokenId));
            vm.warp(time + _cooldown - 1);
            assertFalse(queue.canExit(tokenId));

            vm.warp(time + _cooldown);
            assertTrue(queue.canExit(tokenId));
        }
    }

    // test that changing the cooldown doesn't affect the current ticket holders (TODO)

    // test can exit and this resets the ticket
    function testFuzz_canExit(address _holder) public {
        vm.assume(_holder != address(0));
        vm.warp(0);

        queue.setCooldown(100);

        uint256 _tokenId = 420;

        queue.queueExit(_tokenId, _holder);

        vm.warp(99);

        vm.expectRevert(CannotExit.selector);
        queue.exit(_tokenId);

        vm.warp(100);

        vm.expectEmit(true, false, false, true);
        emit Exit(_tokenId);
        queue.exit(_tokenId);

        assertEq(queue.ticketHolder(_tokenId), address(0));
        assertEq(queue.queue(_tokenId).timestamp, 0);

        vm.expectRevert(CannotExit.selector);
        queue.exit(_tokenId);
    }
}
