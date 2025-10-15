// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    IExitQueueMinLock,
    IExitMinLockCooldownErrorsAndEvents,
    IExitQueueCoreErrorsAndEvents,
    IExitQueueCancelErrorsAndEvents
} from "./IExitQueue.sol";

interface ITicketV2 {
    struct TicketV2 {
        address holder;
        uint48 queuedAt;
    }

    event ExitQueuedV2(uint256 indexed tokenId, address indexed holder, uint48 queuedAt);
}

/*///////////////////////////////////////////////////////////////
                        Fee Collection
//////////////////////////////////////////////////////////////*/

interface IExitFeeWithdrawErrorsAndEvents {
    event Withdraw(address indexed to, uint256 amount);
}

interface IExitFeeWithdraw is IExitFeeWithdrawErrorsAndEvents {
    /// @notice withdraw accumulated fees
    function withdraw(uint256 _amount) external;
}

/*///////////////////////////////////////////////////////////////
                        Early Exit Queue
//////////////////////////////////////////////////////////////*/

interface IDynamicExitQueueEventsAndErrors {
    enum ExitFeeType {
        Fixed,
        Tiered,
        Dynamic
    }

    // Events
    event ExitFeePercentAdjusted(
        uint256 maxFeePercent,
        uint256 minFeePercent,
        uint48 minCooldown,
        ExitFeeType feeType
    );

    // Errors
    error EarlyExitDisabled();
    error MinCooldownNotMet();
    error InvalidFeeParameters();
    error FeePercentTooHigh(uint256 maxAllowed);
    error CooldownTooShort();
    error LegacyFunctionDeprecated();
}

interface IDynamicExitQueueFee is IDynamicExitQueueEventsAndErrors {
    /// @notice Calculate the absolute fee amount for exiting a specific token
    /// @param tokenId The token ID to calculate fee for
    /// @return Fee amount in underlying token units
    function calculateFee(uint256 tokenId) external view returns (uint256);

    /// @notice Check if a token has completed its full cooldown period (minimum fee applies)
    /// @param tokenId The token ID to check
    /// @return True if full cooldown elapsed, false otherwise
    function isCool(uint256 tokenId) external view returns (bool);

    /// @notice Configure linear fee decay system where fees decrease continuously over time
    /// @param _minFeePercent Fee percent after full cooldown (basis points, 0-10000)
    /// @param _maxFeePercent Fee percent immediately after minCooldown (basis points, 0-10000)
    /// @param _cooldown Total cooldown period in seconds
    /// @param _minCooldown Minimum wait before any exit allowed in seconds
    function setDynamicExitFeePercent(
        uint256 _minFeePercent,
        uint256 _maxFeePercent,
        uint48 _cooldown,
        uint48 _minCooldown
    ) external;

    /// @notice Configure two-tier fee system with early exit penalty and normal exit rate
    /// @param _baseFeePercent Fee percent for normal exits after cooldown (basis points, 0-10000)
    /// @param _earlyFeePercent Fee percent for early exits after minCooldown (basis points, 0-10000)
    /// @param _cooldown Total cooldown period in seconds
    /// @param _minCooldown Minimum wait before any exit allowed in seconds
    function setTieredExitFeePercent(
        uint256 _baseFeePercent,
        uint256 _earlyFeePercent,
        uint48 _cooldown,
        uint48 _minCooldown
    ) external;

    /// @notice Configure single fee rate system with optional early exit control
    /// @param _feePercent Fee percent for all exits (basis points, 0-10000)
    /// @param _minCooldown Total cooldown period in seconds - can be zero for instant exits w. fee
    function setFixedExitFeePercent(uint256 _feePercent, uint48 _minCooldown) external;

    /// @notice Minimum fee percent charged after full cooldown
    /// @return Fee percent in basis points (0-10000)
    function minFeePercent() external view returns (uint256);

    /// @notice Minimum wait time before any exit is possible
    /// @return Time in seconds
    function minCooldown() external view returns (uint48);
}

/*///////////////////////////////////////////////////////////////
                        Exit Queue
//////////////////////////////////////////////////////////////*/

interface IDynamicExitQueueErrorsAndEvents is
    IExitQueueCoreErrorsAndEvents,
    IExitMinLockCooldownErrorsAndEvents,
    IDynamicExitQueueEventsAndErrors,
    IExitQueueCancelErrorsAndEvents
{}

interface IDynamicExitQueue is
    IDynamicExitQueueErrorsAndEvents,
    ITicketV2,
    IExitQueueMinLock,
    IDynamicExitQueueFee
{
    /// @notice tokenId => TicketV2
    function queue(uint256 _tokenId) external view returns (TicketV2 memory);

    /// @notice queue an exit for a given tokenId, granting the ticket to the passed holder
    /// @param _tokenId the tokenId to queue an exit for
    /// @param _ticketHolder the address that will be granted the ticket
    function queueExit(uint256 _tokenId, address _ticketHolder) external;

    /// @notice exit the queue for a given tokenId. Requires the cooldown period to have passed
    /// @return exitAmount the amount of tokens that can be withdrawn
    function exit(uint256 _tokenId) external returns (uint256 exitAmount);

    /// @notice return true if the tokenId corresponds to a valid ticket and the cooldown period has passed
    function canExit(uint256 _tokenId) external view returns (bool);

    /// @notice return the ticket holder for a given tokenId
    function ticketHolder(uint256 _tokenId) external view returns (address);
}
