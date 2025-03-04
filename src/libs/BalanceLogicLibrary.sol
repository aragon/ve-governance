// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {QuadraticIncreasingEscrow} from "../escrow/increasing/QuadraticIncreasingEscrow.sol";
import {ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {IEscrowCurveTokenStorage, IEscrowCurveGlobalStorage} from "src/escrow/increasing/interfaces/IEscrowCurveIncreasing.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {console2 as console} from "forge-std/console2.sol";
import {CurveConstantLib} from "@libs/CurveConstantLib.sol";

library BalanceLogicLibrary {

    using SafeCast for int256;
    using SafeCast for uint256;
    using SafeCast for int128;

    uint256 internal constant WEEK = 1 weeks;

    /// @notice Binary search to get the user point index for a token id at or prior to a given timestamp
    /// @dev If a user point does not exist prior to the timestamp, this will return 0.
    /// @param _tokenPointIndex State of all token's latest indexes
    /// @param _tokenPointHistory State of all user point history
    /// @param _tokenId .
    /// @param _timestamp .
    /// @return User point index
    function getPastUserPointIndex(
        mapping(uint256 => uint256) storage _tokenPointIndex,
        mapping(uint256 => IEscrowCurveTokenStorage.TokenPointV2[1000000000]) storage _tokenPointHistory,
        uint256 _tokenId,
        uint256 _timestamp
    ) internal view returns (uint256) {
        uint256 _userEpoch = _tokenPointIndex[_tokenId];
        if (_userEpoch == 0) return 0;
        // First check most recent balance
        if (_tokenPointHistory[_tokenId][_userEpoch].ts <= _timestamp) return (_userEpoch);
        // Next check implicit zero balance
        if (_tokenPointHistory[_tokenId][1].ts > _timestamp) return 0;

        uint256 lower = 0;
        uint256 upper = _userEpoch;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            IEscrowCurveTokenStorage.TokenPointV2 storage userPoint = _tokenPointHistory[_tokenId][center];
            if (userPoint.ts == _timestamp) {
                return center;
            } else if (userPoint.ts < _timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

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
        if (_globalPointHistory[_latestGlobalPointIndex].ts <= _timestamp) return (_latestGlobalPointIndex);
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

    /// @notice Get the current voting power for `_tokenId`
    /// @dev Adheres to the ERC20 `balanceOf` interface for Aragon compatibility
    ///      Fetches last user point prior to a certain timestamp, then walks forward to timestamp.
    /// @param _tokenPointIndex State of all token's latest indexes
    /// @param _tokenPointHistory State of all user point history
    /// @param _tokenId NFT for lock
    /// @param _locked The current locked balance of the tokenId.
    /// @param _t Epoch time to return voting power at
    /// @return User voting power
    function balanceOfNFTAt(
        mapping(uint256 => uint256) storage _tokenPointIndex,
        mapping(uint256 => IEscrowCurveTokenStorage.TokenPointV2[1000000000]) storage _tokenPointHistory,
        uint256 _tokenId,
        ILockedBalanceIncreasing.LockedBalance storage _locked,
        uint256 _t
    ) external view returns (uint256) {
        uint256 _epoch = getPastUserPointIndex(_tokenPointIndex, _tokenPointHistory, _tokenId, _t);
        // epoch 0 is an empty point
        if (_epoch == 0) return 0;
        IEscrowCurveTokenStorage.TokenPointV2 memory lastPoint = _tokenPointHistory[_tokenId][_epoch];
        
        uint48 end = uint48(_locked.start + CurveConstantLib.MAX_TIME);
        uint48 duration;
        
        if(lastPoint.ts <= end && uint48(_t) >= end) {
            duration = end - lastPoint.ts;
        } else {
            duration = uint48(_t) - lastPoint.ts;
        }

        lastPoint.bias += lastPoint.slope * duration;

        return lastPoint.bias;
    }

    /// @notice Calculate total voting power at some point in the past
    /// @param _slopeChanges State of all slopeChanges
    /// @param _globalPointHistory State of all global point history
    /// @param _globalPointLatestIndex The latest global point index to start search from.
    /// @param _t Time to calculate the total voting power at
    /// @return Total voting power at that time
    function supplyAt(
        mapping(uint256 => uint256) storage _slopeChanges,
        mapping(uint256 => IEscrowCurveGlobalStorage.GlobalPoint) storage _globalPointHistory,
        uint256 _globalPointLatestIndex,
        uint256 _t
    ) external view returns (uint256) {
        uint256 epoch_ = getPastGlobalPointIndex(_globalPointLatestIndex, _globalPointHistory, _t);
        // epoch 0 is an empty point
        if (epoch_ == 0) return 0;
        IEscrowCurveGlobalStorage.GlobalPoint memory _point = _globalPointHistory[epoch_];
        uint256 bias = _point.bias;
        uint256 slope = _point.slope;
        uint256 ts = _point.ts; // changes in for loop.
        uint256 t_i = (ts / WEEK) * WEEK;
        
        for (uint256 i = 0; i < 255; ++i) {
            t_i += WEEK;
            uint256 dSlope = 0;
            if (t_i > _t) {
                t_i = _t;
            } else {
                dSlope = _slopeChanges[t_i];
            }
            bias += slope * (t_i - ts);

            if (t_i == _t) {
                break;
            }
            slope -= dSlope;
            ts = t_i;
        }

        return uint256(bias / 1e18); // TODO: USE safe cast
    }
}