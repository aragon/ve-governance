pragma solidity ^0.8.17;

import {EscrowBase} from "./EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {EpochDurationLib} from "@libs/EpochDurationLib.sol";

import {IEscrowCurveUserStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {VotingEscrow} from "@escrow/VotingEscrowIncreasing.sol";

import {SimpleGaugeVoter, SimpleGaugeVoterSetup} from "src/voting/SimpleGaugeVoterSetup.sol";
import {IGaugeVote} from "src/voting/ISimpleGaugeVoter.sol";

contract TestWithdraw is EscrowBase, IEscrowCurveUserStorage, IGaugeVote {
    address gauge = address(1);

    GaugeVote[] votes;

    function setUp() public override {
        super.setUp();

        vm.warp(1);

        // make a voting gauge
        voter.createGauge(gauge, "metadata");
        votes.push(GaugeVote({gauge: gauge, weight: 1}));
    }

    // setup a fee withdrawal
    function testFuzz_feeWithdrawal(uint64 _fee, uint128 _dep, address _who) public {
        vm.assume(_who != address(0));
        vm.assume(_dep > 0);

        if (_fee > 1e18) _fee = 1e18;

        queue.setFeePercent(_fee);

        token.mint(_who, _dep);
        uint tokenId;
        vm.startPrank(_who);
        {
            token.approve(address(escrow), _dep);
            tokenId = escrow.createLock(_dep);

            // voting active after cooldown
            vm.warp(block.timestamp + 2 weeks + 1 hours);

            // make a vote
            voter.vote(tokenId, votes);
        }
        vm.stopPrank();

        // can't enter a withdrawal while voting
        vm.expectRevert(CannotExit.selector);
        escrow.beginWithdrawal(tokenId);

        // enter a withdrawal
        vm.startPrank(_who);
        {
            escrow.approve(address(escrow), tokenId);
            escrow.resetVotesAndBeginWithdrawal(tokenId);
        }
        vm.stopPrank();

        // can't withdraw if not ticket holder
        vm.expectRevert(NotTicketHolder.selector);
        escrow.withdraw(tokenId);

        // can't force approve
        vm.expectRevert("ERC721: approve caller is not token owner or approved for all");
        vm.prank(_who);
        escrow.approve(_who, tokenId);

        // must wait till end of queue
        vm.warp(block.timestamp + queue.cooldown() - 1);
        vm.expectRevert(CannotExit.selector);
        vm.prank(_who);
        escrow.withdraw(tokenId);

        uint fee = queue.calculateFee(tokenId);

        // withdraw
        vm.warp(block.timestamp + queue.cooldown());
        vm.prank(_who);
        vm.expectEmit(true, true, false, true);
        emit Withdraw(_who, tokenId, _dep - fee, block.timestamp, 0);
        escrow.withdraw(tokenId);

        // fee sent to queue
        assertEq(token.balanceOf(address(queue)), fee);

        // remainder sent to user
        assertEq(token.balanceOf(_who), _dep - fee);

        if (_fee == 0) {
            assertEq(token.balanceOf(_who), _dep);
            assertEq(token.balanceOf(address(queue)), 0);
        } else {
            console.log("fee", fee);
            console.log("_fee", _fee);
            console.log("_dep", _dep);
            assertGt(token.balanceOf(address(queue)), 0);
        }

        // nft is burned
        assertEq(escrow.balanceOf(_who), 0);
        assertEq(escrow.balanceOf(address(escrow)), 0);
        assertEq(escrow.totalLocked(), 0);
    }

    function testFuzz_enterWithdrawal(uint128 _dep, address _who) public {
        vm.assume(_who != address(0));
        vm.assume(_dep > 0);

        // make a deposit
        token.mint(_who, _dep);
        uint tokenId;
        vm.startPrank(_who);
        {
            token.approve(address(escrow), _dep);
            tokenId = escrow.createLock(_dep);

            // voting active after cooldown
            vm.warp(block.timestamp + 2 weeks + 1 hours);

            // make a vote
            voter.vote(tokenId, votes);
        }
        vm.stopPrank();

        // can't enter a withdrawal while voting
        vm.expectRevert(CannotExit.selector);
        escrow.beginWithdrawal(tokenId);

        // enter a withdrawal
        vm.startPrank(_who);
        {
            escrow.approve(address(escrow), tokenId);
            escrow.resetVotesAndBeginWithdrawal(tokenId);
        }
        vm.stopPrank();

        // should now have the nft in the escrow
        assertEq(escrow.balanceOf(_who), 0);
        assertEq(escrow.balanceOf(address(escrow)), 1);

        // should be zero vp with the nft
        assertEq(escrow.votingPower(tokenId), 0);

        // account voting power now zero
        assertEq(escrow.votingPowerForAccount(_who), 0);

        // should have a ticket expiring in a few days
        assertEq(queue.canExit(tokenId), false);
        assertEq(queue.queue(tokenId).exitDate, block.timestamp + 3 days);
    }
}
