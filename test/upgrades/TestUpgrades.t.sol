// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {AragonTest} from "../base/AragonTest.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/LegacyUpgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

contract TestUpgrades is AragonTest {
    function testValidateUpgrades() public {
        Options memory options;
        options.referenceBuildInfoDir = "ref_builds/build-info-v101";

        options.referenceContract = "build-info-v101:Lock";
        Upgrades.validateUpgrade("Lock.sol", options);

        options.referenceContract = "build-info-v101:VotingEscrow";
        Upgrades.validateUpgrade("VotingEscrow.sol", options);

        options.referenceContract = "build-info-v101:SimpleGaugeVoter";
        Upgrades.validateUpgrade("SimpleGaugeVoter.sol", options);

        options.referenceContract = "build-info-v101:QuadraticIncreasingEscrow";
        Upgrades.validateUpgrade("QuadraticIncreasingEscrow.sol", options);

        options.referenceContract = "build-info-v101:ExitQueue";
        Upgrades.validateUpgrade("ExitQueue.sol", options);

        options.referenceContract = "build-info-v101:Clock";
        Upgrades.validateUpgrade("Clock.sol", options);
    }
}
