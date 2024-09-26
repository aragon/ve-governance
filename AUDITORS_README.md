Audit scope is all files in the src folder. The `ProxyLib.sol` is a pre-audited contract unchanged from Aragon OSx and we do not require any further reviews.

## Curve conventions

QuadraticIncreasingEscrow attempts to follow a generalised structure that can work for both increasing curves and decreasing curves. Because of this, certain functions have limited use in the current, increasing case:

- It's not possible to increase a lock qty, hence `oldLocked` is not used
- Binary searching through user points is somewhat redundant given the low number of possible locks
- We assume that the calling contract aligns checkpoints with the checkpoint epoch.

# Notes from the Halborn Audit

## Critical and High Severity

| Severity | Issue                                                                    | Status       | Comment or PR                                                                                                                                                                                                                           |
| -------- | ------------------------------------------------------------------------ | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| C        | (HAL-13) Token ID reuse leads to protocol deadlock                       | Fixed        | https://github.com/aragon/ve-governance/pull/3                                                                                                                                                                                          |
| H        | (HAL-12) Inaccurate voting power reporting after withdrawal initiation   | Acknowledged | There are a few competing implementations that address this concern and we think the best approach is to compare when we add onchain voting. In the current setup this issue does not cause any obvious vulnerabilities that we can see |
| H        | (HAL-14) Unsafe minting in Lock contract                                 | Fixed        | https://github.com/aragon/ve-governance/pull/4                                                                                                                                                                                          |
| H        | (HAL-15) Critical withdrawal blockage due to escrow address whitelisting | Fixed        | https://github.com/aragon/ve-governance/pull/5                                                                                                                                                                                          |
| H        | (HAL-16) Potential token lock due to unrestricted escrow transfers       | Fixed        | https://github.com/aragon/ve-governance/pull/6                                                                                                                                                                                          |
| H        | (HAL-10) Unrestricted NFT contract change enables potential fund theft   | Fixed        | https://github.com/aragon/ve-governance/pull/6                                                                                                                                                                                          |

## Other Severity

| Severity | Issue                                                                                          | Status       | Comment or PR                                   |
| -------- | ---------------------------------------------------------------------------------------------- | ------------ | ----------------------------------------------- |
| I        | (HAL-01/02) Naming issues with Clock contract                                                  | Fixed        | https://github.com/aragon/ve-governance/pull/10 |
| L        | (HAL-08) Shared role for pause and unpause functions                                           | Acknowledged | Noted for future releases                       |
| I        | 7.12 (HAL-22) Critical roles not assigned in contract setup                                    | Fixed        | https://github.com/aragon/ve-governance/pull/11 |
| I        | 7.19 (HAL-05) Unnecessary calculation in checkpoint function (+other simple gas optimisations) | Fixed        | https://github.com/aragon/ve-governance/pull/12 |

## Not yet Done

| Severity | Issue                                                                         | Status | Comment or PR |
| -------- | ----------------------------------------------------------------------------- | ------ | ------------- |
| L        | 7.9 (HAL-17) Potential bypass of minimum lock time at checkpoint boundaries   |        |
| M        | 7.8 (HAL-11) Incorrect balance tracking for non-standard ERC20 tokens         |        |
| M        | 7.7 (HAL-06) Checkpoint function allows non-chronological updates             |        |
| I        | 7.20 (HAL-20) Potentially unnecessary check in reset function                 |        |
| I        | 7.18 (HAL-19) Fee precision too high                                          |        |
| I        | 7.17 (HAL-18) Redundant exit check and missing documentation in exit function |        |
| I        | 7.16 (HAL-09) Unset dependencies may cause reverts and improper behavior      |        |
| I        | 7.15 (HAL-07) Misleading variable name for user interaction tracking          |        |
| I        | 7.14 (HAL-04) Unbounded warmup period can span multiple epochs                |        |
| I        | 7.13 (HAL-03) Lack of contract validation in initializer                      |        |
| I        | 7.11 (HAL-21) Inconsistent voting power reporting in Reset event              |        |
| L        | 7.9 (HAL-17) Potential bypass of minimum lock time at checkpoint boundaries   |        |
| M        | 7.8 (HAL-11) Incorrect balance tracking for non-standard ERC20 tokens         |        |
| M        | 7.7 (HAL-06) Checkpoint function allows non-chronological updates             |        |
