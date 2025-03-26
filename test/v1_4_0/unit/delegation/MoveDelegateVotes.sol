pragma solidity ^0.8.17;

import {Base} from "./Base.sol";

import {Lock, Clock, VotingEscrow, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, IEscrowCurveTokenStorage, IGaugeVote} from "../../versions.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {createTestDAO} from "@mocks/MockDAO.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";

import {DelegationMapper} from "@delegation/DelegationMapper.sol";
import {IDelegationMapper} from "@delegation/IDelegationMapper.sol";

contract MoveDelegateVotes is Base {
    function setUp() public override {
        super.setUp();
    }

    function test_Reverts_IfSenderIsNotEscrow() public {
        vm.expectRevert(IDelegationMapper.OnlyEscrow.selector);
        dg.moveDelegateVotes(address(1), address(2), 1);
    }

    function test_RemoveDelegateeAndBalance_After_Token_Transfer() public {
        escrow.write(ids[0], 14);
        escrow.write(ids[1], 15);
        escrow.write(ids[2], 16);

        // Alice is delegatee
        dg.delegate(ids, alice);

        vm.warp(block.timestamp + 10);
        uint256 tokenTransferTs = block.timestamp;

        vm.prank(address(escrow));
        dg.moveDelegateVotes(alice, bob, ids[0]);

        // Alice is not delegatee anymore for tokenId = ids[0]
        assertDelegate(ids[0], block.timestamp, address(0));

        // Alice is still delegatee for ids[1] and ids[2]
        assertDelegate(ids[1], block.timestamp, alice);
        assertDelegate(ids[2], block.timestamp, alice);

        assertEq(dg.getDelegationBalance(alice, block.timestamp), 15 + 16);

        // for the timestamp before token transfer, alice still should be delegatee.
        assertDelegate(ids[0], tokenTransferTs - 1, alice);
    }
}
