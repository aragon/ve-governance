pragma solidity ^0.8.17;

import {Base} from "./Base.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {console2 as console} from "forge-std/console2.sol";

contract TestReDelegate is Base {
    function setUp() public override {
        super.setUp();
    }

    event DelegateChanged(address indexed from, address indexed to, address indexed delegate);

    function test_shouldRevertIfPaused() public {
        dg.pause();

        vm.expectRevert("Pausable: paused");
        dg.redelegate(address(1));
    }

    function test_UndelegatesAndDelegatesToNewAddress() public {
        // Mock tokenIds 1|2|3 with their voting power 
        // and locked amounts  and attach to `sender`.
        address sender = address(this);

        uint256[] memory ownedTokens = new uint256[](3);
        ownedTokens[0] = 1;
        ownedTokens[1] = 2;
        ownedTokens[2] = 3;

        _mockOwnedTokens(sender, ownedTokens);
        _mockLocked(ownedTokens[0], 101, weekStartTs(block.timestamp));
        _mockLocked(ownedTokens[1], 102, weekStartTs(block.timestamp));
        _mockLocked(ownedTokens[2], 103, weekStartTs(block.timestamp));
        _mockVotingPower(ownedTokens[0], 1);
        _mockVotingPower(ownedTokens[1], 1);
        _mockVotingPower(ownedTokens[2], 1);

        uint256[] memory delegatedIds = new uint256[](2);
        delegatedIds[0] = 2;
        delegatedIds[1] = 3;

        // only delegate 2 and 3 tokenIds to alice.
        dg.setAutoDelegationDisabled(true);
        dg.delegate(alice);
        dg.delegate(delegatedIds);
        assertEq(dg.numberOfDelegatedTokens(sender), 2);

        // turn on auto delegation, so when redelegate is called,
        // it should undelegate 2 and 3 tokenIds from alice and
        // delegate all ownedTokens(1, 2, 3) to Bob.
        dg.setAutoDelegationDisabled(false);
        dg.redelegate(bob);

        assertEq(dg.delegates(sender), bob);
        assertEq(dg.numberOfDelegatedTokens(sender), 3);

        assertEq(dg.getVotes(alice), 0);

        uint256 expectedVPBob = bias(101, block.timestamp - weekStartTs(block.timestamp)) +
            bias(102, block.timestamp - weekStartTs(block.timestamp)) +
            bias(103, block.timestamp - weekStartTs(block.timestamp));

        assertEq(dg.getVotes(bob), expectedVPBob);
    }
}
