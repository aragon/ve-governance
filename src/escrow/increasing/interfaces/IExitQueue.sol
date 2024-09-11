/// SPDX-License-Identifier: MIT
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

interface ITicket {
    struct Ticket {
        address holder;
        uint256 exitDate;
    }
}

/*///////////////////////////////////////////////////////////////
                        Fee Collection
//////////////////////////////////////////////////////////////*/

interface IExitQueueFeeErrorsAndEvents {
    error FeeTooHigh();

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

    event CooldownSet(uint256 cooldown);
}

interface IExitQueueCooldown is IExitQueueCooldownErrorsAndEvents {
    /// @notice time in seconds between exit and withdrawal
    function cooldown() external view returns (uint256);

    /// @notice The exit queue manager can set the cooldown period
    /// @param _cooldown time in seconds between exit and withdrawal
    function setCooldown(uint256 _cooldown) external;
}

/*///////////////////////////////////////////////////////////////
                        Exit Queue
//////////////////////////////////////////////////////////////*/

interface IExitQueueErrorsAndEvents is
    IExitQueueCoreErrorsAndEvents,
    IExitQueueFeeErrorsAndEvents,
    IExitQueueCooldownErrorsAndEvents
{

}

interface IExitQueue is IExitQueueErrorsAndEvents, ITicket, IExitQueueFee, IExitQueueCooldown {
    /// @notice tokenId => Ticket
    function queue(uint256 _tokenId) external view returns (Ticket memory);

    /// @notice queue an exit for a given tokenId, granting the ticket to the passed holder
    /// @param _tokenId the tokenId to queue an exit for
    /// @param _ticketHolder the address that will be granted the ticket
    function queueExit(uint256 _tokenId, address _ticketHolder) external;

    /// @notice exit the queue for a given tokenId. Requires the cooldown period to have passed
    /// @return exitAmount the amount of tokens that can be withdrawn
    function exit(uint256 _tokenId) external returns (uint256 exitAmount);

    /// @return true if the tokenId corresponds to a valid ticket and the cooldown period has passed
    function canExit(uint256 _tokenId) external view returns (bool);

    /// @return the ticket holder for a given tokenId
    function ticketHolder(uint256 _tokenId) external view returns (address);
}
