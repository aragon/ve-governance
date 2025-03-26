pragma solidity ^0.8.17;

import {Base} from "./Base.sol";

import {Lock, Clock, VotingEscrow, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, IEscrowCurveTokenStorage, IGaugeVote} from "../../versions.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {createTestDAO} from "@mocks/MockDAO.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";

import {DelegationMapper} from "@delegation/DelegationMapper.sol";

contract UndelegateTest is Base {
    function setUp() public override {
        super.setUp();
    }

    function test_Reverts_If_SenderIsNotOwner() public {
        vm.warp(10);

        dg.delegate(ids, alice);

        escrow.setApproved(false);

        vm.prank(address(123));
        vm.expectRevert(DelegationMapper.NotApprovedOrOwner.selector);
        dg.undelegate(ids);
    }
    
    function test_UpdateBalance_WithZero_And_Remove_Delegate() public {
        escrow.write(ids[0], 14);
        escrow.write(ids[1], 15);
        escrow.write(ids[2], 16);

        dg.delegate(ids, alice);

        uint256 delegateTs = block.timestamp;

        assertEq(dg.getDelegationBalance(alice, delegateTs), 45);

        vm.warp(block.timestamp + 10);
        uint256 undelegateTs = block.timestamp;

        dg.undelegate(ids);

        assertEq(dg.getDelegationBalance(alice, undelegateTs), 0);

        for(uint256 i = 0; i < ids.length; i++) {
            (address delegatee, ) = dg.getDelegate(ids[i], undelegateTs);
            assertEq(delegatee, address(0));
        }

        // Ensure that before undelegation timestamp, alice still is delegatee.
        assertEq(dg.getDelegationBalance(alice, undelegateTs - 1), 45);

        for(uint256 i = 0; i < ids.length; i++) {
            (address delegatee, ) = dg.getDelegate(ids[i], undelegateTs - 1);
            assertEq(delegatee, alice);
        }

    }

}
