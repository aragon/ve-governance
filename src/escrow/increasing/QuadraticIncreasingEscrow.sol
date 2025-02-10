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
        uint256 ts;
    }

   

    

    // endTime => summed up slopes at that endTime
    mapping(uint256 => uint128) public slopeChanges;

    mapping(uint256 => UserPoint) internal pointHistory;
    mapping(uint256 => UserPoint[1000000000]) internal userPointHistory;
    mapping(uint256 => uint256) public userPointEpoch;

    // ============GIORGI===============


    /*//////////////////////////////////////////////////////////////
                                MATH
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                              CHECKPOINT
    //////////////////////////////////////////////////////////////*/

    /// @notice A checkpoint can be called by the VotingEscrow contract to snapshot the user's voting power
    function checkpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) external nonReentrant {
        // TODO: GIORGI uncomment later...
        // if (msg.sender != escrow) revert OnlyEscrow();
        _checkpoint(_tokenId, _oldLocked, _newLocked);
    }

    function supplyAt(uint256 _timestamp) public view override returns (uint256) {
        return BalanceLogicLibrary.supplyAt(slopeChanges, pointHistory, epoch, _timestamp);
    }

    /// @notice Record gper-user data to checkpoints. Used by VotingEscrow system.
    /// @dev Curve finance style but just for users at this stage
    /// @param _tokenId NFT token ID.
    /// @param _newLocked New locked amount / end lock time for the user
    function _checkpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) internal {
        // this implementation doesn't yet support manual checkpointing
        if (_tokenId == 0) revert InvalidTokenId();
        
        uint256 _epoch = epoch;
        UserPoint memory uNew;
        UserPoint memory uOld;
        

        UserPoint memory lastPoint = UserPoint({
            bias: 0,
            slope: 0,
            ts: block.timestamp
        });

        if (_epoch > 0) {
            lastPoint = pointHistory[_epoch];
        }

        uint256 lastCheckpoint = lastPoint.ts; // This will get modified in a loop.
        uint256 lastPointTs = lastPoint.ts; // This stays the same as we need this value to calculate the bias for our point.

        if (_oldLocked.end  > block.timestamp && _oldLocked.amount > 0) {
            uOld.slope = (_oldLocked.amount / MAXTIME).toUint128();
            uOld.bias = _oldLocked.amount;
        }

        // New lock always starts now.
        uNew.slope = (_newLocked.amount / MAXTIME).toUint128();
        uNew.bias = _newLocked.amount;

        uint128 oldDSlope = slopeChanges[_oldLocked.end];
        uint128 newDSlope = slopeChanges[_newLocked.end];
    
        uint256 t_i = (lastCheckpoint / WEEK) * WEEK;

        {
            uint128 slope;
            for (uint256 i = 0; i < 255; ++i) {
                t_i += WEEK; // Initial value of t_i is always larger than the ts of the last point
                
                if (t_i > block.timestamp) {
                    t_i = block.timestamp;
                } else {
                    slope = slopeChanges[t_i];
                }

                lastPoint.bias += lastPoint.slope * (t_i - lastCheckpoint).toUint128();
                lastPoint.slope -= slope;

                lastCheckpoint = t_i;
                lastPoint.ts = t_i;
                _epoch += 1;

                if (t_i == block.timestamp) {
                    break;
                } else {
                    pointHistory[_epoch] = lastPoint;
                }
            }
        }

        lastPoint.slope += uNew.slope - uOld.slope;
        // If `uOld.bias and uOld.slope` exist, that means user is editting the lock.
        // From that new lock's point onwards, old bias/slope must be discarded from 
        // the calculations, but only from the new lock point's timestamp, before then, 
        // it still should calculate it.
        // Note that we also subtract `uOld.slope * (block.timestamp - lastPointTs)` 
        // because this was added in a loop above..
        lastPoint.bias += (uNew.bias - uOld.bias - uOld.slope * (block.timestamp - lastPointTs)).toUint128();
        

        // TODO: see aerodome..
        epoch = _epoch;
        pointHistory[_epoch] = lastPoint;

        if (_oldLocked.end > block.timestamp) {
            oldDSlope -= uOld.slope;

            if (_newLocked.end == _oldLocked.end) {
                oldDSlope += uNew.slope;
            }

            slopeChanges[_oldLocked.end] = oldDSlope;
        }

        if (_newLocked.end > block.timestamp) {
            if ((_newLocked.end > _oldLocked.end)) {
                newDSlope += uNew.slope;
                slopeChanges[_newLocked.end] = newDSlope;
            }
            // else we already recorded it in above..
        }

        uNew.ts = block.timestamp;
        uint256 userEpoch = userPointEpoch[_tokenId];
        if (userEpoch != 0 && userPointHistory[_tokenId][userEpoch].ts == block.timestamp) {
            userPointHistory[_tokenId][userEpoch] = uNew;
        } else {
            userPointEpoch[_tokenId] = ++userEpoch;
            userPointHistory[_tokenId][userEpoch] = uNew;
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
