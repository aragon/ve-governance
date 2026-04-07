/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// The initial bias is scaled by a multiplier, which defaults to 1x (no scaling).
// To start with a higher initial bias (e.g., 1.5x the amount), update this value accordingly.
// For example, set it to 1.5 in case you want to start with 1.5 * amount.
int256 constant INITIAL_BIAS_MULTIPLIER = 2;

/// @title CurveConstantLib
/// @notice Precomputed coefficients for escrow curve
/// Below are the shared coefficients for the linear and quadratic terms
/// @dev This curve goes from 1x -> 2x voting power over a 2 year time horizon
/// Epochs are still 2 weeks long
library CurveConstantLib {
    int256 internal constant SHARED_CONSTANT_COEFFICIENT = INITIAL_BIAS_MULTIPLIER * 1e18;

    /// @dev straight line so the curve is increasing only in the linear term
    /// 1 / (52 * SECONDS_IN_2_WEEKS)
    int256 internal constant SHARED_LINEAR_COEFFICIENT = 1e18 / (int256(MAX_EPOCHS) * 2 weeks);

    /// @dev this curve is linear
    int256 internal constant SHARED_QUADRATIC_COEFFICIENT = 0;

    /// @dev the maxiumum number of epochs the cure can keep increasing
    /// 26 epochs in a year
    uint256 internal constant MAX_EPOCHS = 26;

    function getCoefficients() internal pure returns (int256[3] memory, uint256) {
        int256[3] memory coefficients;
        coefficients[0] = SHARED_CONSTANT_COEFFICIENT;
        coefficients[1] = SHARED_LINEAR_COEFFICIENT;
        coefficients[2] = SHARED_QUADRATIC_COEFFICIENT;
        uint256 maxEpoch = MAX_EPOCHS;

        return (coefficients, maxEpoch);
    }
}
