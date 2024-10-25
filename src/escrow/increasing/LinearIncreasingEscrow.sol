/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotingEscrowIncreasing as IVotingEscrow} from "@escrow-interfaces/IVotingEscrowIncreasing.sol";
import {IEscrowCurveIncreasingGlobal as IEscrowCurve} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {IClockUser, IClock} from "@clock/IClock.sol";

// libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SignedFixedPointMath} from "@libs/SignedFixedPointMathLib.sol";
import {CurveConstantLib} from "@libs/CurveConstantLib.sol";

// contracts
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {DaoAuthorizableUpgradeable as DaoAuthorizable} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizableUpgradeable.sol";

import {console2 as console} from "forge-std/console2.sol";

/// @title Linear Increasing Escrow
contract LinearIncreasingEscrow is
    IEscrowCurve,
    IClockUser,
    ReentrancyGuard,
    DaoAuthorizable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
    using SafeCast for int256;
    using SafeCast for uint256;
    using SignedFixedPointMath for int256;

    error OnlyEscrow();

    /// @notice Administrator role for the contract
    bytes32 public constant CURVE_ADMIN_ROLE = keccak256("CURVE_ADMIN_ROLE");

    /// @notice The VotingEscrow contract address
    address public escrow;

    /// @notice The Clock contract address
    address public clock;

    /// @notice tokenId => point epoch: incremented on a per-tokenId basis
    mapping(uint256 => uint256) public tokenPointIntervals;

    /// @notice The warmup period for the curve
    uint48 public warmupPeriod;

    /// @dev tokenId => tokenPointIntervals => TokenPoint
    /// @dev The Array is fixed so we can write to it in the future
    mapping(uint256 => TokenPoint[1_000_000_000]) internal _tokenPointHistory;

    /*//////////////////////////////////////////////////////////////
                                ADDED: 0.2.0
    //////////////////////////////////////////////////////////////*/

    /// @dev Global state snapshots in the past
    /// pointIndex => GlobalPoint
    mapping(uint256 => GlobalPoint) internal _pointHistory;

    /// @dev Scheduled adjustments to the curve at points in the future
    /// interval timestamp => [bias, slope, 0]
    mapping(uint48 => int256[3]) internal _scheduledCurveChanges;

    /// @dev The latest global point index.
    uint256 internal _latestPointIndex;

    /// @dev Written to when the first deposit is made in the future
    /// this is used to determine when to begin writing global points
    uint48 internal _earliestScheduledChange;

    /// @notice emulation of array like structure starting at 1 index for global points
    /// @return The state snapshot at the given index.
    /// @dev Points are written at least weekly.
    function pointHistory(uint256 _index) external view returns (GlobalPoint memory) {
        return _pointHistory[_index];
    }

    /// @notice Returns the scheduled bias and slope changes at a given timestamp
    /// @param _at the timestamp to check, can be in the future, but such values can change.
    function scheduledCurveChanges(uint48 _at) external view returns (int256[3] memory) {
        return [
            SignedFixedPointMath.fromFP(_scheduledCurveChanges[_at][0]),
            SignedFixedPointMath.fromFP(_scheduledCurveChanges[_at][1]),
            0
        ];
    }

    /// @notice How many GlobalPoints have been written, starting at 1.
    function latestPointIndex() external view returns (uint) {
        return _latestPointIndex;
    }

    /// @notice The amount of time locks can accumulate voting power for since the start.
    function maxTime() external view returns (uint48) {
        return _maxTime().toUint48();
    }

    /*//////////////////////////////////////////////////////////////
                                MATH
    //////////////////////////////////////////////////////////////*/
    int256 private constant SHARED_LINEAR_COEFFICIENT = CurveConstantLib.SHARED_LINEAR_COEFFICIENT;

    int256 private constant SHARED_CONSTANT_COEFFICIENT =
        CurveConstantLib.SHARED_CONSTANT_COEFFICIENT;

    uint256 private constant MAX_EPOCHS = CurveConstantLib.MAX_EPOCHS;

    /*//////////////////////////////////////////////////////////////
                              INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    /// @param _escrow VotingEscrow contract address
    function initialize(
        address _escrow,
        address _dao,
        uint48 _warmupPeriod,
        address _clock
    ) external initializer {
        escrow = _escrow;
        warmupPeriod = _warmupPeriod;
        clock = _clock;

        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
        __ReentrancyGuard_init();

        // other initializers are empty
    }

    /*//////////////////////////////////////////////////////////////
                              CURVE COEFFICIENTS
    //////////////////////////////////////////////////////////////*/

    /// @return The coefficient for the linear term of the quadratic curve, for the given amount
    function _getLinearCoeff(uint256 amount) internal pure returns (int256) {
        return (SignedFixedPointMath.toFP(amount.toInt256())).mul(SHARED_LINEAR_COEFFICIENT);
    }

    /// @return The constant coefficient of the quadratic curve, for the given amount
    /// @dev In this case, the constant term is 1 so we just case the amount
    function _getConstantCoeff(uint256 amount) public pure returns (int256) {
        return (SignedFixedPointMath.toFP(amount.toInt256())).mul(SHARED_CONSTANT_COEFFICIENT);
    }

    /// @return The coefficients of the quadratic curve, for the given amount
    /// @dev The coefficients are returned in the order [constant, linear, quadratic]
    function _getCoefficients(uint256 amount) public pure returns (int256[3] memory) {
        return [_getConstantCoeff(amount), _getLinearCoeff(amount), 0];
    }

    /// @return The coefficients of the quadratic curve, for the given amount
    /// @dev The coefficients are returned in the order [constant, linear, quadratic]
    /// and are converted to regular 256-bit signed integers instead of their fixed-point representation
    function getCoefficients(uint256 amount) public pure returns (int256[3] memory) {
        int256[3] memory coefficients = _getCoefficients(amount);

        return [
            SignedFixedPointMath.fromFP(coefficients[0]),
            SignedFixedPointMath.fromFP(coefficients[1]),
            0
        ];
    }

    /*//////////////////////////////////////////////////////////////
                              CURVE BIAS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the bias for the given time elapsed and amount, up to the maximum time
    function getBias(uint256 timeElapsed, uint256 amount) public view returns (uint256) {
        int256[3] memory coefficients = _getCoefficients(amount);
        return _getBias(timeElapsed, coefficients);
    }

    /// @dev returns the bias ignoring negative values, maximum bounding and fixed point conversion
    function _getBiasUnbound(
        uint256 timeElapsed,
        int256[3] memory coefficients
    ) internal pure returns (int256) {
        int256 linear = coefficients[1];
        int256 const = coefficients[0];

        // convert the time to fixed point
        int256 t = SignedFixedPointMath.toFP(timeElapsed.toInt256());

        return linear.mul(t).add(const);
    }

    function _getBias(
        uint256 timeElapsed,
        int256[3] memory coefficients
    ) internal view returns (uint256) {
        uint256 MAX_TIME = _maxTime();
        timeElapsed = timeElapsed > MAX_TIME ? MAX_TIME : timeElapsed;

        int256 bias = _getBiasUnbound(timeElapsed, coefficients);

        // never return negative values
        // in the increasing case, this should never happen
        return bias.lt((0)) ? uint256(0) : SignedFixedPointMath.fromFP((bias)).toUint256();
    }

    function _maxTime() internal view returns (uint256) {
        return IClock(clock).epochDuration() * MAX_EPOCHS;
    }

    function previewMaxBias(uint256 amount) external view returns (uint256) {
        return getBias(_maxTime(), amount);
    }

    /*//////////////////////////////////////////////////////////////
                              Warmup
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the warmup period for the curve. Voting power accrues silently during this period.
    function setWarmupPeriod(uint48 _warmupPeriod) external auth(CURVE_ADMIN_ROLE) {
        warmupPeriod = _warmupPeriod;
        emit WarmupSet(_warmupPeriod);
    }

    /// @notice Returns whether the NFT is currently warm based on the first point
    function isWarm(uint256 _tokenId) external view returns (bool) {
        return isWarmAt(_tokenId, block.timestamp);
    }

    /// @notice Returns whether the NFT is warm based on the first point, for a given timestamp
    function isWarmAt(uint256 _tokenId, uint256 _timestamp) public view returns (bool) {
        TokenPoint memory point = _tokenPointHistory[_tokenId][1];
        if (point.coefficients[0] == 0) return false;
        else return _timestamp > point.writtenTs + warmupPeriod;
    }

    /*//////////////////////////////////////////////////////////////
                              BALANCE
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the TokenPoint at the passed interval
    /// @param _tokenId The NFT to return the TokenPoint for
    /// @param _tokenInterval The epoch to return the TokenPoint at
    function tokenPointHistory(
        uint256 _tokenId,
        uint256 _tokenInterval
    ) external view returns (TokenPoint memory) {
        return _tokenPointHistory[_tokenId][_tokenInterval];
    }

    /// @notice Binary search to get the token point interval for a token id at or prior to a given timestamp
    /// Once we have the point, we can apply the bias calculation to get the voting power.
    /// @dev If a token point does not exist prior to the timestamp, this will return 0.
    function _getPastTokenPointInterval(
        uint256 _tokenId,
        uint256 _timestamp
    ) internal view returns (uint256) {
        uint256 tokenInterval = tokenPointIntervals[_tokenId];
        if (tokenInterval == 0) return 0;

        // if the most recent point is before the timestamp, return it
        if (_tokenPointHistory[_tokenId][tokenInterval].checkpointTs <= _timestamp)
            return (tokenInterval);

        // Check if the first balance is after the timestamp
        // this means that the first interval has yet to start
        if (_tokenPointHistory[_tokenId][1].checkpointTs > _timestamp) return 0;

        uint256 lower = 0;
        uint256 upper = tokenInterval;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2;
            TokenPoint storage tokenPoint = _tokenPointHistory[_tokenId][center];
            if (tokenPoint.checkpointTs == _timestamp) {
                return center;
            } else if (tokenPoint.checkpointTs < _timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    /// @notice Binary search to get the global point index at or prior to a given timestamp
    /// @dev If a checkpoint does not exist prior to the timestamp, this will return 0.
    function getPastGlobalPointIndex(uint256 _timestamp) internal view returns (uint256) {
        if (_latestPointIndex == 0) return 0;

        // if the most recent point is before the timestamp, return it
        if (_pointHistory[_latestPointIndex].ts <= _timestamp) return (_latestPointIndex);

        // Check if the first balance is after the timestamp
        // this means that the first interval has yet to start
        if (_pointHistory[1].ts > _timestamp) return 0;

        uint256 lower = 0;
        uint256 upper = _latestPointIndex;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2;
            GlobalPoint storage globalPoint = _pointHistory[center];
            if (globalPoint.ts == _timestamp) {
                return center;
            } else if (globalPoint.ts < _timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    /// @notice Calculate voting power at some point in the past for a given tokenId
    /// @return votingPower The voting power at that time, if the first point is in warmup, returns 0
    function votingPowerAt(uint256 _tokenId, uint256 _timestamp) external view returns (uint256) {
        uint256 interval = _getPastTokenPointInterval(_tokenId, _timestamp);
        // epoch 0 is an empty point
        if (interval == 0) return 0;

        // check the warmup status of the token (first point only)
        if (!isWarmAt(_tokenId, _timestamp)) return 0;

        // fetch the start time of the lock
        uint start = IVotingEscrow(escrow).locked(_tokenId).start;

        // calculate the bounded elapsed time since the point, factoring in the original start
        TokenPoint memory lastPoint = _tokenPointHistory[_tokenId][interval];

        uint256 timeElapsed = boundedTimeSinceCheckpoint(
            uint48(start),
            lastPoint.checkpointTs,
            uint48(_timestamp)
        );

        // the bias here is converted from fixed point
        return _getBias(timeElapsed, lastPoint.coefficients);
    }

    /// @notice Calculate total voting power at some point in the past
    /// @param _timestamp Time to calculate the total voting power at
    /// @return totalSupply Total supply of voting power at that time
    /// @dev We have to walk forward from the last point to the timestamp because
    /// we cannot guarantee that allow checkpoints have been written between the last point and the timestamp
    /// covering scheduled changes.
    function supplyAt(uint256 _timestamp) external view returns (uint256 totalSupply) {
        // get the index of the last point before the timestamp
        uint256 index = getPastGlobalPointIndex(_timestamp);
        if (index == 0) return 0;

        GlobalPoint memory latestPoint = _pointHistory[index];
        uint48 latestCheckpoint = uint48(latestPoint.ts);
        uint48 interval = uint48(IClock(clock).checkpointInterval());

        if (latestPoint.ts != _timestamp) {
            // round down to floor of interval ensures we align with schedulling
            uint48 t_i = (latestCheckpoint / interval) * interval;

            for (uint256 i = 0; i < 255; ++i) {
                // the first interval is always the next one after the last checkpoint
                t_i += interval;

                // max now
                if (t_i > _timestamp) t_i = uint48(_timestamp);

                // fetch the changes for this interval
                int biasChange = _scheduledCurveChanges[t_i][0];
                int slopeChange = _scheduledCurveChanges[t_i][1];

                // we create a new "curve" by defining the coefficients starting from time t_i
                // our constant is the y intercept at t_i and is found by evalutating the curve between the last point and t_i
                latestPoint.coefficients[0] =
                    _getBiasUnbound(t_i - latestPoint.ts, latestPoint.coefficients) +
                    biasChange;

                // here we add the slope changes for next period
                // this can be positive or negative depending on if new deposits outweigh tapering effects + withdrawals
                latestPoint.coefficients[1] += slopeChange;

                // neither of these should happen
                if (latestPoint.coefficients[1] < 0) latestPoint.coefficients[1] = 0;
                if (latestPoint.coefficients[0] < 0) latestPoint.coefficients[0] = 0;

                // keep going until we reach the timestamp
                latestPoint.ts = t_i;
                if (t_i == _timestamp) {
                    break;
                }
            }
        }
        return (latestPoint.coefficients[0] / 1e18).toUint256();
    }

    /*//////////////////////////////////////////////////////////////
                              CHECKPOINT
    //////////////////////////////////////////////////////////////*/

    /// @notice A checkpoint can be called by the VotingEscrow contract to snapshot the user's voting power
    /// @dev We assume the escrow checks the validity of the locked balances before calling this function
    function checkpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) external nonReentrant {
        if (msg.sender != escrow) revert OnlyEscrow();
        if (_tokenId == 0) revert InvalidTokenId();
        if (!validateLockedBalances(_oldLocked, _newLocked)) revert("Invalid Locked Balances");
        _checkpoint(_tokenId, _oldLocked, _newLocked);
    }

    /// @dev manual checkpoint that can be called to ensure history is up to date
    function _checkpoint() internal nonReentrant {
        (GlobalPoint memory latestPoint, uint256 currentIndex) = _populateHistory();

        if (currentIndex != _latestPointIndex) {
            _latestPointIndex = currentIndex == 0 ? 1 : currentIndex;
            _pointHistory[currentIndex] = latestPoint;
        }
    }

    /// @dev Main checkpointing function for token and global state
    /// @param _tokenId The NFT token ID
    /// @param _oldLocked The previous locked balance and start time
    /// @param _newLocked The new locked balance and start time
    function _checkpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) internal {
        // write the token checkpoint, fetching the old and new points
        (TokenPoint memory oldTokenPoint, TokenPoint memory newTokenPoint) = _tokenCheckpoint(
            _tokenId,
            _newLocked
        );

        // update our schedules
        _scheduleCurveChanges(oldTokenPoint, newTokenPoint, _oldLocked, _newLocked);

        // if we need to: update the global state
        // this will also write the first point if the earliest scheduled change has elapsed
        (GlobalPoint memory latestPoint, uint256 currentIndex) = _populateHistory();

        // update the global with the latest token point
        // it may be the case that the token is writing a scheduled change
        // meaning there is no current change to latest global point
        bool tokenHasUpdateNow = newTokenPoint.checkpointTs == latestPoint.ts;
        if (tokenHasUpdateNow) {
            latestPoint = _applyTokenUpdateToGlobal(
                _newLocked.start,
                oldTokenPoint,
                newTokenPoint,
                latestPoint
            );
        }

        // if the currentIndex is unchanged, this means no extra state has been written globally
        // so no need to write if there are no changes from token + schedule
        if (currentIndex != _latestPointIndex || tokenHasUpdateNow) {
            // index starts at 1 - so if there are no global updates
            // but there is a token update, write it to index 1
            _latestPointIndex = currentIndex == 0 ? 1 : currentIndex;
            _pointHistory[currentIndex] = latestPoint;
        }
    }

    /// @notice Defensive set of conditions that may not all be necessary but prevent edge cases
    /// In particular same block changes, or alterations of locks and points that are not supported
    /// by the wider system (such as increasing a lock that has already started).
    /// @dev These can be removed if the system is well understood and the edge cases are not a concern.
    function validateLockedBalances(
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) public view returns (bool) {
        // While this blocks changing the time of the lock, changing the time is not supported.
        if (_newLocked.amount == _oldLocked.amount) revert SameDepositsNotSupported();

        // cannot write a new lock before the old
        if (_newLocked.start < _oldLocked.start) revert WriteToPastNotSupported();

        // empty locks on both sides are not supported
        if (_oldLocked.amount == 0 && _newLocked.amount == 0) revert ZeroDepositsNotSupported();

        // We do not support increasing a lock in progress
        bool isIncreasing = _newLocked.amount > _oldLocked.amount && _oldLocked.amount != 0;
        if (isIncreasing) revert IncreaseNotSupported();

        // We do not support making a scheduled change for an existing lock
        if (_oldLocked.amount > 0 && _newLocked.start > block.timestamp) {
            revert ScheduledAdjustmentsNotSupported();
        }

        // Currently deposits must be scheduled
        if (_oldLocked.amount == 0 && _newLocked.start < block.timestamp) {
            revert OnlyScheduledDeposits();
        }
        // revert if at exactly the cp boundary
        // strictly speaking not neccessary but adviseable so that supply changes + schedulling changes
        // are less prone to manipulation
        if (IClock(clock).elapsedInEpoch() == 0) revert Wait1Second();

        return true;
    }

    /// @notice Record per-user data to checkpoints. Used by VotingEscrow system.
    /// @param _tokenId NFT token ID.
    /// @param _lock The new locked balance and start time.
    /// @dev The lock start can only be adjusted before the lock has started.
    function _tokenCheckpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _lock
    ) internal returns (TokenPoint memory oldPoint, TokenPoint memory newPoint) {
        uint lockAmount = _lock.amount;
        uint lockStart = _lock.start;

        // lock start is frozen once it starts -
        // so write to the future if schedulling a deposit
        // else write to the current block timestamp
        newPoint.checkpointTs = block.timestamp < lockStart
            ? uint128(lockStart)
            : uint128(block.timestamp);

        // the writtenTs serves as a reference and is used for warmups and cooldowns
        newPoint.writtenTs = uint128(block.timestamp);

        // get the old point if it exists
        uint256 tokenInterval = tokenPointIntervals[_tokenId];
        oldPoint = _tokenPointHistory[_tokenId][tokenInterval];

        // we can't write checkpoints out of order as it would interfere with searching
        if (oldPoint.checkpointTs > newPoint.checkpointTs) revert InvalidCheckpoint();

        if (lockAmount > 0) {
            int256[3] memory coefficients = _getCoefficients(lockAmount);

            // fetch the elapsed time since the lock has started
            // we rely on start date not being changeable if it's passed
            uint elapsed = boundedTimeSinceLockStart(lockStart, block.timestamp);

            // If the lock has started, just write the initial amount
            // else evaluate the bias based on the elapsed time
            // and the coefficients computed from the lock amount
            newPoint.coefficients[0] = elapsed == 0
                ? coefficients[0]
                : _getBiasUnbound(elapsed, coefficients);
            newPoint.coefficients[1] = coefficients[1];
        }

        // if we're writing to a new point, increment the interval
        if (oldPoint.checkpointTs != newPoint.checkpointTs) {
            tokenPointIntervals[_tokenId] = ++tokenInterval;
        }

        // Record the new point (or overwrite the old one)
        _tokenPointHistory[_tokenId][tokenInterval] = newPoint;

        return (oldPoint, newPoint);
    }
    /// @dev Writes future changes to the schedulling system. Old points that have yet to be written are replaced.
    /// @param _oldPoint The old point to be replaced, if it exists
    /// @param _newPoint The new point to be written, should always exist
    /// @param _oldLocked The old locked balance and amount, if it exists
    /// @param _newLocked The new locked balance and amount
    /// @dev We assume the calling function has correctly matched and valdated the old and new points and locks
    function _scheduleCurveChanges(
        TokenPoint memory _oldPoint,
        TokenPoint memory _newPoint,
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) internal {
        // check if there is any old schedule
        bool existingLock = _oldLocked.amount > 0;
        uint48 max = uint48(_maxTime());

        // if so we have to remove it
        if (existingLock) {
            // cannot change the start date of an existing lock once it's passed
            if (_oldLocked.start != _newLocked.start && block.timestamp >= _oldLocked.start) {
                revert RetroactiveStartChange();
            }

            // first determine where we are relative to the old lock
            uint48 originalStart = _oldLocked.start;
            uint48 originalMax = originalStart + max;

            // if before the start we need to remove the scheduled curve changes
            // strict equality is crucial as we will apply any immediate changes
            // directly to the global point in later functions
            if (block.timestamp < originalStart) {
                _scheduledCurveChanges[originalStart][0] -= _oldPoint.coefficients[0];
                _scheduledCurveChanges[originalStart][1] -= _oldPoint.coefficients[1];
            }

            // If we're not yet at max, also remove the scheduled decrease
            if (block.timestamp < originalMax) {
                _scheduledCurveChanges[originalMax][1] += _oldPoint.coefficients[1];
            }
        }

        // next we apply the scheduling changes - same process in reverse
        uint48 newStart = _newLocked.start;
        uint48 newMax = newStart + max;

        // if before the start we need to add the scheduled changes
        if (block.timestamp < newStart) {
            _scheduledCurveChanges[newStart][0] += _newPoint.coefficients[0];
            _scheduledCurveChanges[newStart][1] += _newPoint.coefficients[1];

            // write the point where the populate history function should start tracking data from
            // technically speaking we should check if the old point needs to be moved forward
            // In practice this is unlikely to make much of a difference other than having some zero points
            if (_earliestScheduledChange == 0 || newStart < _earliestScheduledChange) {
                _earliestScheduledChange = newStart;
            }
        }

        // If we're not yet at max, also add the scheduled decrease to the slope
        if (block.timestamp < newMax) {
            _scheduledCurveChanges[newMax][1] -= _newPoint.coefficients[1];
        }
    }

    /// @dev Fetches the latest global point from history or writes the first point if the earliest scheduled change has elapsed
    /// @return latestPoint This will either be the latest point in history, a new, empty point if no scheduled changes have elapsed, or the first scheduled change
    /// @return latestIndex The index of the latest point in history, or nothing if there is no history
    function _getLatestGlobalPointOrWriteFirstPoint()
        internal
        returns (GlobalPoint memory latestPoint, uint256 latestIndex)
    {
        uint index = _latestPointIndex;
        if (index > 0) return (_pointHistory[index], index);

        // check if a scheduled write has been set and has elapsed
        uint48 earliestTs = _earliestScheduledChange;
        bool firstScheduledWrite = earliestTs > 0 && earliestTs <= block.timestamp;

        // if we have a scheduled point: write the first point to storage @ index 1
        if (firstScheduledWrite) {
            latestPoint.ts = earliestTs;
            latestPoint.coefficients[0] = _scheduledCurveChanges[earliestTs][0];
            latestPoint.coefficients[1] = _scheduledCurveChanges[earliestTs][1];

            index = 1;
            _latestPointIndex = 1;
            _pointHistory[1] = latestPoint;
        }
        // otherwise point is empty but up to date w. no index
        else {
            latestPoint.ts = block.timestamp;
        }

        return (latestPoint, index);
    }

    /// @dev Backfills total supply history up to the present based on elapsed scheduled changes.
    /// Minimum weekly intervals to avoid a sparse array that cannot be binary searched.
    /// @return latestPoint The most recent global state checkpoint
    /// @return currentIndex Latest index + intervals iterated over since last state write
    /// @dev if there is nothing will return the empty point @ now w. index = 0
    function _populateHistory()
        internal
        returns (GlobalPoint memory latestPoint, uint256 currentIndex)
    {
        // fetch the latest point or write the first one if needed
        (latestPoint, currentIndex) = _getLatestGlobalPointOrWriteFirstPoint();

        uint48 latestCheckpoint = uint48(latestPoint.ts);
        uint48 interval = uint48(IClock(clock).checkpointInterval());

        // skip the loop if the latest point is up to date
        if (latestPoint.ts != block.timestamp) {
            // round down to floor so we align with schedulling checkpoints
            uint48 t_i = (latestCheckpoint / interval) * interval;

            for (uint256 i = 0; i < 255; ++i) {
                // first interval is always the next one after the last checkpoint
                // so we double count mid week writes in the past
                t_i += interval;

                // bound to the present
                if (t_i > block.timestamp) t_i = uint48(block.timestamp);

                // fetch the changes for this interval
                int biasChange = _scheduledCurveChanges[t_i][0];
                int slopeChange = _scheduledCurveChanges[t_i][1];

                // we create a new "curve" by defining the coefficients starting from time t_i
                // our constant is the y intercept at t_i and is found by evalutating the curve between the last point and t_i
                latestPoint.coefficients[0] =
                    _getBiasUnbound(t_i - latestPoint.ts, latestPoint.coefficients) +
                    biasChange;

                // here we add the changes to the slope which can be applied next period
                // this can be positive or negative depending on if new deposits outweigh tapering effects + withdrawals
                latestPoint.coefficients[1] += slopeChange;

                // neither of these should happen
                if (latestPoint.coefficients[1] < 0) latestPoint.coefficients[1] = 0;
                if (latestPoint.coefficients[0] < 0) latestPoint.coefficients[0] = 0;

                latestPoint.ts = t_i;
                currentIndex++;

                // if we are exactly on the boundary we don't write yet
                // this means we can add the token-contribution later
                if (t_i == block.timestamp) {
                    break;
                } else {
                    _pointHistory[currentIndex] = latestPoint;
                }
            }
        }

        return (latestPoint, currentIndex);
    }

    /// @dev Under the assumption that the prior global state is updated up until t == block.timestamp
    /// then apply the incremental changes from the token point
    /// @param _oldPoint The old token point in case we are updating
    /// @param _newPoint The new token point to be written
    /// @param _latestGlobalPoint The latest global point in memory
    /// @return The updated global point with the new token point applied
    function _applyTokenUpdateToGlobal(
        uint48 lockStart,
        TokenPoint memory _oldPoint,
        TokenPoint memory _newPoint,
        GlobalPoint memory _latestGlobalPoint
    ) internal view returns (GlobalPoint memory) {
        if (_newPoint.checkpointTs != block.timestamp) revert TokenPointNotUpToDate();
        if (_latestGlobalPoint.ts != block.timestamp) revert GlobalPointNotUpToDate();

        // evaluate the old curve up until now if exists and remove its impact from the bias
        if (_oldPoint.checkpointTs != 0) {
            uint48 elapsed = boundedTimeSinceCheckpoint(
                lockStart,
                _oldPoint.checkpointTs,
                block.timestamp
            ).toUint48();

            int256 oldUserBias = _getBiasUnbound(elapsed, _oldPoint.coefficients);
            _latestGlobalPoint.coefficients[0] -= oldUserBias;
        }

        // if the new point is not an exit, then add it to global state
        if (_newPoint.coefficients[0] > 0) {
            _latestGlobalPoint.coefficients[0] += _newPoint.coefficients[0];
        }

        // the immediate reduction is slope requires removing the old and adding the new
        // only needs to be done if lock has started and we are still accumulating voting power
        if (lockStart <= block.timestamp && block.timestamp - lockStart <= _maxTime()) {
            _latestGlobalPoint.coefficients[1] -= _oldPoint.coefficients[1];
            _latestGlobalPoint.coefficients[1] += _newPoint.coefficients[1];
        }

        // these should never be negative
        if (_latestGlobalPoint.coefficients[0] < 0) _latestGlobalPoint.coefficients[0] = 0;
        if (_latestGlobalPoint.coefficients[1] < 0) _latestGlobalPoint.coefficients[1] = 0;

        return _latestGlobalPoint;
    }

    /*//////////////////////////////////////////////////////////////
			CHECKPOINT TIME FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets the number of seconds since the lock has started, bounded by the maximum time.
    /// @param _start The start time of the lock.
    /// @param _timestamp The timestamp to evaluate over
    function boundedTimeSinceLockStart(
        uint256 _start,
        uint256 _timestamp
    ) public view returns (uint256) {
        if (_timestamp < _start) return 0;

        uint256 rawElapsed = _timestamp - _start;
        uint256 max = _maxTime();

        if (rawElapsed > max) return max;
        else return rawElapsed;
    }

    /// @dev Ensure that when writing multiple points, we don't violate the invariant that no lock
    /// can accumulate more than the maxTime amount of voting power.
    /// @dev We assume Lock start dates cannot be retroactively changed
    /// @param _start The start of the original lock.
    /// @param _checkpointTs The timestamp of the checkPoint.
    /// @param _timestamp The timestamp to evaluate over.
    /// @return The total time elapsed since the checkpoint,
    /// accounting for the original start date and the maximum.
    function boundedTimeSinceCheckpoint(
        uint256 _start,
        uint128 _checkpointTs,
        uint256 _timestamp
    ) public view returns (uint256) {
        if (_checkpointTs < _start) revert InvalidCheckpoint();

        // if the original lock or the checkpoint haven't started, return 0
        if (_timestamp < _start || _timestamp < _checkpointTs) return 0;

        // calculate the max possible time based on the lock start
        uint256 max = _maxTime();
        uint256 maxPossibleTs = _start + max;

        // bound the checkpoint to the max possible time
        // and the current timestamp to the max possible time
        uint256 effectiveCheckpoint = _checkpointTs > maxPossibleTs ? maxPossibleTs : _checkpointTs;
        uint256 effectiveTimestamp = _timestamp > maxPossibleTs ? maxPossibleTs : _timestamp;

        return effectiveTimestamp - effectiveCheckpoint;
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
    function _authorizeUpgrade(address) internal virtual override auth(CURVE_ADMIN_ROLE) {}

    /// @dev gap for upgradeable contract
    uint256[45] private __gap;
}
