pragma solidity ^0.8.17;

import {EscrowBase} from "./EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

import {IEscrowCurveUserStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {VotingEscrow} from "@escrow/VotingEscrowIncreasing.sol";

import {SimpleGaugeVoter, SimpleGaugeVoterSetup} from "src/voting/SimpleGaugeVoterSetup.sol";
import {IGaugeVote} from "src/voting/ISimpleGaugeVoter.sol";

contract TestSweep is EscrowBase, IEscrowCurveUserStorage, IGaugeVote {
    function setUp() public override {
        super.setUp();

        // grant the sweeper role to this contract
        dao.grant({
            _who: address(this),
            _where: address(escrow),
            _permissionId: escrow.SWEEPER_ROLE()
        });
    }

    function testCanSweepExcessTokens() public {
        token.mint(address(escrow), 1000);

        assertEq(token.balanceOf(address(escrow)), 1000);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(escrow.totalLocked(), 0);

        vm.expectEmit(true, false, false, true);
        emit Sweep(address(this), 1000);
        escrow.sweep();

        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(token.balanceOf(address(this)), 1000);
    }

    function testCannotSweepFromLocked() public {
        address user = address(1);
        token.mint(address(user), 1000);

        vm.startPrank(user);
        {
            token.approve(address(escrow), 1000);
            escrow.createLock(1000);
        }
        vm.stopPrank();

        assertEq(token.balanceOf(address(escrow)), 1000);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(escrow.totalLocked(), 1000);

        // first try with no excess tokens
        vm.expectRevert(NothingToSweep.selector);
        escrow.sweep();

        // check that nothing changed
        assertEq(token.balanceOf(address(escrow)), 1000);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(escrow.totalLocked(), 1000);

        // now try with excess tokens
        token.mint(address(escrow), 1000);

        assertEq(token.balanceOf(address(escrow)), 2000);

        escrow.sweep();

        assertEq(token.balanceOf(address(escrow)), 1000);
        assertEq(token.balanceOf(address(this)), 1000);
        assertEq(escrow.totalLocked(), 1000);
    }

    function testOnlySweeperRole() public {
        address notThis = address(1);

        bytes memory err = _authErr(notThis, address(escrow), escrow.SWEEPER_ROLE());

        vm.prank(notThis);
        vm.expectRevert(err);
        escrow.sweep();

        vm.prank(notThis);
        vm.expectRevert(err);
        escrow.sweepNFT(1, address(this));
    }

    function testCannotSweepNFTIfNotInContract() public {
        // create a lock
        token.mint(address(this), 1000);
        token.approve(address(escrow), 1000);
        uint tokenId = escrow.createLock(1000);

        // try to sweep the NFT -- should fail as it's not in the contract
        vm.expectRevert(NothingToSweep.selector);
        escrow.sweepNFT(tokenId, address(this));
    }

    function testCannotSweepNFTIfInQueue() public {
        // create lock, enter withdrawal
        token.mint(address(this), 1000);
        token.approve(address(escrow), 1000);
        uint tokenId = escrow.createLock(1000);

        // warp to the min lock
        vm.warp(1 weeks);

        nftLock.approve(address(escrow), tokenId);
        escrow.beginWithdrawal(tokenId);

        // try to sweep the NFT -- should fail as it's in the queue
        vm.expectRevert(CannotExit.selector);
        escrow.sweepNFT(tokenId, address(this));
    }

    function testCannotSweepNFTIfNotWhitelisted() public {
        // create the lock and transfer the NFT to the contract
        token.mint(address(this), 1000);
        token.approve(address(escrow), 1000);
        uint tokenId = escrow.createLock(1000);
        nftLock.transferFrom(address(this), address(escrow), tokenId);

        // try to sweep the NFT -- should fail as this address is not whitelisted
        vm.expectRevert(NotWhitelisted.selector);
        escrow.sweepNFT(tokenId, address(this));
    }

    function testCanSweepNFT() public {
        // create, transfer, whitelis, sweep
        token.mint(address(this), 1000);
        token.approve(address(escrow), 1000);
        uint tokenId = escrow.createLock(1000);
        nftLock.transferFrom(address(this), address(escrow), tokenId);
        nftLock.setWhitelisted(address(this), true);

        assertEq(nftLock.balanceOf(address(this)), 0);
        assertEq(nftLock.balanceOf(address(escrow)), 1);

        vm.expectEmit(true, false, false, true);
        emit SweepNFT(address(this), tokenId);
        escrow.sweepNFT(tokenId, address(this));

        assertEq(nftLock.balanceOf(address(this)), 1);
        assertEq(nftLock.balanceOf(address(escrow)), 0);
    }

    // Needed for the ERC721Receiver interface
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
