# VotingEscrowIncreasing_v1_2_0.sol Specification

## Summary

The VotingEscrowIncreasing_v1_2_0 contract is the central component of the VE system, implementing a voting escrow where users lock ERC20 tokens to receive NFTs representing time-weighted voting power. All other contracts route through the escrow, except for the Clock (provides timing) and the IVotesAdapter (used directly by AddressGaugeVoter for delegation). This version adds delegation support while maintaining the core lock-and-vote mechanism with merge/split functionality.

## Mechanism Explanation

### Core Escrow Mechanism

Users deposit ERC20 tokens into the contract and receive an NFT that represents their locked position. Key characteristics:

- **Lock Creation**: Tokens are locked starting at the current week checkpoint (backdated to previous Thursday UTC)
- **Voting Power**: Calculated by an external curve contract based on amount locked and time elapsed
- **NFT Representation**: Each lock is an ERC721 token enabling composability and transferability
- **No Lock Extension**: Unlike traditional ve systems, locks cannot be extended - only merged or split

### Merge and Split Operations

- **Merge**: Combine two NFTs into one, summing their locked amounts (requires same start time or maturity)
- **Split**: Divide one NFT into two smaller positions (restricted to whitelisted addresses by default)
- **Constraints**: Both operations maintain minimum deposit requirements and update delegation state

### Exit Mechanism

- **Queue System**: Withdrawals go through an exit queue with configurable cooldown period
- **Fee Structure**: Exit fees can be collected based on queue configuration (standard queue has fixed fee, dynamic queue has variable fees)
- **No Voting Check**: In older versions, could not exit while voting. Now this process is gracefully handled by the updateVotingPowerHook so is no longer needed.

### Delegation Integration (v1.2.0)

- **IVotes Adapter**: External adapter contract manages delegation logic
- **Automatic Updates**: Token transfers trigger delegation updates
- **Voting Power Sync**: Delegation changes update voting power in gauge voter

## Key Interface Functions

```solidity
interface IVotingEscrowIncreasingV1_2_0 {
  // Core Data Structure
  struct LockedBalance {
    uint208 amount; // Amount of tokens locked
    uint48 start; // Start timestamp of the lock
  }

  // Core Lock Management
  /// @notice Create a new lock for the caller
  function createLock(uint256 _value) external;

  /// @notice Create a lock on behalf of another address
  function createLockFor(uint256 _value, address _to) external;

  /// @notice Merge two NFTs into one
  function merge(uint256 _from, uint256 _to) external;

  /// @notice Split an NFT into two positions
  function split(uint256 _from, uint256 _value) external;

  // Exit Functions
  /// @notice Begin withdrawal process by queuing exit
  function beginWithdrawal(uint256 _tokenId) external;

  /// @notice Complete withdrawal after queue period
  function withdraw(uint256 _tokenId) external;

  // Essential View Functions
  /// @notice Get current voting power of an NFT
  function votingPower(uint256 _tokenId) external view returns (uint256);

  /// @notice Get total voting power for an account - aggregates across NFTs
  function votingPowerForAccount(
    address _account
  ) external view returns (uint256);

  /// @notice Get locked balance for an NFT
  function locked(
    uint256 _tokenId
  ) external view returns (LockedBalance memory);

  /// @notice Check if NFT is actively voting
  /// @dev not possible when using AddressGaugeVoter
  function isVoting(uint256 _tokenId) external view returns (bool);

  // Delegation Hooks (called by other contracts)
  /// @notice Called by lockNFT on transfers
  function moveDelegateVotes(
    address _from,
    address _to,
    uint256 _tokenId,
    LockedBalance memory _locked
  ) external;

  /// @notice Called by ivotesAdapter to update voting power
  function updateVotingPower(address _from, address _to) external;

  // Key Events
  event LockCreated(
    address indexed account,
    uint256 indexed tokenId,
    uint256 value
  );
  event Withdrawn(
    address indexed account,
    uint256 indexed tokenId,
    uint256 value
  );
  event Merged(
    address indexed account,
    uint256 indexed from,
    uint256 indexed to,
    uint256 value
  );
  event Splitted(
    address indexed account,
    uint256 indexed from,
    uint256 indexed to,
    uint256 value
  );

  // Key Errors
  error MinDepositNotMet();
  error NotApprovedOrOwner();
  error AlreadyVoted();
  error NotMergeable();
  error NotWhitelistedForSplit();
}
```

## Caveats

- **Token Decimals**: Only supports 18-decimal ERC20 tokens
- **No Lock Extension**: Unlike traditional ve models, locks cannot be extended - only merged
- **Split Restrictions**: Splitting requires whitelist by default to prevent fractional exits. There is less at stake if the user can partially exit the position.
- **Minimum Deposits**: Both initial deposits and split results must never allow for veNFTs with lock.amount below the minDeposit. Such deposits are set to prevent griefing attacks by sending dust NFTs to large holders, making aggregation prohibitively expensive.
- **Start Time**: Locks start at the previous week checkpoint, not the actual deposit time
- **Delegation Complexity**: Token transfers update delegation state through multiple contract calls
- **Exit Queue**: Withdrawals subject to queue cooldown and potential fees
- **Merge Constraints**: Can only merge tokens with same start time or if both are mature - this is due
