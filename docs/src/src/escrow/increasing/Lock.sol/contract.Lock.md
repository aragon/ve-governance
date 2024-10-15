# Lock
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/escrow/increasing/Lock.sol)

**Inherits:**
[ILock](/src/escrow/increasing/interfaces/ILock.sol/interface.ILock.md), ERC721Enumerable, UUPSUpgradeable, DaoAuthorizable, ReentrancyGuard

SPDX-License-Identifier: MIT


## State Variables
### WHITELIST_ANY_ADDRESS
*enables transfers without whitelisting*


```solidity
address public constant WHITELIST_ANY_ADDRESS = address(uint160(uint256(keccak256("WHITELIST_ANY_ADDRESS"))));
```


### LOCK_ADMIN_ROLE
role to upgrade this contract


```solidity
bytes32 public constant LOCK_ADMIN_ROLE = keccak256("LOCK_ADMIN");
```


### escrow
Address of the escrow contract that holds underyling assets


```solidity
address public escrow;
```


### whitelisted
Whitelisted contracts that are allowed to transfer


```solidity
mapping(address => bool) public whitelisted;
```


### __gap

```solidity
uint256[48] private __gap;
```


## Functions
### onlyEscrow


```solidity
modifier onlyEscrow();
```

### supportsInterface


```solidity
function supportsInterface(bytes4 _interfaceId) public view override(ERC721Enumerable) returns (bool);
```

### constructor


```solidity
constructor();
```

### initialize


```solidity
function initialize(address _escrow, string memory _name, string memory _symbol, address _dao) external initializer;
```

### setWhitelisted

Transfers disabled by default, only whitelisted addresses can receive transfers


```solidity
function setWhitelisted(address _account, bool _isWhitelisted) external auth(LOCK_ADMIN_ROLE);
```

### enableTransfers

Enable transfers to any address without whitelisting


```solidity
function enableTransfers() external auth(LOCK_ADMIN_ROLE);
```

### _transfer

*Override the transfer to check if the recipient is whitelisted
This avoids needing to check for mint/burn but is less idomatic than beforeTokenTransfer*


```solidity
function _transfer(address _from, address _to, uint256 _tokenId) internal override;
```

### isApprovedOrOwner


```solidity
function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool);
```

### mint

Minting and burning functions that can only be called by the escrow contract

*Safe mint ensures contract addresses are ERC721 Receiver contracts*


```solidity
function mint(address _to, uint256 _tokenId) external onlyEscrow nonReentrant;
```

### burn

Minting and burning functions that can only be called by the escrow contract


```solidity
function burn(uint256 _tokenId) external onlyEscrow nonReentrant;
```

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
function _authorizeUpgrade(address) internal virtual override auth(LOCK_ADMIN_ROLE);
```

