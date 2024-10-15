/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title CurveConstantLib
/// @notice Precomputed coefficients for escrow curve
library CurveConstantLib {
    /// @dev Inital multiplier for the deposit.
    int256 internal constant SHARED_CONSTANT_COEFFICIENT = 1e18;

    /// @dev For linear curves that need onchain total supply, the linear coefficient is sufficient to show
    /// the slope of the curve.
    int256 internal constant SHARED_LINEAR_COEFFICIENT = 236205593348;

    /// @dev Quadratic curves can be defined in the case where supply can be fetched offchain.
    int256 internal constant SHARED_QUADRATIC_COEFFICIENT = 0;

    /// @dev the maxiumum number of epochs the cure can keep increasing. See the Clock for the epoch duration.
    uint256 internal constant MAX_EPOCHS = 5;
}
