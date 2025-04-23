pragma solidity ^0.8.17;

import {EscrowBase} from "../../../base/EscrowBase.sol";

import {
    Lock,
    Clock,
    VotingEscrow,
    ExitQueue,
    SimpleGaugeVoter,
    SimpleGaugeVoterSetup,
    IEscrowCurveIncreasing,
    IEscrowCurveTokenStorage,
    IEscrowIVotesAdapter
} from "../../../versions.sol";

contract TestIsVoting is IEscrowCurveTokenStorage, EscrowBase {
    function setUp() public override {
        super.setUp();
    }

    function test_shouldRevertIfNonExistentToken() public {
        vm.expectRevert("ERC721: invalid token ID");
        escrow.isVoting(10000);
    }

    function test_shouldReturnFalseIfNotDelegated() public {
        vm.prank(address(escrow));
        nftLock.mint(address(this), 1);

        assertFalse(escrow.isVoting(1));
    }

    function test_shouldCallGaugeVoterWithCorrectDelegateeAddress() public {
        uint256 tokenId = 1;
        address bob = address(456);

        vm.prank(address(escrow));
        nftLock.mint(address(this), tokenId);

        // address(this) is an owner. bob becomes a delegatee.
        ivotesAdapter.setAutoDelegationDisabled(true);
        ivotesAdapter.delegate(bob);
        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        ivotesAdapter.delegate(ids);

        // Since bob is the delegatee, gauge voter's `isVoting`
        // must be called with that address.
        vm.expectCall(address(voter), abi.encodeWithSelector(voter.isVoting.selector, (bob)));
        escrow.isVoting(tokenId);
    }
}
