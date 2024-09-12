# Aragon VE Governance Hub

# Contracts Overview

The primary contracts in the governance hub are found in the `src` directory. The key contracts include

- `VotingEscrowIncreasing.sol`: ERC721 veNFT designed to be used with escrow systems that reward users for longer lock times.
- `SimpleGaugeVoter.sol`: allows split voting across arbitrary options. Votes are simply registered in the gauge voter, they do not perform any onchain actions

The main workflow in the Mode Governance build is as follows:

## Escrow

- Users lock a whitelisted token into the Escrow Contract.
- The user is minted a veNFT which stores:
  - The amount they locked
  - The start of their lock - users begin their locks starting from the next deposit interval
    - In the base case, this means a user will start their lock from the start of the upcoming week
- The user's voting power increases over time, starting from a baseline of the locked amount, up to a maximum voting power
- The user is unable to vote during an initial "warmup period".
- The user can exit their position at any time. In this case, they are entered into an "Exit Queue", whereupon their NFT is held in the queue for a "cooldown" period of X Days. After the period ends, they can burn the NFT to receieve their underlying balance back.
  - Voting power is removed from the NFT at this time
- The exit queue can optionally set an exit fee that will be charged on exit.

## Voting

- Administrators setup voting options on the `SimpleGaugeVoter.sol`, we call these `gauges`.
- Administrators can activate voting at which point a timestamp is recorded. `EpochDurationbLib` tracks 2 week epochs in single week blocks:
  - A Voting phase (default is 1 week), where votes are accepted.
  - A distribution phase of (default is 1 week), where votes are not accepted (this is done in order to allow governance to compute and allocate rewards).
- Users can vote as much as they want during the voting period.
- Users' NFTs are locked unless they `reset` their votes and remove their voting power.

## Parameterization

- Various elements of these contracts can be parameterised in order to support different ve mechanisms. These include:

  - Custom exit queue logic via custom exit queue managers
  - Custom escrow curves
  - Custom voting contracts other than SimpleGaugeVoter
  - Custom epoch clock logic via the `Clock.sol` contract

- Additionally, we use libraries like `CurveCoefficientLib` and `SignedFixedPointMathLib` that allow users to make minimal, consistent and gas-efficient customisations to things like epoch length and curve shapes.

## Rewards

- The current versions of the contracts assume an offchain rewards distribution mechanism.

## Caveats

- This version of the repository defines user-based logic and initial framework for:
  - Voting Escrow Lockers w. veNFT functionality
  - Voting Escrow Curves
  - Exit Queues
- Rewards and emissions are assumed to be offchain
- veNFT transfers are disabled by default in the current implementation, but can be enabled. Fully supporting transfers would require support for allowing for custom transfer logic (resetting voting power) which is as yet not implemented.
- Delegation checkpointing is not yet implemented.
- Total supply is not yet implemented due to complexities in scheduling slope changes for higher order polynomials. We have setup a user-point system where this can be added in the future: please see the linked research below for details.

## Curve design

To build a flexible approach to curve design, we reviewed implementations such as seen in Curve and Aerodrome and attempted to generalise to higher order polynomials [Details on the curve design research can be found here](https://github.com/jordaniza/ve-explainer/blob/main/README.md)
