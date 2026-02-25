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

contract TestMerge_Supply is IEscrowCurveTokenStorage, IEscrowCurveGlobalStorage, EscrowBase {
    function setUp() public override {
        super.setUp();

        super.mintAndApproveEscrow();
    }

    function test_Merge_WhenNotMature_SameStartDate() public {
        // 1. total supply at current time include both tokens' bias till this moment.
        // 2. total supply at current time + t should increase from the totalSupply at current time.
        // 3. total supply at `end` and `end + X` must be the same(sum of maxed out values of both tokens) - it should stop increasing.
        uint256 from = escrow.createLock(Lock_1_Amount);
        uint256 to = escrow.createLock(Lock_2_Amount);

        uint256 weekStartTs = weekStartTs(block.timestamp);
        uint256 currentTs = block.timestamp;

        escrow.merge(from, to);

        uint256 fromLatestEpoch = curve.tokenPointLatestIndex(from);
        assertEq(fromLatestEpoch, 1);

        int256 currentTotalBiasFP = biasFP(Lock_1_Amount, currentTs - weekStartTs) +
            biasFP(Lock_2_Amount, currentTs - weekStartTs);

        uint256 end = getEndTimestamp(weekStartTs, currentTs);
        
        int256 LOCK_1_MAX = biasFP(Lock_1_Amount, end - weekStartTs);
        int256 LOCK_2_MAX = biasFP(Lock_2_Amount, end - weekStartTs);

        // 1
        assertTotalSupply(currentTs, currentTotalBiasFP);

        // 2
        assertTotalSupply(
            currentTs + 10,
            currentTotalBiasFP + slopeFP(Lock_1_Amount) * 10 + slopeFP(Lock_2_Amount) * 10
        );

        // 3
        assertTotalSupply(end, LOCK_1_MAX + LOCK_2_MAX);
        assertTotalSupply(end + 10, LOCK_1_MAX + LOCK_2_MAX);
    }

    function test_Merge_WhenMature_SameStartDate() public {
        // 1. total supply at current time must be sum of both token's maxed out values.
        // 2. total supply at currentTime and `currentTime + X` must be the same(sum of maxed out values of both tokens)
        uint256 from = escrow.createLock(Lock_1_Amount);
        uint256 to = escrow.createLock(Lock_2_Amount);

        uint256 weekStartTs = weekStartTs(block.timestamp);

        uint256 end = weekStartTs + maxTime;
        int256 LOCK_1_MAX = biasFP(Lock_1_Amount, end - weekStartTs);
        int256 LOCK_2_MAX = biasFP(Lock_2_Amount, end - weekStartTs);

        vm.warp(end + 1 hours);
        escrow.merge(from, to);

        uint256 currentTs = block.timestamp;

        uint256 fromLatestEpoch = curve.tokenPointLatestIndex(from);
        assertEq(fromLatestEpoch, 2);

        int256 currentTotalBiasFP = LOCK_1_MAX + LOCK_2_MAX;

        // 1, 2
        assertTotalSupply(currentTs - 1, currentTotalBiasFP);
        assertTotalSupply(currentTs, currentTotalBiasFP);
        assertTotalSupply(currentTs + 1, currentTotalBiasFP);
    }

    function test_Merge_WhenMature_DifferentStartDates() public {
        // 1. total supply at current time must be sum of both token's maxed out values.
        // 2. total supply at currentTime and `currentTime + X` must be the same(sum of maxed out values of both tokens)
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

        int256 currentTotalBiasFP = biasFP(Lock_1_Amount, fromLockEnd - fromLockWeekStart) +
            biasFP(Lock_2_Amount, toLockEnd - toLockWeekStart);

        // 1, 2
        assertTotalSupply(currentTs - 1, currentTotalBiasFP);
        assertTotalSupply(currentTs, currentTotalBiasFP);
        assertTotalSupply(currentTs + 1, currentTotalBiasFP);
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
        uint256 toLockEnd = toLockWeekTs + maxTime;
        
        int256 bias;
        
        if (_mergeTime >= toLockEnd) {
            bias = biasFP(_lock1Amount, maxTime) + biasFP(_lock2Amount, maxTime);
        } else {
            bias =
                biasFP(_lock1Amount, _mergeTime - fromLockWeekTs) +
                biasFP(_lock2Amount, _mergeTime - toLockWeekTs);
        }

        assertTotalSupply(currentTs, bias);
    }

    
}
