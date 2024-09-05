// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "forge-std/console2.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// mocks IDAO for the governanceERC20 auth modifier
contract MockDAOSimplePermission {
    function hasPermission(address, address, bytes32, bytes calldata) public pure returns (bool) {
        // always pass
        return true;
    }
}

contract MockDAORevertFallback {
    function hasPermission(address, address, bytes32, bytes calldata) public pure returns (bool) {
        // always pass
        return true;
    }

    fallback() external {
        revert("MockDAORevertFallback");
    }

    receive() external payable {
        revert("MockDAORevertFallback");
    }

    function gimme() public payable {
        // do nothing but accept ether
    }
}

/// @notice creates an actual DAO behind a basic proxy for testing
/// @param _initialOwner The initial owner of the DAO having the `ROOT_PERMISSION_ID` permission.
function createTestDAO(address _initialOwner) returns (DAO) {
    DAO _dao = DAO(payable(new ERC1967Proxy(address(new DAO()), bytes(""))));
    string memory _daoURI = "ipfs://";
    _dao.initialize({
        _metadata: bytes(""),
        _initialOwner: _initialOwner,
        _trustedForwarder: address(0),
        daoURI_: _daoURI
    });
    return _dao;
}

function createTestDAORevertFallback() returns (MockDAORevertFallback) {
    return new MockDAORevertFallback();
}
