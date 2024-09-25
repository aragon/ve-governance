// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {GaugesDaoFactory, DeploymentParameters, Deployment, TokenParameters} from "../src/factory/GaugesDaoFactory.sol";
import {MultisigSetup as MultisigPluginSetup} from "@aragon/osx/plugins/governance/multisig/MultisigSetup.sol";
import {VotingEscrow, Clock, Lock, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, ISimpleGaugeVoterSetupParams} from "src/voting/SimpleGaugeVoterSetup.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";

contract Deploy is Script {
    SimpleGaugeVoterSetup simpleGaugeVoterSetup;

    /// @dev Thrown when attempting to create a DAO with an empty multisig
    error EmptyMultisig();

    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("Deploying from:", vm.addr(privKey));

        _;

        vm.stopBroadcast();
    }

    function run() public broadcast {
        // NOTE:
        // Deploying the plugin setup's separately because of the code size limit

        // Note: Multisig is already deployed, not redeploying

        // Deploy the voter plugin setup
        // TODO:

        DeploymentParameters memory parameters = getDeploymentParameters(
            vm.envBool("DEPLOY_AS_PRODUCTION")
        );

        // Create the DAO
        GaugesDaoFactory factory = new GaugesDaoFactory(parameters);
        factory.deployOnce();

        // Done
        printDeploymentSummary(factory);
    }

    function getDeploymentParameters(
        bool isProduction
    ) internal returns (DeploymentParameters memory parameters) {
        parameters = DeploymentParameters({
            // Multisig settings
            minProposalDuration: uint64(vm.envUint("MIN_PROPOSAL_DURATION")),
            minApprovals: uint8(vm.envUint("MIN_APPROVALS")),
            multisigMembers: readMultisigMembers(),
            // Gauge Voter
            tokenParameters: getTokenParameters(isProduction),
            feePercent: vm.envUint("FEE_PERCENT_WEI"),
            warmupPeriod: uint64(vm.envUint("WARMUP_PERIOD")),
            cooldownPeriod: uint64(vm.envUint("COOLDOWN_PERIOD")),
            minLockDuration: uint64(vm.envUint("MIN_LOCK_DURATION")),
            votingPaused: vm.envBool("VOTING_PAUSED"),
            // Standard multisig repo
            multisigPluginRepo: PluginRepo(vm.envAddress("MULTISIG_PLUGIN_REPO_ADDRESS")),
            multisigPluginRelease: uint8(vm.envUint("MULTISIG_PLUGIN_RELEASE")),
            multisigPluginBuild: uint16(vm.envUint("MULTISIG_PLUGIN_BUILD")),
            // Voter plugin setup and ENS
            voterPluginSetup: deploySimpleGaugeVoterPluginSetup(),
            voterEnsSubdomain: vm.envString("SIMPLE_GAUGE_VOTER_REPO_ENS_SUBDOMAIN"),
            // OSx addresses
            osxDaoFactory: vm.envAddress("DAO_FACTORY"),
            pluginSetupProcessor: PluginSetupProcessor(vm.envAddress("PLUGIN_SETUP_PROCESSOR")),
            pluginRepoFactory: PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY"))
        });
    }

    function readMultisigMembers() internal view returns (address[] memory result) {
        // JSON list of members
        string memory membersFilePath = vm.envString("MULTISIG_MEMBERS_JSON_FILE_NAME");
        string memory path = string.concat(vm.projectRoot(), membersFilePath);
        string memory strJson = vm.readFile(path);
        result = vm.parseJsonAddressArray(strJson, "$.members");

        if (result.length == 0) revert EmptyMultisig();
    }

    function deploySimpleGaugeVoterPluginSetup() internal returns (SimpleGaugeVoterSetup result) {
        result = new SimpleGaugeVoterSetup(
            address(new SimpleGaugeVoter()),
            address(new QuadraticIncreasingEscrow()),
            address(new ExitQueue()),
            address(new VotingEscrow()),
            address(new Clock()),
            address(new Lock())
        );
    }

    function getTokenParameters(
        bool isProduction
    ) internal view returns (TokenParameters[] memory tokenParameters) {
        if (isProduction) {
            // USE TOKEN(s)
            console.log("Using production parameters");

            bool hasTwoTokens = vm.envAddress("TOKEN2_ADDRESS") != address(0);
            tokenParameters = new TokenParameters[](hasTwoTokens ? 2 : 1);

            tokenParameters[0] = TokenParameters({
                token: vm.envAddress("TOKEN1_ADDRESS"),
                veTokenName: vm.envString("VE_TOKEN1_NAME"),
                veTokenSymbol: vm.envString("VE_TOKEN1_SYMBOL")
            });

            if (hasTwoTokens) {
                tokenParameters[1] = TokenParameters({
                    token: vm.envAddress("TOKEN2_ADDRESS"),
                    veTokenName: vm.envString("VE_TOKEN2_NAME"),
                    veTokenSymbol: vm.envString("VE_TOKEN2_SYMBOL")
                });
            }
        } else {
            // MINT TEST TOKEN
            console.log("Using testing parameters (minting 2 token)");

            // TODO:
        }
    }

    function createTestToken(address[] memory holders) internal {
        // TODO:
        address newToken = vm.envAddress("GOVERNANCE_ERC20_BASE");
    }

    function printDeploymentSummary(GaugesDaoFactory factory) internal view {
        DeploymentParameters memory deploymentParameters = factory.getDeploymentParameters();
        Deployment memory deployment = factory.getDeployment();

        console.log("");
        console.log("Factory:", address(factory));
        console.log("Chain ID:", block.chainid);
        console.log("");
        console.log("DAO:", address(deployment.dao));
        console.log("");

        console.log("Plugins");
        console.log("- Multisig plugin:", address(deployment.multisigPlugin));
        console.log("");
        for (uint i = 0; i < deployment.voterPlugins.length; ) {
            console.log("- Token:", address(deploymentParameters.tokenParameters[i].token));
            console.log("  Gauge voter plugin:", address(deployment.voterPlugins[i]));
            unchecked {
                i++;
            }
        }
        console.log("");

        console.log("Plugin repositories");
        console.log(
            "- Eultisig plugin repository (existing):",
            address(deploymentParameters.multisigPluginRepo)
        );
        console.log("- Gauge voter plugin repository:", address(deployment.voterPluginRepo));
        console.log("");

        console.log("Helpers");
    }
}
