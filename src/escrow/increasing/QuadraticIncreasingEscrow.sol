/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotingEscrowIncreasing as IVotingEscrow} from "@escrow-interfaces/IVotingEscrowIncreasing.sol";
import {IEscrowCurveIncreasing as IEscrowCurve} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {IEscrowCurveCore} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";

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

    /// @notice tokenId => point epoch: incremented on a per-tokenId basis
    mapping(uint256 => uint256) public tokenPointIntervals;

    /// @notice The warmup period for the curve
    uint48 public warmupPeriod;

    /// @dev tokenId => tokenPointIntervals => TokenPoint
    /// @dev The Array is fixed so we can write to it in the future
    /// This implementation means that very short intervals may be challenging
    mapping(uint256 => TokenPoint[1_000_000_000]) internal _tokenPointHistory;

    // ============GIORGI===============
    uint256 public constant WEEK = 1 weeks;
    uint256 internal constant MAXTIME = 4 * 365 * 86400;

    uint256 public epoch;


    struct UserPoint {
        uint208 bias;
        uint128 slope; // TODO: maybe int128 ? can it get negative values ?
        uint48 ts;
        uint48 start;
    }


    // endTime => summed up slopes at that endTime
    mapping(uint256 => uint128) public slopeChanges;

    mapping(uint256 => UserPoint) internal _pointHistory;
    mapping(uint256 => UserPoint[1000000000]) internal _userPointHistory;
    mapping(uint256 => uint256) public userPointEpoch;

    // ============GIORGI===============

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
    /// @param _tokenInterval The epoch to return the TokenPoint at
    function tokenPointHistory(
        uint256 _tokenId,
        uint256 _tokenInterval
    ) external view returns (TokenPoint memory) {
        return _tokenPointHistory[_tokenId][_tokenInterval];
    }

    // TODO:GIORGI it's better to name it as tokenPointHistory, but it matches the above function which uses different structure.
    function userPointHistory_1(uint256 _tokenId, uint256 _tokenInterval) external view returns (UserPoint memory) {
        return _userPointHistory[_tokenId][_tokenInterval];
    }

    /// @notice Returns the global point at the passed epoch
    /// @param _epoch The epoch to return the point for
    function pointHistory(uint256 _epoch) external view returns (UserPoint memory) {
        return _pointHistory[_epoch];
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
    function supplyAt(uint256 _ts) external view returns(uint256) {
        return BalanceLogicLibrary.supplyAt(slopeChanges, _pointHistory, epoch, _ts);
    }

    /*//////////////////////////////////////////////////////////////
                              CHECKPOINT
    //////////////////////////////////////////////////////////////*/

    /// @notice A checkpoint can be called by the VotingEscrow contract to snapshot the user's voting power
    function checkpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.LockedBalance memory _newLocked,
        uint48 _dur
    ) external nonReentrant {
        // TODO: GIORGI uncomment later...
        // if (msg.sender != escrow) revert OnlyEscrow();
        _checkpoint(_tokenId, _oldLocked, _newLocked, _dur);
    }

    /// @notice Record gper-user data to checkpoints. Used by VotingEscrow system.
    /// @dev Curve finance style but just for users at this stage
    /// @param _tokenId NFT token ID.
    /// @param _newLocked New locked amount / end lock time for the user
    function _checkpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _fromLocked,
        IVotingEscrow.LockedBalance memory _newLocked,
        uint48 accumulationDur
    ) internal {
        // this implementation doesn't yet support manual checkpointing
        if (_tokenId == 0) revert InvalidTokenId();

        uint48 currentTime = uint48(block.timestamp);

        uint256 _epoch = epoch;
        UserPoint memory uNew;
        
        UserPoint memory lastPoint = UserPoint({
            bias: 0,
            slope: 0,
            ts: currentTime,
            start: _newLocked.start // rounded to prev week
        });

        if (_epoch > 0) {
            lastPoint = _pointHistory[_epoch];       
        }
        
        {
            uint256 lastPointCheckpoint = lastPoint.ts;
            uint256 t_i = (lastPointCheckpoint / WEEK) * WEEK;
            
            for (uint256 i = 0; i < 255; ++i) {
                t_i += WEEK;
                uint128 dSlope;

                if (t_i > block.timestamp) {
                    t_i = block.timestamp;
                } else {
                    dSlope = slopeChanges[t_i];
                }

                lastPoint.bias += lastPoint.slope * (t_i - lastPointCheckpoint).toUint128();
                lastPoint.slope -= dSlope;
                
                lastPointCheckpoint = t_i;
                lastPoint.ts = t_i.toUint48();
                _epoch += 1;

                if (t_i == block.timestamp) {
                    break;
                } else {
                    _pointHistory[_epoch] = lastPoint;
                }
            }
        }

        uNew.slope = ((_newLocked.amount * 1e18 / CurveConstantLib.MAX_TIME).toUint128());
        uNew.bias = _newLocked.amount * 1e18 + uNew.slope * accumulationDur;
        uNew.start = _newLocked.start;
        uNew.ts = currentTime;

        if(currentTime - _newLocked.start >= CurveConstantLib.MAX_TIME) {
            uNew.slope = 0;
        }

        uint48 newEnd = (_newLocked.start + CurveConstantLib.MAX_TIME).toUint48();
        uint128 newSlope = lastPoint.slope + uNew.slope;
        uint208 newBias = lastPoint.bias + uNew.bias;
        uint128 newDSlope = slopeChanges[newEnd] + uNew.slope;

        uint256 userEpoch = userPointEpoch[_tokenId];

        // The `tokenId` already exists..
        if(userEpoch > 0) {
            UserPoint storage p = _userPointHistory[_tokenId][userEpoch];
            uint48 endOld = (p.start + CurveConstantLib.MAX_TIME).toUint48();
            
            if(_newLocked.amount == 0) {
                if(endOld <= uNew.ts) {
                    // we already subtracted p.slope in the above for loop,
                    // because we encounter slopeChanges[endOld] before uNew.ts.
                    newBias -= (p.bias + p.slope * (endOld - p.ts));
                } else {
                    newSlope -= p.slope;
                    newDSlope -= p.slope;
                    newBias -= (p.bias + p.slope * (currentTime - p.ts));
                }
            } else {
                // User already had locked `x` amount on `tokenId=y` and 
                // tries to add more amount on the same `tokenId=y`.
                if(endOld <= uNew.ts) {
                    // Previous point already ends before new point. This means
                    // from newPoint, old slope must not be included anymore.
                    // bias still must be as after end, it doesn't get 0, 
                    // but maxed out constant. 
                    uNew.bias += (p.bias + (endOld - p.ts) * p.slope);
                } else {
                    // Previous point hasn't ended yet, so from newPoint, 
                    // old slope must still be added.
                    uNew.slope += p.slope;
                    uNew.bias += (p.bias + (currentTime - p.ts) * p.slope);
                    if(endOld != newEnd) newDSlope += p.slope;
                }
            }

            // If the end date has not changed and is in future, 
            // we must not clear out slope changes.
            if(endOld != newEnd && endOld >= uNew.ts) {
                slopeChanges[endOld] -= p.slope;
            }
        }
        
        lastPoint.slope = newSlope;
        lastPoint.bias = newBias;
        lastPoint.start = _newLocked.start;

        // TODO: see aerodome..
        epoch = _epoch;
        _pointHistory[_epoch] = lastPoint;

        slopeChanges[newEnd] = newDSlope;

        if (userEpoch != 0 && _userPointHistory[_tokenId][userEpoch].ts == block.timestamp) {
            _userPointHistory[_tokenId][userEpoch] = uNew;
        } else {
            userPointEpoch[_tokenId] = ++userEpoch;
            _userPointHistory[_tokenId][userEpoch] = uNew;
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
