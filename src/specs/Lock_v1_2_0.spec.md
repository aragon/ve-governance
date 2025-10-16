# Lock_v1_2_0.sol Specification

## Summary

The Lock_v1_2_0 contract is an ERC721 NFT that represents locked positions in the voting escrow system. It provides controlled transferability through a whitelist mechanism and integrates with the delegation system by calling back to the escrow contract on transfers to update voting power delegation.

## Mechanism Explanation

The Lock NFT serves multiple purposes:

### NFT Representation

- Each locked position in VotingEscrow is represented by a unique NFT
- Token IDs correspond directly to lock IDs in the escrow contract
- Provides standard ERC721 functionality with enumeration support

### Transfer Control

- **Default Restriction**: Transfers are disabled by default
- **Whitelist System**: Addresses must be whitelisted to participate in transfers (both sending to and receiving from)
- **Global Enable**: Can enable transfers to any address via WHITELIST_ANY_ADDRESS
- **Escrow Always Whitelisted**: The escrow contract is permanently whitelisted for withdrawals

### Delegation Integration (v1.2.0)

- **Transfer Hook**: On every transfer, calls `moveDelegateVotes` on the escrow contract
- **Voting Power Update**: Ensures delegated voting power moves with NFT ownership
- **Self-transfer Check**: Skips delegation update if from and to are the same

## Key Interface Functions

```solidity
interface ILockV1_2_0 {
  // Constants
  address constant WHITELIST_ANY_ADDRESS =
    address(uint160(uint256(keccak256("WHITELIST_ANY_ADDRESS"))));
  bytes32 constant LOCK_ADMIN_ROLE = keccak256("LOCK_ADMIN");

  // Events
  event WhitelistSet(address indexed account, bool isWhitelisted);

  // Errors
  error OnlyEscrow();
  error NotWhitelisted();
  error ForbiddenWhitelistAddress();

  // Core Whitelist Management
  /// @notice Set whitelist status for an address
  /// @param _account Address to configure
  /// @param _isWhitelisted Whether address can participate in transfers
  function setWhitelisted(address _account, bool _isWhitelisted) external;

  /// @notice Enable transfers to any address globally
  function enableTransfers() external;

  // Escrow-Only Operations
  /// @notice Mint a new NFT (only escrow)
  /// @param _to Recipient address
  /// @param _tokenId Token ID to mint
  function mint(address _to, uint256 _tokenId) external;

  /// @notice Burn an NFT (only escrow)
  /// @param _tokenId Token ID to burn
  function burn(uint256 _tokenId) external;

  // Key View Functions
  /// @notice Check if address is whitelisted for transfers
  function whitelisted(address account) external view returns (bool);

  /// @notice Check if address is approved or owner
  function isApprovedOrOwner(
    address _spender,
    uint256 _tokenId
  ) external view returns (bool);

  // Standard ERC721 Transfer (with delegation hook)
  /// @notice Transfer NFT with delegation update
  function transferFrom(address from, address to, uint256 tokenId) external;
}
```

## Caveats

- **Transfer Restrictions**: By default, only whitelisted addresses can send or receive NFTs
- **Escrow Privilege**: The escrow contract cannot be removed from whitelist
- **Delegation Side Effects**: Every transfer may trigger a delegation update in the escrow (only if delegatees differ)
- **Reentrancy Protection**: Mint and burn are protected against reentrancy
- **Safe Minting**: Uses safe mint to ensure contract recipients can handle NFTs
- **Whitelist Any Address**: Global transfers can be toggled on/off by calling setWhitelisted(WHITELIST_ANY_ADDRESS, true/false)
