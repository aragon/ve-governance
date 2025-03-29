pragma solidity ^0.8.17;

import {Base} from "./Base.sol";

import {Lock, Clock, VotingEscrow, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, IEscrowCurveTokenStorage, IGaugeVote} from "../../versions.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {createTestDAO} from "@mocks/MockDAO.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";

import {DelegationMapper} from "@delegation/DelegationMapper.sol";
import {console2 as console} from "forge-std/console2.sol";

contract DelegateTest is Base {
    function setUp() public override {
        super.setUp();
    }

    function test_ggg() public {
        vm.warp(10);
        escrow.writeLock(1, 10, weekStartTs(block.timestamp));
        dg.delegate(alice);
        dg.delegate(singleId);
        vm.warp(block.timestamp + 10 weeks);
        uint256[] memory idss = new uint256[](1);
        idss[0] = 2;
        escrow.writeLock(2, 50, block.timestamp + 3 weeks);

        // idss[1] = 3;
        // idss[2] = 4;
        uint256 g1 = gasleft();

        dg.delegate(idss);
        uint256 g2 = gasleft();

        console.log("fuckkkk", g1 - g2);

    }

    // function test_CanNotDelegateIfNotOwner() public {
    //     escrow.setApproved(false);

    //     vm.expectRevert(DelegationMapper.NotApprovedOrOwner.selector);

    //     dg.delegate(singleId, alice);
    // }

    // function test_CanNotDelegateeToSameAddress() public {
    //     dg.delegate(singleId, alice);

    //     vm.expectRevert(DelegationMapper.CanNotDelegateToSameAddress.selector);

    //     dg.delegate(singleId, alice);
    // }

    // function test_Fuzz_SetDelegatee_UpdatesBalance_ForSingleToken(
    //     uint256 _tokenId,
    //     uint224 _vp
    // ) public {
    //     uint256[] memory _ids = new uint256[](1);
    //     _ids[0] = _tokenId;

    //     escrow.write(_ids[0], _vp);

    //     dg.delegate(_ids, alice);

    //     (address delegatee, uint256 ts) = dg.getDelegate(_ids[0], block.timestamp);

    //     assertEq(delegatee, alice);
    //     assertEq(ts, block.timestamp);

    //     uint256 balance = dg.getDelegationBalance(alice, block.timestamp);
    //     assertEq(balance, _vp);

    //     assertEq(dg.getVotes(alice), _vp);
    //     assertEq(dg.getPastVotes(alice, block.timestamp), _vp);
    //     assertEq(dg.getPastVotes(alice, block.timestamp - 1), 0);
    //     assertEq(dg.getPastVotes(alice, block.timestamp + 1), _vp);
    // }

    // function test_Fuzz_SetDelegatee_UpdatesBalance_ForMultipleTokens(
    //     uint208[3] memory _vps
    // ) public {
    //     uint256 totalVp;
    //     for (uint256 i = 0; i < ids.length; i++) {
    //         escrow.write(ids[i], _vps[i]);
    //         totalVp += _vps[i];
    //     }

    //     dg.delegate(ids, alice);

    //     for (uint256 i = 0; i < ids.length; i++) {
    //         (address delegatee, uint256 ts) = dg.getDelegate(ids[i], block.timestamp);

    //         assertEq(delegatee, alice);
    //         assertEq(ts, block.timestamp);
    //     }

    //     uint256 balance = dg.getDelegationBalance(alice, block.timestamp);
    //     assertEq(balance, totalVp);

    //     assertEq(dg.getVotes(alice), totalVp);
    //     assertEq(dg.getPastVotes(alice, block.timestamp), totalVp);
    //     assertEq(dg.getPastVotes(alice, block.timestamp - 1), 0);
    //     assertEq(dg.getPastVotes(alice, block.timestamp + 1), totalVp);
    // }

    // function test_Fuzz_ReDelegate_UpdatesOldAndNewDelegateeBalances(uint208[3] memory _vps) public {
    //     uint256 totalVp;
    //     for (uint256 i = 0; i < ids.length; i++) {
    //         escrow.write(ids[i], _vps[i]);
    //         totalVp += _vps[i];
    //     }

    //     uint256 ts = block.timestamp;
    //     dg.delegate(ids, alice);

    //     vm.warp(block.timestamp + 10000);

    //     dg.delegate(ids, bob);

    //     // Alice must have lost delegation and
    //     // Bob should have it at latest timestamp.
    //     assertEq(dg.getDelegationBalance(alice, block.timestamp), 0);
    //     assertEq(dg.getDelegationBalance(bob, block.timestamp), totalVp);
    //     assertDelegate(ids[0], block.timestamp, bob);

    //     // Before re-delegation occured, Alice still
    //     // should be delegated and not Bob.
    //     assertEq(dg.getDelegationBalance(alice, ts), totalVp);
    //     assertEq(dg.getDelegationBalance(bob, ts), 0);
    //     assertDelegate(ids[0], ts, alice);

    //     // Bob must have votes at the latest timestamp.
    //     assertEq(dg.getVotes(bob), totalVp);
    //     assertEq(dg.getPastVotes(bob, block.timestamp), totalVp);
    //     assertEq(dg.getPastVotes(bob, block.timestamp - 1), 0);

    //     // Alice should only have votes before re-delegation occured.
    //     assertEq(dg.getVotes(alice), 0);
    //     assertEq(dg.getPastVotes(alice, block.timestamp), 0);
    //     assertEq(dg.getPastVotes(alice, block.timestamp - 1), totalVp);
    // }
}
