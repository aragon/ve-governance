// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGauge {
    struct Gauge {
        bool active;
        uint256 created; // timestamp or epoch
        bytes32 metadata; // TODO - check how OSx stores this, might just be IPFS
        // address addr; // TODO do we need this
        // more space for data as this is a struct in a mapping
    }
}

interface IGaugeVote {
    struct TokenVoteData {
        mapping(address => uint256) votes;
        address[] gaugesVotedFor;
        uint256 usedWeight;
        uint256 lastVoted;
    }

    struct GaugeVote {
        uint256 weight;
        address gauge;
    }
}

/*///////////////////////////////////////////////////////////////
                            Gauge Manager
//////////////////////////////////////////////////////////////*/

interface IGaugeManagerEvents {
    event GaugeCreated(address indexed gauge, address indexed creator, string metadata);
    event GaugeDeactivated(address indexed gauge);
    event GaugeActivated(address indexed gauge);
    event GaugeMetadataUpdated(address indexed gauge, string metadata);
}

interface IGaugeManagerErrors {
    error GaugeActivationUnchanged();
    error GaugeExists();
}

interface IGaugeManager is IGaugeManagerEvents, IGaugeManagerErrors {
    function isActive(address gauge) external view returns (bool);

    function createGauge(address _gauge, string calldata _metadata) external returns (address);

    function deactivateGauge(address _gauge) external;

    function activateGauge(address _gauge) external;

    function updateGaugeMetadata(address _gauge, string calldata _metadata) external;
}

/*///////////////////////////////////////////////////////////////
                            Gauge Voter
//////////////////////////////////////////////////////////////*/

interface IGaugeVoterEvents {
    event Voted(
        address indexed voter,
        address indexed gauge,
        uint256 indexed tokenId,
        uint256 weight,
        uint256 totalWeight,
        uint256 timestamp
    );
    event Reset(
        address indexed voter,
        address indexed gauge,
        uint256 indexed tokenId,
        uint256 weight,
        uint256 totalWeight,
        uint256 timestamp
    );
}

interface IGaugeVoterErrors {
    error AlreadyVoted(uint256 tokenId);
    error VotingInactive();
    error NotApprovedOrOwner();
    error GaugeDoesNotExist(address _pool);
    error GaugeInactive(address _gauge);
    error NonZeroVotes();
    error NoVotes();
    error ExceedMaxVoteOptions();
}

interface IGaugeVoter is IGaugeVoterEvents, IGaugeVoterErrors, IGaugeVote {
    /// @notice Called by users to vote for pools. Votes distributed proportionally based on weights.
    /// @param _tokenId     Id of veNFT you are voting with.
    /// @param _votes       Array of votes to be cast, contains gauge address and weight.
    function vote(uint256 _tokenId, GaugeVote[] memory _votes) external;

    /// @notice Called by users to reset voting state. Required when withdrawing or transferring veNFT.
    /// @param _tokenId Id of veNFT you are reseting.
    function reset(uint256 _tokenId) external;

    function isVoting(uint256 _tokenId) external view returns (bool);
}

/*///////////////////////////////////////////////////////////////
                        Simple Gauge Voter
//////////////////////////////////////////////////////////////*/

interface ISimpleGaugeVoter is IGaugeVoter, IGaugeManager, IGauge {

}

interface ISimpleGaugeVoterStorageEventsErrors is
    IGaugeManagerEvents,
    IGaugeManagerErrors,
    IGaugeVoterEvents,
    IGaugeVoterErrors
{}
