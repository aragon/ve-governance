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

    /// @notice tokenId => point epoch: incremented on a per-user basis
    mapping(uint256 => uint256) public userPointEpoch;

    /// @notice The warmup period for the curve
    uint256 public warmupPeriod;

    /// @dev tokenId => userPointEpoch => warmup
    mapping(uint256 => mapping(uint256 => uint256)) internal _userPointWarmup;

    /// @dev tokenId => userPointEpoch => UserPoint
    /// @dev The Array is fixed so we can write to it in the future
    /// This implementation means that very short intervals may be challenging
    mapping(uint256 => UserPoint[1_000_000_000]) internal _userPointHistory;

    /*//////////////////////////////////////////////////////////////
                                MATH
    //////////////////////////////////////////////////////////////*/

    /// @dev precomputed coefficients of the quadratic curve
    int256 private constant SHARED_QUADRATIC_COEFFICIENT =
        CurveConstantLib.SHARED_QUADRATIC_COEFFICIENT;

    int256 private constant SHARED_LINEAR_COEFFICIENT = CurveConstantLib.SHARED_LINEAR_COEFFICIENT;

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
        uint256 _warmupPeriod,
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
        return (SignedFixedPointMath.toFP(amount.toInt256()));
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

    function setWarmupPeriod(uint256 _warmupPeriod) external auth(CURVE_ADMIN_ROLE) {
        warmupPeriod = _warmupPeriod;
        emit WarmupSet(_warmupPeriod);
    }

    /// @notice Returns whether the NFT is warm
    function isWarm(uint256 tokenId) public view returns (bool) {
        uint256 _epoch = _getPastUserPointIndex(tokenId, block.timestamp);
        UserPoint memory point = _userPointHistory[tokenId][_epoch];
        if (point.bias == 0) return false;
        else return _isWarm(tokenId, _epoch, block.timestamp);
    }

    function _isWarm(uint256 _tokenId, uint256 _userEpoch, uint256 t) public view returns (bool) {
        return t >= _userPointWarmup[_tokenId][_userEpoch];
    }

    /*//////////////////////////////////////////////////////////////
                              BALANCE
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the UserPoint at the passed epoch
    /// @param _tokenId The NFT to return the UserPoint for
    /// @param _userEpoch The epoch to return the UserPoint at
    function userPointHistory(
        uint256 _tokenId,
        uint256 _userEpoch
    ) external view returns (UserPoint memory) {
        return _userPointHistory[_tokenId][_userEpoch];
    }

    /// @notice Binary search to get the user point index for a token id at or prior to a given timestamp
    /// Once we have the point, we can apply the bias calculation to get the voting power.
    /// @dev If a user point does not exist prior to the timestamp, this will return 0.
    function _getPastUserPointIndex(
        uint256 _tokenId,
        uint256 _timestamp
    ) internal view returns (uint256) {
        uint256 _userEpoch = userPointEpoch[_tokenId];
        if (_userEpoch == 0) return 0;

        // if the most recent point is before the timestamp, return it
        if (_userPointHistory[_tokenId][_userEpoch].ts <= _timestamp) return (_userEpoch);

        // Check if the first balance is after the timestamp
        // this means that the first epoch has yet to start
        if (_userPointHistory[_tokenId][1].ts > _timestamp) return 0;

        uint256 lower = 0;
        uint256 upper = _userEpoch;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            UserPoint storage userPoint = _userPointHistory[_tokenId][center];
            if (userPoint.ts == _timestamp) {
                return center;
            } else if (userPoint.ts < _timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    function votingPowerAt(uint256 _tokenId, uint256 _t) external view returns (uint256) {
        uint256 _epoch = _getPastUserPointIndex(_tokenId, _t);

        // epoch 0 is an empty point
        if (_epoch == 0) return 0;
        UserPoint memory lastPoint = _userPointHistory[_tokenId][_epoch];

        if (!_isWarm(_tokenId, _epoch, _t)) return 0;
        uint256 timeElapsed = _t - lastPoint.ts;

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

    /// @notice Record gper-user data to checkpoints. Used by VotingEscrow system.
    /// @dev Curve finance style but just for users at this stage
    /// @param _tokenId NFT token ID. No user checkpoint if 0
    /// @param _newLocked New locked amount / end lock time for the user
    function _checkpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory /* _oldLocked */,
        IVotingEscrow.LockedBalance memory _newLocked
    ) internal {
        // this implementation doesn't yet support manual checkpointing
        if (_tokenId == 0) revert InvalidTokenId();

        // instantiate a new, empty user point
        UserPoint memory uNew;
        uint amount = _newLocked.amount;
        bool isExiting = amount == 0;

        if (!isExiting) {
            int256[3] memory coefficients = _getCoefficients(amount);
            // for a new lock, write the base bias (elapsed == 0)
            uNew.coefficients = coefficients;
            uNew.bias = _getBias(0, coefficients);
        }
        // write the new timestamp - in the case of an increasing curve
        // we align the checkpoint to the start of the upcoming deposit interval
        // to ensure global slope changes can be scheduled
        // NOTE: the above global functionality is not implemented in this version of the contracts
        uNew.ts = _newLocked.start;

        // check to see if we have an existing epoch for this token
        uint256 userEpoch = userPointEpoch[_tokenId];

        // If this is a new timestamp, increment the epoch
        if (userEpoch == 0 || _userPointHistory[_tokenId][userEpoch].ts != uNew.ts) {
            userPointEpoch[_tokenId] = ++userEpoch;
        }

        // Record the new point and warmup period
        _userPointHistory[_tokenId][userEpoch] = uNew;

        // if the user is exiting, we don't need to set the warmup period
        if (!isExiting) {
            _userPointWarmup[_tokenId][userEpoch] = block.timestamp + warmupPeriod;
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
    uint256[44] private __gap;
}
