// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {QuadraticIncreasingEscrow} from "@curve/QuadraticIncreasingCurve.sol";
import {ILockedBalanceIncreasing} from "@escrow/IVotingEscrowIncreasing.sol";
import {IEscrowCurveTokenStorageV1_4_0, IEscrowCurveGlobalStorage} from "@curve/IEscrowCurveIncreasing_v1_4_0.sol";
import {CurveConstantLib} from "@libs/CurveConstantLib.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

library BalanceLogicLibrary {
    using SafeCast for int256;
    using SafeCast for uint256;
    using SafeCast for int128;

    uint256 internal constant WEEK = 1 weeks;

    /// @notice Binary search to get the global point index at or prior to a given timestamp
    /// @dev If a checkpoint does not exist prior to the timestamp, this will return 0.
    /// @param _latestGlobalPointIndex latest global point index.
    /// @param _globalPointHistory State of all global point history
    /// @param _timestamp .
    /// @return Global point index
    function getPastGlobalPointIndex(
        uint256 _latestGlobalPointIndex,
        mapping(uint256 => IEscrowCurveGlobalStorage.GlobalPoint) storage _globalPointHistory,
        uint256 _timestamp
    ) internal view returns (uint256) {
        if (_latestGlobalPointIndex == 0) return 0;
        // First check most recent balance
        if (_globalPointHistory[_latestGlobalPointIndex].ts <= _timestamp)
            return (_latestGlobalPointIndex);
        // Next check implicit zero balance
        if (_globalPointHistory[1].ts > _timestamp) return 0;

        uint256 lower = 0;
        uint256 upper = _latestGlobalPointIndex;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            IEscrowCurveGlobalStorage.GlobalPoint storage globalPoint = _globalPointHistory[center];
            if (globalPoint.ts == _timestamp) {
                return center;
            } else if (globalPoint.ts < _timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    /// @notice Calculate total voting power at some point in the past
    /// @param _slopeChanges State of all slopeChanges
    /// @param _globalPointHistory State of all global point history
    /// @param _globalPointLatestIndex The latest global point index to start search from.
    /// @param _t Time to calculate the total voting power at
    /// @return Total voting power at that time
    function supplyAt(
        mapping(uint256 => int256) storage _slopeChanges,
        mapping(uint256 => IEscrowCurveGlobalStorage.GlobalPoint) storage _globalPointHistory,
        uint256 _globalPointLatestIndex,
        uint256 _t
    ) external view returns (uint256) {
        uint256 epoch_ = getPastGlobalPointIndex(_globalPointLatestIndex, _globalPointHistory, _t);
        // epoch 0 is an empty point
        if (epoch_ == 0) return 0;
        IEscrowCurveGlobalStorage.GlobalPoint memory _point = _globalPointHistory[epoch_];
        int256 bias = _point.bias;
        int256 slope = _point.slope;
        uint256 ts = _point.ts; // changes in for loop.
        uint256 t_i = (ts / WEEK) * WEEK;

        for (uint256 i = 0; i < 255; ++i) {
            t_i += WEEK;
            int256 dSlope = 0;
            if (t_i > _t) {
                t_i = _t;
            } else {
                dSlope = _slopeChanges[t_i];
            }
            bias += slope * int256(t_i - ts);

            if (t_i == _t) {
                break;
            }
            slope -= dSlope;
            ts = t_i;
        }

        if (bias < 0) bias = 0;

        return uint256(bias / 1e18); // TODO: USE safe cast
    }
}
