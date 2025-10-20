// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {
    VotingEscrow,
    Clock,
    Lock,
    Curve,
    ExitQueue,
    EscrowIVotesAdapter,
    GaugeVoter,
    GaugeVoterPluginSetup,
    IGaugeVoterPluginSetupParams
} from "@setup/GaugeVoterPluginSetup.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/Executor.sol";
import {IPluginRepo, PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {IMultisig} from "@aragon/multisig/src/IMultisig.sol";

struct ScriptParameters {
    PluginRepo pluginRepo;
    string releaseMetadata;
    string buildMetadata;
    IMultisig proposalTargetPlugin;
    string proposalMetadataUri;
}

/// @author Aragon X 2025, v1.5.0
/// @notice This script deploys a new plugin setup publishes it to the given plugin repo
contract DeployNewVersion is Script {
    uint8 constant RELEASE = 1;

    ScriptParameters params;
    GaugeVoterPluginSetup pluginSetup;

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

        // Done
        printDeployment();

        if (!vm.envOr("SIMULATION", false)) {
            writeJsonArtifacts();

            printUpgradeProposalCommand();
        }
    }

    function getScriptParameters() internal view returns (ScriptParameters memory) {
        return ScriptParameters({
            pluginRepo: PluginRepo(vm.envAddress("PLUGIN_REPO")),
            releaseMetadata: vm.envOr("RELEASE_METADATA_URI", string(" ")),
            buildMetadata: vm.envOr("BUILD_METADATA_URI", string(" ")),
            proposalTargetPlugin: IMultisig(vm.envAddress("PROPOSAL_TARGET_PLUGIN")),
            proposalMetadataUri: bytes(vm.envString("PROPOSAL_METADATA_URI"))
        });
    }

    function deployPluginSetup() internal returns (GaugeVoterPluginSetup result) {
        result = new GaugeVoterPluginSetup(
            address(new GaugeVoter()),
            address(new Curve()),
            address(new ExitQueue()),
            address(new VotingEscrow()),
            address(new Clock()),
            address(new Lock()),
            address(new EscrowIVotesAdapter())
        );
    }

    function printDeployment() internal view {
        console.log("Chain ID:", block.chainid);
        console.log("");

        console.log("- Plugin setup:     ", address(pluginSetup));
    }

    function writeJsonArtifacts() internal {
        string memory artifacts = "main";
        vm.serializeAddress(artifacts, "pluginRepo", address(params.pluginRepo));
        vm.serializeAddress(artifacts, "pluginSetup", address(pluginSetup));

        string memory proposal = "createVersionProposal";
        vm.serializeAddress(proposal, "proposalPlugin", address(params.proposalTargetPlugin));
        vm.serializeAddress(proposal, "proposalMetadataUri", address(params.proposalMetadataUri));

        string memory finalJson = vm.serializeString(artifacts, "createVersionProposal", proposal);

        string memory networkName = vm.envString("NETWORK_NAME");
        string memory filePath = string.concat(
            vm.projectRoot(), "/artifacts/deployment-", networkName, "-", vm.toString(block.timestamp), ".json"
        );
        vm.writeJson(finalJson, filePath);

        console.log("Deployment artifacts written to", filePath);
    }

    function printUpgradeProposalCommand() internal {
        bytes memory actionData = abi.encodeCall(
            IPluginRepo.createVersion,
            (RELEASE, address(pluginSetup), params.buildMetadataUri, params.releaseMetadataUri)
        );

        Action[] memory actions = new Action[](1);
        actions[0].to = address(params.pluginRepo);
        actions[0].data = actionData;
        uint64 expirationDate = uint64(vm.envUint("TIMESTAMP")) + 3 weeks;
        bytes memory createProposalData = abi.encodeCall(
            IMultisig.createProposal, (params.proposalMetadataUri, actions, 0, true, false, 0, expirationDate)
        );

        console.log("Proposal details:");
        console.log("- Proposal on plugin:        ", address(params.proposalTargetPlugin), " (Multisig)");
        console.log("- Action[0].to:              ", address(params.pluginRepo), " (plugin repo)");
        console.log("- Action[0].data:            ", vm.toString(actionData));
        console.log("");
        console.log("Action signature:");
        console.log("- createVersion(uint8 release, address pluginSetup, bytes buildMetadata, bytes releaseMetadata)");
        console.log("");
        console.log("");
        console.log("Creating the proposal with Foundry");
        console.log("");
        console.log("Function signature:");
        console.log(
            "- createProposal(bytes calldata _metadata, Action[] calldata _actions, uint256 _allowFailureMap, bool _approveProposal, bool _tryExecution, uint64 _startDate, uint64 _endDate)"
        );
        console.log("");
        console.log("$ export FROM_ADDRESS=<your-address>");
        console.log("$ export RPC_URL='https://chain-name-here.drpc.org'");
        console.log("");
        console.log("$ export WALLET_TYPE=\"--trezor\"   (Set the appropriate value)");
        console.log("$ export WALLET_TYPE=\"--ledger\"");
        console.log("");
        console.log(
            "$ cast send $WALLET_TYPE --from $FROM_ADDRESS --rpc-url $RPC_URL",
            vm.toString(address(params.proposalTargetPlugin)),
            vm.toString(createProposalData)
        );
        console.log("");
        console.log("The transaction can be verified via `cast 4byte-decode <data>`");
        console.log("");
    }
}
