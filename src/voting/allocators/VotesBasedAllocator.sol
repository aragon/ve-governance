// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IIncentiveAllocator.sol";

/// @title Incentive Allocator Contract
/// @notice Implements the logic for calculating incentive allocations for gauges.
/// @dev Uses a fixed allocation for simplicity but can be extended for dynamic calculations.
contract VotesBasedAllocator is IIncentiveAllocator {
    /// @notice Constructor to set the initial base incentive.
    constructor(uint256 _baseIncentive) {}

    /// @notice Calculates the incentive allocation for a given gauge.
    /// @dev If a custom incentive is set, it takes precedence over the base incentive.
    /// @param gauge The address of the gauge to calculate incentives for.
    /// @return amount The calculated incentive amount.
    function calculateIncentive(address gauge) external view override returns (uint256 amount) {}
}
