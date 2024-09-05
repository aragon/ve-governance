// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

contract TestHelpers is Test {
    address constant OSX_ANY_ADDR = address(type(uint160).max);

    bytes ownableError = "Ownable: caller is not the owner";
    bytes initializableError = "Initializable: contract is already initialized";
}
