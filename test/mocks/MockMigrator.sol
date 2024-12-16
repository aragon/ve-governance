pragma solidity ^0.8.0;

import {IMigrateableTo} from "@escrow-interfaces/IMigrateable.sol";

contract MockMigrator is IMigrateableTo {
    uint public received;
    function migrateTo(uint256 _value, address _for) public override returns (uint256 newTokenId) {
        return ++received;
    }
}
