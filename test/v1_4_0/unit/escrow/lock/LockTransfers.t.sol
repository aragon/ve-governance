pragma solidity ^0.8.17;

import {EscrowBase} from "../../../base/EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

import {
    Lock,
    Clock,
    VotingEscrow,
    ExitQueue,
    SimpleGaugeVoter,
    SimpleGaugeVoterSetup,
    IEscrowCurveTokenStorage
} from "../../../versions.sol";

contract TestLockTransfers is IEscrowCurveTokenStorage, EscrowBase {
    uint deposit = 100e18;

    address fromAddress = address(1234);
    address toAddress = address(4321);
    address unlisted = address(3333);
    uint tokenId;

    function setUp() public override {
        super.setUp();

        // create an NFT
        token.mint(address(this), type(uint).max);
        token.approve(address(escrow), type(uint).max);
        tokenId = escrow.createLockFor(deposit, fromAddress);
    }

    function testCannotTransferByDefault() public {
        vm.expectRevert(NotWhitelisted.selector);
        vm.prank(fromAddress);
        nftLock.transferFrom(fromAddress, toAddress, tokenId);

        // check approve workflow
        vm.prank(fromAddress);
        nftLock.approve(address(this), 1);
        vm.expectRevert(NotWhitelisted.selector);
        nftLock.transferFrom(fromAddress, toAddress, tokenId);
    }

    function testCanTransferToAndFromIfWhitelisted() public {
        nftLock.setWhitelisted(toAddress, true);

        assertEq(nftLock.balanceOf(fromAddress), 1);
        assertEq(nftLock.balanceOf(toAddress), 0);

        // can transfer to the toAddress
        vm.prank(fromAddress);
        nftLock.transferFrom(fromAddress, toAddress, tokenId);

        assertEq(nftLock.balanceOf(fromAddress), 0);
        assertEq(nftLock.balanceOf(toAddress), 1);

        // can transfer back
        vm.prank(toAddress);
        nftLock.transferFrom(toAddress, fromAddress, tokenId);

        assertEq(nftLock.balanceOf(fromAddress), 1);
        assertEq(nftLock.balanceOf(toAddress), 0);

        // but not to unlisted
        vm.prank(fromAddress);
        vm.expectRevert(NotWhitelisted.selector);
        nftLock.safeTransferFrom(fromAddress, unlisted, tokenId);
    }

    function testCanTransferToAndFromIfGloballyEnabled() public {
        nftLock.enableTransfers();

        assertEq(nftLock.balanceOf(fromAddress), 1);
        assertEq(nftLock.balanceOf(toAddress), 0);

        // can transfer to the toAddress
        vm.prank(fromAddress);
        nftLock.transferFrom(fromAddress, toAddress, tokenId);

        assertEq(nftLock.balanceOf(fromAddress), 0);
        assertEq(nftLock.balanceOf(toAddress), 1);

        // can transfer back
        vm.prank(toAddress);
        nftLock.transferFrom(toAddress, fromAddress, tokenId);

        assertEq(nftLock.balanceOf(fromAddress), 1);
        assertEq(nftLock.balanceOf(toAddress), 0);

        // and not to unlisted
        vm.prank(fromAddress);
        nftLock.safeTransferFrom(fromAddress, unlisted, tokenId);

        assertEq(nftLock.balanceOf(fromAddress), 0);
        assertEq(nftLock.balanceOf(toAddress), 0);
        assertEq(nftLock.balanceOf(unlisted), 1);
    }
}
