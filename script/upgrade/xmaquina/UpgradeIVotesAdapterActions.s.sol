// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { console2 as console } from "forge-std/Script.sol";

import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { BaseScript } from "./BaseScript.sol";
import { EscrowIVotesAdapter } from "@delegation/EscrowIVotesAdapter.sol";

contract UpgradeIVotesAdapterActions is BaseScript {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");

    function run() public returns (Action[] memory actions, address newImpl) {
        return generateActions();
    }

    function generateActions() public returns (Action[] memory, address newImpl) {
        EscrowIVotesAdapter proxy = EscrowIVotesAdapter(ESCROW_IVOTES_ADAPTER);

        int256 constantCoefficient = proxy.SHARED_CONSTANT_COEFFICIENT();
        int256 linearCoefficient = proxy.SHARED_LINEAR_COEFFICIENT();
        int256 quadraticCoefficient = proxy.SHARED_QUADRATIC_COEFFICIENT();
        uint256 maxEpochs = proxy.MAX_EPOCHS();

        int256[3] memory coefficients;
        coefficients[0] = constantCoefficient;
        coefficients[1] = linearCoefficient;
        coefficients[2] = quadraticCoefficient;

        vm.startBroadcast(deployerPrivateKey);
        newImpl = address(new EscrowIVotesAdapter(coefficients, maxEpochs));
        vm.stopBroadcast();

        Action[] memory actions = new Action[](1);

        // Action 0: Upgrade IVotesAdapter to new implementation
        actions[0] = Action({
            to: ESCROW_IVOTES_ADAPTER,
            value: 0,
            data: abi.encodeWithSignature("upgradeTo(address)", newImpl)
        });

        bytes memory proposalData = createProposalData(
            hex"697066733a2f2f6261666b726569636c78716c667237723737356237706272726568686e666769766435356d646c6470366c756577326d6d6566686f617a616d696d",
            actions
        );

        Action[] memory wrapperAction = new Action[](1);
        wrapperAction[0] = Action({
            to: MULTISIG_PLUGIN,
            value: 0,
            data: proposalData
        });

        // Serialize and write to JSON file
        string memory actionsJson = _serializeActions(wrapperAction);
        string memory outputPath = string.concat("./script/upgrade/xmaquina/upgrade-", network, ".json");
        vm.writeJson(actionsJson, outputPath);

        console.log("new Implementation: ", newImpl);
        console.log("actions file:", outputPath);

        return (wrapperAction, newImpl);
    }
}
