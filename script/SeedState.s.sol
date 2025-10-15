// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {
    GaugePluginSet,
    GaugesDaoFactory,
    DeploymentParameters,
    Deployment,
    TokenParameters
} from "@factory/GaugesDaoFactory.sol";
import {
    VotingEscrow,
    Clock,
    Lock,
    Curve,
    ExitQueue,
    GaugeVoter,
    GaugeVoterSetup,
    IGaugeVoterSetupParams
} from "@setup/GaugeVoterSetup.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

contract SeedState is Script {
    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("Deploying from:", vm.addr(privKey));

        _;

        vm.stopBroadcast();
    }

    /// @notice Runs the deployment flow, records the given parameters and artifacts, and it becomes read only
    function run() public broadcast {
        // fetch deploy
        address factoryAddress = vm.envAddress("VE_FACTORY_ADDRESS");
        GaugesDaoFactory factory = GaugesDaoFactory(factoryAddress);
        Deployment memory deployment = factory.getDeployment();
        GaugePluginSet memory modePluginSet = deployment.gaugeVoterPluginSets[0];
        GaugePluginSet memory bptPluginSet = deployment.gaugeVoterPluginSets[1];

        VotingEscrow modeEscrow = VotingEscrow(modePluginSet.votingEscrow);
        VotingEscrow bptEscrow = VotingEscrow(bptPluginSet.votingEscrow);
        MockERC20 mockMode = MockERC20(modeEscrow.token());
        MockERC20 mockBpt = MockERC20(bptEscrow.token());

        // get members
        address[] memory members = readMultisigMembers();

        // mint sender 1m * members length of each token
        address sender = vm.addr(vm.envUint("DEPLOYMENT_PRIVATE_KEY"));
        uint mint = 1_000_000e18;
        mockMode.mint(sender, mint * members.length);
        mockBpt.mint(sender, mint * members.length);

        // mint stake on behalf
        mockMode.approve(address(modeEscrow), type(uint256).max);
        mockBpt.approve(address(bptEscrow), type(uint256).max);

        for (uint i = 0; i < members.length; i++) {
            mockMode.mint(members[i], mint);
            mockBpt.mint(members[i], mint);
            for (uint j = 0; j < 3; j++) {
                modeEscrow.createLockFor(mint / 3, members[i]);
                bptEscrow.createLockFor(mint / 3, members[i]);
            }
        }
    }

    function readMultisigMembers() public view returns (address[] memory result) {
        // JSON list of members
        string memory membersFilePath = vm.envString("MULTISIG_MEMBERS_JSON_FILE_NAME");
        string memory path = string.concat(vm.projectRoot(), membersFilePath);
        string memory strJson = vm.readFile(path);
        result = vm.parseJsonAddressArray(strJson, "$.members");

        if (result.length == 0) revert("EmptyMultisigMembers");
    }
}
