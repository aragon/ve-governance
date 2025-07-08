pragma solidity ^0.8.17;

import {ProxyLib, ExitQueueBase, DynamicExitQueue} from "./ExitQueueBase.sol";

contract InitTest is ExitQueueBase {
    using ProxyLib for address;
    function test_init_sets_values() public {
        assertEq(queue.escrow(), address(escrow));
        assertEq(queue.cooldown(), 0);
        assertEq(queue.feePercent(), 0);
        assertEq(queue.minLock(), 1);
        assertEq(address(queue.dao()), address(dao));
        assertEq(queue.clock(), address(clock));
    }

    function test_init_cannot_be_called_twice() public {
        vm.expectRevert("Initializable: contract is already initialized");
        queue.initialize(address(escrow), 0, address(dao), 0, address(clock), 1);
    }

    function test_init_sets_dynamic_fee_params() public {
        assertEq(queue.minFeePercent(), 0);
        assertEq(queue.minCooldown(), 0);
        assertEq(queue.slope(), 0);
    }

    function test_init_with_different_fee_percent() public {
        DynamicExitQueue newQueue = _deployDynamicExitQueue(
            address(escrow),
            1000,
            address(dao),
            500,
            address(clock),
            86400
        );

        assertEq(newQueue.feePercent(), 500);
        assertEq(newQueue.cooldown(), 1000);
        assertEq(newQueue.minLock(), 86400);
    }

    function test_init_with_max_fee_percent() public {
        DynamicExitQueue newQueue = _deployDynamicExitQueue(
            address(escrow),
            0,
            address(dao),
            10000,
            address(clock),
            1
        );

        assertEq(newQueue.feePercent(), 10000);
    }

    function test_init_reverts_if_fee_percent_too_high() public {
        DynamicExitQueue impl = new DynamicExitQueue();

        bytes memory initCalldata = abi.encodeCall(
            DynamicExitQueue.initialize,
            (address(escrow), 1, address(dao), 10_001, address(clock), 1)
        );

        vm.expectRevert(abi.encodeWithSelector(FeePercentTooHigh.selector, 10000));
        address(impl).deployUUPSProxy(initCalldata);
    }
    function test_init_emits_min_lock_set_event() public {
        vm.expectEmit(true, true, true, true);
        emit MinLockSet(3600);

        _deployDynamicExitQueue(address(escrow), 0, address(dao), 0, address(clock), 3600);
    }

    function test_init_sets_correct_roles() public {
        assertEq(queue.QUEUE_ADMIN_ROLE(), keccak256("QUEUE_ADMIN"));
        assertEq(queue.WITHDRAW_ROLE(), keccak256("WITHDRAW_ROLE"));
    }
}
