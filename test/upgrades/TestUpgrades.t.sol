// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Upgrades} from "openzeppelin-foundry-upgrades/LegacyUpgrades.sol";
import {Test} from "forge-std/Test.sol";
//import {Clock} from '@aragon/ve-governance-v101/clock/Clock.sol';
//import {Clock as ClockV2} from '@clock/Clock.sol';

import { Options } from "openzeppelin-foundry-upgrades/Options.sol";

contract AragonTest is Test {
    function testUpgrades() public {
        //Clock clock = new Clock();

        Options memory options;
        options.referenceBuildInfoDir = "ref_builds/build-info-v101";
        options.referenceContract = "build-info-v101:Clock";
        
        Upgrades.validateUpgrade("Clock.sol", options);
    }
}
