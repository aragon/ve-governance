// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
contract MockERC20Upgradeable is ERC20Upgradeable, UUPSUpgradeable {
    function initialize() external initializer {
        __ERC20_init("TestToken", "TST");
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    // open upgrade
    function _authorizeUpgrade(address newImplementation) internal override {}
}
