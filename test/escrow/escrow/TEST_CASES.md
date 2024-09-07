- Check alternative escrow implementations like aero to see what they tested
- Explore the flash mint exploit
- Review common exploits with ERC721s
- Explore the issues with ownership changes
- Explore the issue of the mint-ish and burn-ish
- Consider removing the root checkpoint from the contract

- Test supports interface: erc721, plugin

- Think more about the warmup period.

  - We could check if startDate is in the future, this could affect the warmup
  - Warmup could also keep its own state for this purpose

- Test admin setters:

  - whitelisting
  - curve
  - voter
  - queue

- Review function visibility to make sure all are correct

- Add totalVoting power for user? Could be a separate utility contract

## Key workflows

Creating a lock:

- Test it mints an NFT with a new tokenId
- Test we can fetch the nft for the user
- Test the lock corresponds to the correct length
- Test that the first checkpoint is written to
- Test the value is correct
  - Test it can't be zero
- Thest the total locked in the contract increments correctly
- Test if we need to track supply changes or can remove the event

CreateLock time logic:

- Test that the create lock snaps to the nearest voting period start date

Creating a lock for someone:

- Test we can make a lock for someone else
- Test that someone can't be a smart contract unless whitelisted

Creating locks for multiple users:

- Test that we can query multiple locks
- Test that locks correctly track user balances

Upgrades:

- Test we can upgrade the escrow
- Test only the DAO or an authorised multisig can do so

NFT lifecycle:

- Transfers:
  - Test voting power resets on transfer
    - What about warmup, should this reset?
      - Intuitively, yes: a transfer should in essence be a burn/mint of the voting power
  - Test balance correctly updates
  - Ownership is reset on transfer
  - Check that you can't transfer without resetting voting power OR decide if you can actually
  - Can't transfer to contract
  - Can't transfer to nonreceiver
  - can't transfer if not approved or owner
- Ownership & approvals

  - Test we can grant approval (do as part of withdrawal)
  - Test we can grant ownership ("")

- Easily query the total voting power of a user
- Easily query the historic voting power of a user - can't be done

Withdrawals

- Can enter into the queue
- TBC: enter into the queue for someone else if you have permission
- Can't enter withdraw with pending votes
- The NFT is held by the contract
- Can't remove it after
- Checks the exit queue for eligibility
- Add a canWithdraw
- Can't withdraw someone else's token
- Withdrawal resets the locked balance and removes the checkpoint
-

Things that come up: - Test voting power resets on transfer - What about warmup, should this reset? - Intuitively, yes: a transfer should in essence be a burn/mint of the voting power - Test balance correctly updates - Check that you can't transfer without resetting voting power OR decide if you can

Explore some other options for auxilliary contracts:

- What if they revert?
- What about an exit queue that always lets you unlock (allowing atomic exits)?
- What about other voting cotnracts

- Pausing
