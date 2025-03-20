pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {
    Clock, 
    IClock, 
    Lock, 
    VotingEscrow, 
    LinearIncreasingEscrow, 
    IVotingEscrowIncreasing, 
    IEscrowCurveIncreasing, 
    IVotingEscrowIncreasing, 
    IVotingEscrowCoreErrors, 
    IMerge, 
    ISplit, 
    ILockedBalanceIncreasing, 
    IEscrowCurveGlobalStorage, 
    IEscrowCurveTokenStorage
} from "../../versions.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {EscrowBase} from "./EscrowBase.sol";

contract TestMerge is EscrowBase {
    
    function setUp() public override {
        super.setUp();
    }

    function test_Merge_WhenNotMature_SameStartDate() public {
        // 1. on `from` token point, bias and slope must become 0. `start` should stay the same and current timestamp updated.
        // 2. on `to` token point, bias and slope must include both token's bias and slope. `start` should stay the same and current timestamp updated.
        // 3. total supply at current time include both tokens' bias till this moment.
        // 4. total supply at current time + t should increase from the totalSupply at current time.
        // 5. total supply at `end` and `end + X` must be the same(sum of maxed out values of both tokens) - it should stop increasing.
        // 6. Since `to` tokens is not mature yet, end is in the future, so slopeChanges must still contain the sum of both slopes.
        uint256 from = escrow.createLock(Lock_1_Amount);
        uint256 to = escrow.createLock(Lock_2_Amount);

        (uint256 weekStartTs, uint256 endTs, uint256 currentTs) = getTimes();

        // TODO:GIORGI
        // vm.expectEmit();
        // emit IMerge.Merged(sender, from, to, Lock_1_Amount, Lock_2_Amount, Lock_1_Amount + Lock_2_Amount);

        escrow.merge(from, to);

        uint256 fromLatestEpoch = curve.tokenPointLatestIndex(from);
        assertEq(fromLatestEpoch, 1);

        // 1
        TokenPoint memory fromP = curve.tokenPointHistory(from, fromLatestEpoch);

        assertEq(fromP.coefficients[0], 0);
        assertEq(fromP.coefficients[1], 0);
        assertEq(fromP.checkpointTs, weekStartTs); 
        assertEq(fromP.writtenTs, currentTs);

        // 2
        // since merge occured in the same block as `createLock`,
        // it should not cause extra epoch for user.
        uint256 toLatestEpoch = curve.tokenPointLatestIndex(to);
        assertEq(toLatestEpoch, 1);

        TokenPoint memory toP = curve.tokenPointHistory(to, toLatestEpoch);

        int256 currentTotalBiasFP = biasFP(Lock_1_Amount, currentTs - weekStartTs) +
            biasFP(Lock_2_Amount, currentTs - weekStartTs);

        assertEq(toP.coefficients[0], currentTotalBiasFP);
        assertEq(toP.coefficients[1], slopeFP(Lock_1_Amount) + slopeFP(Lock_2_Amount));
        assertEq(toP.checkpointTs, weekStartTs);
        assertEq(toP.writtenTs, currentTs);

        uint256 end = weekStartTs + maxTime;
        int256 LOCK_1_MAX = biasFP(Lock_1_Amount, end - weekStartTs);
        int256 LOCK_2_MAX = biasFP(Lock_2_Amount, end - weekStartTs);

        // 3
        assertTotalSupply(currentTs, currentTotalBiasFP);

        // 4
        assertTotalSupply(
            currentTs + 10,
            currentTotalBiasFP + slopeFP(Lock_1_Amount) * 10 + slopeFP(Lock_2_Amount) * 10
        );

        // 5
        assertTotalSupply(end, LOCK_1_MAX + LOCK_2_MAX);
        assertTotalSupply(end + 10, LOCK_1_MAX + LOCK_2_MAX);

        // 6
        assertEq(slopeChanges(end), slopeFP(Lock_1_Amount) + slopeFP(Lock_2_Amount));
    }

    function test_Merge_WhenMature_SameStartDate() public {
        // 1. on `from` token point, bias and slope must become 0. `start` should stay the same and current timestamp updated.
        // 2. on `to` token point, bias must be the sum of both token's maxed out values. Slope must be 0 as it's already maxed out.
        // `start` should stay the same and current timestamp updated.
        // 3. total supply at current time must be sum of both token's maxed out values.
        // 4. total supply at currentTime and `currentTime + X` must be the same(sum of maxed out values of both tokens)
        // 5. last global point must have slope 0 and bias as sum of both token's maxed out values.
        // 6. Since both have the same end and is in the past, slopeChanges must still be the same of both slopes.
        uint256 from = escrow.createLock(Lock_1_Amount);
        uint256 to = escrow.createLock(Lock_2_Amount);

        (uint256 weekStartTs, uint256 endTs, ) = getTimes();

        uint256 end = weekStartTs + maxTime;
        int256 LOCK_1_MAX = biasFP(Lock_1_Amount, end - weekStartTs);
        int256 LOCK_2_MAX = biasFP(Lock_2_Amount, end - weekStartTs);

        vm.warp(end + 1 hours);
        escrow.merge(from, to);

        uint256 currentTs = block.timestamp;

        uint256 fromLatestEpoch = curve.tokenPointLatestIndex(from);
        assertEq(fromLatestEpoch, 2);

        // 1
        TokenPoint memory fromP = curve.tokenPointHistory(from, fromLatestEpoch);

        assertEq(fromP.coefficients[0], 0);
        assertEq(fromP.coefficients[1], 0);
        assertEq(fromP.checkpointTs, weekStartTs);
        assertEq(fromP.writtenTs, currentTs);

        // 2
        // since merge occured in the different block than `createLock`,
        // it should  cause extra epoch for user.
        uint256 toLatestEpoch = curve.tokenPointLatestIndex(to);
        assertEq(toLatestEpoch, 2);

        TokenPoint memory toP = curve.tokenPointHistory(to, toLatestEpoch);

        int256 currentTotalBiasFP = LOCK_1_MAX + LOCK_2_MAX;

        assertEq(toP.coefficients[0], currentTotalBiasFP);
        assertEq(toP.coefficients[1], slopeFP(Lock_1_Amount + Lock_2_Amount));
        assertEq(toP.checkpointTs, weekStartTs);
        assertEq(toP.writtenTs, currentTs);

        // 3, 4
        assertTotalSupply(currentTs - 1, currentTotalBiasFP);
        assertTotalSupply(currentTs, currentTotalBiasFP);
        assertTotalSupply(currentTs + 1, currentTotalBiasFP);

        // 5
        GlobalPoint memory lastPoint = curve.globalPointHistory(curve.globalPointLatestIndex());

        assertEq(lastPoint.slope, 0);
        assertEq(lastPoint.bias, currentTotalBiasFP);
        assertEq(lastPoint.writtenTs, currentTs);
        // assertEq(lastPoint.start, (currentTs / checkpointInterval) * checkpointInterval); // TODO:GIORGI on the global points, we also store something like lastPoint.start = _newLocked.start
        // in this specific scenario, lastPoint.start becomes the `to` token's start which is in the past. does this make sense at all ?

        // 6
        assertEq(slopeChanges(end), slopeFP(Lock_1_Amount) + slopeFP(Lock_2_Amount));
    }

    function test_Merge_WhenMature_DifferentStartDates() public {
        // 1. on `from` token point, bias and slope must become 0. `start` should stay the same and current timestamp updated.
        // 2. on `to` token point, bias must be the sum of both token's maxed out values. Slope must be 0 as it's already maxed out.
        // `start` should stay the same and current timestamp updated.
        // 3. total supply at current time must be sum of both token's maxed out values.
        // 4. total supply at currentTime and `currentTime + X` must be the same(sum of maxed out values of both tokens)
        // 5. last global point must have slope 0 and bias as sum of both token's maxed out values.
        // 6. Since `to`'s end is greater than `from`'s end, and we make `from` to become 0, `to`'s slope change must also include `to`'s slope.
        uint256 from = escrow.createLock(Lock_1_Amount);
        (uint256 fromLockWeekStart, uint256 fromLockEnd, uint256 fromLockCurrentTime) = getTimes();

        vm.warp(block.timestamp + checkpointInterval);
        uint256 to = escrow.createLock(Lock_2_Amount);
        (uint256 toLockWeekStart, uint256 toLockEnd, uint256 toLockCurrentTime) = getTimes();

        // we merge after both are mature.
        vm.warp(toLockEnd + 1 hours);
        escrow.merge(from, to);

        uint256 currentTs = block.timestamp;

        // 1
        {
            uint256 fromLatestEpoch = curve.tokenPointLatestIndex(from);
            assertEq(fromLatestEpoch, 2);

            TokenPoint memory fromP = curve.tokenPointHistory(from, fromLatestEpoch);

            assertEq(fromP.coefficients[0], 0);
            assertEq(fromP.coefficients[1], 0);
            assertEq(fromP.checkpointTs, fromLockWeekStart);
            assertEq(fromP.writtenTs, currentTs);
        }

        int256 currentTotalBiasFP = biasFP(Lock_1_Amount, fromLockEnd - fromLockWeekStart) +
            biasFP(Lock_2_Amount, toLockEnd - toLockWeekStart);

        // 2
        {
            uint256 toLatestEpoch = curve.tokenPointLatestIndex(to);
            assertEq(toLatestEpoch, 2);

            TokenPoint memory toP = curve.tokenPointHistory(to, toLatestEpoch);

            assertEq(toP.coefficients[0], currentTotalBiasFP);
            assertEq(toP.coefficients[1], slopeFP(Lock_1_Amount) + slopeFP(Lock_2_Amount));
            assertEq(toP.checkpointTs, toLockWeekStart);
            assertEq(toP.writtenTs, currentTs);
        }

        // 3, 4
        assertTotalSupply(currentTs - 1, currentTotalBiasFP);
        assertTotalSupply(currentTs, currentTotalBiasFP);
        assertTotalSupply(currentTs + 1, currentTotalBiasFP);

        // 5
        GlobalPoint memory lastPoint = curve.globalPointHistory(curve.globalPointLatestIndex());

        assertEq(lastPoint.slope, 0);
        assertEq(lastPoint.bias, currentTotalBiasFP);
        assertEq(lastPoint.writtenTs, currentTs);
        // assertEq(lastPoint.start, (currentTs / checkpointInterval) * checkpointInterval); // TODO:GIORGI on the global points, we also store something like lastPoint.start = _newLocked.start
        // // in this specific scenario, lastPoint.start becomes the `to` token's start which is in the past. does this make sense at all ?

        // 6
        assertEq(slopeChanges(fromLockEnd), slopeFP(Lock_1_Amount));
        assertEq(slopeChanges(toLockEnd), slopeFP(Lock_2_Amount));
    }
}
