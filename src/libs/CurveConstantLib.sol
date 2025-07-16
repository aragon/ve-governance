/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// The initial bias is scaled by a multiplier, which defaults to 1x (no scaling).
// To start with a higher initial bias (e.g., 1.5x the amount), update this value accordingly.
// For example, set it to 1.5 in case you want to start with 1.5 * amount.
int256 constant INITIAL_BIAS_MULTIPLIER = 1;

/// @title CurveConstantLib
/// @notice Precomputed coefficients for escrow curve
/// Below are the shared coefficients for the linear and quadratic terms
/// @dev This curve goes from 1x -> 6x voting power over a 6 month time horizon
/// Epochs are still 2 weeks long
library CurveConstantLib {
    int256 internal constant SHARED_CONSTANT_COEFFICIENT = INITIAL_BIAS_MULTIPLIER * 1e18;

    /// @dev straight line so the curve is increasing only in the linear term
    /// 5 / (18 * SECONDS_IN_2_WEEKS) to go from 1x to 6x over 18 epochs
    int256 internal constant SHARED_LINEAR_COEFFICIENT = 5e18 / (int256(MAX_EPOCHS) * 2 weeks);

    /// @dev this curve is linear
    int256 internal constant SHARED_QUADRATIC_COEFFICIENT = 0;

    /// @dev the maxiumum number of epochs the cure can keep increasing
    /// 2 weeks per epoch, 6 months = 26 weeks = 13 epochs
    uint256 internal constant MAX_EPOCHS = 13;
}
