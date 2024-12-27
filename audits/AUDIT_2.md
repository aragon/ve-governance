Aragon's first version of ve governance underwent 2 audits by Halborn and Blocksec, as well as an internal review by senior engineering in Aragon. The findings, changelog and associated PRs are included in the document below.

1. [Summary of Changes](#summary-of-changes)
2. [Audit Notes](#notes-from-the-halborn-audit)

# Summary of changes

The changes in the second audit are a relatively small set of contract changes. Overall there are 2 things we are looking to address:

1. Faciliate the migration from old to new staking contract, to reset the state.

For DAOs wishing to start new governance 'seasons', there is a requirement for voting power to be reset. The changes to the Voting Escrow contract are intended to reflect this:

- A new set of contracts will be deployed
- Direct migration will be enabled between the old and new contracts
- Existing stakers should be able to migrate in a single transaction, skipping the exit queue mechanics
- Existing stakers can migrate even if the destination staking contract is locked for new stakers, this gives existing stakers a window to migrate and gain voting power ahead of new entrants.

2. Add small improvements, these are detailed in the following contracts

- a: lock, add NFT metadata URI
- b: voting contract: permit resets outside of voting windows so users can unstake more easily
- c: move from a quadratic -> linear voting curve

## Additional changes surfaced during the audit

1. Add versioning to the Smart contracts with changed behaviours, to improve traceability

- `VotingEscrowIncreasing` -> `VotingEscrowIncreasing1_1_0`
- `SimpleGaugeVoter` -> `SimpleGaugeVoter1_1_0`

2. Add a snapshot of the voting power inside the `Migrate` event

3. Add `nonReentrant` to the `migrateFrom` function

# Notes from the Halborn Audit

https://www.halborn.com/portal/reports/ve-governance-updates

## Addressed Issues

Below issues were addressed in [PR 43](https://github.com/aragon/ve-governance/pull/43)

| Severity | Issue                                       | Comment                            |
| -------- | ------------------------------------------- | ---------------------------------- |
| L        | (HAL-01) Deposits allowed during migration  | Disabled deposits during migration |
| I        | (HAL-04) Ordering for nonReentrant modifier | Changed order in Lock.sol          |
| I        | (HAL-05) Typos                              |                                    |

## Acknowledged Issues

| Severity | Issue                                                     | Comment                                                                                                                                                                                                                                                     |
| -------- | --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| L        | (HAL-03) Potential Lockup after `sweepNFT`                | As the NFT is non transferrable, by default the DAO needs to also authorise a transfer before the NFT can be sent back to the address via sweep. We assume the DAO will check the address is capable of interacting with the NFT during this authorisation. |
| I        | (HAL-06) Floating pragma                                  | Fixed pragma can cause difficulties integrating with external codebases. We prefer to use floating.                                                                                                                                                         |
| I        | (HAL-02) POSSIBLE STORAGE COLLISIONS IN CONTRACT UPGRADES | Discussed the storage collisions with Halborn team and, on review, confirmed the storage layout is consistent with the v1 of the contracts. New changes don't implement any unexpected increases.                                                           |
