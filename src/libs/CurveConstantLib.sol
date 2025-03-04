/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title CurveConstantLib
/// @notice Precomputed coefficients for escrow curve
library CurveConstantLib {
    /// @dev voting power starts at 1x
    int256 internal constant SHARED_CONSTANT_COEFFICIENT = 1e18;
    /// @dev increase of 1x -> 4x over 3 years
    int256 internal constant SHARED_LINEAR_COEFFICIENT = 31796906796;
    /// @dev linear curve therefore quadratic coefficient is 0
    int256 internal constant SHARED_QUADRATIC_COEFFICIENT = 0;

    /// @dev the maxiumum number of epochs the cure can keep increasing
    /// 3 years worth of epochs of 2 weeks is (52*3)/2 = 78
    uint256 internal constant MAX_EPOCHS = 78;
}
