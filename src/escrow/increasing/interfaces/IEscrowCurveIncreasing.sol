// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import {ILockedBalanceIncreasing} from "./IVotingEscrowIncreasing.sol";

/*///////////////////////////////////////////////////////////////
                        Global Curve
//////////////////////////////////////////////////////////////*/

interface IEscrowCurveGlobalStorage {
    /// @notice Captures the shape of the aggregate voting curve at a specific point in time
    /// @param bias The y intercept of the aggregate voting curve at the given time
    /// @param ts The timestamp at which the we last updated the aggregate voting curve
    /// @param blk The block at which the we last updated the aggregate voting curve
    /// @param coefficients The coefficients of the aggregated curve, supports up to cubic curves.
    /// @dev Coefficients are stored in the following order: [constant, linear, quadratic, cubic]
    /// and not all coefficients are used for all curves.
    struct GlobalPoint {
        uint128 bias;
        uint256 ts;
        uint256 blk;
        int256[4] coefficients;
    }
}

interface IEscrowCurveGlobal is IEscrowCurveGlobalStorage {
    /// @notice Returns the GlobalPoint at the passed epoch
    /// @param _loc The epoch to return the GlobalPoint at
    function pointHistory(uint256 _loc) external view returns (GlobalPoint memory);
}

/*///////////////////////////////////////////////////////////////
                        User Curve
//////////////////////////////////////////////////////////////*/

interface IEscrowCurveUserStorage {
    /// @notice Captures the shape of the user's voting curve at a specific point in time
    /// @param bias The y intercept of the user's voting curve at the given time
    /// @param ts The timestamp at which the user's voting curve was captured
    /// @param blk The block at which the user's voting curve was captured
    /// @param coefficients The coefficients of the curve, supports up to cubic curves.
    /// @dev Coefficients are stored in the following order: [constant, linear, quadratic, cubic]
    /// and not all coefficients are used for all curves.
    struct UserPoint {
        uint256 bias;
        uint256 ts;
        uint256 blk;
        int256[4] coefficients;
    }
}

interface IEscrowCurveUser is IEscrowCurveUserStorage {
    /// @notice returns the user point at time `timestamp`
    function userPointEpoch(uint256 timestamp) external view returns (uint256);

    /// @notice Returns the UserPoint at the passed epoch
    /// @param _tokenId The NFT to return the UserPoint for
    /// @param _loc The epoch to return the UserPoint at
    function userPointHistory(uint256 _tokenId, uint256 _loc) external view returns (UserPoint memory);
}

/*///////////////////////////////////////////////////////////////
                        Core Functions
//////////////////////////////////////////////////////////////*/

interface IEscrowCurveCore {
    /// @notice Get the current voting power for `_tokenId`
    /// @dev Adheres to the ERC20 `balanceOf` interface for Aragon compatibility
    ///      Fetches last user point prior to a certain timestamp, then walks forward to timestamp.
    /// @param _tokenId NFT for lock
    /// @param _t Epoch time to return voting power at
    /// @return User voting power
    function votingPowerAt(uint256 _tokenId, uint256 _t) external view returns (uint256);

    /// @notice Calculate total voting power at some point in the past
    /// @param _t Time to calculate the total voting power at
    /// @return Total voting power at that time
    function supplyAt(uint256 _t) external view returns (uint256);

    /// @notice Writes a snapshot of voting power at the current epoch
    /// @param _tokenId Snapshot a specific token
    /// @param _oldLocked The user's previous locked balance
    /// @param _newLocked The user's new locked balance
    function checkpoint(
        uint256 _tokenId,
        ILockedBalanceIncreasing.LockedBalance memory _oldLocked,
        ILockedBalanceIncreasing.LockedBalance memory _newLocked
    ) external;
}

interface IEscrowCurveMath {
    /// @notice Preview the curve coefficients for curves up to cubic.
    /// @param amount The amount of tokens to calculate the coefficients for - given a fixed algebraic representation
    /// @return coefficients in the form [constant, linear, quadratic, cubic]
    /// @dev Not all coefficients are used for all curves
    function getCoefficients(uint256 amount) external view returns (int256[4] memory coefficients);

    /// @notice Bias is the user's voting weight
    function getBias(uint256 timeElapsed, uint256 amount) external view returns (uint256 bias);
}

/*///////////////////////////////////////////////////////////////
                        WARMUP CURVE
//////////////////////////////////////////////////////////////*/

interface IWarmup {
    /// @notice the warmup period for the curve
    function warmupPeriod() external view returns (uint256);

    /// @notice check if the curve is past the warming period
    function isWarm(uint256 _tokenId) external view returns (bool);
}

/*///////////////////////////////////////////////////////////////
                        INCREASING CURVE
//////////////////////////////////////////////////////////////*/

/// @dev first version only accounts for user-level point histories
interface IEscrowCurveIncreasing is IEscrowCurveCore, IEscrowCurveMath, IEscrowCurveUser, IWarmup {

}