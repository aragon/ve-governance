pragma solidity ^0.8.17;

import {EscrowBase} from "../../base/EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";
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

contract TestSplit_Points is IEscrowCurveTokenStorage, IEscrowCurveGlobalStorage, EscrowBase {
    function setUp() public override {
        super.setUp();

        super.mintAndApproveEscrow();

        escrow.setEnableSplit(address(this), true);
    }

    function test_Split_TokenNotMature() public {
        // 1. the tokenId's point must become 0
        // 2. we should have one new tokenIds with `value` and `Lock_1_Amount - value` with old token with their according bias and slope.
        // 3. bias and slope on the latest global point must include the same slope and bias as it was originally before splitting.
        // 4. slope changes must still include the original token's slope at the same original end.
        uint256 value = 20e18;
        uint256 tokenId = escrow.createLock(Lock_1_Amount);
        uint256 weekStartTs = weekStartTs(block.timestamp);
        uint256 endTs = weekStartTs + maxTime;

        // Still warp just to ensure that we changed the current timestamp
        // but not wrap after the end.
        vm.warp(block.timestamp + checkpointInterval);
    
        escrow.split(tokenId, value);

        int256 slope1 = slopeFP(Lock_1_Amount - value);
        int256 slope2 = slopeFP(value);

        uint256 elapsed = block.timestamp - weekStartTs;

        // 1
        assertTokenPoint(
            tokenId,
            2,
            biasFP(Lock_1_Amount - value, elapsed),
            slope1,
            weekStartTs,
            block.timestamp
        );

        // 2
        assertTokenPoint(2, 1, biasFP(value, elapsed), slope2, weekStartTs, block.timestamp);

        // 3
        assertGlobalPoint(
            3,
            biasFP(Lock_1_Amount, elapsed),
            slopeFP(Lock_1_Amount),
            block.timestamp
        );

        // 4
        assertEq(slopeChanges(endTs), slope1 + slope2);
    }

    function test_Split_TokenAlreadyMature() public {
        // 1. the tokenId's point must become 0
        // 2. we should have one new tokenId with `value` and current token with `Lock_1_Amount - value` with their according bias and slope.
        // 3. slope on the last global point must be 0 as it was stored after both tokens were mature. bias must be maxed out.
        // 4. slope changes must still include the original token's slope at the same original end.
        uint256 value = 20e18;
        uint256 tokenId = escrow.createLock(Lock_1_Amount);
        uint256 weekStartTs = weekStartTs(block.timestamp);
        uint256 endTs = weekStartTs + maxTime;

        // warp after the token end so it's mature.
        vm.warp(endTs + 1 hours);

        escrow.split(tokenId, value);
        uint256 elapsed = endTs - weekStartTs;

        // 1
        assertTokenPoint(
            tokenId,
            2,
            biasFP(Lock_1_Amount - value, elapsed),
            0,
            weekStartTs,
            block.timestamp
        );

        // 2
        assertTokenPoint(2, 1, biasFP(value, elapsed), 0, weekStartTs, block.timestamp);

        // 3
        uint256 lastIndex = (block.timestamp - Lock_1_start) / checkpointInterval + 2;
        assertGlobalPoint(lastIndex, biasFP(Lock_1_Amount, elapsed), 0, block.timestamp);

        // 4
        assertEq(slopeChanges(endTs), slopeFP(Lock_1_Amount));
    }

    function testFuzz_Split(
        uint192 _lock1Amount,
        uint192 _splitValue,
        uint48 _fromLockTime,
        uint192 _splitTime
    ) public {
        (_fromLockTime, _splitTime) = boundLockCreationFuzzTimes(_fromLockTime, _splitTime);

        // Split requirements to work with.
        vm.assume(_lock1Amount > 0 && _splitValue > 0);
        vm.assume(_splitValue < _lock1Amount);
        uint256 minDeposit = escrow.minDeposit();
        vm.assume(_splitValue >= minDeposit && _lock1Amount - _splitValue >= minDeposit);

        mintAndApproveEscrow(uint256(_lock1Amount));

        // Create 2 locks on fuzzed times and
        // merge them on fuzzed time as well.
        vm.warp(_fromLockTime);
        uint256 from = escrow.createLock(_lock1Amount);
        vm.warp(_splitTime);
        escrow.split(from, _splitValue);

        uint256 currentTs = block.timestamp;
        uint256 fromLockWeekTs = weekStartTs(_fromLockTime);
        uint256 fromLockEnd = fromLockWeekTs + maxTime;

        {
            int256 bias1;
            int256 slope1;
            int256 bias2;
            int256 slope2;
            if (_splitTime >= fromLockEnd) {
                bias1 = biasFP(_lock1Amount - _splitValue, maxTime);
                bias2 = biasFP(_splitValue, maxTime);
            } else {
                bias1 = biasFP(_lock1Amount - _splitValue, _splitTime - fromLockWeekTs);
                bias2 = biasFP(_splitValue, _splitTime - fromLockWeekTs);
                slope1 = slopeFP(_lock1Amount - _splitValue);
                slope2 = slopeFP(_splitValue);
            }

            assertTokenPoint(
                from,
                // If the dates match, it should use
                // a single block/record for gas efficiency,
                // otherwise 2.
                _splitTime == _fromLockTime ? 1 : 2,
                bias1,
                slope1,
                fromLockWeekTs,
                currentTs
            );

            assertTokenPoint(2, 1, bias2, slope2, fromLockWeekTs, currentTs);
        }

        {
            int256 bias;
            int256 slope;
            if (_splitTime >= fromLockEnd) {
                bias = biasFP(_lock1Amount, maxTime);
            } else {
                bias = biasFP(_lock1Amount, _splitTime - fromLockWeekTs);
                slope = slopeFP(_lock1Amount);
            }

            assertGlobalPoint(
                expectedIndex(_fromLockTime, _splitTime, _splitTime),
                bias,
                slope,
                currentTs
            );
        }

        assertEq(slopeChanges(fromLockEnd), slopeFP(_lock1Amount));
    }
}
