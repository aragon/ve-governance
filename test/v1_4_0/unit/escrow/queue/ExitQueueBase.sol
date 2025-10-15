pragma solidity ^0.8.17;

import {TestHelpers} from "@helpers/TestHelpers.sol";

import {console2 as console} from "forge-std/console2.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

import {
    Clock,
    ExitQueue,
    IExitQueue,
    ITicket,
    IExitQueueErrorsAndEvents,
    DynamicExitQueue,
    IDynamicExitQueue,
    IDynamicExitQueueErrorsAndEvents,
    ITicketV2,
    IExitQueueCancelErrorsAndEvents
} from "../../../versions.sol";

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

contract MockDynamicExitQueue is DynamicExitQueue {
    function getScaledTimeBasedFee(uint elapsed) external view returns (uint) {
        TicketV2 memory ticket = _globalTicket();
        return _getScaledTimeBasedFee(elapsed, ticket);
    }

    function slope() external view returns (uint) {
        return _slope;
    }
}

contract ExitQueueBase is TestHelpers, IDynamicExitQueueErrorsAndEvents, ITicketV2 {
    using ProxyLib for address;

    MockDynamicExitQueue queue;
    MockERC20 token;
    MockEscrow escrow;
    Clock clock;

    function _deployDynamicExitQueue(
        address _escrow,
        uint48 _cooldown,
        address _dao,
        uint256 _feePercent,
        address _clock,
        uint48 _minLock
    ) public returns (MockDynamicExitQueue) {
        MockDynamicExitQueue impl = new MockDynamicExitQueue();

        bytes memory initCalldata = abi.encodeCall(
            DynamicExitQueue.initialize,
            (_escrow, _cooldown, _dao, _feePercent, _clock, _minLock)
        );
        return MockDynamicExitQueue(address(impl).deployUUPSProxy(initCalldata));
    }

    function setUp() public virtual override {
        super.setUp();
        token = new MockERC20();
        escrow = new MockEscrow(address(token));

        address clockImpl = address(new Clock());
        bytes memory initClockCalldata = abi.encodeWithSelector(Clock.initialize.selector, dao);
        clock = Clock(clockImpl.deployUUPSProxy(initClockCalldata));

        queue = _deployDynamicExitQueue(address(escrow), 0, address(dao), 0, address(clock), 1);
        dao.grant({
            _who: address(this),
            _where: address(queue),
            _permissionId: queue.QUEUE_ADMIN_ROLE()
        });
    }
}
