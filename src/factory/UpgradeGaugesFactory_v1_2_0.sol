// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "test/constants.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {Multisig, MultisigSetup as MultisigPluginSetup} from "@aragon/osx/plugins/governance/multisig/MultisigSetup.sol";
import {hashHelpers, PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

import {
  SimpleGaugeVoterSetupV1_1_0,
  VotingEscrow,
  Clock,
  Lock,
  QuadraticIncreasingEscrow,
  ExitQueue,
  SimpleGaugeVoter
} from "src/voting/SimpleGaugeVoterSetup_v1_1_0.sol";
import {
  GaugesDaoFactoryV1_1_0,
  Deployment,
  DeploymentParameters,
  TokenParameters,
  GaugePluginSet
} from "src/factory/GaugesDaoFactory_v1_1_0.sol";

import {
  Clock as ClockV1_2_0,
  QuadraticIncreasingEscrow as QuadraticIncreasingEscrowV1_2_0,
  SimpleGaugeVoter as SimpleGaugeVoterV1_2_0,
  SimpleGaugeVoterSetupV1_2_0,
  ISimpleGaugeVoterSetupParams as ISimpleGaugeVoterSetupParamsV1_2_0
  } from "src/voting/SimpleGaugeVoterSetup_v1_2_0.sol";


import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";

import {Upgrades} from "@foundry-upgrades/LegacyUpgrades.sol";
import {Options} from "@foundry-upgrades/Options.sol";

contract UpgradeGaugesFactoryV1_2_0 {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;
    using ProxyLib for address;

    GaugesDaoFactoryV1_1_0 factory;

    DAO dao;
    Multisig multisig;

    PluginRepoFactory pluginRepoFactory;
    PluginRepo oldPluginRepo;
    PluginSetupProcessor pluginSetupProcessor;

    Deployment deployment;
    Deployment oldDeployment;

    constructor(GaugesDaoFactoryV1_1_0 _factory) {
        factory = _factory;

        Deployment memory oldDeploymentAux = factory.getDeployment();
        for (uint i = 0; i < oldDeploymentAux.gaugeVoterPluginSets.length; i++) {
            oldDeployment.gaugeVoterPluginSets.push(oldDeploymentAux.gaugeVoterPluginSets[i]);
        }
        oldDeployment.dao = oldDeploymentAux.dao;
        oldDeployment.multisigPlugin = oldDeploymentAux.multisigPlugin;
        oldDeployment.gaugeVoterPluginRepo = oldDeploymentAux.gaugeVoterPluginRepo;

        dao = DAO(oldDeployment.dao);
        multisig = Multisig(oldDeployment.multisigPlugin);
        oldPluginRepo = PluginRepo(oldDeployment.gaugeVoterPluginRepo);

        DeploymentParameters memory parameters = factory.getDeploymentParameters();
        pluginRepoFactory = PluginRepoFactory(parameters.pluginRepoFactory);
        pluginSetupProcessor = PluginSetupProcessor(address(parameters.pluginSetupProcessor));
    }

    function validateUpgrade__v1_1_0__v1_2_0() public {
        Options memory options;
    
        string[] memory exclude = new string[](1);
        // disable initializers is invoked but the custom unsafe allow option is not set in the natspec
        exclude[0] = "lib/osx/packages/contracts/src/core/plugin/PluginUUPSUpgradeable.sol";
        options.exclude = exclude;
    
        // SimpleGaugeVoter can't be upgraded due to slot incompatibilities. Should always be a new deployment
        //options.referenceContract = "SimpleGaugeVoter_v1_1_0.sol";
        //Upgrades.validateUpgrade("SimpleGaugeVoter_v1_2_0.sol:SimpleGaugeVoterV1_2_0", options);
    
        options.referenceContract = "Clock.sol";
        Upgrades.validateUpgrade("Clock_v1_2_0.sol:ClockV1_2_0", options);
    
        options.referenceContract = "QuadraticIncreasingEscrow.sol";
        Upgrades.validateUpgrade("QuadraticIncreasingEscrow_v1_2_0.sol:QuadraticIncreasingEscrowV1_2_0", options);
    }

    function upgrade() public {
      _upgradeContracts();
    }

    ////////////////////////////////////////////////
    ///-------------- Internal ------------------///
    ////////////////////////////////////////////////

    function _upgradeContracts() internal {
        // Get Permission IDs
        bytes32 rootPermissionID = dao.ROOT_PERMISSION_ID();
        bytes32 applyInstallationPermissionID = pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID();
        bytes32 applyUninstallationPermissionID = pluginSetupProcessor.APPLY_UNINSTALLATION_PERMISSION_ID();

        // Grant the temporary permissions.
        // Grant Temporarly `ROOT_PERMISSION` to `pluginSetupProcessor`.
        dao.grant(address(dao), address(pluginSetupProcessor), rootPermissionID);

        // Grant Temporarly `APPLY_INSTALLATION_PERMISSION` on `pluginSetupProcessor` to this `DAOFactory`.
        dao.grant(address(pluginSetupProcessor), address(this), applyInstallationPermissionID);

        // Grant Temporarly `APPLY_UNINSTALLATION_PERMISSION` on `pluginSetupProcessor` to this `DAOFactory`.
        dao.grant(address(pluginSetupProcessor), address(this), applyUninstallationPermissionID);

        DeploymentParameters memory parameters = factory.getDeploymentParameters();

        ClockV1_2_0 clockV1_2_0 = new ClockV1_2_0();
        QuadraticIncreasingEscrowV1_2_0 curveV1_2_0 = new QuadraticIncreasingEscrowV1_2_0();

        for (uint i = 0; i < parameters.tokenParameters.length; i++) {
            GaugePluginSet memory pluginSet = oldDeployment.gaugeVoterPluginSets[i];

            pluginSet.clock.upgradeTo(address(clockV1_2_0));
            pluginSet.curve.upgradeTo(address(curveV1_2_0));

            SimpleGaugeVoterSetupV1_2_0 voterPluginSetupV1_2_0 = new SimpleGaugeVoterSetupV1_2_0(
                address(new SimpleGaugeVoterV1_2_0()),
                false,
                address(pluginSet.curve),
                true,
                address(pluginSet.exitQueue),
                true,
                address(pluginSet.votingEscrow),
                true,
                address(pluginSet.clock),
                true,
                address(pluginSet.nftLock),
                true
            );            

            // Publish repo
            PluginRepo pluginRepo = PluginRepoFactory(pluginRepoFactory)
                .createPluginRepoWithFirstVersion(
                    "simple-gauge-voter-v120",
                    address(voterPluginSetupV1_2_0),
                    address(dao),
                    " ",
                    " "
                );

            
            PluginRepo.Tag memory repoTag = PluginRepo.Tag(1, 1);

            // Prepare old plugin for uninstallation
            PermissionLib.MultiTargetPermission[] memory permissions = preparePluginUninstallation(
                oldPluginRepo,
                repoTag,
                pluginSet
            );

            applyPluginUninstallation(
                address(pluginSet.plugin),
                oldPluginRepo,
                repoTag,
                permissions
            );
            
            // Prepare and apply plugin
            GaugePluginSet memory newPluginSet;
            IPluginSetup.PreparedSetupData memory preparedVoterSetupData;

            // Prepare plugin
            (
                newPluginSet,
                preparedVoterSetupData
            ) = preparePluginInstallation(
                parameters,
                parameters.tokenParameters[i],
                pluginRepo,
                repoTag,
                voterPluginSetupV1_2_0
            );

            applyPluginInstallation(
                address(newPluginSet.plugin),
                pluginRepo,
                repoTag,
                preparedVoterSetupData
            );

            deployment.gaugeVoterPluginSets.push(newPluginSet);

            // Activate the plugin
            updateSimpleGaugeVoterInstallation(newPluginSet);
        }

        // Update deployment
        deployment.dao = oldDeployment.dao;
        deployment.multisigPlugin = oldDeployment.multisigPlugin;
        deployment.gaugeVoterPluginRepo = oldDeployment.gaugeVoterPluginRepo;

        // Revoke the temporary permissions.
        // Revoke `ROOT_PERMISSION` from `pluginSetupProcessor`.
        dao.revoke(address(dao), address(pluginSetupProcessor), rootPermissionID);

        // Revoke `APPLY_INSTALLATION_PERMISSION` from `pluginSetupProcessor`.
        dao.revoke(address(pluginSetupProcessor), address(this), applyInstallationPermissionID);

        // Revoke `APPLY_UNINSTALLATION_PERMISSION` from `pluginSetupProcessor`.
        dao.revoke(address(pluginSetupProcessor), address(this), applyUninstallationPermissionID);


    }

    function preparePluginInstallation(
        DeploymentParameters memory parameters,
        TokenParameters memory tokenParameters,
        PluginRepo pluginRepo,
        PluginRepo.Tag memory repoTag,
        SimpleGaugeVoterSetupV1_2_0 voterPluginSetupV1_2_0
    ) internal returns (GaugePluginSet memory, IPluginSetup.PreparedSetupData memory) {
        // Plugin settings
        bytes memory settingsData = voterPluginSetupV1_2_0.encodeSetupData(
            ISimpleGaugeVoterSetupParamsV1_2_0({
                isPaused: parameters.votingPaused,
                token: tokenParameters.token,
                veTokenName: tokenParameters.veTokenName,
                veTokenSymbol: tokenParameters.veTokenSymbol,
                feePercent: parameters.feePercent,
                warmup: parameters.warmupPeriod,
                cooldown: parameters.cooldownPeriod,
                minLock: parameters.minLockDuration,
                minDeposit: parameters.minDeposit
            })
        );

        (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData) = pluginSetupProcessor
            .prepareInstallation(
                address(dao),
                PluginSetupProcessor.PrepareInstallationParams(
                    PluginSetupRef(repoTag, pluginRepo),
                    settingsData
                )
            );

        address[] memory helpers = preparedSetupData.helpers;
        GaugePluginSet memory pluginSet = GaugePluginSet({
            plugin: SimpleGaugeVoter(plugin),
            curve: QuadraticIncreasingEscrow(helpers[0]),
            exitQueue: ExitQueue(helpers[1]),
            votingEscrow: VotingEscrow(helpers[2]),
            clock: Clock(helpers[3]),
            nftLock: Lock(helpers[4])
        });

        return (pluginSet, preparedSetupData);
    }


    function applyPluginInstallation(
        address plugin,
        PluginRepo pluginRepo,
        PluginRepo.Tag memory pluginRepoTag,
        IPluginSetup.PreparedSetupData memory preparedSetupData
    ) internal {
        pluginSetupProcessor.applyInstallation(
            address(dao),
            PluginSetupProcessor.ApplyInstallationParams(
                PluginSetupRef(pluginRepoTag, pluginRepo),
                plugin,
                preparedSetupData.permissions,
                hashHelpers(preparedSetupData.helpers)
            )
        );
    }

    function preparePluginUninstallation(
        PluginRepo pluginRepo,
        PluginRepo.Tag memory repoTag,
        GaugePluginSet memory pluginSet
    ) internal returns (PermissionLib.MultiTargetPermission[] memory permissions) {

        address[] memory helpers = new address[](5);
        helpers[0] = address(pluginSet.curve);
        helpers[1] = address(pluginSet.exitQueue);
        helpers[2] = address(pluginSet.votingEscrow);
        helpers[3] = address(pluginSet.clock);
        helpers[4] = address(pluginSet.nftLock);
        
        IPluginSetup.SetupPayload memory setupPayload = IPluginSetup.SetupPayload({
            plugin: address(pluginSet.plugin),
            currentHelpers: helpers,
            data: abi.encodePacked(uint256(0))
        });

        permissions = pluginSetupProcessor
            .prepareUninstallation(
                address(dao),
                PluginSetupProcessor.PrepareUninstallationParams(
                    PluginSetupRef(repoTag, pluginRepo),
                    setupPayload
                )
            );
    }

    function applyPluginUninstallation(
        address plugin,
        PluginRepo pluginRepo,
        PluginRepo.Tag memory pluginRepoTag,
        PermissionLib.MultiTargetPermission[] memory permissions
    ) internal {
        pluginSetupProcessor.applyUninstallation(
            address(dao),
            PluginSetupProcessor.ApplyUninstallationParams(
                plugin,
                PluginSetupRef(pluginRepoTag, pluginRepo),
                permissions
            )
        );
    }

    function updateSimpleGaugeVoterInstallation(
        GaugePluginSet memory pluginSet
    ) internal {
        dao.grant(
            address(pluginSet.votingEscrow),
            address(this),
            pluginSet.votingEscrow.ESCROW_ADMIN_ROLE()
        );

        pluginSet.votingEscrow.setVoter(address(pluginSet.plugin));

        dao.revoke(
            address(pluginSet.votingEscrow),
            address(this),
            pluginSet.votingEscrow.ESCROW_ADMIN_ROLE()
        );
    }

    function getOldDeployment() public view returns (Deployment memory) {
        return oldDeployment;
    }

    function getDeployment() public view returns (Deployment memory) {
        return deployment;
    }
}
