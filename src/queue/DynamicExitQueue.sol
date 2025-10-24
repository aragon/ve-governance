/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
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
} from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";

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

    /// @dev 1e18 is used for internal precision in fee calculations
    uint256 private constant INTERNAL_PRECISION = 1e18;

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
    uint256 internal _slope;

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

        // Initialize with fixed fee system, no early exits
        if (_feePercent > MAX_FEE_PERCENT) revert FeePercentTooHigh(MAX_FEE_PERCENT);
        _setFixedExitFeePercent(_feePercent, _cooldown);
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
        uint48 _minCooldown
    ) external auth(QUEUE_ADMIN_ROLE) {
        if (_feePercent > MAX_FEE_PERCENT) revert FeePercentTooHigh(MAX_FEE_PERCENT);

        _setFixedExitFeePercent(_feePercent, _minCooldown);
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
            _minCooldown,
            ExitFeeType.Tiered
        );
    }

    function _setFixedExitFeePercent(uint256 _feePercent, uint48 _cooldown) internal {
        feePercent = _feePercent;
        minFeePercent = _feePercent;
        cooldown = _cooldown;
        minCooldown = _cooldown;
        _slope = 0; // No decay in fixed system

        emit ExitFeePercentAdjusted(_feePercent, _feePercent, minCooldown, ExitFeeType.Fixed);
    }

    /*//////////////////////////////////////////////////////////////
                              SLOPE
    //////////////////////////////////////////////////////////////*/

    function _computeSlope(
        uint256 _minFeePercent,
        uint256 _maxFeePercent,
        uint48 _cooldown,
        uint48 _minCooldown
    ) internal pure returns (uint256) {
        // Calculate slope in 1e18 scale for maximum precision
        uint256 scaledMaxFee = (_maxFeePercent * INTERNAL_PRECISION) / MAX_FEE_PERCENT;
        uint256 scaledMinFee = (_minFeePercent * INTERNAL_PRECISION) / MAX_FEE_PERCENT;
        uint256 scaledFeeRange = scaledMaxFee - scaledMinFee;
        uint256 timeRange = _cooldown - _minCooldown;
        return scaledFeeRange / timeRange;
    }

    /*//////////////////////////////////////////////////////////////
                              WITHDRAWER
    //////////////////////////////////////////////////////////////*/

    /// @notice withdraw staked tokens sent as part of fee collection to the caller
    /// @dev The caller must be authorized to withdraw by the DAO
    function withdraw(uint256 _amount) external auth(WITHDRAW_ROLE) {
        IERC20 underlying = IERC20(IVotingEscrow(escrow).token());
        underlying.safeTransfer(msg.sender, _amount);
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
        if (minLockTime > block.timestamp) {
            revert MinLockNotReached(_tokenId, minLock, minLockTime);
        }

        uint48 queuedAt = uint48(block.timestamp);
        _queue[_tokenId] = TicketV2({
            holder: _ticketHolder,
            queuedAt: queuedAt,
            feePercent: uint16(feePercent),
            minFeePercent: uint16(minFeePercent),
            cooldown: cooldown,
            minCooldown: minCooldown,
            slope: _slope
        });

        emit ExitQueuedV2(_tokenId, _ticketHolder, queuedAt);
    }

    /// @notice Exits the queue for that tokenID.
    /// @dev The holder is not checked. This is left up to the escrow contract to manage.
    function exit(uint256 _tokenId) external onlyEscrow returns (uint256 fee) {
        if (!canExit(_tokenId)) revert CannotExit();

        // calculate fee before resetting ticket
        fee = calculateFee(_tokenId);

        // reset the ticket for that tokenId
        delete _queue[_tokenId];

        emit Exit(_tokenId, fee);
    }

    /// @notice Cancels the exit.
    /// @dev The token must have a holder.
    function cancelExit(uint256 _tokenId) external onlyEscrow {
        TicketV2 memory ticket = _queue[_tokenId];

        // This should never occur as escrow already checks this
        // but for safety, still advisable to have this check.
        if (ticket.holder == address(0)) {
            revert CannotCancelExit();
        }

        delete _queue[_tokenId];
        emit ExitCancelled(_tokenId, ticket.holder);
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
        uint256 scaledFeePercent = _getScaledTimeBasedFee(timeElapsed, ticket);
        return (underlyingBalance * scaledFeePercent) / INTERNAL_PRECISION;
    }

    /// @notice Internal function to get time-based fee in 1e18 scale
    /// @param timeElapsed Time elapsed since ticket was queued
    /// @param ticket The ticket to calculate fee for - ensures changes to global params don't affect existing tickets
    /// @return Fee percent in 1e18 scale (0 = 0%, 1e18 = 100%)
    function _getScaledTimeBasedFee(
        uint256 timeElapsed,
        TicketV2 memory ticket
    ) internal view returns (uint256) {
        uint256 scaledMaxFee = (ticket.feePercent * INTERNAL_PRECISION) / MAX_FEE_PERCENT;
        uint256 scaledMinFee = (ticket.minFeePercent * INTERNAL_PRECISION) / MAX_FEE_PERCENT;

        // Fixed fee system (no decay, no tiers)
        if (ticket.minFeePercent == ticket.feePercent) return scaledMaxFee;

        // Tiered system (no slope) or fixed system
        if (ticket.slope == 0) {
            return timeElapsed <= ticket.cooldown ? scaledMaxFee : scaledMinFee;
        }

        // Dynamic system (linear decay using stored slope)
        if (timeElapsed <= ticket.minCooldown) return scaledMaxFee;
        if (timeElapsed >= ticket.cooldown) return scaledMinFee;

        // Calculate fee reduction using high-precision slope
        uint256 timeInDecay = timeElapsed - ticket.minCooldown;
        uint256 feeReduction = ticket.slope * timeInDecay;

        // Ensure we don't go below minimum fee
        if (feeReduction >= (scaledMaxFee - scaledMinFee)) {
            return scaledMinFee;
        }

        return scaledMaxFee - feeReduction;
    }

    /// @notice Calculate the exit fee percent for a given time elapsed
    /// @param timeElapsed Time elapsed since ticket was queued
    /// @return Fee percent in basis points
    function getTimeBasedFee(uint256 timeElapsed) public view returns (uint256) {
        uint256 scaledFee = _getScaledTimeBasedFee(timeElapsed, _globalTicket());
        return (scaledFee * MAX_FEE_PERCENT) / INTERNAL_PRECISION;
    }

    /// @dev global parameters as a ticket for fee calculation
    function _globalTicket() internal view returns (TicketV2 memory) {
        return
            TicketV2({
                holder: address(0),
                queuedAt: 0,
                feePercent: uint16(feePercent),
                minFeePercent: uint16(minFeePercent),
                cooldown: cooldown,
                minCooldown: minCooldown,
                slope: _slope
            });
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
        return block.timestamp - ticket.queuedAt >= ticket.cooldown;
    }

    /// @return true if the tokenId corresponds to a valid ticket and the minimum cooldown period has passed
    function canExit(uint256 _tokenId) public view returns (bool) {
        TicketV2 memory ticket = _queue[_tokenId];
        if (ticket.holder == address(0)) return false;
        return block.timestamp - ticket.queuedAt >= ticket.minCooldown;
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
