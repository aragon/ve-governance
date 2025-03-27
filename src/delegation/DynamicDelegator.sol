/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotingEscrowIncreasingV1_4_0 as IVotingEscrow, IVotingEscrowIncreasing as IVE} from "@escrow/IVotingEscrowIncreasing_v1_4_0.sol";
import {IEscrowCurveIncreasingV1_4_0 as IEscrowCurve, IEscrowCurveGlobal, IEscrowCurveCore, IEscrowCurveTokenV1_4_0 as IEscrowCurveToken} from "@curve/IEscrowCurveIncreasing_v1_4_0.sol";

import {IClockUser, IClockV1_4_0 as IClock} from "@clock/IClock_v1_4_0.sol";
import {IClockSeason} from "@clock/IClockSeason.sol";

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

interface IOwnedTokens {
    function ownedTokens(address _owner) external view returns (uint256[] memory);
}

interface IGlobalPoint {
    struct GlobalPoint {
        int256 bias;
        int256 slope;
        uint48 writtenTs;
    }

    error InvalidTokenId();
    error InvalidCheckpoint();
}
contract DynamicDelegator is IGlobalPoint, ReentrancyGuard, DaoAuthorizable, UUPSUpgradeable {
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

    int256 private constant SHARED_QUADRATIC_COEFFICIENT =
        CurveConstantLib.SHARED_QUADRATIC_COEFFICIENT;

    int256 private constant SHARED_LINEAR_COEFFICIENT = CurveConstantLib.SHARED_LINEAR_COEFFICIENT;

    int256 private constant SHARED_CONSTANT_COEFFICIENT =
        CurveConstantLib.SHARED_CONSTANT_COEFFICIENT;

    uint256 private constant MAX_EPOCHS = CurveConstantLib.MAX_EPOCHS;

    error UpgradeNotPossible();

    ///////// DELEGATION ////////

    /* 
        so the cases we have 

	1. first time delegating, ids not a gas concern
	2. first time delegating, many ids - gas concern
	3. updating a delegation, ids not a gas concern
	4. updating a delegation, many ids - gas concern
	5. warmups or cooldowns

	ok so first thing. I think we require that voting power is > 0 to delegate. We can fetch this from the curve. This covers warmups but does make them kinda annoying. 
	  Recommend the DAO doesn't use a warmup


	what we could do is have a simple 2 stage delegation.
	  first is setting the delegate.
	  second is delegating the token Ids one at a time.


	what we need to make sure is that updating a delegate happens in a predictable way. 

	easiest way here is to ensure that all tokens are undelegated before allowing the setting of a new delegate. 
	how can we track this? 
	every time we delegate we set tokenIsDelegated and ++numberOfDelegatedTokens 
	you can call delegate when numberOfDelegatedTokens = 0

	when transferring we just call delegates(address) remove from a and add to b




	*/

    mapping(address => uint256) public delegatePointLatestIndex;
    mapping(address => address) public delegates;

    // delegate => tokenId => scheduledSlopeReductions
    mapping(address => mapping(uint256 => int256)) public delegatedSlopeChanges;

    // delegate => index => Point
    mapping(address => mapping(uint256 => GlobalPoint)) internal _delegatePointHistory;

    event Delegated(uint indexed tokenId, address indexed delegatee);
    event AutoDelegationSet(address indexed delegate, bool enabled);

    // holder of veTokens => enabled
    mapping(address => bool) public autoDelegationEnabled;

    // tokenId => isCurrentlyDelegated
    mapping(uint => bool) public tokenIsDelegated;

    mapping(address => uint) public numberOfDelegatedTokens;

    function setAutoDelegation(bool _enabled) external {
        autoDelegationEnabled[msg.sender] = _enabled;
        emit AutoDelegationSet(msg.sender, _enabled);
    }

    function delegate(uint256[] memory tokenIds) public {
        address delegatee = delegates[msg.sender];
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint tokenId = tokenIds[i];
            require(
                IVotingEscrow(escrow).isApprovedOrOwner(msg.sender, tokenId),
                "not approved or owner"
            );
            IVotingEscrow.LockedBalance memory _fromLocked;

            IVotingEscrow.LockedBalance memory _newLocked = IVotingEscrow(escrow).locked(tokenId);
            // todo could require vp here
            require(_newLocked.amount > 0, "delegate: token must be locked");

            // you can only delegate once but you can delegate tokens one at a time
            if (!tokenIsDelegated[tokenIds[i]]) {
                _delegate(tokenId, _fromLocked, _newLocked, delegatee);
            }
        }
    }

    function undelegate(uint256[] memory tokenIds) public {
        address delegatee = delegates[msg.sender];
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint tokenId = tokenIds[i];
            require(
                IVotingEscrow(escrow).isApprovedOrOwner(msg.sender, tokenId),
                "not approved or owner"
            );
            IVotingEscrow.LockedBalance memory _fromLocked;
            IVotingEscrow.LockedBalance memory _newLocked; // zero it

            // you can only undelegate once but you can undelegate tokens one at a time
            if (tokenIsDelegated[tokenIds[i]]) {
                _delegate(tokenId, _fromLocked, _newLocked, delegatee);
            }
        }
    }

    function delegate(address delegatee) public {
        require(
            numberOfDelegatedTokens[msg.sender] == 0,
            "delegate: all tokens must be undelegated before setting a new delegate"
        );
        delegates[msg.sender] = delegatee;

        if (autoDelegationEnabled[msg.sender]) {
            // get owned tokens
            uint256[] memory tokenIds = IOwnedTokens(escrow).ownedTokens(msg.sender);
            delegate(tokenIds);
        }
    }

    // tmp for stack too deep
    struct Variables {
        GlobalPoint lastPoint;
        uint256 _delegatePointLatestIndex;
    }

    function _delegate(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _fromLocked,
        IVotingEscrow.LockedBalance memory _newLocked,
        address _delegatee // todo - zero address
    ) internal {
        Variables memory vars;
        // this implementation doesn't yet support manual checkpointing

        if (_tokenId == 0) revert InvalidTokenId();

        if (_newLocked.start < _fromLocked.start) {
            revert InvalidCheckpoint();
        }

        vars._delegatePointLatestIndex = delegatePointLatestIndex[_delegatee];

        // Get the slope and bias for `_newLocked`...
        (int256 newLockBias, int256 newLockSlope) = _getBiasAndSlope(
            block.timestamp - _newLocked.start,
            _newLocked.amount
        );

        vars.lastPoint = GlobalPoint({bias: 0, slope: 0, writtenTs: uint48(block.timestamp)});

        if (vars._delegatePointLatestIndex > 0) {
            vars.lastPoint = _delegatePointHistory[_delegatee][vars._delegatePointLatestIndex];
        }

        // Get slope changes for the delegate
        mapping(uint256 => int256) storage delegatedSlopeChanges_ = delegatedSlopeChanges[
            _delegatee
        ];

        {
            uint256 checkpointInterval = IClock(clock).checkpointInterval();

            uint256 lastPointCheckpoint = vars.lastPoint.writtenTs;
            uint256 t_i = (lastPointCheckpoint / checkpointInterval) * checkpointInterval;

            for (uint256 i = 0; i < 255; ++i) {
                t_i += checkpointInterval;
                int256 dSlope;

                if (t_i > block.timestamp) {
                    t_i = block.timestamp;
                } else {
                    dSlope = delegatedSlopeChanges_[t_i];
                }

                vars.lastPoint.bias += vars.lastPoint.slope * int256(t_i - lastPointCheckpoint);
                vars.lastPoint.slope -= dSlope;

                if (vars.lastPoint.slope < 0) vars.lastPoint.slope = 0;
                if (vars.lastPoint.bias < 0) vars.lastPoint.bias = 0;

                lastPointCheckpoint = t_i;
                vars.lastPoint.writtenTs = uint48(t_i);
                vars._delegatePointLatestIndex += 1;

                if (t_i == block.timestamp) {
                    break;
                } else {
                    _delegatePointHistory[_delegatee][vars._delegatePointLatestIndex] = vars
                        .lastPoint;
                }
            }
        }

        uint256 newEnd = _newLocked.start + maxTime();
        int256 newDSlope = delegatedSlopeChanges_[newEnd];

        // If the newLocked hasn't ended, add its slope
        // to the latest delgate point. newLocked could be ended in case of
        // merge, when a token is already mature.
        if (block.timestamp < newEnd) {
            vars.lastPoint.slope += newLockSlope;
            newDSlope += newLockSlope;
        }

        vars.lastPoint.bias += newLockBias;

        // we assume the token exists
        {
            uint256 _fromLockedEnd = _fromLocked.start + maxTime();

            // Get the slope and bias for `_fromLocked`...
            (int256 oldLockBias, int256 oldLockSlope) = _getBiasAndSlope(
                block.timestamp - _fromLocked.start,
                _fromLocked.amount
            );

            // undelegating
            if (_newLocked.amount == 0) {
                vars.lastPoint.bias -= oldLockBias;
                if (_fromLockedEnd > block.timestamp) {
                    // If `fromLocked` ends in the future, we must subtract its slope
                    // as from this moment on(due to making amount=0),
                    // the slope must not be included. Note that in case the end is
                    // in the past, we already subtracted it inside the above loop.
                    vars.lastPoint.slope -= oldLockSlope;
                    newDSlope -= oldLockSlope;

                    // DELEGATION: decrement the number of delegated tokens
                    numberOfDelegatedTokens[_delegatee] -= 1;
                    tokenIsDelegated[_tokenId] = false;
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

                // DELEGATION: increment the number of delegated tokens
                numberOfDelegatedTokens[_delegatee] += 1;
                tokenIsDelegated[_tokenId] = true;
            }

            if (_fromLockedEnd != newEnd && _fromLockedEnd >= block.timestamp) {
                int256 oldDSlope = delegatedSlopeChanges_[_fromLockedEnd] - oldLockSlope;
                delegatedSlopeChanges_[_fromLockedEnd] = oldDSlope < 0 ? int256(0) : oldDSlope;
            }
        }

        if (vars.lastPoint.slope < 0) vars.lastPoint.slope = 0;
        if (vars.lastPoint.bias < 0) vars.lastPoint.bias = 0;

        // TODO: see aerodome..
        delegatePointLatestIndex[_delegatee] = vars._delegatePointLatestIndex;
        _delegatePointHistory[_delegatee][vars._delegatePointLatestIndex] = vars.lastPoint;

        delegatedSlopeChanges_[newEnd] = newDSlope < 0 ? int256(0) : newDSlope;

        emit Delegated(_tokenId, _delegatee);
    }

    /// @notice Binary search to get the delegate point index at or prior to a given timestamp
    /// @dev If a checkpoint does not exist prior to the timestamp, this will return 0.
    /// @param _timestamp The timestamp to get a checkpoint at.
    /// @return Global point index
    function getPastDelegatePointIndex(
        address _delegateAddress,
        uint256 _timestamp
    ) internal view returns (uint256) {
        uint delegatePointLatestIndex_ = delegatePointLatestIndex[_delegateAddress];
        if (delegatePointLatestIndex_ == 0) return 0;
        mapping(uint256 => GlobalPoint) storage delegatePointHistory_ = _delegatePointHistory[
            _delegateAddress
        ];
        // First check most recent balance
        if (delegatePointHistory_[delegatePointLatestIndex_].writtenTs <= _timestamp)
            return (delegatePointLatestIndex_);
        // Next check implicit zero balance
        if (delegatePointHistory_[1].writtenTs > _timestamp) return 0;

        uint256 lower = 0;
        uint256 upper = delegatePointLatestIndex_;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            GlobalPoint storage delegatePoint = delegatePointHistory_[center];
            if (delegatePoint.writtenTs == _timestamp) {
                return center;
            } else if (delegatePoint.writtenTs < _timestamp) {
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
    function _delegateBalanceAt(
        address _delegateAddress,
        uint256 _timestamp
    ) internal view returns (uint256) {
        uint256 epoch_ = getPastDelegatePointIndex(_delegateAddress, _timestamp);
        // epoch 0 is an empty point
        if (epoch_ == 0) return 0;
        GlobalPoint memory _point = _delegatePointHistory[_delegateAddress][epoch_];
        int256 bias = _point.bias;
        int256 slope = _point.slope;
        uint256 ts = _point.writtenTs; // changes in for loop.

        mapping(uint256 => int256) storage delegatedSlopeChanges_ = delegatedSlopeChanges[
            _delegateAddress
        ];

        uint256 checkpointInterval = IClock(clock).checkpointInterval();

        uint256 t_i = (ts / checkpointInterval) * checkpointInterval;

        for (uint256 i = 0; i < 255; ++i) {
            t_i += checkpointInterval;
            int256 dSlope = 0;
            if (t_i > _timestamp) {
                t_i = _timestamp;
            } else {
                dSlope = delegatedSlopeChanges_[t_i];
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

    function votingPower(address _delegateAddress) public view returns (uint256) {
        return _delegateBalanceAt(_delegateAddress, block.timestamp);
    }

    function votingPowerAt(
        address _delegateAddress,
        uint256 _timestamp
    ) public view returns (uint256) {
        return _delegateBalanceAt(_delegateAddress, _timestamp);
    }
    /*//////////////////////////////////////////////////////////////
                              INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    constructor() {
        // _disableInitializers();
    }

    /// @param _escrow VotingEscrow contract address
    function initialize(address _escrow, address _dao, address _clock) external initializer {
        escrow = _escrow;
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
