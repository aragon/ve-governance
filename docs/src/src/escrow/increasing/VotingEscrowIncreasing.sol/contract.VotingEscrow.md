# VotingEscrow
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/VotingEscrowIncreasing.sol)

**Inherits:**
IVotingEscrow, ReentrancyGuard, Pausable, DaoAuthorizable, UUPSUpgradeable

SPDX-License-Identifier: MIT


## State Variables
### ESCROW_ADMIN_ROLE
Role required to manage the Escrow curve, this typically will be the DAO


```solidity
bytes32 public constant ESCROW_ADMIN_ROLE = keccak256("ESCROW_ADMIN");
```


### PAUSER_ROLE
Role required to pause the contract - can be given to emergency contracts


```solidity
bytes32 public constant PAUSER_ROLE = keccak256("PAUSER");
```


### SWEEPER_ROLE
Role required to withdraw underlying tokens from the contract


```solidity
bytes32 public constant SWEEPER_ROLE = keccak256("SWEEPER");
```


### decimals
Decimals of the voting power


```solidity
uint8 public constant decimals = 18;
```


### minDeposit
Minimum deposit amount


```solidity
uint256 public minDeposit;
```


### lastLockId
Auto-incrementing ID for the most recently created lock, does not decrease on withdrawal


```solidity
uint256 public lastLockId;
```


### totalLocked
Total supply of underlying tokens deposited in the contract


```solidity
uint256 public totalLocked;
```


### _locked
*tracks the locked balance of each NFT*


```solidity
mapping(uint256 => LockedBalance) private _locked;
```


### token
Address of the underying ERC20 token.

*Only tokens with 18 decimals and no transfer fees are supported*


```solidity
address public token;
```


### voter
Address of the gauge voting contract.

*We need to ensure votes are not left in this contract before allowing positing changes*


```solidity
address public voter;
```


### curve
Address of the voting Escrow Curve contract that will calculate the voting power


```solidity
address public curve;
```


### queue
Address of the contract that manages exit queue logic for withdrawals


```solidity
address public queue;
```


### clock
Address of the clock contract that manages epoch and voting periods


```solidity
address public clock;
```


### lockNFT
Address of the NFT contract that is the lock


```solidity
address public lockNFT;
```


### _lockNFTSet

```solidity
bool private _lockNFTSet;
```


### __gap
*Reserved storage space to allow for layout changes in the future.*


```solidity
uint256[39] private __gap;
```


## Functions
### constructor


```solidity
constructor();
```

### initialize


```solidity
function initialize(address _token, address _dao, address _clock, uint256 _initialMinDeposit) external initializer;
```

### setCurve

Sets the curve contract that calculates the voting power


```solidity
function setCurve(address _curve) external auth(ESCROW_ADMIN_ROLE);
```

### setVoter

Sets the voter contract that tracks votes


```solidity
function setVoter(address _voter) external auth(ESCROW_ADMIN_ROLE);
```

### setQueue

Sets the exit queue contract that manages withdrawal eligibility


```solidity
function setQueue(address _queue) external auth(ESCROW_ADMIN_ROLE);
```

### setClock

Sets the clock contract that manages epoch and voting periods


```solidity
function setClock(address _clock) external auth(ESCROW_ADMIN_ROLE);
```

### setLockNFT

Sets the NFT contract that is the lock

*By default this can only be set once due to the high risk of changing the lock
and having the ability to steal user funds.*


```solidity
function setLockNFT(address _nft) external auth(ESCROW_ADMIN_ROLE);
```

### pause


```solidity
function pause() external auth(PAUSER_ROLE);
```

### unpause


```solidity
function unpause() external auth(PAUSER_ROLE);
```

### setMinDeposit


```solidity
function setMinDeposit(uint256 _minDeposit) external auth(ESCROW_ADMIN_ROLE);
```

### isApprovedOrOwner


```solidity
function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool);
```

### ownedTokens

Fetch all NFTs owned by an address by leveraging the ERC721Enumerable interface


```solidity
function ownedTokens(address _owner) public view returns (uint256[] memory tokenIds);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_owner`|`address`|Address to query|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokenIds`|`uint256[]`|Array of token IDs owned by the address|


### votingPower


```solidity
function votingPower(uint256 _tokenId) public view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The voting power of the NFT at the current block|


### votingPowerAt


```solidity
function votingPowerAt(uint256 _tokenId, uint256 _t) public view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The voting power of the NFT at a specific timestamp|


### totalVotingPower

*Currently unsupported*


```solidity
function totalVotingPower() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The total voting power at the current block|


### totalVotingPowerAt

*Currently unsupported*


```solidity
function totalVotingPowerAt(uint256 _timestamp) public view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The total voting power at a specific timestamp|


### locked


```solidity
function locked(uint256 _tokenId) external view returns (LockedBalance memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`LockedBalance`|The details of the underlying lock for a given veNFT|


### votingPowerForAccount

*We cannot do historic voting power at this time because we don't current track
histories of token transfers.*


```solidity
function votingPowerForAccount(address _account) external view returns (uint256 accountVotingPower);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`accountVotingPower`|`uint256`|The voting power of an account at the current block|


### isVoting

Checks if the NFT is currently voting. We require the user to reset their votes if so.


```solidity
function isVoting(uint256 _tokenId) public view returns (bool);
```

### createLock


```solidity
function createLock(uint256 _value) external nonReentrant whenNotPaused returns (uint256);
```

### createLockFor

Creates a lock on behalf of someone else. Restricted by default.


```solidity
function createLockFor(uint256 _value, address _to) external nonReentrant whenNotPaused returns (uint256);
```

### _createLockFor

*Deposit `_value` tokens for `_to` starting at next deposit interval*


```solidity
function _createLockFor(uint256 _value, address _to) internal returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_value`|`uint256`|Amount to deposit|
|`_to`|`address`|Address to deposit|


### _checkpoint

Record per-user data to checkpoints. Used by VotingEscrow system.

*Old locked balance is unused in the increasing case, at least in this implementation*


```solidity
function _checkpoint(uint256 _tokenId, LockedBalance memory _newLocked) private;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokenId`|`uint256`|NFT token ID|
|`_newLocked`|`LockedBalance`|New locked amount / start lock time for the user|


### _checkpointClear

*resets the voting power for a given tokenId. Checkpoint is written to the end of the epoch.*

*We don't need to fetch the old locked balance as it's not used in this implementation*


```solidity
function _checkpointClear(uint256 _tokenId) private;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokenId`|`uint256`|The tokenId to reset the voting power for|


### resetVotesAndBeginWithdrawal

Resets the votes and begins the withdrawal process for a given tokenId

*Convenience function, the user must have authorized this contract to act on their behalf.*


```solidity
function resetVotesAndBeginWithdrawal(uint256 _tokenId) external whenNotPaused;
```

### beginWithdrawal

Enters a tokenId into the withdrawal queue by transferring to this contract and creating a ticket.

*The user must not have active votes in the voter contract.*


```solidity
function beginWithdrawal(uint256 _tokenId) public nonReentrant whenNotPaused;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokenId`|`uint256`|The tokenId to begin withdrawal for. Will be transferred to this contract before burning.|


### withdraw

Withdraws tokens from the contract


```solidity
function withdraw(uint256 _tokenId) external nonReentrant whenNotPaused;
```

### sweep

withdraw excess tokens from the contract - possibly by accident


```solidity
function sweep() external nonReentrant auth(SWEEPER_ROLE);
```

### sweepNFT

the sweeper can send NFTs mistakenly sent to the contract to a designated address

*Cannot sweep NFTs that are in the exit queue for obvious reasons*


```solidity
function sweepNFT(uint256 _tokenId, address _to) external nonReentrant auth(SWEEPER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokenId`|`uint256`|the tokenId to sweep - must be currently in this contract|
|`_to`|`address`|the address to send the NFT to - must be a whitelisted address for transfers|


### implementation

Returns the address of the implementation contract in the [proxy storage slot](https://eips.ethereum.org/EIPS/eip-1967) slot the [UUPS proxy](https://eips.ethereum.org/EIPS/eip-1822) is pointing to.


```solidity
function implementation() public view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the implementation contract.|


### _authorizeUpgrade

Internal method authorizing the upgrade of the contract via the [upgradeability mechanism for UUPS proxies](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable) (see [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822)).


```solidity
function _authorizeUpgrade(address) internal virtual override auth(ESCROW_ADMIN_ROLE);
```

