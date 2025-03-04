/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotingEscrowIncreasing as IVotingEscrow} from "@escrow-interfaces/IVotingEscrowIncreasing.sol";
import {IEscrowCurveIncreasing as IEscrowCurve} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {IEscrowCurveCore, IEscrowCurveToken} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";

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
import {BalanceLogicLibrary} from "../../libs/BalanceLogicLibrary.sol";
import {console2 as console} from "forge-std/console2.sol";

/// @title Quadratic Increasing Escrow
contract QuadraticIncreasingEscrow is
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
    mapping(uint256 => uint256) public slopeChanges;

    // TODO: update interface for TokenPointV2
    mapping(uint256 => GlobalPoint) internal _globalPointHistory;
    mapping(uint256 => TokenPointV2[1000000000]) internal _userPointHistory;
    
    /// @dev precomputed coefficients of the quadratic curve
    int256 private constant SHARED_QUADRATIC_COEFFICIENT =
        CurveConstantLib.SHARED_QUADRATIC_COEFFICIENT;

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

    /// @return The coefficient for the quadratic term of the quadratic curve, for the given amount
    function _getQuadraticCoeff(uint256 amount) internal pure returns (int256) {
        return (SignedFixedPointMath.toFP(amount.toInt256()).mul(SHARED_QUADRATIC_COEFFICIENT));
    }

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
        return [_getConstantCoeff(amount), _getLinearCoeff(amount), _getQuadraticCoeff(amount)];
    }

    /// @return The coefficients of the quadratic curve, for the given amount
    /// @dev The coefficients are returned in the order [constant, linear, quadratic]
    /// and are converted to regular 256-bit signed integers instead of their fixed-point representation
    function getCoefficients(uint256 amount) public pure returns (int256[3] memory) {
        int256[3] memory coefficients = _getCoefficients(amount);

        return [
            SignedFixedPointMath.fromFP(coefficients[0]),
            SignedFixedPointMath.fromFP(coefficients[1]),
            SignedFixedPointMath.fromFP(coefficients[2])
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
        int256 quadratic = coefficients[2];
        int256 linear = coefficients[1];
        int256 const = coefficients[0];

        // bound the time elapsed to the maximum time
        uint256 MAX_TIME = _maxTime();
        timeElapsed = timeElapsed > MAX_TIME ? MAX_TIME : timeElapsed;

        // convert the time to fixed point
        int256 t = SignedFixedPointMath.toFP(timeElapsed.toInt256());

        // bias = a.t^2 + b.t + c
        int256 tSquared = t.mul(t); // t*t much more gas efficient than t.pow(SD2)
        int256 bias = quadratic.mul(tSquared).add(linear.mul(t)).add(const);

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

    /// @notice Returns the TokenPoint at the passed user epoch.
    /// @param _tokenId The NFT to return the TokenPoint for
    /// @param _index The index to return the TokenPoint at.
    function tokenPointHistory(
        uint256 _tokenId,
        uint256 _index
    ) external view returns (TokenPoint memory) {
        return _tokenPointHistory[_tokenId][_index];
    }

    /// @inheritdoc IEscrowCurveToken
    function tokenPointIntervals(uint256 _tokenId) external view returns (uint256) {
        return tokenPointLatestIndex[_tokenId];
    }

    // TODO:GIORGI it's better to name it as tokenPointHistory, but it matches the above function which uses different structure.
    function userPointHistory_1(
        uint256 _tokenId,
        uint256 _tokenInterval
    ) external view returns (TokenPointV2 memory) {
        return _userPointHistory[_tokenId][_tokenInterval];
    }

    /// @notice Returns the global point at the passed epoch
    /// @param _index The index in an array to return the point for
    function pointHistory(uint256 _index) external view returns (GlobalPoint memory) {
        return _globalPointHistory[_index];
    }

    /// @notice Binary search to get the token point interval for a token id at or prior to a given timestamp
    /// Once we have the point, we can apply the bias calculation to get the voting power.
    /// @dev If a token point does not exist prior to the timestamp, this will return 0.
    function _getPastTokenPointInterval(
        uint256 _tokenId,
        uint256 _timestamp
    ) internal view returns (uint256) {
        uint256 tokenInterval = tokenPointLatestIndex[_tokenId];
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

    /// @inheritdoc IEscrowCurveCore
    function votingPowerAt(uint256 _tokenId, uint256 _t) external view returns (uint256) {
        uint256 interval = _getPastTokenPointInterval(_tokenId, _t);

        // epoch 0 is an empty point
        if (interval == 0) return 0;
        TokenPoint memory lastPoint = _tokenPointHistory[_tokenId][interval];

        if (!_isWarm(lastPoint)) return 0;
        uint256 timeElapsed = _t - lastPoint.checkpointTs;

        return _getBias(timeElapsed, lastPoint.coefficients);
    }

    /// @inheritdoc IEscrowCurveCore
    function supplyAt(uint256 _ts) external view returns (uint256) {
        return
            BalanceLogicLibrary.supplyAt(
                slopeChanges,
                _globalPointHistory,
                globalPointLatestIndex,
                _ts
            );
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

    /// @notice Record gper-user data to checkpoints. Used by VotingEscrow system.
    /// @dev Curve finance style but just for users at this stage
    /// @param _tokenId NFT token ID.
    /// @param _newLocked New locked amount / end lock time for the user
    function _checkpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _fromLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) internal {
        // this implementation doesn't yet support manual checkpointing
        if (_tokenId == 0) revert InvalidTokenId();

        uint256 _globalPointLatestIndex = globalPointLatestIndex;
        TokenPointV2 memory uNew;

        GlobalPoint memory lastPoint = GlobalPoint({
            bias: 0,
            slope: 0,
            ts: uint48(block.timestamp)
        });

        if (_globalPointLatestIndex > 0) {
            lastPoint = _globalPointHistory[_globalPointLatestIndex];
        }

        {
            uint256 checkpointInterval = IClock(clock).checkpointInterval();

            uint256 lastPointCheckpoint = lastPoint.ts;
            uint256 t_i = (lastPointCheckpoint / checkpointInterval) * checkpointInterval;

            for (uint256 i = 0; i < 255; ++i) {
                t_i += checkpointInterval;
                uint256 dSlope;

                if (t_i > block.timestamp) {
                    t_i = block.timestamp;
                } else {
                    dSlope = slopeChanges[t_i];
                }

                lastPoint.bias += lastPoint.slope * (t_i - lastPointCheckpoint);
                lastPoint.slope -= dSlope;

                lastPointCheckpoint = t_i;
                lastPoint.ts = t_i.toUint48();
                _globalPointLatestIndex += 1;

                if (t_i == block.timestamp) {
                    break;
                } else {
                    _globalPointHistory[_globalPointLatestIndex] = lastPoint;
                }
            }
        }

        // Transform amounts into fixed points.
        _fromLocked.amount *= 1e18;
        _newLocked.amount *= 1e18;

        uNew.slope = (_newLocked.amount / CurveConstantLib.MAX_TIME);

        {
            uint256 elapsed = block.timestamp - _newLocked.start;
            if (elapsed > CurveConstantLib.MAX_TIME) {
                elapsed = CurveConstantLib.MAX_TIME;
            }
            uNew.bias = _newLocked.amount + uNew.slope * elapsed;
        }

        uNew.ts = uint48(block.timestamp);

        if (uint48(block.timestamp) - _newLocked.start >= CurveConstantLib.MAX_TIME) {
            uNew.slope = 0;
        }

        uint48 newEnd = (_newLocked.start + CurveConstantLib.MAX_TIME).toUint48();
        uint256 newSlope = lastPoint.slope + uNew.slope;
        uint256 newBias = lastPoint.bias + uNew.bias;
        uint256 newDSlope = slopeChanges[newEnd] + uNew.slope;

        uint256 tokenLatestIndex = tokenPointLatestIndex[_tokenId];

        // The `tokenId` already exists..
        if (tokenLatestIndex > 0) {
            uint48 _fromLockedEnd = uint48(_fromLocked.start + CurveConstantLib.MAX_TIME);
            uint48 ts = _fromLockedEnd <= uNew.ts ? _fromLockedEnd : uint48(block.timestamp);

            uint256 oldSlope = (_fromLocked.amount / CurveConstantLib.MAX_TIME);
            uint256 oldBias = _fromLocked.amount + oldSlope * (ts - _fromLocked.start);

            if (_newLocked.amount == 0) {
                if (_fromLockedEnd <= uNew.ts) {
                    // we already subtracted p.slope in the above for loop,
                    // because we encounter slopeChanges[_fromLockedEnd] before uNew.ts.
                    newBias = oldBias > newBias ? 0 : newBias - oldBias;
                } else {
                    newBias = oldBias > newBias ? 0 : newBias - oldBias;
                    newSlope = oldSlope > newSlope ? 0 : newSlope - oldSlope;
                    newDSlope = oldSlope > newDSlope ? 0 : newDSlope - oldSlope;
                }
            } else {
                // User already had locked `x` amount on `tokenId=y` and
                // tries to add more amount on the same `tokenId=y`.
                if (_fromLockedEnd <= uNew.ts) {
                    // Previous point already ends before new point. This means
                    // from newPoint, old slope must not be included anymore.
                    // bias still must be as after end, it doesn't get 0,
                    // but maxed out constant.
                    uNew.bias += oldBias;
                } else {
                    // Previous point hasn't ended yet, so from newPoint,
                    // old slope must still be added.
                    uNew.slope += oldSlope;
                    uNew.bias += oldBias;
                    if (_fromLockedEnd != newEnd) newDSlope += oldSlope;
                }
            }

            // If the end date has not changed and is in future,
            // we must not clear out slope changes.
            if (_fromLockedEnd != newEnd && _fromLockedEnd >= uNew.ts) {
                slopeChanges[_fromLockedEnd] = oldSlope > slopeChanges[_fromLockedEnd]
                    ? 0
                    : slopeChanges[_fromLockedEnd] - oldSlope;
            }
        }

        lastPoint.slope = newSlope;
        lastPoint.bias = newBias;

        // TODO: see aerodome..
        globalPointLatestIndex = _globalPointLatestIndex;
        _globalPointHistory[_globalPointLatestIndex] = lastPoint;

        slopeChanges[newEnd] = newDSlope;

        if (
            tokenLatestIndex != 0 &&
            _userPointHistory[_tokenId][tokenLatestIndex].ts == block.timestamp
        ) {
            _userPointHistory[_tokenId][tokenLatestIndex] = uNew;
        } else {
            tokenPointLatestIndex[_tokenId] = ++tokenLatestIndex;
            _userPointHistory[_tokenId][tokenLatestIndex] = uNew;
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
