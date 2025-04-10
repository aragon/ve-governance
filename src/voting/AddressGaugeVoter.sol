/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IClockUser, IClockV1_2_0 as IClock} from "@clock/IClock_v1_2_0.sol";
import {IAddressGaugeVoter} from "./IAddressGaugeVoter.sol";

import {
    ReentrancyGuardUpgradeable as ReentrancyGuard
} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {
    PausableUpgradeable as Pausable
} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {
    IVotesUpgradeable as IVotes
} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";

contract AddressGaugeVoter is
    IAddressGaugeVoter,
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

    /// @notice epoch => The total votes that have accumulated in this contract
    mapping(uint256 => uint256) public epochTotalVotingPowerCast;

    /// @notice enumerable list of all gauges that can be voted on
    address[] public gaugeList;

    /// @notice address => gauge data
    mapping(address => Gauge) public gauges;

    /// @notice epoch => gauge => total votes (global)
    mapping(uint256 => mapping(address => uint256)) public epochGaugeVotes;

    /// @dev epoch => address => AddressVoteData
    mapping(uint256 => mapping(address => AddressVoteData)) internal epochTokenVoteData;

    /// @notice Delegation mapper contract
    address public ivotesAdapter;

    /// @notice Activate updateVotingPower hook
    /// @dev This is used to update the voting power of the sender and receiver
    ///      when the delegation mapper is set.
    ///      If the delegation mapper is not set, or the hook is not activated,
    ///      then the voting power will not be updated automatically.
    bool public enableUpdateVotingPowerHook;

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
        address _ivotesAdapter,
        bool _enableUpdateVotingPowerHook
    ) external initializer {
        __PluginUUPSUpgradeable_init(IDAO(_dao));
        __ReentrancyGuard_init();
        __Pausable_init();
        escrow = _escrow;
        clock = _clock;
        ivotesAdapter = _ivotesAdapter;
        enableUpdateVotingPowerHook = _enableUpdateVotingPowerHook;
        if (_startPaused) _pause();
    }

    function initializeFrom(address _ivotesAdapter) public {
        ivotesAdapter = _ivotesAdapter;
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

    modifier onlyIVotesAdapter() {
        if (msg.sender != ivotesAdapter) revert OnlyIVotesAdapter();
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

    function vote(GaugeVote[] calldata _votes) public nonReentrant whenNotPaused whenVotingActive {
        address account = _msgSender();
        _vote(account, _votes);
    }

    function _vote(address _account, GaugeVote[] memory _votes) internal {
        uint256 votingPower = enableUpdateVotingPowerHook
            ? IVotes(ivotesAdapter).getVotes(_account)
            : IVotes(ivotesAdapter).getPastVotes(_account, currentEpochStart());
        if (votingPower == 0) revert NoVotingPower();

        uint256 numVotes = _votes.length;
        if (numVotes == 0) revert NoVotes();

        // clear any existing votes
        if (isVoting(_account)) _reset(_account);

        uint256 epoch = getWriteEpochId();

        // voting power continues to increase over the voting epoch.
        // this means you can revote later in the epoch to increase votes.
        // while not a huge problem, it's worth noting that when rewards are fully
        // on chain, this could be a vector for gaming.
        AddressVoteData storage voteData = epochTokenVoteData[epoch][_account];
        uint256 totalWeight = _getTotalWeight(_votes);

        // this is technically redundant as checks below will revert div by zero
        // but it's clearer to the caller if we revert here
        if (totalWeight == 0) revert NoVotes();

        // iterate over votes and distribute weight
        for (uint256 i = 0; i < numVotes; i++) {
            GaugeVote memory currentVote = _votes[i];
            _safeCastVote(currentVote, epoch, _account, votingPower, totalWeight, voteData);
        }

        // setting the last voted also has the second-order effect of indicating the user has voted
        voteData.lastVoted = block.timestamp;
    }

    function _safeCastVote(
        GaugeVote memory _currentVote,
        uint256 _epoch,
        address _account,
        uint256 _votingPower,
        uint256 _totalWeights,
        AddressVoteData storage _voteData
    ) internal returns (uint256) {
        // the gauge must exist and be active,
        // it also can't have any votes or we haven't reset properly
        if (!gaugeExists(_currentVote.gauge)) revert GaugeDoesNotExist(_currentVote.gauge);
        if (!isActive(_currentVote.gauge)) revert GaugeInactive(_currentVote.gauge);

        // prevent double voting
        if (_voteData.voteWeights[_currentVote.gauge] != 0) revert DoubleVote();

        // calculate the weight for this gauge
        uint256 votesForGauge = _normalizedWeight(_currentVote.weight, _totalWeights);
        if (votesForGauge == 0) revert NoVotes();

        return _castVote(_currentVote, _epoch, _account, _votingPower, votesForGauge, _voteData);
    }

    /// @notice Cast the vote of an tokenId to a specific gauge
    /// @dev This function doesn't do any safety checks and it's up to caller to do validations.
    ///      If you wish to have validations, see `_safeCastVote`.
    function _castVote(
        GaugeVote memory _currentVote,
        uint256 _epoch,
        address _account,
        uint256 _votingPower,
        uint256 _voteWeight,
        AddressVoteData storage _voteData
    ) internal returns (uint256) {
        uint256 _votes = _votesForGauge(_voteWeight, _votingPower);
        // record the vote for the token
        _voteData.gaugesVotedFor.push(_currentVote.gauge);
        _voteData.voteWeights[_currentVote.gauge] += _voteWeight;

        // update the total weights accruing to this gauge
        epochGaugeVotes[_epoch][_currentVote.gauge] += _votes;
        epochTotalVotingPowerCast[_epoch] += _votes;
        _voteData.usedVotingPower += _votes;

        emit Voted({
            voter: _account,
            gauge: _currentVote.gauge,
            epoch: _epoch,
            votingPowerCastForGauge: _votes,
            totalVotingPowerInGauge: epochGaugeVotes[_epoch][_currentVote.gauge],
            totalVotingPowerInContract: epochTotalVotingPowerCast[_epoch],
            timestamp: block.timestamp
        });

        return _votes;
    }

    function reset() external nonReentrant whenNotPaused whenVotingActive {
        if (!isVoting(msg.sender)) revert NotCurrentlyVoting();
        _reset(msg.sender);
    }

    function _reset(address _account) internal {
        // get what we need
        uint256 epoch = getWriteEpochId();
        AddressVoteData storage voteData = epochTokenVoteData[epoch][_account];
        address[] storage pastVotes = voteData.gaugesVotedFor;

        // iterate over all the gauges voted for and reset the votes
        for (uint256 i = 0; i < pastVotes.length; i++) {
            address gauge = pastVotes[i];
            uint256 _voteWeight = voteData.voteWeights[gauge];
            uint256 _votes = _votesForGauge(_voteWeight, voteData.usedVotingPower);

            // remove from the total globals
            epochGaugeVotes[epoch][gauge] -= _votes;
            epochTotalVotingPowerCast[epoch] -= _votes;

            delete voteData.voteWeights[gauge];

            emit Reset({
                voter: _account,
                gauge: gauge,
                epoch: epochId(),
                votingPowerRemovedFromGauge: _votes,
                totalVotingPowerInGauge: epochGaugeVotes[epoch][gauge],
                totalVotingPowerInContract: epochTotalVotingPowerCast[epoch],
                timestamp: block.timestamp
            });
        }

        // reset the global state variables we don't need
        voteData.usedVotingPower = 0;
        voteData.lastVoted = 0;
        voteData.gaugesVotedFor = new address[](0);
    }

    function _updateVotingPower(address _account) internal {
        if (!enableUpdateVotingPowerHook) revert UpdateVotingPowerHookNotEnabled();
        // Skip as `_account` hasn't voted so no need to update it.
        if (!isVoting(_account)) return;

        uint256 epoch = getWriteEpochId();
        AddressVoteData storage voteData = epochTokenVoteData[epoch][_account];

        // In case no pastVotes exist for an account,
        // skip as there's nothing to update.
        address[] storage pastVotes = voteData.gaugesVotedFor;
        if (pastVotes.length == 0) return;

        uint256 votingPower = IVotes(ivotesAdapter).getVotes(_account);

        // If the new voting power is less than the used voting power
        // then we can re-cast the votes otherwise we skip.
        if (voteData.usedVotingPower < votingPower) return;

        GaugeVote[] memory newVoteData = new GaugeVote[](pastVotes.length);

        // cast new votes again.
        for (uint256 i = 0; i < pastVotes.length; i++) {
            address gauge = pastVotes[i];
            uint256 _votes = voteData.voteWeights[gauge];
            newVoteData[i] = GaugeVote(_votes, gauge);
        }

        // Note that even if votingPower is 0, this still records.
        uint256 totalWeight = _getTotalWeight(newVoteData);

        // Reset all votes of `_account` to zero.
        _reset(_account);

        // Re-cast the votes with the new voting power.
        for (uint256 i = 0; i < newVoteData.length; i++) {
            _castVote(
                newVoteData[i],
                epoch,
                _account,
                votingPower,
                _normalizedWeight(newVoteData[i].weight, totalWeight),
                voteData
            );
        }

        voteData.lastVoted = block.timestamp;
    }

    function updateVotingPower(address _from, address _to) external onlyIVotesAdapter {
        // update the voting power of the sender
        _updateVotingPower(_from);

        // This means that account's delegate is itself,
        // so it's enough to only update votes once.
        if (_from == _to) return;

        // update the voting power of the receiver
        _updateVotingPower(_to);
    }

    function _getTotalWeight(GaugeVote[] memory _votes) internal view virtual returns (uint256) {
        uint256 total = 0;

        for (uint256 i = 0; i < _votes.length; i++) {
            total += _votes[i].weight;
        }

        return total;
    }

    function _normalizedWeight(
        uint256 _weight,
        uint256 _totalWeight
    ) internal view virtual returns (uint256) {
        return (_weight * 10e10) / _totalWeight;
    }

    function _votesForGauge(
        uint256 _weight,
        uint256 _votingPower
    ) internal view virtual returns (uint256) {
        return (_weight * _votingPower) / 10e10;
    }

    /// @notice This function is used to get the epoch id in the case of delegation mapper
    /// does not exist or the hook is not activated.
    function getWriteEpochId() public view returns (uint256) {
        return enableUpdateVotingPowerHook ? 0 : epochId();
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
    function currentEpochStart() public view returns (uint256) {
        return IClock(clock).epochStartTs() - IClock(clock).epochDuration();
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
        uint256 epoch = getWriteEpochId();
        return epochTokenVoteData[epoch][_address].lastVoted > 0;
    }

    function votes(address _address, address _gauge) external view returns (uint256) {
        uint256 epoch = getWriteEpochId();
        return
            _votesForGauge(
                epochTokenVoteData[epoch][_address].voteWeights[_gauge],
                epochTokenVoteData[epoch][_address].usedVotingPower
            );
    }

    function gaugesVotedFor(address _address) external view returns (address[] memory) {
        uint256 epoch = getWriteEpochId();
        return epochTokenVoteData[epoch][_address].gaugesVotedFor;
    }

    function usedVotingPower(address _address) external view returns (uint256) {
        uint256 epoch = getWriteEpochId();
        return epochTokenVoteData[epoch][_address].usedVotingPower;
    }

    function totalVotingPowerCast() public view returns (uint256) {
        uint256 epoch = getWriteEpochId();
        return epochTotalVotingPowerCast[epoch];
    }

    function gaugeVotes(address _address) public view returns (uint256) {
        uint256 epoch = getWriteEpochId();
        return epochGaugeVotes[epoch][_address];
    }

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[42] private __gap;
}
