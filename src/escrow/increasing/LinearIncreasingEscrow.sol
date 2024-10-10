/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotingEscrowIncreasing as IVotingEscrow} from "@escrow-interfaces/IVotingEscrowIncreasing.sol";
import {IEscrowCurveIncreasing as IEscrowCurve} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
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

    mapping(uint => GlobalPoint) private _pointHistory;

    uint256 private _latestPointIndex;

    mapping(uint48 => int256[3]) private _scheduledCurveChanges;

    function pointHistory(uint256 _loc) external view returns (GlobalPoint memory) {
        return _pointHistory[_loc];
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
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
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
        bool isIncreasing = _newLocked.amount > _oldLocked.amount && _oldLocked.amount != 0;
        if (isIncreasing) revert IncreaseNotSupported();
        if (_newLocked.amount == _oldLocked.amount) revert SameDepositsNotSupported();

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
            latestPoint = _applyTokenUpdateToGlobal(
                oldTokenPoint,
                newTokenPoint,
                latestPoint,
                isIncreasing
            );
            // write the new global point
            _writeNewGlobalPoint(latestPoint, latestIndex);
        }
    }

    /// @notice Record gper-user data to checkpoints. Used by VotingEscrow system.
    /// @dev Curve finance style but just for users at this stage
    /// @param _tokenId NFT token ID.
    /// @param _newLocked New locked amount / end lock time for the user
    function _tokenCheckpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) internal returns (TokenPoint memory oldPoint, TokenPoint memory newPoint) {
        // instantiate a new, empty token point
        TokenPoint memory uNew;

        uint amount = _newLocked.amount;

        // while the escrow has no way to decrease, we should adjust this
        bool isExiting = amount == 0;

        if (!isExiting) {
            int256[3] memory coefficients = _getCoefficients(amount);
            // for a new lock, write the base bias (elapsed == 0)
            uNew.coefficients = coefficients;
            uNew.bias = _getBias(0, coefficients);
        }

        // check to see if we have an existing interval for this token
        uint256 tokenInterval = tokenPointIntervals[_tokenId];

        // if we don't have a point, we can write to the first interval
        TokenPoint memory lastPoint;
        if (tokenInterval == 0) {
            tokenPointIntervals[_tokenId] = ++tokenInterval;
        } else {
            lastPoint = _tokenPointHistory[_tokenId][tokenInterval];
            // can't do this: we can only write to same point or future
            if (lastPoint.checkpointTs > uNew.checkpointTs) revert InvalidCheckpoint();
        }

        // This needs careful thought and testing
        // we would need to evaluate the slope and bias based on the change and recompute
        // based on the elapsed time
        // but we need to be hyper-aware as to whether we are reducing NOW
        // or in the futre
        bool isReducing = !isExiting && _newLocked.amount < _oldLocked.amount;
        if (isReducing) {
            // our challenge here is writing a new point if the start date is in the future.
            // say we do a reduction
            if (_newLocked.start > block.timestamp) revert("scheduled reductions unsupported");

            // get the elapsed time
            uint48 elapsed = _newLocked.start - _oldLocked.start;
            int256[3] memory coefficients = _getCoefficients(amount);
            // eval the bias vs the old lock and start the new one
            uNew.coefficients = coefficients;
            uNew.bias = _getBias(elapsed, lastPoint.coefficients);
        }

        // write the new timestamp - in the case of an increasing curve
        // we align the checkpoint to the start of the upcoming deposit interval
        // to ensure global slope changes can be scheduled
        // safe to cast as .start is 48 bit unsigned
        uNew.checkpointTs = uint128(_newLocked.start);

        // log the written ts - this can be used to compute warmups and burn downs
        uNew.writtenTs = block.timestamp.toUint128();

        // if we're writing to a new point, increment the interval
        if (tokenInterval != 0 && lastPoint.checkpointTs != uNew.checkpointTs) {
            tokenPointIntervals[_tokenId] = ++tokenInterval;
        }

        // Record the new point (or overwrite the old one)
        _tokenPointHistory[_tokenId][tokenInterval] = uNew;

        return (lastPoint, uNew);
    }

    // there are 2 cases here:
    // 1. we are increasing or creating a new deposit - in the increasing case this mandates waiting for the next checkpoint so that
    // we can't game the system. The lock starts at the next cp and the scheduled change is written to the max duration
    // 2. we are decreasing or exiting a deposit - in this case we can write the change immediately and fetch the associated scheduled change
    // based on the start of the lock
    // TODO this only works given certain assumptions
    // 1. new deposits cleanly snap to checkpoints in the future
    // 2. if oldLocked.amount < newLockedAmount, we are removing tokens
    // in the event they are the same, this is currently undefined
    function _scheduleCurveChanges(
        TokenPoint memory _oldPoint,
        TokenPoint memory _newPoint,
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) internal {
        if (_newLocked.amount == _oldLocked.amount) revert("same deposits not supported");
        // only fresh meat
        if (_newLocked.amount > _oldLocked.amount && _oldLocked.amount != 0)
            revert("increase not supported");

        // step 1: we need to know if we are increasing or decreasing
        bool isExiting = _newLocked.amount == 0;
        bool isRemoving = isExiting || _newLocked.amount < _oldLocked.amount;

        if (isRemoving) {
            // fetch the original lock start and the max time
            uint48 originalStart = _oldLocked.start;
            uint48 scheduledMax = _newLocked.start + _maxTime().toUint48();

            // if we are past the max time, there's no further curve adjustements as they've already happened
            if (scheduledMax < block.timestamp) {
                return;
            }

            // the scheduled curve change at the max is a decrease
            _scheduledCurveChanges[scheduledMax][1] += _oldPoint.coefficients[1];

            // if the new locked is not zero then we need to make the new adjustment here
            if (!isExiting) {
                _scheduledCurveChanges[scheduledMax][1] -= _newPoint.coefficients[1];
            }

            // if the start date has happened, we are all accounted for
            if (originalStart < block.timestamp) {
                return;
            }

            // else remove the scheduled curve changes and biases
            _scheduledCurveChanges[originalStart][0] -= _oldPoint.coefficients[0]; // this was an increase
            _scheduledCurveChanges[originalStart][1] -= _oldPoint.coefficients[1]; // this was an increase

            // replace with the adjustment
            if (!isExiting) {
                _scheduledCurveChanges[originalStart][0] += _newPoint.coefficients[0];
                _scheduledCurveChanges[originalStart][1] += _newPoint.coefficients[1];
            }
        }
        // this is a new deposit so needs to be scheduled
        else {
            // new locks start in the future, so we schedule the diffs here
            _scheduledCurveChanges[_newLocked.start][0] += _newPoint.coefficients[0];
            _scheduledCurveChanges[_newLocked.start][1] += _newPoint.coefficients[1];

            // write the scheduled coeff reduction at the max duration
            uint48 scheduledMax = _newLocked.start + _maxTime().toUint48();
            _scheduledCurveChanges[scheduledMax][1] -= _newPoint.coefficients[1];
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
    function _populateHistory() internal returns (GlobalPoint memory, uint256 latestIndex) {
        GlobalPoint memory latestPoint = getLatestGlobalPoint();

        uint48 interval = uint48(IClock(clock).checkpointInterval());
        uint48 latestCheckpoint = uint48(latestPoint.ts);
        uint currentIndex = _latestPointIndex;

        {
            // step 1: round down to floor of interval
            uint48 t_i = (latestCheckpoint / interval) * interval;
            for (uint256 i = 0; i < 255; ++i) {
                // step 2: the first interval is always the next one after the last checkpoint
                t_i += interval;

                // bound to at least the present
                if (t_i > block.timestamp) t_i = uint48(block.timestamp);

                // we create a new "curve" by defining the coefficients starting from time t_i

                // our constant is the y intercept at t_i and is found by evalutating the curve between the last point and t_i
                // todo: this aint really a coefficient is it?
                // it's just the bias
                // todo safe casting
                latestPoint.coefficients[0] =
                    // evaluate the bias between the latest point and t_i
                    int256(_getBias(t_i - latestPoint.ts, latestPoint.coefficients)) +
                    // add net scheduled increases
                    _scheduledCurveChanges[t_i][0];

                // here we add the net result of the coefficient changes to the slope
                // this can be positive or negative depending on if new deposits outweigh tapering effects + withdrawals
                latestPoint.coefficients[1] += _scheduledCurveChanges[t_i][1];

                // we create a new "curve" by defining the coefficients starting from time t_i
                latestPoint.ts = t_i;

                // write the point to storage if it's in the past
                // otherwise we haven't reached an interval and so can just return the point
                currentIndex++;
                if (t_i == block.timestamp) break;
                else _pointHistory[currentIndex] = latestPoint;
            }
        }

        return (latestPoint, currentIndex);
    }

    function _applyTokenUpdateToGlobal(
        TokenPoint memory _oldPoint,
        TokenPoint memory _newPoint,
        GlobalPoint memory _latestPoint,
        bool isIncreasing
    ) internal view returns (GlobalPoint memory) {
        // here we are changing the voting power immediately.
        // in the schedulling function, we have already diffed the scheduled changes

        // we don't support increasing
        if (isIncreasing) revert("Increasing unsupported");

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

    function _writeNewGlobalPoint(GlobalPoint memory _latestPoint, uint256 _index) internal {
        // If timestamp of latest global point is the same, overwrite the latest global point
        // Else record the new global point into history
        // Exclude index 0 (note: _index is always >= 1, see above)
        // Two possible outcomes:
        // Missing global checkpoints in prior weeks. In this case, _index = index + x, where x > 1
        // No missing global checkpoints, but timestamp != block.timestamp. Create new checkpoint.
        // No missing global checkpoints, but timestamp == block.timestamp. Overwrite _latest checkpoint.
        if (_index != 1 && _pointHistory[_index - 1].ts == block.timestamp) {
            // _index = index + 1, so we do not increment index
            _pointHistory[_index - 1] = _latestPoint;
        } else {
            // more than one global point may have been written, so we update index
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
