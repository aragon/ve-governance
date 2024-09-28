pragma solidity ^0.8.17;

import {TestHelpers} from "@helpers/TestHelpers.sol";

import {console2 as console} from "forge-std/console2.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {IExitQueue, ExitQueue} from "@escrow/ExitQueue.sol";
import {IExitQueueErrorsAndEvents} from "@escrow-interfaces/IExitQueue.sol";
import {IVotingEscrowEventsStorageErrorsEvents} from "@escrow-interfaces/IVotingEscrowIncreasing.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

contract MockEscrow {
    struct LockedBalance {
        uint256 amount;
        uint256 start;
    }

    address public token;

    LockedBalance public lockedBalance = LockedBalance(100e18, 0);

    function setMockLockedBalance(uint256 _amount, uint256 _start) public {
        lockedBalance = LockedBalance(_amount, _start);
    }

    constructor(address _token) {
        token = _token;
    }

    function locked(uint tokenid) external view returns (LockedBalance memory) {
        if (tokenid == 1) return lockedBalance;
        else return LockedBalance(0, 0);
    }
}

contract ExitQueueBase is TestHelpers, IExitQueueErrorsAndEvents {
    using ProxyLib for address;

    ExitQueue queue;
    MockERC20 token;
    MockEscrow escrow;

    function _deployExitQueue(
        address _escrow,
        uint _cooldown,
        address _dao,
        uint256 _feePercent,
        address _clock,
        uint256 _minLock
    ) public returns (ExitQueue) {
        ExitQueue impl = new ExitQueue();

        bytes memory initCalldata = abi.encodeCall(
            ExitQueue.initialize,
            (_escrow, _cooldown, _dao, _feePercent, _clock, _minLock)
        );
        return ExitQueue(address(impl).deployUUPSProxy(initCalldata));
    }

    function setUp() public virtual override {
        super.setUp();
        token = new MockERC20();
        escrow = new MockEscrow(address(token));
        queue = _deployExitQueue(address(escrow), 0, address(dao), 0, address(clock), 1);
        dao.grant({
            _who: address(this),
            _where: address(queue),
            _permissionId: queue.QUEUE_ADMIN_ROLE()
        });
    }
}
