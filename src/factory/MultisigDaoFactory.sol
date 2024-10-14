// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {hashHelpers, PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {Multisig} from "@aragon/osx/plugins/governance/multisig/Multisig.sol";
import {MultisigSetup as MultisigPluginSetup} from "@aragon/osx/plugins/governance/multisig/MultisigSetup.sol";
import {createERC1967Proxy} from "@aragon/osx/utils/Proxy.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";

/// @notice The struct containing all the parameters to deploy the DAO
/// @param minApprovals The amount of approvals required for the multisig to be able to execute a proposal on the DAO
/// @param multisigMembers The list of addresses to be defined as the initial multisig signers
/// @param multisigPluginRepo Address of Aragon's multisig plugin repository on the given network
/// @param multisigPluginRelease The release of the multisig plugin to target
/// @param multisigPluginBuild The build of the multisig plugin to target
/// @param osxDaoFactory The address of the OSx DAO factory contract, used to retrieve the DAO implementation address
/// @param pluginSetupProcessor The address of the OSx PluginSetupProcessor contract on the target chain
struct DeploymentParameters {
    // Multisig settings
    uint16 minApprovals;
    address[] multisigMembers;
    // Voter plugin setup and ENS
    PluginRepo multisigPluginRepo;
    uint8 multisigPluginRelease;
    uint16 multisigPluginBuild;
    // OSx addresses
    address osxDaoFactory;
    PluginSetupProcessor pluginSetupProcessor;
}

/// @notice Contains the artifacts that resulted from running a deployment
struct Deployment {
    DAO dao;
    Multisig multisigPlugin;
}

/// @notice A singleton contract designed to run the deployment once and become a read-only store of the contracts deployed
contract MultisigDaoFactory {
    /// @notice Thrown when attempting to call deployOnce() when the DAO is already deployed.
    error AlreadyDeployed();

    DeploymentParameters parameters;
    Deployment deployment;

    /// @notice Initializes the factory and performs the full deployment. Values become read-only after that.
    /// @param _parameters The parameters of the one-time deployment.
    constructor(DeploymentParameters memory _parameters) {
        parameters.minApprovals = _parameters.minApprovals;
        parameters.multisigMembers = _parameters.multisigMembers;

        parameters.multisigPluginRepo = _parameters.multisigPluginRepo;
        parameters.multisigPluginRelease = _parameters.multisigPluginRelease;
        parameters.multisigPluginBuild = _parameters.multisigPluginBuild;
        
        parameters.osxDaoFactory = _parameters.osxDaoFactory;
        parameters.pluginSetupProcessor = _parameters.pluginSetupProcessor;
    }

    /// @notice Run the deployment and store the artifacts in a read-only store that can be retrieved via `getDeployment()` and `getDeploymentParameters()`
    function deployOnce() public {
        if (address(deployment.dao) != address(0)) revert AlreadyDeployed();

        // Deploy the DAO (this contract is the interim owner)
        DAO dao = prepareDao();
        deployment.dao = dao;

        // Deploy and install the plugins

        grantApplyInstallationPermissions(dao);

        // MULTISIG
        {
            IPluginSetup.PreparedSetupData memory preparedMultisigSetupData;

            PluginRepo.Tag memory repoTag = PluginRepo.Tag(
                parameters.multisigPluginRelease,
                parameters.multisigPluginBuild
            );

            (deployment.multisigPlugin, preparedMultisigSetupData) = prepareMultisig(dao, repoTag);

            applyPluginInstallation(
                dao,
                address(deployment.multisigPlugin),
                parameters.multisigPluginRepo,
                repoTag,
                preparedMultisigSetupData
            );
        }

        // Clean up
        revokeApplyInstallationPermissions(dao);

        // Remove this contract as owner
        revokeOwnerPermission(deployment.dao);
    }

    function prepareDao() internal returns (DAO dao) {
        address daoBase = DAOFactory(parameters.osxDaoFactory).daoBase();

        dao = DAO(
            payable(
                createERC1967Proxy(
                    address(daoBase),
                    abi.encodeCall(
                        DAO.initialize,
                        (
                            "", // Metadata URI
                            address(this), // initialOwner
                            address(0x0), // Trusted forwarder
                            "" // DAO URI
                        )
                    )
                )
            )
        );

        // Grant DAO all the needed permissions on itself
        PermissionLib.SingleTargetPermission[]
            memory items = new PermissionLib.SingleTargetPermission[](3);
        items[0] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Grant,
            address(dao),
            dao.ROOT_PERMISSION_ID()
        );
        items[1] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Grant,
            address(dao),
            dao.UPGRADE_DAO_PERMISSION_ID()
        );
        items[2] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Grant,
            address(dao),
            dao.REGISTER_STANDARD_CALLBACK_PERMISSION_ID()
        );

        dao.applySingleTargetPermissions(address(dao), items);
    }

    function prepareMultisig(
        DAO dao,
        PluginRepo.Tag memory repoTag
    ) internal returns (Multisig, IPluginSetup.PreparedSetupData memory) {
        bytes memory settingsData = abi.encode(
            parameters.multisigMembers,
            Multisig.MultisigSettings(
                true, // onlyListed
                parameters.minApprovals
            )
        );

        (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData) = parameters
            .pluginSetupProcessor
            .prepareInstallation(
                address(dao),
                PluginSetupProcessor.PrepareInstallationParams(
                    PluginSetupRef(repoTag, parameters.multisigPluginRepo),
                    settingsData
                )
            );

        return (Multisig(plugin), preparedSetupData);
    }

    function applyPluginInstallation(
        DAO dao,
        address plugin,
        PluginRepo pluginRepo,
        PluginRepo.Tag memory pluginRepoTag,
        IPluginSetup.PreparedSetupData memory preparedSetupData
    ) internal {
        parameters.pluginSetupProcessor.applyInstallation(
            address(dao),
            PluginSetupProcessor.ApplyInstallationParams(
                PluginSetupRef(pluginRepoTag, pluginRepo),
                plugin,
                preparedSetupData.permissions,
                hashHelpers(preparedSetupData.helpers)
            )
        );
    }

    function grantApplyInstallationPermissions(DAO dao) internal {
        // The PSP can manage permissions on the new DAO
        dao.grant(address(dao), address(parameters.pluginSetupProcessor), dao.ROOT_PERMISSION_ID());

        // This factory can call applyInstallation() on the PSP
        dao.grant(
            address(parameters.pluginSetupProcessor),
            address(this),
            parameters.pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID()
        );
    }

    function revokeApplyInstallationPermissions(DAO dao) internal {
        // Revoking the permission for the factory to call applyInstallation() on the PSP
        dao.revoke(
            address(parameters.pluginSetupProcessor),
            address(this),
            parameters.pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID()
        );

        // Revoke the PSP permission to manage permissions on the new DAO
        dao.revoke(
            address(dao),
            address(parameters.pluginSetupProcessor),
            dao.ROOT_PERMISSION_ID()
        );
    }

    function revokeOwnerPermission(DAO dao) internal {
        dao.revoke(address(dao), address(this), dao.ROOT_PERMISSION_ID());
    }

    // Getters

    function getDeploymentParameters() public view returns (DeploymentParameters memory) {
        return parameters;
    }

    function getDeployment() public view returns (Deployment memory) {
        return deployment;
    }
}
