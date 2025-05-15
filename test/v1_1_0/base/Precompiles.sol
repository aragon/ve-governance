// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

contract Precompiles {
    address public constant TRANSFER = address(0xff - 2);
}
