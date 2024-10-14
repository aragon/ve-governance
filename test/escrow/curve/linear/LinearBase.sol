// SPDX-License-Identifier: UNLICENSE
pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";
import {TestHelpers} from "@helpers/TestHelpers.sol";
import {console2 as console} from "forge-std/console2.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";

import {LinearIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/LinearIncreasingEscrow.sol";
import {IEscrowCurveEventsErrorsStorage} from "src/escrow/increasing/interfaces/IEscrowCurveIncreasing.sol";
import {Clock} from "@clock/Clock.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

contract MockEscrow {
    address public token;
    LinearIncreasingEscrow public curve;

    function setCurve(LinearIncreasingEscrow _curve) external {
        curve = _curve;
    }

    function checkpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) external {
        return curve.checkpoint(_tokenId, _oldLocked, _newLocked);
    }
}

/// @dev expose internal functions for testing
contract MockLinearIncreasingEscrow is LinearIncreasingEscrow {
    function tokenCheckpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) public returns (TokenPoint memory, TokenPoint memory) {
        return _tokenCheckpoint(_tokenId, _oldLocked, _newLocked);
    }

    function scheduleCurveChanges(
        TokenPoint memory _oldPoint,
        TokenPoint memory _newPoint,
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) external {
        _scheduleCurveChanges(_oldPoint, _newPoint, _oldLocked, _newLocked);
    }

    function writeSchedule(uint48 _at, int256[3] memory _change) external {
        _scheduledCurveChanges[_at] = _change;
    }

    function populateHistory() external returns (GlobalPoint memory, uint) {
        return _populateHistory();
    }

    function writeNewGlobalPoint(GlobalPoint memory _latestPoint, uint256 _index) external {
        _writeNewGlobalPoint(_latestPoint, _index);
    }
}

contract LinearCurveBase is TestHelpers, ILockedBalanceIncreasing, IEscrowCurveEventsErrorsStorage {
    using ProxyLib for address;
    MockLinearIncreasingEscrow internal curve;
    MockEscrow internal escrow;

    function setUp() public virtual override {
        super.setUp();
        escrow = new MockEscrow();

        address impl = address(new MockLinearIncreasingEscrow());

        bytes memory initCalldata = abi.encodeCall(
            LinearIncreasingEscrow.initialize,
            (address(escrow), address(dao), 3 days, address(clock))
        );

        curve = MockLinearIncreasingEscrow(impl.deployUUPSProxy(initCalldata));

        // grant this address admin privileges
        DAO(payable(address(dao))).grant({
            _who: address(this),
            _where: address(curve),
            _permissionId: curve.CURVE_ADMIN_ROLE()
        });

        escrow.setCurve(curve);
    }
}
