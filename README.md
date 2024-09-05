# Mode Governance Hub

# Contracts Overview

The primary contracts in the governance hub are found in the `src` directory. The key contracts include

- `VotingEscrowIncreasing.sol`: ERC721 veNFT designed to be used with escrow systems that reward users for longer lock times.
- `SimpleGaugeVoter.sol`: allows split voting across arbitrary options. Votes are simply registered in the gauge voter, they do not perform any onchain actions

The main workflow in the Mode Governance build is as follows:

## Escrow

- Users lock a whitelisted token into the Escrow Contract. For Mode they operate a 2-token model, where a user can either stake $MODE or a BPT-80-20-MODE-WETH token. The latter is an LP token representing the user's position in a Balancer 80/20 pool.
- The user is minted a veNFT which stores:
  - The amount they locked
  - The start of their lock
- The user's voting power increases quadratically over time, starting from a baseline of the locked amount, up to 6x voting power. This takes place over 5 consecutive epochs of 2 weeks.
- The user is unable to vote during an initial "warmup period" of 3 days.
- The user can exit their position at any time. In this case, they are entered into an "Exit Queue", whereupon their NFT is held in the queue for a "cooldown" period of X Days. After the period ends, they can burn the NFT to receieve their underlying balance back.
  - As the NFT is held by the queue, the user cannot vote during this time.

## Voting

- Administrators setup voting options on the `SimpleGaugeVoter.sol`, we call these `gauges`.
- Administrators can activate voting at which point a timestamp is recorded. `EpochDurationbLib` tracks 2 week epochs in single week blocks:
  - A Voting phase of 1 week, where votes are accepted.
  - A distribution phase of 1 week, where votes are not accepted (this is done in order to allow governance to compute and allocate rewards).
- Users can only vote once per epoch and votes don't reset by default. Users' NFTs are locked unless they `reset` their votes and remove their voting power.
- An autoreset function allows the DAO to (optionally) have votes reset in-between epochs.

## Rewards

- Rewards come in 2 flavours:
  1. Rewards to stakers who lock tokens in the voting escrow contract (we call these "staking rewards")
  2. Rewards distributed by the DAO based on votes in `SimpleGaugeVoter` (we call these "emissions")
- In this build, rewards are computed offchain and distributed to stakers and eligible protocols via Merkle Distributors or Batch Transactions. The important part is that we can track:
  - Voting power of a user at a point in time
  - Votes accumulating to each gauge
