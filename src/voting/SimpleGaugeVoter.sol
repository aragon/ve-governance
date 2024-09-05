// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotingEscrowIncreasing as IVotingEscrow} from "../escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {ISimpleGaugeVoter} from "./ISimpleGaugeVoter.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EpochDurationLib} from "@libs/EpochDurationLib.sol";
import {Plugin} from "@aragon/osx/core/plugin/Plugin.sol";

contract SimpleGaugeVoter is ISimpleGaugeVoter, ReentrancyGuard, Plugin {
    /// @notice The Gauge admin can can create and manage voting gauges for token holders
    bytes32 public constant GAUGE_ADMIN_ROLE = keccak256("GAUGE_ADMIN");

    /// @notice Address of the voting escrow contract that will track voting power
    address public escrow;

    /// @notice The total votes that have accumulated in this contract
    uint256 public totalWeight;

    /// @notice Limit on the number of gauges that can be voted on to avoid gas limits
    /// @dev In the simple implementation, this might not be needed
    uint256 public maxVotingNum;

    /// @notice A timestamp indicating when the contract was activated
    uint256 public activated;

    /// @notice if true, will reset votes at the start of each epoch
    bool public autoReset;

    /// @notice enumerable list of all gauges that can be voted on
    address[] public gaugeList;

    /// @notice address => gauge data
    mapping(address => Gauge) public gauges;

    /// @dev epoch => tokenId => tokenVoteData
    mapping(uint256 => mapping(uint256 => TokenVoteData)) internal tokenVoteData;

    /// @dev epoch => gauge => total votes (global)
    mapping(uint256 => mapping(address => uint256)) internal totalWeights_;

    /*///////////////////////////////////////////////////////////////
                            Initialization
    //////////////////////////////////////////////////////////////*/

    constructor(address _dao, address _escrow, bool _autoReset) Plugin(IDAO(_dao)) {
        escrow = _escrow;
        maxVotingNum = 30;
        autoReset = _autoReset;
    }

    // todo if we make this upgradeable we will need a separate activation function
    function initializer() external auth(GAUGE_ADMIN_ROLE) {
        require(activated == 0, "already activated");
        activated = block.timestamp;
    }

    /*///////////////////////////////////////////////////////////////
                            Modifiers
    //////////////////////////////////////////////////////////////*/

    /// todo check activation
    modifier onlyNewEpoch(uint256 _tokenId) {
        // ensure new epoch since last vote
        // todo: check this is correct
        if (EpochDurationLib.epochStart(block.timestamp) <= tokenVoteData[currentEpoch()][_tokenId].lastVoted) {
            revert AlreadyVoted(_tokenId, currentEpoch());
        }
        if (block.timestamp <= EpochDurationLib.epochVoteStart(block.timestamp)) revert VotingInactive();
        _;
    }

    /*///////////////////////////////////////////////////////////////
                               Voting 
    //////////////////////////////////////////////////////////////*/

    function vote(uint256 _tokenId, GaugeVote[] calldata _votes) external onlyNewEpoch(_tokenId) nonReentrant {
        address _sender = _msgSender();
        if (!IVotingEscrow(escrow).isApprovedOrOwner(_sender, _tokenId)) revert NotApprovedOrOwner();
        // if (_votes.length > maxVotingNum) revert TooManyPools();
        // if ((_timestamp > EpochDurationLib.epochVoteEnd(_timestamp))) revert("epochVoteEnd"); // TODO
        if (!votingActive()) revert("VotingInactive()"); // TODO
        uint256 votingPower = IVotingEscrow(escrow).votingPower(_tokenId);
        _vote(_tokenId, votingPower, _votes);
    }

    function _vote(uint256 _tokenId, uint256 _votingPower, GaugeVote[] calldata _votes) internal {
        _reset(_tokenId);

        uint256 _currentEpoch = _storageEpoch();
        TokenVoteData storage voteData = tokenVoteData[_currentEpoch][_tokenId];
        uint256 numVotes = _votes.length;
        uint256 sumOfWeights = 0;
        uint256 _totalWeight = 0;
        uint256 _usedWeight = 0;

        // calculate total weight to use as denominator
        for (uint256 i = 0; i < numVotes; i++) {
            sumOfWeights += _votes[i].weight;
        }

        // iterate over votes and distribute weight
        for (uint256 i = 0; i < numVotes; i++) {
            // the gauge must exist and be active,
            // it also can't have any votes or we haven't reset properly
            address gauge = _votes[i].gauge;

            if (!gaugeExists(gauge)) revert GaugeDoesNotExist(gauge);
            if (!isActive(gauge)) revert GaugeInactive(gauge);
            if (voteData.votes[gauge] != 0) revert NonZeroVotes();

            // calculate the weight for this gauge
            uint256 votesForGauge = (_votes[i].weight * _votingPower) / sumOfWeights;
            if (votesForGauge == 0) revert NoVotes();

            // record the vote for the token
            voteData.gaugesVotedFor.push(gauge);
            voteData.votes[gauge] += votesForGauge;

            // update the total weights accruing to this gauge
            totalWeights_[_currentEpoch][gauge] += votesForGauge;

            // track the running changes to the total
            _usedWeight += votesForGauge;
            _totalWeight += votesForGauge;

            emit Voted({
                voter: _msgSender(),
                gauge: gauge,
                tokenId: _tokenId,
                weight: votesForGauge,
                totalWeight: totalWeights_[_currentEpoch][gauge],
                timestamp: timestamp()
            });
        }

        // TODO - there's probably an easier way to track this, like lastVoted
        // todo this will always say voted = true so we need to check
        // if reset will work with zero votes
        // if (_usedWeight > 0) IVotingEscrow(escrow).voting(_tokenId, true);

        // more voting power is now accumulated
        totalWeight += _totalWeight;

        // record the total weight used for this vote
        voteData.usedWeight = _usedWeight;
        voteData.lastVoted = timestamp();
    }

    function reset(uint256 _tokenId) external onlyNewEpoch(_tokenId) nonReentrant {
        if (!IVotingEscrow(escrow).isApprovedOrOwner(msg.sender, _tokenId)) revert NotApprovedOrOwner();
        _reset(_tokenId);
    }

    function _reset(uint256 _tokenId) internal {
        uint256 _totalWeight = 0;
        uint256 _currentEpoch = _storageEpoch();
        TokenVoteData storage voteData = tokenVoteData[_currentEpoch][_tokenId];

        address[] storage pastVotes = voteData.gaugesVotedFor;

        // iterate over all the gauges voted for and reset the votes
        for (uint256 i = 0; i < pastVotes.length; i++) {
            address gauge = pastVotes[i];
            uint256 _votes = voteData.votes[gauge];

            if (_votes != 0) {
                // remove from the total weight and globals
                totalWeights_[_currentEpoch][gauge] -= _votes;
                _totalWeight += _votes;

                // remove the vote for the tokenId
                delete voteData.votes[gauge];
                delete voteData.gaugesVotedFor[i];

                emit Reset({
                    voter: _msgSender(),
                    gauge: gauge,
                    tokenId: _tokenId,
                    weight: _votes,
                    totalWeight: totalWeights_[_currentEpoch][gauge], // total weight in the gauge
                    timestamp: timestamp()
                });
            }
        }

        // we could here reset the last voted, or even just store this locally
        // for easy querying
        // IVotingEscrow(escrow).voting(_tokenId, false);

        totalWeight -= _totalWeight;
        voteData.usedWeight = 0;
        voteData.lastVoted = 0;

        // TODO check this cleans the state properly
        delete tokenVoteData[_currentEpoch][_tokenId];
    }

    /*///////////////////////////////////////////////////////////////
                            Gauge Management
    //////////////////////////////////////////////////////////////*/

    function gaugeExists(address _gauge) public view returns (bool) {
        return gauges[_gauge].created > 0;
    }

    function isActive(address _gauge) public view returns (bool) {
        return gauges[_gauge].active;
    }

    function createGauge(
        address _gauge,
        string calldata _metadata
    ) external auth(GAUGE_ADMIN_ROLE) nonReentrant returns (address gauge) {
        if (gaugeExists(_gauge)) revert GaugeExists();

        gauges[_gauge] = Gauge(true, block.timestamp, bytes32(abi.encode(_metadata)));
        gaugeList.push(_gauge);

        emit GaugeCreated(_gauge, _msgSender(), _metadata);
        return _gauge;
    }

    function deactivateGauge(address _gauge) external auth(GAUGE_ADMIN_ROLE) {
        if (!gaugeExists(_gauge)) revert GaugeDoesNotExist(_gauge);
        if (!isActive(_gauge)) revert GaugeActivationUnchanged();
        gauges[_gauge].active = false;
        emit GaugeDeactivated(_gauge);
    }

    /// optimise - could use a storage pointer
    function activateGauge(address _gauge) external auth(GAUGE_ADMIN_ROLE) {
        if (!gaugeExists(_gauge)) revert GaugeDoesNotExist(_gauge);
        if (isActive(_gauge)) revert GaugeActivationUnchanged();
        gauges[_gauge].active = true;
        emit GaugeActivated(_gauge);
    }

    function updateGaugeMetadata(address _gauge, string calldata _metadata) external auth(GAUGE_ADMIN_ROLE) {
        if (!gaugeExists(_gauge)) revert GaugeDoesNotExist(_gauge);
        gauges[_gauge].metadata = keccak256(abi.encode(_metadata)); // todo
        emit GaugeMetadataUpdated(_gauge, _metadata);
    }

    /// TOOD Might not be needed
    function setMaxVotingNum(uint256 _maxVotingNum) external auth(GAUGE_ADMIN_ROLE) {
        maxVotingNum = _maxVotingNum;
    }

    /*///////////////////////////////////////////////////////////////
                          Getters: Epochs & Time
    //////////////////////////////////////////////////////////////*/

    // relative time since activation
    // todo better name
    function timestamp() public view returns (uint256) {
        return block.timestamp - activated;
    }

    // time since activation
    // todo: check escrow also snaps to activation time
    function currentEpoch() public view returns (uint256) {
        return timestamp() / EpochDurationLib.EPOCH_DURATION;
    }

    // if autoReset is false, stick to a single epoch
    function _storageEpoch() internal view returns (uint256) {
        return autoReset ? currentEpoch() : 0;
    }

    function votingActive() public view returns (bool) {
        return EpochDurationLib.votingActive(timestamp());
    }

    function epochStart(uint256 _timestamp) external pure returns (uint256) {
        return EpochDurationLib.epochStart(_timestamp);
    }

    function epochNext(uint256 _timestamp) external pure returns (uint256) {
        return EpochDurationLib.epochNext(_timestamp);
    }

    function epochVoteStart(uint256 _timestamp) external pure returns (uint256) {
        return EpochDurationLib.epochVoteStart(_timestamp);
    }

    function epochVoteEnd(uint256 _timestamp) external pure returns (uint256) {
        return EpochDurationLib.epochVoteEnd(_timestamp);
    }

    /*///////////////////////////////////////////////////////////////
                            Getters: Mappings
    //////////////////////////////////////////////////////////////*/

    function getAllGauges() external view returns (address[] memory) {
        return gaugeList;
    }

    function isVoting(uint256 _tokenId) external view returns (bool) {
        return tokenVoteData[currentEpoch()][_tokenId].lastVoted > 0;
    }

    // Public getter for weights with current epoch
    function totalWeights(address _gauge) external view returns (uint256) {
        return totalWeights_[currentEpoch()][_gauge];
    }

    // Public getter for weights with specific epoch
    function totalWeightsAt(uint256 _epoch, address _gauge) external view returns (uint256) {
        return totalWeights_[_epoch][_gauge];
    }

    // Public getter for votes with current epoch
    function votes(uint256 _tokenId, address _gauge) external view returns (uint256) {
        return tokenVoteData[currentEpoch()][_tokenId].votes[_gauge];
    }

    // Public getter for votes with specific epoch
    function votesAt(uint256 _epoch, uint256 _tokenId, address _gauge) external view returns (uint256) {
        return tokenVoteData[_epoch][_tokenId].votes[_gauge];
    }

    // Public getter for poolVote with current epoch
    function gaugesVotedFor(uint256 _tokenId) external view returns (address[] memory) {
        return tokenVoteData[currentEpoch()][_tokenId].gaugesVotedFor;
    }

    // Public getter for poolVote with specific epoch
    function gaugesVotedForAt(uint256 _epoch, uint256 _tokenId) external view returns (address[] memory) {
        return tokenVoteData[_epoch][_tokenId].gaugesVotedFor;
    }

    // Public getter for usedWeights with current epoch
    function usedWeights(uint256 _tokenId) external view returns (uint256) {
        return tokenVoteData[currentEpoch()][_tokenId].usedWeight;
    }

    // Public getter for usedWeights with specific epoch
    function usedWeightsAt(uint256 _epoch, uint256 _tokenId) external view returns (uint256) {
        return tokenVoteData[_epoch][_tokenId].usedWeight;
    }
}
