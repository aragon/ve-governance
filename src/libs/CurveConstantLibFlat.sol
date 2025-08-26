/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// The initial bias is scaled by a multiplier, which defaults to 1x (no scaling).
// To start with a higher initial bias (e.g., 1.5x the amount), update this value accordingly.
// For example, set it to 1.5 in case you want to start with 1.5 * amount.
int256 constant INITIAL_BIAS_MULTIPLIER = 1;

/// @title CurveConstantLibFlat
/// @notice Precomputed coefficients for escrow curve in the case of flat (no change after base multiplier)
/// @dev Flat Curve
/// Epochs are still 2 weeks long
library CurveConstantLibFlat {
    int256 internal constant SHARED_CONSTANT_COEFFICIENT = INITIAL_BIAS_MULTIPLIER * 1e18;

    /// @dev this curve is flat
    int256 internal constant SHARED_LINEAR_COEFFICIENT = 0;

    /// @dev this curve is flat
    int256 internal constant SHARED_QUADRATIC_COEFFICIENT = 0;

    /// @dev the maxiumum number of epochs the cure can keep increasing
    /// 26 epochs in a year, 2 years = 52 epochs
    uint256 internal constant MAX_EPOCHS = 52;

    function getCoefficients() internal view returns (int256[3] memory, uint256) {
        int256[3] memory coefficients;
        coefficients[0] = SHARED_CONSTANT_COEFFICIENT;
        coefficients[1] = SHARED_LINEAR_COEFFICIENT;
        coefficients[2] = SHARED_QUADRATIC_COEFFICIENT;
        uint256 maxEpoch = MAX_EPOCHS;

        return (coefficients, maxEpoch);
    }
}
