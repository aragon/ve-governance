# Notes for the auditors for the second audit

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
