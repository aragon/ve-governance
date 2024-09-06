pragma solidity ^0.8.0;

/// @title ModeCurveCoefficientLib
/// @notice Precomputed coefficients for the mode curve
/// Which is a transformation of the quadratic curve y = (x^2 + 6)/7
/// That starts with 1 unit of voting in period 1, and max 6 in period 6.
/// To use this in zero indexed time, with a per-second rate of increase,
/// we transform this to the polynomial y = (1/7)t^2 + (2/7)t + 1
/// where t = timestamp / 2_weeks (2 weeks is one period)
/// Below are the shared coefficients for the linear and quadratic terms
library ModeCurveCoefficientLib {
    int256 internal constant SD1 = 1e18;
    int256 internal constant SD2 = 2e18;
    int256 internal constant SD7 = 7e18;

    /// 2 / (7 * 2_weeks) - expressed in fixed point
    int256 internal constant SHARED_LINEAR_COEFFICIENT = 1e18;

    /// 1 / (7 * (2_weeks)^2) - expressed in fixed point
    int256 internal constant SHARED_QUADRATIC_COEFFICIENT = 1e18;
}
