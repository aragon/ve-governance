// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IIncentiveAllocator.sol";

import {IClockUser, IClock} from "@clock/IClock.sol";
import {GaugeDistributorVoter} from "../GaugeDistributorVoter.sol";

import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable as Pausable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";

/// @title Incentive Allocator Contract
/// @notice Implements the logic for calculating incentive allocations for gauges.
/// @dev Uses a fixed allocation for simplicity but can be extended for dynamic calculations.
contract VotesBasedAllocator is GaugeDistributorVoter, IIncentiveAllocator {
    uint256 private constant BPS = 10_000;

    /// @notice Constructor to set the initial base incentive.
    constructor() {
        _disableInitializers();
    }

    /// @notice Calculates the incentive allocation for a given gauge.
    /// @dev If a custom incentive is set, it takes precedence over the base incentive.
    /// @param _gauge The address of the gauge to calculate incentives for.
    /// @param _token The address of the token to calculate incentives for.
    /// @return gaugeAmount The calculated incentive amount.
    function calculateIncentive(
        address _gauge,
        address _token
    ) external returns (uint256 gaugeAmount) {
        // TODO: Implement some checks on who's calling the function
        // TODO: Check if we are in the distribution perdiod

        uint256 epoch = epochId();

        // 1. If epoch voting % haven been calculated
        TokenAndAmount[] storage epochAmounts = epochAmountsToBeDistributed[epoch][_token];
        if (epochAmounts.length == 0 || epochAmounts[0].gauge == address(0)) {
            uint256 totalVotingPowerWithFee = (totalVotingPowerCast * (BPS + feePercentage)) / BPS;
            // 1.2 Calculate the different percentages of the whole gauge
            // 1.3 Store the percentages for the epoch
            for (uint256 i = 0; i < gaugeList.length; i++) {
                // Get the votes of the current gauge
                uint256 votes = gaugeVotes[gaugeList[i]];
                uint256 percentage = (votes * BPS) / totalVotingPowerWithFee;

                TokenAndAmount memory localGaugeTokenAndAmount = TokenAndAmount(
                    gaugeList[i],
                    (percentage * tokenIncentives[_token].epochPayout) / BPS
                );
                epochAmounts.push(localGaugeTokenAndAmount);

                if (gaugeList[i] == _gauge) {
                    gaugeAmount = (percentage * tokenIncentives[_token].epochPayout) / BPS;
                }
            }
        }

        // Iterate through epochAmounts until the gauge is found then return it
        for (uint256 i = 0; i < epochAmounts.length; i++) {
            if (epochAmounts[i].gauge == _gauge) {
                return epochAmounts[i].amountToBeDistributed;
            }
        }
    }

    /// Rest of UUPS logic is handled by OSx plugin
    uint256[43] private __gap;

    /// Variales for this specific file should be added here at the end
}
