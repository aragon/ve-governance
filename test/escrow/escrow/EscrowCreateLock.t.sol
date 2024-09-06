pragma solidity ^0.8.17;

import {EscrowBase} from "./EscrowBase.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

import {IEscrowCurveUserStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {VotingEscrow} from "@escrow/VotingEscrowIncreasing.sol";

import {SimpleGaugeVoter, SimpleGaugeVoterSetup} from "src/voting/SimpleGaugeVoterSetup.sol";

contract TestCreateLock is EscrowBase, IEscrowCurveUserStorage {
    function setUp() public override {
        super.setUp();

        // token.mint(address(this), 1_000_000_000 ether);
    }

    function testCannotCreateLockWithZeroValue() public {
        vm.expectRevert(ZeroAmount.selector);
        escrow.createLock(0);
    }

    function testCantMintToZeroAddress() public {
        token.mint(address(this), 1);
        vm.expectRevert("ERC721: mint to the zero address");
        escrow.createLockFor(1, address(0));
    }

    /// @param _value is positive, we check this in a previous test. It needs to fit inside an int256
    /// so we use the maximum value for a uint128
    /// @param _depositor is not the zero address, we check this in a previous test
    /// @param _time is bound to 128 bits to avoid overflow - seems reasonable as is not a user input
    function testFuzz_createLock(uint128 _value, address _depositor, uint128 _time) public {
        vm.assume(_value > 0);
        vm.assume(_depositor != address(0));

        // set zero warmup for this test
        curve.setWarmupPeriod(0);

        vm.warp(_time);
        token.mint(_depositor, _value);

        // start of next week
        uint256 expectedTime = uint(_time) + 1 weeks - (_time % 1 weeks);

        vm.startPrank(_depositor);
        {
            token.approve(address(escrow), _value);
            vm.expectEmit(true, true, true, true);
            emit Deposit(_depositor, 1, expectedTime, _value, _value);
            escrow.createLock(_value);
        }
        vm.stopPrank();

        // get all tokenIds for the user
        uint256[] memory tokenIds = escrow.ownedTokens(_depositor);
        assertEq(tokenIds.length, 1);

        uint256 tokenId = tokenIds[0];
        assertEq(tokenId, 1);

        // Essentially the below are tests within tests

        // check the various getters
        {
            // voting power will be zero due to warmup
            assertEq(escrow.votingPower(tokenId), 0);
            assertEq(escrow.tokenOfOwnerByIndex(_depositor, 0), tokenId);

            // warp to the start date
            vm.warp(expectedTime);

            // voting power will be the same as the deposit
            assertEq(escrow.votingPower(tokenId), _value);
            assertEq(escrow.votingPowerForAccount(_depositor), _value);
        }

        // check the user has the nft:
        {
            assertEq(tokenId, tokenId);
            assertEq(escrow.ownerOf(tokenId), _depositor);
            assertEq(escrow.balanceOf(_depositor), tokenId);
            assertEq(escrow.totalSupply(), tokenId);
        }

        // check the contract has tokens
        {
            assertEq(escrow.totalLocked(), _value);
            assertEq(token.balanceOf(address(escrow)), _value);
        }

        // Check the lock was created:
        {
            LockedBalance memory lock = escrow.locked(tokenId);
            assertEq(lock.amount, _value);
            assertEq(lock.start, expectedTime);
        }
        // Check the checkpoint was created
        {
            uint256 epoch = curve.userPointEpoch(tokenId);
            UserPoint memory checkpoint = curve.userPointHistory(tokenId, epoch);
            assertEq(checkpoint.bias, _value);
            assertEq(checkpoint.ts, expectedTime);
        }
    }

    //   Creating a lock:
    // - Test it mints an NFT with a new tokenId
    // - Test we can fetch the nft for the user
    // - Test the lock corresponds to the correct length
    // - Test that the first checkpoint is written to
    // - Test the value is correct
    // - Thest the total locked in the contract increments correctly
    // - Test if we need to track supply changes or can remove the event
    // CreateLock time logic:
    // - Test that the create lock snaps to the nearest voting period start date
    // Creating a lock for someone:
    // - Test we can make a lock for someone else
    // - Test that someone can't be a smart contract unless whitelisted
    // Creating locks for multiple users:
    // - Test that we can query multiple locks
    // - Test that locks correctly track user balances
}
