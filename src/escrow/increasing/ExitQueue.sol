/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IExitQueue} from "./interfaces/IExitQueue.sol";
import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVotingEscrowIncreasing as IVotingEscrow} from "@escrow-interfaces/IVotingEscrowIncreasing.sol";
import {IClockUser, IClock} from "@clock/IClock.sol";

import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {DaoAuthorizableUpgradeable as DaoAuthorizable} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizableUpgradeable.sol";

/// @title ExitQueue
/// @notice Token IDs associated with an NFT are given a ticket when they are queued for exit.
/// After a cooldown period, the ticket holder can exit the NFT.
contract ExitQueue is IExitQueue, IClockUser, DaoAuthorizable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice role required to manage the exit queue
    bytes32 public constant QUEUE_ADMIN_ROLE = keccak256("QUEUE_ADMIN");

    /// @notice role required to withdraw tokens from the escrow contract
    bytes32 public constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");

    /// @dev 10_000 = 100%
    uint16 private constant MAX_FEE_PERCENT = 10_000;

    /// @notice the fee percent charged on withdrawals
    uint256 public feePercent;

    /// @notice address of the escrow contract
    address public escrow;

    /// @notice clock contract for epoch duration
    address public clock;

    /// @notice time in seconds between exit and withdrawal
    uint256 public cooldown;

    /// @notice minimum time from the original lock date before one can enter the queue
    uint256 public minLock;

    /// @notice tokenId => Ticket
    mapping(uint256 => Ticket) internal _queue;

    /*//////////////////////////////////////////////////////////////
                              Constructor
    //////////////////////////////////////////////////////////////*/
    constructor() {
        _disableInitializers();
    }

    /// @param _escrow address of the escrow contract where tokens are stored
    /// @param _cooldown time in seconds between exit and withdrawal
    /// @param _dao address of the DAO that will be able to set the queue
    function initialize(
        address _escrow,
        uint256 _cooldown,
        address _dao,
        uint256 _feePercent,
        address _clock,
        uint256 _minLock
    ) external initializer {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
        escrow = _escrow;
        clock = _clock;
        _setMinLock(_minLock);
        _setFeePercent(_feePercent);
        _setCooldown(_cooldown);
    }

    /*//////////////////////////////////////////////////////////////
                              Modifiers
    //////////////////////////////////////////////////////////////*/

    modifier onlyEscrow() {
        if (msg.sender != escrow) revert OnlyEscrow();
        _;
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

    /// @notice The exit queue manager can set the fee percent
    /// @param _feePercent the fee percent charged on withdrawals
    function setFeePercent(uint256 _feePercent) external auth(QUEUE_ADMIN_ROLE) {
        _setFeePercent(_feePercent);
    }

    function _setFeePercent(uint256 _feePercent) internal {
        if (_feePercent > MAX_FEE_PERCENT) revert FeeTooHigh(MAX_FEE_PERCENT);
        feePercent = _feePercent;
        emit FeePercentSet(_feePercent);
    }

    /// @notice The exit queue manager can set the minimum lock time
    /// @param _minLock the minimum time from the original lock date before one can enter the queue
    function setMinLock(uint256 _minLock) external auth(QUEUE_ADMIN_ROLE) {
        _setMinLock(_minLock);
    }

    function _setMinLock(uint256 _minLock) internal {
        minLock = _minLock;
        emit MinLockSet(_minLock);
    }

    /*//////////////////////////////////////////////////////////////
                              WITHDRAWER
    //////////////////////////////////////////////////////////////*/

    /// @notice withdraw staked tokens sent as part of fee collection to the caller
    /// @dev The caller must be authorized to withdraw by the DAO
    function withdraw(uint256 _amount) external auth(WITHDRAW_ROLE) {
        IERC20 underlying = IERC20(IVotingEscrow(escrow).token());
        underlying.transfer(msg.sender, _amount);
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
    function queueExit(uint256 _tokenId, address _ticketHolder) external onlyEscrow {
        if (_ticketHolder == address(0)) revert ZeroAddress();
        if (_queue[_tokenId].holder != address(0)) revert AlreadyQueued();

        // get time to min lock and revert if it hasn't been reached
        uint minLockTime = timeToMinLock(_tokenId);
        if (minLockTime > block.timestamp) revert MinLockNotReached(_tokenId, minLock, minLockTime);

        uint exitDate = nextExitDate();

        _queue[_tokenId] = Ticket(_ticketHolder, exitDate);
        emit ExitQueued(_tokenId, _ticketHolder, exitDate);
    }

    /// @notice Returns the next exit date for a ticket
    /// @dev The next exit date is the later of the cooldown expiry and the next checkpoint
    function nextExitDate() public view returns (uint256) {
        // snap to next checkpoint interval, we can't cooldown before this
        uint nextCP = IClock(clock).epochNextCheckpointTs();
        uint cooldownExpiry = block.timestamp + cooldown;

        // if the next cp is after the cooldown, return the next cp
        return nextCP >= cooldownExpiry ? nextCP : cooldownExpiry;
    }

    /// @notice Exits the queue for that tokenID.
    /// @dev The holder is not checked. This is left up to the escrow contract to manage.
    function exit(uint256 _tokenId) external onlyEscrow returns (uint256 fee) {
        if (!canExit(_tokenId)) revert CannotExit();

        // reset the ticket for that tokenId
        _queue[_tokenId] = Ticket(address(0), 0);

        // return the fee to the caller
        fee = calculateFee(_tokenId);
        emit Exit(_tokenId, fee);
    }

    /// @notice Calculate the exit fee for a given tokenId
    function calculateFee(uint256 _tokenId) public view returns (uint256) {
        if (feePercent == 0) return 0;
        uint underlyingBalance = IVotingEscrow(escrow).locked(_tokenId).amount;
        if (underlyingBalance == 0) revert NoLockBalance();
        return (underlyingBalance * feePercent) / MAX_FEE_PERCENT;
    }

    /*//////////////////////////////////////////////////////////////
                              View Functions
    //////////////////////////////////////////////////////////////*/

    /// @return true if the tokenId corresponds to a valid ticket and the cooldown period has passed
    /// @dev If the admin chages the cooldown, this will affect all ticket holders. We may not want this.
    function canExit(uint256 _tokenId) public view returns (bool) {
        Ticket memory ticket = _queue[_tokenId];
        if (ticket.holder == address(0)) return false;
        return block.timestamp >= ticket.exitDate;
    }

    /// @return holder of a ticket for a given tokenId
    function ticketHolder(uint256 _tokenId) external view returns (address) {
        return _queue[_tokenId].holder;
    }

    function queue(uint256 _tokenId) external view override returns (Ticket memory) {
        return _queue[_tokenId];
    }

    function timeToMinLock(uint256 _tokenId) public view returns (uint256) {
        uint256 lockStart = IVotingEscrow(escrow).locked(_tokenId).start;
        return lockStart + minLock;
    }

    /*///////////////////////////////////////////////////////////////
                            UUPS Upgrade
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the address of the implementation contract in the [proxy storage slot](https://eips.ethereum.org/EIPS/eip-1967) slot the [UUPS proxy](https://eips.ethereum.org/EIPS/eip-1822) is pointing to.
    /// @return The address of the implementation contract.
    function implementation() public view returns (address) {
        return _getImplementation();
    }

    /// @notice Internal method authorizing the upgrade of the contract via the [upgradeability mechanism for UUPS proxies](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable) (see [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822)).
    function _authorizeUpgrade(address) internal virtual override auth(QUEUE_ADMIN_ROLE) {}

    uint256[44] private __gap;
}
