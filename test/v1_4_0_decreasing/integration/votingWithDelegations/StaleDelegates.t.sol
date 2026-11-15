pragma solidity ^0.8.17;

import {EscrowBase} from "../../base/EscrowBase.sol";

contract TestStaleDelegates is EscrowBase {
    address holder = address(1);
    address attacker = address(2);
    address delegateA = address(3);
    address delegateB = address(4);

    function test_NewLockCannotAddSnapshotPowerThroughStaleDelegates() public {
        uint256 oneStep = 1;
        uint256 staleWeeks = 260;
        uint256 holderAmount = Lock_1_Amount;
        uint256 attackerAmount = Lock_2_Amount;

        // Week 0: create empty records for A and B, then leave both untouched
        uint256 weekZero = weekStartTs(block.timestamp);
        vm.warp(weekZero);
        ivotesAdapter.checkpointTransition(delegateA, oneStep);
        ivotesAdapter.checkpointTransition(delegateB, oneStep);

        // The holder's record also stays untouched. A permanent lock has zero slope
        uint256 holderLockId = _createPermanentLock(holder, holderAmount);
        vm.prank(holder);
        ivotesAdapter.delegate(holder);

        // Week 260, day 1 is the snapshot. The new lock is created and delegated after it
        uint256 snapshotTs = weekZero + staleWeeks * checkpointInterval + 1 days;
        vm.warp(snapshotTs + 1 days);
        _createPermanentLock(attacker, attackerAmount);
        vm.prank(attacker);
        ivotesAdapter.delegate(delegateA);

        // Move the same lock to the second stale delegate
        vm.warp(snapshotTs + 2 days);
        vm.prank(attacker);
        ivotesAdapter.delegate(delegateB);

        uint256 holderPower = curve.votingPowerAt(holderLockId, snapshotTs);
        assertEq(holderPower, bias(holderAmount, 0));
        assertEq(ivotesAdapter.getPastVotes(delegateA, snapshotTs), 0, "A should have no snapshot power");
        assertEq(ivotesAdapter.getPastVotes(delegateB, snapshotTs), 0, "B should have no snapshot power");
        assertEq(ivotesAdapter.getPastVotes(holder, snapshotTs), holderPower);
        assertEq(ivotesAdapter.getPastTotalSupply(snapshotTs), holderPower);
    }

    function _createPermanentLock(address _owner, uint256 _amount) internal returns (uint256 tokenId) {
        mintAndApproveEscrow(_owner, _amount);
        vm.startPrank(_owner);
        tokenId = escrow.createLock(_amount, MAX_TIME);
        escrow.lockPermanent(tokenId);
        vm.stopPrank();
    }
}
