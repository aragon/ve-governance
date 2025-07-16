// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract MockERC20 is ERC20("MockERC20", "MERC") {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockERC20Votes is ERC20Votes {
    constructor() ERC20("votes", "V") ERC20Permit("votes") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    

    function clock() public view virtual override returns (uint48) {
        return SafeCast.toUint48(block.timestamp);
    }

    // The following functions are 
    function CLOCK_MODE() public view virtual override returns (string memory) {
        // Check that the clock was not modified
        require(clock() == block.timestamp, "ERC20Votes: broken clock mode");
        return "mode=timestamp&from=default";
    }
}
