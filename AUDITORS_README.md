Audit scope is all files in the src folder. The `ProxyLib.sol` is a pre-audited contract unchanged from Aragon OSx and we do not require any further reviews.

## Curve conventions

QuadraticIncreasingEscrow attempts to follow a generalised structure that can work for both increasing curves and decreasing curves. Because of this, certain functions have limited use in the current, increasing case:

- It's not possible to increase a lock qty, hence `oldLocked` is not used
- Binary searching through user points is somewhat redundant given the low number of possible locks
- We assume that the calling contract aligns checkpoints with the checkpoint epoch.
