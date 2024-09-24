// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {ModeDaoFactory} from "../src/factory/ModeDaoFactory.sol";
import {MultisigSetup} from "@aragon/osx/plugins/governance/multisig/MultisigSetup.sol";
import {SimpleGaugeVoterSetup} from "../src/voting/SimpleGaugeVoterSetup.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";

contract Deploy is Script {
    MultisigPluginSetup multisigPluginSetup;
    SimpleGaugeVoterSetup simpleGaugeVoterSetup;

    modifier broadcast() {
        vm.startBroadcast(vm.envUint("DEPLOYMENT_PRIVATE_KEY"));
        console.log("Deploying from:", vm.addr(vm.envUint("DEPLOYMENT_PRIVATE_KEY")));
        _;
        vm.stopBroadcast();
    }

    function run() public broadcast {
        // NOTE:
        // Deploying the plugin setup's separately because of the code size limit

        // Resolve the multisig plugin repo address

        // Deploy the main plugin setup

        // TODO

        ModeDaoFactory.DeploymentSettings memory settings;
        if (vm.envBool("DEPLOY_AS_PRODUCTION")) {
            settings = getProductionSettings();
        } else {
            settings = getInternalTestingSettings();
        }

        console.log("");

        // Create the DAO
        ModeDaoFactory factory = new ModeDaoFactory(settings);
        factory.deployOnce();

        // Done
        printDeploymentSummary(factory);
    }

    function getProductionSettings()
        internal
        view
        returns (ModeDaoFactory.DeploymentSettings memory settings)
    {
        console.log("Using production settings");

        settings = ModeDaoFactory.DeploymentSettings({
            // Mode contract settings
            tokenAddress: IVotesUpgradeable(vm.envAddress("TOKEN_ADDRESS")),
            // Voting settings
            minVetoRatio: uint32(vm.envUint("MIN_VETO_RATIO")),
            minStdProposalDuration: uint64(vm.envUint("MIN_STD_PROPOSAL_DURATION")),
            minStdApprovals: uint16(vm.envUint("MIN_STD_APPROVALS")),
            // OSx contracts
            osxDaoFactory: vm.envAddress("DAO_FACTORY"),
            pluginSetupProcessor: PluginSetupProcessor(vm.envAddress("PLUGIN_SETUP_PROCESSOR")),
            pluginRepoFactory: PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY")),
            // Plugin setup's
            multisigPluginSetup: MultisigPluginSetup(multisigPluginSetup),
            optimisticTokenVotingPluginSetup: OptimisticTokenVotingPluginSetup(
                optimisticTokenVotingPluginSetup
            ),
            // Multisig members
            multisigMembers: readMultisigMembers(),
            multisigExpirationPeriod: uint64(vm.envUint("MULTISIG_PROPOSAL_EXPIRATION_PERIOD")),
            // ENS
            stdMultisigEnsDomain: vm.envString("STD_MULTISIG_ENS_DOMAIN"),
            optimisticTokenVotingEnsDomain: vm.envString("OPTIMISTIC_TOKEN_VOTING_ENS_DOMAIN")
        });
    }

    function getInternalTestingSettings()
        internal
        returns (ModeDaoFactory.DeploymentSettings memory settings)
    {
        console.log("Using internal testing settings");

        address[] memory multisigMembers = readMultisigMembers();
        // address votingToken = createTestToken(multisigMembers, tokenAddress);

        settings = ModeDaoFactory.DeploymentSettings({
            // Mode contract settings
            tokenAddress: IVotesUpgradeable(votingToken),
            // Voting settings
            minVetoRatio: uint32(vm.envUint("MIN_VETO_RATIO")),
            minStdProposalDuration: uint64(vm.envUint("MIN_STD_PROPOSAL_DURATION")),
            minStdApprovals: uint16(vm.envUint("MIN_STD_APPROVALS")),
            // OSx contracts
            osxDaoFactory: vm.envAddress("DAO_FACTORY"),
            pluginSetupProcessor: PluginSetupProcessor(vm.envAddress("PLUGIN_SETUP_PROCESSOR")),
            pluginRepoFactory: PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY")),
            // Plugin setup's
            multisigPluginSetup: MultisigPluginSetup(multisigPluginSetup),
            optimisticTokenVotingPluginSetup: OptimisticTokenVotingPluginSetup(
                optimisticTokenVotingPluginSetup
            ),
            // Multisig members
            multisigMembers: multisigMembers,
            multisigExpirationPeriod: uint64(vm.envUint("MULTISIG_PROPOSAL_EXPIRATION_PERIOD")),
            // ENS
            stdMultisigEnsDomain: vm.envString("STD_MULTISIG_ENS_DOMAIN"),
            optimisticTokenVotingEnsDomain: vm.envString("OPTIMISTIC_TOKEN_VOTING_ENS_DOMAIN")
        });
    }

    function readMultisigMembers() internal view returns (address[] memory) {
        // JSON list of members
        string memory path = string.concat(vm.projectRoot(), "/script/multisig-members.json");
        string memory json = vm.readFile(path);
        return vm.parseJsonAddressArray(json, "$.members");
    }

    function printDeploymentSummary(address factory) internal {
        console.log("Factory:", address(factory));
        console.log("Chain ID:", block.chainid);
        console.log("");
        console.log("DAO:", address(daoDeployment.dao));
        console.log("Voting token:", address(settings.tokenAddress));
        console.log("");

        console.log("Plugins");
        console.log("- Multisig plugin:", address(daoDeployment.multisigPlugin));
        console.log(
            "- Token voting plugin:",
            address(daoDeployment.optimisticTokenVotingPlugin)
        );
        console.log("");

        console.log("Plugin repositories");
        console.log("- Multisig plugin repository:", address(daoDeployment.multisigPluginRepo));
        console.log(
            "- Token voting plugin repository:",
            address(daoDeployment.optimisticTokenVotingPluginRepo)
        );
        console.log("");

        console.log("Helpers");
    }
}
