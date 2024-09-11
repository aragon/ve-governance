pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {IExitQueue, ExitQueue} from "@escrow/ExitQueue.sol";
import {ExitQueueBase} from "./ExitQueueBase.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

contract MockEscrow {
    struct LockedBalance {
        uint256 amount;
        uint256 start;
    }

    address public token;

    constructor(address _token) {
        token = _token;
    }

    function locked(uint tokenid) external pure returns (LockedBalance memory) {
        if (tokenid == 1) return LockedBalance(100e18, 0);
        else return LockedBalance(0, 0);
    }
}

contract TestExitQueueWithdrawals is ExitQueueBase {
    MockERC20 token;

    function setUp() public override {
        super.setUp();

        token = new MockERC20();
        MockEscrow escrow = new MockEscrow(address(token));

        queue = _deployExitQueue(address(escrow), 0, address(dao), 0);

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
    function testFuzz_feeCalculatesCorretly(uint64 _fee) public {
        if (_fee > 1e18) {
            _fee = 1e18;
        }
        queue.setFeePercent(_fee);

        uint256 expectedFee = (100e18 * uint(_fee)) / 1e18;

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
}
