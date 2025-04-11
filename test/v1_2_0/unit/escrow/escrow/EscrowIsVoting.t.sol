pragma solidity ^0.8.17;

import {EscrowBase} from "../../../base/EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

import {
    Lock,
    Clock,
    VotingEscrow,
    QuadraticIncreasingEscrow,
    ExitQueue,
    SimpleGaugeVoter,
    SimpleGaugeVoterSetup,
    IEscrowCurveIncreasing,
    IEscrowCurveTokenStorage
} from "../../../versions.sol";

contract TestIsVoting is IEscrowCurveTokenStorage, EscrowBase {
    function setUp() public override {
        super.setUp();
    }

    function test_shouldReturnFalseIfNotDelegated() public {
        uint256 tokenId = 1;

        vm.expectCall(
            address(ivotesAdapter),
            abi.encodeWithSelector(ivotesAdapter.tokenIsDelegated.selector, (tokenId))
        );
        assertFalse(escrow.isVoting(tokenId));
    }

    function test_shouldCallGaugeVoterWithCorrectDelegateeAddress() public {
        uint256 tokenId = 1;
        address bob = address(456);

        vm.prank(address(escrow));
        nftLock.mint(address(this), tokenId);

        // address(this) is an owner. bob becomes a delegatee.
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
