/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IDynamicExitQueue, IDynamicExitQueueFee} from "./IDynamicExitQueue.sol";
import {
    IERC20Upgradeable as IERC20
} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVotingEscrowIncreasing as IVotingEscrow} from "@escrow/IVotingEscrowIncreasing.sol";
import {IClockUser, IClock} from "@clock/IClock.sol";

import {
    SafeERC20Upgradeable as SafeERC20
} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    DaoAuthorizableUpgradeable as DaoAuthorizable
} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizableUpgradeable.sol";

/// @title DynamicExitQueue
/// @notice Token IDs associated with an NFT are given a ticket when they are queued for exit.
/// After a cooldown period, the ticket holder can exit the NFT with dynamic fee calculations.
contract DynamicExitQueue is IDynamicExitQueue, IClockUser, DaoAuthorizable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice role required to manage the exit queue
    bytes32 public constant QUEUE_ADMIN_ROLE = keccak256("QUEUE_ADMIN");

    /// @notice role required to withdraw tokens from the escrow contract
    bytes32 public constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");

    /// @dev 10_000 = 100%
    uint16 private constant MAX_FEE_PERCENT = 10_000;

    /// @notice the highest fee someone will pay on exit
    uint256 public feePercent;

    /// @notice address of the escrow contract
    address public escrow;

    /// @notice clock contract for epoch duration
    address public clock;

    /// @notice time in seconds between entering queue and exiting on optimal terms
    uint48 public cooldown;

    /// @notice minimum time from the original lock date before one can enter the queue
    uint48 public minLock;

    /// @notice tokenId => TicketV2
    mapping(uint256 => TicketV2) internal _queue;

    /*//////////////////////////////////////////////////////////////
			  Dynamic Fee Params
    //////////////////////////////////////////////////////////////*/

    /// @notice Minimum fee percent charged after full cooldown period
    uint256 public minFeePercent;

    /// @notice Minimum wait time before any exit is possible
    uint48 public minCooldown;

    /// @notice Fee decrease per second (basis points/second) during decay period
    /// @dev Set to 0 when minCooldown == cooldown to prevent division by zero
    uint256 private _slope;

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
        uint48 _cooldown,
        address _dao,
        uint256 _feePercent,
        address _clock,
        uint48 _minLock
    ) external initializer {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
        escrow = _escrow;
        clock = _clock;
        _setMinLock(_minLock);

        // Initialize with fixed fee system
        if (_feePercent > MAX_FEE_PERCENT) revert FeePercentTooHigh(MAX_FEE_PERCENT);
        _setFixedExitFeePercent(_feePercent, _cooldown, true);
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

    /// @notice The exit queue manager can set the minimum lock time
    function setMinLock(uint48 _minLock) external auth(QUEUE_ADMIN_ROLE) {
        _setMinLock(_minLock);
    }

    function _setMinLock(uint48 _minLock) internal {
        if (_minLock == 0) revert MinLockOutOfBounds();
        minLock = _minLock;
        emit MinLockSet(_minLock);
    }

    /// @inheritdoc IDynamicExitQueueFee
    function setDynamicExitFeePercent(
        uint256 _minFeePercent,
        uint256 _maxFeePercent,
        uint48 _cooldown,
        uint48 _minCooldown
    ) external auth(QUEUE_ADMIN_ROLE) {
        if (_minFeePercent > MAX_FEE_PERCENT || _maxFeePercent > MAX_FEE_PERCENT) {
            revert FeePercentTooHigh(MAX_FEE_PERCENT);
        }
        if (_maxFeePercent <= _minFeePercent) revert InvalidFeeParameters();
        // setting cooldown == minCooldown would imply a vertical slope
        if (_cooldown <= _minCooldown) revert CooldownTooShort();

        _setDynamicExitFeePercent(_minFeePercent, _maxFeePercent, _cooldown, _minCooldown);
    }

    /// @inheritdoc IDynamicExitQueueFee
    function setTieredExitFeePercent(
        uint256 _baseFeePercent,
        uint256 _earlyFeePercent,
        uint48 _cooldown,
        uint48 _minCooldown
    ) external auth(QUEUE_ADMIN_ROLE) {
        if (_baseFeePercent > MAX_FEE_PERCENT || _earlyFeePercent > MAX_FEE_PERCENT) {
            revert FeePercentTooHigh(MAX_FEE_PERCENT);
        }
        if (_earlyFeePercent <= _baseFeePercent) revert InvalidFeeParameters();
        if (_cooldown <= _minCooldown) revert CooldownTooShort();

        _setTieredExitFeePercent(_baseFeePercent, _earlyFeePercent, _cooldown, _minCooldown);
    }

    /// @inheritdoc IDynamicExitQueueFee
    function setFixedExitFeePercent(
        uint256 _feePercent,
        uint48 _cooldown,
        bool _allowEarlyExit
    ) external auth(QUEUE_ADMIN_ROLE) {
        if (_feePercent > MAX_FEE_PERCENT) revert FeePercentTooHigh(MAX_FEE_PERCENT);

        _setFixedExitFeePercent(_feePercent, _cooldown, _allowEarlyExit);
    }

    function _setDynamicExitFeePercent(
        uint256 _minFeePercent,
        uint256 _maxFeePercent,
        uint48 _cooldown,
        uint48 _minCooldown
    ) internal {
        feePercent = _maxFeePercent;
        minFeePercent = _minFeePercent;
        cooldown = _cooldown;
        minCooldown = _minCooldown;
        _slope = _computeSlope(_minFeePercent, _maxFeePercent, _cooldown, _minCooldown);

        emit ExitFeePercentAdjusted(
            _maxFeePercent,
            _minFeePercent,
            _slope,
            _minCooldown,
            ExitFeeType.Dynamic
        );
    }

    function _setTieredExitFeePercent(
        uint256 _baseFeePercent,
        uint256 _earlyFeePercent,
        uint48 _cooldown,
        uint48 _minCooldown
    ) internal {
        feePercent = _earlyFeePercent;
        minFeePercent = _baseFeePercent;
        cooldown = _cooldown;
        minCooldown = _minCooldown;
        _slope = 0; // No decay in tiered system

        emit ExitFeePercentAdjusted(
            _earlyFeePercent,
            _baseFeePercent,
            0,
            _minCooldown,
            ExitFeeType.Tiered
        );
    }

    function _setFixedExitFeePercent(
        uint256 _feePercent,
        uint48 _cooldown,
        bool _allowEarlyExit
    ) internal {
        feePercent = _feePercent;
        minFeePercent = _feePercent;
        cooldown = _cooldown;
        _slope = 0; // No decay in fixed system

        // immediate or none
        if (_allowEarlyExit) minCooldown = 0;
        else minCooldown = _cooldown;

        emit ExitFeePercentAdjusted(_feePercent, _feePercent, 0, minCooldown, ExitFeeType.Fixed);
    }

    /*//////////////////////////////////////////////////////////////
                              SLOPE
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the rate of fee decrease per second during the decay period
    /// @dev will return 0 if the fee system is not dynamic
    function slope() external view returns (uint256) {
        return _slope / MAX_FEE_PERCENT;
    }

    function _computeSlope(
        uint256 _minFeePercent,
        uint256 _maxFeePercent,
        uint48 _cooldown,
        uint48 _minCooldown
    ) internal pure returns (uint256) {
        // Calculate slope - safe from division by zero due to validation
        uint256 numerator = (_maxFeePercent - _minFeePercent) * MAX_FEE_PERCENT;
        return numerator / (_cooldown - _minCooldown);
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
        uint48 minLockTime = timeToMinLock(_tokenId);
        if (minLockTime > block.timestamp) revert MinLockNotReached(_tokenId, minLock, minLockTime);

        uint48 queuedAt = uint48(block.timestamp);
        _queue[_tokenId] = TicketV2(_ticketHolder, queuedAt);

        emit ExitQueuedV2(_tokenId, _ticketHolder, queuedAt);
    }

    /// @notice Exits the queue for that tokenID.
    /// @dev The holder is not checked. This is left up to the escrow contract to manage.
    function exit(uint256 _tokenId) external onlyEscrow returns (uint256 fee) {
        if (!canExit(_tokenId)) revert CannotExit();

        // calculate fee before resetting ticket
        fee = calculateFee(_tokenId);

        // reset the ticket for that tokenId
        _queue[_tokenId] = TicketV2(address(0), 0);

        emit Exit(_tokenId, fee);
    }

    /// @notice Calculate the absolute fee amount for exiting a specific token
    /// @param _tokenId The token ID to calculate fee for
    /// @return Fee amount in underlying token units
    function calculateFee(uint256 _tokenId) public view returns (uint256) {
        TicketV2 memory ticket = _queue[_tokenId];
        if (ticket.holder == address(0)) return 0;

        uint256 underlyingBalance = IVotingEscrow(escrow).locked(_tokenId).amount;
        if (underlyingBalance == 0) revert NoLockBalance();

        uint256 timeElapsed = block.timestamp - ticket.queuedAt;
        uint256 feePercentToApply = getTimeBasedFee(timeElapsed);

        return (underlyingBalance * feePercentToApply) / MAX_FEE_PERCENT;
    }

    /// @notice Calculate the exit fee percent for a given time elapsed
    /// @param timeElapsed Time elapsed since ticket was queued
    /// @return Fee percent in basis points
    function getTimeBasedFee(uint256 timeElapsed) public view returns (uint256) {
        // Fixed fee system (no decay, no tiers)
        if (minFeePercent == feePercent) return feePercent;

        // Tiered system w. no slope
        // Early exit period: feePercent, after cooldown: minFeePercent
        if (_slope == 0) {
            return timeElapsed <= cooldown ? feePercent : minFeePercent;
        }

        // Dynamic system (linear decay)
        if (timeElapsed <= minCooldown) return feePercent;
        else if (timeElapsed > cooldown) return minFeePercent;

        // we only start decaying after minCooldown
        uint256 feeReduction = (_slope * (timeElapsed - minCooldown)) / MAX_FEE_PERCENT;

        if (feeReduction >= (feePercent - minFeePercent)) return minFeePercent;
        else return feePercent - feeReduction;
    }

    /*//////////////////////////////////////////////////////////////
                              View Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if a token has completed its full cooldown period (minimum fee applies)
    /// @param _tokenId The token ID to check
    /// @return True if full cooldown elapsed, false otherwise
    function isCool(uint256 _tokenId) public view returns (bool) {
        TicketV2 memory ticket = _queue[_tokenId];
        if (ticket.holder == address(0)) return false;
        return block.timestamp - ticket.queuedAt > cooldown;
    }

    /// @return true if the tokenId corresponds to a valid ticket and the minimum cooldown period has passed
    function canExit(uint256 _tokenId) public view returns (bool) {
        TicketV2 memory ticket = _queue[_tokenId];
        if (ticket.holder == address(0)) return false;
        return block.timestamp - ticket.queuedAt > minCooldown;
    }

    /// @return holder of a ticket for a given tokenId
    function ticketHolder(uint256 _tokenId) external view returns (address) {
        return _queue[_tokenId].holder;
    }

    function queue(uint256 _tokenId) external view override returns (TicketV2 memory) {
        return _queue[_tokenId];
    }

    function timeToMinLock(uint256 _tokenId) public view returns (uint48) {
        uint48 lockStart = IVotingEscrow(escrow).locked(_tokenId).start;
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

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[42] private __gap; // Reduced to account for new state variables
}
