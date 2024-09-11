pragma solidity ^0.8.0;

/// @title CurveCoefficientLib
/// @notice Precomputed coefficients for escrow curve
/// This curve implementation is a quadratic curve of the form y = (1/7)t^2 + (2/7)t + 1
/// Which is a transformation of the quadratic curve y = (x^2 + 6)/7
/// That starts with 1 unit of voting in period 1, and max 6 in period 6.
/// To use this in zero indexed time, with a per-second rate of increase,
/// we transform this to the polynomial y = (1/7)t^2 + (2/7)t + 1
/// where t = timestamp / 2_weeks (2 weeks is one period)
/// Below are the shared coefficients for the linear and quadratic terms
library CurveCoefficientLib {
    /// 2 / (7 * 2_weeks) - expressed in fixed point
    int256 internal constant SHARED_LINEAR_COEFFICIENT = 236205593348;

    /// 1 / (7 * (2_weeks)^2) - expressed in fixed point
    int256 internal constant SHARED_QUADRATIC_COEFFICIENT = 97637;
}
