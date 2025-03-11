/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotingEscrowIncreasingV1_4_0 as IVotingEscrow} from "@escrow/IVotingEscrowIncreasing_v1_4_0.sol";
import {IEscrowCurveIncreasingV1_4_0 as IEscrowCurve, IEscrowCurveGlobal, IEscrowCurveCore, IEscrowCurveTokenV1_4_0 as IEscrowCurveToken} from "@curve/IEscrowCurveIncreasing_v1_4_0.sol";

import {IClockUser, IClockV1_4_0 as IClock} from "@clock/IClock_v1_4_0.sol";
import {IClockSeason} from "@clock/IClockSeason.sol";

// import {IVotingEscrowIncreasingV1_4_0 as IVotingEscrow} from "@escrow/IVotingEscrowIncreasing_v1_4_0.sol";
// import {IEscrowCurveIncreasingV1_4_0 as IEscrowCurve} from "@curve/IEscrowCurveIncreasing_v1_4_0.sol";
// import {IERC721EnumerableMintableBurnable as IERC721EMB} from "@lock/IERC721EMB.sol";

// import {IClockUser} from "@clock/IClock.sol";
// import {IClockV1_4_0 as IClock, IClockSeason} from "@clock/IClock_v1_4_0.sol";

// libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SignedFixedPointMath} from "@libs/SignedFixedPointMathLib.sol";
import {CurveConstantLib} from "@libs/CurveConstantLib.sol";

// contracts
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {DaoAuthorizableUpgradeable as DaoAuthorizable} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizableUpgradeable.sol";
import {PausableUpgradeable as Pausable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

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

    /// @notice Administrator role for the contract
    bytes32 public constant CURVE_ADMIN_ROLE = keccak256("CURVE_ADMIN_ROLE");

    /// @notice The VotingEscrow contract address
    address public escrow;

    /// @notice The Clock contract address
    address public clock;

    /// @notice tokenId => latest index: incremented on a per-tokenId basis
    mapping(uint256 => uint256) public tokenPointLatestIndex;

    /// @notice The warmup period for the curve
    uint48 public warmupPeriod;

    /// @dev tokenId => tokenPointIntervals => TokenPoint
    /// @dev The Array is fixed so we can write to it in the future
    /// This implementation means that very short intervals may be challenging
    mapping(uint256 => TokenPoint[1_000_000_000]) internal _tokenPointHistory;

    /*//////////////////////////////////////////////////////////////
                                ADDED: 0.2.0
    //////////////////////////////////////////////////////////////*/

    /// @dev The latest global point index.
    uint256 public globalPointLatestIndex;

    // endTime => summed up slopes at that endTime
    mapping(uint16 => mapping(uint256 => int256)) public slopeChanges;
    mapping(uint256 => GlobalPoint) internal _globalPointHistory;

    /// @dev precomputed coefficients of the quadratic curve
    int256 private constant SHARED_QUADRATIC_COEFFICIENT =
        CurveConstantLib.SHARED_QUADRATIC_COEFFICIENT;

    int256 private constant SHARED_LINEAR_COEFFICIENT = CurveConstantLib.SHARED_LINEAR_COEFFICIENT;

    int256 private constant SHARED_CONSTANT_COEFFICIENT =
        CurveConstantLib.SHARED_CONSTANT_COEFFICIENT;

    uint256 private constant MAX_EPOCHS = CurveConstantLib.MAX_EPOCHS;

    error UpgradeNotPossible();

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
        return int256(amount) * SHARED_LINEAR_COEFFICIENT;
    }

    /// @return The constant coefficient of the quadratic curve, for the given amount
    /// @dev In this case, the constant term is 1 so we just case the amount
    function _getConstantCoeff(uint256 amount) public pure returns (int256) {
        return int256(amount) * SHARED_CONSTANT_COEFFICIENT;
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
            coefficients[0], // amount
            coefficients[1], // slope
            0
        ];
    }

    /*//////////////////////////////////////////////////////////////
                              CURVE BIAS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the bias for the given time elapsed and amount, up to the maximum time
    function getBias(uint256 timeElapsed, uint256 amount) public view returns (uint256) {
        int256[3] memory coefficients = _getCoefficients(amount);
        return _getBias(timeElapsed, coefficients[0], coefficients[1]);
    }

    /// @notice Returns the bias for the given time elapsed and amount, up to the maximum time
    function _getBias(
        uint256 timeElapsed,
        int256 constantCoeff,
        int256 slope
    ) internal view returns (uint256) {
        uint256 MAX_TIME = maxTime();
        timeElapsed = timeElapsed > MAX_TIME ? MAX_TIME : timeElapsed;

        int256 bias = slope * int256(timeElapsed) + constantCoeff;
        if (bias < 0) bias = 0;

        return bias.toUint256();
    }

    function _getBiasAndSlope(
        uint256 timeElapsed,
        uint256 amount
    ) public view returns (int256, int256) {
        int256 slope = _getLinearCoeff(amount);
        uint256 bias = _getBias(timeElapsed, _getConstantCoeff(amount), slope);

        return (int256(bias), slope);
    }

    function maxTime() public view returns (uint256) {
        return IClock(clock).epochDuration() * MAX_EPOCHS;
    }

    function previewMaxBias(uint256 amount) external view returns (uint256) {
        return getBias(maxTime(), amount);
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

    /// @inheritdoc IEscrowCurveToken
    function tokenPointHistory(
        uint256 _tokenId,
        uint256 _index
    ) external view returns (TokenPoint memory) {
        return _tokenPointHistory[_tokenId][_index];
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

        TokenPoint memory lastPoint = _tokenPointHistory[_tokenId][interval];

        if (!_isWarm(lastPoint)) return 0;

        // get latest season prior to `_t`.
        (uint48 start, ) = IClockSeason(clock).seasonTsAt(uint48(_t));

        int256 bias = lastPoint.coefficients[0];
        int256 slope = lastPoint.coefficients[1];

        if (start == 0) {
            start = uint48(lastPoint.checkpointTs);
        }

        uint256 maxTime = maxTime();

        // Subtract the accumulated bias to the current bias,
        // which will give only total amount on that token point.
        // This step can be avoided in case the season
        // doesn't exist between `_t` and last token point, but to have
        // the consistent flow, the below code works the same way in every case.
        uint256 timeElapsed = lastPoint.writtenTs - lastPoint.checkpointTs;
        if (timeElapsed > maxTime) timeElapsed = maxTime;
        bias -= slope * int256(timeElapsed);

        // For rounding errors, this can become less than 0.
        if (bias < 0) bias = 0;

        // Calculate the elapsed time.
        // If season exists, we use the time from season to the `_t`.
        // If not, we use the time from token point's start to
        if (lastPoint.checkpointTs < start) {
            timeElapsed = _t - start;
        } else {
            timeElapsed = _t - lastPoint.checkpointTs;
        }

        return _getBias(timeElapsed, bias, slope);
    }

    /// @inheritdoc IEscrowCurveCore
    function supplyAt(uint256 _timestamp) external view returns (uint256) {
        uint16 seasonIndex = IClockSeason(clock).seasonIndexAt(uint48(_timestamp));
        return _supplyAt(_timestamp, seasonIndex);
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

    /// TODO: GIORGI add desc
    function resetCheckPoint(uint256 _amount, uint48 _at, uint16 _seasonIndex) public {
        if (msg.sender != escrow) revert OnlyEscrow();

        _resetCheckPoint(_amount, _at, _seasonIndex);
    }

    /// TODO: GIORGI add desc
    function _resetCheckPoint(uint256 _amount, uint48 _at, uint16 _seasonIndex) internal {
        int256 slope = _getLinearCoeff(_amount);
    
        // The below check also ensures that new global point will be stored 
        // after the latest already stored global point, as latest stored global point 
        // either will have `block.timestamp` or less on its `.writtenTs`
        if (_at <= block.timestamp) {
            revert("TODO: GIORGI better message");
        }

        slopeChanges[_seasonIndex][_at + maxTime()] = slope;

        _globalPointHistory[++globalPointLatestIndex] = GlobalPoint({
            bias: _getConstantCoeff(_amount),
            slope: slope,
            writtenTs: _at
        });
    }

    /// @notice Record gper-user data to checkpoints. Used by VotingEscrow system.
    /// @dev Curve finance style but just for users at this stage
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

        // Get latest season index till current time.
        uint16 seasonIndex = IClockSeason(clock).seasonIndexAt(uint48(block.timestamp));
        mapping(uint256 => int256) storage slopeChanges_ = slopeChanges[seasonIndex];

        {
            uint256 checkpointInterval = IClock(clock).checkpointInterval();

            uint256 lastPointCheckpoint = lastPoint.writtenTs;
            uint256 t_i = (lastPointCheckpoint / checkpointInterval) * checkpointInterval;

            for (uint256 i = 0; i < 255; ++i) {
                t_i += checkpointInterval;
                int256 dSlope;

                if (t_i > block.timestamp) {
                    t_i = block.timestamp;
                } else {
                    dSlope = slopeChanges_[t_i];
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

        uint256 newEnd = _newLocked.start + maxTime();

        int256 newDSlope = slopeChanges_[newEnd];

        // If the newLocked hasn't ended, add its slope
        // to the latest global point. newLocked could be ended in case of
        // merge, when a token is already mature.
        if (block.timestamp < newEnd) {
            lastPoint.slope += newLockSlope;
            newDSlope += newLockSlope;
        }

        lastPoint.bias += newLockBias;

        uint256 tokenLatestIndex = tokenPointLatestIndex[_tokenId];
        
        // The `tokenId` already exists..
        if (tokenLatestIndex > 0) {
            uint256 _fromLockedEnd = _fromLocked.start + maxTime();
            
            // Get the slope and bias for `_fromLocked`...
            (int256 oldLockBias, int256 oldLockSlope) = _getBiasAndSlope(
                block.timestamp - _fromLocked.start,
                _fromLocked.amount
            );

            if (_newLocked.amount == 0) {
                lastPoint.bias -= oldLockBias;
                if (_fromLockedEnd > block.timestamp) {
                    // If `fromLocked` ends in the future, we must subtract its slope
                    // as from this moment on(due to making amount=0),
                    // the slope must not be included. Note that in case the end is
                    // in the past, we already subtracted it inside the above loop.
                    lastPoint.slope -= oldLockSlope;
                    newDSlope -= oldLockSlope;
                }
            } else {
                // Merge is occuring, so get the total
                // bias and slope for `fromLocked` and `newLocked`.
                newLockSlope += oldLockSlope;
                newLockBias += oldLockBias;

                // fromLocked's current end is in the future and since `fromLocked` gets destroyed,
                // its slope must be recorded on the newLocked's end.
                if (_fromLockedEnd > block.timestamp && _fromLockedEnd != newEnd) {
                    newDSlope += oldLockSlope;
                }
            }

            if (_fromLockedEnd != newEnd && _fromLockedEnd >= block.timestamp) {
                int256 oldDSlope = slopeChanges_[_fromLockedEnd] - oldLockSlope;
                slopeChanges_[_fromLockedEnd] = oldDSlope < 0 ? int256(0) : oldDSlope;
            }
        }

        if (lastPoint.slope < 0) lastPoint.slope = 0;
        if (lastPoint.bias < 0) lastPoint.bias = 0;

        // TODO: see aerodome..
        globalPointLatestIndex = _globalPointLatestIndex;
        _globalPointHistory[_globalPointLatestIndex] = lastPoint;

        slopeChanges_[newEnd] = newDSlope < 0 ? int256(0) : newDSlope;

        // Create new token point and store.
        TokenPoint memory tNew;
        tNew.writtenTs = uint128(block.timestamp);
        tNew.checkpointTs = _newLocked.start;
        tNew.coefficients = [newLockBias, newLockSlope, 0];

        if (
            tokenLatestIndex != 0 &&
            _tokenPointHistory[_tokenId][tokenLatestIndex].writtenTs == block.timestamp
        ) {
            _tokenPointHistory[_tokenId][tokenLatestIndex] = tNew;
        } else {
            tokenPointLatestIndex[_tokenId] = ++tokenLatestIndex;
            _tokenPointHistory[_tokenId][tokenLatestIndex] = tNew;
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
        if (_tokenPointHistory[_tokenId][tokenInterval].writtenTs <= _timestamp) return (tokenInterval);

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
    /// @param _seasonIndex The season index to which the slope changes were stored for `_timestamp`.
    /// @return Total voting power at that time
    function _supplyAt(uint256 _timestamp, uint16 _seasonIndex) internal view returns (uint256) {
        uint256 epoch_ = getPastGlobalPointIndex(_timestamp);
        // epoch 0 is an empty point
        if (epoch_ == 0) return 0;
        GlobalPoint memory _point = _globalPointHistory[epoch_];
        int256 bias = _point.bias;
        int256 slope = _point.slope;
        uint256 ts = _point.writtenTs; // changes in for loop.

        mapping(uint256 => int256) storage slopeChanges_ = slopeChanges[_seasonIndex];

        uint256 checkpointInterval = IClock(clock).checkpointInterval();

        uint256 t_i = (ts / checkpointInterval) * checkpointInterval;

        for (uint256 i = 0; i < 255; ++i) {
            t_i += checkpointInterval;
            int256 dSlope = 0;
            if (t_i > _timestamp) {
                t_i = _timestamp;
            } else {
                dSlope = slopeChanges_[t_i];
            }
            bias += slope * int256(t_i - ts);

            if (t_i == _timestamp) {
                break;
            }
            slope -= dSlope;
            ts = t_i;
        }

        if (bias < 0) bias = 0;

        return uint256(bias / 1e18); // TODO: USE safe cast
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
