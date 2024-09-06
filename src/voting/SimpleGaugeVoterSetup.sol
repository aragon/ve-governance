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

import {SimpleGaugeVoter} from "@voting/SimpleGaugeVoter.sol";
import {VotingEscrow} from "@escrow/VotingEscrowIncreasing.sol";
import {ExitQueue} from "@escrow/ExitQueue.sol";
import {QuadraticIncreasingEscrow} from "@escrow/QuadraticIncreasingEscrow.sol";

struct ISimpleGaugeVoterSetupParams {
    // voter
    bool autoReset;
    // escrow
    string veTokenName;
    string veTokenSymbol;
    address token;
    // queue
    uint256 cooldown;
    // curve
    uint256 warmup;
}

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

    address escrowBase;

    address curveBase;

    /// @notice Deploys the setup by binding the implementation contracts required during installation.
    constructor(address _escrowBase, address _curveBase) PluginSetup() {
        escrowBase = _escrowBase;
        curveBase = _curveBase;
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
        // TODO a better way to do this would be to use the getter
        ISimpleGaugeVoterSetupParams memory params = abi.decode(
            _data,
            (ISimpleGaugeVoterSetupParams)
        );

        // deploy the escrow locker
        VotingEscrow escrow = VotingEscrow(
            escrowBase.deployUUPSProxy(
                abi.encodeCall(
                    VotingEscrow.initialize,
                    (params.token, _dao, params.veTokenName, params.veTokenSymbol)
                )
            )
        );

        // deploy the plugin
        SimpleGaugeVoter voter = new SimpleGaugeVoter(_dao, address(escrow), false);
        plugin = address(voter);

        // deploy the curve
        address curve = curveBase.deployUUPSProxy(
            abi.encodeCall(
                QuadraticIncreasingEscrow.initialize,
                (address(escrow), _dao, params.warmup)
            )
        );

        // deploy the exit queue
        address exitQueue = address(new ExitQueue(address(escrow), params.cooldown, _dao));

        // encode our setup data with permissions and helpers
        PermissionLib.MultiTargetPermission[] memory permissions = getPermissions(
            _dao,
            plugin,
            curve,
            exitQueue,
            address(escrow),
            PermissionLib.Operation.Grant
        );

        address[] memory helpers = new address[](3);

        helpers[0] = curve;
        helpers[1] = exitQueue;
        helpers[2] = address(escrow);

        preparedSetupData.helpers = helpers;
        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external view returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        // check the helpers length
        if (_payload.currentHelpers.length != 3) {
            revert WrongHelpersArrayLength(_payload.currentHelpers.length);
        }

        address curve = _payload.currentHelpers[0];
        address queue = _payload.currentHelpers[1];
        address escrow = _payload.currentHelpers[2];

        permissions = getPermissions(
            _dao,
            _payload.plugin,
            curve,
            queue,
            escrow,
            PermissionLib.Operation.Revoke
        );
    }

    /// @notice Returns the permissions required for the plugin install and uninstall.
    /// @param _dao The DAO address on this chain.
    /// @param _plugin The plugin address.
    /// @param _grantOrRevoke The operation to perform.
    function getPermissions(
        address _dao,
        address _plugin,
        address _curve,
        address _queue,
        address _escrow,
        PermissionLib.Operation _grantOrRevoke
    ) public view returns (PermissionLib.MultiTargetPermission[] memory) {
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](4);

        permissions[0] = PermissionLib.MultiTargetPermission({
            permissionId: SimpleGaugeVoter(_plugin).GAUGE_ADMIN_ROLE(),
            where: _plugin,
            who: _dao,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            permissionId: VotingEscrow(_escrow).ESCROW_ADMIN_ROLE(),
            where: _escrow,
            who: _dao,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[2] = PermissionLib.MultiTargetPermission({
            permissionId: ExitQueue(_queue).QUEUE_ADMIN_ROLE(),
            where: _queue,
            who: _dao,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[3] = PermissionLib.MultiTargetPermission({
            permissionId: QuadraticIncreasingEscrow(_curve).CURVE_ADMIN_ROLE(),
            where: _curve,
            who: _dao,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        return permissions;
    }
}
