# Aragon Ve Governance Audit

Aragon's first version of ve governance underwent 2 audits by Halborn and Blocksec, as well as an internal review by senior engineering in Aragon. The findings, changelog and associated PRs are included in the document below.

1. [Summary of Changes](#summary-of-changes)
2. [Notes from the Halborn Audit](#notes-from-the-halborn-audit)
   - [Critical and High Severity Issues](#critical-and-high-severity)
   - [Other Severity Issues](#other-severity)
   - [HAL-06 Issue](#hal-06)
3. [Notes from the BlocSec Audit](#notes-from-the-blocsec-audit)
4. [Notes from Aragon Internal Audit](#notes-from-aragon-internal-audit)

# Summary of changes

Audit scope is all files in the src folder. The `ProxyLib.sol` is a pre-audited contract unchanged from Aragon OSx and we do not require any further reviews.

Changes have been added into a rollup commit https://github.com/aragon/ve-governance/pull/30

The git history of this commit has been carefully squashed to make it clean and easy to review the incremental changes added at each step. We propose going ahead with this.

# Notes from the Halborn Audit

https://www.halborn.com/portal/reports/ve-governance-hub

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

| Severity | Issue                                                                                          | Status          | Comment or PR                                                                                              |
| -------- | ---------------------------------------------------------------------------------------------- | --------------- | ---------------------------------------------------------------------------------------------------------- |
| I        | (HAL-01/02) Naming issues with Clock contract                                                  | Fixed           | https://github.com/aragon/ve-governance/pull/10                                                            |
| L        | (HAL-08) Shared role for pause and unpause functions                                           | Acknowledged    | Noted for future releases                                                                                  |
| I        | 7.12 (HAL-22) Critical roles not assigned in contract setup                                    | Fixed           | https://github.com/aragon/ve-governance/pull/11                                                            |
| I        | 7.19 (HAL-05) Unnecessary calculation in checkpoint function (+other simple gas optimisations) | Fixed           | https://github.com/aragon/ve-governance/pull/12                                                            |
| I        | 7.20 (HAL-20) Potentially unnecessary check in reset function                                  | Fixed           | https://github.com/aragon/ve-governance/pull/13                                                            |
| I        | 7.18 (HAL-19) Fee precision too high                                                           | Fixed + Revised | https://github.com/aragon/ve-governance/pull/14                                                            |
| I        | 7.17 (HAL-18) Redundant exit check and missing documentation in exit function                  | Acknowledged    | Accepted the redundancy - we prefer to have the check in place given the critical nature of the exit queue |
| I        | 7.16 (HAL-09) Unset dependencies may cause reverts and improper behavior                       | Acknowledged    | Noted for future: implement a graceful and idomatic revert strategy.                                       |
| I        | 7.15 (HAL-07) Misleading variable name for user interaction tracking                           | Fixed           | https://github.com/aragon/ve-governance/pull/15                                                            |
| I        | 7.13 (HAL-03) Lack of contract validation in initializer                                       | Acknowledged    | The DAO and deployers are responsible for ensuring they validate the contracts and can update if needed    |
| I        | 7.11 (HAL-21) Inconsistent voting power reporting in Reset event                               | Fixed           | https://github.com/aragon/ve-governance/pull/16                                                            |
| M        | 7.8 (HAL-11) Incorrect balance tracking for non-standard ERC20 tokens                          | Fixed + Revised | https://github.com/aragon/ve-governance/pull/17                                                            |
| L        | 7.9 (HAL-17) Potential bypass of minimum lock time at checkpoint boundaries                    | Fixed           | https://github.com/aragon/ve-governance/pull/25                                                            |
| M        | 7.7 (HAL-06) Checkpoint function allows non-chronological updates                              | Fixed           | See [HAL-06 Below](#HAL-06) Fix is https://github.com/aragon/ve-governance/pull/26                         |
| I        | 7.14 (HAL-04) Unbounded warmup period can span multiple epochs                                 | Semi-Fixed      | https://github.com/aragon/ve-governance/pull/27                                                            |

- See the aragon section below for some consistent findings wrt strict inequalities which we have addressed

### HAL-06

![image](https://github.com/user-attachments/assets/b211c368-2e14-4d80-a7f4-de7d1b83fbfb)

# Notes from the BlockSec Audit

https://docs.google.com/document/d/1bLOIahrZjzf7DrraT42F9mBiLwpn4b9_Npn3GJlK93M/

| Severity | Issue                                                               | Status       | Comment or PR                                                            |
| -------- | ------------------------------------------------------------------- | ------------ | ------------------------------------------------------------------------ |
| H        | Incorrect calculation of newTokenId in function `\_createLockFor()` | Fixed        | https://github.com/aragon/ve-governance/pull/3                           |
| U        | Override function \_baseURI() for contract Lock                     | Acknowledged | Noted for future: have a proper Art Proxy or metadata proxy for the NFTs |
| U        | Lack of checks in function setWhitelisted()                         | Fixed        | https://github.com/aragon/ve-governance/pull/5                           |
| U        | Lack of refund method in contract VotingEscrow                      | Fixed        | https://github.com/aragon/ve-governance/pull/6                           |
| U        | Use dedicated event for function enableTransfers()                  | Acknowledged | Happy to leave as the single event with the signalling address           |

# Notes from Aragon Internal Audit

Aragon Audits were conducted by various team members.

- @novaknole provided a [gist](https://gist.github.com/novaknole/53d1478a724ab707b2c39ad41f05a636) with _findings_
- @brickpop @xavikh @carlosgj94 all contributed on an [internal audit document that you may not have access to](https://www.notion.so/aragonorg/ve-Internal-Review-641d2e99c53e4f2391821e6d3ef0673a) but which have been added as _Internal Review_ notes below.

| Severity | Issue                                                                                     | Status       | Comment or PR                                                                                                                       |
| -------- | ----------------------------------------------------------------------------------------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| U        | Finding 5: Fee percentage can be set by admin to 100%                                     | Acknowledged | This is a trust vector of the protocol at this current time                                                                         |
| U        | Finding 4: Admin can update cooldown after users stake to prevent unlock near permanently | Acknowledged | This is a trust vector of the protocol at this current time                                                                         |
| U        | Finding 3: Choice of epoch duration can affect voting power due to FPA                    | Acknowledged | We acknowledge that choosing an appropriate epoch length + testing curves is important for FPA                                      |
| U        | Finding 2: Questions regarding the change in voting power over time                       | Resolved     | These discussions were settled in private chats                                                                                     |
| U        | Finding 1: Tokens that do not support `.decimals` are not supported                       | TBC          | This check is potentially unneccessary https://github.com/aragon/ve-governance/pull/18                                              |
| U        | Finding 7: SupportsInterface should include the interface Ids                             | Fixed        | https://github.com/aragon/ve-governance/pull/20                                                                                     |
| U        | Finding 8: For loop in `ownedTokens` can be used as a DoS vector                          | Fixed        | https://github.com/aragon/ve-governance/pull/24                                                                                     |
| U        | Internal Review 1: metadata hash does nothing in the gauges                               | Fixed        | https://github.com/aragon/ve-governance/pull/21                                                                                     |
| U        | Internal Review 2: opportunities to compress storage with structs                         | Part Fixed   | https://github.com/aragon/ve-governance/pull/23                                                                                     |
| U        | Internal Review 3: use strict inequalities where possible                                 | Fixed        | https://github.com/aragon/ve-governance/pull/28                                                                                     |
| U        | Internal Review 4: Check \_\_gap values to ensure they align with occupied storage slots  | Fixed        | https://github.com/aragon/ve-governance/pull/30 review                                                                              |
| U        | Internal Review: can use early returns in the clock contract                              | Acknowledged | Minor optimisation - can be added as a refinement feature later                                                                     |
| U        | Internal Review: Log the timestamp of checkpoints                                         | Fixed        | https://github.com/aragon/ve-governance/pull/22                                                                                     |
| U        | Internal Review: x.pow(2) is less precise and more expensive than x.mul(x)                | Fixed        | https://github.com/aragon/ve-governance/pull/12                                                                                     |
| U        | Internal Review: passing very small weights to gauges leads to precision loss             | Acknowledged | In this build, voting is signalling only, so rounding errors are ok for small values, we may wish to reevaluate with onchain voting |
| U        | Internal Review: Small deposits and fees will round to zero in the exit queue             | Acknowledged | Fee rounding to zero simply won't charge a fee, we don't think it's a major issue + we can enforce a min deposit                    |

# Notes relating to the second round of audits by BlockSec

| Severity | Issue          | Status       | Comment or PR                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| -------- | -------------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| U        | New Note-1     | Acknowledged | This is correct and is acknowledged in the same manner as HAL-12. The voting power of votes in the withdrawal queue is active until the end of the current interval, but it cannot be used as the NFT is held by the escrow, so in the current implementation we don't believe this is a problem. Blocksec is correct to acknowledge that this should be addressed in future implementations.                                                                                                                                                                                                                                                                                                                                       |
| U        | New Note-2     | Acknowledged | Allowing the users to change votes during the voting period is intended behaviour in this implementation.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| U        | New Question-1 | Acknowledged | The purpose of the warmup period is to function as a minimum buffer before users can vote. In the current implementation, voting power starts accumulating from the start of the upcoming deposit interval (weekly by default), but to avoid someone opportunisitically locking 1 second before voting starts, we add a minimum period where they cannot vote. The intended behaviour is that the voting power _should_ still accumulate during this time.                                                                                                                                                                                                                                                                          |
| U        | New Question-2 | TBC          | Reviewing this in depth I believe the behaviour you mentioned is intended. The resolveEpochVoteXXIn function uses the sentinel value "0" to indicate "has started" (startsIn) or "has ended" (endsIn), else it returns a positive value. In the example you give, if one is outside the voting window. `EndsIn` should return 0 and `StartsIn` should return the seconds until the next voting window (including the buffer). That said, I agree this needs to be approached with care, the above semantics may not be well understood, and perhaps a different way of expressing active should be fetched. It's telling that the `resolveVotingActive` doesn't use the zero sentinel value, so again, it's not particularly clear. |
