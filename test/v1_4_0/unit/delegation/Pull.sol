pragma solidity ^0.8.17;

import {Base} from "./Base.sol";

import {Lock, Clock, VotingEscrow, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, IEscrowCurveTokenStorage, IGaugeVote} from "../../versions.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {createTestDAO} from "@mocks/MockDAO.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";

import {DelegationMapper} from "@delegation/DelegationMapper.sol";

contract PullTest is Base {
    function setUp() public override {
        super.setUp();
    }

    function test_Reverts_If_TokenNotDelegated() public {
        vm.warp(10);

        dg.delegate(ids, alice);

        vm.expectRevert(
            abi.encodeWithSelector(DelegationMapper.TokenNotDelegated.selector, ids[0])
        );

        dg.pull(ids, block.timestamp - 1);
    }
    
    function test_UpdatesBalance_Latest_Timestamp() public {
        escrow.write(ids[0], 14);
        escrow.write(ids[1], 15);
        escrow.write(ids[2], 16);

        dg.delegate(ids, alice);

        assertEq(dg.getDelegationBalance(alice, block.timestamp), 14 + 15 + 16);

        vm.warp(block.timestamp + 10);

        escrow.write(1, 30);
        escrow.write(2, 45);
        escrow.write(3, 22);

        dg.pull(ids, block.timestamp);
        assertEq(dg.getDelegationBalance(alice, block.timestamp), 30 + 45 + 22);
    }

    function test_UpdatesBalance_With_Past_Timestamp_1() public {
        // Given: The past timestamp of `pull` is still greater 
        //        than all the already existing timestamps in checkpoints.
        vm.warp(20);

        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;

        // delegate 15 + 17 voting power
        escrow.write(1, 15);
        escrow.write(2, 17);

        dg.delegate(ids, alice);
        
        // Sometime has passed, and voting powers changed.
        vm.warp(block.timestamp + 5);

        escrow.write(1, 16);
        escrow.write(2, 18);

        // some more time has passed.
        vm.warp(block.timestamp + 5);   

        // pull the voting power for the past timestamp.
        dg.pull(ids, block.timestamp - 5);

        assertEq(dg.getDelegationBalance(alice, block.timestamp - 5), 16 + 18);
    }

    function test_UpdatesBalance_With_Past_Timestamp_2() public {
        // Given: The past timestamp of `pull` is greater 
        //        than all some already existing checkpoint timestamps
        //        and less than some other checkpoint timestamps.
        vm.warp(20);

        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;

        // delegate 15 + 17 voting power
        escrow.write(1, 15);
        escrow.write(2, 17);

        dg.delegate(ids, alice);
        
        // Sometime has passed, and voting powers changed.
        vm.warp(block.timestamp + 5);
        uint256 tsVPChange1 = block.timestamp;
        escrow.write(1, 16);
        escrow.write(2, 18);

        // Sometime has passed, and voting powers changed.
        vm.warp(block.timestamp + 5);
        uint256 tsVPChange2 = block.timestamp;
        escrow.write(1, 24);
        escrow.write(2, 27);

        // some more time has passed.
        vm.warp(block.timestamp + 5);   

        // pull the voting power for the past timestamp.
        dg.pull(ids, block.timestamp);

        assertEq(dg.getDelegationBalance(alice, block.timestamp), 24 + 27);

        dg.pull(ids, tsVPChange1);

        assertEq(dg.getDelegationBalance(alice, tsVPChange1), 16 + 18);
    }
}

