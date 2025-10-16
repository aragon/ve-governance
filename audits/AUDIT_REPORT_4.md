# Audit Response - Halborn Audit 4

This document summarizes our response to Halborn's security audit of the VE Governance plugin conducted between September 24th and October 8th, 2025.

## Summary of Findings

| Issue  | Name                                                                       | Status       | Details                                                                                                                        |
| ------ | -------------------------------------------------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| HAL-01 | Incorrect Maturity Check Blocks Merging at Unlock Time                     | Acknowledged | [See detailed response below](#hal-01-detailed-response)                                                                       |
| HAL-02 | Retroactive Fee Parameter Changes Expose Users to Unexpected Charges       | Fixed        | [PR #180](https://github.com/aragon/ve-governance/pull/180)                                                                    |
| HAL-03 | minCooldown Can Be Zero Even When Early Exit is Disabled in Fixed Fee Mode | Fixed        | [PR #179](https://github.com/aragon/ve-governance/pull/179)                                                                    |
| HAL-04 | Maximum Fee Can Only Apply at Exact MinCooldown Due to Exit Restrictions   | Acknowledged | Harmless and doesn't require knowing rest of codebase                                                                          |
| HAL-05 | Missing Access Control in createLockFor() Function                         | Fixed        | [PR #178](https://github.com/aragon/ve-governance/pull/178)                                                                    |
| HAL-06 | Floating and Outdated Pragma                                               | Acknowledged | Need floating pragma as ve is used as dependency in lots of our builds                                                         |
| HAL-07 | Missing Zero Address Checks                                                | Acknowledged | These are set by the DAO and factories so the validation is the governance process                                             |
| HAL-08 | Missing Events                                                             | Acknowledged | ivotesadapter can't be set more than once, setEnableHook will typically never be changed, withdraw emits ERC20::Transfer event |

## HAL-01 Detailed Response

We evaluated the impact of changing the definition of maturity from strictly greater than the end of the lock to greater than or equal to. This revealed 2 things:

1. Switching to weak inequality has implications for the checkpointing functionality and would require additional changes in a sensitive function. We don't see the strong inequality as a fundamental logical error, more of a business preference, so we are happy to keep it.

2. Upon investigating the implications of the merge maturity we found an error with the existing withdrawal lock implementation that did not allow for the intended behaviour of restricting atomic lock creation and queueing withdrawal, while also allowing atomic merge/splits and beginning withdrawal.

We have implemented a fix for this in [PR #177](https://github.com/aragon/ve-governance/pull/177).

