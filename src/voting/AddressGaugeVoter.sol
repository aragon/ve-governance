/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
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
import {
    PluginUUPSUpgradeable
} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";
import {console2 as console} from "forge-std/console2.sol";

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
    mapping(uint256 => mapping(address => AddressVoteData)) internal epochVoteData;

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

    modifier onlyEscrow() {
        if (msg.sender != escrow) revert OnlyEscrow();
        _;
    }

    /*///////////////////////////////////////////////////////////////
                               Voting
    //////////////////////////////////////////////////////////////*/

    function vote(GaugeVote[] calldata _votes) public nonReentrant whenNotPaused whenVotingActive {
        address account = msg.sender;
        _vote(account, _votes);
    }

    /**
     * @dev If `enableUpdateVotingPowerHook` is false, It's assumed that token contract does/can NOT call
     * `updateVotingPower` during transfers This can happen if the token is already deployed and non-upgradeable,
     * or for other design limitations. In such cases, relying on `getVotes(_account)` (which reflects live balance)
     * instead of `getPastVotes(...)` (which snapshots voting power at a fixed time) can lead
     * to critical vulnerabilities, including double voting.
     *
     * Example of the issue:
     * - Ts 100: Epoch begins, voting window opens.
     * - Ts 110: Alice has 1000 votes.
     * - Ts 120: Alice votes for Gauge A with all 1000.
     * - Ts 130: Alice transfers tokens to Bob, but `updateVotingPower` is NOT triggered.
     * - Ts 140: Bob now votes for Gauge B using the same 1000 tokens.
     *
     * Result: The same 1000 tokens were used to vote for *two* gauges in the same epoch — a double spend.
     *
     * To prevent this, we use `getPastVotes(_account, currentEpochStart())`, which ensures voting power is fixed at epoch start.
     * Even if a transfer happens mid-epoch, the recipient (e.g., Bob) cannot vote in that epoch because their `getPastVotes(...)`
     * will return 0.
     *
     * Note: Once a new epoch starts, Bob *can* vote with the transferred tokens, but this is safe.
     * Since gauge vote tracking is scoped per-epoch, votes from Alice in epoch 11 and from Bob in epoch 12 are kept separate.
     * Querying Gauge A’s votes in epoch 12 will correctly return 1000, not 2000 — avoiding any vote inflation.
     */
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
        AddressVoteData storage voteData = epochVoteData[epoch][_account];
        uint256 totalWeight = _getTotalWeight(_votes);

        // this is technically redundant as checks below will revert div by zero
        // but it's clearer to the caller if we revert here
        if (totalWeight == 0) revert NoVotes();

        // iterate over votes and distribute weight
        for (uint256 i = 0; i < numVotes; i++) {
            GaugeVote memory currentVote = _votes[i];
            _safeCastVote(currentVote, epoch, _account, votingPower, totalWeight, voteData);
        }

        voteData.usedVotingPower = votingPower;
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
        // No votes can happen with extreme weight discrepancies and/or small
        // voting power, in which case caller should adjust weights accordingly
        uint256 normWeight = _normalizedWeight(_currentVote.weight, _totalWeights);
        if (normWeight == 0) revert NoVotes();

        return _castVote(_currentVote.gauge, _epoch, _account, _votingPower, normWeight, _voteData);
    }

    /// @notice Cast the vote of an tokenId to a specific gauge
    /// @dev This function doesn't do any safety checks and it's up to caller to do validations.
    ///      If you wish to have validations, see `_safeCastVote`.
    /// @dev _voteWeight must be normalized to 1e36 precision.
    function _castVote(
        address _gauge,
        uint256 _epoch,
        address _account,
        uint256 _votingPower,
        uint256 _voteWeight,
        AddressVoteData storage _voteData
    ) internal returns (uint256) {
        uint256 _votes = _votesForGauge(_voteWeight, _votingPower);

        // record the vote for the token
        _voteData.gaugesVotedFor.push(_gauge);
        _voteData.voteWeights[_gauge] += _voteWeight;

        // update the total weights accruing to this gauge
        epochGaugeVotes[_epoch][_gauge] += _votes;
        epochTotalVotingPowerCast[_epoch] += _votes;

        emit Voted({
            voter: _account,
            gauge: _gauge,
            epoch: epochId(),
            votingPowerCastForGauge: _votes,
            totalVotingPowerInGauge: epochGaugeVotes[_epoch][_gauge],
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
        uint256 epoch = getWriteEpochId();
        AddressVoteData storage voteData = epochVoteData[epoch][_account];
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
        AddressVoteData storage voteData = epochVoteData[epoch][_account];

        // In case no pastVotes exist for an account,
        // skip as there's nothing to update.
        address[] storage pastVotes = voteData.gaugesVotedFor;
        if (pastVotes.length == 0) return;

        uint256 votingPower = IVotes(ivotesAdapter).getVotes(_account);

        // After the voting window closes, votes shouldn't be auto-recast via _updateVotingPower.
        // But if a user loses voting power (e.g., had 100, now 0),
        // gauges must reflect this drop to avoid overstated voting power.
        // If a user's voting power increases (e.g., 100 → 150),
        // we *don't* auto-recast—doing so would inflate gauge power post-window.
        // So: decrease → auto-adjust gauges; increase → ignored
        // unless user manually votes when window reopens.
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
                newVoteData[i].gauge,
                epoch,
                _account,
                votingPower,
                _normalizedWeight(newVoteData[i].weight, totalWeight),
                voteData
            );
        }

        voteData.usedVotingPower = votingPower;
        voteData.lastVoted = block.timestamp;
    }

    function updateVotingPower(address _from, address _to) external onlyEscrow {
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

    /// @dev Scales weights as percentage of total weight and then to 1e36 precision
    function _normalizedWeight(
        uint256 _weight,
        uint256 _totalWeight
    ) internal view virtual returns (uint256) {
        return (_weight * 1e36) / _totalWeight;
    }

    /// @dev Calculates the votes for a gauge based on weight and voting power.
    ///      We assume the weight is already normalized to 1e36 precision.
    function _votesForGauge(
        uint256 _weight,
        uint256 _votingPower
    ) internal view virtual returns (uint256) {
        return (_weight * _votingPower) / 1e36;
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

        emit GaugeCreated(_gauge, msg.sender, _metadataURI);
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
                                Setters
    //////////////////////////////////////////////////////////////*/

    function setEnableUpdateVotingPowerHook(
        bool _enableUpdateVotingPowerHook
    ) external auth(GAUGE_ADMIN_ROLE) {
        enableUpdateVotingPowerHook = _enableUpdateVotingPowerHook;
    }

    function setIVotesAdapter(address _ivotesAdapter) external auth(GAUGE_ADMIN_ROLE) {
        ivotesAdapter = _ivotesAdapter;
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
        return epochVoteData[epoch][_address].lastVoted > 0;
    }

    function votes(address _address, address _gauge) external view returns (uint256) {
        uint256 epoch = getWriteEpochId();
        return
            _votesForGauge(
                epochVoteData[epoch][_address].voteWeights[_gauge],
                epochVoteData[epoch][_address].usedVotingPower
            );
    }

    function gaugesVotedFor(address _address) external view returns (address[] memory) {
        uint256 epoch = getWriteEpochId();
        return epochVoteData[epoch][_address].gaugesVotedFor;
    }

    function usedVotingPower(address _address) external view returns (uint256) {
        uint256 epoch = getWriteEpochId();
        return epochVoteData[epoch][_address].usedVotingPower;
    }

    function totalVotingPowerCast() public view returns (uint256) {
        uint256 epoch = getWriteEpochId();
        return epochTotalVotingPowerCast[epoch];
    }

    function gaugeVotes(address _address) public view returns (uint256) {
        uint256 epoch = getWriteEpochId();
        return epochGaugeVotes[epoch][_address];
    }

    /// @dev Consumer's responsibility to ensure that `_epoch` exists.
    function gaugeVotes(uint256 _epoch, address _address) public view returns (uint256) {
        return epochGaugeVotes[_epoch][_address];
    }

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[42] private __gap;
}
