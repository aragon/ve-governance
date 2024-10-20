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
    /// This implementation means that very short intervals may be challenging
    mapping(uint256 => TokenPoint[1_000_000_000]) internal _tokenPointHistory;

    /// ADDED v0.1.1

    mapping(uint => GlobalPoint) internal _pointHistory;

    uint256 internal _latestPointIndex;

    // changes are stored in fixed point
    mapping(uint48 => int256[3]) internal _scheduledCurveChanges;

    uint48 internal _earliestScheduledChange;

    /// @notice emulation of array like structure starting at 1 index for global points
    function pointHistory(uint256 _index) external view returns (GlobalPoint memory) {
        return _pointHistory[_index];
    }

    function scheduledCurveChanges(uint48 _at) external view returns (int256[3] memory) {
        return [
            SignedFixedPointMath.fromFP(_scheduledCurveChanges[_at][0]),
            SignedFixedPointMath.fromFP(_scheduledCurveChanges[_at][1]),
            0
        ];
    }

    function latestPointIndex() external view returns (uint) {
        return _latestPointIndex;
    }

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

    /// @dev returns the bias ignoring negative values and not converting from fp
    function _getBiasUnbound(
        uint256 timeElapsed,
        int256[3] memory coefficients
    ) internal view returns (int256) {
        int256 linear = coefficients[1];
        int256 const = coefficients[0];

        // bound the time elapsed to the maximum time
        uint256 MAX_TIME = _maxTime();
        timeElapsed = timeElapsed > MAX_TIME ? MAX_TIME : timeElapsed;

        // convert the time to fixed point
        int256 t = SignedFixedPointMath.toFP(timeElapsed.toInt256());

        int256 bias = linear.mul(t).add(const);

        return bias;
    }

    function _getBias(
        uint256 timeElapsed,
        int256[3] memory coefficients
    ) internal view returns (uint256) {
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

    function setWarmupPeriod(uint48 _warmupPeriod) external auth(CURVE_ADMIN_ROLE) {
        warmupPeriod = _warmupPeriod;
        emit WarmupSet(_warmupPeriod);
    }

    /// @notice Returns whether the NFT is warm
    function isWarm(uint256 tokenId) public view returns (bool) {
        uint256 interval = _getPastTokenPointInterval(tokenId, block.timestamp);
        TokenPoint memory point = _tokenPointHistory[tokenId][interval];
        if (point.bias == 0) return false;
        else return _isWarm(point);
    }

    function _isWarm(TokenPoint memory _point) public view returns (bool) {
        // BUG: should only be for the first point unless that's expected behaviour
        return block.timestamp > _point.writtenTs + warmupPeriod;
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
        // this means that the first epoch has yet to start
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

    function votingPowerAt(uint256 _tokenId, uint256 _t) external view returns (uint256) {
        uint256 interval = _getPastTokenPointInterval(_tokenId, _t);

        // epoch 0 is an empty point
        if (interval == 0) return 0;
        TokenPoint memory lastPoint = _tokenPointHistory[_tokenId][interval];

        if (!_isWarm(lastPoint)) return 0;
        // TODO: BUG - if you have multiple points > 0, you won't accurately sync
        // from the start of the lock. You need to fetch escrow.locked(tokenId).start
        // and use that as the elapsed time for the max
        uint256 timeElapsed = _t - lastPoint.checkpointTs;

        // the bias here is converted from fixed point
        return _getBias(timeElapsed, lastPoint.coefficients);
    }

    /// @notice [NOT IMPLEMENTED] Calculate total voting power at some point in the past
    /// @dev This function will be implemented in a future version of the contract
    function supplyAt(uint256) external pure returns (uint256) {
        revert("Supply Not Implemented");
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
    // TODO test this
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
        // write the token checkpoint
        (TokenPoint memory oldTokenPoint, TokenPoint memory newTokenPoint) = _tokenCheckpoint(
            _tokenId,
            _oldLocked,
            _newLocked
        );

        // update our schedules
        _scheduleCurveChanges(oldTokenPoint, newTokenPoint, _oldLocked, _newLocked);

        // if we need to: update the global state
        // this will also write the first point if the earliest scheduled change has elapsed
        (GlobalPoint memory latestPoint, uint256 currentIndex) = _populateHistory();

        // update the global with the latest token point
        // it may be the case that the token is writing a scheduled change in which case there is no
        // incremental change to the global state
        bool tokenHasUpdateNow = newTokenPoint.checkpointTs == latestPoint.ts;
        if (tokenHasUpdateNow) {
            latestPoint = _applyTokenUpdateToGlobal(
                _newLocked.start, // TODO
                oldTokenPoint,
                newTokenPoint,
                latestPoint
            );
        }

        // if the currentIndex is unchanged, this means no extra state has been written globally
        // so no need to write if there are no changes from token + schedule
        if (currentIndex != _latestPointIndex || tokenHasUpdateNow) {
            // index starts at 1 - so if there is an update we need to add it
            _latestPointIndex = currentIndex == 0 ? 1 : currentIndex;
            _pointHistory[currentIndex] = latestPoint;
        }
    }

    function validateLockedBalances(
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) public view returns (bool) {
        if (_newLocked.amount == _oldLocked.amount) revert SameDepositsNotSupported();
        if (_newLocked.start < _oldLocked.start) revert WriteToPastNotSupported();
        if (_oldLocked.amount == 0 && _newLocked.amount == 0) revert ZeroDepositsNotSupported();
        bool isIncreasing = _newLocked.amount > _oldLocked.amount && _oldLocked.amount != 0;
        if (isIncreasing) revert IncreaseNotSupported();
        if (_oldLocked.amount > 0 && _newLocked.start > block.timestamp) {
            revert ScheduledAdjustmentsNotSupported();
        }
        if (_oldLocked.amount == 0 && _newLocked.start < block.timestamp) {
            revert("No front running");
        }
        // revert if at exactly the cp boundary
        // strictly speaking not neccessary but adviseable so that supply changes + schedulling changes
        // are less prone to manipulation
        if (IClock(clock).elapsedInEpoch() == 0) revert("Wait 1 second");

        return true;
    }

    /// @notice Record per-user data to checkpoints. Used by VotingEscrow system.
    /// @dev Curve finance style but just for users at this stage
    /// @param _tokenId NFT token ID.
    /// @param _newLocked New locked amount / end lock time for the tokenid
    function _tokenCheckpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory /*_oldLocked */,
        IVotingEscrow.LockedBalance memory _newLocked
    ) internal returns (TokenPoint memory oldPoint, TokenPoint memory newPoint) {
        uint newAmount = _newLocked.amount;
        uint newStart = _newLocked.start;

        // in increasing curve, for new amounts we schedule the voting power
        // to be created at the next checkpoint, this is not enforced in this function
        // the writtenTs is used for warmups, cooldowns and for logging
        // safe to cast as .start is 48 bit unsigned
        newPoint.checkpointTs = uint128(newStart);
        newPoint.writtenTs = uint128(block.timestamp);

        // get the old point if it exists
        uint256 tokenInterval = tokenPointIntervals[_tokenId];
        oldPoint = _tokenPointHistory[_tokenId][tokenInterval];

        // we can't write checkpoints out of order as it would interfere with searching
        if (oldPoint.checkpointTs > newPoint.checkpointTs) revert InvalidCheckpoint();

        // for all locks other than amount == 0 (an exit)
        // we need to compute the coefficients and the bias
        if (newAmount > 0) {
            int256[3] memory coefficients = _getCoefficients(newAmount);

            // If the lock hasn't started, we use the base value for the bias
            uint elapsed = newStart >= block.timestamp ? 0 : block.timestamp - newStart;

            newPoint.coefficients = coefficients;
            // this bias is stored having been converted from fixed point
            // be mindful about converting back
            newPoint.bias = _getBias(elapsed, coefficients);
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

        // max time is set during contract deploy, if its > uint48 someone didn't test properly
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

            // if before the start we need to remove the scheduled slope increase
            // and the scheduled bias increase
            // strict equality is crucial as we will apply any immediate changes
            // directly to the global point in later functions
            if (block.timestamp < originalStart) {
                _scheduledCurveChanges[originalStart][0] -= _oldPoint.coefficients[0];
                _scheduledCurveChanges[originalStart][1] -= _oldPoint.coefficients[1];
            }

            // If we're not yet at max, also remove the scheduled decrease
            // (i.e. increase the slope)
            if (block.timestamp < originalMax) {
                _scheduledCurveChanges[originalMax][1] += _oldPoint.coefficients[1];
            }
        }

        // next we apply the scheduling changes - same process in reverse
        uint48 newStart = _newLocked.start;
        uint48 newMax = newStart + max;

        // if before the start we need to add the scheduled slope increase
        // and the scheduled bias increase
        // strict equality is crucial as we will apply any immediate changes
        // directly to the global point in later functions
        if (block.timestamp < newStart) {
            // directly to the global point in later functions if (block.timestamp < newStart) {
            _scheduledCurveChanges[newStart][0] += _newPoint.coefficients[0];
            _scheduledCurveChanges[newStart][1] += _newPoint.coefficients[1];

            // write the point where the populate history function should start tracking data from
            // technically speaking we should check if the old point needs to be moved forward
            // if all the coefficients are zero. In practice this is unlikely to make much of a difference.
            // unless someone is able to grief by locking very early then removing to much later.
            if (_earliestScheduledChange == 0 || newStart < _earliestScheduledChange) {
                _earliestScheduledChange = newStart;
            }
        }

        // If we're not yet at max, also add the scheduled decrease
        // (i.e. decrease the slope)
        if (block.timestamp < newMax) {
            _scheduledCurveChanges[newMax][1] -= _newPoint.coefficients[1];
        }
    }

    /// @dev Fetches the latest global point from history or writes the first point if the earliest scheduled change has elapsed
    /// @return latestPoint This will either be the latest point in history, a new, empty point if no scheduled changes have elapsed, or the first scheduled change
    /// if the earliest scheduled change has elapsed
    function _getLatestGlobalPointOrWriteFirstPoint()
        internal
        returns (GlobalPoint memory latestPoint)
    {
        // early return the point if we have it
        uint index = _latestPointIndex;
        if (index > 0) return _pointHistory[index];

        // determine if we have some existing state we need to start from
        uint48 earliestTs = _earliestScheduledChange;
        bool firstScheduledWrite = index == 0 && // if index == 1, we've got at least one point in history already
            // earliest TS must have been set
            earliestTs > 0 &&
            // the earliest scheduled change must have elapsed
            earliestTs <= block.timestamp;

        // write the first point and return it
        if (firstScheduledWrite) {
            latestPoint.ts = earliestTs;
            latestPoint.coefficients[0] = _scheduledCurveChanges[earliestTs][0];
            latestPoint.coefficients[1] = _scheduledCurveChanges[earliestTs][1];

            // write operations to storage
            _latestPointIndex = 1;
            _pointHistory[1] = latestPoint;
        }
        // otherwise return an empty point at the current ts
        else {
            latestPoint.ts = block.timestamp;
        }

        return latestPoint;
    }

    /// @dev Backfills total supply history up to the present based on elapsed scheduled changes
    /// @dev Will write to storage if there are changes in the past, otherwise will keep the array sparse to save gas
    /// @return latestPoint The most recent global state checkpoint in memory. This point is not yet written to storage in case of token-level updates
    /// @return currentIndex Latest index + intervals iterated over since last state write
    function _populateHistory()
        internal
        returns (GlobalPoint memory latestPoint, uint256 currentIndex)
    {
        // fetch the latest point or write the first one if needed
        latestPoint = _getLatestGlobalPointOrWriteFirstPoint();

        // needs to go after writing the point
        currentIndex = _latestPointIndex;
        uint48 latestCheckpoint = uint48(latestPoint.ts);
        uint48 interval = uint48(IClock(clock).checkpointInterval());

        // if we are at the block timestamp with the latest point, history has already been written
        bool latestPointUpToDate = latestPoint.ts == block.timestamp;

        if (!latestPointUpToDate) {
            // step 1: round down to floor of interval ensures we align with schedulling
            uint48 t_i = (latestCheckpoint / interval) * interval;

            for (uint256 i = 0; i < 255; ++i) {
                // step 2: the first interval is always the next one after the last checkpoint
                t_i += interval;

                // bound to at least the present
                if (t_i > block.timestamp) t_i = uint48(block.timestamp);

                // fetch the changes for this interval
                int biasChange = _scheduledCurveChanges[t_i][0];
                int slopeChange = _scheduledCurveChanges[t_i][1];

                console.log("biasChange", biasChange / 1e18);
                console.log("slopeChange", slopeChange / 1e18);
                console.log("idx number", currentIndex);
                console.log("prev-coeff", latestPoint.coefficients[0] / 1e36);
                console.log("prev-slope", latestPoint.coefficients[1] / 1e18);

                // we create a new "curve" by defining the coefficients starting from time t_i
                // our constant is the y intercept at t_i and is found by evalutating the curve between the last point and t_i
                latestPoint.coefficients[0] =
                    _getBiasUnbound(t_i - latestPoint.ts, latestPoint.coefficients) +
                    biasChange;

                // here we add the net result of the coefficient changes to the slope
                // which can be applied for the ensuring period
                // this can be positive or negative depending on if new deposits outweigh tapering effects + withdrawals
                latestPoint.coefficients[1] += slopeChange;

                console.log("new coeff", latestPoint.coefficients[0] / 1e36);
                console.log("new slope", latestPoint.coefficients[1] / 1e18);

                console.log("");

                // the slope itself can't be < 0 so we bound it
                if (latestPoint.coefficients[1] < 0) {
                    latestPoint.coefficients[1] = 0;
                    // TODO test this and below
                    revert("ahhhh sheeeet");
                }

                // if the bias is negative we also should bound it, although should not happen
                if (latestPoint.coefficients[0] < 0) {
                    latestPoint.coefficients[0] = 0;
                }

                // update the timestamp ahead of either breaking or the next iteration
                latestPoint.ts = t_i;
                currentIndex++;
                bool hasScheduledChange = (biasChange != 0 || slopeChange != 0);
                // write the point to storage if there are changes, otherwise continue
                // interpolating in memory and can write to storage at the end
                // otherwise we are as far as we can go so we break
                if (t_i == block.timestamp) {
                    break;
                }
                // note: if we are exactly on the boundary we don't write yet
                // this means we can add the token-contribution later
                else if (hasScheduledChange) {
                    _pointHistory[currentIndex] = latestPoint;
                }
            }
        }

        // issue here is that this will always return a new index if called mid interval
        // meaning we will always write a new point even if there is no change that couldn't
        // have been interpolated
        console.log("returning currentIndex", currentIndex);
        return (latestPoint, currentIndex);
    }

    /// @dev Under the assumption that the prior global state is updated up until t == block.timestamp
    /// then apply the incremental changes from the token point
    /// @param _oldPoint The old token point in case we are updating
    /// @param _newPoint The new token point to be written
    /// @param _latestGlobalPoint The latest global point in memory
    /// @return The updated global point with the new token point applied
    function _applyTokenUpdateToGlobal(
        uint lockStart,
        TokenPoint memory _oldPoint,
        TokenPoint memory _newPoint,
        GlobalPoint memory _latestGlobalPoint
    ) internal view returns (GlobalPoint memory) {
        if (_newPoint.checkpointTs != block.timestamp) revert("token point not up to date");
        if (_latestGlobalPoint.ts != block.timestamp) revert("global point not up to date");

        // if there is something to be replaced (old point has data)
        uint oldCp = _oldPoint.checkpointTs;
        uint elapsed = 0;
        if (oldCp != 0 && block.timestamp > oldCp) {
            elapsed = block.timestamp - oldCp;
        }

        // evaluate the old curve up until now and remove its impact from the bias
        // TODO bounding to zero
        int256 oldUserBias = _getBiasUnbound(elapsed, _oldPoint.coefficients);
        console.log("Old user bias", oldUserBias);
        _latestGlobalPoint.coefficients[0] -= oldUserBias;

        // if the new point is not an exit, then add it back in
        if (_newPoint.coefficients[0] > 0) {
            // Add the new user's bias back to the global bias
            _latestGlobalPoint.coefficients[0] += int256(_newPoint.coefficients[0]);
        }

        // the immediate reduction is slope requires removing the old and adding the new
        // this could involve zero writes
        _latestGlobalPoint.coefficients[1] -= _oldPoint.coefficients[1];
        _latestGlobalPoint.coefficients[1] += _newPoint.coefficients[1];

        return _latestGlobalPoint;
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
