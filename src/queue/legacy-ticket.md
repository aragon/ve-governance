# ExitQueue Dynamic Fees: Upgrade Strategy Decision

## Current State and Problem

### Existing Ticket Structure
```solidity
struct Ticket {
    address holder;
    uint256 exitDate;    // When the user can exit (queueTime + cooldown)
}
```

### The Problem
The current `exitDate` field is incompatible with dynamic fee calculations. Dynamic fees need to know **when the ticket was queued** to calculate fees based on time elapsed, but we only store when they can exit.

**Example Issue**:
- User queues at `t=100`, can exit at `t=200` (100-second cooldown)  
- For dynamic fees at `t=150`, we need to know they've waited 50 seconds
- But we only know they have 50 seconds remaining until `t=200`
- We can't determine the fee decay position without the original queue time

## Problem Statement

We're implementing dynamic exit fees for the ExitQueue contract, which requires changing how we store and calculate ticket data. The core question: **Should we maintain backwards compatibility for existing tickets during the upgrade?**

### Context
- **Limited current usage**: We don't have a ton of existing clients and nobody is explicitly asking for backwards compatibility
- **Consistency consideration**: We've maintained backwards compatibility for other features, so departing from this pattern should be a deliberate decision
- **Technical requirement**: Dynamic fees need to know when a ticket was queued, but current tickets only store exit dates

## Upgrade Options

### Option 1: Full Backwards Compatibility (Dual System)

**Approach**: Use feature flag in `initializeFrom()` to respect legacy tickets with separate handling.

**Technical Implementation**:
```solidity
struct TicketV2 {
    address holder;
    uint48 queuedAt;     // New: for dynamic fee calculation
    uint48 exitDate;     // Kept for potential future compatibility
}

// Single mapping with evolution
struct TicketV2 {
    address holder;
    uint48 queuedAt;
    uint48 legacyExitDate; // 0 for new tickets, set for migrated legacy
}
```

**Required Function Changes**:
```solidity
function calculateFee(uint256 tokenId) external view returns (uint256) {
    TicketV2 memory ticket = _queue[tokenId];
    
    if (ticket.legacyExitDate != 0) {
        // Legacy: use predetermined flat fee
        return legacyFlatFee * tokenAmount / 10000;
    }
    
    // New: dynamic fee calculation based on queue time
    return dynamicFeeCalculation(ticket.queuedAt);
}
```

Other functions like `canExit()`, `getFee()`, and view functions would have similar branching logic. It's not crazy complex, but it's not super clean either.

### Option 2: Breaking Change (Clean Slate)

**Approach**: Accept breaking change, migrate to new system entirely.

**Technical Implementation**:
```solidity
struct TicketV2 {
    address holder;
    uint48 queuedAt;     // Only field needed for dynamic fees
}
```

**Migration Strategy**: Document breaking changes, provide migration tools/timeline.

## Detailed Pros and Cons

### Option 1: Full Backwards Compatibility

#### Pros ✅
- **User Experience**: Existing users aren't disrupted or forced to re-queue
- **Predictable Legacy Behavior**: Old tickets get guaranteed flat fee at predetermined exit date
- **Risk Mitigation**: No chance of breaking existing integrations
- **Consistency**: Maintains our pattern of supporting backwards compatibility
- **Graceful Migration**: Clear cutoff between old and new behavior

#### Cons ❌
- **Code Complexity**: Every fee-related function needs branching logic for dual systems
- **Testing Burden**: 2-3x testing scenarios (legacy tickets, new tickets, mixed states)
- **Maintenance Overhead**: Long-term maintenance of two different calculation paths
- **Storage Overhead**: Larger struct with legacy fields or dual mappings
- **Gas Costs**: Additional conditional logic in fee calculations
- **Governance Complexity**: Admins must understand which parameters affect which tickets

### Option 2: Breaking Change

#### Pros ✅
- **Code Simplicity**: Single, clean implementation path
- **Easier Testing**: One system to test thoroughly
- **Better Performance**: No conditional logic overhead
- **Cleaner Architecture**: Purpose-built for dynamic fees
- **Easier Maintenance**: Single system to maintain and debug
- **Storage Efficiency**: Minimal struct size

#### Cons ❌
- **User Disruption**: Existing tickets become invalid or need migration
- **Integration Risk**: Potential to break existing client integrations
- **Inconsistent Pattern**: Breaks from our backwards compatibility approach
- **Migration Complexity**: Need to handle existing tickets somehow
- **Potential User Loss**: Users might be frustrated by forced changes

## Recommendation Framework

**Choose Option 1 (Backwards Compatibility) if**:
- User experience is our highest priority
- We have development bandwidth for complex implementation
- Consistency with past decisions is important
- We want to minimize any risk of user disruption

**Choose Option 2 (Breaking Change) if**:
- Code quality and maintainability are highest priority
- Our current user base is small enough to manage migration
- We want to establish a new pattern for major upgrades
- Timeline or complexity concerns are significant
