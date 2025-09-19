// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

/// @title MockDAORegistry
contract MockDAORegistry {
    function register(IDAO dao, address creator, string calldata subdomain) public {}
}
