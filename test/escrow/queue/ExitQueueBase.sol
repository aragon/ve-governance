pragma solidity ^0.8.17;

import {TestHelpers} from "@helpers/TestHelpers.sol";

import {console2 as console} from "forge-std/console2.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {IExitQueue, ExitQueue} from "@escrow/ExitQueue.sol";
import {IExitQueueErrorsAndEvents} from "@escrow-interfaces/IExitQueue.sol";
import {IVotingEscrowEventsStorageErrorsEvents} from "@escrow-interfaces/IVotingEscrowIncreasing.sol";

contract ExitQueueBase is TestHelpers, IExitQueueErrorsAndEvents {
    ExitQueue queue;
    using ProxyLib for address;

    function _deployExitQueue(
        address _escrow,
        uint _cooldown,
        address _dao,
        uint256 _feePercent,
        address _clock
    ) public returns (ExitQueue) {
        ExitQueue impl = new ExitQueue();

        bytes memory initCalldata = abi.encodeCall(
            ExitQueue.initialize,
            (_escrow, _cooldown, _dao, _feePercent, _clock)
        );
        return ExitQueue(address(impl).deployUUPSProxy(initCalldata));
    }

    function setUp() public virtual override {
        super.setUp();
        queue = _deployExitQueue(address(this), 0, address(dao), 0, address(clock));
        dao.grant({
            _who: address(this),
            _where: address(queue),
            _permissionId: queue.QUEUE_ADMIN_ROLE()
        });
    }
}
