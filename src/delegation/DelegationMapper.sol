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

    // Here I think it makes sense to split the delegatee and the voting power.
    // This has no overall impact to storage other than the overhead of a second
    // mapping but would mean, in the event of seasons, we can preserve the delegatee whilst
    // resetting the voting power
    struct DelegationInfo {
        address delegatee;
        uint256 votingPower;
    }

    // tokenId => delegateAddress
    mapping(uint256 => address) public delegatees;
    // tokenId => votingPower
    mapping(uint256 => uint256) public delegatedVotingPower;
    // season => tokenId => votingPower
    mapping(uint16 => mapping(uint256 => uint256)) public delegatedVotingPower;

    struct Checkpoint {
        uint256 timestamp; // we can bound to uint48 and 208 which dovetails with our locked struct
        uint256 balance;
    }

    // you can remove this now
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

        // id just fetch this from the double mapping
        address delegatee = delegatees[_tokenId];
        uint256 votingPower = delegatedVotingPower[_tokenId];
        // if we need seasons can be indexed by season
        votingPower = delegatedVotingPower[season][tokenId];

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

    // batch pull gas efficient
    function pull(uint256[] memory _tokenIds) public {
        uint totalToSubtract = 0;
        uint totalToAdd = 0;
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            address sender = _msgSender();
            require(delegatees[_tokenId] == sender, "caller is not delegated");
            uint oldVp = delegatedVotingPower[_tokenId];
            // Fetch and store new voting power
            uint256 newVp = IVotingEscrow(escrow).votingPowerAt(_tokenId, block.timestamp);
            info.votingPower = newVp;
            totalToSubtract += oldVp;
            totalToAdd += oldVp;
        }
        _updateDelegateBalance(_msgSender(), _subtract, totalToSubtract);
        _updateDelegateBalance(_msgSender(), _add, totalToAdd);
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

        // I think we should mirror the Oz implementation here, namely:
        // Action	Delegation Status (Sender)	Delegation Status (Receiver)	Voting Checkpoint Updated?
        // Transfer	❌ No delegate	❌ No delegate	❌ No update
        // Transfer	✅ Delegated (self/other)	❌ No delegate	✅ Sender delegate decreases
        // Transfer	❌ No delegate	✅ Delegated (self/other)	✅ Receiver delegate increases
        // Transfer	✅ Delegated (A)	✅ Delegated (B)	✅ Delegate A decreases, Delegate B increases
        // Mint (to address)	N/A (minting)	✅ Delegated (receiver)	✅ Delegate (receiver) increases, total votes increase
        // Mint (to address)	N/A (minting)	❌ No delegate	✅ Total votes increase, no delegate increases
        // Burn (from address)	✅ Delegated (sender)	N/A (burning)	✅ Delegate (sender) decreases, total votes decrease
        // Burn (from address)	❌ No delegate	N/A (burning)	✅ Total votes decrease, no delegate decreases

        // so in the above case when giorgi transfers to javi, we update the delegation to jordan EXCEPT in the event
        // that javi also delegates to jordan. In OZ they do the check if (to != from) and call delegates(to) and delegates(from)
        // if these values are equal the delgation is skipped.
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

    // another option is that we mandate self delegation for voting. This is the same as in the ERC20Votes case
    // and to be further compatible with Aragon we could auto self delegate on mint.
    // Let's think about the mandatory self-delegation.
    // It means voting power is frozen for the user unless they update which also means in a checkpoint-based system
    // they have to update BEFORE the voting checkpoint (same for delegates).
    // In the case of, say, Optimistic voting, we need to consider this behaviour carefully.
    // Another problem with checkpoint based voting is that the initial self delegation with warmups will be zero.
    // and the user would have to come back after the warmup to activate votes.
    // So I think in general we need to think about what we are trying to do. Mixing checkpoint and continuous voting
    // doesn't make a whole lot of sense.

    // out of your options then:

    // I don't mind 1. The loop over owned tokens is a gas risk though. Honestly I'd prefer to stick to an ivotes signature
    // as this means we can start utilising the gauge voter outside VE and VE outside the gauges.
    // Way 2 I'm guessing just duplicates the IVotes functions. Not a fan tbh.
    // Way 3 might work. If we are planning to use delegation checkpoints I think they should ignore warmups. Maybe we can expose
    // a version of getBias that ignores warmups.
    // The issue then is that with new builds they would need to self delegate. If we aren't using checkpoints (i.e. in the gauge voter)
    // frontend can check for any pending voting power and run `pull` prior to voting

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
        // looking at OZ we can do some checks for redundancy here, namely don't update
        // if the delegation is unchanged
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

    function _add(uint256 a, uint256 b) private pure returns (uint256) {
        return a + b;
    }

    function _subtract(uint256 a, uint256 b) private pure returns (uint256) {
        return a - b;
    }
}

