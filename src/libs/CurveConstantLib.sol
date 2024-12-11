/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title CurveConstantLib
/// @notice Precomputed coefficients for escrow curve
/// This curve implementation is a linear curve of the form y = t + 1
/// That starts with 1 unit of voting in epoch 1 (t=0),
/// and max 6 at the end of epoch 5 (t=5).
/// To use this in zero indexed time, with a per-second rate of increase,
/// where t = timestamp / 2_weeks (2 weeks is one epoch)
/// Below are the shared coefficients for the linear and quadratic terms
library CurveConstantLib {
    int256 internal constant SHARED_CONSTANT_COEFFICIENT = 1e18;
    /// @dev 1e18 / (3600 * 24 * 14) - expressed in fixed point
    int256 internal constant SHARED_LINEAR_COEFFICIENT = 826719576719;
    /// @dev Zero, since the curve is linear
    int256 internal constant SHARED_QUADRATIC_COEFFICIENT = 0;

    /// @dev the maxiumum number of epochs the curve can keep increasing
    uint256 internal constant MAX_EPOCHS = 5;
}
