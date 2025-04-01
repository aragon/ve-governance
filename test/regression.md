Here, we detail some of the regression tests we want to run.

First some ideas, then we move on to what we want to cover.

- Take an existing DAO and upgrade to the new curve.

  - Check that the token points return the same data from a pure view perspective
  - Check that the votingPowerAt returns the same value both before and after
  - Check the locked.amount and start are unaffected for the existing locks
  - Check the same for the exit queus

- Fork an existing DAO and check and existing lock in each of the states

- We are changing the lock.start behavior - break the contract by having a lock.start from an old lock in the future
- Same for the exiting process - IIRC we are changing how the CP works between the old and new process

Note: define a diff between the Escrow, Curve and Queue. Do an itemised series of tests based on line-by-line changes.

- Build the unit test suite for the curve. Check warmups.
- Unit test the new clock function

- For any function that is a public view or event, check that it's data isn't changing.
