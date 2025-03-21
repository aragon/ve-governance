/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotingEscrowIncreasingV1_4_0 as IVotingEscrow} from "@escrow/IVotingEscrowIncreasing_v1_4_0.sol";
import {IClockUser, IClock} from "@clock/IClock.sol";
import {IClockSeason} from "@clock/IClockSeason.sol";

import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";
import {IVotes, IDelegationMapper} from "./IDelegationMapper.sol";

contract DelegationMapper is
    IClockUser,
    ReentrancyGuard,
    IDelegationMapper,
    IVotes,
    PluginUUPSUpgradeable
{
    /// @notice Address of the voting escrow contract that will track voting power
    address public escrow;

    /// @notice Clock contract for epoch duration
    address public clock;

    struct DelegationInfo {
        address delegatee;
        uint256 votingPower;
    }

    struct Checkpoint {
        uint256 timestamp;
        uint256 balance;
    }

    struct DelegationHistory {
        uint256 timestamp;
        address delegatee;
    }

    mapping(uint256 => DelegationHistory[]) public delegationHistories;

    // tokenId => history
    mapping(uint256 => DelegationInfo) public delegations;
    mapping(address => Checkpoint[]) public delegateCheckpoints;

    error NotApprovedOrOwner();

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
    function delegate(uint256 _tokenId, address _to) public {
        address sender = _msgSender();

        // ensure the sender owns the `_tokenId`.
        if (!IVotingEscrow(escrow).isApprovedOrOwner(sender, _tokenId)) {
            revert NotApprovedOrOwner();
        }

        DelegationInfo storage info = delegations[_tokenId];

        uint256 currentVotingPower = IVotingEscrow(escrow).votingPowerAt(_tokenId, block.timestamp);

        if (info.delegatee != _to) {
            // Reduce old delegate's balance
            _updateDelegateBalance(info.delegatee, _subtract, info.votingPower);
        }

        info.delegatee = _to;
        info.votingPower = currentVotingPower;

        _updateDelegateBalance(_to, _add, currentVotingPower);
    }

    // Called by delegatee to re-pull the power and update its power.
    function pull(uint256 _tokenId) public {
        address sender = _msgSender();

        DelegationInfo storage info = delegations[_tokenId];

        require(info.delegatee == sender, "caller is not delegated");

        // Subtract old power
        _updateDelegateBalance(sender, _subtract, info.votingPower);

        // Fetch and store new voting power
        uint256 newVotingPower = IVotingEscrow(escrow).votingPowerAt(_tokenId, block.timestamp);
        info.votingPower = newVotingPower;

        // Add new power
        _updateDelegateBalance(sender, _add, newVotingPower);
    }

    function pullAt(uint256 _tokenId, address _dst, uint48 _at) public nonRentrant {
        // fetch delegation history using binary search
	(address delegate, uint48 ts) = getPriorDelegateHistory(_tokenId, _at)
	require(_dst == delegate, "not delegated at the time");
	require(ts <= _at, "seems unlikely");


	if (ts != _at) {
	
	// get the votes for the token id
        uint256 votesPrev =  IVotingEscrow(escrow).votingPowerAt(_tokenId, ts);
        uint256 votesCurr =  IVotingEscrow(escrow).votingPowerAt(_tokenId, _at);

	uint dif = votesCurr - votesPrev;

	// then add at _at
	_updateDelegateBalanceAt(delegate, _add, dif, _tokenId, _at);
	}
	

    }

    // Called by the escrow when the transfer of the token occurs..
    function moveDelegateVotes(address _from, address _to, uint256 _tokenId) public {
        if (_msgSender() != escrow) {
            revert OnlyEscrow();
        }

        DelegationInfo storage info = delegations[_tokenId];

        // Remove voting power from old delegatee
        _updateDelegateBalance(info.delegatee, _subtract, info.votingPower);

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
    // we do: getPriorDelegateBalance(_account, _t) + escrow.VotingPowerAtTotally..
    // Way 2: We can design a new contract where these functions of IVotes will be. It's the same idea.
    // I prefer Way 1 as this is also the case in ERC20Votes or ERC721Votes where a single contract is also IVotes
    // and also holds delegation records.
    // Problem 2:
    // Currently, I don't use the seasons. Even if I do, It seems tricky. While we can
    // use indexes of seasons in a mapping(i.e store each stuff on the latest season), what if
    // season starts and user asks for getPastVotes for a user for the timestamp > seasonStart
    // This would return 0. We need to come up with solid plans around this topic..
    function getVotes(address _account) external view returns (uint256) {
        (uint48 seasonStart, ) = IClockSeason(clock).seasonTsAt(uint48(block.timestamp));

        return getPriorDelegateBalance(_account, block.timestamp);
    }

    function getPastVotes(address _account, uint256 _timepoint) external view returns (uint256) {
        (uint48 seasonStart, ) = IClockSeason(clock).seasonTsAt(uint48(_timepoint));

        return getPriorDelegateBalance(_account, _timepoint);
    }

    function getPastTotalSupply(uint256 _timepoint) external view returns (uint256) {
        return IVotingEscrow(escrow).totalVotingPowerAt(_timepoint);
    }

    // =========================== INTERNAL/PRIVATE Functions =========================================

    function _updateDelegateBalance(
        address _delegate,
        function(uint256, uint256) view returns (uint256) _op,
        uint256 _delta
    ) internal {
        uint256 currentBalance = 0;

        uint256 length = delegateCheckpoints[_delegate].length;
        if (length != 0) {
            currentBalance = delegateCheckpoints[_delegate][length - 1].balance;
        }

        // Store a new checkpoint
        delegateCheckpoints[_delegate].push(
            Checkpoint(block.timestamp, _op(currentBalance, _delta))
        );
    }

    function getPriorDelegateBalance(
        address _delegate,
        uint256 _t
    ) internal view returns (uint256) {
        Checkpoint[] storage checkpoints = delegateCheckpoints[_delegate];
        uint256 length = checkpoints.length;
        if (length == 0 || checkpoints[0].timestamp > _t) {
            return 0;
        }
a
        uint256 low = 0;
        uint256 high = length - 1;

        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            if (checkpoints[mid].timestamp <= _t) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        return checkpoints[low].balance;
    }

    function getPriorDelegateHistory(
        uint256 _tokenId,
        uint256 _t
    ) internal view returns (address, timestamp) {
        DelegationHistory[] storage checkpoints = delegationHistories[_tokenId];
        uint256 length = checkpoints.length;
        if (length == 0 || checkpoints[0].timestamp > _t) {
            return 0;
        }
        uint256 low = 0;
        uint256 high = length - 1;

        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            if (checkpoints[mid].timestamp <= _t) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }
        return checkpoints[low];
    }

function _updateDelegateBalanceAt(
  address _delegate,
  function(uint256, uint256) view returns (uint256) _op,
  uint256 _delta,
  uint256 _at
) internal {
  uint256 idx = 0;
  bool isExact = false;

  uint256 length = delegateCheckpoints[_delegate].length;
  if (length != 0) {
    // do a binary search to fetch the index
    // isExact is 
    (idx, isExact) = getPriorDelegateIndex(_delegate, _at);
  }

  // is there is not a match, insert a record at idx + 1 
  if (!isExact) {
    // if at the .length, must be a push
  }

  // get the most recent value
  uint bal = delegateCheckpoints[_delegate][idx].balance;

  // diff the balance
  _op(bal, _delta);
}


    function _add(uint256 a, uint256 b) private pure returns (uint256) {
        return a + b;
    }

    function _subtract(uint256 a, uint256 b) private pure returns (uint256) {
        return a - b;
    }
}

