pragma solidity ^0.8.17;

import {EscrowBase} from "../../../base/EscrowBase.sol";

import {
    Lock,
    VotingEscrow,
    IEscrowCurveTokenStorage
} from "../../../versions.sol";

contract TestLockBaseURI is IEscrowCurveTokenStorage, EscrowBase {
    event BaseURISet(string baseURI);

    uint deposit = 100e18;
    address owner = address(1234);
    address attacker = address(1);
    uint tokenId;

    function setUp() public override {
        super.setUp();

        token.mint(address(this), type(uint).max);
        token.approve(address(escrow), type(uint).max);
        tokenId = escrow.createLockFor(deposit, owner);
    }

    function testTokenURIDefaultEmpty() public {
        assertEq(nftLock.tokenURI(tokenId), "");
    }

    function testSetBaseURIUpdatesTokenURI() public {
        nftLock.setBaseURI("https://example.com/metadata/");

        assertEq(
            nftLock.tokenURI(tokenId),
            string.concat("https://example.com/metadata/", vm.toString(tokenId))
        );
    }

    function testSetBaseURIAppliesToAllTokens() public {
        uint tokenId2 = escrow.createLockFor(deposit, address(4321));

        nftLock.setBaseURI("https://example.com/metadata/");

        assertEq(
            nftLock.tokenURI(tokenId),
            string.concat("https://example.com/metadata/", vm.toString(tokenId))
        );
        assertEq(
            nftLock.tokenURI(tokenId2),
            string.concat("https://example.com/metadata/", vm.toString(tokenId2))
        );
    }

    function testSetBaseURICanBeUpdated() public {
        nftLock.setBaseURI("https://old.com/");
        assertEq(
            nftLock.tokenURI(tokenId),
            string.concat("https://old.com/", vm.toString(tokenId))
        );

        nftLock.setBaseURI("https://new.com/");
        assertEq(
            nftLock.tokenURI(tokenId),
            string.concat("https://new.com/", vm.toString(tokenId))
        );
    }

    function testSetBaseURICanBeCleared() public {
        nftLock.setBaseURI("https://example.com/");
        nftLock.setBaseURI("");

        assertEq(nftLock.tokenURI(tokenId), "");
    }

    function testSetBaseURIEmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit BaseURISet("https://example.com/metadata/");
        nftLock.setBaseURI("https://example.com/metadata/");
    }

    function testSetBaseURIRevertsIfUnauthorized() public {
        bytes memory err = _authErr(attacker, address(nftLock), nftLock.LOCK_ADMIN_ROLE());

        vm.prank(attacker);
        vm.expectRevert(err);
        nftLock.setBaseURI("https://example.com/");
    }

    function testTokenURIRevertsForNonexistentToken() public {
        vm.expectRevert("ERC721: invalid token ID");
        nftLock.tokenURI(999);
    }
}
