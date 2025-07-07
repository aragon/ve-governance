// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IExitQueueCoreErrorsAndEvents {
    error OnlyEscrow();
    error AlreadyQueued();
    error ZeroAddress();
    error CannotExit();
    error NoLockBalance();
    event ExitQueued(uint256 indexed tokenId, address indexed holder, uint256 exitDate);
    event Exit(uint256 indexed tokenId, uint256 fee);
}

interface ITicketV2 {
    struct TicketV2 {
        address holder;
        uint48 queuedAt;
        uint48 originalExitDate;
    }
}

/*///////////////////////////////////////////////////////////////
                        Fee Collection
//////////////////////////////////////////////////////////////*/

interface IExitQueueFeeErrorsAndEvents {
    error FeeTooHigh(uint256 maxFee);

    event Withdraw(address indexed to, uint256 amount);
    event FeePercentSet(uint256 feePercent);
}

interface IExitQueueFee is IExitQueueFeeErrorsAndEvents {
    /// @notice optional fee charged for exiting the queue
    function feePercent() external view returns (uint256);

    /// @notice The exit queue manager can set the fee
    function setFeePercent(uint256 _fee) external;

    /// @notice withdraw accumulated fees
    function withdraw(uint256 _amount) external;
}

/*///////////////////////////////////////////////////////////////
                        Cooldown
//////////////////////////////////////////////////////////////*/

interface IExitQueueCooldownErrorsAndEvents {
    error CooldownTooHigh();

    event CooldownSet(uint48 cooldown);
}

interface IExitQueueCooldown is IExitQueueCooldownErrorsAndEvents {
    /// @notice time in seconds between exit and withdrawal
    function cooldown() external view returns (uint48);

    /// @notice The exit queue manager can set the cooldown period
    /// @param _cooldown time in seconds between exit and withdrawal
    function setCooldown(uint48 _cooldown) external;
}

/*///////////////////////////////////////////////////////////////
                        Min Lock
//////////////////////////////////////////////////////////////*/

interface IExitMinLockCooldownErrorsAndEvents {
    event MinLockSet(uint48 minLock);
    error MinLockOutOfBounds();
    error MinLockNotReached(uint256 tokenId, uint48 minLock, uint48 earliestExitDate);
}

interface IExitQueueMinLock is IExitMinLockCooldownErrorsAndEvents {
    /// @notice minimum time from the original lock date before one can enter the queue
    function minLock() external view returns (uint48);

    /// @notice The exit queue manager can set the minimum lock time
    function setMinLock(uint48 _cooldown) external;
}

/*///////////////////////////////////////////////////////////////
                        Early Exit Queue
//////////////////////////////////////////////////////////////*/

interface IEarlyExitQueueEventsAndErrors {
    // Events
    event ExitFeePercentAdjusted(
        uint256 maxFeePercent,
        uint256 minFeePercent,
        uint256 slope,
        uint48 minCooldown
    );

    // Errors
    error EarlyExitDisabled();
    error MinCooldownNotMet();
    error InvalidFeeParameters();
    error FeePercentTooHigh(uint256 maxAllowed);
    error CooldownTooShort();
    error LegacyFunctionDeprecated();
}

interface IEarlyExitQueue is IEarlyExitQueueEventsAndErrors {
    /// @notice Calculate the absolute fee amount for exiting a specific token
    /// @param tokenId The token ID to calculate fee for
    /// @return Fee amount in underlying token units
    function getFee(uint256 tokenId) external view returns (uint256);

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
    /// @param _cooldown Total cooldown period in seconds
    /// @param _allowEarlyExit If true, allow exits after minCooldown=0; if false, require full cooldown
    function setFixedExitFeePercent(
        uint256 _feePercent,
        uint48 _cooldown,
        bool _allowEarlyExit
    ) external;

    /// @notice Maximum fee percent charged during early exit period
    /// @return Fee percent in basis points (0-10000)
    function maxFeePercent() external view returns (uint256);

    /// @notice Minimum fee percent charged after full cooldown
    /// @return Fee percent in basis points (0-10000)
    function minFeePercent() external view returns (uint256);

    /// @notice Rate of fee decrease per second during decay period
    /// @return Slope in basis points per second
    function slope() external view returns (uint256);

    /// @notice Minimum wait time before any exit is possible
    /// @return Time in seconds
    function minCooldown() external view returns (uint48);
}

/*///////////////////////////////////////////////////////////////
                        Exit Queue
//////////////////////////////////////////////////////////////*/

interface IExitQueueErrorsAndEvents is
    IExitQueueCoreErrorsAndEvents,
    IExitQueueFeeErrorsAndEvents,
    IExitQueueCooldownErrorsAndEvents,
    IExitMinLockCooldownErrorsAndEvents,
    IEarlyExitQueueEventsAndErrors
{}

interface IDynamicExitQueue is
    IExitQueueErrorsAndEvents,
    ITicketV2,
    IExitQueueFee,
    IExitQueueCooldown,
    IExitQueueMinLock,
    IEarlyExitQueue
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
