Audit scope is all files in the src folder. The `ProxyLib.sol` is a pre-audited contract unchanged from Aragon OSx and we do not require any further reviews.

## Curve conventions

QuadraticIncreasingEscrow attempts to follow a generalised structure that can work for both increasing curves and decreasing curves. Because of this, certain functions have limited use in the current, increasing case:

- It's not possible to increase a lock qty, hence `oldLocked` is not used
- Binary searching through user points is somewhat redundant given the low number of possible locks
- We assume that the calling contract aligns checkpoints with the checkpoint epoch.

# Notes from the Halborn Audit

## Critical and High Severity

| Severity | Issue                                                                    | Status     | Comment or PR                                   |
| -------- | ------------------------------------------------------------------------ | ---------- | ----------------------------------------------- |
| C        | (HAL-13) Token ID reuse leads to protocol deadlock                       | Fixed      | https://github.com/aragon/ve-governance/pull/3  |
| H        | (HAL-14) Unsafe minting in Lock contract                                 | Fixed      | https://github.com/aragon/ve-governance/pull/4  |
| H        | (HAL-15) Critical withdrawal blockage due to escrow address whitelisting | Fixed      | https://github.com/aragon/ve-governance/pull/5  |
| H        | (HAL-16) Potential token lock due to unrestricted escrow transfers       | Fixed      | https://github.com/aragon/ve-governance/pull/6  |
| H        | (HAL-10) Unrestricted NFT contract change enables potential fund theft   | Fixed      | https://github.com/aragon/ve-governance/pull/6  |
| H        | (HAL-12) Inaccurate voting power reporting after withdrawal initiation   | Semi-Fixed | https://github.com/aragon/ve-governance/pull/22 |

## Other Severity

| Severity | Issue                                                                                          | Status       | Comment or PR                                                                                              |
| -------- | ---------------------------------------------------------------------------------------------- | ------------ | ---------------------------------------------------------------------------------------------------------- |
| I        | (HAL-01/02) Naming issues with Clock contract                                                  | Fixed        | https://github.com/aragon/ve-governance/pull/10                                                            |
| L        | (HAL-08) Shared role for pause and unpause functions                                           | Acknowledged | Noted for future releases                                                                                  |
| I        | 7.12 (HAL-22) Critical roles not assigned in contract setup                                    | Fixed        | https://github.com/aragon/ve-governance/pull/11                                                            |
| I        | 7.19 (HAL-05) Unnecessary calculation in checkpoint function (+other simple gas optimisations) | Fixed        | https://github.com/aragon/ve-governance/pull/12                                                            |
| I        | 7.20 (HAL-20) Potentially unnecessary check in reset function                                  | Fixed        | https://github.com/aragon/ve-governance/pull/13                                                            |
| I        | 7.18 (HAL-19) Fee precision too high                                                           | Fixed        | https://github.com/aragon/ve-governance/pull/14                                                            |
| I        | 7.17 (HAL-18) Redundant exit check and missing documentation in exit function                  | Acknowledged | Accepted the redundancy - we prefer to have the check in place given the critical nature of the exit queue |
| I        | 7.16 (HAL-09) Unset dependencies may cause reverts and improper behavior                       | Acknowledged | Noted for future: implement a graceful and idomatic revert strategy.                                       |
| I        | 7.15 (HAL-07) Misleading variable name for user interaction tracking                           | Fixed        | https://github.com/aragon/ve-governance/pull/15                                                            |
| I        | 7.13 (HAL-03) Lack of contract validation in initializer                                       | Acknowledged | The DAO and deployers are responsible for ensuring they validate the contracts and can update if needed    |
| I        | 7.11 (HAL-21) Inconsistent voting power reporting in Reset event                               | Fixed        | https://github.com/aragon/ve-governance/pull/16                                                            |
| M        | 7.8 (HAL-11) Incorrect balance tracking for non-standard ERC20 tokens                          | Fixed        | https://github.com/aragon/ve-governance/pull/17                                                            |

## Not yet Done

| Severity | Issue                                                                       | Status  | Comment or PR                                                              |
| -------- | --------------------------------------------------------------------------- | ------- | -------------------------------------------------------------------------- |
| L        | 7.9 (HAL-17) Potential bypass of minimum lock time at checkpoint boundaries |         |
| M        | 7.7 (HAL-06) Checkpoint function allows non-chronological updates           | Blocked | Description of the issue does not match the title - awaiting clarification |
| I        | 7.14 (HAL-04) Unbounded warmup period can span multiple epochs              |         |

# Notes from the BlocSec Audit

| Severity | Issue                                                               | Status       | Comment or PR                                                            |
| -------- | ------------------------------------------------------------------- | ------------ | ------------------------------------------------------------------------ |
| H        | Incorrect calculation of newTokenId in function `\_createLockFor()` | Fixed        | https://github.com/aragon/ve-governance/pull/3                           |
| U        | Override function \_baseURI() for contract Lock                     | Acknowledged | Noted for future: have a proper Art Proxy or metadata proxy for the NFTs |
| U        | Lack of checks in function setWhitelisted()                         | Fixed        | https://github.com/aragon/ve-governance/pull/5                           |
| U        | Lack of refund method in contract VotingEscrow                      | Fixed        | https://github.com/aragon/ve-governance/pull/6                           |
| U        | Use dedicated event for function enableTransfers()                  | Acknowledged | Happy to leave as the single event with the signalling address           |

# Notes from Aragon Internal Audit

Aragon Audits were conducted by various team members.

- @novaknole provided a [gist](https://gist.github.com/novaknole/53d1478a724ab707b2c39ad41f05a636)
- @brickpop @xavikh @carlosgj94 all contributed on an [internal audit document that you may not have access to](https://www.notion.so/aragonorg/ve-Internal-Review-641d2e99c53e4f2391821e6d3ef0673a)

| Severity | Issue                                                                                     | Status       | Comment or PR                                                                                                                       |
| -------- | ----------------------------------------------------------------------------------------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| U        | Finding 5: Fee percentage can be set by admin to 100%                                     | Acknowledged | This is a trust vector of the protocol at this current time                                                                         |
| U        | Finding 4: Admin can update cooldown after users stake to prevent unlock near permanently | Acknowledged | This is a trust vector of the protocol at this current time                                                                         |
| U        | Finding 3: Choice of epoch duration can affect voting power due to FPA                    | Acknowledged | We acknowledge that choosing an appropriate epoch length + testing curves is important for FPA                                      |
| U        | Finding 2: Questions regarding the change in voting power over time                       | Resolved     | These discussions were settled in private chats                                                                                     |
| U        | Finding 1: Tokens that do not support `.decimals` are not supported                       | TBC          | This check is potentially unneccessary https://github.com/aragon/ve-governance/pull/18                                              |
| U        | Internal Review 1: metadata hash does nothing in the gauges                               | Fixed        | https://github.com/aragon/ve-governance/pull/21                                                                                     |
| U        | Internal Review: x.pow(2) is less precise and more expensive than x.mul(x)                | Fixed        | https://github.com/aragon/ve-governance/pull/12                                                                                     |
| U        | Internal Review: passing very small weights to gauges leads to precision loss             | Acknowledged | In this build, voting is signalling only, so rounding errors are ok for small values, we may wish to reevaluate with onchain voting |
| U        | Internal Review: Small deposits and fees will round to zero in the exit queue             | Acknowledged | Fee rounding to zero simply won't charge a fee, we don't think it's a major issue + we can enforce a min deposit                    |
| U        | Finding 7: SupportsInterface should include the interface Ids                             | Fixed        | https://github.com/aragon/ve-governance/pull/20                                                                                     |
| U        | Internal Review: Log the timestamp of checkpoints                                         | Fixed        | https://github.com/aragon/ve-governance/pull/22                                                                                     |

## Not yet Done

| Severity | Issue                                                                            | Status  | Comment or PR                                          |
| -------- | -------------------------------------------------------------------------------- | ------- | ------------------------------------------------------ |
| U        | Internal Review: can use early returns in the clock contract                     |         |                                                        |
| U        | Finding 8: For loop in `ownedTokens` can be used as a DoS vector                 |         |                                                        |
| U        | Finding 6: Check \_\_gap values to ensure they align with occupied storage slots | Blocked | Wait till all audit findings merged for a final review |
| U        | Internal Review: opportunities to compress storage with structs                  |         |                                                        |
