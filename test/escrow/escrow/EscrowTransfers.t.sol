pragma solidity ^0.8.17;

import {EscrowBase} from "./EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

import {IEscrowCurveTokenStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {VotingEscrow} from "@escrow/VotingEscrowIncreasing.sol";

import {SimpleGaugeVoter, SimpleGaugeVoterSetup} from "src/voting/SimpleGaugeVoterSetup.sol";

contract TestEscrowTransfers is EscrowBase, IEscrowCurveTokenStorage {
    uint deposit = 100e18;
    uint tokenId;

    function setUp() public override {
        super.setUp();

        // create an NFT
        token.mint(address(this), deposit);
        token.approve(address(escrow), deposit);
        tokenId = escrow.createLock(deposit);

        assertEq(nftLock.balanceOf(address(this)), 1);
    }

    function testCannotTransferByDefault() public {
        vm.expectRevert(NotWhitelisted.selector);
        nftLock.transferFrom(address(this), address(123), tokenId);

        vm.expectRevert(NotWhitelisted.selector);
        nftLock.safeTransferFrom(address(this), address(123), tokenId);
    }

    function testCanTransferIfWhitelisted() public {
        nftLock.setWhitelisted(address(123), true);

        assertEq(nftLock.balanceOf(address(123)), 0);
        assertEq(nftLock.balanceOf(address(this)), 1);

        nftLock.transferFrom(address(this), address(123), tokenId);

        assertEq(nftLock.balanceOf(address(123)), 1);
        assertEq(nftLock.balanceOf(address(this)), 0);
    }
}
