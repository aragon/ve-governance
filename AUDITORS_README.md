Audit scope is all files in the src folder. The `ProxyLib.sol` is a pre-audited contract unchanged from Aragon OSx and we do not require any further reviews.

## Curve conventions

QuadraticIncreasingEscrow attempts to follow a generalised structure that can work for both increasing curves and decreasing curves. Because of this, certain functions have limited use in the current, increasing case:

- It's not possible to increase a lock qty, hence `oldLocked` is not used
- Binary searching through user points is somewhat redundant given the low number of possible locks
- We assume that the calling contract aligns checkpoints with the checkpoint epoch.

# Notes from the Halborn Audit

| Issue                                                                    | Status       | Comment or PR                                                                                                                                                                                                                           |
| ------------------------------------------------------------------------ | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| (HAL-13) Token ID reuse leads to protocol deadlock                       | Fixed        | https://github.com/aragon/ve-governance/pull/3                                                                                                                                                                                          |
| (HAL-12) Inaccurate voting power reporting after withdrawal initiation   | Acknowledged | There are a few competing implementations that address this concern and we think the best approach is to compare when we add onchain voting. In the current setup this issue does not cause any obvious vulnerabilities that we can see |
| (HAL-14) Unsafe minting in Lock contract                                 | Fixed        | https://github.com/aragon/ve-governance/pull/4                                                                                                                                                                                          |
| (HAL-15) Critical withdrawal blockage due to escrow address whitelisting | Fixed        | https://github.com/aragon/ve-governance/pull/5                                                                                                                                                                                          |
| (HAL-16) Potential token lock due to unrestricted escrow transfers       | Fixed        | https://github.com/aragon/ve-governance/pull/6                                                                                                                                                                                          |
| (HAL-10) Unrestricted NFT contract change enables potential fund theft   | Fixed        | https://github.com/aragon/ve-governance/pull/6                                                                                                                                                                                          |
