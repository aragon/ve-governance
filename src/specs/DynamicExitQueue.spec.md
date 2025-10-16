# DynamicExitQueue.sol Specification

## Overview

The DynamicExitQueue contract extends ExitQueue with dynamic early exit fees that decay linearly over time. It provides a comprehensive fee system supporting dynamic decay, tiered fees, and fixed fees through a unified interface. This version removes the legacy requirement for exits to align with weekly checkpoint intervals, allowing for immediate exit processing once conditions are met.

## Fee System Types

### Dynamic Fee System

**Description**: A continuously changing fee that decreases linearly over time, rewarding users who wait longer with progressively lower fees. This creates a smooth incentive curve encouraging patience while still allowing flexibility.

**Example**: User queues exit and must wait 2 days minimum. After 2 days, they pay 5% fee. Each additional day they wait, the fee decreases by 1% until reaching 1% after 6 days total.

**Use Case**: When you want to discourage early exits but provide fair compensation for those who wait, creating a balanced economic incentive.

```
Fee %
  5% |........................███
     |                           ████
     |                               ████
  3% |                                   ████
     |                                       ████
     |                                           ████
  1% |                                               ████████████████████████
     |_______________________________________________________________________
     0    minCooldown(2d)      cooldown(6d)        time
          Phase 1: Locked     Phase 2: Decay       Phase 3: Normal
```

### Tiered Fee System

**Description**: A two-level fee structure with a higher "penalty" rate for early exits and a lower "normal" rate after the full cooldown period. Simple binary choice between paying more to exit early or waiting for the standard rate.

**Example**: User must wait 1 day minimum, then pays 3% for any exit before 7 days, or 1% after waiting the full 7 days. Clear choice: pay penalty for convenience or wait for normal rate.

**Use Case**: When you want clear, predictable fee tiers that are easy for users to understand and plan around.

```
Fee %
  3% |...................████████████████████████████████████
     |
     |
  1% |                                                       ██████████████████████
     |
     |
     |
     |_____________________________________________________________________________
     0    minCooldown(1d)                      cooldown(7d)                  time
          Phase 1: Locked              Phase 2: Early Exit           Phase 3: Normal
```

### Fixed Fee System

**Description**: A single fee rate applies to all exits after the minimum cooldown period. Simplest configuration with consistent, predictable costs.

**Example**: Setting minCooldown=0 allows instant 2% fee exits, while minCooldown=5 days requires users to wait exactly 5 days before paying 2%. Eliminates timing games and fee uncertainty.

**Use Case**: When you want simplicity and predictability, using the minCooldown parameter to control whether instant exits are allowed (minCooldown=0) or a specific waiting period is enforced (minCooldown>0).

```
Fee %
  2% |.........................................███████████████████████████████████████
     |
     |
     |
     |
     |
     |
     |________________________________________________________________________________
     0    minCooldown(1d)                                                       time
          Phase 1: Locked                     Phase 2: Same Rate
```

## Core Mechanism

### Key Concepts

#### Cooldown vs MinCooldown

- **`cooldown`**: Total time a user should ideally wait before exiting (inherited from base contract)
- **`minCooldown`**: Minimum time before ANY exit is allowed (prevents immediate exits)
- **Decay Period**: The time between `minCooldown` and `cooldown` where fees decay linearly

#### The Slope

- **`slope`**: Rate of fee decrease per second during the decay period, calculated to suitable precision
- **Formula**: `slope = (maxFeePercent - minFeePercent) / (cooldown - minCooldown)`
- **Units**: Basis points per second of fee reduction
- **Zero slope**: Creates flat/tiered fee system (no decay)
- **⚠️ Division by Zero Prevention**: When `minCooldown == cooldown`, the slope calculation would result in division by zero. This scenario only occurs with fixed fee systems where no decay period exists. Implementation must check for this condition and set `slope = 0` directly without performing the division.

#### Timeline Phases

```
Queue Entry → [Phase 1: Locked] → [Phase 2: Decay] → [Phase 3: Normal]
              ^cannot exit        ^linear decay   ^minFeePercent only

Phase 1: 0 to minCooldown seconds - NO EXIT ALLOWED
Phase 2: minCooldown to cooldown seconds - LINEAR FEE DECAY (maxFeePercent → minFeePercent)
Phase 3: cooldown + seconds - NORMAL EXIT (minFeePercent only)
```

All fee calculations are based on `timeElapsed = block.timestamp - ticket.queuedAt` to provide precise timing.

## State Variables

```solidity
// cooldown & fee percent inherited from base contract

/// @notice Minimum fee percent charged after full cooldown period
uint256 public minFeePercent;

/// @notice Minimum wait time before any exit is possible
uint48 public minCooldown;

/// @notice Fee decrease per second (basis points/second) during decay period
/// @dev Set to 0 when minCooldown == cooldown to prevent division by zero
uint256 private _slope;
```

## Interface Specification

```solidity
interface IEarlyExitQueueEventsAndErrors {
  enum ExitFeeType {
    Fixed,
    Tiered,
    Dynamic
  }

  // Events
  event ExitFeePercentAdjusted(
    uint256 maxFeePercent,
    uint256 minFeePercent,
    uint48 minCooldown,
    ExitFeeType feeType
  );

  // Errors
  error EarlyExitDisabled();
  error MinCooldownNotMet();
  error InvalidFeeParameters();
  error FeePercentTooHigh(uint256 maxAllowed);
  error CooldownTooShort();
  error LegacyFunctionDeprecated();
  error CannotCancelExit();
}

interface IEarlyExitQueue is IEarlyExitQueueEventsAndErrors {
  /// @notice Check if a token has completed its full cooldown period (minimum fee applies)
  /// @param tokenId The token ID to check
  /// @return True if full cooldown elapsed, false otherwise
  function isCool(uint256 tokenId) external view returns (bool);

  /// @notice Configure linear fee decay system where fees decrease continuously over time
  /// @param _minFeePercent Fee percent after full cooldown (basis points, 0-10000)
  /// @param _maxFeePercent Fee percent immediately after minCooldown (basis points, 0-10000)
  /// @param _cooldown Total cooldown period in seconds
  /// @param _minCooldown Minimum wait before any exit allowed in seconds
  function setDynamicExitFeePercent(
    uint256 _minFeePercent,
    uint256 _maxFeePercent,
    uint48 _cooldown,
    uint48 _minCooldown
  ) external;

  /// @notice Configure two-tier fee system with early exit penalty and normal exit rate
  /// @param _baseFeePercent Fee percent for normal exits after cooldown (basis points, 0-10000)
  /// @param _earlyFeePercent Fee percent for early exits after minCooldown (basis points, 0-10000)
  /// @param _cooldown Total cooldown period in seconds
  /// @param _minCooldown Minimum wait before any exit allowed in seconds
  function setTieredExitFeePercent(
    uint256 _baseFeePercent,
    uint256 _earlyFeePercent,
    uint48 _cooldown,
    uint48 _minCooldown
  ) external;

  /// @notice Configure single fee rate system
  /// @param _feePercent Fee percent for all exits (basis points, 0-10000)
  /// @param _minCooldown Total cooldown period in seconds - can be zero for instant exits w. fee
  function setFixedExitFeePercent(
    uint256 _feePercent,
    uint48 _minCooldown
  ) external;

  /// @return Fee percent in basis points (0-10000)
  function feePercent() external view returns (uint256);

  /// @notice Minimum fee percent charged after full cooldown
  /// @return Fee percent in basis points (0-10000)
  function minFeePercent() external view returns (uint256);

  /// @notice Minimum wait time before cheapest exit is possible
  function cooldown() external view returns (uint48);

  /// @notice Minimum wait time before any exit is possible
  /// @return Time in seconds
  function minCooldown() external view returns (uint48);

  /// @notice Cancel an exit that has been queued
  /// @param _tokenId The token ID to cancel exit for
  /// @dev Only callable by escrow contract
  function cancelExit(uint256 _tokenId) external;
}
```

## Function Requirements

### 1. `setDynamicExitFeePercent(uint256 _minFeePercent, uint256 _maxFeePercent, uint48 _cooldown, uint48 _minCooldown)`

**Purpose**: Configure linear fee decay system
**Requirements**:

- Only callable by QUEUE_ADMIN_ROLE
- Validate all fee percents <= 10000 (100%)
- Validate `_maxFeePercent > _minFeePercent` (must have meaningful decay)
- Validate `_cooldown > _minCooldown` (must have decay period)
- Calculate and store `slope = (_maxFeePercent - _minFeePercent) / (_cooldown - _minCooldown)` to suitable precision
- Update all four state variables atomically
- Emit `ExitFeePercentAdjusted` event

### 2. `setTieredExitFeePercent(uint256 _baseFeePercent, uint256 _earlyFeePercent, uint48 _cooldown, uint48 _minCooldown)`

**Purpose**: Configure two-tier fee system (early vs normal)
**Requirements**:

- Only callable by QUEUE_ADMIN_ROLE
- Validate all fee percents <= 10000 (100%)
- Validate `_earlyFeePercent >= _baseFeePercent` (early fee should be penalty)
- Validate `_minCooldown < _cooldown` (must have early exit period - cannot equal)
- Set `maxFeePercent = _earlyFeePercent`, `minFeePercent = _baseFeePercent`, `slope = 0`
- Update cooldown and minCooldown parameters
- Emit `ExitFeePercentAdjusted` event

### 3. `setFixedExitFeePercent(uint256 _feePercent, uint48 _minCooldown)`

**Purpose**: Configure single fee rate system
**Requirements**:

- Only callable by QUEUE_ADMIN_ROLE
- Validate `_feePercent <= 10000` (100%)
- Set `minCooldown = _minCooldown` (if 0, immediate exit allowed; if > 0, must wait)
- Set `cooldown = _minCooldown` (same as minCooldown for fixed fee system)
- Set `maxFeePercent = minFeePercent = _feePercent`, `slope = 0`
- **Note**: Since `minCooldown == cooldown`, slope is automatically 0 (no decay period exists)
- Emit `ExitFeePercentAdjusted` event

### 4. `calculateFee(uint256 _tokenId)`

**Purpose**: Calculate absolute fee amount for token exit
**Requirements**:

- Return fee amount in underlying token units (not percentage)
- Handle all three timeline phases correctly
- Apply calculated fee percentage to token's locked amount
- Use `ticket.queuedAt` for precise elapsed time calculation
- **IMPORTANT**: Use fee parameters stored in the ticket (NOT global parameters) to ensure immutability of fee terms

### 5. `isCool(uint256 _tokenId)`

**Purpose**: Check if token has completed full cooldown period
**Requirements**:

- Return `true` if full cooldown elapsed (Phase 3 - normal exit)
- Return `false` if still in Phase 1 or 2
- Clear indicator for "minimum fee applies" status
- **IMPORTANT**: Use `ticket.cooldown` (NOT global `cooldown`) to determine if the ticket's specific cooldown period has elapsed

### 6. `cancelExit(uint256 _tokenId)`

**Purpose**: Cancel a previously queued exit request
**Requirements**:

- Only callable by the escrow contract (onlyEscrow modifier)
- Validate that the ticket exists (ticket.holder != address(0))
- If no ticket exists, revert with `CannotCancelExit()` error
- Clear the ticket by setting holder to address(0) and queuedAt to 0

## Breaking Change: Ticket Structure Redesign

### Problem Statement

The current `Ticket` struct in ExitQueue stores only the exit date (`exitDate`) which represents when a user can exit, but dynamic fee calculations require knowing **when the ticket was originally queued** to determine how much time has elapsed. This creates a fundamental incompatibility:

- **Current**: `exitDate = queueTime + cooldown` (we only know when they can exit)
- **Needed**: `queueTime` to calculate `timeElapsed = now - queueTime` for dynamic fees

### Solution: TicketV2 Structure

```solidity
struct TicketV2 {
  address holder;      // ticket holder address
  uint48 queuedAt;     // when ticket was queued (timestamp)
  uint48 minCooldown;  // minimum wait time at queue time
  uint48 cooldown;     // total cooldown period at queue time
  uint16 feePercent;   // max/early fee percent at queue time
  uint16 minFeePercent;// min/base fee percent at queue time
  uint256 slope;       // fee decay rate at queue time
}
```

**Design Rationale**:

- **`holder`**: Unchanged functionality - who owns the ticket
- **`queuedAt`**: **New** - enables dynamic fee calculations based on elapsed time
- **Fee Parameters**: **New** - preserves the exact fee configuration at queue time, ensuring existing ticket holders are protected from subsequent fee parameter changes
- **Immutability**: Once a ticket is created, its fee terms are locked in and cannot be changed by admin actions

### Rationale for Breaking Change

Rather than maintaining backwards compatibility with a dual-system approach, we're implementing a clean breaking change for the following reasons:

1. **Complexity Reduction**: Backwards compatibility would require branching logic in every fee calculation function
2. **Limited Impact**: Current usage is limited and no explicit backwards compatibility requests exist
3. **Performance**: Single code path without conditional logic overhead
4. **Clarity**: Clear cutoff between old and new behavior

### Fee Parameter Immutability

A critical feature of the TicketV2 structure is that it preserves all fee parameters at the time of ticket creation. This ensures that:

1. **Protection from Changes**: Existing ticket holders maintain their original fee terms even if administrators change the global fee parameters
2. **Fair Treatment**: Users who queued under specific fee terms are guaranteed those terms throughout their exit process
3. **No Retroactive Changes**: Admin cannot retroactively change fees for users who have already queued

**Example Scenario**:
- User A queues exit when fee is 10%
- Admin changes global fee to 20%
- User A still pays only 10% when they exit
- New users (User B) who queue after the change will pay 20%

### Required Contract Changes

#### IExitQueue Interface Updates

```solidity
interface IExitQueue {
  struct TicketV2 {
    address holder;
    uint48 queuedAt;
    uint48 minCooldown;
    uint48 cooldown;
    uint16 feePercent;
    uint16 minFeePercent;
    uint256 slope;
  }

  /// @notice Get ticket information for a token ID
  /// @param _tokenId The token ID to query
  /// @return ticket The TicketV2 struct containing holder, queuedAt, and all fee parameters
  function queue(
    uint256 _tokenId
  ) external view returns (TicketV2 memory ticket);

  // ticketHolder() remains unchanged - returns address
}
```

#### ExitQueue Contract Updates

##### Storage Changes

```solidity
/// @notice tokenId => TicketV2
mapping(uint256 => TicketV2) internal _queue;
```

##### Key Function Modifications

**`queueExit(uint256 _tokenId, address _ticketHolder)`**

- Store `queuedAt = block.timestamp` for dynamic fee calculations
- Capture current fee parameters to lock in terms for this ticket
- Create `TicketV2` struct with all parameters:
```solidity
_queue[_tokenId] = TicketV2({
  holder: _ticketHolder,
  queuedAt: uint48(block.timestamp),
  minCooldown: minCooldown,
  cooldown: cooldown,
  feePercent: uint16(feePercent),
  minFeePercent: uint16(minFeePercent),
  slope: _slope
});
```

**`canExit(uint256 _tokenId)`**

- Uses `ticket.minCooldown` (NOT global `minCooldown`) to determine if the minimum wait period has elapsed
- Returns true only after `block.timestamp - ticket.queuedAt >= ticket.minCooldown`

**`calculateFee(uint256 _tokenId)`**

- All fee calculations use ticket parameters (feePercent, minFeePercent, slope, cooldown, minCooldown)
- Elapsed time calculated as `block.timestamp - ticket.queuedAt`
- No backwards compatibility - clean implementation using new structure

## Legacy Checkpoint Removal

This version removes the legacy requirement for `nextExitDate()` to align with weekly checkpoint intervals. Previously, exits were forced to wait until the next weekly boundary regardless of individual cooldown completion. This requirement no longer serves a purpose and created unnecessary delays. The new implementation allows exits to process immediately once individual cooldown conditions are met, providing faster and more responsive exit processing.

## Deprecated Legacy Functions

### `setFeePercent(uint256 _feePercent)`

**Reason**: Incomplete parameter specification in dynamic fee system
**Migration**: Use `setFixedExitFeePercent()` for equivalent functionality

### `setCooldown(uint48 _cooldown)`

**Reason**: Cooldown changes affect slope calculations and require fee parameter review
**Migration**: Use appropriate fee setting function that includes cooldown parameter

## Covered Use Cases

### Case Analysis

1. **Dynamic Decay**: `setDynamicExitFeePercent()` ✅
2. **Tiered Penalty**: `setTieredExitFeePercent()` ✅
3. **Fixed Rate with Early Exit**: `setFixedExitFeePercent(fee, 0)` ✅
4. **Fixed Rate, No Early Exit**: `setFixedExitFeePercent(fee, cooldown)` ✅
5. **Always-on Fee**: `setFixedExitFeePercent(fee, 0)` ✅
6. **No Fee System**: `setFixedExitFeePercent(0, 0)` ✅

All major fee configuration patterns are covered through the three setter functions.

## Design Philosophy

### Clean Break Strategy

Rather than maintaining dual systems, we're implementing a clean architectural break that:

- Eliminates technical debt from backwards compatibility
- Reduces complexity for developers and auditors
- Optimizes for the primary use case (dynamic fees)

### Atomic Parameter Setting

Each setter function requires all relevant parameters, forcing administrators to consider the complete fee configuration rather than making incremental changes that might have unintended interactions.

### Unified Internal State

All three configuration approaches manipulate the same underlying state variables (`maxFeePercent`, `minFeePercent`, `slope`, `minCooldown`), ensuring consistent behavior regardless of configuration method.

### Clear Conceptual Separation

- **Dynamic**: Linear decay over time
- **Tiered**: Binary early/normal fee structure
- **Fixed**: Single fee rate with early exit control
