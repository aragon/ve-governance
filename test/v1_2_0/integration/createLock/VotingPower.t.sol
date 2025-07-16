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

contract TestVotingPower is IEscrowCurveTokenStorage, IEscrowCurveGlobalStorage, EscrowBase {
    function setUp() public override {
        super.setUp();

        super.mintAndApproveEscrow();

        vm.warp(1);
    }

    function test_whenOnlyOneTokenPoint() public {
        // Given: no prior locks existing
        uint256 tokenId = escrow.createLock(Lock_1_Amount);
        uint256 weekStartTs = weekStartTs(block.timestamp);
        uint256 endTs = getEndTimestamp(weekStartTs, block.timestamp);

        // 1
        assertEq(curve.isWarm(tokenId), true);
        assertVotingPower(tokenId,  biasFP(Lock_1_Amount, block.timestamp - weekStartTs));

        // 2
        int256 maxVotingPower = biasFP(Lock_1_Amount, endTs - weekStartTs);
        assertVotingPower(tokenId, endTs, maxVotingPower);
        assertVotingPower(tokenId, endTs + 10, maxVotingPower);
    }

    function test_whenMultipleTokenPoints_NotMature() public {
        uint256 weekStartTs = weekStartTs(block.timestamp);

        uint256 tokenId1 = escrow.createLock(Lock_1_Amount);
        uint256 tokenId2 = escrow.createLock(Lock_2_Amount);

        vm.warp(block.timestamp + 10);

        escrow.merge(tokenId1, tokenId2);
        uint256 endTs = getEndTimestamp(weekStartTs, block.timestamp);

        assertVotingPower(
            tokenId2,
            biasFP(Lock_1_Amount, block.timestamp - weekStartTs) +
                biasFP(Lock_2_Amount, block.timestamp - weekStartTs)
        );

        int256 maxVotingPower = biasFP(Lock_1_Amount, maxTime) + biasFP(Lock_2_Amount, maxTime);
        assertVotingPower(tokenId2, endTs, maxVotingPower);
        assertVotingPower(tokenId2, endTs + 10, maxVotingPower);
    }

    function test_whenMultipleTokenPoints_Mature() public {
        uint256 weekStartTs = weekStartTs(block.timestamp);
        uint256 endTs = getEndTimestamp(weekStartTs, block.timestamp);

        uint256 tokenId1 = escrow.createLock(Lock_1_Amount);
        uint256 tokenId2 = escrow.createLock(Lock_2_Amount);

        vm.warp(endTs + 1);

        escrow.merge(tokenId1, tokenId2);

        int256 maxVotingPower = biasFP(Lock_1_Amount, maxTime) + biasFP(Lock_2_Amount, maxTime);
        assertVotingPower(tokenId2, endTs, biasFP(Lock_2_Amount, maxTime));
        assertVotingPower(tokenId2, endTs + 10, maxVotingPower);
        assertVotingPower(tokenId2, endTs + 20, maxVotingPower);
    }
}
