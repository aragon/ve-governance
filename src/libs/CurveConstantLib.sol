/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


/// @title CurveConstantLib
/// @notice Precomputed coefficients for escrow curve
/// This curve implementation is a quadratic curve of the form y = (1/7)t^2 + (2/7)t + 1
/// Which is a transformation of the quadratic curve y = (x^2 + 6)/7
/// That starts with 1 unit of voting in period 1, and max 6 in period 6.
/// To use this in zero indexed time, with a per-second rate of increase,
/// we transform this to the polynomial y = (1/7)t^2 + (2/7)t + 1
/// where t = timestamp / 2_weeks (2 weeks is one period)
/// Below are the shared coefficients for the linear and quadratic terms
library CurveConstantLib {
    /// @notice Helps to define how the curve should be changing.
    int256 internal constant SHARED_CONSTANT_COEFFICIENT = 1e18;

    /// 1 / (52 * SECONDS_IN_2_WEEKS)
    int256 internal constant SHARED_LINEAR_COEFFICIENT = 15898453398;
    
    int256 internal constant SHARED_QUADRATIC_COEFFICIENT = 0;

    /// @dev the maxiumum number of epochs the cure can keep increasing
    uint256 internal constant MAX_EPOCHS = 52;    
}
