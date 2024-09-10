pragma solidity ^0.8.0;

interface IExitQueueErrors {
    error OnlyEscrow();
    error AlreadyQueued();
    error ZeroAddress();
    error CannotExit();
    error FeeTooHigh();
    error NoLockBalance();
}

interface IExitQueueEvents {
    event ExitQueued(uint256 indexed tokenId, address indexed holder, uint256 exitDate);
    event Exit(uint256 indexed tokenId, uint256 fee);
    event CooldownSet(uint256 cooldown);
    event FeePercentSet(uint256 feePercent);
}

interface ITicket {
    struct Ticket {
        address holder;
        uint256 exitDate;
    }
}

interface IExitQueue is IExitQueueErrors, IExitQueueEvents, ITicket {
    function feePercent() external view returns (uint256);

    /// @notice tokenId => Ticket
    function queue(uint256 _tokenId) external view returns (Ticket memory);

    /// @notice time in seconds between exit and withdrawal
    function cooldown() external view returns (uint256);

    /// @notice The exit queue manager can set the cooldown period
    /// @param _cooldown time in seconds between exit and withdrawal
    function setCooldown(uint256 _cooldown) external;

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
