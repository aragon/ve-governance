// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {VotingEscrow} from "src/voting/SimpleGaugeVoterSetup.sol";
import {GaugesDaoFactory, GaugePluginSet, Deployment} from "src/factory/GaugesDaoFactory.sol";

contract Router {
    address public escrow;

    constructor(address _escrow) {
        escrow = _escrow;
    }

    function getLocked(uint _tokenId) public view returns (uint256) {
        return VotingEscrow(escrow).locked(_tokenId).amount;
    }

    function getTotalLocked(address _user) public view returns (uint256) {
        uint256[] memory ids = VotingEscrow(escrow).ownedTokens(_user);

        uint256 totalLocked = 0;

        for (uint i = 0; i < ids.length; i++) {
            totalLocked += VotingEscrow(escrow).locked(ids[i]).amount;
        }
        return totalLocked;
    }
}

contract DeployRouter is Script {
    function run() public {
        address factoryAddress = vm.envAddress("FACTORY");
        if (factoryAddress == address(0)) {
            revert("Factory address not set");
        }
        GaugesDaoFactory factory = GaugesDaoFactory(factoryAddress);

        // set our contracts
        Deployment memory deployment = factory.getDeployment();

        // if deploying multiple tokens, you can adjust the index here
        GaugePluginSet memory pluginSet = deployment.gaugeVoterPluginSets[0];

        vm.startBroadcast(vm.envUint("DEPLOYMENT_PRIVATE_KEY"));
        {
            Router router = new Router({_escrow: address(pluginSet.votingEscrow)});
            console.log("Router deployed at:", address(router));
        }
        vm.stopBroadcast();
    }
}
