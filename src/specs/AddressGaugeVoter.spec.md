# AddressGaugeVoter.sol Specification

## Summary

The AddressGaugeVoter contract is the main voting plugin for the gauge voting system v1.2.0+, implementing address-based voting where users allocate their voting power across multiple gauges. It integrates with the IVotes adapter for delegation support, manages gauge creation and activation, and tracks votes by epoch with automatic voting power updates when delegation changes occur.

## Mechanism Explanation

The AddressGaugeVoter implements a multi-gauge voting system where:

### Voting Mechanism

- **Address-Based**: Users vote directly from their addresses, not NFT tokens
- **Proportional Distribution**: Users allocate weights across gauges, normalized to 100%
- **Epoch-Scoped**: When hook is disabled, votes are scoped to the current epoch. When hook is enabled, votes persist across epochs (stored in epoch 0)
- **Vote Recasting**: Users must reset() before changing their vote allocation
- **Voting Power Source**: Obtained from IVotesAdapter (either live or snapshotted)
- **Self-Delegation Required**: While compatible with any IVotes token, in the VE system users must self-delegate to activate their voting power

### Update Hook Behavior

The `enableUpdateVotingPowerHook` setting determines vote persistence:

- **Hook Enabled (Default for VE)**: Votes persist across epochs without manual re-voting. The escrow contract calls `updateVotingPower()` on transfers, unstakes, or delegation changes to automatically adjust gauge voting power. This is the default and expected behavior for the VE system.
- **Hook Disabled (ERC20Votes)**: Required for standard ERC20Votes tokens that don't support automatic updates. Voting power resets each epoch and uses `getPastVotes()` at epoch start to prevent double-voting. Users must re-vote each epoch.

### Delegation Integration

- **IVotes Adapter**: Bridges voting escrow to standard IVotes interface
- **Automatic Updates**: When `enableUpdateVotingPowerHook` is true, votes auto-adjust on delegation changes
- **Power Snapshots**: When hook disabled, uses `getPastVotes()` at epoch start to prevent double-voting
- **Delegation Hooks**: Escrow calls `updateVotingPower()` on transfers/delegation changes

### Gauge Management

- **Permissioned Creation**: Only GAUGE_ADMIN_ROLE can create/manage gauges
- **Active/Inactive States**: Gauges can be deactivated to prevent voting
- **Metadata Support**: Each gauge has an associated metadata URI
- **Enumerable List**: All gauges stored in array for iteration

### Safety Features

- **Pausable**: Can be paused to disable all voting
- **Reentrancy Protection**: All external functions protected
- **Weight Normalization**: Prevents precision loss in vote calculations
- **Zero Vote Prevention**: Reverts if calculated votes round to zero

## Key Interface Functions

```solidity
interface IAddressGaugeVoter {
  // Core Data Structures
  struct GaugeVote {
    uint256 weight; // Relative weight (will be normalized)
    address gauge; // Gauge address to vote for
  }

  // Main Voting Functions
  /// @notice Vote for multiple gauges with specified weights
  /// @param _votes Array of GaugeVote structs with gauge addresses and weights
  function vote(GaugeVote[] memory _votes) external;

  /// @notice Reset all votes for the caller
  /// @dev Required before changing votes or transferring voting power
  function reset() external;

  /// @notice Update voting power for affected addresses on delegation change
  /// @param _from Address losing voting power
  /// @param _to Address gaining voting power
  /// @dev Only callable by escrow contract
  function updateVotingPower(address _from, address _to) external;

  // Essential View Functions
  /// @notice Check if an address is currently voting
  function isVoting(address _address) external view returns (bool);

  /// @notice Get votes cast by an address for a specific gauge
  function votes(
    address _address,
    address _gauge
  ) external view returns (uint256);

  /// @notice Get total votes for a gauge in current epoch
  function gaugeVotes(address _address) external view returns (uint256);

  // Key Events
  event Voted(
    address indexed voter,
    address indexed gauge,
    uint256 indexed epoch,
    uint256 votingPowerCastForGauge,
    uint256 totalVotingPowerInGauge,
    uint256 totalVotingPowerInContract,
    uint256 timestamp
  );

  // Key Errors
  error VotingInactive();
  error GaugeDoesNotExist(address _pool);
  error GaugeInactive(address _gauge);
  error NoVotingPower();
  error AlreadyVoted(address _address);
}
```

## Caveats

- **Double Voting Prevention**: When hook is disabled, uses `getPastVotes()` to snapshot power at epoch start. When hook is enabled, uses live `getVotes()` and votes auto-update with delegation changes
- **Vote Timing**: Can only vote during active voting windows defined by Clock contract
- **Weight Precision**: Very small weights relative to total may result in zero votes due to rounding. While this will revert, it's the user's responsibility to avoid extremely fractional weights
- **Vote Persistence**: Votes persist across epochs when hook is enabled (epoch 0 storage)
- **Gas Considerations**: Voting for many gauges or frequent resets can be gas intensive
- **Delegation Complexity**: Auto-update behavior differs significantly based on hook setting
- **Reset Requirement**: Must reset before any vote changes or NFT transfers
- **Gauge Uniqueness**: Cannot create duplicate gauges (by address)
- **Vote Recasting**: With hook enabled and voting power decreases, votes auto-adjust downward
- **No Vote Inflation**: System prevents using same tokens to vote multiple times per epoch
