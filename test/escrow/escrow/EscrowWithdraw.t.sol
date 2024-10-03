pragma solidity ^0.8.17;

import {EscrowBase} from "./EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

import {IEscrowCurveTokenStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {VotingEscrow} from "@escrow/VotingEscrowIncreasing.sol";

import {SimpleGaugeVoter, SimpleGaugeVoterSetup} from "@voting/SimpleGaugeVoterSetup.sol";
import {IGaugeVote} from "@voting/ISimpleGaugeVoter.sol";
import {ITicket} from "@escrow-interfaces/IExitQueue.sol";

contract TestWithdraw is EscrowBase, IEscrowCurveTokenStorage, IGaugeVote, ITicket {
    address gauge = address(1);

    GaugeVote[] votes;

    function setUp() public override {
        super.setUp();

        vm.warp(1);

        // make a voting gauge
        voter.createGauge(gauge, "metadata");
        votes.push(GaugeVote({gauge: gauge, weight: 1}));

        escrow.setMinDeposit(0);
    }

    // setup a fee withdrawal
    function testFuzz_feeWithdrawal(uint64 _fee, uint128 _dep, address _who) public {
        vm.assume(_who != address(0) && address(_who).code.length == 0);
        vm.assume(_dep > 0);

        if (_fee > 10_000) _fee = 10_000;

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
            nftLock.approve(address(escrow), tokenId);
            escrow.resetVotesAndBeginWithdrawal(tokenId);
        }
        vm.stopPrank();

        // can't withdraw if not ticket holder
        vm.expectRevert(NotTicketHolder.selector);
        escrow.withdraw(tokenId);

        // can't force approve
        vm.expectRevert("ERC721: approve caller is not token owner or approved for all");
        vm.prank(_who);
        nftLock.approve(_who, tokenId);

        // must wait till end of queue
        vm.warp(3 weeks);
        vm.expectRevert(CannotExit.selector);
        vm.prank(_who);
        escrow.withdraw(tokenId);

        uint fee = queue.calculateFee(tokenId);

        // withdraw
        vm.warp(3 weeks + 1);
        vm.prank(_who);
        vm.expectEmit(true, true, false, true);
        emit Withdraw(_who, tokenId, _dep - fee, block.timestamp, 0);
        escrow.withdraw(tokenId);

        // fee sent to queue
        assertEq(token.balanceOf(address(queue)), fee);

        // remainder sent to user
        assertEq(token.balanceOf(_who), _dep - fee);

        bool feeDepTooSmall = uint(_fee) * uint(_dep) < 10_000;

        if (_fee == 0 || feeDepTooSmall) {
            assertEq(token.balanceOf(_who), _dep);
            assertEq(token.balanceOf(address(queue)), 0);
        } else {
            assertGt(token.balanceOf(address(queue)), 0);
        }

        // nft is burned
        assertEq(nftLock.balanceOf(_who), 0);
        assertEq(nftLock.balanceOf(address(escrow)), 0);
        assertEq(escrow.totalLocked(), 0);

        assertEq(escrow.votingPowerForAccount(_who), 0);
    }

    function testFuzz_enterWithdrawal(uint128 _dep, address _who) public {
        vm.assume(_who != address(0) && address(_who).code.length == 0);
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
            nftLock.approve(address(escrow), tokenId);
            escrow.resetVotesAndBeginWithdrawal(tokenId);
        }
        vm.stopPrank();

        // should now have the nft in the escrow
        assertEq(nftLock.balanceOf(_who), 0);
        assertEq(nftLock.balanceOf(address(escrow)), 1);

        // voting power should still be there as the cp is still active
        assertGt(escrow.votingPower(tokenId), 0);

        // but we should have written a token point in the future
        TokenPoint memory up = curve.tokenPointHistory(tokenId, 2);
        assertEq(up.bias, 0);
        assertEq(up.writtenTs, block.timestamp);
        assertEq(up.checkpointTs, 3 weeks);

        // should have a ticket expiring in a few days
        assertEq(queue.canExit(tokenId), false);
        assertEq(queue.queue(tokenId).exitDate, 3 weeks);

        // check the future to see the voting power expired
        vm.warp(3 weeks + 1);
        assertEq(escrow.votingPower(tokenId), 0);
    }

    function testCanWithdrawAfterCooldownOnlyIfCrossesWeekBoundary() public {
        address _who = address(1);
        uint128 _dep = 100e18;

        // voting window is ea. 2 weeks + 1 hour
        vm.warp(2 weeks + 1 hours + 1);

        assertTrue(voter.votingActive());

        token.mint(_who, _dep);
        uint tokenId;
        vm.startPrank(_who);
        {
            token.approve(address(escrow), _dep);
            tokenId = escrow.createLock(_dep);

            // voting active after cooldown
            // +1 week: voting ends
            // +2 weeks: next voting period opens
            vm.warp(block.timestamp + 2 weeks);

            // make a vote
            voter.vote(tokenId, votes);

            // warp so cooldown crosses the week boundary
            vm.warp(block.timestamp + clock.checkpointInterval() - queue.cooldown() + 1);

            nftLock.approve(address(escrow), tokenId);
            escrow.resetVotesAndBeginWithdrawal(tokenId);
        }
        vm.stopPrank();

        // must wait till after end of cooldown
        vm.warp(block.timestamp + queue.cooldown());
        vm.expectRevert(CannotExit.selector);
        vm.prank(_who);
        escrow.withdraw(tokenId);

        uint fee = queue.calculateFee(tokenId);

        // withdraw
        vm.warp(block.timestamp + 1);
        vm.prank(_who);
        vm.expectEmit(true, true, false, true);
        emit Withdraw(_who, tokenId, _dep - fee, block.timestamp, 0);
        escrow.withdraw(tokenId);

        // asserts
        assertEq(token.balanceOf(address(queue)), fee);
        assertEq(token.balanceOf(_who), _dep - fee);
        assertEq(nftLock.balanceOf(_who), 0);
        assertEq(nftLock.balanceOf(address(escrow)), 0);
        assertEq(escrow.totalLocked(), 0);
    }
    // HAL-13: locks are re-used causing reverts and duplications
    function testCanCreateLockAfterBurning() public {
        address USER1 = address(1);
        address USER2 = address(2);

        // mint
        token.mint(USER1, 100);
        token.mint(USER2, 100);

        vm.prank(USER1);
        token.approve(address(escrow), 100);

        vm.prank(USER2);
        token.approve(address(escrow), 100);

        vm.prank(USER1);
        uint256 tokenId = escrow.createLockFor(100, USER1); // Token ID 1

        vm.prank(USER2);
        uint256 tokenId2 = escrow.createLockFor(100, USER2); // Token ID 2

        // approve
        uint256 tokenId3;
        vm.startPrank(USER1);
        {
            nftLock.approve(address(escrow), tokenId);

            vm.warp(1 weeks + 1 days);

            escrow.beginWithdrawal(tokenId);

            Ticket memory ticket = queue.queue(tokenId);
            vm.warp(ticket.exitDate + 1);

            escrow.withdraw(tokenId);
            token.approve(address(escrow), 100);
            tokenId3 = escrow.createLockFor(100, USER1); // Token ID 2 - Duplicated - Reescrowrt
        }
        vm.stopPrank();

        // assert that the lock Id is incremented
        assertEq(tokenId3, 3);
        assertNotEq(tokenId2, tokenId3);
        assertEq(nftLock.totalSupply(), 2);
        assertEq(escrow.lastLockId(), 3);
    }

    function testCantDepositAndWithdrawInTheSameBlock() public {
        // this is a timing
        // deposit falls exactly on the week boundary, so that we start immediately
        // then we try to withdraw in the same block
        // we also need a zero warmup period or we will error with a zero voting power
        curve.setWarmupPeriod(0);

        // warp to a week boundary
        vm.warp(1 weeks);

        // deposit
        token.mint(address(1), 100e18);

        uint tokenId;

        bytes memory data = abi.encodeWithSelector(CannotExit.selector);
        // start the deposit
        vm.startPrank(address(1));
        {
            // create
            token.approve(address(escrow), 100e18);
            tokenId = escrow.createLock(100e18);

            // withdraw
            nftLock.approve(address(escrow), tokenId);
            vm.expectRevert(data);
            escrow.beginWithdrawal(tokenId);
        }
        vm.stopPrank();
    }

    function testCannotExitDuringWarmupIfWarmupIsLong() public {
        // warp to genesis
        vm.warp(1);

        // set a long warmup that crosses an epoch boundary
        curve.setWarmupPeriod(4 weeks);

        // make a deposit
        token.mint(address(1), 100e18);

        uint tokenId;

        vm.startPrank(address(1));
        {
            token.approve(address(escrow), 100e18);
            tokenId = escrow.createLock(100e18);
        }
        vm.stopPrank();

        // check the start date
        uint start = escrow.locked(tokenId).start;
        assertEq(start, 1 weeks);

        vm.warp(1 weeks);

        // should not be able to exit
        vm.startPrank(address(1));
        {
            nftLock.approve(address(escrow), tokenId);
            vm.expectRevert(CannotExit.selector);
            escrow.beginWithdrawal(tokenId);
        }
        vm.stopPrank();
    }
}
