/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotingEscrowIncreasingV1_4_0 as IVotingEscrow} from "@escrow/IVotingEscrowIncreasing_v1_4_0.sol";
import {VotingEscrowV1_4_0 as VotingEscrow} from "@escrow/VotingEscrowIncreasing_v1_4_0.sol";

import {IClockUser, IClockV1_4_0 as IClock} from "@clock/IClock_v1_4_0.sol";

import {PluginUUPSUpgradeable} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";
import {IDelegationMapper} from "./IDelegationMapper.sol";
import {console2 as console} from "forge-std/console2.sol";
import {CurveConstantLib} from "@libs/CurveConstantLib.sol";
import {SignedFixedPointMath} from "@libs/SignedFixedPointMathLib.sol";

contract DelegationMapper is
    IClockUser,
    ReentrancyGuard,
    IDelegationMapper,
    IVotesUpgradeable,
    PluginUUPSUpgradeable
{
    using SafeCastUpgradeable for uint256;

    /// @notice Address of the voting escrow contract that will track voting power
    address public escrow;

    /// @notice Clock contract for epoch duration
    address public clock;

    mapping(address => mapping(uint256 => int256)) internal slopeChanges;
    mapping(address => mapping(uint256 => GlobalPoint)) internal pointHistory;
    mapping(address => address) private delegatees_;
    mapping(address => uint256) public latestPointIndex;

    mapping(uint256 => bool) public tokenIsDelegated;
    mapping(address => uint) public numberOfDelegatedTokens;
    mapping(address => bool) public autoDelegationEnabled;

    int256 private sharedLinearCoefficient;
    int256 private sharedConstantCoefficient;
    uint256 private maxTime;

    error NotApprovedOrOwner();
    error InvalidTokenId();
    error DelegationNotAllowed();
    error DelegateeNotSet();

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

    function setAutoDelegation(bool _enabled) external {
        // address sender = _msgSender();

        autoDelegationEnabled[msg.sender] = _enabled;
        emit AutoDelegationSet(msg.sender, _enabled);
    }

    function delegate(address _delegatee) public {
        address sender = _msgSender();

        if (numberOfDelegatedTokens[sender] != 0) {
            revert DelegationNotAllowed();
        }

        address oldDelegatee = delegates(_delegatee);

        delegatees_[sender] = _delegatee;

        if (autoDelegationEnabled[sender]) {
            uint256[] memory tokenIds = VotingEscrow(escrow).ownedTokens(sender);
            delegate(tokenIds);
        }

        emit DelegateChanged(sender, oldDelegatee, _delegatee);
    }

    function delegate(uint256[] memory _tokenIds) public {
        address sender = _msgSender();

        address delegatee = delegates(sender);

        if(delegatee == address(0)) {
            revert DelegateeNotSet();
        }

        int256 totalBias;
        int256 totalSlope;

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];

            if (!IVotingEscrow(escrow).isApprovedOrOwner(sender, tokenId)) {
                // revert NotApprovedOrOwner();
            }

            // IVotingEscrow.LockedBalance memory locked = IVotingEscrow(escrow).locked(tokenId);

            // // you can only delegate once but you can delegate tokens one at a time
            // if (!tokenIsDelegated[tokenId]) {
            //     (int256 bias, int256 slope) = _getBiasAndSlope(delegatee, locked, _positive);

            //     totalBias += bias;
            //     totalSlope += slope;
            // }
        }

        // numberOfDelegatedTokens[sender] += _tokenIds.length;

        // _checkpoint(totalBias, totalSlope, delegatee);
    }

    function undelegate(uint256[] memory _tokenIds) public {
        address sender = _msgSender();

        address delegatee = delegates(sender);

        int256 totalBias;
        int256 totalSlope;

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];

            if (!IVotingEscrow(escrow).isApprovedOrOwner(sender, tokenId)) {
                revert NotApprovedOrOwner();
            }

            IVotingEscrow.LockedBalance memory locked = IVotingEscrow(escrow).locked(tokenId);

            if (tokenIsDelegated[tokenId]) {
                (int256 bias, int256 slope) = _getBiasAndSlope(delegatee, locked, _negative);

                totalBias += bias;
                totalSlope += slope;
            }
        }

        numberOfDelegatedTokens[sender] -= _tokenIds.length;

        _checkpoint(totalBias, totalSlope, delegatee);
    }

    function moveDelegateVotes(address _from, address _to, uint256 _tokenId) external {
        if (_msgSender() != escrow) {
            revert OnlyEscrow();
        }

        address from = delegates(_from);
        address to = delegates(_to);

        // `_tokenId` already has the same delegatee, so skip.
        if (from == to) {
            return;
        }

        IVotingEscrow.LockedBalance memory locked = IVotingEscrow(escrow).locked(_tokenId);

        if (from != address(0)) {
            (int256 bias, int256 slope) = _getBiasAndSlope(from, locked, _negative);
            _checkpoint(bias, slope, from);
        }

        if (to != address(0)) {
            (int256 bias, int256 slope) = _getBiasAndSlope(to, locked, _positive);
            _checkpoint(bias, slope, to);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        Checkpoint Functions
    //////////////////////////////////////////////////////////////*/

    function checkpointTransition(address _delegatee, uint256 _transitionCount) external {
        _checkpoint(0, 0, _delegatee, _transitionCount);
    }
    
    function checkpointTransition(uint256 _transitionCount) external {
         _checkpoint(0, 0, _msgSender(), _transitionCount);
    }

    function _checkpoint(int256 _totalBias, int256 _totalSlope, address _delegatee) internal {
        _checkpoint(_totalBias, _totalSlope, _delegatee, 255);
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

        {
            uint256 checkpointInterval = IClock(clock).checkpointInterval();
            uint256 lastPointCheckpoint = lastPoint.writtenTs;
            uint256 t_i = (lastPointCheckpoint / checkpointInterval) * checkpointInterval;

            for (uint256 i = 0; i < _transitionCount; ++i) {
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

                if(t_i == block.timestamp) {
                    break;
                }
            }
        }

        // totalBias and totalSlope can be negative, in which case
        // it will subtract instead of adding.
        lastPoint.bias += _totalBias;
        lastPoint.slope += _totalSlope;

        if (lastPoint.slope < 0) lastPoint.slope = 0;
        if (lastPoint.bias < 0) lastPoint.bias = 0;

        latestPointIndex[_delegatee] = ++latestPointIndex_;
        pointHistory[_delegatee][latestPointIndex_] = lastPoint;
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
        return delegatees_[_account];
    }

    function delegateBySig(
        address,
        uint256,
        uint256,
        uint8,
        bytes32,
        bytes32
    ) public virtual {
        revert DelegateBySigNotSupported();
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
        // The reasoning is delegationMapper might not be useful for some clients in the beginning,
        // but might become useful later on. But when the time comes that we decide to deploy this for them,
        // curveconstant coefficients might have changed and this could result in a problem.
        // Clearly, this delegationMapper only expects `escrow` address in `initialize`, but those functions
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

    function _positive(int256 _value) private pure returns (int256) {
        return _value;
    }

    function _negative(int256 _value) private pure returns (int256) {
        return -_value;
    }
}
