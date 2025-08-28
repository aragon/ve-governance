pragma solidity ^0.8.17;

import {EscrowBase} from "../../../base/EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/src/MultisigSetup.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

import {
    Lock,
    Clock,
    VotingEscrow,
    ExitQueue,
    SimpleGaugeVoter,
    SimpleGaugeVoterSetup,
    IEscrowCurveTokenStorage,
    IGaugeVote,
    ITicket,
    IExitQueueCancelErrorsAndEvents
} from "../../../versions.sol";

contract TestCancelWithdraw is IEscrowCurveTokenStorage, IGaugeVote, ITicket, IExitQueueCancelErrorsAndEvents, EscrowBase {
    function setUp() public override {
        super.setUp();

        vm.warp(1);

        escrow.setMinDeposit(0);
    }

    function testRevert_BeginWithdrawalHasNotOccuredYet() public {
        token.mint(address(this), 100e18);
        token.approve(address(escrow), 100e18);

        uint256 tokenId = escrow.createLock(100e18);
        nftLock.approve(address(escrow), tokenId);

        vm.warp(block.timestamp + 1);
        escrow.beginWithdrawal(tokenId);

        vm.prank(address(1));
        vm.expectRevert(NotTicketHolder.selector);
        escrow.cancelWithdrawalRequest(tokenId);
    }

    function test_CancelsWithdraw() public {
        token.mint(address(this), 100e18);
        token.approve(address(escrow), 100e18);

        uint256 tokenId = escrow.createLock(100e18);
        nftLock.approve(address(escrow), tokenId);

        vm.warp(block.timestamp + 1);

        uint256 vpBefore = escrow.votingPower(tokenId);
        escrow.beginWithdrawal(tokenId);
        uint256 vpAfterWithdraw = escrow.votingPower(tokenId);

        assertEq(queue.ticketHolder(tokenId), address(this));
        assertNotEq(queue.queue(tokenId).exitDate, 0);
        
        vm.expectEmit(true, true, false, true);
        emit ExitCancelled(tokenId, address(this));
        escrow.cancelWithdrawalRequest(tokenId);
        uint256 vpAfterCancelWithdraw = escrow.votingPower(tokenId);

        assertEq(vpBefore, vpAfterCancelWithdraw);
        assertEq(vpAfterWithdraw, 0);
        assertNotEq(vpAfterCancelWithdraw, 0);

        assertEq(queue.ticketHolder(tokenId), address(0));
        assertEq(queue.queue(tokenId).exitDate, 0);
    }      
}
