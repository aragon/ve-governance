pragma solidity ^0.8.17;

import {EscrowBase} from "../../../base/EscrowBase.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/src/MultisigSetup.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

import {
    Lock,
    Clock,
    VotingEscrow,
    ExitQueue,
    SimpleGaugeVoter,
    SimpleGaugeVoterSetup
} from "../../../versions.sol";

contract TestEscrowAdmin is EscrowBase {
    address attacker = address(1);

    function testCannotResetLockNFT() public {
        vm.expectRevert(LockNFTAlreadySet.selector);
        escrow.setLockNFT(address(0));
    }

    function test_RevertIfIVotesAdapterSetUnauthorized() public {
        VotingEscrow escrow_ = _deployEscrow(address(token), address(dao), address(clock), 1);

        bytes memory err = _authErr(attacker, address(escrow), escrow.ESCROW_ADMIN_ROLE());
        vm.prank(attacker);
        vm.expectRevert(err);
        escrow.setIVotesAdapter(address(2));
    }

    function test_RevertIfIvotesAdapterAlreadySet(address _ivotesAdapter) public {
        vm.expectRevert(AddressAlreadySet.selector);
        escrow.setIVotesAdapter(_ivotesAdapter);
    }

    function test_RevertIfCurveSetUnauthorized() public {
        VotingEscrow escrow_ = _deployEscrow(address(token), address(dao), address(clock), 1);

        bytes memory err = _authErr(attacker, address(escrow), escrow.ESCROW_ADMIN_ROLE());
        vm.prank(attacker);
        vm.expectRevert(err);
        escrow.setCurve(address(2));
    }

    function test_RevertIfCurveAlreadySet(address _newCurve) public {
        vm.expectRevert(AddressAlreadySet.selector);
        escrow.setCurve(_newCurve);
    }

    function test_RevertIfClockSetUnauthorized() public {
        VotingEscrow escrow_ = _deployEscrow(address(token), address(dao), address(clock), 1);

        bytes memory err = _authErr(attacker, address(escrow), escrow.ESCROW_ADMIN_ROLE());
        vm.prank(attacker);
        vm.expectRevert(err);
        escrow.setClock(address(2));
    }

    function test_RevertIfClockAlreadySet(address _newClock) public {
        vm.expectRevert(AddressAlreadySet.selector);
        escrow.setCurve(_newClock);
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

    function test_RevertIfVoterSetUnauthorized() public {
        VotingEscrow escrow_ = _deployEscrow(address(token), address(dao), address(clock), 1);

        bytes memory err = _authErr(attacker, address(escrow), escrow.ESCROW_ADMIN_ROLE());
        vm.prank(attacker);
        vm.expectRevert(err);
        escrow.setVoter(address(2));

        escrow.setVoter(address(2));
    }
    
    function test_RevertIfQueueSetUnauthorized() public {
        VotingEscrow escrow_ = _deployEscrow(address(token), address(dao), address(clock), 1);

        bytes memory err = _authErr(attacker, address(escrow), escrow.ESCROW_ADMIN_ROLE());
        vm.prank(attacker);
        vm.expectRevert(err);
        escrow.setVoter(address(2));
    }

    function test_RevertIfQueueAlreadySet(address _queue) public {
        vm.expectRevert(AddressAlreadySet.selector);
        escrow.setVoter(_queue);
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

    function testSplitWhitelist() public {
        address addr = address(1);
        vm.expectEmit(true, false, false, true);
        emit SplitWhitelistSet(addr, true);

        assertFalse(escrow.splitWhitelisted(addr));
        escrow.setEnableSplit(addr, true);
        assertTrue(escrow.splitWhitelisted(addr));
        escrow.setEnableSplit(addr, false);
        assertFalse(escrow.splitWhitelisted(addr));

        escrow.enableSplit();
        assertTrue(
            escrow.splitWhitelisted(
                address(uint160(uint256(keccak256("SPLIT_WHITELIST_ANY_ADDRESS"))))
            )
        );

        bytes memory err = _authErr(attacker, address(escrow), escrow.ESCROW_ADMIN_ROLE());

        vm.startPrank(attacker);
        {
            vm.expectRevert(err);
            escrow.setEnableSplit(addr, true);

            vm.expectRevert(err);
            escrow.enableSplit();
        }
        vm.stopPrank();
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
