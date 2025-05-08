/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title CurveConstantLib
/// @notice Precomputed coefficients for escrow curve
/// @dev The coefficients are precomputed for the curve: they represent a linear increase of 3x over 6 weeks
library CurveConstantLib {
    int256 internal constant SHARED_CONSTANT_COEFFICIENT = 1e18;
    /// @dev 2 / (7 * 2_weeks) - expressed in fixed point
    int256 internal constant SHARED_LINEAR_COEFFICIENT = 551146384479;
    /// @dev 1 / (7 * (2_weeks)^2) - expressed in fixed point
    int256 internal constant SHARED_QUADRATIC_COEFFICIENT = 0;

    /// @dev the maxiumum number of epochs the cure can keep increasing
    uint256 internal constant MAX_EPOCHS = 3; // 3 epochs of 2 weeks each
}
