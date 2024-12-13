/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title CurveConstantLib
/// @notice Precomputed coefficients for escrow curve
/// That starts with 1 unit of voting in period 1, and max 6 in period 6, increasing linearly
library CurveConstantLib {
    int256 internal constant SHARED_CONSTANT_COEFFICIENT = 1e18;
    /// @dev rate of increase per second expressed in fixed point
    int256 internal constant SHARED_LINEAR_COEFFICIENT = 826719576719;

    /// @dev linear curve with zero quadratic term
    int256 internal constant SHARED_QUADRATIC_COEFFICIENT = 0;

    /// @dev the maxiumum number of epochs the cure can keep increasing
    uint256 internal constant MAX_EPOCHS = 5;
}
