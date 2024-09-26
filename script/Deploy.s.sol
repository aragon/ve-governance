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
import {MockERC20} from "@mocks/MockERC20.sol";

contract Deploy is Script {
    SimpleGaugeVoterSetup simpleGaugeVoterSetup;

    /// @dev Thrown when attempting to deploy a multisig with no members
    error EmptyMultisig();

    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("Deploying from:", vm.addr(privKey));

        _;

        vm.stopBroadcast();
    }

    /// @notice Runs the deployment flow, records the given parameters and artifacts, and it becomes read only
    function run() public broadcast {
        // Prepare all parameters
        bool isProduction = vm.envBool("DEPLOY_AS_PRODUCTION");
        DeploymentParameters memory parameters = getDeploymentParameters(isProduction);

        // Create the DAO
        GaugesDaoFactory factory = new GaugesDaoFactory(parameters);
        factory.deployOnce();

        // Done
        printDeploymentSummary(factory);
    }

    function getDeploymentParameters(
        bool isProduction
    ) internal returns (DeploymentParameters memory parameters) {
        address[] memory multisigMembers = readMultisigMembers();
        TokenParameters[] memory tokenParameters = getTokenParameters(isProduction);

        // NOTE: Multisig is already deployed, using the existing Aragon's repo
        // NOTE: Deploying the plugin setup from the current script to avoid code size constraints

        SimpleGaugeVoterSetup gaugeVoterPluginSetup = deploySimpleGaugeVoterPluginSetup();

        parameters = DeploymentParameters({
            // Multisig settings
            minApprovals: uint8(vm.envUint("MIN_APPROVALS")),
            multisigMembers: multisigMembers,
            // Gauge Voter
            tokenParameters: tokenParameters,
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
            voterPluginSetup: gaugeVoterPluginSetup,
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
    ) internal returns (TokenParameters[] memory tokenParameters) {
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
            console.log("Using testing parameters (minting 2 test tokens)");

            address[] memory multisigMembers = readMultisigMembers();
            tokenParameters = new TokenParameters[](2);
            tokenParameters[0] = TokenParameters({
                token: createTestToken(multisigMembers),
                veTokenName: "VE Token 1",
                veTokenSymbol: "veTK1"
            });
            tokenParameters[1] = TokenParameters({
                token: createTestToken(multisigMembers),
                veTokenName: "VE Token 2",
                veTokenSymbol: "veTK2"
            });
        }
    }

    function createTestToken(address[] memory holders) internal returns (address) {
        MockERC20 newToken = new MockERC20();

        for (uint i = 0; i < holders.length; ) {
            newToken.mint(holders[i], 50 ether);
            console.log("Minting 50 tokens for", holders[i]);

            unchecked {
                i++;
            }
        }

        return address(newToken);
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

        for (uint i = 0; i < deployment.gaugeVoterPluginSets.length; ) {
            console.log("- Using token:", address(deploymentParameters.tokenParameters[i].token));
            console.log(
                "  Gauge voter plugin:",
                address(deployment.gaugeVoterPluginSets[i].plugin)
            );
            console.log("  Curve:", address(deployment.gaugeVoterPluginSets[i].curve));
            console.log("  Exit Queue:", address(deployment.gaugeVoterPluginSets[i].exitQueue));
            console.log(
                "  Voting Escrow:",
                address(deployment.gaugeVoterPluginSets[i].votingEscrow)
            );
            console.log("  Clock:", address(deployment.gaugeVoterPluginSets[i].clock));
            console.log("  NFT Lock:", address(deployment.gaugeVoterPluginSets[i].nftLock));

            unchecked {
                i++;
            }
        }
        console.log("");

        console.log("Plugin repositories");
        console.log(
            "- Multisig plugin repository (existing):",
            address(deploymentParameters.multisigPluginRepo)
        );
        console.log("- Gauge voter plugin repository:", address(deployment.gaugeVoterPluginRepo));
        console.log("");

        console.log("Helpers");
    }
}
