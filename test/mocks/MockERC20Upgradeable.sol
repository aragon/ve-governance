// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract MockERC20Upgradeable is ERC20Upgradeable {
    function initialize() external initializer {
        __ERC20_init("TestToken", "TST");
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
