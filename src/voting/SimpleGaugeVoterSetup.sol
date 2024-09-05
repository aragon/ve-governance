// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.8;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {IProposal} from "@aragon/osx/core/plugin/proposal/IProposal.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {PluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";

import {SimpleGaugeVoter} from "./SimpleGaugeVoter.sol";

contract SimpleGaugeVoterSetup is PluginSetup {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;
    using ProxyLib for address;

    /// @notice The identifier of the `EXECUTE_PERMISSION` permission.
    bytes32 public constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");

    /// @notice Thrown if passed helpers array is of wrong length.
    /// @param length The array length of passed helpers.
    error WrongHelpersArrayLength(uint256 length);

    /// @notice Thrown if the voting plugin does not support the `IToucanVoting` interface.
    error InvalidInterface();

    /// @notice Thrown if the voting plugin is not in vote replacement mode.
    error NotInVoteReplacementMode();

    /// @notice Deploys the setup by binding the implementation contracts required during installation.
    constructor() PluginSetup() {
        // escrowBase = _escrowBase;
        // curveBase = _curveBase;
        // voterBase = _voterBase;
        // exitQueueBase = _exitQueueBase;
    }

    /// @return The address of the `ToucanReceiver` implementation contract.
    function implementation() external pure returns (address) {
        // return escrowBase;
        revert("Not a proxy");
    }

    /// @inheritdoc IPluginSetup
    /// @dev You need to set the helpers on the plugin as a post install action.
    function prepareInstallation(
        address _dao,
        bytes calldata _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        (address escrow, bool autoReset) = abi.decode(_data, (address, bool));

        SimpleGaugeVoter voter = new SimpleGaugeVoter(_dao, escrow, autoReset);
        plugin = address(voter);

        // encode our setup data with permissions and helpers
        PermissionLib.MultiTargetPermission[] memory permissions = getPermissions(
            _dao,
            plugin,
            PermissionLib.Operation.Grant
        );

        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external view returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        // check the helpers length
        if (_payload.currentHelpers.length != 2) {
            revert WrongHelpersArrayLength(_payload.currentHelpers.length);
        }

        // address adapter = _payload.currentHelpers[0];
        // address actionRelay = _payload.currentHelpers[1];

        permissions = getPermissions(_dao, payable(_payload.plugin), PermissionLib.Operation.Revoke);
    }

    /// @notice Returns the permissions required for the plugin install and uninstall.
    /// @param _dao The DAO address on this chain.
    /// @param _plugin The plugin address.
    /// @param _grantOrRevoke The operation to perform.
    function getPermissions(
        address _dao,
        address _plugin,
        PermissionLib.Operation _grantOrRevoke
    ) public view returns (PermissionLib.MultiTargetPermission[] memory) {
        PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](1);

        permissions[0] = PermissionLib.MultiTargetPermission({
            permissionId: SimpleGaugeVoter(_plugin).GAUGE_ADMIN_ROLE(),
            where: _plugin,
            who: _dao,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        return permissions;
    }
}
