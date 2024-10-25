// SPDX-License-Identifier: UNLICENSE
pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";
import {TestHelpers} from "@helpers/TestHelpers.sol";
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

    mapping(uint256 => IVotingEscrow.LockedBalance) internal _locked;

    function setLockedBalance(uint256 _tokenId, IVotingEscrow.LockedBalance memory lock) external {
        _locked[_tokenId] = lock;
    }

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

    function locked(uint256 _tokenId) external view returns (IVotingEscrow.LockedBalance memory) {
        return _locked[_tokenId];
    }
}

/// @dev expose internal functions for testing
contract MockLinearIncreasingEscrow is LinearIncreasingEscrow {
    function tokenCheckpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _newLocked
    ) public returns (TokenPoint memory, TokenPoint memory) {
        return _tokenCheckpoint(_tokenId, _newLocked);
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
        _latestPointIndex = _index;
        _pointHistory[_index] = _latestPoint;
    }

    function writeNewTokenPoint(
        uint256 _tokenId,
        TokenPoint memory _point,
        uint _interval
    ) external {
        tokenPointIntervals[_tokenId] = _interval;
        _tokenPointHistory[_tokenId][_interval] = _point;
    }

    function getLatestGlobalPointOrWriteFirstPoint() external returns (GlobalPoint memory, uint) {
        return _getLatestGlobalPointOrWriteFirstPoint();
    }

    function earliestScheduledChange() external view returns (uint48) {
        return _earliestScheduledChange;
    }

    function writeEarliestScheduleChange(uint48 _at) external {
        _earliestScheduledChange = _at;
    }

    function previewPoint(uint amount) external view returns (TokenPoint memory point) {
        point.coefficients = _getCoefficients(amount);
        point.bias = _getBias(0, point.coefficients);
    }

    function applyTokenUpdateToGlobal(
        uint48 lockStart,
        TokenPoint memory _oldPoint,
        TokenPoint memory _newPoint,
        GlobalPoint memory _latestGlobalPoint
    ) external view returns (GlobalPoint memory) {
        return _applyTokenUpdateToGlobal(lockStart, _oldPoint, _newPoint, _latestGlobalPoint);
    }

    function getBiasUnbound(
        uint elapsed,
        int[3] memory coefficients
    ) external pure returns (int256) {
        return _getBiasUnbound(elapsed, coefficients);
    }

    function getBiasUnbound(uint elapsed, uint amount) external pure returns (int256) {
        return _getBiasUnbound(elapsed, _getCoefficients(amount));
    }

    function unsafeCheckpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) external {
        return _checkpoint(_tokenId, _oldLocked, _newLocked);
    }

    function unsafeManualCheckpoint() external {
        return _checkpoint();
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
