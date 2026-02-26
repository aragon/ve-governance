// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console2 as console} from "forge-std/console2.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {EscrowIVotesAdapter} from "@delegation/EscrowIVotesAdapter.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import {BaseScript} from "./BaseScript.sol";
import { UpgradeIVotesAdapterActions } from "./UpgradeIVotesAdapterActions.s.sol";

/// @title UpgradeEscrowIVotesAdapter
contract VerifyIVotesAdapterUpgrade is BaseScript {
    function run() public {
        EscrowIVotesAdapter proxy = EscrowIVotesAdapter(ESCROW_IVOTES_ADAPTER);

        address oldImpl = proxy.implementation();
        require(oldImpl != address(0), "Old impl is zero");

        // Get current state from proxy before upgrading
        int256 constantCoefficient = proxy.SHARED_CONSTANT_COEFFICIENT();
        int256 linearCoefficient = proxy.SHARED_LINEAR_COEFFICIENT();
        int256 quadraticCoefficient = proxy.SHARED_QUADRATIC_COEFFICIENT();
        uint256 maxEpochs = proxy.MAX_EPOCHS();
        IDAO dao = proxy.dao();
        address escrow = proxy.escrow();
        address clock = proxy.escrowClock();
        bool paused = proxy.paused();
        uint256 maxTime = uint256(vm.load(address(proxy), bytes32(uint256(357)))); // (use `forge inspect EscrowIVotesAdapter storage`)
        
        (Action[] memory actions, address newImplAddr) = (new UpgradeIVotesAdapterActions()).generateActions();
        // automatically disables initializer.
        require(uint256(vm.load(newImplAddr, bytes32(uint256(0)))) != 0);

        createProposalViaAragonMultisig("upgrade-ivotes-adapter", actions);

        // Verify state is preserved after upgrade
        require(proxy.SHARED_CONSTANT_COEFFICIENT() == constantCoefficient);
        require(proxy.SHARED_LINEAR_COEFFICIENT() == linearCoefficient);
        require(proxy.SHARED_QUADRATIC_COEFFICIENT() == quadraticCoefficient);
        require(proxy.MAX_EPOCHS() == maxEpochs);
        require(proxy.dao() == dao);
        require(proxy.escrow() == escrow);
        require(proxy.escrowClock() == clock);
        require(proxy.paused() == paused);
        require(uint256(vm.load(address(proxy), bytes32(uint256(357)))) == maxTime);
        require(uint256(vm.load(address(proxy), bytes32(uint256(0)))) != 0);
        require(proxy.implementation() == newImplAddr);

        // Verify that initialize cannot be called again on the proxy
        try proxy.initialize(address(dao), escrow, clock, false) {
            revert("Initialize should have reverted");
        } catch (bytes memory reason) {
            require(
                keccak256(reason) == keccak256(abi.encodeWithSignature("Error(string)", "Initializable: contract is already initialized")),
                "Unexpected revert reason on proxy"
            );
        }

        // Verify that initialize cannot be called on the implementation
        try EscrowIVotesAdapter(newImplAddr).initialize(address(dao), escrow, clock, false) {
            revert("Initialize on impl should have reverted");
        } catch (bytes memory reason) {
            require(
                keccak256(reason) == keccak256(abi.encodeWithSignature("Error(string)", "Initializable: contract is already initialized")),
                "Unexpected revert reason on impl"
            );
        }

        console.log("Upgrade successful!");
        console.log("New implementation:", newImplAddr);
    }
}
