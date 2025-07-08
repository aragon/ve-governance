# Test Cases for DynamicExitQueue

## Unit Tests

### Constructor and Initialization

#### Test: Cannot initialize twice
- Call initialize() twice on same contract
- Assert: Second call reverts with Initializable error

#### Test: Initialization sets all parameters correctly
- Initialize with valid parameters (escrow, cooldown, dao, feePercent, clock, minLock)
- Assert: All state variables match input parameters
- Assert: Fixed fee system is configured (minFeePercent == feePercent, slope == 0)
- Assert: minCooldown == 0 (allowEarlyExit = true by default)

#### Test: Initialization parameter validation
- Test with zero addresses for escrow, dao, clock
- Test with minLock = 0
- Test with feePercent > 10000
- Assert: Reverts with appropriate errors

### State Variable Getters

#### Test: Slope getter returns correct scaled value
- Set dynamic fee with known parameters
- Calculate expected slope manually
- Assert: slope() returns expectedSlope / MAX_FEE_PERCENT

#### Test: All getters return correct values after fee system changes
- Test after each fee system type is configured
- Assert: feePercent, minFeePercent, cooldown, minCooldown match expected values

### Fee Setter Functions - Authorization

#### Test: All fee setters require QUEUE_ADMIN_ROLE
- Call setDynamicExitFeePercent, setTieredExitFeePercent, setFixedExitFeePercent without role
- Assert: All revert with authorization error

#### Test: setMinLock requires QUEUE_ADMIN_ROLE
- Call setMinLock without role
- Assert: Reverts with authorization error

### Dynamic Fee System Configuration

#### Test: Valid dynamic fee configuration
- Fuzz inputs within bounds: minFeePercent (0-9999), maxFeePercent (minFeePercent+1 to 10000), cooldown (minCooldown+1 to type(uint48).max), minCooldown (0 to cooldown-1)
- Call setDynamicExitFeePercent with fuzzy inputs
- Assert: feePercent == maxFeePercent
- Assert: minFeePercent == input minFeePercent
- Assert: cooldown == input cooldown
- Assert: minCooldown == input minCooldown
- Assert: slope() == (maxFeePercent - minFeePercent) / (cooldown - minCooldown)
- Assert: ExitFeePercentAdjusted event emitted with correct parameters and ExitFeeType.Dynamic

#### Test: Dynamic fee validation - fee bounds
- Test minFeePercent = 10001
- Test maxFeePercent = 10001
- Test both fees > 10000
- Assert: Reverts with FeePercentTooHigh(10000)

#### Test: Dynamic fee validation - fee relationship
- Test maxFeePercent == minFeePercent
- Test maxFeePercent < minFeePercent
- Assert: Reverts with InvalidFeeParameters

#### Test: Dynamic fee validation - cooldown relationship
- Test cooldown == minCooldown
- Test cooldown < minCooldown
- Assert: Reverts with CooldownTooShort

#### Test: Dynamic fee edge cases
- Test minCooldown = 0, cooldown = 1 (1 second decay)
- Test very long decay periods (years)
- Assert: Slope calculation handles precision correctly
- Assert: No overflow in slope calculation

#### Test: Hardcoded dynamic fee scenario 1
- Configure: minFeePercent = 0, maxFeePercent = 10000, cooldown = 4 weeks, minCooldown = 2 weeks
- Test timeElapsed = 0: Assert returns 10000 (100%)
- Test timeElapsed = 2 weeks: Assert returns 10000 (100%)
- Test timeElapsed = 3 weeks: Assert returns 5000 (50%)
- Test timeElapsed = 3.5 weeks: Assert returns 2500 (25%)
- Test timeElapsed = 4 weeks: Assert returns 0 (0%)
- Test timeElapsed > 4 weeks: Assert returns 0 (0%)

#### Test: Hardcoded dynamic fee scenario 2
- Configure: minFeePercent = 1000, maxFeePercent = 2000, cooldown = 1 year, minCooldown = 0
- Test timeElapsed = 0: Assert returns 2000 (20%)
- Test timeElapsed = 1 second: Assert returns < 2000 (accounting for rounding)
- Test timeElapsed = 6 months: Assert returns 1500 (15%)
- Test timeElapsed = 11 months: Assert returns > 1000 (>10%)
- Test timeElapsed = 1 year: Assert returns 1000 (10%)
- Test timeElapsed > 1 year: Assert returns 1000 (10%)

### Tiered Fee System Configuration

#### Test: Valid tiered fee configuration
- Fuzz inputs within bounds: baseFeePercent (0-9999), earlyFeePercent (baseFeePercent+1 to 10000), cooldown (minCooldown+1 to type(uint48).max), minCooldown (0 to cooldown-1)
- Call setTieredExitFeePercent with fuzzy inputs
- Assert: feePercent == earlyFeePercent
- Assert: minFeePercent == baseFeePercent
- Assert: cooldown == input cooldown
- Assert: minCooldown == input minCooldown
- Assert: slope() == 0
- Assert: ExitFeePercentAdjusted event emitted with correct parameters and ExitFeeType.Tiered

#### Test: Tiered fee validation - fee bounds
- Test baseFeePercent = 10001
- Test earlyFeePercent = 10001
- Assert: Reverts with FeePercentTooHigh(10000)

#### Test: Tiered fee validation - fee relationship
- Test earlyFeePercent == baseFeePercent
- Test earlyFeePercent < baseFeePercent
- Assert: Reverts with InvalidFeeParameters

#### Test: Tiered fee validation - cooldown relationship
- Test cooldown == minCooldown
- Test cooldown < minCooldown
- Assert: Reverts with CooldownTooShort

### Fixed Fee System Configuration

#### Test: Valid fixed fee configuration with early exit allowed
- Fuzz inputs within bounds: feePercent (0-10000), cooldown (0 to type(uint48).max)
- Call setFixedExitFeePercent with fuzzy inputs and allowEarlyExit = true
- Assert: feePercent == input feePercent
- Assert: minFeePercent == input feePercent
- Assert: cooldown == input cooldown
- Assert: minCooldown == 0
- Assert: slope() == 0
- Assert: ExitFeePercentAdjusted event emitted with correct parameters and ExitFeeType.Fixed

#### Test: Valid fixed fee configuration with early exit disabled
- Fuzz inputs within bounds: feePercent (0-10000), cooldown (0 to type(uint48).max)
- Call setFixedExitFeePercent with fuzzy inputs and allowEarlyExit = false
- Assert: feePercent == input feePercent
- Assert: minFeePercent == input feePercent
- Assert: cooldown == input cooldown
- Assert: minCooldown == cooldown
- Assert: slope() == 0
- Assert: ExitFeePercentAdjusted event emitted with correct parameters and ExitFeeType.Fixed

#### Test: Fixed fee validation - fee bounds
- Test feePercent = 10001
- Assert: Reverts with FeePercentTooHigh(10000)

### MinLock Configuration

#### Test: Valid minLock configuration
- Fuzz input within bounds: minLock (1 to type(uint48).max)
- Call setMinLock with fuzzy input
- Assert: minLock == input
- Assert: MinLockSet event emitted

#### Test: MinLock validation
- Test minLock = 0
- Assert: Reverts with MinLockOutOfBounds

### Time-Based Fee Calculations

#### Test: getTimeBasedFee for fixed fee system
- Configure fixed fee system with 2000 basis points
- Test with various timeElapsed values (0, minCooldown, cooldown, beyond cooldown)
- Assert: Always returns 2000 regardless of time

#### Test: getTimeBasedFee for tiered fee system
- Configure tiered system: baseFee = 1000, earlyFee = 3000, cooldown = 604800 (7 days), minCooldown = 86400 (1 day)
- Test timeElapsed = 0: Assert returns 3000
- Test timeElapsed = 86400: Assert returns 3000
- Test timeElapsed = 604799: Assert returns 3000
- Test timeElapsed = 604800: Assert returns 1000
- Test timeElapsed = 1000000: Assert returns 1000

#### Test: getTimeBasedFee for dynamic fee system
- Configure dynamic system: minFee = 1000, maxFee = 5000, cooldown = 518400 (6 days), minCooldown = 172800 (2 days)
- Test timeElapsed = 0: Assert returns 5000
- Test timeElapsed = 172800: Assert returns 5000
- Test timeElapsed = 259200 (3 days): Assert returns approximately 4000
- Test timeElapsed = 345600 (4 days): Assert returns approximately 3000
- Test timeElapsed = 432000 (5 days): Assert returns approximately 2000
- Test timeElapsed = 518400: Assert returns 1000
- Test timeElapsed = 1000000: Assert returns 1000

#### Test: getTimeBasedFee boundary conditions
- Test exactly at minCooldown timestamp
- Test exactly at cooldown timestamp
- Test one second before and after boundaries
- Assert: Correct fee transitions at boundaries

#### Test: getTimeBasedFee precision handling
- Configure system with maximum fee difference and minimum time difference
- Test fee reduction calculation doesn't overflow
- Test fee reduction doesn't exceed maximum possible reduction
- Assert: Returns minFeePercent when calculated reduction exceeds maximum

### Queue Exit Function

#### Test: Successful queue exit
- Mock valid escrow call with valid tokenId and ticketHolder
- Call queueExit from escrow address
- Assert: Ticket created with correct holder and queuedAt timestamp
- Assert: ExitQueuedV2 event emitted with correct parameters

#### Test: Queue exit authorization
- Call queueExit from non-escrow address
- Assert: Reverts with OnlyEscrow error

#### Test: Queue exit validation - zero address
- Call queueExit with ticketHolder = address(0)
- Assert: Reverts with ZeroAddress error

#### Test: Queue exit validation - already queued
- Queue exit for tokenId once
- Attempt to queue exit for same tokenId again
- Assert: Second call reverts with AlreadyQueued error

#### Test: Queue exit validation - minLock not reached
- Mock escrow to return lock start time such that minLock period hasn't elapsed
- Call queueExit
- Assert: Reverts with MinLockNotReached error

#### Test: Queue exit validation - minLock boundary
- Mock escrow to return lock start time exactly at minLock boundary
- Call queueExit exactly at minLock expiration
- Assert: Succeeds and creates ticket

### Exit Function

#### Test: Successful exit
- Queue exit for tokenId
- Fast forward past minCooldown
- Mock escrow to return positive locked amount
- Call exit from escrow address
- Assert: Returns calculated fee amount
- Assert: Ticket is cleared (holder = address(0), queuedAt = 0)
- Assert: Exit event emitted with correct tokenId and fee

#### Test: Exit authorization
- Call exit from non-escrow address
- Assert: Reverts with OnlyEscrow error

#### Test: Exit validation - cannot exit
- Queue exit for tokenId
- Call exit before minCooldown elapsed
- Assert: Reverts with CannotExit error

#### Test: Exit fee calculation consistency
- Queue exit for tokenId
- Fast forward to various time points
- Mock escrow to return known locked amount
- Call exit and capture returned fee
- Assert: Returned fee matches calculateFee result

### Calculate Fee Function

#### Test: Calculate fee with no ticket
- Call calculateFee for non-existent tokenId
- Assert: Returns 0

#### Test: Calculate fee with zero balance
- Queue exit for tokenId
- Mock escrow to return 0 locked amount
- Call calculateFee
- Assert: Reverts with NoLockBalance error

#### Test: Calculate fee with valid conditions
- Queue exit for tokenId
- Mock escrow to return known locked amount (e.g., 1000000)
- Fast forward to various time points
- Call calculateFee
- Assert: Returns (lockedAmount * expectedFeePercent) / 10000

#### Test: Calculate fee precision and rounding
- Test with very small locked amounts (1, 2, 99)
- Test with very large locked amounts (type(uint256).max / 10000)
- Test fee calculations that result in fractional amounts
- Assert: Proper rounding behavior and no overflow

#### Test: Calculate fee with different fee systems
- Test same tokenId and locked amount across all three fee system types
- Assert: Returns appropriate fees based on configured system

### View Functions

#### Test: isCool function
- Queue exit for tokenId
- Test at various time points relative to cooldown
- Assert: Returns false before cooldown elapsed
- Assert: Returns true after cooldown elapsed
- Assert: Returns false for non-existent tickets

#### Test: canExit function
- Queue exit for tokenId
- Test at various time points relative to minCooldown
- Assert: Returns false before minCooldown elapsed
- Assert: Returns true after minCooldown elapsed
- Assert: Returns false for non-existent tickets

#### Test: ticketHolder function
- Queue exit for tokenId with specific holder
- Assert: Returns correct holder address
- Assert: Returns address(0) for non-existent tickets
- Exit the token and test again
- Assert: Returns address(0) after exit

#### Test: queue function
- Queue exit for tokenId
- Call queue function
- Assert: Returns TicketV2 with correct holder and queuedAt
- Assert: Returns empty TicketV2 for non-existent tickets

#### Test: timeToMinLock function
- Mock escrow to return various lock start times
- Call timeToMinLock for tokenId
- Assert: Returns lockStart + minLock

### Withdraw Function

#### Test: Successful withdraw
- Add tokens to contract balance
- Call withdraw with valid amount and WITHDRAW_ROLE
- Assert: Tokens transferred to caller
- Assert: Contract balance reduced

#### Test: Withdraw authorization
- Call withdraw without WITHDRAW_ROLE
- Assert: Reverts with authorization error

#### Test: Withdraw with insufficient balance
- Call withdraw with amount exceeding contract balance
- Assert: Reverts with ERC20 transfer error

## Functional Tests

### Fee System Transitions

#### Test: Dynamic to tiered transition
- Configure dynamic fee system
- Queue exit for tokenId
- Change to tiered fee system
- Fast forward time
- Assert: Existing ticket uses new fee calculation logic

#### Test: Tiered to fixed transition
- Configure tiered fee system
- Queue exit for tokenId
- Change to fixed fee system
- Fast forward time
- Assert: Existing ticket uses new fee calculation logic

#### Test: Fixed to dynamic transition
- Configure fixed fee system
- Queue exit for tokenId
- Change to dynamic fee system
- Fast forward time
- Assert: Existing ticket uses new fee calculation logic

#### Test: Multiple transitions with active tickets
- Configure initial fee system
- Queue exits for multiple tokenIds at different times
- Transition through all fee system types
- Test fee calculations at various points
- Assert: All tickets use current fee system logic

### Time-Based Behavior

#### Test: Long-term stability
- Configure dynamic fee system with long cooldown periods
- Queue exit for tokenId
- Fast forward through entire decay period in steps
- Test fee calculations at each step
- Assert: Smooth linear decay from max to min fee
- Assert: No unexpected jumps or reversals

#### Test: Boundary precision
- Configure system with parameters that create precision challenges
- Test fee calculations exactly at boundary timestamps
- Assert: Correct fee transitions without precision errors

#### Test: Multiple active tickets
- Queue exits for multiple tokenIds at staggered times
- Test fee calculations for all tickets at various future timestamps
- Assert: Each ticket calculates fees based on its own queuedAt time

### Administrative Workflows

#### Test: Fee system reconfiguration workflow
- Start with one fee system configuration
- Have multiple active tickets
- Reconfigure to different fee system
- Verify all tickets immediately use new fee logic
- Verify new tickets use new configuration

#### Test: MinLock adjustment workflow
- Queue exit for tokenId with current minLock
- Increase minLock
- Attempt to queue exit for new tokenId before new minLock
- Assert: New queuing fails with MinLockNotReached

#### Test: Emergency parameter adjustment
- Configure system with problematic parameters
- Have active tickets
- Adjust parameters to fix issues
- Verify active tickets work correctly with new parameters

### Edge Case Scenarios

#### Test: Maximum fee scenario
- Configure system with 100% fee (10000 basis points)
- Queue exit and perform exit
- Assert: Entire locked amount is collected as fee

#### Test: Zero fee scenario
- Configure system with 0% fee
- Queue exit and perform exit
- Assert: No fee is collected

#### Test: Minimum time granularity
- Configure system with 1-second differences between time boundaries
- Test fee calculations at exact boundaries
- Assert: Correct fee transitions at 1-second precision

#### Test: Maximum time periods
- Configure system with maximum uint48 values for cooldown periods
- Test fee calculations over long periods
- Assert: No overflow or underflow in calculations

### Error Handling

#### Test: Cascading error conditions
- Test combinations of error conditions (e.g., no ticket AND zero balance)
- Assert: Appropriate error is returned in correct order of precedence

#### Test: State consistency after errors
- Trigger various error conditions during operations
- Assert: Contract state remains consistent
- Assert: No partial state updates occur

### Precision and Mathematical Accuracy

#### Test: Slope calculation precision
- Configure dynamic systems with parameters that challenge precision
- Test fee calculations across decay period
- Assert: Monotonic decrease in fees
- Assert: Reaches exactly minFeePercent at cooldown

#### Test: Fee calculation accuracy
- Test fee calculations with various locked amounts and fee percentages
- Assert: Mathematical accuracy within acceptable precision bounds
- Assert: No unexpected rounding errors

#### Test: Boundary condition mathematical accuracy
- Test fee calculations exactly at time boundaries
- Assert: Exact fee values at boundaries match expectations
- Assert: No precision errors cause incorrect fee jumps
