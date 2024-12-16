Tests can be grouped into the following:

## Setup:

- Test the upgrade of the contract from the prior to the current version
- Test this on a fork connected to the current contracts

## Logic: stateless

- Test the migration works in isolation on the source contract in the base case
- Test the migration works in isolation on the destination contract
- Test together in the base case

## Logic: stateful

- Ensure the logic between contracts holds in the source with:
  - Prior deposits
  - Prior exit queue
  - New deposits
  - New exit queue

## E2E

- Write the fork test to migrate at a block snapshot including
  - Upgrading the contracts via a multisig proposal
  - Migrating all users including those in the queue
  - Should empty the total locked
