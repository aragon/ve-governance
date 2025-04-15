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
    Curve as LinearIncreasingEscrow,
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
        // 2. we should have 2 new tokenIds with `value` and `Lock_1_Amount - value` with their according bias and slope.
        uint256 value = 20e18;
        uint256 tokenId = escrow.createLock(Lock_1_Amount);
        uint256 weekStartTs = weekStartTs(block.timestamp);

        // Still warp just to ensure that we changed the current timestamp
        // but not wrap after the end.
        vm.warp(block.timestamp + checkpointInterval);

        escrow.split(tokenId, value);

        int256 slope1 = slopeFP(Lock_1_Amount - value);
        int256 slope2 = slopeFP(value);

        uint256 elapsed = block.timestamp - weekStartTs;

        // 1
        assertTokenPoint(tokenId, 2, 0, 0, weekStartTs, block.timestamp);

        // 2
        assertTokenPoint(
            2,
            1,
            biasFP(Lock_1_Amount - value, elapsed),
            slope1,
            weekStartTs,
            block.timestamp
        );

        assertTokenPoint(3, 1, biasFP(value, elapsed), slope2, weekStartTs, block.timestamp);
    }

    function test_Split_TokenAlreadyMature() public {
        // 1. the tokenId's point must become 0
        // 2. we should have 2 new tokenIds with `value` and `Lock_1_Amount - value` with their according bias and slope.
        uint256 value = 20e18;
        uint256 tokenId = escrow.createLock(Lock_1_Amount);
        uint256 weekStartTs = weekStartTs(block.timestamp);
        uint256 endTs = weekStartTs + maxTime;

        // warp after the token end so it's mature.
        vm.warp(endTs + 1 hours);

        escrow.split(tokenId, value);

        // 1
        assertTokenPoint(tokenId, 2, 0, 0, weekStartTs, block.timestamp);

        uint256 elapsed = endTs - weekStartTs;

        // 2
        assertTokenPoint(
            2,
            1,
            biasFP(Lock_1_Amount - value, elapsed),
            0,
            weekStartTs,
            block.timestamp
        );

        assertTokenPoint(
            3,
            1,
            biasFP(value, elapsed),
            0,
            weekStartTs,
            block.timestamp
        );
    }
}
