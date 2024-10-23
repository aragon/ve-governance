/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console2 as console} from "forge-std/Script.sol";

import {StakeInspector} from "src/helpers/StakeInspector.sol";

contract DeployStakeInspector is Script {
    address escrowMode = 0xff8AB822b8A853b01F9a9E9465321d6Fe77c9D2F;
    address escrowBPT = 0x9c2eFe2a1FBfb601125Bb07a3D5bC6EC91F91e01;

    function run() public {
        vm.startBroadcast(vm.addr(vm.envUint("DEPLOYMENT_PRIVATE_KEY")));
        StakeInspector stakeInspectorMode = new StakeInspector(escrowMode);
        StakeInspector stakeInspectorBPT = new StakeInspector(escrowBPT);

        vm.stopBroadcast();
        console.log("StakeInspector for Mode deployed at: ", address(stakeInspectorMode));
        console.log("StakeInspector for BPT deployed at: ", address(stakeInspectorBPT));
    }
}
