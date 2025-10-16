# LinearIncreasingCurve.sol Specification

## Summary

The LinearIncreasingCurve contract implements a linear voting power curve where voting power increases with time, reaching maximum value at the start of the lock and decreasing linearly to zero at MAX_EPOCHS. It maintains checkpointed history for both individual tokens and total supply, enabling on-chain governance with accurate quorum calculations.

## Mechanism Explanation

The curve mechanism operates on two key principles:

### Voting Power Calculation

- **Linear increase**: Voting power starts at maximum when lock is created and decreases linearly over time
- **Formula**: Voting power = amount × (timeRemaining/maxTime)
- **Bias**: The current voting power at any point in time (stored in coefficients[0])
- **Slope**: The rate of voting power decrease per second, stored as negative value in coefficients[1]
- **Time to maturity**: When timeRemaining reaches 0, the veNFT no longer has voting power
- **Maximum time**: Determined by epoch duration × max epochs (e.g., 2 weeks × 52 = 1 year)
- **Coefficients array**: [bias, slope, 0] where the third element is maintained for backwards compatibility with older quadratic implementations

### Checkpointing System

The contract maintains two checkpoint histories:

1. **Token Points**: Per-NFT voting power snapshots
   - **checkpointTs**: The aligned weekly boundary when the voting curve starts (lock.start snapped to previous checkpoint interval)
   - **writtenTs**: The actual timestamp when this checkpoint was written to storage

   - Stores bias and slope coefficients at each checkpoint
   - Enables historical voting power queries for individual tokens
   - Indexed by tokenId → checkpoint index → TokenPoint

2. **Global Points**: Aggregate voting power snapshots
   - Tracks total system bias and slope
   - Updates when any token's voting power changes
   - Critical for on-chain governance with quorums

### Slope Changes

- Lock start times are "snapped" to the previous checkpoint interval (weekly boundary)
- This alignment ensures that weekly boundaries capture ALL scheduled voting power changes
- When a lock expires, its slope contribution is removed from the global slope
- Tracked in `slopeChanges` mapping (endTime → slopeChange)
- Applied during checkpoint calculations to maintain accuracy
- This aggregation on weekly intervals prevents missing any voting power transitions

## Interface

```solidity
interface ILinearIncreasingCurve {
  // Structs
  struct TokenPoint {
    uint256 bias; // Legacy bias field for backwards compatibility
    uint128 checkpointTs; // When the voting curve starts/started (aligned to week)
    uint128 writtenTs; // When this checkpoint was written (actual timestamp)
    int256[3] coefficients; // [bias, slope, 0] - third element maintained for backwards compatibility with quadratic curves
  }

  struct GlobalPoint {
    int256 bias; // Total voting power at writtenTs
    int256 slope; // Total rate of voting power decrease
    uint48 writtenTs; // Actual timestamp when this global checkpoint was written
  }

## Key Interface Functions

```solidity
interface ILinearIncreasingCurve {
  // Core Checkpoint Function
  // Core Checkpoint Function
  /// @notice Create a voting power checkpoint for a token
  /// @param _tokenId Token to checkpoint
  /// @param _oldLocked Previous locked balance
  /// @param _newLocked New locked balance
  /// @dev Only callable by escrow contract
  function checkpoint(
    uint256 _tokenId,
    LockedBalance memory _oldLocked,
    LockedBalance memory _newLocked
  ) external;

  // Essential View Functions
  /// @notice Calculate voting power for a token at a specific timestamp
  /// @param _tokenId NFT token ID
  /// @param _t Timestamp to query voting power at
  /// @return Voting power in token units
  function votingPowerAt(uint256 _tokenId, uint256 _t) external view returns (uint256);

  /// @notice Calculate total system voting power at a specific timestamp
  /// @param _timestamp Time to calculate total voting power at
  /// @return Total voting power in token units
  function supplyAt(uint256 _timestamp) external view returns (uint256);

  // Key Errors
  error OnlyEscrow();
  error InvalidTokenId();
  error InvalidCheckpoint();
}
```

## Caveats

- **Fixed-point arithmetic**: Internal calculations use 1e18 fixed-point math for precision, but external interfaces return regular integers
- **Checkpoint timing**: Checkpoints cannot occur exactly on checkpoint interval boundaries to prevent edge cases
- **Binary search efficiency**: Historical queries use binary search, making them O(log n) but still gas-intensive for very old data
- **Slope accumulation**: Global slope must be carefully maintained when locks expire to prevent drift
- **Warmup deprecated**: The warmup period functionality has been removed but functions remain for backwards compatibility
- **Maximum 255 checkpoint iterations**: The checkpoint loop has a safety limit to prevent excessive gas consumption
- **Merge restrictions**: Merging tokens with different start dates is restricted unless both are already mature

## LinearIncreasingCurveNoSupply Variant

The LinearIncreasingCurveNoSupply contract is a simplified version that omits global supply tracking. It is intended for deployments upgrading from earlier versions where the gas costs of maintaining global checkpoints provide no benefit, as the historical data would be incomplete.

### Key Differences
- **No Global Points**: Does not maintain global point history or slope changes
- **No Supply Queries**: `supplyAt()` always reverts with "Supply Not Implemented"
- **Reduced Gas Costs**: Checkpoint operations only update token-specific data
- **Same Voting Power Math**: Individual token calculations remain identical

### Use Cases
- Gas-optimized deployments where on-chain supply queries aren't needed
- Upgrades from v1.2.0 where historical supply data would be incomplete anyway
- Systems relying on off-chain supply aggregation

The interface is identical except `supplyAt()` reverts and all global point related storage and functions are removed.

