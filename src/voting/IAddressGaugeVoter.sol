/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    IGaugeManager,
    IGauge,
    IGaugeVoterEvents,
    IGaugeVoterErrors,
    IGaugeManagerEvents,
    IGaugeManagerErrors
} from "./ISimpleGaugeVoter.sol";

interface IAddressGaugeVote {
    /// @param votes gauge => votes cast at that time
    /// @param gaugesVotedFor array of gauges we have active votes for
    /// @param usedVotingPower total voting power used at the time of the vote
    /// @dev this changes so we need an historic snapshot
    /// @param lastVoted is the last time the user voted
    struct AddressVoteData {
        mapping(address => uint256) voteWeights;
        address[] gaugesVotedFor;
        uint256 usedVotingPower;
        uint256 lastVoted;
    }

    /// @param weight proportion of voting power the address will allocate to the gauge. Will be normalised.
    /// @param gauge address of the gauge to vote for
    struct GaugeVote {
        uint256 weight;
        address gauge;
    }
}

/*///////////////////////////////////////////////////////////////
                            Gauge Voter
//////////////////////////////////////////////////////////////*/

interface IAddressGaugeVoterEvents {
    /// @param votingPowerCastForGauge votes cast by this address for this gauge in this vote
    /// @param totalVotingPowerInGauge total voting power in the gauge at the time of the vote, after applying the vote
    /// @param totalVotingPowerInContract total voting power in the contract at the time of the vote, after applying the vote
    event Voted(
        address indexed voter,
        address indexed gauge,
        uint256 indexed epoch,
        uint256 votingPowerCastForGauge,
        uint256 totalVotingPowerInGauge,
        uint256 totalVotingPowerInContract,
        uint256 timestamp
    );

    /// @param votingPowerRemovedFromGauge votes removed by this address for this gauge, at the time of this rest
    /// @param totalVotingPowerInGauge total voting power in the gauge at the time of the reset, after applying the reset
    /// @param totalVotingPowerInContract total voting power in the contract at the time of the reset, after applying the reset
    event Reset(
        address indexed voter,
        address indexed gauge,
        uint256 indexed epoch,
        uint256 votingPowerRemovedFromGauge,
        uint256 totalVotingPowerInGauge,
        uint256 totalVotingPowerInContract,
        uint256 timestamp
    );
}

interface IAddressGaugeVoterErrors {
    error VotingInactive();
    error NotApprovedOrOwner();
    error GaugeDoesNotExist(address _pool);
    error GaugeInactive(address _gauge);
    error DoubleVote();
    error NoVotes();
    error NoVotingPower();
    error NotCurrentlyVoting();
    error OnlyIVotesAdapter();
    error UpdateVotingPowerHookNotEnabled();
    error AlreadyVoted(address _address);
}

interface IAddressGaugeVoter is
    IAddressGaugeVoterEvents,
    IAddressGaugeVoterErrors,
    IAddressGaugeVote,
    IGaugeManager,
    IGauge
{
    /// @notice Called by users to vote for pools. Votes distributed proportionally based on weights.
    /// @param _votes       Array of votes to be cast, contains gauge address and weight.
    function vote(GaugeVote[] memory _votes) external;

    /// @notice Called by users to reset voting state. Required when withdrawing or transferring veNFT.
    function reset() external;

    /// @notice Can be called to check if an address is currently voting
    function isVoting(address _address) external view returns (bool);

    function updateVotingPower(address _from, address _to) external;
}

/*///////////////////////////////////////////////////////////////
                      Address Gauge Voter
//////////////////////////////////////////////////////////////*/

interface IAddressGaugeVoterStorageEventsErrors is
    IGaugeManagerEvents,
    IGaugeManagerErrors,
    IAddressGaugeVoterEvents,
    IAddressGaugeVoterErrors
{}
