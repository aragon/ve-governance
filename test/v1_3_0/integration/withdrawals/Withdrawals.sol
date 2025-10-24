pragma solidity ^0.8.17;

import {EscrowBase, IAddressGaugeVote} from "../../base/EscrowBase.sol";
import {console2 as console} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {
    Clock,
    IClock,
    Lock,
    VotingEscrow,
    IVotingEscrowIncreasing,
    IEscrowCurveIncreasing,
    IVotingEscrowIncreasing,
    IVotingEscrowCoreErrors,
    IMerge,
    ISplit,
    ILockedBalanceIncreasing,
    IEscrowCurveGlobalStorage,
    IEscrowCurveTokenStorage,
    IEscrowCurveGlobalStorage,
    EscrowIVotesAdapter,
    IEscrowIVotesAdapterErrorsAndEvents,
    IGaugeVote
} from "../../versions.sol";

contract ERC721ReceiverMock is IERC721Receiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract TestWithdrawal is IEscrowCurveTokenStorage, IEscrowCurveGlobalStorage, EscrowBase {
    address gauge = address(0x777);

    function setUp() public override {
        super.setUp();

        vm.warp(2 weeks + 1 hours + 1);
        voter.createGauge(gauge, "metadata");
        escrow.enableSplit();
    }

    struct User {
        address user;
        uint96 amount;
        bool withdraws;
        bool delegateToOther;
        address delegatee;
    }

    function slopeChanges(uint256 _tokenId) internal view override returns (int256) {
        return super.slopeChanges(weekStartTs(escrow.locked(_tokenId).start) + maxTime);
    }

    function slopeOfToken(uint256 _tokenId) internal view returns (int256) {
        return slopeFP(escrow.locked(_tokenId).amount);
    }

    function testRevert_IfBeginWithdrawalSameBlockWithTwoTokens() public {
        super.mintAndApproveEscrow();

        vm.warp(1);
        uint256 tokenId1 = escrow.createLock(10e18);

        vm.warp(2);
        uint256 tokenId2 = escrow.createLock(15e18);
        
        escrow.merge(tokenId2, tokenId1);
        nftLock.approve(address(escrow), tokenId1);

        vm.expectRevert(CannotWithdrawInSameBlock.selector);
        escrow.beginWithdrawal(tokenId1);
    }

    function testRevert_IfBeginWithdrawalSameBlockWithThreeTokens() public {
        super.mintAndApproveEscrow();

        vm.warp(1);
        uint256 tokenId1 = escrow.createLock(10e18);
        uint256 tokenId2 = escrow.createLock(10e18);

        vm.warp(2);
        uint256 tokenId3 = escrow.createLock(15e18);
        
        escrow.merge(tokenId3, tokenId2);
        escrow.merge(tokenId2, tokenId1);

        vm.expectRevert(CannotWithdrawInSameBlock.selector);
        escrow.beginWithdrawal(tokenId1);
    }

    function test_AllowBeginWithdrawalIfLockWasCreatedInPreviousBlock() public {
        super.mintAndApproveEscrow();

        vm.warp(1);
        uint256 tokenId1 = escrow.createLock(10e18);
        uint256 tokenId2 = escrow.createLock(10e18);
        uint256 tokenId3 = escrow.createLock(15e18);

        vm.warp(2);
        
        escrow.merge(tokenId3, tokenId2);
        escrow.merge(tokenId2, tokenId1);

        nftLock.approve(address(escrow), tokenId1);

        escrow.beginWithdrawal(tokenId1);
    }

    /// 20 users create locks. Each of them either delegates to themselves or someone else.
    /// This means that a single user could end up being delegated multiple times.
    function testFuzz_WithrawWithCancel(User[20] memory _users) public {
        uint256[] memory tokenIds = new uint256[](_users.length);
        IAddressGaugeVote.GaugeVote[] memory votes = new IAddressGaugeVote.GaugeVote[](1);
        votes[0] = IAddressGaugeVote.GaugeVote(100, gauge);

        // Assume no duplicate addresses are found.
        uint256 count;
        for (uint256 i = 0; i < _users.length; i++) {
            vm.assume(_users[i].amount != 0);
            vm.assume(_users[i].user != address(0));

            for (uint256 j = i + 1; j < _users.length; j++) {
                vm.assume(_users[i].user != _users[j].user);
            }

            if (_users[i].user.code.length > 0) {
                _users[i].user = address(new ERC721ReceiverMock());
            }

            if (_users[i].withdraws) count++;
        }

        // At least 3 withdraw request must take place.
        vm.assume(count >= 3);

        // Create locks for each user, delegate each user
        // to themselves and make them vote.
        for (uint256 i = 0; i < _users.length; i++) {
            super.mintAndApproveEscrow(_users[i].user, _users[i].amount);

            vm.startPrank(_users[i].user);
            tokenIds[i] = escrow.createLock(_users[i].amount);
            nftLock.approve(address(escrow), tokenIds[i]);

            // Either delegate to himself or someone else.
            address user = _users[i].user;
            if (_users[i].delegateToOther) {
                user = _users[(i + 1) % _users.length].user;
            }
            _users[i].delegatee = user;

            ivotesAdapter.delegate(user);
            vm.stopPrank();

            vm.prank(user);
            voter.vote(votes);
        }

        // warp so create locks and beginwithdrawals are not in the same block.
        vm.warp(block.timestamp + 1);

        uint256 totalVpBefore = escrow.totalVotingPower();
        uint256[] memory vpBefore = new uint256[](_users.length);

        for (uint256 i = 0; i < _users.length; i++) {
            vpBefore[i] = escrow.votingPower(tokenIds[i]);

            if (!_users[i].withdraws) {
                assertNotEq(escrow.votingPower(tokenIds[i]), 0);

                continue;
            }

            // If beginWithdraw occurs, delegatee's balance must be decreased
            // by the amount of that specific tokenId for which begin
            // withdraw occured.
            uint256 beforeBeginWithdraw = ivotesAdapter.getVotes(_users[i].delegatee);
            int256 slopeChangesBefore = slopeChanges(tokenIds[i]);

            vm.prank(_users[i].user);
            escrow.beginWithdrawal(tokenIds[i]);

            int256 slopeChangesAfter = slopeChanges(tokenIds[i]);
            uint256 afterBeginWithdraw = ivotesAdapter.getVotes(_users[i].delegatee);

            assertApproxEqAbs(afterBeginWithdraw, beforeBeginWithdraw - vpBefore[i], 1);
            assertEq(slopeChangesAfter, slopeChangesBefore - slopeOfToken(tokenIds[i]));
            assertEq(escrow.votingPower(tokenIds[i]), 0);
        }

        for (uint256 i = 0; i < _users.length; i++) {
            if (!_users[i].withdraws) {
                assertEq(escrow.votingPower(tokenIds[i]), vpBefore[i]);
                continue;
            }

            // If cancel withdraw occurs, delegatee's balance must be increased
            // by the amount of that specific tokenId for which begin
            // cancel withdraw occured occured.
            uint256 beforeCancelWithdraw = ivotesAdapter.getVotes(_users[i].delegatee);
            int256 slopeChangesBefore = slopeChanges(tokenIds[i]);

            vm.prank(_users[i].user);
            escrow.cancelWithdrawalRequest(tokenIds[i]);

            uint256 afterCancelWithdraw = ivotesAdapter.getVotes(_users[i].delegatee);
            int256 slopeChangesAfter = slopeChanges(tokenIds[i]);

            assertApproxEqAbs(afterCancelWithdraw, beforeCancelWithdraw + vpBefore[i], 1);
            assertEq(slopeChangesAfter, slopeChangesBefore + slopeOfToken(tokenIds[i]));
            assertEq(escrow.votingPower(tokenIds[i]), vpBefore[i]);
        }

        uint256 totalVpAfter = escrow.totalVotingPower();
        assertEq(totalVpBefore, totalVpAfter);
    }

    /*//////////////////////////////////////////////////////////////
                        ATOMIC WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     *  | createLock | merge | split | beginWithdrawal | allowed |
     *  | ---------- | ----- | ----- | --------------- | ------- |
     *  | ✅         | ❌    | ❌    | ✅              | ❌      |
     *  | ✅         | ✅    | ❌    | ✅              | ❌      |
     *  | ✅         | ❌    | ✅    | ✅              | ❌      |
     *  | ✅         | ✅    | ✅    | ✅              | ❌      |
     *  | ❌         | ✅    | ❌    | ✅              | ✅      |
     *  | ❌         | ❌    | ✅    | ✅              | ✅      |
     *  | ❌         | ✅    | ✅    | ✅              | ✅      |
     *
     *  These are allowed but we are only checking withdrawals
     *
     *  | ✅         | ✅    | ❌    | ❌              | ✅      |
     *  | ✅         | ❌    | ✅    | ❌              | ✅      |
     *  | ✅         | ✅    | ✅    | ❌              | ✅      |
     **/

    // Row 1: createLock ✅, merge ❌, split ❌, beginWithdrawal ✅ => Should revert
    function testRevert_AtomicWithdrawal_CreateLockOnly() public {
        super.mintAndApproveEscrow();
        
        uint256 tokenId = escrow.createLock(10e18);
        nftLock.approve(address(escrow), tokenId);
        
        vm.expectRevert(CannotWithdrawInSameBlock.selector);
        escrow.beginWithdrawal(tokenId);
    }

    // Row 2: createLock ✅, merge ✅, split ❌, beginWithdrawal ✅ => Should revert
    function testRevert_AtomicWithdrawal_CreateLockAndMerge() public {
        super.mintAndApproveEscrow();
        
        // Create first token in previous block
        vm.warp(1);
        uint256 existingTokenId = escrow.createLock(5e18);
        
        // Create and merge in current block
        vm.warp(2);
        uint256 newTokenId = escrow.createLock(10e18);
        escrow.merge(newTokenId, existingTokenId);
        nftLock.approve(address(escrow), existingTokenId);
        
        vm.expectRevert(CannotWithdrawInSameBlock.selector);
        escrow.beginWithdrawal(existingTokenId);
    }

    // Row 3: createLock ✅, merge ❌, split ✅, beginWithdrawal ✅ => Should revert
    function testRevert_AtomicWithdrawal_CreateLockAndSplit() public {
        super.mintAndApproveEscrow();
        
        uint256 tokenId = escrow.createLock(20e18);
        uint256 splitTokenId = escrow.split(tokenId, 10e18);
        nftLock.approve(address(escrow), tokenId);
        
        // Try to withdraw the original token
        vm.expectRevert(CannotWithdrawInSameBlock.selector);
        escrow.beginWithdrawal(tokenId);
        
        // Also try to withdraw the split token
        nftLock.approve(address(escrow), splitTokenId);
        vm.expectRevert(CannotWithdrawInSameBlock.selector);
        escrow.beginWithdrawal(splitTokenId);
    }

    // Row 4: createLock ✅, merge ✅, split ✅, beginWithdrawal ✅ => Should revert
    function testRevert_AtomicWithdrawal_CreateLockMergeAndSplit() public {
        super.mintAndApproveEscrow();
        
        // Create first token in previous block
        vm.warp(1);
        uint256 existingTokenId = escrow.createLock(5e18);
        
        // Create, merge and split in current block
        vm.warp(2);
        uint256 newTokenId = escrow.createLock(20e18);
        escrow.merge(newTokenId, existingTokenId);
        uint256 splitTokenId = escrow.split(existingTokenId, 10e18);
        
        // Try to withdraw any of the tokens
        nftLock.approve(address(escrow), existingTokenId);
        vm.expectRevert(CannotWithdrawInSameBlock.selector);
        escrow.beginWithdrawal(existingTokenId);
        
        nftLock.approve(address(escrow), splitTokenId);
        vm.expectRevert(CannotWithdrawInSameBlock.selector);
        escrow.beginWithdrawal(splitTokenId);
    }

    // Row 5: createLock ❌, merge ✅, split ❌, beginWithdrawal ✅ => Should allow
    function test_AtomicWithdrawal_MergeOnly() public {
        super.mintAndApproveEscrow();
        
        // Create tokens in previous block
        vm.warp(1);
        uint256 tokenId1 = escrow.createLock(10e18);
        uint256 tokenId2 = escrow.createLock(5e18);
        
        // Merge and withdraw in current block
        vm.warp(2);
        escrow.merge(tokenId2, tokenId1);
        nftLock.approve(address(escrow), tokenId1);
        
        // Should succeed - no createLock in current transaction
        escrow.beginWithdrawal(tokenId1);
        assertEq(escrow.votingPower(tokenId1), 0);
    }

    // Row 6: createLock ❌, merge ❌, split ✅, beginWithdrawal ✅ => Should allow
    function test_AtomicWithdrawal_SplitOnly() public {
        super.mintAndApproveEscrow();
        
        // Create token in previous block
        vm.warp(1);
        uint256 tokenId = escrow.createLock(20e18);
        
        // Split and withdraw in current block
        vm.warp(2);
        uint256 splitTokenId = escrow.split(tokenId, 10e18);
        
        // Should succeed - no createLock in current transaction
        nftLock.approve(address(escrow), tokenId);
        escrow.beginWithdrawal(tokenId);
        assertEq(escrow.votingPower(tokenId), 0);
        
        // Also test withdrawing the split token
        nftLock.approve(address(escrow), splitTokenId);
        escrow.beginWithdrawal(splitTokenId);
        assertEq(escrow.votingPower(splitTokenId), 0);
    }

    // Row 7: createLock ❌, merge ✅, split ✅, beginWithdrawal ✅ => Should allow
    function test_AtomicWithdrawal_MergeAndSplit() public {
        super.mintAndApproveEscrow();
        
        // Create tokens in previous block
        vm.warp(1);
        uint256 tokenId1 = escrow.createLock(15e18);
        uint256 tokenId2 = escrow.createLock(5e18);
        
        // Merge, split and withdraw in current block
        vm.warp(2);
        escrow.merge(tokenId2, tokenId1);
        uint256 splitTokenId = escrow.split(tokenId1, 10e18);
        
        nftLock.approve(address(escrow), tokenId1);
        
        // Should succeed - no createLock in current transaction
        escrow.beginWithdrawal(tokenId1);
        assertEq(escrow.votingPower(tokenId1), 0);
        
        // Also test withdrawing the split token
        nftLock.approve(address(escrow), splitTokenId);
        escrow.beginWithdrawal(splitTokenId);
        assertEq(escrow.votingPower(splitTokenId), 0);
    }
}
