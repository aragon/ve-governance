// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotingEscrowIncreasing as IVotingEscrow} from "../escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {ISimpleGaugeVoter} from "./ISimpleGaugeVoter.sol";

import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable as Pausable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {EpochDurationLib} from "@libs/EpochDurationLib.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";

contract SimpleGaugeVoter is ISimpleGaugeVoter, ReentrancyGuard, Pausable, PluginUUPSUpgradeable {
    /// @notice The Gauge admin can can create and manage voting gauges for token holders
    bytes32 public constant GAUGE_ADMIN_ROLE = keccak256("GAUGE_ADMIN");

    /// @notice Address of the voting escrow contract that will track voting power
    address public escrow;

    /// @notice The total votes that have accumulated in this contract
    uint256 public totalWeight;

    /// @notice Limit on the number of gauges that can be voted on to avoid gas limits
    /// @dev In the simple implementation, this might not be needed
    uint256 public maxVotingNum;

    /// @notice enumerable list of all gauges that can be voted on
    address[] public gaugeList;

    /// @notice address => gauge data
    mapping(address => Gauge) public gauges;

    /// @dev tokenId => tokenVoteData
    mapping(uint256 => TokenVoteData) internal tokenVoteData;

    /// @dev gauge => total votes (global)
    mapping(address => uint256) internal totalWeights_;

    /// @dev TODO Move to bottom of code before audit
    uint256[43] private __gap;

    /*///////////////////////////////////////////////////////////////
                            Initialization
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(address _dao, address _escrow, bool _startPaused) external initializer {
        __PluginUUPSUpgradeable_init(IDAO(_dao));
        __ReentrancyGuard_init();
        __Pausable_init();
        escrow = _escrow;
        if (_startPaused) _pause();
    }

    function pause() external auth(GAUGE_ADMIN_ROLE) whenNotPaused {
        _pause();
    }

    function unpause() external auth(GAUGE_ADMIN_ROLE) whenPaused {
        _unpause();
    }

    /*///////////////////////////////////////////////////////////////
                            Modifiers
    //////////////////////////////////////////////////////////////*/

    /// todo check activation
    modifier onlyNewEpoch(uint256 _tokenId) {
        // ensure new epoch since last vote
        // todo: check this is correct
        if (EpochDurationLib.epochStart(block.timestamp) <= tokenVoteData[_tokenId].lastVoted) {
            revert AlreadyVoted(_tokenId);
        }
        if (block.timestamp <= EpochDurationLib.epochVoteStart(block.timestamp))
            revert VotingInactive();
        _;
    }

    /*///////////////////////////////////////////////////////////////
                               Voting 
    //////////////////////////////////////////////////////////////*/

    /// @notice extrememly simple for loop. We don't need reentrancy checks in this implementation
    /// because the plugin doesn't do anything other than signal.
    function voteMultiple(
        uint256[] calldata _tokenIds,
        GaugeVote[] calldata _votes
    ) external nonReentrant whenNotPaused {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _voteAllowReentrant(_tokenIds[i], _votes);
        }
    }

    function vote(
        uint256 _tokenId,
        GaugeVote[] calldata _votes
    ) public onlyNewEpoch(_tokenId) nonReentrant whenNotPaused {
        _voteAllowReentrant(_tokenId, _votes);
    }

    /// @dev bypass reentrancy checks to enable multiple votes to be cast in a single transaction
    function _voteAllowReentrant(uint256 _tokenId, GaugeVote[] calldata _votes) internal {
        address _sender = _msgSender();
        if (!IVotingEscrow(escrow).isApprovedOrOwner(_sender, _tokenId))
            revert NotApprovedOrOwner();
        if (maxVotingNum > 0 && _votes.length > maxVotingNum) revert ExceedMaxVoteOptions();
        // TODO this logic overlaps with the onlyNewEpoch modifier and can be streamlined
        if (!votingActive()) revert VotingInactive();
        uint256 _votingPower = IVotingEscrow(escrow).votingPower(_tokenId);
        _vote(_tokenId, _votingPower, _votes);
    }

    function _vote(uint256 _tokenId, uint256 _votingPower, GaugeVote[] calldata _votes) internal {
        _reset(_tokenId);

        TokenVoteData storage voteData = tokenVoteData[_tokenId];
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
            totalWeights_[gauge] += votesForGauge;

            // track the running changes to the total
            _usedWeight += votesForGauge;
            _totalWeight += votesForGauge;

            emit Voted({
                voter: _msgSender(),
                gauge: gauge,
                tokenId: _tokenId,
                weight: votesForGauge,
                totalWeight: totalWeights_[gauge],
                timestamp: block.timestamp
            });
        }

        // more voting power is now accumulated
        totalWeight += _totalWeight;

        // record the total weight used for this vote
        voteData.usedWeight = _usedWeight;

        // setting the last voted also has the second-order effect of indicating the user has voted
        voteData.lastVoted = block.timestamp;
    }

    function reset(uint256 _tokenId) external onlyNewEpoch(_tokenId) nonReentrant whenNotPaused {
        if (!IVotingEscrow(escrow).isApprovedOrOwner(msg.sender, _tokenId))
            revert NotApprovedOrOwner();
        _reset(_tokenId);
    }

    function _reset(uint256 _tokenId) internal {
        uint256 _totalWeight = 0;
        TokenVoteData storage voteData = tokenVoteData[_tokenId];

        address[] storage pastVotes = voteData.gaugesVotedFor;

        // iterate over all the gauges voted for and reset the votes
        for (uint256 i = 0; i < pastVotes.length; i++) {
            address gauge = pastVotes[i];
            uint256 _votes = voteData.votes[gauge];

            if (_votes != 0) {
                // remove from the total weight and globals
                totalWeights_[gauge] -= _votes;
                _totalWeight += _votes;

                // remove the vote for the tokenId
                delete voteData.votes[gauge];
                delete voteData.gaugesVotedFor[i];

                emit Reset({
                    voter: _msgSender(),
                    gauge: gauge,
                    tokenId: _tokenId,
                    weight: _votes,
                    totalWeight: totalWeights_[gauge], // total weight in the gauge
                    timestamp: block.timestamp
                });
            }
        }

        totalWeight -= _totalWeight;
        voteData.usedWeight = 0;
        voteData.lastVoted = 0;

        // TODO check this cleans the state properly
        delete tokenVoteData[_tokenId];
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

    function updateGaugeMetadata(
        address _gauge,
        string calldata _metadata
    ) external auth(GAUGE_ADMIN_ROLE) {
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

    function votingActive() public view returns (bool) {
        return EpochDurationLib.votingActive(block.timestamp);
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
        return tokenVoteData[_tokenId].lastVoted > 0;
    }

    // Public getter for weights with current epoch
    function totalWeights(address _gauge) external view returns (uint256) {
        return totalWeights_[_gauge];
    }

    // Public getter for votes with current epoch
    function votes(uint256 _tokenId, address _gauge) external view returns (uint256) {
        return tokenVoteData[_tokenId].votes[_gauge];
    }

    // Public getter for poolVote with current epoch
    function gaugesVotedFor(uint256 _tokenId) external view returns (address[] memory) {
        return tokenVoteData[_tokenId].gaugesVotedFor;
    }

    function usedWeights(uint256 _tokenId) external view returns (uint256) {
        return tokenVoteData[_tokenId].usedWeight;
    }
}
