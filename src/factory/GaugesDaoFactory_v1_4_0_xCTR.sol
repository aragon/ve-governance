// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {AddressGaugeVoter as GaugeVoter} from "@voting/AddressGaugeVoter.sol";
import {ClockV1_2_0 as Clock} from "@clock/Clock_v1_2_0.sol";
import {
    GaugeVoterSetupV1_4_0_xCTR as GaugeVoterSetup,
    IGaugeVoterSetupXCTRParams
} from "@setup/GaugeVoterSetup_v1_4_0_xCTR.sol";

import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
import {
    hashHelpers,
    PluginSetupRef
} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {Multisig} from "@aragon/multisig/src/Multisig.sol";

struct DeploymentParameters {
    address daoExecutor;
    string daoMetadataURI;
    string daoSubdomain;
    // Multisig
    uint16 minApprovals;
    address[] multisigMembers;
    bytes multisigMetadata;
    // Gauge voter
    address ivotesSource; // pre-deployed GaugeVotes (xCTR voting tracker)
    bool votingPaused;
    // Multisig repo
    PluginRepo multisigPluginRepo;
    uint8 multisigPluginRelease;
    uint16 multisigPluginBuild;
    // Voter plugin repo
    GaugeVoterSetup voterPluginSetup;
    string voterEnsSubdomain;
    // OSx
    address osxDaoFactory;
    PluginSetupProcessor pluginSetupProcessor;
    PluginRepoFactory pluginRepoFactory;
}

struct GaugePluginSet {
    GaugeVoter plugin;
    Clock clock;
}

struct Deployment {
    DAO dao;
    Multisig multisigPlugin;
    GaugePluginSet gaugeVoterPluginSet;
    PluginRepo gaugeVoterPluginRepo;
}

/// @notice Single-shot factory that deploys a DAO + multisig + AddressGaugeVoter
/// plugin pointed at a pre-existing GaugeVotes IVotes source (xCTR).
contract GaugesDaoFactoryV1_4_0_xCTR {
    function version() external pure returns (string memory) {
        return "1.4.0-xCTR";
    }

    error AlreadyDeployed();

    DeploymentParameters parameters;
    Deployment deployment;

    constructor(DeploymentParameters memory _parameters) {
        parameters.minApprovals = _parameters.minApprovals;
        parameters.multisigMembers = _parameters.multisigMembers;
        parameters.multisigMetadata = _parameters.multisigMetadata;

        parameters.daoMetadataURI = _parameters.daoMetadataURI;
        parameters.daoSubdomain = _parameters.daoSubdomain;
        parameters.daoExecutor = _parameters.daoExecutor;

        parameters.ivotesSource = _parameters.ivotesSource;
        parameters.votingPaused = _parameters.votingPaused;

        parameters.multisigPluginRepo = _parameters.multisigPluginRepo;
        parameters.multisigPluginRelease = _parameters.multisigPluginRelease;
        parameters.multisigPluginBuild = _parameters.multisigPluginBuild;
        parameters.voterPluginSetup = _parameters.voterPluginSetup;
        parameters.voterEnsSubdomain = _parameters.voterEnsSubdomain;
        parameters.osxDaoFactory = _parameters.osxDaoFactory;
        parameters.pluginSetupProcessor = _parameters.pluginSetupProcessor;
        parameters.pluginRepoFactory = _parameters.pluginRepoFactory;
    }

    function deployOnce() public {
        if (address(deployment.dao) != address(0)) revert AlreadyDeployed();

        DAO dao = prepareDao();
        deployment.dao = dao;

        grantApplyInstallationPermissions(dao);

        // MULTISIG
        {
            PluginRepo.Tag memory repoTag = PluginRepo.Tag(
                parameters.multisigPluginRelease,
                parameters.multisigPluginBuild
            );
            (Multisig plugin, IPluginSetup.PreparedSetupData memory prepared) = prepareMultisig(
                dao,
                repoTag
            );
            deployment.multisigPlugin = plugin;
            applyPluginInstallation(
                dao,
                address(plugin),
                parameters.multisigPluginRepo,
                repoTag,
                prepared
            );
        }

        // GAUGE VOTER
        {
            PluginRepo.Tag memory repoTag = PluginRepo.Tag(1, 1);
            PluginRepo pluginRepo = prepareGaugeVoterPluginRepo(dao);
            deployment.gaugeVoterPluginRepo = pluginRepo;

            (
                GaugePluginSet memory pluginSet,
                IPluginSetup.PreparedSetupData memory prepared
            ) = prepareGaugeVoterPlugin(dao, pluginRepo, repoTag);

            deployment.gaugeVoterPluginSet = pluginSet;

            applyPluginInstallation(
                dao,
                address(pluginSet.plugin),
                pluginRepo,
                repoTag,
                prepared
            );
        }

        revokeApplyInstallationPermissions(dao);
        revokeOwnerPermission(deployment.dao);
    }

    function prepareDao() internal returns (DAO dao) {
        DAOFactory.DAOSettings memory daoSettings = DAOFactory.DAOSettings({
            trustedForwarder: address(0),
            daoURI: "",
            subdomain: parameters.daoSubdomain,
            metadata: bytes(parameters.daoMetadataURI)
        });

        (dao, ) = DAOFactory(parameters.osxDaoFactory).createDao(
            daoSettings,
            new DAOFactory.PluginSettings[](0)
        );

        address daoExecutor = parameters.daoExecutor;
        Action[] memory actions = new Action[](daoExecutor == address(0) ? 1 : 2);
        actions[0].to = address(dao);
        actions[0].data = abi.encodeCall(
            PermissionManager.grant,
            (address(dao), address(this), dao.ROOT_PERMISSION_ID())
        );
        if (daoExecutor != address(0)) {
            actions[1].to = address(dao);
            actions[1].data = abi.encodeCall(
                PermissionManager.grant,
                (address(dao), daoExecutor, dao.EXECUTE_PERMISSION_ID())
            );
        }

        dao.execute(bytes32(0), actions, 0);
    }

    function prepareMultisig(
        DAO dao,
        PluginRepo.Tag memory repoTag
    ) internal returns (Multisig, IPluginSetup.PreparedSetupData memory) {
        bytes memory settingsData = abi.encode(
            parameters.multisigMembers,
            Multisig.MultisigSettings(true, parameters.minApprovals),
            IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call}),
            parameters.multisigMetadata
        );

        (address plugin, IPluginSetup.PreparedSetupData memory prepared) = parameters
            .pluginSetupProcessor
            .prepareInstallation(
                address(dao),
                PluginSetupProcessor.PrepareInstallationParams(
                    PluginSetupRef(repoTag, parameters.multisigPluginRepo),
                    settingsData
                )
            );

        return (Multisig(plugin), prepared);
    }

    function prepareGaugeVoterPluginRepo(DAO dao) internal returns (PluginRepo pluginRepo) {
        pluginRepo = PluginRepoFactory(parameters.pluginRepoFactory)
            .createPluginRepoWithFirstVersion(
                parameters.voterEnsSubdomain,
                address(parameters.voterPluginSetup),
                address(dao),
                " ",
                " "
            );
    }

    function prepareGaugeVoterPlugin(
        DAO dao,
        PluginRepo pluginRepo,
        PluginRepo.Tag memory repoTag
    ) internal returns (GaugePluginSet memory, IPluginSetup.PreparedSetupData memory) {
        bytes memory settingsData = parameters.voterPluginSetup.encodeSetupData(
            IGaugeVoterSetupXCTRParams({
                isPaused: parameters.votingPaused,
                ivotesSource: parameters.ivotesSource
            })
        );

        (address plugin, IPluginSetup.PreparedSetupData memory prepared) = parameters
            .pluginSetupProcessor
            .prepareInstallation(
                address(dao),
                PluginSetupProcessor.PrepareInstallationParams(
                    PluginSetupRef(repoTag, pluginRepo),
                    settingsData
                )
            );

        GaugePluginSet memory pluginSet = GaugePluginSet({
            plugin: GaugeVoter(plugin),
            clock: Clock(prepared.helpers[0])
        });

        return (pluginSet, prepared);
    }

    function applyPluginInstallation(
        DAO dao,
        address plugin,
        PluginRepo pluginRepo,
        PluginRepo.Tag memory pluginRepoTag,
        IPluginSetup.PreparedSetupData memory prepared
    ) internal {
        parameters.pluginSetupProcessor.applyInstallation(
            address(dao),
            PluginSetupProcessor.ApplyInstallationParams(
                PluginSetupRef(pluginRepoTag, pluginRepo),
                plugin,
                prepared.permissions,
                hashHelpers(prepared.helpers)
            )
        );
    }

    function grantApplyInstallationPermissions(DAO dao) internal {
        dao.grant(address(dao), address(parameters.pluginSetupProcessor), dao.ROOT_PERMISSION_ID());
        dao.grant(
            address(parameters.pluginSetupProcessor),
            address(this),
            parameters.pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID()
        );
    }

    function revokeApplyInstallationPermissions(DAO dao) internal {
        dao.revoke(
            address(parameters.pluginSetupProcessor),
            address(this),
            parameters.pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID()
        );
        dao.revoke(
            address(dao),
            address(parameters.pluginSetupProcessor),
            dao.ROOT_PERMISSION_ID()
        );
    }

    function revokeOwnerPermission(DAO dao) internal {
        dao.revoke(address(dao), address(this), dao.EXECUTE_PERMISSION_ID());
        dao.revoke(address(dao), address(this), dao.ROOT_PERMISSION_ID());
    }

    function getDeploymentParameters() public view returns (DeploymentParameters memory) {
        return parameters;
    }

    function getDeployment() public view returns (Deployment memory) {
        return deployment;
    }
}
