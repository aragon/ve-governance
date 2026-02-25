pragma solidity ^0.8.17;

import {EscrowBase} from "../../base/EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/src/MultisigSetup.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

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
    IEscrowCurveGlobalStorage
} from "../../versions.sol";

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
        uint256 from = escrow.createLock(Lock_2_Amount);
        uint256 to = escrow.createLock(Lock_1_Amount);

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

    function testFuzz_Merge(
        uint184 _lock1Amount,
        uint184 _lock2Amount,
        uint48 _fromLockTime,
        uint48 _toLockTime,
        uint48 _mergeTime
    ) public {
        (_fromLockTime, _toLockTime, _mergeTime) = boundLockCreationFuzzTimes(
            _fromLockTime,
            _toLockTime,
            _mergeTime
        );

        vm.assume(_toLockTime >= _fromLockTime && _mergeTime >= _toLockTime);
        vm.assume(_lock1Amount > 0 && _lock2Amount > 0);

        // If start dates of locks don't match,
        // in order to merge, both tokens have to be mature.
        // So we restrict `_mergeTime` to be greater than
        // both token's maturity date.
        if (_fromLockTime != _toLockTime) {
            vm.assume(_mergeTime > _toLockTime + maxTime);
        }

        mintAndApproveEscrow(uint256(_lock1Amount) + uint256(_lock2Amount));

        // Create 2 locks on fuzzed times and
        // merge them on fuzzed time as well.
        vm.warp(_fromLockTime);
        uint256 from = escrow.createLock(_lock1Amount);
        vm.warp(_toLockTime);
        uint256 to = escrow.createLock(_lock2Amount);
        vm.warp(_mergeTime);
        escrow.merge(from, to);

        uint256 currentTs = block.timestamp;
        uint256 fromLockWeekTs = weekStartTs(_fromLockTime);
        uint256 toLockWeekTs = weekStartTs(_toLockTime);
        uint256 fromLockEnd = fromLockWeekTs + maxTime;
        uint256 toLockEnd = toLockWeekTs + maxTime;

        assertTokenPoint(
            from,
            // If the dates match, it should use
            // a single block/record for gas efficiency,
            // otherwise 2.
            _mergeTime == _fromLockTime ? 1 : 2,
            0,
            0,
            fromLockWeekTs,
            currentTs
        );


        {
            int256 bias;

            if (_mergeTime >= toLockEnd) {
                bias = biasFP(_lock1Amount, maxTime) + biasFP(_lock2Amount, maxTime);
            } else {
                bias =
                    biasFP(_lock1Amount, _mergeTime - fromLockWeekTs) +
                    biasFP(_lock2Amount, _mergeTime - toLockWeekTs);
            }
            

            int256 slope = 0;
            if (_mergeTime < toLockEnd) {
                slope = slopeFP(_lock1Amount) + slopeFP(_lock2Amount);
            }

            assertTokenPoint(
                to,
                // If the dates match, it should use
                // a single block/record for gas efficiency,
                // otherwise 2.
                _mergeTime == _toLockTime ? 1 : 2,
                bias,
                slope,
                toLockWeekTs,
                currentTs
            );

            assertGlobalPoint(
                expectedIndex(_fromLockTime, _toLockTime, _mergeTime),
                bias,
                slope,
                currentTs
            );
        }

        if (fromLockWeekTs == toLockWeekTs) {
            assertEq(slopeChanges(toLockEnd), slopeFP(_lock1Amount) + slopeFP(_lock2Amount));
        } else {
            assertEq(slopeChanges(fromLockEnd), slopeFP(_lock1Amount));
            assertEq(slopeChanges(toLockEnd), slopeFP(_lock2Amount));
        }
    }
}
