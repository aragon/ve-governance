/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotingEscrowIncreasingV1_4_0 as IVotingEscrow} from "@escrow/IVotingEscrowIncreasing_v1_4_0.sol";
import {VotingEscrowV1_4_0 as VotingEscrow} from "@escrow/VotingEscrowIncreasing_v1_4_0.sol";

import {IClockUser, IClock} from "@clock/IClock.sol";
import {IClockSeason} from "@clock/IClockSeason.sol";

import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";
import {IVotes, IDelegationMapper} from "./IDelegationMapper.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
contract DelegationMapper is
    IClockUser,
    ReentrancyGuard,
    IDelegationMapper,
    IVotes,
    PluginUUPSUpgradeable
{

    using SafeCastUpgradeable for uint256;

    /// @notice Address of the voting escrow contract that will track voting power
    address public escrow;

    /// @notice Clock contract for epoch duration
    address public clock;

    struct DelegationInfo {
        address delegatee;
        uint256 votingPower;
    }

    struct Checkpoint {
        uint32 timestamp;
        uint224 balance;
    }

    mapping(uint256 => DelegationInfo) public delegations;
    mapping(address => Checkpoint[]) private delegateCheckpoints;

    error NotApprovedOrOwner();

    error CanNotDelegateeToAddressZero();

    error SenderNotADelegatee(address delegatee, address sender);

    error TokenNotDelegated(uint256 tokenId);

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
    }

    // Called by the delegator..
    function delegate(uint256[] calldata _tokenIds, address _to) public {
        if (_to == address(0)) {
            revert CanNotDelegateeToAddressZero();
        }

        address sender = _msgSender();

        uint256 add = 0;
        uint256 subtract = 0;

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];

            // ensure the sender owns the `tokenId`.
            if (!IVotingEscrow(escrow).isApprovedOrOwner(sender, tokenId)) {
                revert NotApprovedOrOwner();
            }

            DelegationInfo storage info = delegations[tokenId];

            uint256 oldVotingPower = info.votingPower;
            uint256 newVotingPower = IVotingEscrow(escrow).votingPowerAt(tokenId, block.timestamp);

            address currentDelegatee = info.delegatee;

            if (currentDelegatee == address(0)) {
                // token has no delegatee
                add += newVotingPower;
            } else if (currentDelegatee == _to) {
                // the delegatee didn't change
                subtract += oldVotingPower;
                add += newVotingPower;
            } else {
                // the delegatee changes, reduce old delegatee, add new delegatee balances.
                _store(currentDelegatee, oldVotingPower, 0);
                add += newVotingPower;
            }

            info.delegatee = _to;
            info.votingPower = newVotingPower;
        }

        _store(_to, subtract, add);
    }

    function undelegate(uint256[] calldata _tokenIds) public {
        address sender = _msgSender();
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];

            // ensure the sender owns the `tokenId`.
            if (!IVotingEscrow(escrow).isApprovedOrOwner(sender, tokenId)) {
                revert NotApprovedOrOwner();
            }

            DelegationInfo storage info = delegations[tokenId];

            _store(info.delegatee, info.votingPower, 0);

            info.delegatee = address(0);
            info.votingPower = 0;
        }
    }

    // Called by delegatee to re-pull the power and update its power.
    function pull(uint256[] calldata _tokenIds) public {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];

            DelegationInfo storage info = delegations[tokenId];

            if (info.delegatee == address(0)) {
                revert TokenNotDelegated(tokenId);
            }

            uint256 oldVotingPower = info.votingPower;
            uint256 newVotingPower = IVotingEscrow(escrow).votingPowerAt(tokenId, block.timestamp);

            info.votingPower = newVotingPower;

            _store(info.delegatee, oldVotingPower, newVotingPower);
        }
    }

    // Called by the escrow when the transfer of the token occurs..
    function moveDelegateVotes(address _from, address _to, uint256 _tokenId) public {
        if (_msgSender() != escrow) {
            revert OnlyEscrow();
        }

        DelegationInfo storage info = delegations[_tokenId];

        // delegatee is not set, so skip.
        if (info.delegatee == address(0)) {
            return;
        }

        // Remove voting power from current delegatee.
        _store(info.delegatee, info.votingPower, 0);

        // When the token transfer occurs, we must clear out delegatee data
        // and not automatically re-delegate it as this must only be decided by
        // the receiver by calling `delegate`.
        info.votingPower = 0;
        info.delegatee = address(0);

        // TODO: Let's think:
        // If I own a tokenId = 5 and I delegated it to Jordan, Jordan's voting power has been stored.
        // Assuming that I now transfered this tokenId = 5 to Javi, It's clear that Jordan should lose
        // the voting power that he had.
    }

    // =================== IVotes Functions ==========================

    // Problem 1:
    // TODO: The getVotes and getPastVotes below have only one problem.
    // They count the delegation part only where as we need to also count voting powers that user owns for his tokenIds.
    // This requires to first call `ownedTokens` and then loop through and call votingPowerAt for each of them and sum it up.
    // Way 1: We add votingPowerAt(different signature) function in escrow that does this and then below
    // we do: getDelegationBalance(_account, _t) + escrow.VotingPowerAtTotally..
    // Way 2: We can design a new contract where these functions of IVotes will be. It's the same idea.
    // I prefer Way 1 as this is also the case in ERC20Votes or ERC721Votes where a single contract is also IVotes
    // and also holds delegation records.
    function getVotes(address _account) external view returns (uint256) {
        uint256[] memory tokenIds = VotingEscrow(escrow).ownedTokens(_account);
        
        uint256 total = 0;

        for(uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            
            DelegationInfo storage info = delegations[tokenId];

            // Even though `_account` owns the token, it was delegated, 
            // so we shouldn't count it for this `_account`.
            if(info.delegatee == address(0)) {
                total += IVotingEscrow(escrow).votingPowerAt(tokenId, block.timestamp);
            }
        }

        return total + getDelegationBalance(_account, block.timestamp);
    }

    function getPastVotes(address _account, uint256 _timepoint) external view returns (uint256) {
        return getDelegationBalance(_account, _timepoint);
    }

    function getPastTotalSupply(uint256 _timepoint) external view returns (uint256) {
        return IVotingEscrow(escrow).totalVotingPowerAt(_timepoint);
    }

    // =========================== INTERNAL/PRIVATE Functions =========================================
    function getDelegationBalance(
        address _delegatee,
        uint256 _timestamp
    ) internal view returns (uint256) {
        // Get the latest season's start before `_t`
        (uint48 seasonStart, ) = IClockSeason(clock).seasonTsAt(uint48(_timestamp));

        Checkpoint[] storage checkpoints = delegateCheckpoints[_delegatee];

        uint256 pos = _upperBinaryLookup(checkpoints, uint32(_timestamp));

        if(pos == 0) return 0;

        Checkpoint storage checkpoint = checkpoints[pos - 1];
        
        if (seasonStart > checkpoint.timestamp) return 0;

        return checkpoint.balance;
    }

    /// @dev Note that if this function is called in the same tx multiple times, 
    ///      it only uses single slot and extra gas comes only from writing to "dirty slot".
    function _store(address _delegatee, uint256 _subtractAmount, uint256 _addAmount) private {
        Checkpoint[] storage checkpoints = delegateCheckpoints[_delegatee];
        uint256 length = checkpoints.length;

        if(length == 0) {
            checkpoints.push(Checkpoint(uint32(block.timestamp), _addAmount.toUint224()));

            return;
        }

        Checkpoint storage lastCheckpoint = checkpoints[length - 1];
        uint224 balance = (uint256(lastCheckpoint.balance) - _subtractAmount + _addAmount).toUint224();

        if(lastCheckpoint.timestamp == block.timestamp) {
            lastCheckpoint.balance = balance;
        } else {
            checkpoints.push(Checkpoint(uint32(block.timestamp), balance));
        }
    }

    function _upperBinaryLookup(
        Checkpoint[] storage _checkpoints,
        uint32 _timestamp
    ) private view returns (uint256) {
        uint256 low = 0;
        uint256 high = _checkpoints.length;

        while (low < high) {
            uint256 mid = MathUpgradeable.average(low, high);
            if(_checkpoints[mid].timestamp > _timestamp) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        return high;
    }
}
