/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    IVotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {
    SafeCastUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable as ReentrancyGuard
} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {
    IVotingEscrowIncreasingV1_2_0 as IVotingEscrow
} from "@escrow/IVotingEscrowIncreasing_v1_2_0.sol";
import {VotingEscrowV1_2_0 as VotingEscrow} from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";

import {IClockUser, IClockV1_2_0 as IClock} from "@clock/IClock_v1_2_0.sol";

import {PluginUUPSUpgradeable} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";
import {IEscrowIVotesAdapter} from "./IEscrowIVotesAdapter.sol";
import {ISimpleGaugeVoterV1_2_0 as ISimpleGaugeVoter} from "@voting/ISimpleGaugeVoter_v1_2_0.sol";
import {console2 as console} from "forge-std/console2.sol";
import {CurveConstantLib} from "@libs/CurveConstantLib.sol";
import {SignedFixedPointMath} from "@libs/SignedFixedPointMathLib.sol";

contract EscrowIVotesAdapter is
    IClockUser,
    ReentrancyGuard,
    IEscrowIVotesAdapter,
    IVotesUpgradeable,
    PluginUUPSUpgradeable
{
    using SafeCastUpgradeable for uint256;

    /// @notice The Gauge admin can can create and manage voting gauges for token holders
    bytes32 public constant DELEGATION_ADMIN_ROLE = keccak256("DELEGATION_ADMIN");

    /// @notice Address of the voting escrow contract that will track voting power
    address public escrow;

    /// @notice Clock contract for epoch duration
    address public clock;

    /// @notice Voter contract
    address public voter;

    struct Delegation {
        address delegatee;
        uint256 timestamp;
    }

    mapping(address => mapping(uint256 => int256)) internal slopeChanges;
    mapping(address => mapping(uint256 => GlobalPoint)) internal pointHistory;
    mapping(address => uint256) public latestPointIndex;

    mapping(address => mapping(uint256 => int256)) internal selfSlopeChanges;
    mapping(address => mapping(uint256 => GlobalPoint)) internal selfPointHistory;
    mapping(address => uint256) public selfLatestPointIndex;

    mapping(address => Delegation[]) private delegateesHistory;

    mapping(uint256 => bool) public tokenIsDelegated;
    mapping(address => uint) public numberOfDelegatedTokens;
    mapping(address => bool) public autoDelegationEnabled;

    int256 private sharedLinearCoefficient;
    int256 private sharedConstantCoefficient;
    uint256 private maxTime;

    /*///////////////////////////////////////////////////////////////
                            Initialization
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(address _dao, address _escrow, address _clock) external initializer {
        __PluginUUPSUpgradeable_init(IDAO(_dao));
        __ReentrancyGuard_init();
        escrow = _escrow;
        clock = _clock;

        maxTime = IClock(clock).epochDuration() * CurveConstantLib.MAX_EPOCHS;
    }

    function setVoter(address _voter) external auth(DELEGATION_ADMIN_ROLE) {
        voter = _voter;
    }

    function setAutoDelegation(bool _enabled) external {
        address sender = _msgSender();

        autoDelegationEnabled[sender] = _enabled;
        emit AutoDelegationSet(sender, _enabled);
    }

    function delegate(address _delegatee) public {
        address sender = _msgSender();

        if (numberOfDelegatedTokens[sender] != 0) {
            revert DelegationNotAllowed();
        }

        address oldDelegatee = delegates(sender);

        delegateesHistory[sender].push(
            Delegation({delegatee: _delegatee, timestamp: block.timestamp})
        );

        if (autoDelegationEnabled[sender]) {
            uint256[] memory tokenIds = VotingEscrow(escrow).ownedTokens(sender);
            delegate(tokenIds);
        }

        emit DelegateChanged(sender, oldDelegatee, _delegatee);
    }

    function delegate(uint256[] memory _tokenIds) public {
        address sender = _msgSender();
        address delegatee = delegates(sender);

        if (delegatee == address(0)) {
            revert DelegateeNotSet();
        }

        int256 totalBias;
        int256 totalSlope;

        int256 selfBias;
        int256 selfSlope;

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];

            if (!IVotingEscrow(escrow).isApprovedOrOwner(sender, tokenId)) {
                revert NotApprovedOrOwner();
            }

            if (tokenIsDelegated[tokenId]) {
                revert TokenAlreadyDelegated(tokenId);
            }

            tokenIsDelegated[tokenId] = true;

            IVotingEscrow.LockedBalance memory locked = IVotingEscrow(escrow).locked(tokenId);
            (int256 bias, int256 slope) = _getBiasAndSlope(delegatee, locked, _positive);

            (int256 selfBias_, int256 selfSlope_) = _getSelfBiasAndSlope(sender, locked, _positive);

            totalBias += bias;
            totalSlope += slope;

            selfBias += selfBias_;
            selfSlope += selfSlope_;
        }

        numberOfDelegatedTokens[sender] += _tokenIds.length;

        _checkpoint(totalBias, totalSlope, delegatee);

        _selfCheckpoint(selfBias, selfSlope, sender);

        ISimpleGaugeVoter(voter).updateVotingPower(sender, delegatee);

        emit TokensDelegated(sender, delegatee, _tokenIds);
    }

    function undelegate(uint256[] memory _tokenIds) public {
        address sender = _msgSender();
        address delegatee = delegates(sender);

        if (delegatee == address(0)) {
            revert DelegateeNotSet();
        }

        int256 totalBias;
        int256 totalSlope;

        int256 selfBias;
        int256 selfSlope;

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];

            if (!IVotingEscrow(escrow).isApprovedOrOwner(sender, tokenId)) {
                revert NotApprovedOrOwner();
            }

            if (!tokenIsDelegated[tokenId]) {
                revert TokenNotDelegated(tokenId);
            }

            tokenIsDelegated[tokenId] = false;

            IVotingEscrow.LockedBalance memory locked = IVotingEscrow(escrow).locked(tokenId);
            (int256 bias, int256 slope) = _getBiasAndSlope(delegatee, locked, _negative);

            (int256 selfBias_, int256 selfSlope_) = _getSelfBiasAndSlope(sender, locked, _negative);

            totalBias += bias;
            totalSlope += slope;

            selfBias += selfBias_;
            selfSlope += selfSlope_;
        }

        numberOfDelegatedTokens[sender] -= _tokenIds.length;

        _checkpoint(totalBias, totalSlope, delegatee);

        _selfCheckpoint(selfBias, selfSlope, sender);

        ISimpleGaugeVoter(voter).updateVotingPower(sender, delegatee);

        emit TokensUndelegated(sender, delegatee, _tokenIds);
    }

    function moveDelegateVotes(address _from, address _to, uint256 _tokenId) external {
        if (_msgSender() != escrow) {
            revert OnlyEscrow();
        }

        address fromDelegatee = delegates(_from);
        address toDelegatee = delegates(_to);

        if (_from == _to || fromDelegatee == toDelegatee) {
            return;
        }

        // burn is occuring, but we don't need to do anything
        // as prior to this, `beginWithdrawal` would have been
        // called, transfering token to escrow contract.
        if (_to == address(0)) {
            return;
        }

        IVotingEscrow.LockedBalance memory locked = IVotingEscrow(escrow).locked(_tokenId);

        // mint is occuring and the receiver already has a delegatee.
        // Increase the delegatee's voting power.
        if (_from == address(0) && toDelegatee != address(0)) {
            (int256 bias, int256 slope) = _getBiasAndSlope(toDelegatee, locked, _positive);
            _checkpoint(bias, slope, toDelegatee);

            (bias, slope) = _getSelfBiasAndSlope(_to, locked, _positive);
            _selfCheckpoint(bias, slope, _to);

            tokenIsDelegated[_tokenId] = true;
            numberOfDelegatedTokens[_to]++;

            ISimpleGaugeVoter(voter).updateVotingPower(fromDelegatee, toDelegatee);

            return;
        }

        if (fromDelegatee != address(0)) {
            (int256 bias, int256 slope) = _getBiasAndSlope(fromDelegatee, locked, _negative);
            _checkpoint(bias, slope, fromDelegatee);

            (bias, slope) = _getSelfBiasAndSlope(_from, locked, _negative);
            _selfCheckpoint(bias, slope, _from);

            numberOfDelegatedTokens[_from]--;
        }

        if (_to == address(escrow)) {
            // transfering to address(escrow) is the same as `beginWithdrawal`, i.e burn.
            tokenIsDelegated[_tokenId] = false;
        } else if (toDelegatee != address(0)) {
            (int256 bias, int256 slope) = _getBiasAndSlope(toDelegatee, locked, _positive);
            _checkpoint(bias, slope, toDelegatee);

            (bias, slope) = _getSelfBiasAndSlope(_to, locked, _positive);
            _selfCheckpoint(bias, slope, _to);

            numberOfDelegatedTokens[_to]++;
            tokenIsDelegated[_tokenId] = true;
        }

        ISimpleGaugeVoter(voter).updateVotingPower(fromDelegatee, toDelegatee);
    }

    /*//////////////////////////////////////////////////////////////
                        Checkpoint Functions
    //////////////////////////////////////////////////////////////*/

    function checkpointTransition(address _delegatee, uint256 _transitionCount) external {
        _checkpoint(0, 0, _delegatee, _transitionCount);
    }

    function _checkpoint(int256 _totalBias, int256 _totalSlope, address _delegatee) internal {
        _checkpoint(_totalBias, _totalSlope, _delegatee, 255);
    }

    function _selfCheckpoint(int256 _totalBias, int256 _totalSlope, address _account) internal {
        _selfCheckpoint(_totalBias, _totalSlope, _account, 255);
    }

    function _checkpoint(
        int256 _totalBias,
        int256 _totalSlope,
        address _delegatee,
        uint256 _transitionCount
    ) internal {
        GlobalPoint memory lastPoint = GlobalPoint({
            bias: 0,
            slope: 0,
            writtenTs: uint48(block.timestamp)
        });

        uint256 latestPointIndex_ = latestPointIndex[_delegatee];
        if (latestPointIndex_ > 0) {
            lastPoint = pointHistory[_delegatee][latestPointIndex_];
        }

        // Get slope changes for the delegatee
        mapping(uint256 => int256) storage slopeChanges_ = slopeChanges[_delegatee];

        uint256 expectedWrittenTs;

        {
            uint256 checkpointInterval = IClock(clock).checkpointInterval();
            uint256 lastPointCheckpoint = lastPoint.writtenTs;
            uint256 t_i = (lastPointCheckpoint / checkpointInterval) * checkpointInterval;

            // Since `_checkpoint` can be called manually due to transition,
            // the global point's writtenTs shouldn't be block.timestamp
            // by default, but whatever the transition's max week is.
            expectedWrittenTs = t_i + _transitionCount * checkpointInterval;
            if (expectedWrittenTs > block.timestamp) {
                expectedWrittenTs = block.timestamp;
            }

            for (uint256 i = 0; i < _transitionCount; ++i) {
                t_i += checkpointInterval;
                int256 dSlope;

                if (t_i > expectedWrittenTs) {
                    t_i = expectedWrittenTs;
                } else {
                    dSlope = slopeChanges_[t_i];
                }

                lastPoint.bias += lastPoint.slope * int256(t_i - lastPointCheckpoint);
                lastPoint.slope -= dSlope;

                if (lastPoint.slope < 0) lastPoint.slope = 0;
                if (lastPoint.bias < 0) lastPoint.bias = 0;

                lastPointCheckpoint = t_i;

                if (t_i == expectedWrittenTs) {
                    break;
                }
            }
        }

        // totalBias and totalSlope can be negative, in which case
        // it will subtract instead of adding.
        lastPoint.bias += _totalBias;
        lastPoint.slope += _totalSlope;
        lastPoint.writtenTs = uint48(expectedWrittenTs);

        if (lastPoint.slope < 0) lastPoint.slope = 0;
        if (lastPoint.bias < 0) lastPoint.bias = 0;

        latestPointIndex[_delegatee] = ++latestPointIndex_;
        pointHistory[_delegatee][latestPointIndex_] = lastPoint;
    }

    function _selfCheckpoint(
        int256 _totalBias,
        int256 _totalSlope,
        address _account,
        uint256 _transitionCount
    ) internal {
        GlobalPoint memory lastPoint = GlobalPoint({
            bias: 0,
            slope: 0,
            writtenTs: uint48(block.timestamp)
        });

        uint256 latestPointIndex_ = selfLatestPointIndex[_account];
        if (latestPointIndex_ > 0) {
            lastPoint = selfPointHistory[_account][latestPointIndex_];
        }

        // Get slope changes for the delegatee
        mapping(uint256 => int256) storage slopeChanges_ = selfSlopeChanges[_account];

        uint256 expectedWrittenTs;

        {
            uint256 checkpointInterval = IClock(clock).checkpointInterval();
            uint256 lastPointCheckpoint = lastPoint.writtenTs;
            uint256 t_i = (lastPointCheckpoint / checkpointInterval) * checkpointInterval;

            // Since `_checkpoint` can be called manually due to transition,
            // the global point's writtenTs shouldn't be block.timestamp
            // by default, but whatever the transition's max week is.
            expectedWrittenTs = t_i + _transitionCount * checkpointInterval;
            if (expectedWrittenTs > block.timestamp) {
                expectedWrittenTs = block.timestamp;
            }

            for (uint256 i = 0; i < _transitionCount; ++i) {
                t_i += checkpointInterval;
                int256 dSlope;

                if (t_i > expectedWrittenTs) {
                    t_i = expectedWrittenTs;
                } else {
                    dSlope = slopeChanges_[t_i];
                }

                lastPoint.bias += lastPoint.slope * int256(t_i - lastPointCheckpoint);
                lastPoint.slope -= dSlope;

                if (lastPoint.slope < 0) lastPoint.slope = 0;
                if (lastPoint.bias < 0) lastPoint.bias = 0;

                lastPointCheckpoint = t_i;

                if (t_i == expectedWrittenTs) {
                    break;
                }
            }
        }

        // totalBias and totalSlope can be negative, in which case
        // it will subtract instead of adding.
        lastPoint.bias += _totalBias;
        lastPoint.slope += _totalSlope;
        lastPoint.writtenTs = uint48(expectedWrittenTs);

        if (lastPoint.slope < 0) lastPoint.slope = 0;
        if (lastPoint.bias < 0) lastPoint.bias = 0;

        selfLatestPointIndex[_account] = ++latestPointIndex_;
        selfPointHistory[_account][latestPointIndex_] = lastPoint;
    }

    /*//////////////////////////////////////////////////////////////
                      IVotes Function
    //////////////////////////////////////////////////////////////*/

    function getVotes(address _account) external view returns (uint256) {
        return _delegateBalanceAt(_account, block.timestamp);
    }

    function getPastVotes(address _account, uint256 _timestamp) external view returns (uint256) {
        return _delegateBalanceAt(_account, _timestamp);
    }

    function getPastTotalSupply(uint256 _timestamp) external view returns (uint256) {
        return IVotingEscrow(escrow).totalVotingPowerAt(_timestamp);
    }

    function delegates(address _account) public view virtual returns (address) {
        return delegateesHistory[_account][delegateesHistory[_account].length - 1].delegatee;
    }

    function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) public virtual {
        revert DelegateBySigNotSupported();
    }

    /*//////////////////////////////////////////////////////////////
                        Getter Functions
    //////////////////////////////////////////////////////////////*/

    function getOwnedVotes(address _account) external view returns (uint256) {
        return _delegatedBalanceAt(_account, block.timestamp);
    }

    function delegatesAt(
        address _account,
        uint256 timestamp
    ) public view virtual returns (address) {
        Delegation[] storage history = delegateesHistory[_account];
        uint256 length = history.length;
        if (length == 0) return address(0);
        if (history[length - 1].timestamp <= timestamp) {
            return history[length - 1].delegatee;
        }
        if (history[0].timestamp > timestamp) return address(0);
    }

    /*//////////////////////////////////////////////////////////////
                      Binary Search Functions
    //////////////////////////////////////////////////////////////*/

    function getPastDelegatePointIndex(
        address _delegatee,
        uint256 _timestamp
    ) internal view returns (uint256) {
        uint256 latestPointIndex_ = latestPointIndex[_delegatee];
        if (latestPointIndex_ == 0) return 0;

        mapping(uint256 => GlobalPoint) storage pointHistory_ = pointHistory[_delegatee];

        // First check most recent balance
        if (pointHistory_[latestPointIndex_].writtenTs <= _timestamp) return (latestPointIndex_);

        // Next check implicit zero balance
        if (pointHistory_[1].writtenTs > _timestamp) return 0;

        uint256 lower = 0;
        uint256 upper = latestPointIndex_;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            GlobalPoint storage delegatePoint = pointHistory_[center];
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

    function getSelfPastDelegatePointIndex(
        address _account,
        uint256 _timestamp
    ) internal view returns (uint256) {
        uint256 latestPointIndex_ = selfLatestPointIndex[_account];
        if (latestPointIndex_ == 0) return 0;

        mapping(uint256 => GlobalPoint) storage pointHistory_ = selfPointHistory[_account];

        // First check most recent balance
        if (pointHistory_[latestPointIndex_].writtenTs <= _timestamp) return (latestPointIndex_);

        // Next check implicit zero balance
        if (pointHistory_[1].writtenTs > _timestamp) return 0;

        uint256 lower = 0;
        uint256 upper = latestPointIndex_;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            GlobalPoint storage delegatePoint = pointHistory_[center];
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
        address _delegatee,
        uint256 _timestamp
    ) internal view returns (uint256) {
        uint256 index = getPastDelegatePointIndex(_delegatee, _timestamp);
        // epoch 0 is an empty point
        if (index == 0) return 0;
        GlobalPoint memory point = pointHistory[_delegatee][index];

        int256 bias = point.bias;
        int256 slope = point.slope;
        uint256 ts = point.writtenTs;

        mapping(uint256 => int256) storage slopeChanges_ = slopeChanges[_delegatee];

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

        return uint256(SignedFixedPointMath.fromFP(bias));
    }

    function _delegatedBalanceAt(
        address _account,
        uint256 _timestamp
    ) internal view returns (uint256) {
        uint256 index = getSelfPastDelegatePointIndex(_account, _timestamp);
        // epoch 0 is an empty point
        if (index == 0) return 0;
        GlobalPoint memory point = selfPointHistory[_account][index];

        int256 bias = point.bias;
        int256 slope = point.slope;
        uint256 ts = point.writtenTs;

        mapping(uint256 => int256) storage slopeChanges_ = selfSlopeChanges[_account];

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

        return uint256(SignedFixedPointMath.fromFP(bias));
    }

    /*//////////////////////////////////////////////////////////////
                        Private Helper Functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Note that this function also updates slopeChanges.
    function _getBiasAndSlope(
        address _delegatee,
        IVotingEscrow.LockedBalance memory _locked,
        function(int256) view returns (int256) op
    ) private returns (int256, int256) {
        uint256 elapsed = block.timestamp - _locked.start;
        elapsed = elapsed > maxTime ? maxTime : elapsed;

        int256 amount = uint256(_locked.amount).toInt256();

        // TODO: Probably better if we could get this constants by calling the contract.
        // The reasoning is EscrowIVotesAdapter might not be useful for some clients in the beginning,
        // but might become useful later on. But when the time comes that we decide to deploy this for them,
        // curveconstant coefficients might have changed and this could result in a problem.
        // Clearly, this EscrowIVotesAdapter only expects `escrow` address in `initialize`, but those functions
        // that return constant coefficients live inside curve. Passing `curve` address just for this reason
        // is ideal ? even if we do so, we also have to make the functions public (see curve).

        int256 slope = amount * CurveConstantLib.SHARED_LINEAR_COEFFICIENT;
        int256 bias = slope *
            int256(elapsed) +
            amount *
            CurveConstantLib.SHARED_CONSTANT_COEFFICIENT;

        if (bias < 0) bias = 0;

        if (elapsed < maxTime) {
            slope = op(slope);
            slopeChanges[_delegatee][_locked.start + maxTime] += op(slope);
        } else {
            slope = 0;
        }

        return (op(bias), slope);
    }

    /// @dev Note that this function also updates slopeChanges.
    function _getSelfBiasAndSlope(
        address _account,
        IVotingEscrow.LockedBalance memory _locked,
        function(int256) view returns (int256) op
    ) private returns (int256, int256) {
        uint256 elapsed = block.timestamp - _locked.start;
        elapsed = elapsed > maxTime ? maxTime : elapsed;

        int256 amount = uint256(_locked.amount).toInt256();

        // TODO: Probably better if we could get this constants by calling the contract.
        // The reasoning is EscrowIVotesAdapter might not be useful for some clients in the beginning,
        // but might become useful later on. But when the time comes that we decide to deploy this for them,
        // curveconstant coefficients might have changed and this could result in a problem.
        // Clearly, this EscrowIVotesAdapter only expects `escrow` address in `initialize`, but those functions
        // that return constant coefficients live inside curve. Passing `curve` address just for this reason
        // is ideal ? even if we do so, we also have to make the functions public (see curve).

        int256 slope = amount * CurveConstantLib.SHARED_LINEAR_COEFFICIENT;
        int256 bias = slope *
            int256(elapsed) +
            amount *
            CurveConstantLib.SHARED_CONSTANT_COEFFICIENT;

        if (bias < 0) bias = 0;

        if (elapsed < maxTime) {
            slope = op(slope);
            selfSlopeChanges[_account][_locked.start + maxTime] += op(slope);
        } else {
            slope = 0;
        }

        return (op(bias), slope);
    }

    function _positive(int256 _value) private pure returns (int256) {
        return _value;
    }

    function _negative(int256 _value) private pure returns (int256) {
        return -_value;
    }
}
