// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {
    GaugesDaoFactoryV1_4_0_xCTR as GaugesDaoFactory,
    DeploymentParameters,
    Deployment
} from "@factory/GaugesDaoFactory_v1_4_0_xCTR.sol";
import {GaugeVoterSetupV1_4_0_xCTR as GaugeVoterSetup} from "@setup/GaugeVoterSetup_v1_4_0_xCTR.sol";
import {AddressGaugeVoter as GaugeVoter} from "@voting/AddressGaugeVoter.sol";
import {ClockV1_2_0 as Clock} from "@clock/Clock_v1_2_0.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract DeployGaugesV1_4_0_xCTR is Script {
    using SafeCast for uint256;

    error EmptyMultisig();

    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("Deploying from:", vm.addr(privKey));
        _;
        vm.stopBroadcast();
    }

    function run() public broadcast {
        DeploymentParameters memory parameters = getDeploymentParameters();

        GaugesDaoFactory factory = new GaugesDaoFactory(parameters);
        require(keccak256(abi.encode(factory.version())) == keccak256(abi.encode("1.4.0-xCTR")), "Version mismatch");
        factory.deployOnce();

        printDeploymentSummary(factory);
    }

    function getDeploymentParameters() public returns (DeploymentParameters memory parameters) {
        address[] memory multisigMembers = readMultisigMembers();
        GaugeVoterSetup gaugeVoterPluginSetup = deployGaugeVoterPluginSetup();

        parameters = DeploymentParameters({
            daoSubdomain: "",
            daoMetadataURI: "",
            daoExecutor: address(0),
            minApprovals: vm.envUint("MIN_APPROVALS").toUint8(),
            multisigMembers: multisigMembers,
            multisigMetadata: bytes(vm.envString("MULTISIG_METADATA_URI")),
            ivotesSource: vm.envAddress("IVOTES_SOURCE_ADDRESS"),
            votingPaused: vm.envBool("VOTING_PAUSED"),
            multisigPluginRepo: PluginRepo(vm.envAddress("MULTISIG_PLUGIN_REPO_ADDRESS")),
            multisigPluginRelease: vm.envUint("MULTISIG_PLUGIN_RELEASE").toUint8(),
            multisigPluginBuild: vm.envUint("MULTISIG_PLUGIN_BUILD").toUint16(),
            voterPluginSetup: gaugeVoterPluginSetup,
            voterEnsSubdomain: vm.envString("SIMPLE_GAUGE_VOTER_REPO_ENS_SUBDOMAIN"),
            osxDaoFactory: vm.envAddress("DAO_FACTORY"),
            pluginSetupProcessor: PluginSetupProcessor(vm.envAddress("PLUGIN_SETUP_PROCESSOR")),
            pluginRepoFactory: PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY"))
        });
    }

    function readMultisigMembers() public view returns (address[] memory result) {
        string memory membersFilePath = vm.envString("MULTISIG_MEMBERS_JSON_FILE_NAME");
        string memory path = string.concat(vm.projectRoot(), membersFilePath);
        string memory strJson = vm.readFile(path);

        if (!vm.keyExistsJson(strJson, "$.members")) revert EmptyMultisig();

        result = vm.parseJsonAddressArray(strJson, "$.members");
        if (result.length == 0) revert EmptyMultisig();
    }

    function deployGaugeVoterPluginSetup() internal returns (GaugeVoterSetup result) {
        result = new GaugeVoterSetup(address(new GaugeVoter()), address(new Clock()));
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
        console.log("- Gauge voter plugin:", address(deployment.gaugeVoterPluginSet.plugin));
        console.log("  Clock:", address(deployment.gaugeVoterPluginSet.clock));
        console.log("  IVotes source (xCTR GaugeVotes):", deploymentParameters.ivotesSource);
        console.log("");
        console.log("Plugin repositories");
        console.log("- Multisig plugin repository (existing):", address(deploymentParameters.multisigPluginRepo));
        console.log("- Gauge voter plugin repository:", address(deployment.gaugeVoterPluginRepo));
        console.log("");
        console.log("NEXT STEP: Citrea deployer must call");
        console.log(
            "  GaugeVotes(",
            deploymentParameters.ivotesSource,
            ").setGaugeVoter(",
            address(deployment.gaugeVoterPluginSet.plugin)
        );
        console.log(")");
    }
}
