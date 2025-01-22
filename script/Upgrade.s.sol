// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import {Multisig} from "@aragon/multisig/Multisig.sol";
import {VotingEscrow, Lock, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, ISimpleGaugeVoterSetupParams} from "src/voting/SimpleGaugeVoterSetup.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {GaugesDaoFactory, GaugePluginSet, DeploymentParameters, Deployment, TokenParameters, DAO} from "src/factory/GaugesDaoFactory.sol";
import {TestUpgradeToV110} from "test/fork/upgradeViaMultisig.t.sol";

contract UpgradeToV110 is Script, TestUpgradeToV110 {
    function run() public {
        setModeSigners();

        address signer = vm.envAddress("SIGNER_ADDRESS");
        bool tryExecute = vm.envBool("TRY_EXECUTE");
        string memory network = vm.envString("NETWORK");
        _retrieveDeployment(vm.envAddress("FACTORY_ADDRESS"));

        uint proposalId;
        vm.startBroadcast(signer);
        {
            IDAO.Action[] memory actions = buildActions();
            if (isMainnet(network)) {
                proposalId = _createAragonMsigProposal(actions);
            } else if (isTestnet(network)) {
                proposalId = _buildMsigProposal(
                    actions,
                    modeSigners,
                    modeMultisig,
                    vm.envOr("TRY_EXECUTE", false)
                );
            } else {
                revert("Invalid network");
            }
        }
        vm.stopBroadcast();
        console.log("Proposal ID: ", proposalId);
    }
}
