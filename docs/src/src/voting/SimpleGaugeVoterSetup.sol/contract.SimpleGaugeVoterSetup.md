# SimpleGaugeVoterSetup
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/voting/SimpleGaugeVoterSetup.sol)

**Inherits:**
PluginSetup


## State Variables
### EXECUTE_PERMISSION_ID
The identifier of the `EXECUTE_PERMISSION` permission.


```solidity
bytes32 public constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");
```


### voterBase
*implementation of the gaugevoting plugin*


```solidity
address voterBase;
```


### curveBase
*implementation of the escrow voting curve*


```solidity
address curveBase;
```


### queueBase
*implementation of the exit queue*


```solidity
address queueBase;
```


### escrowBase
*implementation of the escrow locker*


```solidity
address escrowBase;
```


### clockBase
*implementation of the clock*


```solidity
address clockBase;
```


### nftBase
*implementation of the escrow NFT*


```solidity
address nftBase;
```


## Functions
### constructor

Deploys the setup by binding the implementation contracts required during installation.


```solidity
constructor(
    address _voterBase,
    address _curveBase,
    address _queueBase,
    address _escrowBase,
    address _clockBase,
    address _nftBase
) PluginSetup();
```

### implementation


```solidity
function implementation() external view returns (address);
```

### prepareInstallation

Prepares the installation of a plugin.

*You need to set the helpers on the plugin as a post install action.*


```solidity
function prepareInstallation(address _dao, bytes calldata _data)
    external
    returns (address plugin, PreparedSetupData memory preparedSetupData);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_dao`|`address`|The address of the installing DAO.|
|`_data`|`bytes`|The bytes-encoded data containing the input parameters for the installation as specified in the plugin's build metadata JSON file.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`plugin`|`address`|The address of the `Plugin` contract being prepared for installation.|
|`preparedSetupData`|`PreparedSetupData`|The deployed plugin's relevant data which consists of helpers and permissions.|


### prepareUninstallation

Prepares the uninstallation of a plugin.


```solidity
function prepareUninstallation(address _dao, SetupPayload calldata _payload)
    external
    view
    returns (PermissionLib.MultiTargetPermission[] memory permissions);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_dao`|`address`|The address of the uninstalling DAO.|
|`_payload`|`SetupPayload`|The relevant data necessary for the `prepareUninstallation`. See above.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`permissions`|`PermissionLib.MultiTargetPermission[]`|The array of multi-targeted permission operations to be applied by the `PluginSetupProcessor` to the uninstalling DAO.|


### getPermissions

Returns the permissions required for the plugin install and uninstall.


```solidity
function getPermissions(
    address _dao,
    address _plugin,
    address _curve,
    address _queue,
    address _escrow,
    address _clock,
    address _nft,
    PermissionLib.Operation _grantOrRevoke
) public view returns (PermissionLib.MultiTargetPermission[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_dao`|`address`|The DAO address on this chain.|
|`_plugin`|`address`|The plugin address.|
|`_curve`|`address`||
|`_queue`|`address`||
|`_escrow`|`address`||
|`_clock`|`address`||
|`_nft`|`address`||
|`_grantOrRevoke`|`PermissionLib.Operation`|The operation to perform|


### encodeSetupData


```solidity
function encodeSetupData(ISimpleGaugeVoterSetupParams calldata _params) external pure returns (bytes memory);
```

### encodeSetupData

Simple utility for external applications create the encoded setup data.


```solidity
function encodeSetupData(
    bool isPaused,
    string calldata veTokenName,
    string calldata veTokenSymbol,
    address token,
    uint48 cooldown,
    uint48 warmup,
    uint256 feePercent,
    uint48 minLock,
    uint256 minDeposit
) external pure returns (bytes memory);
```

## Errors
### WrongHelpersArrayLength
Thrown if passed helpers array is of wrong length.


```solidity
error WrongHelpersArrayLength(uint256 length);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`length`|`uint256`|The array length of passed helpers.|

