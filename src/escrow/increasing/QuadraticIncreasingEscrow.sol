// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVotingEscrowIncreasing as IVotingEscrow} from "@escrow-interfaces/IVotingEscrowIncreasing.sol";
import {IEscrowCurveIncreasing as IEscrowCurve} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";

// libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EpochDurationLib} from "@libs/EpochDurationLib.sol";
import {SignedFixedPointMath} from "@libs/SignedFixedPointMathLib.sol";

// contracts
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {console2 as console} from "forge-std/console2.sol";

/// @title Quadratic Increasing Escrow
contract QuadraticIncreasingEscrow is IEscrowCurve, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCast for int256;
    using SafeCast for uint256;
    using SignedFixedPointMath for int256;

    error OnlyEscrow();

    /// @notice The VotingEscrow contract address
    address public escrow;

    /// @notice timestamp => UserPoint[]
    /// @dev The Array is fixed so we can write to it in the future
    /// This implementation means that very short intervals may be challenging
    mapping(uint256 => UserPoint[1_000_000_000]) internal _userPointHistory;

    /// @notice tokenId => point epoch: incremented on a per-user basis
    mapping(uint256 => uint256) public userPointEpoch;

    /// @notice The duration of each period
    /// @dev used to calculate the value of t / PERIOD_LENGTH
    uint256 public constant period = EpochDurationLib.EPOCH_DURATION;

    // todo: should this be in voting or balance?
    uint256 public constant WARMUP_PERIOD = 3 days;

    /*//////////////////////////////////////////////////////////////
                              MATH CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev FP constants for 1, 2, and 7
    int256 private immutable SD1 = SignedFixedPointMath.toFP(1);
    int256 private immutable SD2 = SignedFixedPointMath.toFP(2);
    int256 private immutable SD7 = SignedFixedPointMath.toFP(7);

    /// @dev t = timestamp / 2 weeks
    int256 private PERIOD_LENGTH = SignedFixedPointMath.toFP(int256(period));
    int256 private PERIOD_LENGTH_SQUARED = PERIOD_LENGTH.pow(SignedFixedPointMath.toFP(2));

    /// @dev precomputed coefficients of the quadratic curve
    /// votingPower = amount * ((1/7)t^2 + (2/7)t + 1)
    int256 private SHARED_QUADRATIC_COEFFICIENT;
    int256 private SHARED_LINEAR_COEFFICIENT;

    /// @param _escrow VotingEscrow contract address
    constructor(address _escrow) {
        escrow = _escrow;

        /// @dev precomputed coefficients of the quadratic curve
        /// votingPower = amount * ((1/7)t^2 + (2/7)t + 1)
        SHARED_QUADRATIC_COEFFICIENT = SD1.div(SD7.mul(PERIOD_LENGTH_SQUARED));
        SHARED_LINEAR_COEFFICIENT = SD2.div(SD7.mul(PERIOD_LENGTH));
    }

    /*//////////////////////////////////////////////////////////////
                              CURVE COEFFICIENTS
    //////////////////////////////////////////////////////////////*/

    /// @return The coefficient for the quadratic term of the quadratic curve, for the given amount
    function _getQuadraticCoeff(uint256 amount) internal view returns (int256) {
        // 1 / (7 * 2 weeks^2)
        return (SignedFixedPointMath.toFP(amount.toInt256()).mul(SHARED_QUADRATIC_COEFFICIENT));
    }

    /// @return The coefficient for the linear term of the quadratic curve, for the given amount
    function _getLinearCoeff(uint256 amount) internal view returns (int256) {
        // 2 / 7 * 2 weeks
        return (SignedFixedPointMath.toFP(amount.toInt256())).mul(SHARED_LINEAR_COEFFICIENT);
    }

    /// @return The constant coefficient of the quadratic curve, for the given amount
    /// @dev In this case, the constant term is 1 so we just case the amount
    function _getConstantCoeff(uint256 amount) public pure returns (int256) {
        return (SignedFixedPointMath.toFP(amount.toInt256()));
    }

    /// @return The coefficients of the quadratic curve, for the given amount
    /// @dev The coefficients are returned in the order [constant, linear, quadratic]
    function _getCoefficients(uint256 amount) public view returns (int256[3] memory) {
        return [_getConstantCoeff(amount), _getLinearCoeff(amount), _getQuadraticCoeff(amount)];
    }

    /// @return The coefficients of the quadratic curve, for the given amount
    /// @dev The coefficients are returned in the order [constant, linear, quadratic, cubic]
    /// and are converted to regular 256-bit signed integers instead of their fixed-point representation
    function getCoefficients(uint256 amount) public view returns (int256[4] memory) {
        int256[3] memory coefficients = _getCoefficients(amount);

        return [
            SignedFixedPointMath.fromFP(coefficients[0]),
            SignedFixedPointMath.fromFP(coefficients[1]),
            SignedFixedPointMath.fromFP(coefficients[2]),
            0
        ];
    }

    /*//////////////////////////////////////////////////////////////
                              CURVE BIAS
    //////////////////////////////////////////////////////////////*/

    /// @return The bias of the quadratic curve, for the given amount and time elapsed, irrespective of boundary
    /// @param timeElapsed number of seconds over which to evaluate the bias
    /// @param amount the amount of the curve to evaluate the bias for
    function getBiasUnbound(uint timeElapsed, uint amount) public view returns (uint256) {
        int256[3] memory coefficients = _getCoefficients(amount);
        return _getBiasUnbound(timeElapsed, coefficients);
    }

    function _getBiasUnbound(uint256 timeElapsed, int256[3] memory coefficients) public view returns (uint256) {
        int256 quadratic = coefficients[2];
        int256 linear = coefficients[1];
        int256 const = coefficients[0];

        int256 t = SignedFixedPointMath.toFP(timeElapsed.toInt256());

        // bias = a.t^2 + b.t + c
        int256 bias = quadratic.mul(t.pow(SD2)).add(linear.mul(t)).add(const);
        // never return negative values
        // in the increasing case, this should never happen
        return bias.lt((0)) ? uint256(0) : SignedFixedPointMath.fromFP((bias)).toUint256();
    }

    // The above assumes a boundary - this is applicable for most use cases and it is trivial to set
    // a sentinel value of max(uint256) if you want an unbounded increase
    function getBias(uint256 timeElapsed, uint256 amount, uint256 boundary) public view returns (uint256) {
        uint256 bias = getBiasUnbound(timeElapsed, amount);
        return bias > boundary ? boundary : bias;
    }

    function getBias(uint256 timeElapsed, uint256 amount) public view returns (uint256) {
        uint256 MAX_VOTING_AMOUNT = 6 * amount;
        return getBias(timeElapsed, amount, MAX_VOTING_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                              Warmup
    //////////////////////////////////////////////////////////////*/

    function warmupPeriod() external pure returns (uint256) {
        return WARMUP_PERIOD;
    }

    function _isWarm(UserPoint memory point, uint256 t) public pure returns (bool) {
        return t > point.ts + WARMUP_PERIOD;
    }

    /// @notice Returns whether the NFT is warm
    function isWarm(uint256 tokenId) public view returns (bool) {
        uint256 _epoch = _getPastUserPointIndex(tokenId, block.timestamp);
        UserPoint memory point = _userPointHistory[tokenId][_epoch];
        if (point.bias == 0) return false;
        else return _isWarm(point, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                              BALANCE
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the UserPoint at the passed epoch
    /// @param _tokenId The NFT to return the UserPoint for
    /// @param _userEpoch The epoch to return the UserPoint at
    function userPointHistory(uint256 _tokenId, uint256 _userEpoch) external view returns (UserPoint memory) {
        return _userPointHistory[_tokenId][_userEpoch];
    }

    /// @notice Binary search to get the user point index for a token id at or prior to a given timestamp
    /// @dev If a user point does not exist prior to the timestamp, this will return 0.
    function _getPastUserPointIndex(uint256 _tokenId, uint256 _timestamp) internal view returns (uint256) {
        uint256 _userEpoch = userPointEpoch[_tokenId];
        if (_userEpoch == 0) return 0;
        // First check most recent balance
        if (_userPointHistory[_tokenId][_userEpoch].ts <= _timestamp) return (_userEpoch);
        // Next check implicit zero balance
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
        if (!_isWarm(lastPoint, _t)) return 0;
        uint256 timeElapsed = _t - lastPoint.ts;

        // in the increasing case, we don't allow changes to locks, so the ts and blk are
        // equivalent to the creation time of the lock
        return getBias(timeElapsed, lastPoint.bias);
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
        IVotingEscrow.LockedBalance memory,
        IVotingEscrow.LockedBalance memory _newLocked
    ) internal {
        UserPoint memory uNew;

        if (_tokenId != 0) {
            if (_newLocked.amount > 0) {
                uint256 amount = _newLocked.amount;
                uNew.coefficients = getCoefficients(amount);
                uNew.bias = getBias(0, amount);
            }
            // If timestamp of last user point is the same, overwrite the last user point
            // Else record the new user point into history
            // Exclude epoch 0
            uNew.ts = block.timestamp;
            uNew.blk = block.number;
            // check to see if we have an existing epoch for this timestamp
            uint256 userEpoch = userPointEpoch[_tokenId];

            if (
                // if we do have a point AND
                // if we've already recorded a point for this timestamp
                userEpoch != 0 && _userPointHistory[_tokenId][userEpoch].ts == block.timestamp
            ) {
                // overwrite the last point
                _userPointHistory[_tokenId][userEpoch] = uNew;
            } else {
                // otherwise, create a new epoch by incrementing the userEpoch
                // and record the new point
                userPointEpoch[_tokenId] = ++userEpoch;
                _userPointHistory[_tokenId][userEpoch] = uNew;
            }
        }
    }
}
