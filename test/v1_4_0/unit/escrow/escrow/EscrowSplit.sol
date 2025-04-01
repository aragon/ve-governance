pragma solidity ^0.8.17;

import {EscrowBase} from "../../../base/EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

import {Clock, IClock, Lock, VotingEscrow, LinearIncreasingEscrow, IVotingEscrowIncreasing, IEscrowCurveIncreasing, IVotingEscrowIncreasing, IVotingEscrowCoreErrors, IMerge, ISplit, ILockedBalanceIncreasing, IEscrowCurveGlobalStorage, IEscrowCurveTokenStorage, ISplitEventsAndErrors} from "../../../versions.sol";

contract TestEscrowSplit is EscrowBase, ISplitEventsAndErrors {
    function setUp() public override {
        super.setUp();

        super.mintAndApproveEscrow();
    }

    function test_shouldRevert_IfSenderIsNotApprovedOrOwner() public {
        uint256 from = escrow.createLock(Lock_1_Amount);

        vm.startPrank(address(999));
        vm.expectRevert(IVotingEscrowCoreErrors.NotApprovedOrOwner.selector);
        escrow.split(from, 10);
    }

    function test_shouldRevert_ifAmountZero() public {
        uint256 from = escrow.createLock(Lock_1_Amount);

        vm.expectRevert(IVotingEscrowCoreErrors.ZeroAmount.selector);
        escrow.split(from, 0);
    }

    function test_shouldRevert_ifAmountTooBig() public {
        uint256 from = escrow.createLock(Lock_1_Amount);

        vm.expectRevert(SplitAmountTooBig.selector);
        escrow.split(from, Lock_1_Amount);
    }

    function test_fromTokenIsCorrectlyBurnt() public {
        vm.warp(checkpointInterval + 1 hours);

        uint256 from = escrow.createLock(Lock_1_Amount);

        escrow.split(from, Lock_1_Amount - 10);

        LockedBalance memory lockedFrom = escrow.locked(from);

        // check that `from` token object doesn't exist anymore
        assertEq(lockedFrom.start, 0);
        assertEq(lockedFrom.amount, 0);

        vm.expectRevert();
        nftLock.ownerOf(from);
    }

    function test_CreatesTwoNewTokensAndWithSameStartDate() public {
        vm.warp(checkpointInterval + 1 hours);

        uint256 originalTokenStartTs = weekStartTs(block.timestamp);

        uint256 splitVal = 1200;

        uint256 token1Value = Lock_1_Amount - splitVal;
        uint256 token2Value = splitVal;

        uint256 from = escrow.createLock(Lock_1_Amount);

        // warp so even though the start should give different week,
        // the new tokens stills should use original token's start.
        vm.warp(block.timestamp + checkpointInterval + 1 hours);
        escrow.split(from, splitVal);

        LockedBalance memory token1 = escrow.locked(from + 1);
        LockedBalance memory token2 = escrow.locked(from + 2);

        assertEq(token1.amount, token1Value);
        assertEq(token1.start, originalTokenStartTs);

        assertEq(token2.amount, token2Value);
        assertEq(token2.start, originalTokenStartTs);
    }

    function test_SplitEventIsEmitted() public {
        uint256 splitVal = 20;
        uint256 from = escrow.createLock(Lock_1_Amount);
        vm.expectEmit();
        emit Split(
            from,
            from + 1,
            from + 2,
            address(this),
            uint208(Lock_1_Amount - splitVal),
            uint208(splitVal)
        );
        escrow.split(from, splitVal);
    }
}
