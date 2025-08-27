// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console2 as console} from "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {GaugesDaoFactory, DeploymentParameters} from "@factory/GaugesDaoFactory.sol";

contract GetFactoryValues is Script {
    GaugesDaoFactory public factory;

    function run() public {
        factory = GaugesDaoFactory(vm.envAddress("FACTORY_ADDRESS"));

        console.log("Deployment address (and implementation):");
        console.log(
            "  - DAO: %s (%s)",
            address(factory.getDeployment().dao),
            address(factory.getDeployment().dao)
        );
        console.log(
            "  - Multisig: %s (%s)",
            address(factory.getDeployment().multisigPlugin),
            address(factory.getDeployment().multisigPlugin.implementation())
        );
        console.log(
            "  - GaugeVoterPluginRepo: %s",
            address(factory.getDeployment().gaugeVoterPluginRepo)
        );
        console.log(
            "  - GaugeVoterPluginSets: %s",
            factory.getDeployment().gaugeVoterPluginSets.length
        );

        for (uint i; i < factory.getDeployment().gaugeVoterPluginSets.length; i++) {
            console.log("    - GaugePluginSet %s", i);
            console.log(
                "      - SimpleGaugeVoter: %s (%s)",
                address(factory.getDeployment().gaugeVoterPluginSets[i].plugin),
                address(factory.getDeployment().gaugeVoterPluginSets[i].plugin.implementation())
            );
            console.log(
                "      - QuadraticIncreasingEscrow: %s (%s)",
                address(factory.getDeployment().gaugeVoterPluginSets[i].curve),
                address(factory.getDeployment().gaugeVoterPluginSets[i].curve.implementation())
            );
            console.log(
                "      - ExitQueue: %s (%s)",
                address(factory.getDeployment().gaugeVoterPluginSets[i].exitQueue),
                address(factory.getDeployment().gaugeVoterPluginSets[i].exitQueue.implementation())
            );
            console.log(
                "      - VotingEscrow: %s (%s)",
                address(factory.getDeployment().gaugeVoterPluginSets[i].votingEscrow),
                address(
                    factory.getDeployment().gaugeVoterPluginSets[i].votingEscrow.implementation()
                )
            );
            console.log(
                "      - Clock: %s (%s)",
                address(factory.getDeployment().gaugeVoterPluginSets[i].clock),
                address(factory.getDeployment().gaugeVoterPluginSets[i].clock.implementation())
            );
            console.log(
                "      - Lock: %s (%s)",
                address(factory.getDeployment().gaugeVoterPluginSets[i].nftLock),
                address(factory.getDeployment().gaugeVoterPluginSets[i].nftLock.implementation())
            );
        }

        console.log("Deployment parameters:");
        DeploymentParameters memory params = factory.getDeploymentParameters();
        console.log("  - MinApprovals: %d", params.minApprovals);
        console.log("  - MultisigMembers:");
        for (uint i = 0; i < params.multisigMembers.length; i++) {
            console.log("      -", params.multisigMembers[i]);
        }
        console.log("  - TokenParameters:");
        for (uint i = 0; i < params.tokenParameters.length; i++) {
            console.log(
                "      - Token: %s [%s] (%s)",
                params.tokenParameters[i].veTokenName,
                params.tokenParameters[i].veTokenSymbol,
                params.tokenParameters[i].token
            );
        }
        console.log("  - FeePercent: %d", params.feePercent);
        console.log("  - WarmupPeriod: %d", params.warmupPeriod);
        console.log("  - CooldownPeriod: %d", params.cooldownPeriod);
        console.log("  - MinLockDuration: %d", params.minLockDuration);
        console.log("  - VotingPaused: %d", params.votingPaused);
        console.log("  - MinDeposit: %d", params.minDeposit);
        console.log(
            "  - MultisigPluginRepo: %s",
            address(params.multisigPluginRepo)
        );
        console.log(
            "  - MultisigPluginRelease: %s",
            factory.getDeploymentParameters().multisigPluginRelease
        );
        console.log(
            "  - MultisigPluginBuild: %s",
            factory.getDeploymentParameters().multisigPluginBuild
        );
        console.log(
            "  - VoterPluginSetup: %s",
            address(factory.getDeploymentParameters().voterPluginSetup)
        );
        console.log(
            "  - VoterEnsSubdomain: %s",
            factory.getDeploymentParameters().voterEnsSubdomain
        );
        console.log("  - OSxDaoFactory: %s", factory.getDeploymentParameters().osxDaoFactory);
        console.log(
            "  - PluginSetupProcessor: %s",
            address(factory.getDeploymentParameters().pluginSetupProcessor)
        );
        console.log(
            "  - PluginRepoFactory: %s",
            address(factory.getDeploymentParameters().pluginRepoFactory)
        );
    }
}
