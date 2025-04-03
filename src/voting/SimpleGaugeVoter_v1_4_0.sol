/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotingEscrowIncreasing as IVotingEscrow} from "@escrow/IVotingEscrowIncreasing.sol";
import {IClockUser, IClock, IClockSeason} from "@clock/Clock_v1_2_0.sol";
import {ISimpleGaugeVoter} from "./ISimpleGaugeVoter_v1_4_0.sol";
import {IVotes} from "../delegation/IDelegationMapper.sol";

import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable as Pausable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";

contract SimpleGaugeVoterV1_4_0 is
    ISimpleGaugeVoter,
    IClockUser,
    ReentrancyGuard,
    Pausable,
    PluginUUPSUpgradeable
{
    /// @notice The Gauge admin can can create and manage voting gauges for token holders
    bytes32 public constant GAUGE_ADMIN_ROLE = keccak256("GAUGE_ADMIN");

    /// @notice Address of the voting escrow contract that will track voting power
    address public escrow;

    /// @notice Clock contract for epoch duration
    address public clock;

    /// @notice season => The total votes that have accumulated in this contract
    mapping(uint16 => uint256) public seasonTotalVotingPowerCast;

    /// @notice enumerable list of all gauges that can be voted on
    address[] public gaugeList;

    /// @notice address => gauge data
    mapping(address => Gauge) public gauges;

    /// @notice season => gauge => total votes (global)
    mapping(uint16 => mapping(address => uint256)) public seasonGaugeVotes;

    /// @dev epoch => tokenId => AddressVoteData
    mapping(uint16 => mapping(address => AddressVoteData)) internal seasonTokenVoteData;

    /// @notice Delegation mapper contract
    address public delegationMapper;

    /*///////////////////////////////////////////////////////////////
                            Initialization
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _dao,
        address _escrow,
        bool _startPaused,
        address _clock,
        address _delegationMapper
    ) external initializer {
        __PluginUUPSUpgradeable_init(IDAO(_dao));
        __ReentrancyGuard_init();
        __Pausable_init();
        escrow = _escrow;
        clock = _clock;
        delegationMapper = _delegationMapper;
        if (_startPaused) _pause();
    }

    function initializeFrom(address _delegationMapper) public {
        delegationMapper = _delegationMapper;
    }

    /*///////////////////////////////////////////////////////////////
                            Modifiers
    //////////////////////////////////////////////////////////////*/

    function pause() external auth(GAUGE_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external auth(GAUGE_ADMIN_ROLE) {
        _unpause();
    }

    modifier whenVotingActive() {
        if (!votingActive()) revert VotingInactive();
        _;
    }

    modifier onlyDelegationMapper() {
        if (msg.sender != delegationMapper) revert OnlyDelegationMapper();
        _;
    }

    /*///////////////////////////////////////////////////////////////
                               Voting
    //////////////////////////////////////////////////////////////*/

    /// @notice extrememly simple for loop. We don't need reentrancy checks in this implementation
    /// because the plugin doesn't do anything other than signal.
    function voteMultiple(
        address[] calldata _address,
        GaugeVote[] calldata _votes
    ) external nonReentrant whenNotPaused whenVotingActive {
        // unimplemented
        revert("Not implemented");
    }

    function vote(
        address _address,
        GaugeVote[] calldata _votes
    ) public nonReentrant whenNotPaused whenVotingActive {
        // Check voter address is == _address
        if (msg.sender != _address) revert NotApprovedOrOwner();
        _vote(_address, _votes);
    }

    /// @notice Cast the vote of an tokenId to a specific gauge
    function _castVote(
        GaugeVote memory currentVote,
        uint16 season,
        address _address,
        uint256 votingPower,
        uint256 sumOfWeights,
        AddressVoteData storage voteData
    ) internal returns (uint256) {
        // the gauge must exist and be active,
        // it also can't have any votes or we haven't reset properly
        if (!gaugeExists(currentVote.gauge)) revert GaugeDoesNotExist(currentVote.gauge);
        if (!isActive(currentVote.gauge)) revert GaugeInactive(currentVote.gauge);

        // prevent double voting
        if (voteData.votes[currentVote.gauge] != 0) revert DoubleVote();

        // calculate the weight for this gauge
        uint256 votesForGauge = (currentVote.weight * votingPower) / sumOfWeights;
        if (votesForGauge == 0) revert NoVotes();

        // record the vote for the token
        voteData.gaugesVotedFor.push(currentVote.gauge);
        voteData.votes[currentVote.gauge] += votesForGauge;

        // update the total weights accruing to this gauge
        seasonGaugeVotes[season][currentVote.gauge] += votesForGauge;
        seasonTotalVotingPowerCast[season] += votesForGauge;
        voteData.usedVotingPower += votesForGauge;

        emit Voted({
            voter: _address,
            gauge: currentVote.gauge,
            epoch: epochId(),
            votingPowerCastForGauge: votesForGauge,
            totalVotingPowerInGauge: seasonGaugeVotes[season][currentVote.gauge],
            totalVotingPowerInContract: seasonTotalVotingPowerCast[season],
            timestamp: block.timestamp
        });

        return votesForGauge;
    }

    /// @notice Cast the vote of an tokenId to the selected gauges
    function _vote(address _address, GaugeVote[] memory _votes) internal {
        uint256 votingPower = IVotes(delegationMapper).getVotes(_address);
        if (votingPower == 0) revert NoVotingPower();

        uint256 numVotes = _votes.length;
        if (numVotes == 0) revert NoVotes();

        // clear any existing votes
        if (isVoting(_address)) _reset(_address);

        uint16 season = IClockSeason(clock).currentSeasonIndex();

        // voting power continues to increase over the voting epoch.
        // this means you can revote later in the epoch to increase votes.
        // while not a huge problem, it's worth noting that when rewards are fully
        // on chain, this could be a vector for gaming.
        AddressVoteData storage voteData = seasonTokenVoteData[season][_address];
        uint256 sumOfWeights = 0;

        for (uint256 i = 0; i < numVotes; i++) {
            sumOfWeights += _votes[i].weight;
        }

        // this is technically redundant as checks below will revert div by zero
        // but it's clearer to the caller if we revert here
        if (sumOfWeights == 0) revert NoVotes();

        // iterate over votes and distribute weight
        for (uint256 i = 0; i < numVotes; i++) {
            GaugeVote memory currentVote = _votes[i];
            _castVote(currentVote, season, _address, votingPower, sumOfWeights, voteData);
        }

        // setting the last voted also has the second-order effect of indicating the user has voted
        voteData.lastVoted = block.timestamp;
    }

    function reset(address _address) external nonReentrant whenNotPaused whenVotingActive {
        if (msg.sender != _address) revert NotApprovedOrOwner();
        if (!isVoting(_address)) revert NotCurrentlyVoting();
        _reset(_address);
    }

    function _reset(address _address) internal {
        // get what we need
        uint16 season = IClockSeason(clock).currentSeasonIndex();
        AddressVoteData storage voteData = seasonTokenVoteData[season][_address];
        address[] storage pastVotes = voteData.gaugesVotedFor;

        // reset the global state variables we don't need
        voteData.usedVotingPower = 0;
        voteData.lastVoted = 0;

        // iterate over all the gauges voted for and reset the votes
        for (uint256 i = 0; i < pastVotes.length; i++) {
            address gauge = pastVotes[i];
            uint256 _votes = voteData.votes[gauge];

            // remove from the total globals
            seasonGaugeVotes[season][gauge] -= _votes;
            seasonTotalVotingPowerCast[season] -= _votes;

            delete voteData.votes[gauge];

            emit Reset({
                voter: _address,
                gauge: gauge,
                epoch: epochId(),
                votingPowerRemovedFromGauge: _votes,
                totalVotingPowerInGauge: seasonGaugeVotes[season][gauge],
                totalVotingPowerInContract: seasonTotalVotingPowerCast[season],
                timestamp: block.timestamp
            });
        }

        // clear the remaining state
        voteData.gaugesVotedFor = new address[](0);
    }

    function updateVotingPower(address _address) external onlyDelegationMapper {
        if (!isVoting(_address)) revert NotCurrentlyVoting();

        uint16 season = IClockSeason(clock).currentSeasonIndex();
        AddressVoteData storage voteData = seasonTokenVoteData[season][_address];
        address[] storage pastVotes = voteData.gaugesVotedFor;

        GaugeVote[] memory newVoteData = new GaugeVote[](pastVotes.length);
        for (uint256 i = 0; i < pastVotes.length; i++) {
            address gauge = pastVotes[i];
            uint256 _votes = voteData.votes[gauge];

            newVoteData[i] = GaugeVote(_votes, gauge);
        }

        _vote(_address, newVoteData);
    }

    /*///////////////////////////////////////////////////////////////
                            Gauge Management
    //////////////////////////////////////////////////////////////*/

    function gaugeExists(address _gauge) public view returns (bool) {
        // this doesn't revert if you create multiple gauges at genesis
        // but that's not a practical concern
        return gauges[_gauge].created > 0;
    }

    function isActive(address _gauge) public view returns (bool) {
        return gauges[_gauge].active;
    }

    function createGauge(
        address _gauge,
        string calldata _metadataURI
    ) external auth(GAUGE_ADMIN_ROLE) nonReentrant returns (address gauge) {
        if (_gauge == address(0)) revert ZeroGauge();
        if (gaugeExists(_gauge)) revert GaugeExists();

        gauges[_gauge] = Gauge(true, block.timestamp, _metadataURI);
        gaugeList.push(_gauge);

        emit GaugeCreated(_gauge, _msgSender(), _metadataURI);
        return _gauge;
    }

    function deactivateGauge(address _gauge) external auth(GAUGE_ADMIN_ROLE) {
        if (!gaugeExists(_gauge)) revert GaugeDoesNotExist(_gauge);
        if (!isActive(_gauge)) revert GaugeActivationUnchanged();
        gauges[_gauge].active = false;
        emit GaugeDeactivated(_gauge);
    }

    function activateGauge(address _gauge) external auth(GAUGE_ADMIN_ROLE) {
        if (!gaugeExists(_gauge)) revert GaugeDoesNotExist(_gauge);
        if (isActive(_gauge)) revert GaugeActivationUnchanged();
        gauges[_gauge].active = true;
        emit GaugeActivated(_gauge);
    }

    function updateGaugeMetadata(
        address _gauge,
        string calldata _metadataURI
    ) external auth(GAUGE_ADMIN_ROLE) {
        if (!gaugeExists(_gauge)) revert GaugeDoesNotExist(_gauge);
        gauges[_gauge].metadataURI = _metadataURI;
        emit GaugeMetadataUpdated(_gauge, _metadataURI);
    }

    /*///////////////////////////////////////////////////////////////
                          Getters: Epochs & Time
    //////////////////////////////////////////////////////////////*/

    /// @notice autogenerated epoch id based on elapsed time
    function epochId() public view returns (uint256) {
        return IClock(clock).currentEpoch();
    }

    /// @notice whether voting is active in the current epoch
    function votingActive() public view returns (bool) {
        return IClock(clock).votingActive();
    }

    /// @notice timestamp of the start of the next epoch
    function epochStart() external view returns (uint256) {
        return IClock(clock).epochStartTs();
    }

    /// @notice timestamp of the start of the next voting period
    function epochVoteStart() external view returns (uint256) {
        return IClock(clock).epochVoteStartTs();
    }

    /// @notice timestamp of the end of the current voting period
    function epochVoteEnd() external view returns (uint256) {
        return IClock(clock).epochVoteEndTs();
    }

    /*///////////////////////////////////////////////////////////////
                            Getters: Mappings
    //////////////////////////////////////////////////////////////*/

    function getGauge(address _gauge) external view returns (Gauge memory) {
        return gauges[_gauge];
    }

    function getAllGauges() external view returns (address[] memory) {
        return gaugeList;
    }

    function isVoting(address _address) public view returns (bool) {
        uint16 season = IClockSeason(clock).currentSeasonIndex();
        return seasonTokenVoteData[season][_address].lastVoted > 0;
    }

    function votes(address _address, address _gauge) external view returns (uint256) {
        uint16 season = IClockSeason(clock).currentSeasonIndex();
        return seasonTokenVoteData[season][_address].votes[_gauge];
    }

    function gaugesVotedFor(address _address) external view returns (address[] memory) {
        uint16 season = IClockSeason(clock).currentSeasonIndex();
        return seasonTokenVoteData[season][_address].gaugesVotedFor;
    }

    function usedVotingPower(address _address) external view returns (uint256) {
        uint16 season = IClockSeason(clock).currentSeasonIndex();
        return seasonTokenVoteData[season][_address].usedVotingPower;
    }

    function totalVotingPowerCast() public view returns (uint256) {
        uint16 season = IClockSeason(clock).currentSeasonIndex();
        return seasonTotalVotingPowerCast[season];
    }

    function gaugeVotes(address _address) public view returns (uint256) {
        uint16 season = IClockSeason(clock).currentSeasonIndex();
        return seasonGaugeVotes[season][_address];
    }

    /// Rest of UUPS logic is handled by OSx plugin
    uint256[42] private __gap;
}
