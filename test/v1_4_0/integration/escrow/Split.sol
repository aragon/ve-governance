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

contract TestSplit is EscrowBase {
    
    function setUp() public override {
        super.setUp();
    }

    function test_Split_shouldRevert_IfSenderIsNotApprovedOrOwner() public {
        uint256 from = escrow.createLock(Lock_1_Amount);

        vm.startPrank(address(999));
        vm.expectRevert(IVotingEscrowCoreErrors.NotApprovedOrOwner.selector);
        escrow.split(from, 10);
    }

    function test_Split_shouldRevert_ifAmountZero() public {
        uint256 from = escrow.createLock(Lock_1_Amount);

        vm.expectRevert(IVotingEscrowCoreErrors.ZeroAmount.selector);
        escrow.split(from, 0);
    }

    function test_Split_shouldRevert_ifAmountTooBig() public {
        uint256 from = escrow.createLock(Lock_1_Amount);

        vm.expectRevert(ISplit.SplitAmountTooBig.selector);
        escrow.split(from, Lock_1_Amount);
    }

    function test_Split_TokenNotMature() public {
        // 1. the tokenId's point must become 0
        // 2. we should have 2 new tokenIds with `value` and `Lock_1_Amount - value` with their according bias and slope.
        // 3. total supply at current timestamp must be both of the token's bias summed up till that point.
        // 4. check that after the original token's end, the total supply doesn't increase.
        // 5. slope changes must still include the original token's slope at the same original end.
        uint256 value = 20e18;
        uint256 tokenId = escrow.createLock(Lock_1_Amount);
        (uint256 weekStartTs, uint256 endTs, ) = getTimes();

        // Still warp just to ensure that we changed the current timestamp
        // but not wrap after the end.
        vm.warp(block.timestamp + checkpointInterval);

        // TODO:GIORGI
        // vm.expectEmit();
        // emit ISplit.Split(tokenId, 2, 3, sender, Lock_1_Amount - value, value);

        escrow.split(tokenId, value);   
        uint256 currentTs = block.timestamp;

        int256 slope1 = slopeFP(Lock_1_Amount - value);
        int256 slope2 = slopeFP(value);

        // 1
        uint256 mainTokenIdEpoch = curve.tokenPointLatestIndex(tokenId);
        assertEq(mainTokenIdEpoch, 2);

        TokenPoint memory mainP = curve.tokenPointHistory(tokenId, mainTokenIdEpoch);

        assertEq(mainP.coefficients[0], 0);
        assertEq(mainP.coefficients[1], 0);
        assertEq(mainP.checkpointTs, weekStartTs);
        assertEq(mainP.writtenTs, block.timestamp);

        // 2
        {
            uint256 token1Epoch = curve.tokenPointLatestIndex(2);
            assertEq(token1Epoch, 1);
            TokenPoint memory token1P = curve.tokenPointHistory(
                2, // tokenId
                token1Epoch
            );

            assertEq(
                token1P.coefficients[0],
                biasFP(Lock_1_Amount - value, block.timestamp - weekStartTs)
            );
            assertEq(token1P.coefficients[1], slope1);
            assertEq(token1P.checkpointTs, weekStartTs);
            assertEq(token1P.writtenTs, block.timestamp);

            uint256 token2Epoch = curve.tokenPointLatestIndex(3);
            assertEq(token2Epoch, 1);
            TokenPoint memory token2P = curve.tokenPointHistory(
                3, // tokenId
                token2Epoch
            );

            assertEq(token2P.coefficients[0], biasFP(value, block.timestamp - weekStartTs));
            assertEq(token2P.coefficients[1], slope2);
            assertEq(token2P.checkpointTs, weekStartTs);
            assertEq(token2P.writtenTs, block.timestamp);
        }

        // 3.
        assertTotalSupply(
            currentTs,
            biasFP(Lock_1_Amount - value, currentTs - weekStartTs) +
                biasFP(value, currentTs - weekStartTs)
        );

        assertTotalSupply(currentTs, biasFP(Lock_1_Amount, currentTs - weekStartTs));

        // 4.
        assertTotalSupply(
            endTs,
            biasFP(Lock_1_Amount - value, endTs - weekStartTs) + biasFP(value, endTs - weekStartTs)
        );
        assertTotalSupply(endTs, biasFP(Lock_1_Amount, endTs - weekStartTs));

        assertTotalSupply(
            endTs + 5,
            biasFP(Lock_1_Amount - value, endTs - weekStartTs) + biasFP(value, endTs - weekStartTs)
        );

        // 5
        assertEq(slopeChanges(endTs), slope1 + slope2);
    }

    function test_Split_TokenAlreadyMature() public {
        // 1. TotalSupply before and after the split must not change.
        // 2. the tokenId's point must become 0
        // 3. we should have 2 new tokenIds with `value` and `Lock_1_Amount - value` with their according bias and slope.
        // 4. total supply at current timestamp must be both of the token's max-out biases summed up.
        // 5. slope changes must still include the original token's slope at the same original end.
        uint256 value = 20e18;
        uint256 tokenId = escrow.createLock(Lock_1_Amount);
        (uint256 weekStartTs, uint256 endTs, ) = getTimes();

        // warp after the token end so it's mature.
        vm.warp(endTs + 1 hours);

        // 1
        assertTotalSupply(block.timestamp, biasFP(Lock_1_Amount, endTs - weekStartTs));
        escrow.split(tokenId, value);
        assertTotalSupply(block.timestamp, biasFP(Lock_1_Amount, endTs - weekStartTs));

        uint256 currentTs = block.timestamp;

        // 2
        uint256 mainTokenIdEpoch = curve.tokenPointLatestIndex(tokenId);
        assertEq(mainTokenIdEpoch, 2);

        TokenPoint memory mainP = curve.tokenPointHistory(tokenId, mainTokenIdEpoch);

        assertEq(mainP.coefficients[0], 0);
        assertEq(mainP.coefficients[1], 0);
        assertEq(mainP.checkpointTs, weekStartTs);
        assertEq(mainP.writtenTs, block.timestamp);

        // 2
        {
            uint256 token1Epoch = curve.tokenPointLatestIndex(2);
            assertEq(token1Epoch, 1);
            TokenPoint memory token1P = curve.tokenPointHistory(
                2, // tokenId
                token1Epoch
            );

            assertEq(token1P.coefficients[0], biasFP(Lock_1_Amount - value, endTs - weekStartTs));
            assertEq(token1P.coefficients[1], slopeFP(Lock_1_Amount - value));
            assertEq(token1P.checkpointTs, weekStartTs);
            assertEq(token1P.writtenTs, block.timestamp);

            uint256 token2Epoch = curve.tokenPointLatestIndex(3);
            assertEq(token2Epoch, 1);
            TokenPoint memory token2P = curve.tokenPointHistory(
                3, // tokenId
                token2Epoch
            );

            assertEq(token2P.coefficients[0], biasFP(value, endTs - weekStartTs));
            assertEq(token2P.coefficients[1], slopeFP(value));
            assertEq(token2P.checkpointTs, weekStartTs);
            assertEq(token2P.writtenTs, block.timestamp);
        }

        // 3.
        assertTotalSupply(
            currentTs,
            biasFP(Lock_1_Amount - value, endTs - weekStartTs) + biasFP(value, endTs - weekStartTs)
        );

        assertTotalSupply(currentTs, biasFP(Lock_1_Amount, endTs - weekStartTs));

        // 4.
        assertTotalSupply(
            endTs,
            biasFP(Lock_1_Amount - value, endTs - weekStartTs) + biasFP(value, endTs - weekStartTs)
        );
        assertTotalSupply(endTs, biasFP(Lock_1_Amount, endTs - weekStartTs));

        assertTotalSupply(
            endTs + 5,
            biasFP(Lock_1_Amount - value, endTs - weekStartTs) + biasFP(value, endTs - weekStartTs)
        );

        // 5
        assertEq(slopeChanges(endTs), slopeFP(Lock_1_Amount));
    }
}
