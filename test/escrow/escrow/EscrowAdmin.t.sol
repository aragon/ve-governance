pragma solidity ^0.8.17;

import {EscrowBase} from "./EscrowBase.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

import {Lock} from "@escrow/Lock.sol";
import {VotingEscrow} from "@escrow/VotingEscrowIncreasing.sol";
import {QuadraticIncreasingEscrow} from "@escrow/QuadraticIncreasingEscrow.sol";
import {ExitQueue} from "@escrow/ExitQueue.sol";
import {SimpleGaugeVoter, SimpleGaugeVoterSetup} from "src/voting/SimpleGaugeVoterSetup.sol";

contract TestEscrowAdmin is EscrowBase {
    address attacker = address(1);

    function testCannotResetLockNFT() public {
        vm.expectRevert(LockNFTAlreadySet.selector);
        escrow.setLockNFT(address(0));
    }

    function testSetCurve(address _newCurve) public {
        escrow.setCurve(_newCurve);
        assertEq(escrow.curve(), _newCurve);

        bytes memory err = _authErr(attacker, address(escrow), escrow.ESCROW_ADMIN_ROLE());
        vm.prank(attacker);
        vm.expectRevert(err);
        escrow.setCurve(_newCurve);
        escrow.setCurve(address(0));
    }

    function testSetMinDeposit(uint256 _newMinDeposit) public {
        vm.expectEmit(false, false, false, true);
        emit MinDepositSet(_newMinDeposit);
        escrow.setMinDeposit(_newMinDeposit);
        assertEq(escrow.minDeposit(), _newMinDeposit);

        bytes memory err = _authErr(attacker, address(escrow), escrow.ESCROW_ADMIN_ROLE());
        vm.prank(attacker);
        vm.expectRevert(err);
        escrow.setMinDeposit(_newMinDeposit);
    }

    function testSetVoter(address _newVoter) public {
        escrow.setVoter(_newVoter);
        assertEq(escrow.voter(), _newVoter);

        bytes memory err = _authErr(attacker, address(escrow), escrow.ESCROW_ADMIN_ROLE());
        vm.prank(attacker);
        vm.expectRevert(err);
        escrow.setVoter(_newVoter);
        escrow.setVoter(address(0));
    }

    function testSetQueue(address _newQueue) public {
        escrow.setQueue(_newQueue);
        assertEq(escrow.queue(), _newQueue);

        bytes memory err = _authErr(attacker, address(escrow), escrow.ESCROW_ADMIN_ROLE());
        vm.prank(attacker);
        vm.expectRevert(err);
        escrow.setQueue(_newQueue);
    }

    function testUUPSUpgrade() public {
        address newImpl = address(new VotingEscrow());
        escrow.upgradeTo(newImpl);
        assertEq(escrow.implementation(), newImpl);

        bytes memory err = _authErr(attacker, address(escrow), escrow.ESCROW_ADMIN_ROLE());
        vm.prank(attacker);
        vm.expectRevert(err);
        escrow.upgradeTo(newImpl);
    }

    function testPause() public {
        escrow.pause();
        assertTrue(escrow.paused());

        escrow.unpause();
        assertFalse(escrow.paused());

        bytes memory err = _authErr(attacker, address(escrow), escrow.PAUSER_ROLE());
        vm.startPrank(attacker);
        {
            vm.expectRevert(err);
            escrow.pause();

            vm.expectRevert(err);
            escrow.unpause();
        }
        vm.stopPrank();
    }

    function testCannotCallPausedFunctions() public {
        escrow.pause();

        bytes memory PAUSEABLE_ERROR = "Pausable: paused";

        vm.expectRevert(PAUSEABLE_ERROR);
        escrow.createLock(100);

        vm.expectRevert(PAUSEABLE_ERROR);
        escrow.createLockFor(100, address(this));

        vm.expectRevert(PAUSEABLE_ERROR);
        escrow.beginWithdrawal(100);

        vm.expectRevert(PAUSEABLE_ERROR);
        escrow.withdraw(100);
    }

    function testWhitelist() public {
        address addr = address(1);
        vm.expectEmit(true, false, false, true);
        emit WhitelistSet(addr, true);

        nftLock.setWhitelisted(addr, true);
        assertTrue(nftLock.whitelisted(addr));

        nftLock.setWhitelisted(addr, false);
        assertFalse(nftLock.whitelisted(addr));

        nftLock.enableTransfers();
        assertTrue(
            nftLock.whitelisted(address(uint160(uint256(keccak256("WHITELIST_ANY_ADDRESS")))))
        );

        bytes memory err = _authErr(attacker, address(nftLock), nftLock.LOCK_ADMIN_ROLE());

        vm.startPrank(attacker);
        {
            vm.expectRevert(err);
            nftLock.setWhitelisted(addr, true);

            vm.expectRevert(err);
            nftLock.enableTransfers();
        }
        vm.stopPrank();
    }

    // test unusued function revert
    function testUnusedFunctionRevert() public {
        vm.expectRevert();
        escrow.totalVotingPowerAt(0);

        vm.expectRevert();
        escrow.totalVotingPower();
    }

    // test upgrading the lock
    function testUpgradeLock() public {
        address newImpl = address(new Lock());
        nftLock.upgradeTo(newImpl);
        assertEq(nftLock.implementation(), newImpl);

        bytes memory err = _authErr(attacker, address(nftLock), nftLock.LOCK_ADMIN_ROLE());
        vm.prank(attacker);
        vm.expectRevert(err);
        nftLock.upgradeTo(newImpl);
    }

    // hal-16 should not be possible to unwhitelist the escrow
    function testUnwhitelistEscrow() public {
        address escrowAddr = nftLock.escrow();
        vm.expectRevert(ForbiddenWhitelistAddress.selector);
        nftLock.setWhitelisted(escrowAddr, false);
    }
}
