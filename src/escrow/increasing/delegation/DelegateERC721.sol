// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

/*////////////////////////////////////////////////////
                    WIP CONTRACT
////////////////////////////////////////////////////*/

import {ICheckpoint, IDelegateVoterErrors} from "./IDelegateVoter.sol";
import {IVotingEscrowIncreasing as IVotingEscrow} from "../interfaces/IVotingEscrowIncreasing.sol";
import {EpochDurationLib} from "@libs/EpochDurationLib.sol";
import {DaoAuthorizable} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizable.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

// wip interfaces while we think about the architecture
interface IERC721Shortcut is IERC721Metadata {
    function isApprovedOrOwner(address spender, uint256 tokenId) external view returns (bool);
}

interface IDelegateCheckpointer is ICheckpoint, IDelegateVoterErrors {
    event DelegateChanged(address indexed delegator, uint256 indexed fromDelegate, uint256 indexed toDelegate);
}

// this is a potential architectural improvement: federate the delegation logic
// to a separate place either logically (via abstract contract) or architecturally (via a separate contract)
// this would allow changing delegation behaviour but needs work as will need to be
// integrated into the voting escrow at specific times
contract DelegateERC721 is IDelegateCheckpointer, DaoAuthorizable {
    error NonExistentToken();
    error OwnershipChange();
    error NotVe();
    error NotApprovedOrOwner();

    /// @notice A checkpoint for marking balance delegated at a given timestamp
    mapping(uint256 => uint48) public numCheckpoints;

    /// @notice The voting escrow IERC721 contract
    IERC721Shortcut public ve;

    /// @dev tokenid => index
    mapping(uint256 => uint256) private _delegates;

    /// @dev token => timestamp => checkpoint
    mapping(uint256 => mapping(uint48 => Checkpoint)) private _checkpoints;

    /*//////////////////////////////////////////////////////////////
                            INUTIALIZATION
    //////////////////////////////////////////////////////////////*/

    constructor(IDAO _dao, address _ve) DaoAuthorizable(_dao) {
        ve = IERC721Shortcut(_ve);
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function delegates(uint256 delegator) external view returns (uint256) {
        return _delegates[delegator];
    }

    function checkpoints(uint256 _tokenId, uint48 _index) external view returns (Checkpoint memory) {
        return _checkpoints[_tokenId][_index];
    }

    function getUnderlyingLockAmount(uint256 _tokenId) public view returns (uint256) {
        return IVotingEscrow(address(ve)).locked(_tokenId).amount;
    }

    /*//////////////////////////////////////////////////////////////
                      ESCROW RESTRICTED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function checkpointDelegator(
        uint256 _lockedAmount,
        uint256 _delegator,
        uint256 _delegatee,
        address _owner
    ) external {
        if (msg.sender != address(ve)) revert NotVe();
        _checkpointDelegator(_lockedAmount, _delegator, _delegatee, _owner);
    }

    function checkpointDelegatee(uint256 _delegatee, uint256 balance_, bool _increase) external {
        if (msg.sender != address(ve)) revert NotVe();
        _checkpointDelegatee(_delegatee, balance_, _increase);
    }

    // allows proxy delegation if called throught he ve:
    // alternative - abstract
    function delegateFor(uint256 delegator, uint256 delegatee, address _onBehalfOf) external {
        if (_msgSender() != address(ve)) revert NotVe();
        if (!ve.isApprovedOrOwner(_onBehalfOf, delegator)) revert NotApprovedOrOwner();
        uint256 amount = getUnderlyingLockAmount(delegator);
        return _delegate(delegator, delegatee, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function delegate(uint256 delegator, uint256 delegatee) external {
        if (!ve.isApprovedOrOwner(_msgSender(), delegator)) revert NotApprovedOrOwner();
        uint256 amount = getUnderlyingLockAmount(delegator);
        return _delegate(delegator, delegatee, amount);
    }

    function unDelegate(uint256 delegator) external {
        if (!ve.isApprovedOrOwner(_msgSender(), delegator)) revert NotApprovedOrOwner();
        uint256 amount = getUnderlyingLockAmount(delegator);
        return _delegate(delegator, 0, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        CHECKPOINT DELEGATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Record user delegation checkpoints. Used by voting system.
    /// @dev Skips delegation if already delegated to `delegatee`.
    function _delegate(uint256 _delegator, uint256 _delegatee, uint256 _amount) internal {
        if (_delegatee != 0 && ve.ownerOf(_delegatee) == address(0)) revert NonExistentToken();
        // TODO look at this closely
        // if (ve.ownershipChange(_delegator) == block.number) revert OwnershipChange();
        if (_delegatee == _delegator) _delegatee = 0;
        uint256 currentDelegate = _delegates[_delegator];
        if (currentDelegate == _delegatee) return;

        uint256 delegatedBalance = _amount;
        _checkpointDelegator(_amount, _delegator, _delegatee, ve.ownerOf(_delegator));
        _checkpointDelegatee(_delegatee, delegatedBalance, true);

        emit DelegateChanged(_msgSender(), currentDelegate, _delegatee);
    }

    /// @notice Write a checkpoint for the delegator.
    /// @notice Used by `_mint`, `_transferFrom`, `_burn` and `delegate`
    ///         to update delegator voting checkpoints.
    ///         Automatically dedelegates, then updates checkpoint.
    /// @dev This function depends on `_locked` and must be called prior to token state changes.
    ///      If you wish to dedelegate only, use `_delegate(tokenId, 0)` instead.
    /// @param _lockedAmount at the time of the call
    /// @param _delegator The delegator to update checkpoints for
    /// @param _delegatee The new delegatee for the delegator. Cannot be equal to `_delegator` (use 0 instead).
    /// @param _owner The new (or current) owner for the delegator
    function _checkpointDelegator(uint _lockedAmount, uint256 _delegator, uint256 _delegatee, address _owner) internal {
        // fetch the current locked amount, prior to updating
        uint256 delegatedBalance = _lockedAmount;

        // get the checkpoint number for the delegator
        uint48 numCheckpoint = numCheckpoints[_delegator];

        // if the user has at least 2 cps, then we fetch the prior one
        // else we just fetch the first one to avoid out of bounds
        Checkpoint storage oldCheckpoint = numCheckpoint > 0
            ? _checkpoints[_delegator][numCheckpoint - 1]
            : _checkpoints[_delegator][0];

        // here we undelegate from the prior delegatee
        _checkpointDelegatee(oldCheckpoint.delegatee, delegatedBalance, false);

        Checkpoint storage newCheckpoint = _checkpoints[_delegator][numCheckpoint];
        newCheckpoint.fromTimestamp = block.timestamp;
        newCheckpoint.delegatedBalance = oldCheckpoint.delegatedBalance;
        newCheckpoint.delegatee = _delegatee;
        newCheckpoint.owner = _owner;

        if (_isCheckpointInNewBlock(_delegator)) {
            numCheckpoints[_delegator]++;
        } else {
            _checkpoints[_delegator][numCheckpoint - 1] = newCheckpoint;
            delete _checkpoints[_delegator][numCheckpoint];
        }

        _delegates[_delegator] = _delegatee;
    }

    /// @notice Update delegatee's `delegatedBalance` by `balance`.
    /// Only updates if delegating to a new delegatee.
    /// @dev If `delegatee` is 0 (i.e. user is not delegating), then do nothing.
    /// @param _delegatee The delegatee's tokenId
    /// @param balance_ The delta in balance change
    /// @param _increase True if balance is increasing, false if decreasing
    function _checkpointDelegatee(uint256 _delegatee, uint256 balance_, bool _increase) internal {
        // do nothing if not delegating
        if (_delegatee == 0) return;

        // as above, we fetch the number of checkpoints for the delegatee
        // and fetch the spread of the last checkpoint if we can
        uint48 numCheckpoint = numCheckpoints[_delegatee];
        Checkpoint storage oldCheckpoint = numCheckpoint > 0
            ? _checkpoints[_delegatee][numCheckpoint - 1]
            : _checkpoints[_delegatee][0];
        Checkpoint storage newCheckpoint = _checkpoints[_delegatee][numCheckpoint];

        // we update the latest checkpoint by setting the current timestamp and copying across the old data
        // note that it could be empty here, that's totally fine
        newCheckpoint.fromTimestamp = block.timestamp;
        newCheckpoint.owner = oldCheckpoint.owner;
        newCheckpoint.delegatee = oldCheckpoint.delegatee;

        // in the increasing case, we add the balance uncondtionally
        if (_increase) {
            newCheckpoint.delegatedBalance = oldCheckpoint.delegatedBalance + balance_;
        }
        // in the decreasing case, we prevent underflow and set to 0 if the balance is less than the old balance
        else if (balance_ < oldCheckpoint.delegatedBalance) {
            newCheckpoint.delegatedBalance = oldCheckpoint.delegatedBalance - balance_;
        } else {
            newCheckpoint.delegatedBalance = 0;
        }

        // if we are in a new block, we increment the number of checkpoints
        if (_isCheckpointInNewBlock(_delegatee)) {
            numCheckpoints[_delegatee]++;
        }
        // otherwise, we update the last checkpoint and delete the current one
        else {
            _checkpoints[_delegatee][numCheckpoint - 1] = newCheckpoint;
            delete _checkpoints[_delegatee][numCheckpoint];
        }
    }

    function _isCheckpointInNewBlock(uint256 _tokenId) internal view returns (bool) {
        uint48 _nCheckPoints = numCheckpoints[_tokenId];

        if (_nCheckPoints > 0) return false;

        Checkpoint memory latest = _checkpoints[_tokenId][_nCheckPoints - 1];

        // latest timestamp must be in the past
        return latest.fromTimestamp < block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                              VOTING POWER
    //////////////////////////////////////////////////////////////*/

    /// @notice Retrieves historical voting balance for a token id at a given timestamp.
    /// @dev If a checkpoint does not exist prior to the timestamp, this will return 0.
    ///      The user must also own the token at the time in order to receive a voting balance.
    /// @param _account .
    /// @param _tokenId .
    /// @param _timestamp .
    /// @return Total voting balance including delegations at a given timestamp.
    function getPastVotes(address _account, uint256 _tokenId, uint256 _timestamp) external view returns (uint256) {
        uint48 _checkIndex = getPastVotesIndex(_tokenId, _timestamp);
        Checkpoint memory lastCheckpoint = _checkpoints[_tokenId][_checkIndex];
        // If no point exists prior to the given timestamp, return 0
        if (lastCheckpoint.fromTimestamp > _timestamp) return 0;
        // Check ownership
        if (_account != lastCheckpoint.owner) return 0;
        uint256 votes = lastCheckpoint.delegatedBalance;
        return
            lastCheckpoint.delegatee == 0
                ? votes + IVotingEscrow(address(ve)).votingPowerAt(_tokenId, _timestamp)
                : votes;
    }

    /// @notice Binary search to get the voting checkpoint for a token id at or prior to a given timestamp.
    /// @dev If a checkpoint does not exist prior to the timestamp, this will return 0.
    /// @param _tokenId .
    /// @param _timestamp .
    /// @return The index of the checkpoint.
    function getPastVotesIndex(uint256 _tokenId, uint256 _timestamp) internal view returns (uint48) {
        uint48 nCheckpoints = numCheckpoints[_tokenId];
        if (nCheckpoints == 0) return 0;
        // First check most recent balance
        if (_checkpoints[_tokenId][nCheckpoints - 1].fromTimestamp <= _timestamp) return (nCheckpoints - 1);
        // Next check implicit zero balance
        if (_checkpoints[_tokenId][0].fromTimestamp > _timestamp) return 0;

        uint48 lower = 0;
        uint48 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint48 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint storage cp = _checkpoints[_tokenId][center];
            if (cp.fromTimestamp == _timestamp) {
                return center;
            } else if (cp.fromTimestamp < _timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    /*//////////////////////////////////////////////////////////////
                            ERC6372 CLOCK LOGIC
    //////////////////////////////////////////////////////////////*/

    function clock() external view returns (uint48) {
        return uint48(block.timestamp);
    }

    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=timestamp";
    }
}
