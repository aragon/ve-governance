# Delegation Specification

The escrow contract implements different type of operations for ERC721 tokens such as:
* createLock
* merge
* split
* withdraw
* transfer

Upon each operation, it becomes important to update delegatee's balances on `EscrowIVotesAdapter` to ensure that their voting powers that they use on the `AddressGaugeVoter` are correctly reflected. Hence, It's crucial to safely update delegatees's voting powers. We define the following specifications(i.e rules) of how this should work.

**IMPORTANT:** The following assumptions and current code implementation are based on the following important facts:
* The user can only merge the token if he owns both of the tokens.
* Transfer can 


### Split

The `split` function allows a user to divide an existing token into two tokens:
* `fromTokenId`: the original token with reduced balance
* `toTokenId`: a newly minted token with the split-off balance

These names (`fromTokenId`, `toTokenId`) are used for consistency with the `merge` function. The rules we follow are as such:

* If `fromTokenId` is NOT delegataed:
    * Do nothing even if sender already has a delegatee set. This ensures to avoid extra gas costs as sender might not yet want to automatically delegate these tokens.
* If `fromTokenId` is delegated:
    * Automatically delegate `toTokenId`, increase the number of delegated counts by 1 on the sender. 
    >  If `x` is split into `x` and `y`, and `x` is delegated,
       then automatically delegate `y` as well. This is to ensure that
       later on, delegating `y` manually will revert, otherwise it would
       cause votes to be double spent as original `x` that was delegated
       already included the amount of `y`. 

### Merge

> Note that the current implementation of escrow allows to merge tokens only if sender is the owner of both tokens. If this assumption needs to change, care must be taken for `mergeDelegateVotes` function to ensure it correctly reflects different delegatees after the merge.

The `merge` function allows one token to be merged into another token. This causes `fromTokenId`'s amount to be included/merged into `toTokenId`'s amount. The rules we follow are as such:

* If `fromTokenId` is NOT delegated, but:
    * `toTokenId` is delegated:
        * Update the checkpoint for the delegatee with addition of `fromTokenId`'s amount. This should not cause the events to be emitted as after this operation, `fromTokenId` must become undelegated(which was the case initially) and `toTokenId` being delegated(which also was the case).
    * `toTokenId` is NOT delegated:
        * Do nothing.
* If `_fromTokenId` is delegated, but:
    * `toTokenId` is delegated:
        * Set the status of `fromTokenId` as undelegated and reduce the delegated token's count on sender. Note that checkpoints do NOT need to be updated as before the merge was called, both these tokens were delegated to the same delegatee which already included both these token's amounts in the checkpoint. 
    * `toTokenId` is NOT delegated:
        * Set the status of `fromTokenId` as undelegated and `toTokenId` as delegated and add the `toTokenId`'s amount in the checkpoint. This is crucial as after the merge, user can manually delegate `toTokenId` which's vp at the time will include the total amount after the merge that would cause double-spend.

### Transfer

Transfer function allows users to transfer their tokens to others. The rules are quite simple on this. 

When the `tokenId` is transfered from `from` to `to`:

* (1) Check `from`'s delegatee address.
* (2) Check `to`'s delegatee address.

As long as (1) and (2) are not equal:

* If `tokenId` was delegated, remove its amount from the checkpoint of `from`'s delegatee, reduce the number of delegated tokens count by 1 and emit the `TokenUndelegated` event.
* If `to`'s delegatee addres is set, automatically delegate `tokenId` to that address with updating the checkpoints and increasing the number of delegated tokens count on `to`'s address with an event emitted as `TokenDelegated`.

### Withdraw

The `beginWithdraw` function uses a `transfer` mechanism that transfers `tokenId` from the user to escrow contract. Since this is still a transfer, the same rules apply as we explained in `Transfer`, with a deterministic assumption that `to`'s delegatee address will be `address(0)`.
