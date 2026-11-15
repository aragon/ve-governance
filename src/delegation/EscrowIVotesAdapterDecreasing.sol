/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    IVotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {
    SafeCastUpgradeable as SafeCast
} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable as ReentrancyGuard
} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {
    PausableUpgradeable as Pausable
} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IERC721EnumerableMintableBurnable as IERC721EMB} from "@lock/IERC721EMB.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {
    DaoAuthorizableUpgradeable as DaoAuthorizable
} from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";

import {
    IVotingEscrowDecreasing as IVotingEscrow
} from "@escrow/IVotingEscrowDecreasing.sol";
import {VotingEscrowDecreasing as VotingEscrow} from "@escrow/VotingEscrowDecreasing.sol";

import {IClockV1_2_0 as IClock} from "@clock/IClock_v1_2_0.sol";

import {IEscrowIVotesAdapter, IDelegateMoveVoteRecipient} from "./IEscrowIVotesAdapter.sol";
import {SignedFixedPointMath} from "@libs/SignedFixedPointMathLib.sol";
import {DelegationHelper} from "./DelegationHelper.sol";

contract EscrowIVotesAdapterDecreasing is
    IERC6372,
    ReentrancyGuard,
    Pausable,
    DaoAuthorizable,
    UUPSUpgradeable,
    DelegationHelper
{
    using SafeCast for int256;
    using SafeCast for uint256;

    /// @notice The Gauge admin can can create and manage voting gauges for token holders
    bytes32 public constant DELEGATION_ADMIN_ROLE = keccak256("DELEGATION_ADMIN");

    /// @notice The role used to call `setDelegateAddress` and delegate/undelegate for specific tokens.
    bytes32 public constant DELEGATION_TOKEN_ROLE = keccak256("DELEGATION_TOKEN_ROLE");

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    int256 public immutable SHARED_LINEAR_DENOMINATOR;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    int256 public immutable SHARED_CONSTANT_COEFFICIENT;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 public immutable MAX_EPOCHS;
    
    /// @notice Clock contract for epoch duration
    address public escrowClock;

    mapping(address => mapping(uint256 => int256)) internal slopeChanges;
    mapping(address => mapping(uint256 => GlobalPoint)) public pointHistory;
    mapping(address => address) private delegatees_;

    mapping(address => uint256) public latestPointIndex;
    mapping(address => bool) private autoDelegationDisabled_;

    uint256 private maxTime;
    uint256 private checkpointInterval;

    /*///////////////////////////////////////////////////////////////
                            Initialization
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(int256 _constantCoefficient, int256 _linearDenominator, uint256 _maxEpochs) {
        require(_linearDenominator< 0, "Linear denominator should be negative");
        SHARED_CONSTANT_COEFFICIENT = _constantCoefficient;
        SHARED_LINEAR_DENOMINATOR = _linearDenominator;

        MAX_EPOCHS = _maxEpochs;

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
        __DelegationHelper_init(_escrow);

        escrowClock = _clock;

        if (_startPaused) _pause();

        maxTime = IClock(escrowClock).epochDuration() * MAX_EPOCHS;
        checkpointInterval = IClock(escrowClock).checkpointInterval();
        require(maxTime <= 255 * checkpointInterval, "maxTime exceeds checkpoint loop limit");
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
        emit AutoDelegationDisabledSet(sender, _disabled);
    }

    /*//////////////////////////////////////////////////////////////
                        Delegate Functions
    //////////////////////////////////////////////////////////////*/

    /// @param _delegatee The new delegatee address.
    /// @dev Allows to change a delegatee address. This is useful
    ///      for cases when delegator has huge number of tokens in
    ///      which case  `delegate(address)` would go out of gas.
    ///      In rare cases, Caller first has to undelegate all tokens,
    ///      then call this function and then call `delegate(tokenIds)`.
    function setDelegateAddress(
        address _delegatee
    ) public whenNotPaused auth(DELEGATION_TOKEN_ROLE) {
        address sender = _msgSender();

        if (numberOfDelegatedTokens[sender] != 0) {
            revert DelegationNotAllowed();
        }

        address currentDelegatee = delegates(sender);
        delegatees_[sender] = _delegatee;

        emit DelegateChanged(sender, currentDelegatee, _delegatee);
    }

    /// @dev Note that `_tokenIds` must be owned by sender and tokens must not be delegated yet.
    /// @param _tokenIds The array of token ids that will be delegated to the current delegatee of `sender`.
    function delegate(
        uint256[] memory _tokenIds
    ) public virtual whenNotPaused auth(DELEGATION_TOKEN_ROLE) {
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
    // TODO: auth(DELEGATION_TOKEN_ROLE) ?
    function delegate(address _delegatee) public virtual whenNotPaused {
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
    function undelegate(
        uint256[] memory _tokenIds
    ) public virtual whenNotPaused auth(DELEGATION_TOKEN_ROLE) {
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

        address lockNFT = IVotingEscrow(escrow).lockNFT();

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];

            if (_validate) {
                if (IERC721EMB(lockNFT).ownerOf(tokenId) != _sender) {
                    revert NotOwner();
                }

                if (tokenIsDelegated(tokenId)) {
                    revert TokenAlreadyDelegated(tokenId);
                }
            }

            // Ensure that lock is not expired
            if (IVotingEscrow(escrow).isLockExpiredAtNextCheckpoint(tokenId)) {
                revert LockExpired(tokenId);
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
        
        address lockNFT = IVotingEscrow(escrow).lockNFT();

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];

            if (_validate) {
                if (IERC721EMB(lockNFT).ownerOf(tokenId) != _sender) {
                    revert NotOwner();
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
        uint256[] memory delegatedTokenIds = new uint256[](_tokenIds.length);
        uint256 count;

        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            if (tokenIsDelegated(_tokenIds[i])) {
                delegatedTokenIds[count++] = _tokenIds[i];
            }
        }

        // Trim to size
        assembly {
            mstore(delegatedTokenIds, count)
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
                        IERC6372 Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC6372
    function clock() external view returns (uint48) {
        return uint48(block.timestamp);
    }

    /// @inheritdoc IERC6372
    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=timestamp";
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

    function _checkpoint(
        int256 _totalBias,
        int256 _totalSlope,
        address _delegatee
    ) internal override {
        // Processes at most 255 intervals. A longer gap is closed linearly in one extra step, 
        // because no slope changes can remain beyond `maxTime`.
        _checkpoint(_totalBias, _totalSlope, _delegatee, 255);
    }

    function _checkpoint(
        int256 _totalBias,
        int256 _totalSlope,
        address _delegatee,
        uint256 _transitionCount
    ) internal override {
        if(_transitionCount == 0) revert ZeroTransition();

        GlobalPoint memory lastPoint = GlobalPoint({
            bias: 0,
            slope: 0,
            writtenTs: uint48(_getNextCheckpointStart())
        });

        uint256 latestPointIndex_ = latestPointIndex[_delegatee];
        if (latestPointIndex_ > 0) {
            lastPoint = pointHistory[_delegatee][latestPointIndex_];
        }

        // Get slope changes for the delegatee
        mapping(uint256 => int256) storage slopeChanges_ = slopeChanges[_delegatee];

        uint256 expectedWrittenTs;
        uint256 nextCheckpointStart = _getNextCheckpointStart();

        {
            uint256 lastPointCheckpoint = lastPoint.writtenTs;
            uint256 t_i = lastPointCheckpoint;

            // Since `_checkpoint` can be called manually due to transition,
            // the global point's writtenTs shouldn't be block.timestamp
            // by default, but whatever the transition's max week is.
            expectedWrittenTs = t_i + _transitionCount * checkpointInterval;
            if (expectedWrittenTs > nextCheckpointStart) {
                expectedWrittenTs = nextCheckpointStart;
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

                if (lastPoint.slope > 0) lastPoint.slope = 0;
                if (lastPoint.bias < 0) lastPoint.bias = 0;

                lastPointCheckpoint = t_i;

                if (t_i == expectedWrittenTs) {
                    break;
                }
            }
        }

        // The loop stopped short of the next checkpoint, but has already passed every pending slope change.
        // Extend the point linearly so new voting power is dated at the next checkpoint, not in the past.
        if (expectedWrittenTs < nextCheckpointStart && _transitionCount * checkpointInterval >= maxTime) {
            lastPoint.bias += lastPoint.slope * int256(nextCheckpointStart - expectedWrittenTs);
            if (lastPoint.bias < 0) lastPoint.bias = 0;
            expectedWrittenTs = nextCheckpointStart;
        }

        // totalBias and totalSlope can be negative, in which case
        // it will subtract instead of adding.
        lastPoint.bias += _totalBias;
        lastPoint.slope += _totalSlope;
        lastPoint.writtenTs = uint48(expectedWrittenTs);

        if (lastPoint.slope > 0) lastPoint.slope = 0;
        if (lastPoint.bias < 0) lastPoint.bias = 0;

        // If the timestamp of last stored token point is the same as
        // current timestamp, overwrite it, otherwise store a new one.
        if (
            latestPointIndex_ != 0 && 
            pointHistory[_delegatee][latestPointIndex_].writtenTs == nextCheckpointStart
        ) {
            pointHistory[_delegatee][latestPointIndex_] = lastPoint;
        } else {
            latestPointIndex[_delegatee] = ++latestPointIndex_;
            pointHistory[_delegatee][latestPointIndex_] = lastPoint;
        }
    }

    /// @notice Proxies a call to the ERC721 contract
    /// @dev Useful for calling contracts looking to validate if the contract is token-like
    function balanceOf(address _account) public view virtual returns (uint256) {
        address lockNFT = IVotingEscrow(escrow).lockNFT();
        if (lockNFT == address(0)) return 0;

        return IERC721EMB(lockNFT).balanceOf(_account);
    }

    /*//////////////////////////////////////////////////////////////
                      IVotes Function
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the current amount of votes that `account` has.
    function getVotes(address _account) external view returns (uint256) {
        return _delegateBalanceAt(_account, block.timestamp);
    }

    /// @notice Returns the amount of votes that `account` had at a specific moment in the past.
    function getPastVotes(address _account, uint256 _timestamp) public view returns (uint256) {
        return _delegateBalanceAt(_account, _timestamp);
    }

    /// @notice Returns the total supply of votes available at a specific moment in the past.
    /// @dev This value is the sum of all available votes, which is not necessarily the sum
    ///      of all delegated votes. Votes that have not been delegated are still part of
    ///      total supply, even though they would not participate in a vote.
    function getPastTotalSupply(uint256 _timestamp) external view returns (uint256) {
        return IVotingEscrow(escrow).totalVotingPowerAt(_timestamp);
    }

    /// @inheritdoc IEscrowIVotesAdapter
    function delegates(address _account) public view virtual override returns (address) {
        return delegatees_[_account];
    }

    /// @dev Not implemented.
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

        uint256 _checkpointInterval = checkpointInterval;

        uint256 t_i = (ts / _checkpointInterval) * _checkpointInterval;

        // If the system hasn't been touched for > 255 intervals (~5 years), this will end prematurely
        // We assume the system gets checkpointed more frequently than that.
        for (uint256 i = 0; i < 255; ++i) {
            t_i += _checkpointInterval;
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

    function _getNextCheckpointStart() internal view returns (uint256) {
        uint256 _checkpointInterval = checkpointInterval;
        uint256 nextCheckpointStart = block.timestamp / _checkpointInterval * _checkpointInterval;
        if (nextCheckpointStart < block.timestamp) nextCheckpointStart += _checkpointInterval;
        return nextCheckpointStart;
    }

    /// @dev Note that this function also updates slopeChanges.
    function _getBiasAndSlope(
        address _delegatee,
        IVotingEscrow.LockedBalance memory _locked,
        function(int256) view returns (int256) op
    ) internal override returns (int256, int256) {
        uint256 nextCheckpointStart = _getNextCheckpointStart();
        if (nextCheckpointStart < _locked.start) {
            return (0, 0);
        }

        uint256 elapsed = nextCheckpointStart - _locked.start;
        elapsed = elapsed > maxTime ? maxTime : elapsed;

        int256 amount = _getFlooredAmount(_locked.amount).toInt256();

        int256 slope;
        if (_locked.start == 0) { // permanent lock
            slope = 0;
        } else {
            slope = amount * 1e18 / SHARED_LINEAR_DENOMINATOR;
        }
        int256 bias = slope * int256(elapsed) + amount * SHARED_CONSTANT_COEFFICIENT;

        if (bias < 0) bias = 0;

        if (elapsed < maxTime) {
            slope = op(slope);
            slopeChanges[_delegatee][_locked.start + maxTime] += slope;
        } else {
            slope = 0;
        }

        return (op(bias), slope);
    }

    // Copy of LinearDecreasingCurve:getFlooredAmount()
    // To make sure that locks reach zero exactly at the end of the epoch
    function _getFlooredAmount(uint256 _amount) internal view returns (uint256) {
        uint256 denominator = (-SHARED_LINEAR_DENOMINATOR).toUint256();
        return _amount / denominator * denominator;
    }

    /// @notice Returns the address of the implementation contract in the [proxy storage slot](https://eips.ethereum.org/EIPS/eip-1967) slot the [UUPS proxy](https://eips.ethereum.org/EIPS/eip-1822) is pointing to.
    /// @return The address of the implementation contract.
    function implementation() public view returns (address) {
        return _getImplementation();
    }

    /// @notice Internal method authorizing the upgrade of the contract via the [upgradeability mechanism for UUPS proxies](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable) (see [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822)).
    function _authorizeUpgrade(address) internal virtual override auth(DELEGATION_ADMIN_ROLE) {}

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[42] private __gap;
}
