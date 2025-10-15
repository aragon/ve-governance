// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {
    VotingEscrow,
    Clock,
    Lock,
    Curve,
    ExitQueue,
    EscrowIVotesAdapter,
    GaugeVoter,
    GaugeVoterSetupV1_4_0 as GaugeVoterSetup,
    IGaugeVoterSetupParams
} from "@setup/GaugeVoterSetup_v1_4_0.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {CurveConstantLib} from "@libs/CurveConstantLib.sol";

struct ScriptParameters {
    address pluginRepoMaintainer;
    string pluginRepoEnsSubdomain;
    address pluginRepoFactory;
    string releaseMetadata;
    string buildMetadata;
}

contract DeployGaugesPluginSetup_v1_4_0 is Script {
    using SafeCast for uint256;

    ScriptParameters params;
    GaugeVoterSetup pluginSetup;
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
    }

    function getScriptParameters() internal view returns (ScriptParameters memory) {
        return
            ScriptParameters({
                pluginRepoMaintainer: vm.envAddress("PLUGIN_REPO_MAINTAINER"),
                pluginRepoEnsSubdomain: vm.envOr("PLUGIN_REPO_ENS_SUBDOMAIN", string("")),
                pluginRepoFactory: vm.envAddress("PLUGIN_REPO_FACTORY"),
                releaseMetadata: vm.envOr("RELEASE_METADATA_URI", string(" ")),
                buildMetadata: vm.envOr("BUILD_METADATA_URI", string(" "))
            });
    }

    function deployPluginSetup() internal returns (GaugeVoterSetup result) {
        (int256[3] memory coefficients, uint256 maxEpoch) = CurveConstantLib.getCoefficients();
        result = new GaugeVoterSetup(
            address(new GaugeVoter()),
            address(new Curve(coefficients, maxEpoch)),
            address(new ExitQueue()),
            address(new VotingEscrow()),
            address(new Clock()),
            address(new Lock()),
            address(new EscrowIVotesAdapter(coefficients, maxEpoch))
        );
    }

    function preparePluginRepo(address maintainer) internal returns (PluginRepo) {
        // Use a random value if empty
        if (bytes(params.pluginRepoEnsSubdomain).length == 0) {
            params.pluginRepoEnsSubdomain = string.concat(
                "ve-governance-",
                vm.toString(block.timestamp)
            );
        }

        // Publish repo
        return
            PluginRepoFactory(params.pluginRepoFactory).createPluginRepoWithFirstVersion(
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
        console.log(
            "  - ENS:            ",
            string.concat(params.pluginRepoEnsSubdomain, ".plugin.dao.eth")
        );
        console.log("  - Maintainer:     ", address(params.pluginRepoMaintainer));
        console.log("- Plugin setup:     ", address(pluginSetup));
    }
}
