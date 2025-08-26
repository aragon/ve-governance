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

contract TestSplit_Supply is IEscrowCurveTokenStorage, IEscrowCurveGlobalStorage, EscrowBase {
    function setUp() public override {
        super.setUp();

        super.mintAndApproveEscrow();

        escrow.setEnableSplit(address(this), true);
    }

    function test_Split_TokenNotMature() public {
        // 1. total supply at current timestamp must be both of the token's bias summed up till that point.
        // 2. check that after the original token's end, the total supply doesn't increase.
        uint256 value = 20e18;
        uint256 tokenId = escrow.createLock(Lock_1_Amount);
        uint256 weekStartTs = weekStartTs(block.timestamp);
        uint256 endTs = getEndTimestamp(weekStartTs, block.timestamp);

        // Still warp just to ensure that we changed the current timestamp
        // but not wrap after the end.
        vm.warp(block.timestamp + checkpointInterval);

        escrow.split(tokenId, value);
        uint256 currentTs = block.timestamp;

        // 1.
        assertTotalSupply(
            currentTs,
            biasFP(Lock_1_Amount - value, currentTs - weekStartTs) +
                biasFP(value, currentTs - weekStartTs)
        );

        assertTotalSupply(currentTs, biasFP(Lock_1_Amount, currentTs - weekStartTs));

        // 2.
        assertTotalSupply(
            endTs,
            biasFP(Lock_1_Amount - value, endTs - weekStartTs) + biasFP(value, endTs - weekStartTs)
        );
        assertTotalSupply(endTs, biasFP(Lock_1_Amount, endTs - weekStartTs));

        assertTotalSupply(
            endTs + 5,
            biasFP(Lock_1_Amount - value, endTs - weekStartTs) + biasFP(value, endTs - weekStartTs)
        );
    }

    function test_Split_TokenAlreadyMature() public {
        // 1. TotalSupply before and after the split must not change.
        // 2. total supply at current timestamp must be both of the token's max-out biases summed up.
        uint256 value = 20e18;
        uint256 tokenId = escrow.createLock(Lock_1_Amount);
        uint256 weekStartTs = weekStartTs(block.timestamp);
        uint256 endTs = getEndTimestamp(weekStartTs, block.timestamp);

        // warp after the token end so it's mature.
        vm.warp(endTs + 1 hours);

        // 1
        assertTotalSupply(block.timestamp, biasFP(Lock_1_Amount, endTs - weekStartTs));
        escrow.split(tokenId, value);
        assertTotalSupply(block.timestamp, biasFP(Lock_1_Amount, endTs - weekStartTs));

        uint256 currentTs = block.timestamp;

        // 2.
        assertTotalSupply(
            currentTs,
            biasFP(Lock_1_Amount - value, endTs - weekStartTs) + biasFP(value, endTs - weekStartTs)
        );

        assertTotalSupply(currentTs, biasFP(Lock_1_Amount, endTs - weekStartTs));

        assertTotalSupply(
            endTs,
            biasFP(Lock_1_Amount - value, endTs - weekStartTs) + biasFP(value, endTs - weekStartTs)
        );
        assertTotalSupply(endTs, biasFP(Lock_1_Amount, endTs - weekStartTs));

        assertTotalSupply(
            endTs + 5,
            biasFP(Lock_1_Amount - value, endTs - weekStartTs) + biasFP(value, endTs - weekStartTs)
        );
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

        int256 bias;
        if (_splitTime > fromLockEnd) {
            bias = biasFP(_lock1Amount, maxTime);
        } else {
            bias =
                biasFP(_lock1Amount - _splitValue, _splitTime - fromLockWeekTs) +
                biasFP(_splitValue, _splitTime - fromLockWeekTs);
        }

        assertTotalSupply(currentTs, bias);
    }
}
