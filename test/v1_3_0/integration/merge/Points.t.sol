pragma solidity ^0.8.17;

import {EscrowBase} from "../../base/EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

import {Clock, IClock, Lock, VotingEscrow, LinearIncreasingEscrow, IVotingEscrowIncreasing, IEscrowCurveIncreasing, IVotingEscrowIncreasing, IVotingEscrowCoreErrors, IMerge, ISplit, ILockedBalanceIncreasing, IEscrowCurveGlobalStorage, IEscrowCurveTokenStorage, IEscrowCurveGlobalStorage} from "../../versions.sol";

contract TestMerge_Points is IEscrowCurveTokenStorage, IEscrowCurveGlobalStorage, EscrowBase {
    function setUp() public override {
        super.setUp();

        super.mintAndApproveEscrow();
    }

    function test_Merge_WhenNotMature_SameStartDate() public {
        // 1. on `from` token point, bias and slope must become 0. `start` should stay the same and current timestamp updated.
        // 2. on `to` token point, bias and slope must include both token's bias and slope. `start` should stay the same and current timestamp updated.
        // 3. latest global point  must have the same data as the latest token point of `to`.
        // 3. Since `to` tokens is not mature yet, end is in the future, so slopeChanges must still contain the sum of both slopes.
        uint256 from = escrow.createLock(Lock_1_Amount);
        uint256 to = escrow.createLock(Lock_2_Amount);

        uint256 currentTs = block.timestamp;
        uint256 weekStartTs = weekStartTs(currentTs);

        escrow.merge(from, to);

        uint256 fromLatestEpoch = curve.tokenPointLatestIndex(from);
        assertEq(fromLatestEpoch, 1);

        // 1
        assertTokenPoint(from, 1, 0, 0, weekStartTs, currentTs);

        int256 currentTotalBiasFP = biasFP(Lock_1_Amount, currentTs - weekStartTs) +
            biasFP(Lock_2_Amount, currentTs - weekStartTs);

        int256 totalSlopeFP = slopeFP(Lock_1_Amount) + slopeFP(Lock_2_Amount);

        // 2
        // since merge occured in the same block as `createLock`,
        // it should not cause extra epoch for user.
        assertTokenPoint(
            to, // tokenId
            1, // latestIndex
            currentTotalBiasFP,
            totalSlopeFP,
            weekStartTs,
            currentTs
        );

        // 3
        assertGlobalPoint(1, currentTotalBiasFP, totalSlopeFP, currentTs);

        // 4
        assertEq(slopeChanges(weekStartTs + maxTime), totalSlopeFP);
    }

    function test_Merge_WhenMature_SameStartDate() public {
        // 1. on `from` token point, bias and slope must become 0. `start` should stay the same and current timestamp updated.
        // 2. on `to` token point, bias must be the sum of both token's maxed out values. Slope must be 0 as it's already maxed out.
        // `start` should stay the same and current timestamp updated.
        // 3. last global point must have slope 0 and bias as sum of both token's maxed out values.
        // 4. Since both have the same end and is in the past, slopeChanges must still be the same of both slopes.
        uint256 from = escrow.createLock(Lock_1_Amount);
        uint256 to = escrow.createLock(Lock_2_Amount);

        uint256 weekStartTs = weekStartTs(block.timestamp);

        uint256 end = weekStartTs + maxTime;
        int256 LOCK_1_MAX = biasFP(Lock_1_Amount, end - weekStartTs);
        int256 LOCK_2_MAX = biasFP(Lock_2_Amount, end - weekStartTs);

        vm.warp(end + 1 hours);
        escrow.merge(from, to);

        uint256 currentTs = block.timestamp;

        // 1
        assertTokenPoint(from, 2, 0, 0, weekStartTs, currentTs);

        // 2
        // since merge occured in the different block than `createLock`,
        // it should  cause extra epoch for user.
        int256 currentTotalBiasFP = LOCK_1_MAX + LOCK_2_MAX;
        int256 totalSlopeFP = slopeFP(Lock_1_Amount + Lock_2_Amount);

        assertTokenPoint(to, 2, currentTotalBiasFP, 0, weekStartTs, currentTs);

        // 3
        uint256 lastIndex = (currentTs - Lock_1_start) / checkpointInterval + 2;
        assertGlobalPoint(lastIndex, currentTotalBiasFP, 0, currentTs);

        // 4
        assertEq(slopeChanges(end), totalSlopeFP);
    }

    function test_Merge_WhenMature_DifferentStartDates() public {
        // 1. on `from` token point, bias and slope must become 0. `start` should stay the same and current timestamp updated.
        // 2. on `to` token point, bias must be the sum of both token's maxed out values. Slope must be 0 as it's already maxed out.
        // `start` should stay the same and current timestamp updated.
        // 3. last global point must have slope 0 and bias as sum of both token's maxed out values.
        // 4. Since `to`'s end is greater than `from`'s end, and we make `from` to become 0, `to`'s slope change must also include `to`'s slope.
        uint256 from = escrow.createLock(Lock_1_Amount);

        uint256 fromLockWeekStart = weekStartTs(block.timestamp);
        uint256 fromLockEnd = fromLockWeekStart + maxTime;

        vm.warp(block.timestamp + checkpointInterval);
        uint256 to = escrow.createLock(Lock_2_Amount);

        uint256 toLockWeekStart = weekStartTs(block.timestamp);
        uint256 toLockEnd = toLockWeekStart + maxTime;

        // we merge after both are mature.
        vm.warp(toLockEnd + 1 hours);
        escrow.merge(from, to);

        uint256 currentTs = block.timestamp;

        // 1
        assertTokenPoint(
            from, // tokenId
            2, // latestIndex
            0,
            0,
            fromLockWeekStart,
            currentTs
        );

        int256 currentTotalBiasFP = biasFP(Lock_1_Amount, fromLockEnd - fromLockWeekStart) +
            biasFP(Lock_2_Amount, toLockEnd - toLockWeekStart);

        // 2
        assertTokenPoint(
            to, // tokenId
            2, // latestIndex
            currentTotalBiasFP,
            0,
            toLockWeekStart,
            currentTs
        );

        // 3
        uint256 lastIndex = (currentTs - Lock_1_start) / checkpointInterval + 3;
        assertGlobalPoint(lastIndex, currentTotalBiasFP, 0, currentTs);

        // 4
        assertEq(slopeChanges(fromLockEnd), slopeFP(Lock_1_Amount));
        assertEq(slopeChanges(toLockEnd), slopeFP(Lock_2_Amount));
    }
}
