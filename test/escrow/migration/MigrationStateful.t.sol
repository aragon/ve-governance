/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";

// aragon contracts
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
import {MockDAOFactory} from "@mocks/osx/MockDAOFactory.sol";
import {MockERC20} from "@mocks/MockERC20.sol";
import {createTestDAO} from "@mocks/MockDAO.sol";

import "@helpers/OSxHelpers.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";

import {IGaugeVote} from "src/voting/ISimpleGaugeVoter.sol";
import {IVotingEscrowEventsStorageErrorsEvents} from "@escrow-interfaces/IVotingEscrowIncreasing.sol";
import {IWhitelistErrors, IWhitelistEvents} from "@escrow-interfaces/ILock.sol";
import {Lock} from "@escrow/Lock.sol";
import {VotingEscrow} from "@escrow/VotingEscrowIncreasing.sol";
import {QuadraticIncreasingEscrow} from "@escrow/QuadraticIncreasingEscrow.sol";
import {ExitQueue} from "@escrow/ExitQueue.sol";
import {SimpleGaugeVoter, SimpleGaugeVoterSetup} from "src/voting/SimpleGaugeVoterSetup.sol";
import {Clock} from "@clock/Clock.sol";

import {MigrationBase} from "./MigrationBase.sol";
import {MockMigrator} from "@mocks/MockMigrator.sol";

/**
 * @dev Tests various real world scenarios where we have migrations from contracts
 */
contract TestMigrationStateful is MigrationBase, IGaugeVote {
    MockMigrator migrator;
    GaugeVote[] votes;
    address gauge = address(0x777);
    function setUp() public override {
        super.setUp();
        migrator = new MockMigrator();
    }

    // tests votes reset if the user is voting
    function testVotesResetIfVoting(uint32 _warp) public {
        // setup a gauge vote
        src.voter.createGauge(gauge, "metadata");

        address depositor = address(420);
        src.token.mint(depositor, 100 ether);
        uint tokenId;

        vm.startPrank(depositor);
        {
            src.token.approve(address(src.escrow), 100 ether);
            tokenId = src.escrow.createLock(100 ether);

            // arbitrary jump for voting power
            vm.warp(1 weeks);
            // next voting window
            vm.warp(src.clock.resolveEpochVoteStartTs(block.timestamp) + 1);

            // vote
            votes.push(GaugeVote(100 ether, gauge));
            src.voter.vote(tokenId, votes);

            // check votes are set
            assertGt(src.voter.totalVotingPowerCast(), 0, "votes cast");
        }
        vm.stopPrank();

        // random warp: means we can be in either voting or non-voting period
        vm.warp(block.timestamp + uint(_warp));
        src.escrow.enableMigration(address(migrator));

        vm.startPrank(depositor);
        {
            // migrate - requires approving the escrow
            src.nftLock.approve(address(src.escrow), tokenId);
            src.escrow.migrateFrom(tokenId);

            // check votes are reset
            assertEq(src.voter.totalVotingPowerCast(), 0, "votes cast after migration");
        }
        vm.stopPrank();
    }

    function testExitingUserIsUnaffected() public {
        dst.dao.grant({
            _who: address(src.escrow),
            _where: address(dst.escrow),
            _permissionId: dst.escrow.MIGRATOR_ROLE()
        });

        address alice = address(0xa11ce);
        address bob = address(0xb0b);

        src.token.mint(alice, 100 ether);
        src.token.mint(bob, 100 ether);

        uint aliceTokenId;
        uint bobTokenId;
        // user 1 and 2 create lock
        vm.startPrank(alice);
        {
            src.token.approve(address(src.escrow), 100 ether);
            aliceTokenId = src.escrow.createLock(100 ether);
        }
        vm.stopPrank();

        vm.startPrank(bob);
        {
            src.token.approve(address(src.escrow), 100 ether);
            bobTokenId = src.escrow.createLock(100 ether);
        }
        vm.stopPrank();

        src.escrow.enableMigration(address(dst.escrow));

        // u1 goes through the exit queue
        vm.warp(10 weeks); // arbitrary time

        vm.startPrank(alice);
        {
            src.nftLock.approve(address(src.escrow), aliceTokenId);
            src.escrow.beginWithdrawal(aliceTokenId);

            // check #1: can't now migrate
            vm.expectRevert(NotOwner.selector);
            src.escrow.migrateFrom(aliceTokenId);
        }
        vm.stopPrank();

        // u2 migrates
        vm.startPrank(bob);
        {
            src.nftLock.approve(address(src.escrow), bobTokenId);
            src.escrow.migrateFrom(bobTokenId);

            // cant withdraw as doesn't exist
            vm.expectRevert("ERC721: invalid token ID");
            src.escrow.beginWithdrawal(bobTokenId);
        }
        vm.stopPrank();

        // check #2: u1 can still exit
        vm.startPrank(alice);
        {
            vm.warp(block.timestamp + 52 weeks); // arbitrary time
            src.escrow.withdraw(aliceTokenId);
        }
        vm.stopPrank();

        // expect empty state on src
        assertEq(src.nftLock.totalSupply(), 0, "src total supply");
        assertEq(src.escrow.totalLocked(), 0, "src total locked");
        assertEq(src.escrow.locked(aliceTokenId).amount, 0, "src alice locked amount");
        assertEq(src.escrow.locked(bobTokenId).amount, 0, "src bob locked amount");
        assertEq(src.nftLock.balanceOf(alice), 0, "src alice balance");
        assertEq(src.nftLock.balanceOf(bob), 0, "src bob balance");
        assertEq(src.token.balanceOf(address(src.escrow)), 0, "src escrow balance");
        assertEq(src.token.balanceOf(alice), 100 ether, "src alice balance");

        // expect state on dst
        assertEq(dst.nftLock.totalSupply(), 1, "dst total supply");
        assertEq(dst.escrow.totalLocked(), 100 ether, "dst total locked");
        // remember bob is now id 1 on dst
        assertEq(dst.escrow.locked(1).amount, 100 ether, "dst bob locked amount");
        assertEq(dst.nftLock.balanceOf(alice), 0, "dst alice balance");
        assertEq(dst.nftLock.balanceOf(bob), 1, "dst bob balance");
        assertEq(dst.nftLock.ownerOf(1), bob, "dst bob owner");
        assertEq(dst.token.balanceOf(address(dst.escrow)), 100 ether, "dst escrow balance");
    }
}
