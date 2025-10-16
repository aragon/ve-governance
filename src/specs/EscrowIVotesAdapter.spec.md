# EscrowIVotesAdapter.sol Specification

## Summary

The EscrowIVotesAdapter contract bridges the voting escrow system with the standard IVotes interface, enabling address-to-address delegation of voting power. It maintains checkpointed voting power history per delegatee and inherits from DelegationHelper to manage delegation state during token operations (splits, merges, transfers). This contract is the primary interface for delegation in the VE system.

## Architecture Overview

### Contract Hierarchy

- **EscrowIVotesAdapter** (Concrete): Main user-facing contract implementing IVotes interface
- **DelegationHelper** (Abstract Base): Provides core delegation tracking and token operation hooks

### Integration Points

- **IVotes Compliance**: Implements standard governance interface (getVotes, getPastVotes, delegates)
- **ERC6372 Clock**: Uses timestamp-based clock for time consistency and exposes this logic to calling contracts in predictable way.
- **Escrow Hooks**: Receives notifications for splits, merges, and transfers to update delegation state
- **AddressGaugeVoter**: Used directly for address-based voting power queries

## Delegation Model

### Address-to-Address Delegation

- **Not Split Delegation**: This allows delegating specific NFT tokens to an address, not splitting a single token's power
- **Partial Delegation**: Users can delegate some tokens while keeping others undelegated - however this is not the default and is permissioned - we found several edge cases in testing that resulted from inconsistent state with parial delegation and so have decided to restrict its use, for now.
- **One Delegatee**: Each account can only delegate to one address at a time
- **Self-Delegation Required**: In the VE system, users must self-delegate to activate voting power

### Auto-Delegation Features

- **Default Behavior**: When setting a delegatee, all owned tokens are automatically delegated
- **Opt-Out Available**: Whitelisted users can disable auto-delegation for manual control
- **Permissioned Use Case**: Manual partial delegation is primarily for large token holders

## Token Operation Rules

The escrow contract performs various operations that require delegation updates:

### Split Operations

When token X splits into X and Y:

- **If X is NOT delegated**: Do nothing (avoids unnecessary gas costs)
- **If X is delegated**: Automatically delegate Y to prevent double-voting
  - Rationale: If X was delegated with amount A+B, and splits into X(A) and Y(B), both must remain delegated or the delegatee could later delegate Y manually and double-spend voting power

### Merge Operations

When merging token `fromTokenId` into `toTokenId`:

1. **Neither delegated**: No action needed
2. **From NOT delegated, To delegated**: Add from's amount to delegatee's checkpoint
3. **Both delegated**: Decrease count, mark from as undelegated (amounts already in checkpoint)
4. **From delegated, To NOT delegated**: Mark to as delegated, add to's amount to checkpoint
   - Prevents double-spending if user later delegates the merged token

### Transfer Operations

When transferring `tokenId` from sender to recipient:

- Check both parties' delegatees
- If different and token is delegated:
  - Remove voting power from sender's delegatee
  - Add voting power to recipient's delegatee (if set)
  - Update delegation bitmap and counters
- Call `updateVotingPower()` on escrow if delegatees differ

### Withdraw Operations

- Uses transfer mechanism (user → escrow)
- Follows transfer rules with escrow having no delegatee

## Checkpointing System

### Per-Delegatee History

- Each delegatee has independent checkpoint history
- Uses bias (current power) and slope (decay rate) model
- Binary search enables efficient historical queries

### Checkpoint Structure

```solidity
struct GlobalPoint {
  int256 bias; // Current voting power at writtenTs
  int256 slope; // Rate of voting power decrease
  uint48 writtenTs; // Actual timestamp when written
}
```

### Time Limitations

- After ~5 years (255 weekly intervals), checkpoint loops may run out of gas
- Manual `checkpointTransition()` allows catching up on missed updates
- Critical for delegated addresses not accessed regularly

### Timestamp Tracking

- **writtenTs**: Actual timestamp when checkpoint was written
- **checkpointTs**: Weekly-aligned boundary for voting curve calculations

## Key Interface Functions

```solidity
interface IEscrowIVotesAdapter {
  // Core Delegation Functions
  /// @notice Set delegatee and auto-delegate all owned tokens
  function delegate(address _delegatee) external;

  /// @notice Delegate specific tokens to current delegatee
  function delegate(uint256[] calldata _tokenIds) external;

  /// @notice Undelegate specific tokens
  function undelegate(uint256[] calldata _tokenIds) external;

  /// @notice Set delegatee without auto-delegating (for many tokens)
  function setDelegateAddress(address _delegatee) external;

  // IVotes Core Functions
  /// @notice Get current voting power
  function getVotes(address _account) external view returns (uint256);

  /// @notice Get historical voting power
  function getPastVotes(
    address _account,
    uint256 _timestamp
  ) external view returns (uint256);

  /// @notice Get current delegatee
  function delegates(address _account) external view returns (address);

  // Essential View Functions
  /// @notice Check if a token is delegated
  function tokenIsDelegated(uint256 _tokenId) external view returns (bool);

  /// @notice Enable/disable auto-delegation for caller
  function setAutoDelegationDisabled(bool _disabled) external;

  // Manual Checkpointing (for gas issues)
  /// @notice Process missed checkpoint transitions (max 255)
  function checkpointTransition(
    address _delegatee,
    uint256 _transitionCount
  ) external;

  // Hook Functions (called by escrow)
  /// @notice Handle delegation during token split
  function splitDelegateVotes(
    TokenLock calldata _from,
    TokenLock calldata _to
  ) external;

  /// @notice Handle delegation during token merge
  function mergeDelegateVotes(
    TokenLock calldata _from,
    TokenLock calldata _to
  ) external;

  /// @notice Update delegation on transfer/mint/burn
  function moveDelegateVotes(
    address _from,
    address _to,
    uint256 _tokenId,
    ILockedBalance memory _locked
  ) external;

  // Key Events
  event DelegateChanged(
    address indexed delegator,
    address indexed fromDelegate,
    address indexed toDelegate
  );

  event TokensDelegated(
    address indexed sender,
    address indexed delegatee,
    uint256[] tokenIds
  );

  event TokensUndelegated(
    address indexed sender,
    address indexed delegatee,
    uint256[] tokenIds
  );

  // Key Errors
  error DelegateeNotSet();
  error TokenAlreadyDelegated(uint256 tokenId);
  error TokenNotDelegated(uint256 tokenId);
  error VotingPowerZero(uint256 tokenId);
}
```

## Implementation Details

### Bitmap Storage (from DelegationHelper)

- Tokens tracked in 256-bit buckets for gas efficiency
- Bucket = tokenId >> 8 (tokenId / 256)
- Position = tokenId & 0xff (tokenId % 256)
- Bitwise operations for setting/checking delegation status

### Voting Power Calculation

- Fixed-point math with 1e18 precision internally
- Bias represents current voting power
- Slope represents decay rate over time
- External functions return regular integers

### Security Considerations

- **Only Escrow**: All delegation updates must come from escrow contract
- **Pausable**: Operations can be paused in emergencies
- **Reentrancy Protection**: Inherited from base contracts

## Caveats

- **No Signature Delegation**: `delegateBySig` not supported, always reverts
- **Delegation Switching**: Must undelegate all tokens before changing delegatee
- **Self-Delegation Required**: For VE system, users must self-delegate before voting
- **Checkpoint Gas Limits**: Manual intervention needed after ~5 years of inactivity
- **Zero Power Tokens**: Cannot delegate tokens with no voting power
- **Automatic Propagation**: Split tokens inherit delegation which may surprise users
- **One Delegatee Limit**: Cannot split delegation across multiple addresses
- **Transfer Assumptions**: Merge operations assume same owner for both tokens

