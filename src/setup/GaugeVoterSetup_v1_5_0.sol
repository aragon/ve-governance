/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {PluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginSetup.sol";

import {AddressGaugeVoter as GaugeVoter} from "@voting/AddressGaugeVoter.sol";
import {VotingEscrowV1_2_0 as VotingEscrow} from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";
import {DynamicExitQueue as ExitQueue} from "@queue/DynamicExitQueue.sol";
import {LinearIncreasingCurve as Curve} from "@curve/LinearIncreasingCurve.sol";
import {ClockV1_2_0 as Clock} from "@clock/Clock_v1_2_0.sol";
import {LockV1_2_0 as Lock} from "@lock/Lock_v1_2_0.sol";
import {EscrowIVotesAdapter} from "@delegation/EscrowIVotesAdapter.sol";

/// @param isPaused Whether the voter contract is deployed in a paused state
/// @param veTokenName The name of the voting escrow token
/// @param veTokenSymbol The symbol of the voting escrow token
/// @param token The underlying token for the escrow
/// @param cooldown The cooldown period for the exit queue
struct IGaugeVoterPluginSetupParams {
    // Voter
    bool isPaused;
    // Escrow - NFT
    string veTokenName;
    string veTokenSymbol;
    // Escrow - main
    address token;
    uint256 minDeposit;
    // Queue
    uint256 feePercent;
    uint48 cooldown;
    uint48 minLock;
    // Curve
    int256 curveConstantCoefficient;
    int256 curveLinearCoefficient;
    int256 curveQuadraticCoefficient;
    /// @param The maxiumum number of epochs that the curve can increase up to
    /// @dev 1 epoch = 2 weeks => 26 epochs in a year
    uint256 curveMaxEpoch;
}

contract GaugeVoterSetup_v1_5_0 is PluginSetup {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;
    using ProxyLib for address;

    /// @notice Thrown if passed helpers array is of wrong length.
    /// @param length The array length of passed helpers.
    error WrongHelpersArrayLength(uint256 length);

    /// @dev implementation of the gaugevoting plugin
    address voterBase;

    /// @dev implementation of the exit queue
    address queueBase;

    /// @dev implementation of the escrow locker
    address escrowBase;

    /// @dev implementation of the clock
    address clockBase;

    /// @dev implementation of the escrow NFT
    address nftBase;

    struct Deployment {
        address curve;
        address exitQueue;
        address escrow;
        address clock;
        address nftLock;
        address ivotesAdapter;
        address plugin;
    }

    /// @notice Deploys the setup by binding the implementation contracts required during installation.
    constructor(address _voterBase, address _queueBase, address _escrowBase, address _clockBase, address _nftBase)
        PluginSetup(_voterBase)
    {
        voterBase = _voterBase;
        queueBase = _queueBase;
        escrowBase = _escrowBase;
        clockBase = _clockBase;
        nftBase = _nftBase;
    }

    /// @inheritdoc IPluginSetup
    /// @dev You need to set the helpers on the plugin as a post install action.
    function prepareInstallation(address _dao, bytes calldata _data)
        external
        returns (address plugin, PreparedSetupData memory preparedSetupData)
    {
        IGaugeVoterPluginSetupParams memory params = abi.decode(_data, (IGaugeVoterPluginSetupParams));

        Deployment memory deps;

        // deploy the clock
        deps.clock = address(clockBase.deployUUPSProxy(abi.encodeWithSelector(Clock.initialize.selector, _dao)));

        // deploy the escrow locker
        deps.escrow = escrowBase.deployUUPSProxy(
            abi.encodeCall(VotingEscrow.initialize, (params.token, _dao, deps.clock, params.minDeposit))
        );

        {
            int256[3] memory _curveCoefficients;
            _curveCoefficients[0] = params.curveConstantCoefficient;
            _curveCoefficients[1] = params.curveLinearCoefficient;
            _curveCoefficients[2] = params.curveQuadraticCoefficient;

            // deploy the IVotes adapter
            address ivotesAdapterBase = address(new EscrowIVotesAdapter(_curveCoefficients, params.curveMaxEpoch));
            deps.ivotesAdapter = ivotesAdapterBase.deployUUPSProxy(
                abi.encodeCall(EscrowIVotesAdapter.initialize, (_dao, deps.escrow, deps.clock, false))
            );

            // deploy the curve
            address curveBase = address(new Curve(_curveCoefficients, params.curveMaxEpoch));
            deps.curve = curveBase.deployUUPSProxy(abi.encodeCall(Curve.initialize, (deps.escrow, _dao, deps.clock)));
        }

        // deploy the voting contract (plugin)
        deps.plugin = voterBase.deployUUPSProxy(
            abi.encodeCall(
                GaugeVoter.initialize, (_dao, deps.escrow, params.isPaused, deps.clock, deps.ivotesAdapter, true)
            )
        );

        // deploy the exit queue
        deps.exitQueue = queueBase.deployUUPSProxy(
            abi.encodeCall(
                ExitQueue.initialize,
                (deps.escrow, params.cooldown, _dao, params.feePercent, deps.clock, params.minLock)
            )
        );

        // deploy the escrow NFT
        deps.nftLock = nftBase.deployUUPSProxy(
            abi.encodeCall(Lock.initialize, (deps.escrow, params.veTokenName, params.veTokenSymbol, _dao))
        );

        // encode our setup data with permissions and helpers
        PermissionLib.MultiTargetPermission[] memory permissions = getPermissions(
            _dao,
            deps.plugin,
            deps.curve,
            deps.exitQueue,
            deps.escrow,
            deps.clock,
            deps.nftLock,
            deps.ivotesAdapter,
            PermissionLib.Operation.Grant
        );

        address[] memory helpers = new address[](6);

        helpers[0] = deps.curve;
        helpers[1] = deps.exitQueue;
        helpers[2] = deps.escrow;
        helpers[3] = deps.clock;
        helpers[4] = deps.nftLock;
        helpers[5] = deps.ivotesAdapter;

        // return arguments
        preparedSetupData.helpers = helpers;
        preparedSetupData.permissions = permissions;
        plugin = deps.plugin;
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(address _dao, SetupPayload calldata _payload)
        external
        view
        returns (PermissionLib.MultiTargetPermission[] memory permissions)
    {
        // check the helpers length
        if (_payload.currentHelpers.length != 6) {
            revert WrongHelpersArrayLength(_payload.currentHelpers.length);
        }

        address curve = _payload.currentHelpers[0];
        address queue = _payload.currentHelpers[1];
        address escrow = _payload.currentHelpers[2];
        address clock = _payload.currentHelpers[3];
        address nftLock = _payload.currentHelpers[4];
        address ivotesAdapter = _payload.currentHelpers[5];

        permissions = getPermissions(
            _dao, _payload.plugin, curve, queue, escrow, clock, nftLock, ivotesAdapter, PermissionLib.Operation.Revoke
        );
    }

    /// @notice Returns the permissions required for the plugin install and uninstall.
    /// @param _dao The DAO address on this chain.
    /// @param _plugin The plugin address.
    /// @param _grantOrRevoke The operation to perform
    function getPermissions(
        address _dao,
        address _plugin,
        address _curve,
        address _queue,
        address _escrow,
        address _clock,
        address _nft,
        address _ivotesAdapter,
        PermissionLib.Operation _grantOrRevoke
    ) public view returns (PermissionLib.MultiTargetPermission[] memory) {
        PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](12);

        permissions[0] = PermissionLib.MultiTargetPermission({
            permissionId: GaugeVoter(_plugin).GAUGE_ADMIN_ROLE(),
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
            permissionId: Curve(_curve).CURVE_ADMIN_ROLE(),
            where: _curve,
            who: _dao,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[4] = PermissionLib.MultiTargetPermission({
            permissionId: GaugeVoter(_plugin).UPGRADE_PLUGIN_PERMISSION_ID(),
            where: _plugin,
            who: _dao,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[5] = PermissionLib.MultiTargetPermission({
            permissionId: Clock(_clock).CLOCK_ADMIN_ROLE(),
            where: _clock,
            who: _dao,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[6] = PermissionLib.MultiTargetPermission({
            permissionId: Lock(_nft).LOCK_ADMIN_ROLE(),
            where: _nft,
            who: _dao,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[7] = PermissionLib.MultiTargetPermission({
            permissionId: EscrowIVotesAdapter(_ivotesAdapter).DELEGATION_ADMIN_ROLE(),
            where: _ivotesAdapter,
            who: _dao,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[8] = PermissionLib.MultiTargetPermission({
            permissionId: EscrowIVotesAdapter(_ivotesAdapter).DELEGATION_TOKEN_ROLE(),
            where: _ivotesAdapter,
            who: _dao,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[9] = PermissionLib.MultiTargetPermission({
            permissionId: VotingEscrow(_escrow).PAUSER_ROLE(),
            where: _escrow,
            who: _dao,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[10] = PermissionLib.MultiTargetPermission({
            permissionId: VotingEscrow(_escrow).SWEEPER_ROLE(),
            where: _escrow,
            who: _dao,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[11] = PermissionLib.MultiTargetPermission({
            permissionId: ExitQueue(_queue).WITHDRAW_ROLE(),
            where: _queue,
            who: _dao,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        return permissions;
    }

    function encodeSetupData(IGaugeVoterPluginSetupParams calldata _params) external pure returns (bytes memory) {
        return abi.encode(_params);
    }
}
