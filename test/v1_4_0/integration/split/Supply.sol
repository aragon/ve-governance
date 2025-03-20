pragma solidity ^0.8.17;

import {EscrowBase} from "../../base/EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

import {Clock, IClock, Lock, VotingEscrow, LinearIncreasingEscrow, IVotingEscrowIncreasing, IEscrowCurveIncreasing, IVotingEscrowIncreasing, IVotingEscrowCoreErrors, IMerge, ISplit, ILockedBalanceIncreasing, IEscrowCurveGlobalStorage, IEscrowCurveTokenStorage, IEscrowCurveGlobalStorage} from "../../versions.sol";

contract TestSplit_Supply is IEscrowCurveTokenStorage, IEscrowCurveGlobalStorage, EscrowBase {
    function setUp() public override {
        super.setUp();
    }

    function test_Split_TokenNotMature() public {
        // 1. total supply at current timestamp must be both of the token's bias summed up till that point.
        // 2. check that after the original token's end, the total supply doesn't increase.
        uint256 value = 20e18;
        uint256 tokenId = escrow.createLock(Lock_1_Amount);
        uint256 weekStartTs = weekStartTs(block.timestamp);
        uint256 endTs = weekStartTs + maxTime;

        // Still warp just to ensure that we changed the current timestamp
        // but not wrap after the end.
        vm.warp(block.timestamp + checkpointInterval);

        escrow.split(tokenId, value);
        uint256 currentTs = block.timestamp;

        int256 slope1 = slopeFP(Lock_1_Amount - value);
        int256 slope2 = slopeFP(value);

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
        uint256 endTs = weekStartTs + maxTime;

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
}
