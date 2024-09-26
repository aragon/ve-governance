pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {IExitQueue, ExitQueue} from "@escrow/ExitQueue.sol";
import {ExitQueueBase} from "./ExitQueueBase.sol";

contract TestExitQueueWithdrawals is ExitQueueBase {
    function setUp() public override {
        super.setUp();

        dao.grant({
            _who: address(this),
            _where: address(queue),
            _permissionId: queue.QUEUE_ADMIN_ROLE()
        });

        dao.grant({
            _who: address(this),
            _where: address(queue),
            _permissionId: queue.WITHDRAW_ROLE()
        });
    }

    // vary the fee percent with a fixed locked amount to check it calculates correctly
    function testFuzz_feeCalculatesCorretly(uint16 _fee) public {
        if (_fee > queue.MAX_FEE_PERCENT()) {
            _fee = queue.MAX_FEE_PERCENT();
        }
        queue.setFeePercent(_fee);

        uint256 expectedFee = (100e18 * uint(_fee)) / 10_000;

        assertEq(queue.calculateFee(1), expectedFee);
    }

    // zero lock balance reverts
    function testZeroLockedBalanceReverts() public {
        queue.setFeePercent(1); // you need this or it'll early return
        vm.expectRevert(NoLockBalance.selector);
        queue.calculateFee(0);
    }

    // cant set fee percent too high
    function testFeeTooHighReverts() public {
        vm.expectRevert(FeeTooHigh.selector);
        queue.setFeePercent(1e18 + 1);
    }

    // allow only the withdrawer to withdraw
    function testOnlyWithdrawerCanWithdraw(address _notWithdrawer) public {
        vm.assume(_notWithdrawer != address(this));
        bytes memory data = abi.encodeWithSelector(
            DaoUnauthorized.selector,
            address(dao),
            address(queue),
            _notWithdrawer,
            queue.WITHDRAW_ROLE()
        );
        vm.expectRevert(data);
        vm.prank(_notWithdrawer);
        queue.withdraw(0);
    }

    // withdraw the erc20
    function testWithdraw() public {
        token.mint(address(queue), 100e18);

        queue.withdraw(90e18);

        assertEq(token.balanceOf(address(queue)), 10e18);
        assertEq(token.balanceOf(address(this)), 90e18);
    }

    /// @dev using 128 bit integers to avoid overflow
    function testFuzz_CannotQueueWithIfBeforeMinLock(uint128 _minLock, uint128 _lockStart) public {
        // create a lock at a random time
        vm.warp(_lockStart);
        escrow.setMockLockedBalance(100e18, _lockStart);

        // set the min lock to another random time
        queue.setMinLock(_minLock);

        uint256 minLockThreshold = uint256(_minLock) + uint256(_lockStart);

        assertEq(queue.timeToMinLock(1), minLockThreshold);

        vm.startPrank(address(escrow));
        {
            if (minLockThreshold > 0) {
                // warp to one second before the min lock + start
                vm.warp(minLockThreshold - 1);

                bytes memory err = abi.encodeWithSelector(
                    MinLockNotReached.selector,
                    1,
                    _minLock,
                    minLockThreshold
                );
                // expect revert
                vm.expectRevert(err);
                queue.queueExit(1, address(this));
            }

            // warp to the min lock + start - expect success
            vm.warp(minLockThreshold);
            queue.queueExit(1, address(this));
        }
        vm.stopPrank();
    }
}
