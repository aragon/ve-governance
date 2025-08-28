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

            vm.prank(_users[i].user);
            escrow.beginWithdrawal(tokenIds[i]);

            uint256 afterBeginWithdraw = ivotesAdapter.getVotes(_users[i].delegatee);

            assertApproxEqAbs(afterBeginWithdraw, beforeBeginWithdraw - vpBefore[i], 1);
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

            vm.prank(_users[i].user);
            escrow.cancelWithdrawalRequest(tokenIds[i]);

            uint256 afterCancelWithdraw = ivotesAdapter.getVotes(_users[i].delegatee);

            assertApproxEqAbs(afterCancelWithdraw, beforeCancelWithdraw + vpBefore[i], 1);
            assertEq(escrow.votingPower(tokenIds[i]), vpBefore[i]);
        }

    }
}
