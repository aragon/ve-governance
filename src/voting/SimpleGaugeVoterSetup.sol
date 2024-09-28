/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {IProposal} from "@aragon/osx/core/plugin/proposal/IProposal.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {PluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";

// these should be interfaces
import {SimpleGaugeVoter} from "@voting/SimpleGaugeVoter.sol";
import {VotingEscrow} from "@escrow/VotingEscrowIncreasing.sol";
import {ExitQueue} from "@escrow/ExitQueue.sol";
import {QuadraticIncreasingEscrow} from "@escrow/QuadraticIncreasingEscrow.sol";
import {Clock} from "@clock/Clock.sol";
import {Lock} from "@escrow/Lock.sol";

/// @param isPaused Whether the voter contract is deployed in a paused state
/// @param veTokenName The name of the voting escrow token
/// @param veTokenSymbol The symbol of the voting escrow token
/// @param token The underlying token for the escrow
/// @param cooldown The cooldown period for the exit queue
/// @param warmup The warmup period for the escrow curve
struct ISimpleGaugeVoterSetupParams {
    // voter
    bool isPaused;
    // escrow - NFT
    string veTokenName;
    string veTokenSymbol;
    // escrow - main
    address token;
    // queue
    uint256 feePercent;
    uint48 cooldown;
    uint48 minLock;
    // curve
    uint48 warmup;
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

    /// @dev implementation of the gaugevoting plugin
    address voterBase;

    /// @dev implementation of the escrow voting curve
    address curveBase;

    /// @dev implementation of the exit queue
    address queueBase;

    /// @dev implementation of the escrow locker
    address escrowBase;

    /// @dev implementation of the clock
    address clockBase;

    /// @dev implementation of the escrow NFT
    address nftBase;

    /// @notice Deploys the setup by binding the implementation contracts required during installation.
    constructor(
        address _voterBase,
        address _curveBase,
        address _queueBase,
        address _escrowBase,
        address _clockBase,
        address _nftBase
    ) PluginSetup() {
        voterBase = _voterBase;
        curveBase = _curveBase;
        queueBase = _queueBase;
        escrowBase = _escrowBase;
        clockBase = _clockBase;
        nftBase = _nftBase;
    }

    function implementation() external view returns (address) {
        return voterBase;
    }

    /// @inheritdoc IPluginSetup
    /// @dev You need to set the helpers on the plugin as a post install action.
    function prepareInstallation(
        address _dao,
        bytes calldata _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        ISimpleGaugeVoterSetupParams memory params = abi.decode(
            _data,
            (ISimpleGaugeVoterSetupParams)
        );

        // deploy the clock
        address clock = address(
            Clock(
                clockBase.deployUUPSProxy(abi.encodeWithSelector(Clock.initialize.selector, _dao))
            )
        );

        // deploy the escrow locker
        VotingEscrow escrow = VotingEscrow(
            escrowBase.deployUUPSProxy(
                abi.encodeCall(VotingEscrow.initialize, (params.token, _dao, clock))
            )
        );

        // deploy the voting contract (plugin)
        SimpleGaugeVoter voter = SimpleGaugeVoter(
            voterBase.deployUUPSProxy(
                abi.encodeCall(
                    SimpleGaugeVoter.initialize,
                    (_dao, address(escrow), params.isPaused, clock)
                )
            )
        );
        plugin = address(voter);

        // deploy the curve
        address curve = curveBase.deployUUPSProxy(
            abi.encodeCall(
                QuadraticIncreasingEscrow.initialize,
                (address(escrow), _dao, params.warmup, clock)
            )
        );

        // deploy the exit queue
        address exitQueue = queueBase.deployUUPSProxy(
            abi.encodeCall(
                ExitQueue.initialize,
                (address(escrow), params.cooldown, _dao, params.feePercent, clock, params.minLock)
            )
        );

        // deploy the escrow NFT
        address nftLock = nftBase.deployUUPSProxy(
            abi.encodeCall(
                Lock.initialize,
                (address(escrow), params.veTokenName, params.veTokenSymbol, _dao)
            )
        );

        // encode our setup data with permissions and helpers
        PermissionLib.MultiTargetPermission[] memory permissions = getPermissions(
            _dao,
            plugin,
            curve,
            exitQueue,
            address(escrow),
            clock,
            nftLock,
            PermissionLib.Operation.Grant
        );

        address[] memory helpers = new address[](5);

        helpers[0] = curve;
        helpers[1] = exitQueue;
        helpers[2] = address(escrow);
        helpers[3] = clock;
        helpers[4] = address(nftLock);

        preparedSetupData.helpers = helpers;
        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external view returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        // check the helpers length
        if (_payload.currentHelpers.length != 5) {
            revert WrongHelpersArrayLength(_payload.currentHelpers.length);
        }

        address curve = _payload.currentHelpers[0];
        address queue = _payload.currentHelpers[1];
        address escrow = _payload.currentHelpers[2];
        address clock = _payload.currentHelpers[3];
        address nftLock = _payload.currentHelpers[4];

        permissions = getPermissions(
            _dao,
            _payload.plugin,
            curve,
            queue,
            escrow,
            clock,
            nftLock,
            PermissionLib.Operation.Revoke
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
        PermissionLib.Operation _grantOrRevoke
    ) public view returns (PermissionLib.MultiTargetPermission[] memory) {
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](10);

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

        permissions[4] = PermissionLib.MultiTargetPermission({
            permissionId: SimpleGaugeVoter(_plugin).UPGRADE_PLUGIN_PERMISSION_ID(),
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
            permissionId: VotingEscrow(_escrow).PAUSER_ROLE(),
            where: _escrow,
            who: _dao,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[8] = PermissionLib.MultiTargetPermission({
            permissionId: VotingEscrow(_escrow).SWEEPER_ROLE(),
            where: _escrow,
            who: _dao,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[9] = PermissionLib.MultiTargetPermission({
            permissionId: ExitQueue(_queue).WITHDRAW_ROLE(),
            where: _queue,
            who: _dao,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });
        return permissions;
    }

    function encodeSetupData(
        ISimpleGaugeVoterSetupParams calldata _params
    ) external pure returns (bytes memory) {
        return abi.encode(_params);
    }

    /// @notice Simple utility for external applications create the encoded setup data.
    function encodeSetupData(
        bool isPaused,
        string calldata veTokenName,
        string calldata veTokenSymbol,
        address token,
        uint48 cooldown,
        uint48 warmup,
        uint256 feePercent,
        uint48 minLock
    ) external pure returns (bytes memory) {
        return
            abi.encode(
                ISimpleGaugeVoterSetupParams({
                    isPaused: isPaused,
                    token: token,
                    veTokenName: veTokenName,
                    veTokenSymbol: veTokenSymbol,
                    warmup: warmup,
                    cooldown: cooldown,
                    feePercent: feePercent,
                    minLock: minLock
                })
            );
    }
}
