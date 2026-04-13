/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {PluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginSetup.sol";

import {AddressGaugeVoter as GaugeVoter} from "@voting/AddressGaugeVoter.sol";
import {ClockV1_2_0 as Clock} from "@clock/Clock_v1_2_0.sol";

/// @param isPaused Whether the voter contract is deployed in a paused state
/// @param ivotesSource The pre-deployed IVotes contract (GaugeVotes) that tracks
///        xCTR-backed voting units and calls updateVotingPower() on the plugin
struct IGaugeVoterSetupXCTRParams {
    bool isPaused;
    address ivotesSource;
}

/// @notice Plugin setup variant that skips the ve-NFT escrow stack entirely and
/// wires AddressGaugeVoter to a pre-deployed IVotes source (xCTR's GaugeVotes).
contract GaugeVoterSetupV1_4_0_xCTR is PluginSetup {
    using ProxyLib for address;

    error WrongHelpersArrayLength(uint256 length);
    error ZeroIVotesSource();

    address voterBase;
    address clockBase;

    constructor(address _voterBase, address _clockBase) PluginSetup(_voterBase) {
        voterBase = _voterBase;
        clockBase = _clockBase;
    }

    function prepareInstallation(
        address _dao,
        bytes calldata _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        IGaugeVoterSetupXCTRParams memory params = abi.decode(_data, (IGaugeVoterSetupXCTRParams));
        if (params.ivotesSource == address(0)) revert ZeroIVotesSource();

        address clock = clockBase.deployUUPSProxy(
            abi.encodeWithSelector(Clock.initialize.selector, _dao)
        );

        // escrow = ivotesAdapter = ivotesSource (GaugeVotes).
        // hook = true: GaugeVotes calls updateVotingPower() on xCTR mint/burn,
        // which passes the onlyEscrow modifier since msg.sender == escrow.
        plugin = voterBase.deployUUPSProxy(
            abi.encodeCall(
                GaugeVoter.initialize,
                (_dao, params.ivotesSource, params.isPaused, clock, params.ivotesSource, true)
            )
        );

        address[] memory helpers = new address[](1);
        helpers[0] = clock;

        preparedSetupData.helpers = helpers;
        preparedSetupData.permissions = getPermissions(
            _dao,
            plugin,
            clock,
            PermissionLib.Operation.Grant
        );
    }

    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external view returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        if (_payload.currentHelpers.length != 1) {
            revert WrongHelpersArrayLength(_payload.currentHelpers.length);
        }
        permissions = getPermissions(
            _dao,
            _payload.plugin,
            _payload.currentHelpers[0],
            PermissionLib.Operation.Revoke
        );
    }

    function getPermissions(
        address _dao,
        address _plugin,
        address _clock,
        PermissionLib.Operation _op
    ) public view returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        permissions = new PermissionLib.MultiTargetPermission[](3);

        permissions[0] = PermissionLib.MultiTargetPermission({
            permissionId: GaugeVoter(_plugin).GAUGE_ADMIN_ROLE(),
            where: _plugin,
            who: _dao,
            operation: _op,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            permissionId: GaugeVoter(_plugin).UPGRADE_PLUGIN_PERMISSION_ID(),
            where: _plugin,
            who: _dao,
            operation: _op,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[2] = PermissionLib.MultiTargetPermission({
            permissionId: Clock(_clock).CLOCK_ADMIN_ROLE(),
            where: _clock,
            who: _dao,
            operation: _op,
            condition: PermissionLib.NO_CONDITION
        });
    }

    function encodeSetupData(
        IGaugeVoterSetupXCTRParams calldata _params
    ) external pure returns (bytes memory) {
        return abi.encode(_params);
    }

    function encodeSetupData(
        bool isPaused,
        address ivotesSource
    ) external pure returns (bytes memory) {
        return abi.encode(IGaugeVoterSetupXCTRParams({isPaused: isPaused, ivotesSource: ivotesSource}));
    }
}
