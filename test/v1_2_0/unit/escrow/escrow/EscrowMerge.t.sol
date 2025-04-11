pragma solidity ^0.8.17;

import {EscrowBase} from "../../../base/EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

import {Clock, IClock, Lock, VotingEscrow, LinearIncreasingEscrow, IVotingEscrowIncreasing, IEscrowCurveIncreasing, IVotingEscrowIncreasing, IVotingEscrowCoreErrors, IMerge, IMergeEventsAndErrors, ISplit, ILockedBalanceIncreasing, IEscrowCurveGlobalStorage, IEscrowCurveTokenStorage} from "../../../versions.sol";

contract TestEscrowMerge is IEscrowCurveTokenStorage, EscrowBase, IMergeEventsAndErrors {
    function setUp() public override {
        super.setUp();

        super.mintAndApproveEscrow();
    }

    function canMerge(uint256 _startForFrom, uint256 _startForTo) private view returns (bool) {
        return
            escrow.canMerge(
                LockedBalance(Lock_1_Amount, uint48(_startForFrom)),
                LockedBalance(Lock_2_Amount, uint48(_startForTo))
            );
    }

    function test_shouldRevert_IfNotMatureAndDifferentStart() public {
        uint256 from = escrow.createLock(Lock_1_Amount);

        uint256 startForFrom = weekStartTs(block.timestamp);

        // Warp so start dates end up different..
        vm.warp(block.timestamp + checkpointInterval);
        uint256 to = escrow.createLock(Lock_2_Amount);

        uint256 startForTo = weekStartTs(block.timestamp);

        assertEq(canMerge(startForFrom, startForTo), false);

        //reverts as start dates are different and tokens are not mature.
        vm.expectRevert(abi.encodeWithSelector(CannotMerge.selector, from, to));

        escrow.merge(from, to);
    }

    function test_shouldRevert_IfSenderIsNotApprovedOrOwner() public {
        uint256 from = escrow.createLock(Lock_1_Amount);
        uint256 to = escrow.createLock(Lock_2_Amount);

        vm.startPrank(address(999));
        vm.expectRevert(IVotingEscrowCoreErrors.NotApprovedOrOwner.selector);
        escrow.merge(from, to);
    }

    function test_shouldRevert_BothNFTsAreSame() public {
        uint256 from = escrow.createLock(Lock_1_Amount);

        vm.expectRevert(SameNFT.selector);
        escrow.merge(from, from);
    }

    function test_StartDate_NotChangeForToToken() public {
        vm.warp(checkpointInterval + 1 hours);

        uint256 startTime = weekStartTs(block.timestamp);

        uint256 from = escrow.createLock(Lock_1_Amount);
        uint256 to = escrow.createLock(Lock_2_Amount);
        vm.warp(startTime + maxTime);

        // merge should become possible since both are mature
        assertEq(canMerge(startTime, startTime), true);
        escrow.merge(from, to);

        // start date stays the same
        assertEq(escrow.locked(to).start, startTime);
    }

    function test_FromTokenIsCorrectlyBurnt() public {
        // warp so start dates don't end up 0..
        // important as `from` token's locked object becomes 0 after merge
        // and would incorrectly match the start date of from before
        // merging(which would be 0 as well without warping)
        vm.warp(checkpointInterval + 1 hours);

        uint256 from = escrow.createLock(Lock_1_Amount);
        uint256 to = escrow.createLock(Lock_2_Amount);

        vm.warp(block.timestamp + maxTime);

        // before merging, sender owns 2 tokens.
        assertEq(nftLock.balanceOf(address(this)), 2);

        escrow.merge(from, to);

        LockedBalance memory lockedFrom = escrow.locked(from);

        // check that `from` token object doesn't exist anymore
        assertEq(lockedFrom.start, 0);
        assertEq(lockedFrom.amount, 0);

        // after merge, sender only owns one token.
        assertEq(nftLock.balanceOf(address(this)), 1);

        // Ensure that `from` token was burnt and not `to`.
        assertEq(nftLock.ownerOf(to), address(this));
        vm.expectRevert();
        nftLock.ownerOf(from);
    }

    function test_TotalLockedDoesnotChange() public {
        uint256 from = escrow.createLock(Lock_1_Amount);
        uint256 to = escrow.createLock(Lock_2_Amount);

        vm.warp(block.timestamp + maxTime);
        escrow.merge(from, to);

        LockedBalance memory locked = escrow.locked(to);

        uint256 total = Lock_1_Amount + Lock_2_Amount;
        assertEq(locked.amount, total);
        assertEq(escrow.totalLocked(), total);
    }

    function test_MergedEventIsEmitted() public {
        uint256 from = escrow.createLock(Lock_1_Amount);
        uint256 to = escrow.createLock(Lock_2_Amount);
        vm.warp(block.timestamp + maxTime);
        vm.expectEmit();

        emit Merged(
            address(this),
            from,
            to,
            uint208(Lock_1_Amount),
            uint208(Lock_2_Amount),
            uint208(Lock_1_Amount + Lock_2_Amount)
        );
        escrow.merge(from, to);
    }
}
