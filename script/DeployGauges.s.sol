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
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract DeployGauges is Script {
    using SafeCast for uint256;

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
        bool mintTestTokens = vm.envOr("MINT_TEST_TOKENS", false);
        DeploymentParameters memory parameters = getDeploymentParameters(mintTestTokens);

        // Create the DAO
        GaugesDaoFactory factory = new GaugesDaoFactory(parameters);
        factory.deployOnce();

        // Done
        printDeploymentSummary(factory);
    }

    function getDeploymentParameters(
        bool mintTestTokens
    ) public returns (DeploymentParameters memory parameters) {
        address[] memory multisigMembers = readMultisigMembers();
        TokenParameters[] memory tokenParameters = getTokenParameters(mintTestTokens);

        // NOTE: Multisig is already deployed, using the existing Aragon's repo
        // NOTE: Deploying the plugin setup from the current script to avoid code size constraints

        SimpleGaugeVoterSetup gaugeVoterPluginSetup = deploySimpleGaugeVoterPluginSetup();

        parameters = DeploymentParameters({
            // Multisig settings
            minApprovals: vm.envUint("MIN_APPROVALS").toUint8(),
            multisigMembers: multisigMembers,
            // Gauge Voter
            tokenParameters: tokenParameters,
            feePercent: vm.envUint("FEE_PERCENT").toUint16(),
            warmupPeriod: vm.envUint("WARMUP_PERIOD").toUint48(),
            cooldownPeriod: vm.envUint("COOLDOWN_PERIOD").toUint48(),
            minLockDuration: vm.envUint("MIN_LOCK_DURATION").toUint48(),
            votingPaused: vm.envBool("VOTING_PAUSED"),
            minDeposit: vm.envUint("MIN_DEPOSIT"),
            // Standard multisig repo
            multisigPluginRepo: PluginRepo(vm.envAddress("MULTISIG_PLUGIN_REPO_ADDRESS")),
            multisigPluginRelease: vm.envUint("MULTISIG_PLUGIN_RELEASE").toUint8(),
            multisigPluginBuild: vm.envUint("MULTISIG_PLUGIN_BUILD").toUint16(),
            // Voter plugin setup and ENS
            voterPluginSetup: gaugeVoterPluginSetup,
            voterEnsSubdomain: vm.envString("SIMPLE_GAUGE_VOTER_REPO_ENS_SUBDOMAIN"),
            // OSx addresses
            osxDaoFactory: vm.envAddress("DAO_FACTORY"),
            pluginSetupProcessor: PluginSetupProcessor(vm.envAddress("PLUGIN_SETUP_PROCESSOR")),
            pluginRepoFactory: PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY"))
        });
    }

    function readMultisigMembers() public view returns (address[] memory result) {
        // JSON list of members
        string memory membersFilePath = vm.envString("MULTISIG_MEMBERS_JSON_FILE_NAME");
        string memory path = string.concat(vm.projectRoot(), membersFilePath);
        string memory strJson = vm.readFile(path);

        bool exists = vm.keyExistsJson(strJson, "$.members");
        if (!exists) revert EmptyMultisig();

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
        bool mintTestTokens
    ) internal returns (TokenParameters[] memory tokenParameters) {
        if (mintTestTokens) {
            // MINT
            console.log("Deploying 2 token contracts (testing)");

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
        } else {
            // USE TOKEN(s)

            bool hasTwoTokens = vm.envAddress("TOKEN2_ADDRESS") != address(0);
            tokenParameters = new TokenParameters[](hasTwoTokens ? 2 : 1);

            console.log("Using token", vm.envAddress("TOKEN1_ADDRESS"));
            tokenParameters[0] = TokenParameters({
                token: vm.envAddress("TOKEN1_ADDRESS"),
                veTokenName: vm.envString("VE_TOKEN1_NAME"),
                veTokenSymbol: vm.envString("VE_TOKEN1_SYMBOL")
            });

            if (hasTwoTokens) {
                console.log("Using token", vm.envAddress("TOKEN2_ADDRESS"));
                tokenParameters[1] = TokenParameters({
                    token: vm.envAddress("TOKEN2_ADDRESS"),
                    veTokenName: vm.envString("VE_TOKEN2_NAME"),
                    veTokenSymbol: vm.envString("VE_TOKEN2_SYMBOL")
                });
            }
        }
    }

    function createTestToken(address[] memory holders) internal returns (address) {
        console.log("");
        MockERC20 newToken = new MockERC20();

        for (uint i = 0; i < holders.length; ) {
            newToken.mint(holders[i], 5000 ether);
            console.log("Minting 5000 tokens for", holders[i]);

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
        console.log("Chain ID:", block.chainid);
        console.log("Factory:", address(factory));
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
            console.log("");

            unchecked {
                i++;
            }
        }

        console.log("Plugin repositories");
        console.log(
            "- Multisig plugin repository (existing):",
            address(deploymentParameters.multisigPluginRepo)
        );
        console.log("- Gauge voter plugin repository:", address(deployment.gaugeVoterPluginRepo));
    }
}
