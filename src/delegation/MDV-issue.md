We have a grid of options for moving delegate votes

from to

undelegated undelegated
undelegated delegated
delegated undelegated
delegated delegated

We also can think about this modified for lifecycle
from to  
mint  
transfer
merge
split
beginWithdrawal
burn

Following are not possible or not interesting

| Lifecycle Event | From        | To          | NumDelegatedTokens | TokenDelegated | delegateFromChange | delegateToChange | Comments                         |
| --------------- | ----------- | ----------- | ------------------ | -------------- | ------------------ | ---------------- | -------------------------------- |
| beginWithdrawal | undelegated | delegated   |                    |                |                    |                  | Not possible, escrow is reciever |
| beginWithdrawal | delegated   | delegated   |                    |                |                    |                  | Not possible, escrow is reciever |
| mint            | delegated   | undelegated |                    |                |                    |                  | Not possible, mint not delegated |
| mint            | delegated   | delegated   |                    |                |                    |                  | Not possible, mint not delegated |
| burn            | undelegated | delegated   |                    |                |                    |                  | Not possible, burn not delegated |
| burn            | delegated   | delegated   |                    |                |                    |                  | Not possible, burn not delegated |
| self split      | undelegated | delegated   |                    |                |                    |                  | Not possible, self               |
| self split      | delegated   | undelegated |                    |                |                    |                  | Not possible, self               |
| self merge      | undelegated | delegated   |                    |                |                    |                  | Not possible, self               |
| self merge      | undelegated | delegated   |                    |                |                    |                  | Not possible, self               |
| transfer self   | undelegated | delegated   |                    |                |                    |                  | Not possible, self               |
| transfer self   | delegated   | undelegated |                    |                |                    |                  | Not possible, self               |
| mint            | undelegated | undelegated | 0                  | f              | 0                  | 0                |                                  |
| burn            | undelegated | undelegated | 0                  | f              | 0                  | 0                |                                  |
| transfer self   | undelegated | undelegated | 0                  | f              | 0                  | 0                |                                  |
| transfer other  | undelegated | undelegated | 0                  | f              | 0                  | 0                |                                  |
| approved merge  | undelegated | undelegated | 0                  | f              | 0                  | 0                |                                  |
| self merge      | undelegated | undelegated | 0                  | f              | 0                  | 0                |                                  |
| approved merge  | undelegated | undelegated | 0                  | f              | 0                  | 0                |                                  |
| beginWithdrawal | undelegated | undelegated | 0                  | f              | 0                  | 0                |                                  |
| self split      | undelegated | undelegated | 0                  | f              | 0                  | 0                |                                  |

Below events are interesting

| Lifecycle Event | From        | To          | NumDelegatedTokens | TokenDelegated | delegateFromChange | delegateToChange | Comments                                    |
| --------------- | ----------- | ----------- | ------------------ | -------------- | ------------------ | ---------------- | ------------------------------------------- |
| mint            | undelegated | delegated   | +1 to              | t              | 0                  | d                | Only case of mint where we care             |
| transfer self   | delegated   | delegated   | 0                  | t              | 0                  | 0                | Self transfer when delegated can be skipped |
| transfer other  | undelegated | delegated   | +1 to              | t              | 0                  | d                |                                             |
| transfer other  | delegated   | undelegated | -1 from            | f              | -d                 | 0                |                                             |
| transfer other  | delegated   | delegated   | -1 from / +1 to    | t              | -d                 | d                |                                             |
| self merge      | delegated   | delegated   | -1 from            | f\*            | 0                  | 0                | the burned token isn't delegated            |
| self split      | delegated   | delegated   | +1                 | t              | 0                  | 0                |                                             |
| approved merge  | undelegated | delegated   | 0 (no change)      | f              | 0                  | d                |                                             |
| approved merge  | delegated   | undelegated | -1 from            | f              | -d                 | 0                |                                             |
| approved merge  | delegated   | delegated   | -1 from            | f              | -d                 | d                |                                             |
| beginWithdrawal | delegated   | undelegated | -1 from            | f              | -d                 | 0                | End up same as burn                         |
| burn            | delegated   | undelegated | -1 from            | f              | -d                 | 0                | End up same as withdraw                     |

Ok so comment 1, if both delegates are 0 there is nothing to do in any case
the blocks need splitting into delegatesTo and delegatesFrom, that's really then only thing that matters

So first thing, we need to know if the delegatesTo and From are both zero, if so you can exit right now

we then have code blocks for if delegatesTo and delegatesFrom are each positive, which is what we have.

right so first comment:

- tokenIsDelegated is dependent ENTIRELY on the delegatesTo != 0
- transferSelf is the ONLY case where there the change in d is not entirely captured by delegatesTo and delgatesFrom
- so this leaves only the NumDelegatedTokens

This really is the complex one.

In the case of split, simply passing a mint w. locked.amount = 0 will have d=0 and therefore achieve split

| Lifecycle Event | From        | To        | NumDelegatedTokens | TokenDelegated | delegateFromChange | delegateToChange | Comments |
| --------------- | ----------- | --------- | ------------------ | -------------- | ------------------ | ---------------- | -------- |
| self split      | delegated   | delegated | +1 to              | t              | 0                  | 0                |          |
| mint            | undelegated | delegated | +1 to              | t              | 0                  | d                |          |

In the case of merge, self merge can be achieved w. the same, locked.amount = 0 on the burn. Here we can just skip the balance updates

| Lifecycle Event | From      | To          | NumDelegatedTokens | TokenDelegated | delegateFromChange | delegateToChange | Comments |
| --------------- | --------- | ----------- | ------------------ | -------------- | ------------------ | ---------------- | -------- |
| self merge      | delegated | delegated   | -1 from            | f              | 0                  | 0                |          |
| burn            | delegated | undelegated | -1 from            | f              | -d                 | 0                |          |

Approved merges, we have 3 cases

merging on behalf of someone else, where the recipient is undelegated = a straight burn of the delegate voting power

| Lifecycle Event | From      | To          | NumDelegatedTokens | TokenDelegated | delegateFromChange | delegateToChange | Comments |
| --------------- | --------- | ----------- | ------------------ | -------------- | ------------------ | ---------------- | -------- |
| approved merge  | delegated | undelegated | -1 from            | f              | -d                 | 0                |          |
| burn            | delegated | undelegated | -1 from            | f              | -d                 | 0                |          |

In the case of merging to a delegated recipient on behalf of someone else:

When merging,

- the recipient never gains tokenIsDelegated or numDelegatedTokens
- if the from is undelegated and the to is delegated, we only need to run the checkpoint function.
- if both are delegated, we need to run a burn from the first delegate, and the checkpoint only from the second

| Lifecycle Event | From        | To        | NumDelegatedTokens | TokenDelegated | delegateFromChange | delegateToChange | Comments |
| --------------- | ----------- | --------- | ------------------ | -------------- | ------------------ | ---------------- | -------- |
| approved merge  | undelegated | delegated | 0 (no change)      | f              | 0                  | d                |          |
| approved merge  | delegated   | delegated | -1 from            | f              | -d                 | d                |          |

How can we determine checkpoint only?

Option 1: pass it. We have all this written.

Option 2: infer it. We have a few options:

- we need the tokenId to be valid, can't use that as sentinel.
- Messing around w. the addresses tough. What if they are the same?
  - risky, we just use the checkpoint only

Recapping, what are our calls then:

| Lifecycle Event | From        | To          | NumDelegatedTokens | TokenDelegated | delegateFromChange | delegateToChange | Call                                          |
| --------------- | ----------- | ----------- | ------------------ | -------------- | ------------------ | ---------------- | --------------------------------------------- |
| mint            | undelegated | delegated   | +1 to              | t              | 0                  | d                | create lock from address O                    |
| transfer self   | delegated   | delegated   | 0                  | t              | 0                  | 0                | Don't call in lock.sol                        |
| transfer other  | undelegated | delegated   | +1 to              | t              | 0                  | d                | handledin lock.sol                            |
| transfer other  | delegated   | undelegated | -1 from            | f              | -d                 | 0                | default to not skipping cps                   |
| transfer other  | delegated   | delegated   | -1 from / +1 to    | t              | -d                 | d                | default to not skipping cps                   |
| self merge      | delegated   | delegated   | -1 from            | f\*            | 0                  | 0                | the burned token isn't delegated              |
| self split      | delegated   | delegated   | +1                 | t              | 0                  | 0                |                                               |
| approved merge  | undelegated | delegated   | 0 (no change)      | f              | 0                  | d                |                                               |
| approved merge  | delegated   | undelegated | -1 from            | f              | -d                 | 0                |                                               |
| approved merge  | delegated   | delegated   | -1 from            | f              | -d                 | d                |                                               |
| beginWithdrawal | delegated   | undelegated | -1 from            | f              | -d                 | 0                | End up same as burn or transfer non delegated |
| burn            | delegated   | undelegated | -1 from            | f              | -d                 | 0                | End up same as withdraw                       |
