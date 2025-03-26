/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title CurveConstantLib
/// @notice Precomputed coefficients for escrow curve
/// Below are the shared coefficients for the linear and quadratic terms
/// @dev This curve goes from 1x -> 8x voting power over a 12 week (~3m) period
/// Epochs are 2 weeks long
library CurveConstantLib {
    int256 internal constant SHARED_CONSTANT_COEFFICIENT = 1e18;

    /// @dev straight line so the curve is increasing only in the linear term
    /// 7e18 / 12 weeks;
    /// Rearrangement of 8 = x * 12_weeks + 1
    int256 internal constant SHARED_LINEAR_COEFFICIENT = 7e18 / (int256(MAX_EPOCHS) * 2 weeks);

    /// @dev this curve is linear
    int256 internal constant SHARED_QUADRATIC_COEFFICIENT = 0;

    /// @dev the maxiumum number of epochs the cure can keep increasing
    // 12 weeks / 2 weeks per epoch = 6 epochs
    uint256 internal constant MAX_EPOCHS = 6;
}
