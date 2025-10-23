// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {
    VotingEscrow,
    Clock,
    Lock,
    Curve,
    ExitQueue,
    EscrowIVotesAdapter,
    GaugeVoter,
    GaugeVoterSetup_v1_5_0 as GaugeVoterPluginSetup,
    IGaugeVoterPluginSetupParams
} from "@setup/GaugeVoterSetup_v1_5_0.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";

struct ScriptParameters {
    address pluginRepoMaintainer;
    string pluginRepoEnsSubdomain;
    address pluginRepoFactory;
    string releaseMetadata;
    string buildMetadata;
}

/// @author Aragon X 2025, v1.5.0
/// @notice This script deploys a new plugin repo and publishes the current PluginSetup
contract DeployPluginRepo_v1_5_0 is Script {
    ScriptParameters params;
    GaugeVoterPluginSetup pluginSetup;
    PluginRepo pluginRepo;

    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("Deploying from:", vm.addr(privKey));
        console.log("");

        _;

        vm.stopBroadcast();
    }

    /// @notice Runs the deployment flow, records the given parameters and artifacts, and it becomes read only
    function run() public broadcast {
        // Read parameters
        params = getScriptParameters();

        // Deploy
        pluginSetup = deployPluginSetup();
        pluginRepo = preparePluginRepo(params.pluginRepoMaintainer);

        // Done
        printDeploymentSummary();

        if (!vm.envOr("SIMULATION", false)) {
            writeJsonArtifacts();
        }
    }

    function getScriptParameters() internal view returns (ScriptParameters memory) {
        return ScriptParameters({
            pluginRepoMaintainer: vm.envAddress("PLUGIN_REPO_MAINTAINER"),
            pluginRepoEnsSubdomain: vm.envOr("PLUGIN_REPO_ENS_SUBDOMAIN", string("")),
            pluginRepoFactory: vm.envAddress("PLUGIN_REPO_FACTORY"),
            releaseMetadata: vm.envOr("RELEASE_METADATA_URI", string(" ")),
            buildMetadata: vm.envOr("BUILD_METADATA_URI", string(" "))
        });
    }

    function deployPluginSetup() internal returns (GaugeVoterPluginSetup result) {
        result = new GaugeVoterPluginSetup(
            address(new GaugeVoter()),
            address(new ExitQueue()),
            address(new VotingEscrow()),
            address(new Clock()),
            address(new Lock())
        );
    }

    function preparePluginRepo(address maintainer) internal returns (PluginRepo) {
        // Use a random value if empty
        if (bytes(params.pluginRepoEnsSubdomain).length == 0) {
            params.pluginRepoEnsSubdomain = string.concat("ve-governance-", vm.toString(block.timestamp));
        }

        // Publish version
        return PluginRepoFactory(params.pluginRepoFactory).createPluginRepoWithFirstVersion(
            params.pluginRepoEnsSubdomain,
            address(pluginSetup),
            maintainer,
            bytes(params.releaseMetadata),
            bytes(params.buildMetadata)
        );
    }

    function printDeploymentSummary() internal view {
        console.log("Chain ID:", block.chainid);
        console.log("");

        console.log("- Plugin repository:", address(pluginRepo));
        console.log("  - ENS:            ", string.concat(params.pluginRepoEnsSubdomain, ".plugin.dao.eth"));
        console.log("  - Maintainer:     ", address(params.pluginRepoMaintainer));
        console.log("- Plugin setup:     ", address(pluginSetup));
    }

    function writeJsonArtifacts() internal {
        string memory artifacts = "output";
        vm.serializeAddress(artifacts, "pluginRepo", address(pluginRepo));
        vm.serializeString(artifacts, "pluginRepoEns", string.concat(params.pluginRepoEnsSubdomain, ".plugin.dao.eth"));
        vm.serializeAddress(artifacts, "pluginRepoMaintainer", address(params.pluginRepoMaintainer));
        string memory finalJson = vm.serializeAddress(artifacts, "pluginSetup", address(pluginSetup));

        string memory networkName = vm.envString("NETWORK_NAME");
        string memory filePath = string.concat(
            vm.projectRoot(), "/artifacts/deployment-", networkName, "-", vm.toString(block.timestamp), ".json"
        );
        vm.writeJson(finalJson, filePath);

        console.log("Deployment artifacts written to", filePath);
    }
}
