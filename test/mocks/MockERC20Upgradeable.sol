// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";

contract MockERC20Upgradeable is ERC20Upgradeable {
    function initialize() public initializer {
        __ERC20_init("MockERC20Upgradeable", "MERCU");
    }
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockERC20Votes is ERC20VotesUpgradeable {
    function initialize() public initializer {
        __ERC20_init("votes", "V");
        __ERC20Permit_init("votes");
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function clock() public view virtual override returns (uint48) {
        return SafeCastUpgradeable.toUint48(block.timestamp);
    }

    // The following functions are
    function CLOCK_MODE() public view virtual override returns (string memory) {
        // Check that the clock was not modified
        require(clock() == block.timestamp, "ERC20Votes: broken clock mode");
        return "mode=timestamp&from=default";
    }
}
