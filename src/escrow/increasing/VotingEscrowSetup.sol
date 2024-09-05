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

import {VotingEscrow} from "./VotingEscrowIncreasing.sol";
import {ExitQueue} from "./ExitQueue.sol";
import {QuadraticIncreasingEscrow} from "./QuadraticIncreasingEscrow.sol";

contract VotingEscrowSetup is PluginSetup {
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
        (address token, uint256 exitQueueCooldown, string memory _name, string memory _symbol) = abi.decode(
            _data,
            (address, uint256, string, string)
        );

        // deploy the escrow locker
        VotingEscrow escrow = new VotingEscrow(token, _dao, _name, _symbol);
        plugin = address(escrow);

        // deploy the curve
        address curve = address(new QuadraticIncreasingEscrow(plugin));

        // deploy the exit queue
        address exitQueue = address(new ExitQueue(plugin, exitQueueCooldown, _dao));

        // encode our setup data with permissions and helpers
        PermissionLib.MultiTargetPermission[] memory permissions = getPermissions(
            _dao,
            plugin,
            exitQueue,
            PermissionLib.Operation.Grant
        );

        address[] memory helpers = new address[](2);

        helpers[0] = curve;
        helpers[1] = exitQueue;

        preparedSetupData.helpers = helpers;
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

        address queue = _payload.currentHelpers[1];
        // address actionRelay = _payload.currentHelpers[1];

        permissions = getPermissions(_dao, payable(_payload.plugin), queue, PermissionLib.Operation.Revoke);
    }

    /// @notice Returns the permissions required for the plugin install and uninstall.
    /// @param _dao The DAO address on this chain.
    /// @param _plugin The plugin address.
    /// @param _grantOrRevoke The operation to perform.
    function getPermissions(
        address _dao,
        address _plugin,
        address _queue,
        PermissionLib.Operation _grantOrRevoke
    ) public view returns (PermissionLib.MultiTargetPermission[] memory) {
        PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](2);

        permissions[0] = PermissionLib.MultiTargetPermission({
            permissionId: VotingEscrow(_plugin).ESCROW_ADMIN_ROLE(),
            where: _plugin,
            who: _dao,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            permissionId: ExitQueue(_queue).EXIT_QUEUE_MANAGER_ROLE(),
            where: _queue,
            who: _dao,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        return permissions;
    }
}
