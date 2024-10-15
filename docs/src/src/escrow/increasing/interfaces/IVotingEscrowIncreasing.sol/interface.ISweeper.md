# ISweeper
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol)

**Inherits:**
[ISweeperEvents](/src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol/interface.ISweeperEvents.md), [ISweeperErrors](/src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol/interface.ISweeperErrors.md)


## Functions
### sweep

sweeps excess tokens from the contract to a designated address


```solidity
function sweep() external;
```

### sweepNFT


```solidity
function sweepNFT(uint256 _tokenId, address _to) external;
```

