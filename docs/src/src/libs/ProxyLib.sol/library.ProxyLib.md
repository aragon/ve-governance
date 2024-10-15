# ProxyLib
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/libs/ProxyLib.sol)

**Author:**
Aragon X - 2024

SPDX-License-Identifier: MIT

A library containing methods for the deployment of proxies via the UUPS pattern (see [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822)) and minimal proxy pattern (see [ERC-1167](https://eips.ethereum.org/EIPS/eip-1167)).


## Functions
### deployUUPSProxy

Creates an [ERC-1967](https://eips.ethereum.org/EIPS/eip-1967) UUPS proxy contract pointing to a logic contract and allows to immediately initialize it.

*If `_initCalldata` is non-empty, it is used in a delegate call to the `_logic` contract. This will typically be an encoded function call initializing the storage of the proxy (see [OpenZeppelin ERC1967Proxy-constructor](https://docs.openzeppelin.com/contracts/4.x/api/proxy#ERC1967Proxy-constructor-address-bytes-)).*


```solidity
function deployUUPSProxy(address _logic, bytes memory _initCalldata) internal returns (address uupsProxy);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_logic`|`address`|The logic contract the proxy is pointing to.|
|`_initCalldata`|`bytes`|The initialization data for this contract.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`uupsProxy`|`address`|The address of the UUPS proxy contract created.|


### deployMinimalProxy

Creates an [ERC-1167](https://eips.ethereum.org/EIPS/eip-1167) minimal proxy contract, also known as clones, pointing to a logic contract and allows to immediately initialize it.

*If `_initCalldata` is non-empty, it is used in a call to the clone contract. This will typically be an encoded function call initializing the storage of the contract.*


```solidity
function deployMinimalProxy(address _logic, bytes memory _initCalldata) internal returns (address minimalProxy);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_logic`|`address`|The logic contract the proxy is pointing to.|
|`_initCalldata`|`bytes`|The initialization data for this contract.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`minimalProxy`|`address`|The address of the minimal proxy contract created.|


