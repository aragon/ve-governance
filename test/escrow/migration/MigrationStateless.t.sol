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

contract TestMigrationStateless is MigrationBase {
    MockMigrator migrator;
    function setUp() public override {
        super.setUp();
        migrator = new MockMigrator();
    }

    function testFuzz_enableOnlyEscrowAdmin(address _notAdmin) public {
        vm.assume(_notAdmin != address(this));

        vm.startPrank(_notAdmin);
        {
            vm.expectRevert(
                _authErr(
                    address(src.dao),
                    _notAdmin,
                    address(src.escrow),
                    src.escrow.ESCROW_ADMIN_ROLE()
                )
            );
            src.escrow.enableMigration(address(1));
        }
        vm.stopPrank();

        // no revert if called by admin
        src.escrow.enableMigration(address(1));
    }

    // enable: can't enable twice
    function testCannotEnableTwice() public {
        src.escrow.enableMigration(address(1));
        vm.expectRevert(MigrationAlreadySet.selector);
        src.escrow.enableMigration(address(2));
    }

    // enable: sets migrator, emits event, can transfer tokens to new contracts
    function testFuzz_enableSetsMigratorAndEmitsEvent(address _migrator) public {
        vm.assume(_migrator != address(0));

        vm.expectEmit(false, false, false, true);
        emit MigrationEnabled(_migrator);
        src.escrow.enableMigration(_migrator);

        assertEq(
            src.token.allowance(address(src.escrow), _migrator),
            type(uint256).max,
            "allowance"
        );
        assertEq(src.escrow.migrator(), _migrator, "migrator");
    }

    // migrate from: can't call if migrator not set
    function testCannotMigrateIfMigratorNotSet() public {
        vm.expectRevert(MigrationNotActive.selector);
        src.escrow.migrateFrom(1);
    }

    function testCannotMigrateIfNotOwner() public {
        address depositor = address(420);

        src.token.mint(depositor, 100 ether);
        uint tokenId;

        vm.startPrank(depositor);
        {
            src.token.approve(address(src.escrow), 100 ether);
            tokenId = src.escrow.createLock(100 ether);
        }
        vm.stopPrank();

        src.escrow.enableMigration(address(migrator));

        vm.expectRevert(NotOwner.selector);
        src.escrow.migrateFrom(tokenId);
    }

    function testCannotMigrateIfNoVotingPower() public {
        address depositor = address(420);

        src.token.mint(depositor, 100 ether);
        uint tokenId;

        vm.startPrank(depositor);
        {
            src.token.approve(address(src.escrow), 100 ether);
            tokenId = src.escrow.createLock(100 ether);
        }
        vm.stopPrank();

        src.escrow.enableMigration(address(migrator));

        vm.startPrank(depositor);
        {
            vm.expectRevert(CannotExit.selector);
            src.escrow.migrateFrom(tokenId);
        }
        vm.stopPrank();
    }
    function testCannotDepositIfMigrationEnabled() public {
        src.escrow.enableMigration(address(dst.escrow));
        address depositor = address(420);

        src.token.mint(depositor, 100 ether);
        uint tokenId;

        vm.startPrank(depositor);
        {
            src.token.approve(address(src.escrow), 100 ether);
            vm.expectRevert(MigrationActive.selector);
            tokenId = src.escrow.createLock(100 ether);
        }
        vm.stopPrank();
    }

    function testCannotMigrateIfMigratorRoleNotGivenToDestination() public {
        address depositor = address(420);

        src.token.mint(depositor, 100 ether);
        uint tokenId;

        vm.startPrank(depositor);
        {
            src.token.approve(address(src.escrow), 100 ether);
            tokenId = src.escrow.createLock(100 ether);

            vm.warp(src.clock.checkpointInterval() + 1);
        }
        vm.stopPrank();

        src.escrow.enableMigration(address(dst.escrow));

        vm.startPrank(depositor);
        {
            vm.expectRevert(
                _authErr(
                    address(dst.dao),
                    address(src.escrow),
                    address(dst.escrow),
                    dst.escrow.MIGRATOR_ROLE()
                )
            );
            src.escrow.migrateFrom(tokenId);
        }
        vm.stopPrank();
    }

    function testMigrateFromAndTo() public {
        dst.dao.grant({
            _who: address(src.escrow),
            _where: address(dst.escrow),
            _permissionId: dst.escrow.MIGRATOR_ROLE()
        });

        address depositor = address(420);

        src.token.mint(depositor, 100 ether);
        uint tokenId;
        uint newTokenId;

        vm.startPrank(depositor);
        {
            src.token.approve(address(src.escrow), 100 ether);
            tokenId = src.escrow.createLock(100 ether);
        }
        vm.stopPrank();

        vm.warp(src.clock.checkpointInterval() + 1);
        src.escrow.enableMigration(address(dst.escrow));

        vm.startPrank(depositor);
        {
            vm.expectEmit(true, true, true, true);
            emit Migrated(depositor, tokenId, 1, 100 ether);
            newTokenId = src.escrow.migrateFrom(tokenId);
        }
        vm.stopPrank();

        assertEq(src.nftLock.totalSupply(), 0);
        assertEq(src.escrow.totalLocked(), 0);
        assertEq(src.curve.tokenPointIntervals(tokenId), 2);
        assertEq(src.curve.tokenPointHistory(tokenId, 2).bias, 0);
        assertEq(src.escrow.locked(tokenId).amount, 0);
        assertEq(src.escrow.locked(tokenId).start, 0);
        assertEq(src.nftLock.balanceOf(depositor), 0);
        assertEq(src.token.balanceOf(address(src.escrow)), 0);

        // check state on destination
        assertEq(dst.nftLock.totalSupply(), 1);
        assertEq(dst.escrow.totalLocked(), 100 ether);
        assertEq(dst.curve.tokenPointIntervals(newTokenId), 1);
        assertEq(dst.curve.tokenPointHistory(newTokenId, 2).bias, 0);
        assertEq(dst.escrow.locked(newTokenId).amount, 100 ether);
        assertEq(
            dst.escrow.locked(newTokenId).start,
            dst.clock.resolveEpochNextCheckpointTs(block.timestamp)
        );
        assertEq(dst.nftLock.balanceOf(depositor), 1);
        assertEq(dst.token.balanceOf(address(dst.escrow)), 100 ether);
    }
}
