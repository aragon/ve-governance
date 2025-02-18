// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {AragonTest} from "../../base/AragonTest.sol";

import {Upgrades} from "@foundry-upgrades/LegacyUpgrades.sol";
import {Options} from "@foundry-upgrades/Options.sol";

contract TestUpgrades is AragonTest {
    function testValidateUpgradeGaugeVoter__v1_0_0__v1_1_0() public {
        Options memory options;

        string[] memory exclude = new string[](1);
        // disable initializers is invoked but the custom unsafe allow option is not set in the natspec
        exclude[0] = "lib/osx/packages/contracts/src/core/plugin/PluginUUPSUpgradeable.sol";
        options.exclude = exclude;

        options.referenceContract = "SimpleGaugeVoter.sol";
        Upgrades.validateUpgrade("SimpleGaugeVoter_v1_1_0.sol:SimpleGaugeVoterV1_1_0", options);
    }
}
