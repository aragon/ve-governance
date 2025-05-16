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
import {
    PausableUpgradeable as Pausable
} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {
    DaoAuthorizableUpgradeable as DaoAuthorizable
} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizableUpgradeable.sol";

import {
    IVotingEscrowIncreasingV1_2_0 as IVotingEscrow
} from "@escrow/IVotingEscrowIncreasing_v1_2_0.sol";
import {VotingEscrowV1_2_0 as VotingEscrow} from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";

import {IClockUser, IClockV1_2_0 as IClock} from "@clock/IClock_v1_2_0.sol";

import {IEscrowIVotesAdapter, IDelegateMoveVoteRecipient} from "./IEscrowIVotesAdapter.sol";
import {CurveConstantLib} from "@libs/CurveConstantLib.sol";
import {SignedFixedPointMath} from "@libs/SignedFixedPointMathLib.sol";

contract EscrowIVotesAdapter is
    IClockUser,
    ReentrancyGuard,
    IEscrowIVotesAdapter,
    Pausable,
    DaoAuthorizable,
    UUPSUpgradeable
{
    using SafeCastUpgradeable for uint256;

    /// @notice The Gauge admin can can create and manage voting gauges for token holders
    bytes32 public constant DELEGATION_ADMIN_ROLE = keccak256("DELEGATION_ADMIN");

    /// @notice Address of the voting escrow contract that will track voting power
    address public escrow;

    /// @notice Clock contract for epoch duration
    address public clock;

    mapping(address => mapping(uint256 => int256)) internal slopeChanges;
    mapping(address => mapping(uint256 => GlobalPoint)) internal pointHistory;
    mapping(address => address) private delegatees_;
    mapping(address => uint256) public latestPointIndex;

    mapping(address => uint256) public numberOfDelegatedTokens;
    mapping(address => bool) private autoDelegationDisabled_;
    mapping(uint256 => uint256) private delegatedBitmap;

    uint256 private maxTime;

    /*///////////////////////////////////////////////////////////////
                            Initialization
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _dao,
        address _escrow,
        address _clock,
        bool _startPaused
    ) external initializer {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
        __ReentrancyGuard_init();
        escrow = _escrow;
        clock = _clock;

        if (_startPaused) _pause();

        maxTime = IClock(clock).epochDuration() * CurveConstantLib.MAX_EPOCHS;
    }

    function pause() external auth(DELEGATION_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external auth(DELEGATION_ADMIN_ROLE) {
        _unpause();
    }

    /// @dev Note that by default, auto delegation of tokenIds is turned on.
    function setAutoDelegationDisabled(bool _disabled) external {
        address sender = _msgSender();

        autoDelegationDisabled_[sender] = _disabled;
        emit AutoDelegationSet(sender, _disabled);
    }

    /// @dev Internal helper function to set token delegated to true by using bitmap operations.
    function _setDelegated(uint256 tokenId, bool value) internal virtual {
        uint256 bucket = tokenId >> 8; // tokenId / 256
        uint256 mask = 1 << (tokenId & 0xff); // tokenId % 256

        if (value) {
            delegatedBitmap[bucket] |= mask;
        } else {
            delegatedBitmap[bucket] &= ~mask;
        }
    }

    /// @dev Whether token is currently delegated or not.
    function tokenIsDelegated(uint256 tokenId) public view virtual returns (bool) {
        uint256 bucket = tokenId >> 8;
        uint256 mask = 1 << (tokenId & 0xff);
        return (delegatedBitmap[bucket] & mask) != 0;
    }

    /*//////////////////////////////////////////////////////////////
                        Delegate Functions
    //////////////////////////////////////////////////////////////*/

    /// @param _delegatee The new delegatee address.
    /// @dev If auto delegation is not disabled, it will delegate all token ids
    ///      that sender currently has. Note that sender must first undelegate
    ///      all token ids before calling this function.
    function delegate(address _delegatee) public whenNotPaused {
        address sender = _msgSender();

        if (numberOfDelegatedTokens[sender] != 0) {
            revert DelegationNotAllowed();
        }

        address currentDelegatee = delegates(sender);
        delegatees_[sender] = _delegatee;

        if (!autoDelegationDisabled(sender) && _delegatee != address(0)) {
            uint256[] memory tokenIds = VotingEscrow(escrow).ownedTokens(sender);
            if (tokenIds.length != 0) {
                _delegate(sender, _delegatee, tokenIds, false);
            }
        }

        emit DelegateChanged(sender, currentDelegatee, _delegatee);
    }

    /// @dev Note that `_tokenIds` must be either owned or approved to sender and tokens must not be delegated yet.
    /// @param _tokenIds The array of token ids that will be delegated to the current delegatee of `sender`.
    function delegate(uint256[] memory _tokenIds) public virtual whenNotPaused {
        address sender = _msgSender();
        address delegatee = delegates(sender);

        if (delegatee == address(0)) {
            revert DelegateeNotSet();
        }

        if (_tokenIds.length == 0) {
            revert TokenListEmpty();
        }

        _delegate(sender, delegatee, _tokenIds, true);
    }

    /// @dev Undelegates currently delegated tokens from the current delegatee
    ///      and delegates all owned tokens by the sender to the new delegatee.
    /// @param _delegatee The new delegatee address.
    function redelegate(address _delegatee) public virtual whenNotPaused {
        address sender = _msgSender();
        address currentDelegatee = delegates(sender);

        uint256[] memory tokenIds = VotingEscrow(escrow).ownedTokens(sender);
        uint256 ownedTokenLength = tokenIds.length;

        if (currentDelegatee != address(0) && ownedTokenLength != 0) {
            uint256[] memory delegatedTokenIds = getDelegatedTokens(tokenIds);
            if (delegatedTokenIds.length != 0) {
                _undelegate(sender, currentDelegatee, delegatedTokenIds, false);
            }
        }

        delegatees_[sender] = _delegatee;

        if (!autoDelegationDisabled(sender) && _delegatee != address(0) && ownedTokenLength != 0) {
            _delegate(sender, _delegatee, tokenIds, false);
        }

        emit DelegateChanged(sender, currentDelegatee, _delegatee);
    }

    /// @dev Note that the token ids must be currently delegated and must be owned/approved to the sender.
    /// @param _tokenIds The array of token ids that will be undelegated from the current delegatee.
    function undelegate(uint256[] memory _tokenIds) public virtual whenNotPaused {
        address sender = _msgSender();
        address delegatee = delegates(sender);

        if (delegatee == address(0)) {
            revert DelegateeNotSet();
        }

        if (_tokenIds.length == 0) {
            revert TokenListEmpty();
        }

        _undelegate(sender, delegatee, _tokenIds, true);
    }

    /// @notice private helper function to delegate token ids to the `_delegatee`.
    /// @dev It updates checkpoints, sets token delegation to true and
    ///      updates voting power on the address gauge voter.
    /// @param _sender The address that owns `_tokenIds` and delegates.
    /// @param _delegatee The new delegatee address to which `_tokenIds` will be delegated.
    /// @param _tokenIds The array of token ids. Note that it's caller's responsibility to not
    ///                  call this function for empty list of `_tokenIds`.
    /// @param _validate The boolean flag of whether to validate that token ids are owned by the `_sender` or not.
    ///                  In some cases, validation is not needed as caller already knows that there's no need.
    function _delegate(
        address _sender,
        address _delegatee,
        uint256[] memory _tokenIds,
        bool _validate
    ) internal virtual {
        (int256 totalBias, int256 totalSlope) = (0, 0);

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];

            if (_validate) {
                if (!IVotingEscrow(escrow).isApprovedOrOwner(_sender, tokenId)) {
                    revert NotApprovedOrOwner();
                }

                if (tokenIsDelegated(tokenId)) {
                    revert TokenAlreadyDelegated(tokenId);
                }
            }

            // Ensure that voting power is greater than 0.
            // This can not be figured out with only `locked` data, as
            // token might exist, but might not be warm.
            if (IVotingEscrow(escrow).votingPower(tokenId) == 0) {
                revert VotingPowerZero(tokenId);
            }

            _setDelegated(tokenId, true);

            IVotingEscrow.LockedBalance memory locked = IVotingEscrow(escrow).locked(tokenId);
            (int256 bias, int256 slope) = _getBiasAndSlope(_delegatee, locked, _positive);
            totalBias += bias;
            totalSlope += slope;
        }

        numberOfDelegatedTokens[_sender] += _tokenIds.length;
        _checkpoint(totalBias, totalSlope, _delegatee);
        IVotingEscrow(escrow).updateVotingPower(_sender, _delegatee);
        emit TokensDelegated(_sender, _delegatee, _tokenIds);
    }

    /// @notice private helper function to undelegate token ids to the `_delegatee`.
    /// @dev It updates checkpoints, sets token delegation to false and
    ///      updates voting power on the address gauge voter.
    /// @param _sender The address that owns `_tokenIds` and undelegates.
    /// @param _delegatee The delegatee address from which `_tokenIds` will be undelegated.
    /// @param _tokenIds The array of token ids. Note that it's caller's responsibility to not
    ///                  call this function for empty list of `_tokenIds`.
    /// @param _validate The boolean flag of whether to validate that token ids are owned by the `_sender` or not.
    ///                  In some cases, validation is not needed as caller already knows that there's no need.
    function _undelegate(
        address _sender,
        address _delegatee,
        uint256[] memory _tokenIds,
        bool _validate
    ) internal virtual {
        (int256 totalBias, int256 totalSlope) = (0, 0);

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];

            if (_validate) {
                if (!IVotingEscrow(escrow).isApprovedOrOwner(_sender, tokenId)) {
                    revert NotApprovedOrOwner();
                }

                if (!tokenIsDelegated(tokenId)) {
                    revert TokenNotDelegated(tokenId);
                }
            }

            _setDelegated(tokenId, false);

            IVotingEscrow.LockedBalance memory locked = IVotingEscrow(escrow).locked(tokenId);
            (int256 bias, int256 slope) = _getBiasAndSlope(_delegatee, locked, _negative);

            totalBias += bias;
            totalSlope += slope;
        }

        numberOfDelegatedTokens[_sender] -= _tokenIds.length;
        _checkpoint(totalBias, totalSlope, _delegatee);
        IVotingEscrow(escrow).updateVotingPower(_sender, _delegatee);

        emit TokensUndelegated(_sender, _delegatee, _tokenIds);
    }

    /// @notice It returns which tokens are currently delegated from the list of `_tokenIds`.
    function getDelegatedTokens(
        uint256[] memory _tokenIds
    ) public view virtual returns (uint256[] memory) {
        uint256[] memory tmp = new uint256[](_tokenIds.length);
        uint256 count;

        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            if (tokenIsDelegated(_tokenIds[i])) {
                tmp[count++] = _tokenIds[i];
            }
        }

        // Trim to size
        uint256[] memory delegatedTokenIds = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            delegatedTokenIds[i] = tmp[i];
        }

        return delegatedTokenIds;
    }

    /// @notice Whether an `account` has disabled auto delegation or not.
    /// @param _account The address on which auto delegation is checked for.
    /// @return True if auto delegation is disabled, otherwise false.
    function autoDelegationDisabled(address _account) public view virtual returns (bool) {
        return autoDelegationDisabled_[_account];
    }

    /*//////////////////////////////////////////////////////////////
                        Hook Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDelegateMoveVoteRecipient
    function moveDelegateVotes(
        address _from,
        address _to,
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _locked
    ) public virtual whenNotPaused {
        if (_msgSender() != escrow) {
            revert OnlyEscrow();
        }

        address fromDelegatee = delegates(_from);
        address toDelegatee = delegates(_to);

        // undelegated src and recipient, no balances to update
        if (fromDelegatee == address(0) && toDelegatee == address(0)) {
            return;
        }

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = _tokenId;

        if (fromDelegatee != address(0)) {
            // can be skipped if there are no updates
            if (_locked.amount != 0) {
                (int256 bias, int256 slope) = _getBiasAndSlope(fromDelegatee, _locked, _negative);
                _checkpoint(bias, slope, fromDelegatee);
            }

            numberOfDelegatedTokens[_from]--;

            emit TokensUndelegated(_from, fromDelegatee, tokenIds);
        }

        if (toDelegatee != address(0)) {
            // can be skipped if there are no updates
            if (_locked.amount != 0) {
                (int256 bias, int256 slope) = _getBiasAndSlope(toDelegatee, _locked, _positive);
                _checkpoint(bias, slope, toDelegatee);
            }

            numberOfDelegatedTokens[_to]++;
            _setDelegated(_tokenId, true);

            emit TokensDelegated(_to, toDelegatee, tokenIds);
        } else {
            // else this is new delegate voting power being burned
            _setDelegated(_tokenId, false);
        }

        // If transfer is a merge or split of tokens owned by the same delegatee,
        // we don't need to update the voting power.
        if (fromDelegatee != toDelegatee) {
            IVotingEscrow(escrow).updateVotingPower(fromDelegatee, toDelegatee);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        Checkpoint Functions
    //////////////////////////////////////////////////////////////*/

    function checkpointTransition(
        address _delegatee,
        uint256 _transitionCount
    ) external whenNotPaused {
        _checkpoint(0, 0, _delegatee, _transitionCount);
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

    function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) public virtual {
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

    /// @notice Returns the address of the implementation contract in the [proxy storage slot](https://eips.ethereum.org/EIPS/eip-1967) slot the [UUPS proxy](https://eips.ethereum.org/EIPS/eip-1822) is pointing to.
    /// @return The address of the implementation contract.
    function implementation() public view returns (address) {
        return _getImplementation();
    }

    /// @notice Internal method authorizing the upgrade of the contract via the [upgradeability mechanism for UUPS proxies](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable) (see [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822)).
    function _authorizeUpgrade(address) internal virtual override auth(DELEGATION_ADMIN_ROLE) {}

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[40] private __gap;
}
