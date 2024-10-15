# Aragon veGovernance

Welcome to an (early) version of the technical documentation for Aragon's veGovernance system. This guide is primarily intended as a reference for external developers looking to integrate with our ve contracts.

> This is a preview docs build that we hope is helpful but we don't guarantee to be fully up to date or free of typos or issues, if you have an questions please reach out to [the Aragon team](mailto:jordan@aragon.org)

## Quick start

- For voting power, querying underlying balances, depositing or withdrawing - start at the Voting Escrow contract.
- For gauge voting, start at the gauge voter contract
- For inspecting the dynamic voting power tracking, as well as warmups, see the Curve contract
- For checking protocol time, start at the Clock contract
- For checking if a user canExit or not, as well as min locks and cooldowns, check the Exit Queue contract
- For approving NFT locks, check out the Lock contract.

## Contracts Overview

Contracts are built on Aragon OSx and assume an Aragon DAO is the owner of the permissions system.

| Contract      | Dir                                                                                                                                                | Description                                                                                                                                              |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Voting Escrow | [src/escrow/increasing/VotingEscrowIncreasing.sol](src/escrow/increasing/VotingEscrowIncreasing.sol/contract.VotingEscrow.html)                    | Main Staking contract for the tokens. In most cases you will be calling this contract for staking data and computing voting power.                       |
| Gauge Voter   | [src/voting/SimpleGaugeVoter.sol](src/voting/SimpleGaugeVoter.sol/contract.SimpleGaugeVoter.html)                                                  | Gauge Voting Contract that users will cast votes against when voting for emissions. In most cases you will be calling this data for checking gauge data. |
| Escrow Curve  | [src/escrow/increasing/QuadraticIncreasingEscrow.sol](src/escrow/increasing/QuadraticIncreasingEscrow.sol/contract.QuadraticIncreasingEscrow.html) | Contains Logic for calculating voting power change over time and stores checkpoint data                                                                  |
| Exit Queue    | [src/escrow/increasing/ExitQueue.sol](src/escrow/increasing/ExitQueue.sol/contract.ExitQueue/html)                                                 | Controls cooldowns, min locks and exit mechanisms for those looking to unstake.                                                                          |
| Clock         | [src/clock/Clock.sol](src/clock/Clock.sol/contract.Clock.html)                                                                                     | Unified contract that tracks epochs, checkpoint intervals and voting windows.                                                                            |
| veNFT Lock    | [src/escrow/increasing/Lock.sol](src/escrow/increasing/Lock.sol/contract.Lock.html)                                                                | ERC721 Representation of a staking position.                                                                                                             |

## Escrow

- Users lock a whitelisted token into the Escrow Contract.
- The user is minted a veNFT which stores:
  - The amount they locked
  - The start of their lock - users begin their locks starting from the next deposit interval
    - In the base case, this means a user will start their lock from the start of the upcoming week
- The user's voting power increases over time, starting from a baseline of the locked amount, up to a maximum voting power
- The user is unable to vote during an initial "warmup period".
- The user can exit their position at any time. In this case, they are entered into an "Exit Queue", whereupon their NFT is held in the queue for a "cooldown" period of X Days. After the period ends, they can burn the NFT to receieve their underlying balance back.
- It's possible to add a `minLock` period whereby a user is prevented from entering the exit queue before a certain time. This means they have their NFT available to vote but can't enter the exit process.
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

## Understanding Parameters

The Aragon veGovernance system has several parameters. Understanding them is key for the governance process

_These are the most important parameters for the staking and unstaking process_

| Category           | Name             | Description                                                                                                                                                                                                | Considerations                                                                                                                                                                                                                                                            | Example               |
| ------------------ | ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------- |
| Voting Power Curve | Max Multiplier   | Maximum boost on initial deposit that will be reached if a user leaves staked tokens in indefinitely                                                                                                       | - Too large can lock out small holders or allow minority stakes to become majority<br>- Too small is not enough of an incentive                                                                                                                                           | 5x                    |
| Voting Power Curve | Max Duration     | The time it takes to reach the max multiplier                                                                                                                                                              | - Too fast can remove the incentive to keep holding and/or make governance unstable<br>- Too slow removes the incentive to lock in the first place                                                                                                                        | 4 years               |
| Voting Power Curve | Warmup Period    | Time after locking in which a user can vote                                                                                                                                                                | - Too slow can eat into voting windows<br>- Too fast (i.e. zero or a few seconds) can allow for timing attacks or timestamp manipulation                                                                                                                                  | 24 hours              |
| ERC721             | Name             | For the Lock NFT                                                                                                                                                                                           |                                                                                                                                                                                                                                                                           | Voting Escrow MyToken |
| ERC721             | Symbol           | For the Lock NFT                                                                                                                                                                                           |                                                                                                                                                                                                                                                                           | veMYTOKENE            |
| Exit Queue         | Cooldown         | Cooldown is the period between the user entering the exit queue and being able to withdraw the underlying tokens. They do not have voting power at this time as their NFT is held in the staking contract. | Cooldowns can be useful to prevent users voting oppprtunisitically then exiting before the market has time to price the consequences in. As the user no longer has the NFT at this stage, they cannot partake in voting. Too long of a cooldown might create backlash. be | 14 days               |
| Exit Queue         | Min Lock         | Min amount of time a staker must hold before they can begin the exit process                                                                                                                               | The user still has voting power while in the min lock, so this is effectively a global minimum commitment for a given staker.                                                                                                                                             | 2 Months              |
| Exit Queue         | Exit Fee Percent | Tax paid in the underlying token on exit                                                                                                                                                                   |                                                                                                                                                                                                                                                                           | 1%                    |
| Escrow             | Minimum Deposit  | Number of tokens a user must deposit as a minimum                                                                                                                                                          | Small deposits risk “dust attacks” where whales can be griefed by sending very small locks to their wallet, making transactions that aggregate across voting power expensive. This can be configured by the DAO over time                                                 | 10 MYTOKEN            |

## Clock Parameters

The `Clock.sol` contract comes with a default set of parameters. We recommend these are kept as is unless there is good reason.

| Category | Name                            | Description                                                                                                                                                                     | Considerations                                                                                                          | Example |
| -------- | ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ------- |
|          | Epoch Duration                  | An epoch comprises a _Voting Period_ and a _Distribution Period_ and is considered some single interval over which a DAO conducts gauge voting + operational work for emissions | - Very short epochs create administrative overhead<br>- Very long epochs might create apathy                            | 2 Weeks |
|          | Voting Period Duration          | Time inside the full epoch when voting is active                                                                                                                                |                                                                                                                         | 1 Week  |
|          | Distribution Period Duration    | Time when voting is disabled in order to allow the team to do anything needed for voting-related activities                                                                     | - Typically this might involve whitelisting new protocols for rounds of voting, or preparing and distributing emissions | 1 Week  |
|          | Voting Period Warmup & Cooldown | Delay voting starting and ending by a short while to prevent timing attacks                                                                                                     | - More relevant with onchain voting systems with onchain execution                                                      | 1 Hour  |
|          | Checkpoint Intervals            | Changes to voting power all take effect at the same time at each interval - this is to ensure we can have a total view of voting power at start of each week                    | - Technical limitation of Solidity: Recommend leaving this to 1 week                                                    | 1 Week  |
