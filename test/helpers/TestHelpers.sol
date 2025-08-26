// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {DAO} from "@mocks/MockDAO.sol";

import {createTestDAO} from "@mocks/MockDAO.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

contract TestHelpers is Test {
    using ProxyLib for address;

    DAO dao;

    address constant OSX_ANY_ADDR = address(type(uint160).max);

    bytes ownableError = "Ownable: caller is not the owner";
    bytes initializableError = "Initializable: contract is already initialized";

    function setUp() public virtual {
        dao = createTestDAO(address(this));
    }

    function _authErr(
        address _caller,
        address _contract,
        bytes32 _perm
    ) internal view returns (bytes memory) {
        return
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                _contract,
                _caller,
                _perm
            );
    }
}
