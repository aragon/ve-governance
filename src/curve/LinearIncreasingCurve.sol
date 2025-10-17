/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {
    IVotingEscrowIncreasingV1_2_0 as IVotingEscrow
} from "@escrow/IVotingEscrowIncreasing_v1_2_0.sol";
import {
    IEscrowCurveIncreasingV1_2_0 as IEscrowCurve,
    IEscrowCurveGlobal,
    IEscrowCurveCore,
    IEscrowCurveTokenV1_2_0 as IEscrowCurveToken
} from "@curve/IEscrowCurveIncreasing_v1_2_0.sol";

import {IClockUser, IClockV1_2_0 as IClock} from "@clock/IClock_v1_2_0.sol";

// libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SignedFixedPointMath} from "@libs/SignedFixedPointMathLib.sol";

// contracts
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable as ReentrancyGuard
} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {
    DaoAuthorizableUpgradeable as DaoAuthorizable
} from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";

/// @title Linear Increasing Escrow Curve
contract LinearIncreasingCurve is
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

    /// @notice Administrator role for the contract
    bytes32 public constant CURVE_ADMIN_ROLE = keccak256("CURVE_ADMIN_ROLE");

    /// @notice The VotingEscrow contract address
    address public escrow;

    /// @notice The Clock contract address
    address public clock;

    /// @notice tokenId => latest index: incremented on a per-tokenId basis
    /// @custom:oz-renamed-from tokenPointIntervals
    mapping(uint256 => uint256) public tokenPointLatestIndex;

    /// @notice The warmup period for the curve
    /// @dev Deprecated in this version, but kept for backwards compatibility.
    uint48 public warmupPeriod;

    /// @dev tokenId => tokenPointIntervals => TokenPoint
    /// @dev The Array is fixed so we can write to it in the future
    /// This implementation means that very short intervals may be challenging
    mapping(uint256 => TokenPoint[1_000_000_000]) internal _tokenPointHistory;

    /*//////////////////////////////////////////////////////////////
                                MATH
    //////////////////////////////////////////////////////////////*/

    int256 public curveConstantCoefficient;
    int256 public curveLinearCoefficient;
    int256 public curveQuadraticCoefficient;

    uint256 public curveMaxEpochs;
    
    /*//////////////////////////////////////////////////////////////
                            ADDED: TOTAL SUPPLY(1.2.0)
    //////////////////////////////////////////////////////////////*/

    /// @dev The latest global point index.
    uint256 public globalPointLatestIndex;

    // endTime => summed up slopes at that endTime
    mapping(uint256 => int256) public slopeChanges;

    /// @dev The global point history
    mapping(uint256 => GlobalPoint) internal _globalPointHistory;

    /*//////////////////////////////////////////////////////////////
                              INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    /// @param _escrow VotingEscrow contract address
    function initialize(address _escrow, address _dao, address _clock, int256[3] memory _coefficients, uint256 _maxEpochs) external initializer {
        escrow = _escrow;
        clock = _clock;
        
        curveConstantCoefficient = _coefficients[0];
        curveLinearCoefficient = _coefficients[1];
        // curveQuadraticCoefficient = _coefficients[2];

        curveMaxEpochs = _maxEpochs;

        __ReentrancyGuard_init();
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));

        // other initializers are empty
    }

    /*//////////////////////////////////////////////////////////////
                              CURVE COEFFICIENTS
    //////////////////////////////////////////////////////////////*/

    /// @return The coefficient for the curve's linear term, for the given amount
    function _getLinearCoeff(uint256 amount) internal view virtual returns (int256) {
        return amount.toInt256() * curveLinearCoefficient;
    }

    /// @return The constant coefficient of the increasing curve, for the given amount
    /// @dev In this case, the constant term is 1 so we just case the amount
    function _getConstantCoeff(uint256 amount) internal view virtual returns (int256) {
        return amount.toInt256() * curveQuadraticCoefficient;
    }

    /// @return The coefficients of the quadratic curve, for the given amount
    /// @dev The coefficients are returned in the order [constant, linear, quadratic]
    function _getCoefficients(uint256 amount) internal view virtual returns (int256[3] memory) {
        return [_getConstantCoeff(amount), _getLinearCoeff(amount), 0];
    }

    /// @return The coefficients of the quadratic curve, for the given amount
    /// @dev The coefficients are returned in the order [constant, linear, quadratic]
    /// and are converted to regular 256-bit signed integers instead of their fixed-point representation
    function getCoefficients(uint256 amount) public view virtual returns (int256[3] memory) {
        int256[3] memory coefficients = _getCoefficients(amount);

        return [
            coefficients[0] / 1e18, // amount
            coefficients[1] / 1e18, // slope
            0
        ];
    }

    /*//////////////////////////////////////////////////////////////
                              CURVE BIAS
    //////////////////////////////////////////////////////////////*/

    /// @notice Rounds `_elapsed` to maxTime if it's greater, otherwise returns `_elapsed`.
    function boundElapsedMaxTime(uint256 _elapsed) private view returns (uint256) {
        uint256 MAX_TIME = maxTime();
        return _elapsed > MAX_TIME ? MAX_TIME : _elapsed;
    }

    /// @notice Returns the bias for the given time elapsed and amount, up to the maximum time
    function getBias(uint256 timeElapsed, uint256 amount) public view returns (uint256) {
        int256[3] memory coefficients = _getCoefficients(amount);
        uint256 bias = _getBias(boundElapsedMaxTime(timeElapsed), coefficients[0], coefficients[1]);

        return bias / 1e18;
    }

    /// @notice Returns the bias for the given time elapsed and amount, up to the maximum time
    /// @dev Returned values from these functions are in fixed point representation
    ///    which is not the case in `getBias`.
    function _getBias(
        uint256 _timeElapsed,
        int256 _constantCoeff,
        int256 _linearCoeff
    ) internal pure returns (uint256) {
        int256 bias = _linearCoeff * int256(_timeElapsed) + _constantCoeff;
        if (bias < 0) bias = 0;

        return bias.toUint256();
    }

    function _getBiasAndSlope(
        uint256 _timeElapsed,
        uint256 _amount
    ) public view returns (int256, int256) {
        int256 slope = _getLinearCoeff(_amount);
        uint256 bias = _getBias(
            boundElapsedMaxTime(_timeElapsed),
            _getConstantCoeff(_amount),
            slope
        );

        return (int256(bias), slope);
    }

    function maxTime() public view virtual returns (uint256) {
        return IClock(clock).epochDuration() * curveMaxEpochs;
    }

    function previewMaxBias(uint256 amount) external view returns (uint256) {
        return getBias(maxTime(), amount);
    }

    /*//////////////////////////////////////////////////////////////
                              BALANCE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEscrowCurveToken
    function tokenPointHistory(
        uint256 _tokenId,
        uint256 _index
    ) external view returns (TokenPoint memory point) {
        point = _tokenPointHistory[_tokenId][_index];
        /// bind for backwards compatibility
        point.bias = uint(point.coefficients[0]) / 1e18;
    }

    /// @inheritdoc IEscrowCurveGlobal
    function globalPointHistory(uint256 _index) public view returns (GlobalPoint memory) {
        return _globalPointHistory[_index];
    }

    /// @inheritdoc IEscrowCurveToken
    function tokenPointIntervals(uint256 _tokenId) external view returns (uint256) {
        return tokenPointLatestIndex[_tokenId];
    }

    /// @inheritdoc IEscrowCurveCore
    function votingPowerAt(uint256 _tokenId, uint256 _t) external view returns (uint256) {
        uint256 interval = _getPastTokenPointInterval(_tokenId, _t);

        // epoch 0 is an empty point
        if (interval == 0) return 0;

        // Note that very first point is saved at index 1.
        // Grab original point(the very first point for `_tokenId`).
        TokenPoint memory originalPoint = _tokenPointHistory[_tokenId][1];

        // Grab last point before `_t`.
        TokenPoint memory lastPoint = _tokenPointHistory[_tokenId][interval];
        int256 bias = lastPoint.coefficients[0];
        int256 slope = lastPoint.coefficients[1];

        uint256 end = originalPoint.checkpointTs + maxTime();

        // If the point was created before the upgrade:
        //    it will have `checkpointTs` greater than `writtenTs`.
        //    bias would have been stored as just the amount(without bonus).
        // In such case, we make writtenTs equal to avoid checkpointTs greater.
        // This ensures that behaviour after and before upgrade are same.
        if (lastPoint.checkpointTs > lastPoint.writtenTs) {
            lastPoint.writtenTs = lastPoint.checkpointTs;
            if (_t < lastPoint.writtenTs) return 0;
        }

        uint256 elapsed = _t - lastPoint.writtenTs;

        uint256 timeTillMaxTime = 0;
        if (end > lastPoint.writtenTs) {
            timeTillMaxTime = end - lastPoint.writtenTs;
        }

        if (elapsed >= timeTillMaxTime) {
            elapsed = timeTillMaxTime;
        }

        return _getBias(elapsed, bias, slope) / 1e18;
    }

    /// @inheritdoc IEscrowCurveCore
    function supplyAt(uint256 _timestamp) external view returns (uint256) {
        return _supplyAt(_timestamp);
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

    /// @notice Record user data to checkpoints. Used by VotingEscrow system.
    /// @param _tokenId NFT token ID.
    /// @param _fromLocked The locked from which we're moving.
    /// @param _newLocked New locked amount / end lock time for the user
    function _checkpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _fromLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) internal {
        // this implementation doesn't yet support manual checkpointing
        if (_tokenId == 0) revert InvalidTokenId();

        if (_newLocked.start < _fromLocked.start) {
            revert InvalidCheckpoint();
        }

        uint256 _globalPointLatestIndex = globalPointLatestIndex;

        // Get the slope and bias for `_newLocked`...
        (int256 newLockBias, int256 newLockSlope) = _getBiasAndSlope(
            block.timestamp - _newLocked.start,
            _newLocked.amount
        );

        GlobalPoint memory lastPoint = GlobalPoint({
            bias: 0,
            slope: 0,
            writtenTs: uint48(block.timestamp)
        });

        if (_globalPointLatestIndex > 0) {
            lastPoint = _globalPointHistory[_globalPointLatestIndex];
        }

        {
            uint256 checkpointInterval = IClock(clock).checkpointInterval();

            // For safety reasons, we don't allow checkpoints
            // on the exact checkpointInterval.
            if (block.timestamp % checkpointInterval == 0) {
                revert CheckpointOnDepositIntervalNotAllowed();
            }

            uint256 lastPointCheckpoint = lastPoint.writtenTs;
            uint256 t_i = (lastPointCheckpoint / checkpointInterval) * checkpointInterval;

            for (uint256 i = 0; i < 255; ++i) {
                t_i += checkpointInterval;
                int256 dSlope;

                if (t_i > block.timestamp) {
                    t_i = block.timestamp;
                } else {
                    dSlope = slopeChanges[t_i];
                }

                lastPoint.bias += lastPoint.slope * int256(t_i - lastPointCheckpoint);
                lastPoint.slope -= dSlope;

                if (lastPoint.slope < 0) lastPoint.slope = 0;
                if (lastPoint.bias < 0) lastPoint.bias = 0;

                lastPointCheckpoint = t_i;
                lastPoint.writtenTs = uint48(t_i);
                _globalPointLatestIndex += 1;

                if (t_i == block.timestamp) {
                    break;
                } else {
                    _globalPointHistory[_globalPointLatestIndex] = lastPoint;
                }
            }
        }

        uint256 _maxTime = maxTime();
        uint256 newLockedEnd = _newLocked.start + _maxTime;
        uint256 fromLockedEnd = _fromLocked.start + _maxTime;

        // The following condition is true if merging non-mature locks with different start dates.
        // current version of ve-governance is built around the assumption that merge can only
        // occur if tokens are either mature or have the same start dates. Even though `escrow`
        // does this check before calling `checkpoint` on curve, it's still a safety measure to repeat
        // the check in case the code of checkpoint might be called by another contract in the future.
        if (
            _fromLocked.start != 0 &&
            _newLocked.start != 0 &&
            _fromLocked.start != _newLocked.start &&
            (newLockedEnd >= block.timestamp || fromLockedEnd >= block.timestamp)
        ) {
            revert InvalidLocks(_tokenId, _fromLocked, _newLocked);
        }

        // newLocked could be ended in case of merge, when
        // a token is already mature.
        if (newLockedEnd <= block.timestamp) {
            newLockSlope = 0;
        }

        (int256 oldLockBias, int256 oldLockSlope) = (0, 0);

        if (_fromLocked.amount > 0) {
            (oldLockBias, oldLockSlope) = _getBiasAndSlope(
                block.timestamp - _fromLocked.start,
                _fromLocked.amount
            );

            // In case fromLocked already ended, its slope would already
            // be subtracted from `lastPoint.slope` in the above for loop.
            // So we make this 0 to not subtract double times.
            if (fromLockedEnd <= block.timestamp) {
                oldLockSlope = 0;
            }
        }

        lastPoint.bias += (newLockBias - oldLockBias);
        lastPoint.slope += (newLockSlope - oldLockSlope);

        if (lastPoint.slope < 0) lastPoint.slope = 0;
        if (lastPoint.bias < 0) lastPoint.bias = 0;

        uint256 tokenLatestIndex = tokenPointLatestIndex[_tokenId];

        // The token point already exists..
        if (tokenLatestIndex > 0) {
            if (fromLockedEnd > block.timestamp) {
                slopeChanges[fromLockedEnd] -= oldLockSlope;
            }
        }

        // store new slope change
        slopeChanges[newLockedEnd] += newLockSlope;

        // Record the latest global point.
        _storeLatestGlobalPoint(lastPoint, _globalPointLatestIndex);

        // Create new token point and store.
        TokenPoint memory tNew;
        tNew.writtenTs = uint128(block.timestamp);
        tNew.checkpointTs = _newLocked.start;
        tNew.coefficients = [newLockBias, newLockSlope, 0];

        // Record the latest token point.
        _storeLatestTokenPoint(tNew, _tokenId, tokenLatestIndex);
    }

    /// @dev The private helper function to either store latest global point on a new index or overwrite it.
    ///      In case of overwriting, the latest global point index is not incremented.
    function _storeLatestGlobalPoint(GlobalPoint memory _p, uint256 _index) private {
        // If the timestamp of last stored global point is the same as
        // current timestamp, overwrite it, otherwise store a new one
        // to reduce unnecessary global points in the history for
        // gas costs and binary search efficiency.
        if (_index != 1 && _globalPointHistory[_index - 1].writtenTs == block.timestamp) {
            _globalPointHistory[_index - 1] = _p;
        } else {
            globalPointLatestIndex = _index;
            _globalPointHistory[_index] = _p;
        }
    }

    /// @dev The private helper function to either store latest token point on a new index or overwrite it.
    ///      In case of overwriting, the latest token point index is not incremented.
    function _storeLatestTokenPoint(
        TokenPoint memory _p,
        uint256 _tokenId,
        uint256 _index
    ) private {
        // If the timestamp of last stored token point is the same as
        // current timestamp, overwrite it, otherwise store a new one
        // to reduce unnecessary global points in the history for
        // gas costs and binary search efficiency.
        if (_index != 0 && _tokenPointHistory[_tokenId][_index].writtenTs == block.timestamp) {
            _tokenPointHistory[_tokenId][_index] = _p;
        } else {
            tokenPointLatestIndex[_tokenId] = ++_index;
            _tokenPointHistory[_tokenId][_index] = _p;
        }
    }

    /*///////////////////////////////////////////////////////////////
            Total Supply and Voting Power Calculations
    //////////////////////////////////////////////////////////////*/

    /// @notice Binary search to get the token point interval for a token id at or prior to a given timestamp
    /// Once we have the point , we can apply the bias calculation to get the voting power.
    /// @dev If a token point does not exist prior to the timestamp, this will return 0.
    function _getPastTokenPointInterval(
        uint256 _tokenId,
        uint256 _timestamp
    ) internal view returns (uint256) {
        uint256 tokenInterval = tokenPointLatestIndex[_tokenId];

        if (tokenInterval == 0) return 0;

        // if the most recent point is before the timestamp, return it
        if (_tokenPointHistory[_tokenId][tokenInterval].writtenTs <= _timestamp)
            return (tokenInterval);

        // Check if the first balance is after the timestamp
        // this means that the first epoch has yet to start
        if (_tokenPointHistory[_tokenId][1].writtenTs > _timestamp) return 0;

        uint256 lower = 0;
        uint256 upper = tokenInterval;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            TokenPoint storage tokenPoint = _tokenPointHistory[_tokenId][center];
            if (tokenPoint.writtenTs == _timestamp) {
                return center;
            } else if (tokenPoint.writtenTs < _timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    /// @notice Binary search to get the global point index at or prior to a given timestamp
    /// @dev If a checkpoint does not exist prior to the timestamp, this will return 0.
    /// @param _timestamp The timestamp to get a checkpoint at.
    /// @return Global point index
    function getPastGlobalPointIndex(uint256 _timestamp) internal view returns (uint256) {
        if (globalPointLatestIndex == 0) return 0;
        // First check most recent balance
        if (_globalPointHistory[globalPointLatestIndex].writtenTs <= _timestamp)
            return (globalPointLatestIndex);
        // Next check implicit zero balance
        if (_globalPointHistory[1].writtenTs > _timestamp) return 0;

        uint256 lower = 0;
        uint256 upper = globalPointLatestIndex;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            GlobalPoint storage globalPoint = _globalPointHistory[center];
            if (globalPoint.writtenTs == _timestamp) {
                return center;
            } else if (globalPoint.writtenTs < _timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    /// @notice Calculate total voting power at some point in the past
    /// @param _timestamp Time to calculate the total voting power at
    /// @return Total voting power at that time
    function _supplyAt(uint256 _timestamp) internal view returns (uint256) {
        uint256 epoch_ = getPastGlobalPointIndex(_timestamp);
        // epoch 0 is an empty point
        if (epoch_ == 0) return 0;
        GlobalPoint memory _point = _globalPointHistory[epoch_];

        int256 bias = _point.bias;
        int256 slope = _point.slope;
        uint256 ts = _point.writtenTs; // changes in for loop.

        uint256 checkpointInterval = IClock(clock).checkpointInterval();

        uint256 t_i = (ts / checkpointInterval) * checkpointInterval;

        for (uint256 i = 0; i < 255; ++i) {
            t_i += checkpointInterval;
            int256 dSlope = 0;

            if (t_i > _timestamp) {
                t_i = _timestamp;
            } else {
                dSlope = slopeChanges[t_i];
            }

            bias += slope * int256(t_i - ts);

            if (t_i == _timestamp) {
                break;
            }
            slope -= dSlope;
            ts = t_i;
        }

        if (bias < 0) bias = 0;

        return uint256(bias / 1e18);
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

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[42] private __gap;

    /*//////////////////////////////////////////////////////////////
                          DEPRECATED: Warmup
    //////////////////////////////////////////////////////////////*/

    function setWarmupPeriod(uint48) external pure {
        revert Deprecated();
    }

    /// @notice Returns whether the NFT is warm
    /// @dev In this version, warm functionality has been deprecated.
    ///      For backwards compatibility, always return true.
    function isWarm(uint256) public pure virtual returns (bool) {
        return true;
    }

    /// @notice Returns whether the NFT is warm at the specified timestamp(`_ts`)
    /// @dev In this version, warm functionality has been deprecated.
    ///      For backwards compatibility, always return true.
    function isWarm(uint256, uint48) public pure virtual returns (bool) {
        return true;
    }
}
