# IVotingEscrowCoreEvents
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol)


## Events
### MinDepositSet

```solidity
event MinDepositSet(uint256 minDeposit);
```

### Deposit

```solidity
event Deposit(
    address indexed depositor, uint256 indexed tokenId, uint256 indexed startTs, uint256 value, uint256 newTotalLocked
);
```

### Withdraw

```solidity
event Withdraw(address indexed depositor, uint256 indexed tokenId, uint256 value, uint256 ts, uint256 newTotalLocked);
```

