pragma solidity ^0.8.17;

import {DaoAuthorizable} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizable.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IExitQueue} from "./interfaces/IExitQueue.sol";

/// @title ExitQueue
/// @notice Token IDs associated with an NFT are given a ticket when they are queued for exit.
/// After a cooldown period, the ticket holder can exit the NFT.
contract ExitQueue is IExitQueue, DaoAuthorizable {
    /// @notice role required to manage the exit queue
    bytes32 public constant QUEUE_ADMIN_ROLE = keccak256("QUEUE_ADMIN");

    /// @notice address of the escrow contract
    address public immutable escrow;

    /// @notice tokenId => Ticket
    mapping(uint256 => Ticket) internal _queue;

    /// @notice time in seconds between exit and withdrawal
    uint256 public cooldown;

    /*//////////////////////////////////////////////////////////////
                              Constructor
    //////////////////////////////////////////////////////////////*/

    /// @param _escrow address of the escrow contract where tokens are stored
    /// @param _cooldown time in seconds between exit and withdrawal
    /// @param _dao address of the DAO that will be able to set the queue
    constructor(address _escrow, uint256 _cooldown, address _dao) DaoAuthorizable(IDAO(_dao)) {
        escrow = _escrow;
        _setCooldown(_cooldown);
    }

    /*//////////////////////////////////////////////////////////////
                              Admin Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice The exit queue manager can set the cooldown period
    /// @param _cooldown time in seconds between exit and withdrawal
    function setCooldown(uint256 _cooldown) external auth(QUEUE_ADMIN_ROLE) {
        _setCooldown(_cooldown);
    }

    function _setCooldown(uint256 _cooldown) internal {
        cooldown = _cooldown;
        emit CooldownSet(_cooldown);
    }

    /*//////////////////////////////////////////////////////////////
                              Exit Logic
    //////////////////////////////////////////////////////////////*/

    /// @notice queue an exit for a given tokenId, granting the ticket to the passed holder
    /// @param _tokenId the tokenId to queue an exit for
    /// @param _ticketHolder the address that will be granted the ticket
    /// @dev we don't check that the ticket holder is the caller
    /// this is because the escrow contract is the only one that can queue an exit
    /// and we leave that logic to the escrow contract
    function queueExit(uint256 _tokenId, address _ticketHolder) external {
        if (msg.sender != address(escrow)) revert OnlyEscrow();
        if (_ticketHolder == address(0)) revert ZeroAddress();
        if (_queue[_tokenId].holder != address(0)) revert AlreadyQueued();

        _queue[_tokenId] = Ticket(_ticketHolder, block.timestamp);
        emit ExitQueued(_tokenId, _ticketHolder);
    }

    /// @notice Exits the queue for that tokenID.
    /// @dev The holder is not checked. This is left up to the escrow contract to manage.
    function exit(uint256 _tokenId) external {
        if (msg.sender != address(escrow)) revert OnlyEscrow();
        if (!canExit(_tokenId)) revert CannotExit();

        // reset the ticket for that tokenId
        _queue[_tokenId] = Ticket(address(0), 0);
        emit Exit(_tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                              View Functions
    //////////////////////////////////////////////////////////////*/

    /// @return true if the tokenId corresponds to a valid ticket and the cooldown period has passed
    /// @dev If the admin chages the cooldown, this will affect all ticket holders. We may not want this.
    function canExit(uint256 _tokenId) public view returns (bool) {
        Ticket memory ticket = _queue[_tokenId];
        if (ticket.holder == address(0)) return false;

        // TODO: we could hardcode the end date, this would prevent the admin from arbitrarily changing the cooldown
        // whilst the exit is pending
        return block.timestamp >= ticket.timestamp + cooldown;
    }

    /// @return holder of a ticket for a given tokenId
    function ticketHolder(uint256 _tokenId) external view returns (address) {
        return _queue[_tokenId].holder;
    }

    function queue(uint256 _tokenId) external view override returns (Ticket memory) {
        return _queue[_tokenId];
    }
}
