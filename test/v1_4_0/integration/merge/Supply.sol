pragma solidity ^0.8.17;

import {EscrowBase} from "../../base/EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

import {Clock, IClock, Lock, VotingEscrow, LinearIncreasingEscrow, IVotingEscrowIncreasing, IEscrowCurveIncreasing, IVotingEscrowIncreasing, IVotingEscrowCoreErrors, IMerge, ISplit, ILockedBalanceIncreasing, IEscrowCurveGlobalStorage, IEscrowCurveTokenStorage, IEscrowCurveGlobalStorage} from "../../versions.sol";

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

        uint256 end = weekStartTs + maxTime;
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
}
