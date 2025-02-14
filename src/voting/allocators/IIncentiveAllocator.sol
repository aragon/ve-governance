// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice This interface defines the contract responsible for calculating incentive allocations.
/// @dev Implementations of this interface should provide logic for determining how much should be sent to each gauge.
interface IIncentiveAllocator {
    /// @notice Calculates the incentive allocation for a given gauge.
    /// @dev Implementing contracts should use relevant logic (e.g., gauge weight, emissions rate).
    /// @param gauge The address of the gauge to calculate incentives for.
    /// @return amount The amount of incentives to be allocated.
    function calculateIncentive(address gauge, address _token) external returns (uint256 amount);
}
