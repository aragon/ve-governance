pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";

import {console2 as console} from "forge-std/console2.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {IExitQueue, ExitQueue} from "@escrow/ExitQueue.sol";
import {IExitQueueErrorsAndEvents} from "@escrow-interfaces/IExitQueue.sol";
import {IVotingEscrowEventsStorageErrorsEvents} from "@escrow-interfaces/IVotingEscrowIncreasing.sol";

contract ExitQueueBase is Test, IExitQueueErrorsAndEvents {
    ExitQueue queue;
    DAO dao;
    using ProxyLib for address;

    function _deployExitQueue(
        address _escrow,
        uint _cooldown,
        address _dao,
        uint256 _feePercent
    ) public returns (ExitQueue) {
        ExitQueue impl = new ExitQueue();

        bytes memory initCalldata = abi.encodeCall(
            ExitQueue.initialize,
            (_escrow, _cooldown, _dao, _feePercent)
        );
        return ExitQueue(address(impl).deployUUPSProxy(initCalldata));
    }

    function setUp() public virtual {
        dao = createTestDAO(address(this));
        queue = _deployExitQueue(address(this), 0, address(dao), 0);
        dao.grant({
            _who: address(this),
            _where: address(queue),
            _permissionId: queue.QUEUE_ADMIN_ROLE()
        });
    }

    function _authErr(
        address _caller,
        address _contract,
        bytes32 _perm
    ) internal view returns (bytes memory) {
        return
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                _contract,
                _caller,
                _perm
            );
    }
}
