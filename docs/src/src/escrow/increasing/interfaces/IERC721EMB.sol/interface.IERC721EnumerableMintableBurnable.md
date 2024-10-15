# IERC721EnumerableMintableBurnable
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/IERC721EMB.sol)

**Inherits:**
IERC721Enumerable


## Functions
### mint


```solidity
function mint(address to, uint256 tokenId) external;
```

### burn


```solidity
function burn(uint256 tokenId) external;
```

### isApprovedOrOwner


```solidity
function isApprovedOrOwner(address spender, uint256 tokenId) external view returns (bool);
```

