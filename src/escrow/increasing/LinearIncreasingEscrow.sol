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

    uint256 private _latestPointIndex;

    mapping(uint48 => int256[3]) internal _scheduledCurveChanges;

    function pointHistory(uint256 _loc) external view returns (GlobalPoint memory) {
        return _pointHistory[_loc];
    }

    function scheduledCurveChanges(uint48 _at) external view returns (int256[3] memory) {
        return _scheduledCurveChanges[_at];
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

    function _getBias(
        uint256 timeElapsed,
        int256[3] memory coefficients
    ) internal view returns (uint256) {
        int256 linear = coefficients[1];
        int256 const = coefficients[0];

        // bound the time elapsed to the maximum time

        uint256 MAX_TIME = _maxTime();
        timeElapsed = timeElapsed > MAX_TIME ? MAX_TIME : timeElapsed;

        // convert the time to fixed point
        int256 t = SignedFixedPointMath.toFP(timeElapsed.toInt256());

        int256 bias = linear.mul(t).add(const);

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
    function checkpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) external nonReentrant {
        if (msg.sender != escrow) revert OnlyEscrow();
        _checkpoint(_tokenId, _oldLocked, _newLocked);
    }

    function _checkpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) internal {
        if (_tokenId == 0) revert InvalidTokenId();
        if (!validateLockedBalances(_oldLocked, _newLocked)) revert("Invalid Locked Balances");

        // write the token checkpoint
        (TokenPoint memory oldTokenPoint, TokenPoint memory newTokenPoint) = _tokenCheckpoint(
            _tokenId,
            _oldLocked,
            _newLocked
        );

        // update our schedules
        _scheduleCurveChanges(oldTokenPoint, newTokenPoint, _oldLocked, _newLocked);

        // backpop the history
        (GlobalPoint memory latestPoint, uint256 latestIndex) = _populateHistory();

        // update with the latest token point
        // this only should happen with a decrease because we don't currently support increases
        // if we wrote into the future, we don't need to update the current state as hasn't taken place yet
        if (newTokenPoint.checkpointTs == latestPoint.ts) {
            latestPoint = _applyTokenUpdateToGlobal(oldTokenPoint, newTokenPoint, latestPoint);
            // write the new global point
            _writeNewGlobalPoint(latestPoint, latestIndex);
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

            // TODO: being extra safe we could check the old point has data
            // but that should never happen.

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
        }

        // If we're not yet at max, also add the scheduled decrease
        // (i.e. decrease the slope)
        if (block.timestamp < newMax) {
            _scheduledCurveChanges[newMax][1] -= _newPoint.coefficients[1];
        }
    }

    // fetch our latest global point
    // in the base case initialise from zero but set the timestamp to the current block time
    function getLatestGlobalPoint() public view returns (GlobalPoint memory latestPoint) {
        if (_latestPointIndex == 0) {
            latestPoint.ts = uint48(block.timestamp);
            return latestPoint;
        } else {
            return _pointHistory[_latestPointIndex];
        }
    }

    /// @dev iterates over the interval and looks for scheduled changes that have elapsed
    ///
    function _populateHistory() internal returns (GlobalPoint memory, uint256) {
        GlobalPoint memory latestPoint = getLatestGlobalPoint();

        uint48 interval = uint48(IClock(clock).checkpointInterval());
        uint48 latestCheckpoint = uint48(latestPoint.ts);
        uint currentIndex = _latestPointIndex;

        {
            // step 1: round down to floor of interval
            uint48 t_i = (latestCheckpoint / interval) * interval;

            console.log("t_i", t_i);

            for (uint256 i = 0; i < 255; ++i) {
                // step 2: the first interval is always the next one after the last checkpoint
                t_i += interval;

                console.log("t_i + interval", t_i);

                // bound to at least the present
                if (t_i > block.timestamp) t_i = uint48(block.timestamp);

                console.log("bound t_i", t_i);

                // fetch the changes for this interval
                int biasChange = _scheduledCurveChanges[t_i][0];
                int slopeChange = _scheduledCurveChanges[t_i][1];

                console.log("biasChange", biasChange);
                console.log("slopeChange", slopeChange);

                // we create a new "curve" by defining the coefficients starting from time t_i
                // our constant is the y intercept at t_i and is found by evalutating the curve between the last point and t_i
                // todo safe casting
                latestPoint.coefficients[0] =
                    int256(_getBias(t_i - latestPoint.ts, latestPoint.coefficients)) +
                    biasChange;

                // here we add the net result of the coefficient changes to the slope
                // which can be applied for the ensuring period
                // this can be positive or negative depending on if new deposits outweigh tapering effects + withdrawals
                latestPoint.coefficients[1] += slopeChange;

                // the slope itself can't be < 0 so we bound it
                if (latestPoint.coefficients[1] < 0) {
                    latestPoint.coefficients[1] = 0;
                    revert("ahhhh sheeeet");
                }

                // if the bias is negativo we also should bound it
                if (latestPoint.coefficients[0] < 0) {
                    // think this is redundant as bias checks for this
                    latestPoint.coefficients[0] = 0;
                }

                // update the timestamp ahead of either breaking or the next iteration
                latestPoint.ts = t_i;
                currentIndex++;

                bool hasScheduledChange = (biasChange != 0 || slopeChange != 0);

                // write the point to storage if there are changes, otherwise continue
                // interpolating in memory and can write to storage at the end
                // otherwise we haven't reached an interval and so can just return the point
                if (t_i == block.timestamp) break;
                else if (hasScheduledChange) _pointHistory[currentIndex] = latestPoint;
            }
        }

        return (latestPoint, currentIndex);
    }

    function _applyTokenUpdateToGlobal(
        TokenPoint memory _oldPoint,
        TokenPoint memory _newPoint,
        GlobalPoint memory _latestPoint
    ) internal view returns (GlobalPoint memory) {
        // here we are changing the voting power immediately.
        // in the schedulling function, we have already diffed the scheduled changes

        // should never happen that the checkpoint is in the future
        // this should be handled by scheulling function
        if (_newPoint.checkpointTs > block.timestamp) revert("removing in the future");

        // meaning we just, now need to write the update
        // The curve should be backfilled up to the present
        if (_latestPoint.ts != block.timestamp) revert("point not up to date");

        // evaluate the old curve up until now
        uint256 timeElapsed = block.timestamp - _oldPoint.checkpointTs;
        uint256 oldUserBias = _getBias(timeElapsed, _oldPoint.coefficients);

        // Subtract the old user's bias from the global bias at this point
        _latestPoint.coefficients[0] -= int256(oldUserBias);

        // User is reducing, not exiting
        if (_newPoint.bias > 0) {
            // Add the new user's bias back to the global bias
            _latestPoint.coefficients[0] += int256(_newPoint.bias);
        }

        // the immediate reduction is slope requires removing the old and adding the new
        _latestPoint.coefficients[1] -= _oldPoint.coefficients[1];
        _latestPoint.coefficients[1] += _newPoint.coefficients[1];

        return _latestPoint;
    }

    /// @dev Writes or overwrites the latest global point into storage at the index
    /// @param _latestPoint The latest global point to write.
    /// @param _index The returned index following the history backpop loop.
    /// @dev Begins at 1 as corresponds to length of the pseudo-array.
    function _writeNewGlobalPoint(GlobalPoint memory _latestPoint, uint256 _index) internal {
        // Missing global checkpoints in prior weeks. In this case, _index = index + x, where x > 1
        // TODO: doesn't look like that's the case here
        // No missing global checkpoints, but timestamp != block.timestamp. Create new checkpoint.
        // No missing global checkpoints, but timestamp == block.timestamp. Overwrite _latest checkpoint.
        if (_index != 1 && _pointHistory[_index - 1].ts == block.timestamp) {
            // overwrite the current index, given that the passed one will be the i+1
            _pointHistory[_index - 1] = _latestPoint;
        } else {
            // first point or a new point
            _latestPointIndex = _index;
            _pointHistory[_index] = _latestPoint;
        }
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
