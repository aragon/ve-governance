# Simplifying gauge voting

We already have a simplified voting interface and, and this point, we are pitching signalling.

We also already have the notion of signalling votes.

the difference in gauge systems to proposal-based voting is that gauges accumulate votes over time, proposals are for something specific.

Consequently, the notion of matching Actions to gauges doesn't totally make sense.
Probaably the most future proof way to build this is

gauge id, metadata, tbc onchain data handled via a mapping to storage, your gauge then is decoupled from needing to be an ddress, this can be just the metadata (off chain) or additional data (onchain), which for now can just be bytes memory.

We DO need epoch-based voting, so quite frankly most of the code can stay.

## Test cases

Init:

- Remove the relative timestamps for now and log it as a point of discussion
- Consider whether to remove the reset functionality
- The currentEpoch is a bit weird, because it starts from genesis it probably needs a better name

- Test initilization variables
- Test upgrades

Gauge management:

- Change to gauge ids, metadata and onchain data.
- For now the onchain data will simply be the metadata
- consider adding a version to the schema that allows for a flexible change to the gauge state as we move forward.
- We could easily add resets - this is not a huge priority rn

# Voting

- Test the onlyNewEpoch modifer - what do we want it to do?
- Add the option to vote with >1 tokenIds even if that's just a loop
- should we use votingPower at epoch start?

- condendse the voting active logic to a simple function
- can't vote for gauge that doesn't exit or gaguge that's deactivated
- can't vote with zero votes on a gauge
- can't hack to vote with effective zero votes due to rounding
- votes can't exceed max voting power
- Events are emit as expected f
-

Voting:

- only vote when voting is active
- only vote with tokens you own
-

- multiple votes resets voting power
- multiple voters calcs correctly
