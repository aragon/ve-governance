pragma solidity ^0.8.17;

import {EscrowBase} from "../../../base/EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

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
    ITicketV2
} from "../../../versions.sol";

contract TestDynamicExitQueueIntegration is
    IEscrowCurveTokenStorage,
    IGaugeVote,
    ITicketV2,
    EscrowBase
{
    function setUp() public override {
        super.setUp();

        vm.warp(1);

        escrow.setMinDeposit(0);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Setup a token and queue it for withdrawal
    /// @param user The user to create the lock for
    /// @param amount The amount to lock
    /// @return tokenId The created token ID
    function _setupTokenAndQueue(address user, uint256 amount) internal returns (uint256 tokenId) {
        token.mint(user, amount);
        vm.startPrank(user);
        {
            token.approve(address(escrow), amount);
            tokenId = escrow.createLock(amount);

            // Wait past minLock period
            vm.warp(block.timestamp + 1 days);

            nftLock.approve(address(escrow), tokenId);
            escrow.beginWithdrawal(tokenId);
        }
        vm.stopPrank();
    }

    /// @notice Withdraw and verify the correct fees and balances
    /// @param user The user withdrawing
    /// @param tokenId The token ID to withdraw
    /// @param expectedFee The expected fee amount
    function _withdrawAndVerify(address user, uint256 tokenId, uint256 expectedFee) internal {
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 queueBalanceBefore = token.balanceOf(address(queue));
        uint256 lockedAmount = escrow.locked(tokenId).amount;

        vm.prank(user);
        escrow.withdraw(tokenId);

        // Verify user received correct amount (locked - fee)
        assertEq(token.balanceOf(user), userBalanceBefore + (lockedAmount - expectedFee));

        // Verify queue received the fee
        assertEq(token.balanceOf(address(queue)), queueBalanceBefore + expectedFee);

        // Verify NFT was burned
        assertEq(nftLock.balanceOf(user), 0);

        // Verify ticket was cleared
        assertEq(queue.ticketHolder(tokenId), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            TESTS
    //////////////////////////////////////////////////////////////*/

    function testFixedFeeEarlyExitEnabled() public {
        address user = address(0x123);

        queue.setFixedExitFeePercent(1500, 7 days, true);

        uint256 tokenId = _setupTokenAndQueue(user, 1000e18);

        assertTrue(queue.canExit(tokenId));

        vm.warp(block.timestamp + 1);
        uint256 fee1 = queue.calculateFee(tokenId);
        assertEq(fee1, 150e18);

        vm.warp(block.timestamp + 3 days);
        uint256 fee2 = queue.calculateFee(tokenId);
        assertEq(fee2, 150e18);

        vm.warp(block.timestamp + 7 days);
        uint256 fee3 = queue.calculateFee(tokenId);
        assertEq(fee3, 150e18);

        _withdrawAndVerify(user, tokenId, 150e18);
    }

    function testTieredFeeSystem() public {
        address user1 = address(0x123);
        address user2 = address(0x456);
        address user3 = address(0x789);

        // 25% -> 5% over 10 days, 2 days minCooldown
        queue.setTieredExitFeePercent(500, 2500, 10 days, 2 days);

        uint256 tokenId1 = _setupTokenAndQueue(user1, 1000e18);
        uint256 tokenId2 = _setupTokenAndQueue(user2, 1000e18);
        uint256 tokenId3 = _setupTokenAndQueue(user3, 1000e18);

        uint start = block.timestamp;

        // @3 days, should be 25% of 1000e18 = 250e18
        vm.warp(start + 3 days);
        uint256 fee1 = queue.calculateFee(tokenId1);
        assertEq(fee1, 250e18);
        _withdrawAndVerify(user1, tokenId1, 250e18);

        // @7 days, should still be 25% of 1000e18 = 250e18
        vm.warp(start + 7 days);
        uint256 fee2 = queue.calculateFee(tokenId2);
        assertEq(fee2, 250e18);
        _withdrawAndVerify(user2, tokenId2, 250e18);

        // after 10 days, should drop to 5% of 1000e18 = 50e18
        vm.warp(start + 10 days + 1);
        uint256 fee3 = queue.calculateFee(tokenId3);
        assertEq(fee3, 50e18);
        _withdrawAndVerify(user3, tokenId3, 50e18);

        assertEq(token.balanceOf(address(queue)), 550e18);
    }

    function testDynamicFeeSystem() public {
        address user0 = address(0xccc);
        address user1 = address(0x123);
        address user2 = address(0x456);
        address user3 = address(0x789);
        address[4] memory users = [user0, user1, user2, user3];

        // Set a dynamic fee system with 30% max fee, 4% min fee, decay over 12 days, and 2 days minCooldown
        // this means the estimated decay per day is (3000 - 400) / 12 = 216.67 or 2.1667% per day
        queue.setDynamicExitFeePercent(400, 3000, 14 days, 2 days);

        // setup 4 tokens and queue
        for (uint i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            {
                token.mint(users[i], 1000e18);
                token.approve(address(escrow), 1000e18);
                uint256 tokenId = escrow.createLock(1000e18);
                nftLock.approve(address(escrow), tokenId);
            }
            vm.stopPrank();
        }

        vm.warp(block.timestamp + 1 days);

        for (uint i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            {
                escrow.beginWithdrawal(i + 1);
            }
            vm.stopPrank();
        }

        uint start = block.timestamp;
        uint accumulator = 0;

        // begin at max
        vm.warp(start + 2 days);
        uint fee = queue.calculateFee(1);
        accumulator += fee;
        uint expectedFee = (3000 * 1000e18) / 10000; // 30% of 1000e18

        assertEq(fee, expectedFee);
        _withdrawAndVerify(user0, 1, expectedFee);

        // at 4 days we are 2 days in.
        // we expect that the total fees are 30% - 2*2.1667% = 30% - 4.33% = 25.67%
        vm.warp(start + 4 days);
        fee = queue.calculateFee(2);
        accumulator += fee;
        uint expectedFeePc = 2567;
        expectedFee = (expectedFeePc * 1000e18) / 10000; // 4.33% of 1000e18

        assertApproxEqAbs(fee, expectedFee, 0.1e18);
        _withdrawAndVerify(user1, 2, fee);

        // now right before the end
        // 11 days down so we expect 4 + 2.16 remaining
        vm.warp(start + 13 days);
        fee = queue.calculateFee(3);
        accumulator += fee;
        expectedFeePc = 617;
        expectedFee = (expectedFeePc * 1000e18) / 10000; // 2.16% of 1000e18
        assertApproxEqAbs(fee, expectedFee, 0.1e18);
        _withdrawAndVerify(user2, 3, fee);

        vm.warp(start + 50 days);
        fee = queue.calculateFee(4);
        accumulator += fee;
        assertEq(fee, 40e18);
        _withdrawAndVerify(user3, 4, fee);

        assertEq(token.balanceOf(address(queue)), accumulator);
    }

    function testMultiTokenFeeSystemChanges() public {
        address user1 = address(0x111);
        address user2 = address(0x222);
        address user3 = address(0x333);
        address user4 = address(0x444);
        address user5 = address(0x555);
        address user6 = address(0x666);

        // Phase 1: Fixed fee (no early exit)
        queue.setFixedExitFeePercent(1000, 5 days, false);
        uint256 tokenId1 = _setupTokenAndQueue(user1, 1000e18);
        uint256 tokenId2 = _setupTokenAndQueue(user2, 1000e18);

        // Phase 2: Fixed fee (early exit enabled)
        queue.setFixedExitFeePercent(1500, 3 days, true);
        uint256 tokenId3 = _setupTokenAndQueue(user3, 1000e18);
        uint256 tokenId4 = _setupTokenAndQueue(user4, 1000e18);

        // Phase 3: Tiered fee
        queue.setTieredExitFeePercent(800, 2000, 7 days, 1 days);
        uint256 tokenId5 = _setupTokenAndQueue(user5, 1000e18);

        // Phase 4: Dynamic fee
        queue.setDynamicExitFeePercent(600, 2400, 10 days, 2 days);
        uint256 tokenId6 = _setupTokenAndQueue(user6, 1000e18);

        // Wait long enough for all systems to reach minimum fees
        vm.warp(block.timestamp + 12 days);

        // All tokens should pay minimum fee (6% = 60e18) since they've all passed their cooldown periods
        uint256 minFee = 60e18;

        uint256 fee1 = queue.calculateFee(tokenId1);
        assertEq(fee1, minFee);
        _withdrawAndVerify(user1, tokenId1, minFee);

        uint256 fee2 = queue.calculateFee(tokenId2);
        assertEq(fee2, minFee);
        _withdrawAndVerify(user2, tokenId2, minFee);

        uint256 fee3 = queue.calculateFee(tokenId3);
        assertEq(fee3, minFee);
        _withdrawAndVerify(user3, tokenId3, minFee);

        uint256 fee4 = queue.calculateFee(tokenId4);
        assertEq(fee4, minFee);
        _withdrawAndVerify(user4, tokenId4, minFee);

        uint256 fee5 = queue.calculateFee(tokenId5);
        assertEq(fee5, minFee);
        _withdrawAndVerify(user5, tokenId5, minFee);

        uint256 fee6 = queue.calculateFee(tokenId6);
        assertEq(fee6, minFee);
        _withdrawAndVerify(user6, tokenId6, minFee);

        assertEq(token.balanceOf(address(queue)), 360e18);
    }

    function testCannotExitBeforeMinCooldown() public {
        address user = address(0x123);

        // Set a system with 2 day minimum cooldown
        queue.setTieredExitFeePercent(500, 2500, 10 days, 2 days);

        uint256 tokenId = _setupTokenAndQueue(user, 1000e18);

        // Should not be able to exit immediately
        assertFalse(queue.canExit(tokenId));

        // Should not be able to exit after 1 day
        vm.warp(block.timestamp + 1 days);
        assertFalse(queue.canExit(tokenId));

        // Should be able to exit after 2 days
        vm.warp(block.timestamp + 1 days);
        assertTrue(queue.canExit(tokenId));

        // Verify withdrawal fails before minCooldown
        vm.warp(block.timestamp - 1 days);
        vm.expectRevert();
        vm.prank(user);
        escrow.withdraw(tokenId);
    }

    function testFeeCalculationAccuracy() public {
        address user = address(0x123);

        // Test dynamic fee calculation accuracy
        // 20% max fee, 5% min fee, decay over 20 days, 5 days minCooldown
        // so over 15 days we see the decline from 20->5
        queue.setDynamicExitFeePercent(500, 2000, 20 days, 5 days);

        uint256 tokenId = _setupTokenAndQueue(user, 1000e18);

        uint start = block.timestamp;

        vm.warp(start); // before minCooldown
        uint256 fee = queue.calculateFee(tokenId);
        assertEq(fee, 200e18); // Should be max fee (20%)

        // Test at various time points
        vm.warp(start + 5 days - 1); // At minCooldown
        fee = queue.calculateFee(tokenId);
        assertEq(fee, 200e18); // Should be max fee (20%)

        // Test at various time points
        vm.warp(start + 5 days); // At minCooldown
        fee = queue.calculateFee(tokenId);
        assertEq(fee, 200e18); // Should be max fee (20%)

        vm.warp(start + 10 days); // 5 days of decay is 5pp
        fee = queue.calculateFee(tokenId);
        assertApproxEqAbs(fee, 150e18, 0.0001e18); // Should be 15% fee (1500/10000)

        vm.warp(start + 15 days);
        fee = queue.calculateFee(tokenId);
        assertApproxEqAbs(fee, 100e18, 0.0001e18); // Should be 10% fee (1000/10000)

        vm.warp(start + 20 days);
        fee = queue.calculateFee(tokenId);
        assertEq(fee, 50e18); // Should be min fee (5%)

        // Verify fee doesn't decrease further
        vm.warp(block.timestamp + 5 days);
        fee = queue.calculateFee(tokenId);
        assertEq(fee, 50e18); // Should still be min fee (5%)
    }
}
