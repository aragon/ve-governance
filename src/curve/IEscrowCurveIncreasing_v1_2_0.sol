/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IEscrowCurveIncreasing.sol";
import "../IDeprecated.sol";

/*///////////////////////////////////////////////////////////////
                        Global Curve
//////////////////////////////////////////////////////////////*/

interface IEscrowCurveGlobalStorage {
    /// @notice Captures the shape of the aggregate voting curve at a specific point in time
    /// TODO: change the natspec
    /// @param bias The y intercept of the aggregate voting curve at the given time
    /// @param writtenTs The timestamp at which the we last updated the aggregate voting curve
    /// @param coefficients The coefficients of the aggregated curve, supports up to quadratic curves.
    /// @dev Coefficients are stored in the following order: [constant, linear, quadratic]
    /// and not all coefficients are used for all curves.
    struct GlobalPoint {
        int256 bias;
        int256 slope;
        uint48 writtenTs;
    }
}

interface IEscrowCurveGlobal is IEscrowCurveGlobalStorage {
    /// @notice Returns the global point at the passed epoch
    /// @param _index The index in an array to return the point for
    function globalPointHistory(uint256 _index) external view returns (GlobalPoint memory);
}

/*///////////////////////////////////////////////////////////////
                        Token Curve
//////////////////////////////////////////////////////////////*/

interface IEscrowCurveTokenV1_2_0 is IEscrowCurveTokenStorage {
    /// @notice Returns the latest index of the tokenId which can be used
    ///         to retrive token point from `tokenPointHistory` function.
    /// @dev This has been renamed to `tokenPointLatestIndex` in the latest upgrade, but
    ///      for backwards-compatibility, the function still stays in the contract.
    ///      Note that we treat it as deprecated, So use `tokenPointLatestIndex` instead.
    /// @return The latest index of the token id.
    function tokenPointIntervals(uint256 _tokenId) external view returns (uint256);

    /// @notice Returns the latest index of the tokenId which can be used
    ///         to retrive token point from `tokenPointHistory` function.
    /// @param _tokenId The NFT to return the latest token point index
    /// @return The latest index of the token id.
    function tokenPointLatestIndex(uint256 _tokenId) external view returns (uint256);

    /// @notice Returns the TokenPoint at the passed `_index`.
    /// @param _tokenId The NFT to return the TokenPoint for
    /// @param _index The index to return the TokenPoint at.
    function tokenPointHistory(
        uint256 _tokenId,
        uint256 _index
    ) external view returns (TokenPoint memory);
}

interface IEscrowCurveMaxTime is IEscrowCurveErrorsAndEvents {
    /// @return The max time allowed for the lock duration.
    function maxTime() external view returns (uint256);
}

/*///////////////////////////////////////////////////////////////
                        INCREASING CURVE
//////////////////////////////////////////////////////////////*/

interface IEscrowCurveIncreasingV1_2_0 is
    IEscrowCurveCore,
    IEscrowCurveMath,
    IEscrowCurveTokenV1_2_0,
    IEscrowCurveMaxTime,
    IEscrowCurveGlobal,
    IDeprecated
{}

interface IEscrowCurveIncreasingV1_2_0_NoSupply is
    IEscrowCurveCore,
    IEscrowCurveMath,
    IEscrowCurveTokenV1_2_0,
    IEscrowCurveMaxTime,
    IDeprecated
{}
