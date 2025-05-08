/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {
    IVotingEscrowIncreasingV1_2_0 as IVotingEscrow
} from "@escrow/IVotingEscrowIncreasing_v1_2_0.sol";

import {
    IEscrowCurveIncreasingV1_2_0_NoSupply as IEscrowCurve,
    IEscrowCurveCore,
    IEscrowCurveTokenV1_2_0 as IEscrowCurveToken
} from "@curve/IEscrowCurveIncreasing_v1_2_0.sol";
import {IClockUser, IClockV1_2_0 as IClock} from "@clock/IClock_v1_2_0.sol";

// libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SignedFixedPointMath} from "@libs/SignedFixedPointMathLib.sol";
import {CurveConstantLib} from "@libs/CurveConstantLib.sol";

// contracts
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable as ReentrancyGuard
} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {
    DaoAuthorizableUpgradeable as DaoAuthorizable
} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizableUpgradeable.sol";

/// @title Linear Increasing Escrow
contract LinearIncreasingCurveNoSupply is
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
    uint48 public warmupPeriod;

    /// @dev tokenId => tokenPointIntervals => TokenPoint
    /// @dev The Array is fixed so we can write to it in the future
    /// This implementation means that very short intervals may be challenging
    mapping(uint256 => TokenPoint[1_000_000_000]) internal _tokenPointHistory;

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

    error UpgradeNotPossible();

    /*//////////////////////////////////////////////////////////////
                              INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
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

        __ReentrancyGuard_init();
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));

        // other initializers are empty
    }

    /*//////////////////////////////////////////////////////////////
                              CURVE COEFFICIENTS
    //////////////////////////////////////////////////////////////*/

    /// @return The coefficient for the curve's linear term, for the given amount
    function _getLinearCoeff(uint256 amount) internal pure returns (int256) {
        return amount.toInt256() * SHARED_LINEAR_COEFFICIENT;
    }

    /// @return The constant coefficient of the increasing curve, for the given amount
    /// @dev In this case, the constant term is 1 so we just case the amount
    function _getConstantCoeff(uint256 amount) public pure returns (int256) {
        return amount.toInt256() * SHARED_CONSTANT_COEFFICIENT;
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
    /// @dev Note that the returned value includes the linear and constant
    ///     coefficients multiplication, which is not the case in `getBias`.
    function getBias(uint256 timeElapsed, uint256 amount) public view returns (uint256) {
        int256[3] memory coefficients = _getCoefficients(amount);
        uint256 bias = _getBias(boundElapsedMaxTime(timeElapsed), coefficients[0], coefficients[1]);

        return bias / 1e18;
    }

    /// @notice Returns the bias for the given time elapsed and amount, up to the maximum time
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
    function isWarm(uint256 _tokenId) public view returns (bool) {
        return _isWarm(_tokenId, block.timestamp);
    }

    function isWarm(uint256 _tokenId, uint48 _ts) public view returns (bool) {
        return _isWarm(_tokenId, _ts);
    }

    function _isWarm(uint256 _tokenId, uint256 _ts) public view returns (bool) {
        IVotingEscrow.LockedBalance memory locked = IVotingEscrow(escrow).locked(_tokenId);

        // This could occur if user withdraw in which case lock is removed.
        // In such case, `_tokenId` is treated as if it never existed
        // in which case we anyways return false.
        if (locked.amount == 0) return false;

        return _ts > locked.start + warmupPeriod;
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
        // bind for backwards compatibility
        point.bias = uint(point.coefficients[0]) / 1e18;
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

        if (!_isWarm(_tokenId, _t)) return 0;

        int256 bias = lastPoint.coefficients[0];
        int256 slope = lastPoint.coefficients[1];

        // Note that very first point is saved at index 1.
        TokenPoint memory originalPoint = _tokenPointHistory[_tokenId][1];

        uint256 maxTime_ = maxTime();
        uint256 end = originalPoint.checkpointTs + maxTime_;

        // If the point was created before the upgrade:
        //    it will have `checkpointTs` greater than `writtenTs`.
        //    bias would have been stored as just the amount(without bonus).
        // In such case, we make writtenTs equal to avoid checkpointTs greater.
        // This ensures that behaviour after and before upgrade are same.
        if (originalPoint.checkpointTs > originalPoint.writtenTs) {
            originalPoint.writtenTs = originalPoint.checkpointTs;
        }

        if (lastPoint.checkpointTs > lastPoint.writtenTs) {
            lastPoint.writtenTs = lastPoint.checkpointTs;
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

        // Get the slope and bias for `_newLocked`...
        (int256 newLockBias, int256 newLockSlope) = _getBiasAndSlope(
            block.timestamp - _newLocked.start,
            _newLocked.amount
        );

        uint256 newEnd = _newLocked.start + maxTime();

        // If the new lock is mature, don't include the slope.
        if (block.timestamp >= newEnd) {
            newLockSlope = 0;
        }

        uint256 tokenLatestIndex = tokenPointLatestIndex[_tokenId];

        // Create new token point and store.
        TokenPoint memory tNew;
        tNew.writtenTs = uint128(block.timestamp);
        tNew.checkpointTs = _newLocked.start;
        tNew.coefficients = [newLockBias, newLockSlope, 0];

        // Record the latest token point.
        _storeLatestTokenPoint(tNew, _tokenId, tokenLatestIndex);
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
