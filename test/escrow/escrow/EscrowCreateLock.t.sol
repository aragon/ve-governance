pragma solidity ^0.8.17;

import {EscrowBase} from "./EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {EpochDurationLib} from "@libs/EpochDurationLib.sol";

import {IEscrowCurveUserStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {VotingEscrow} from "@escrow/VotingEscrowIncreasing.sol";

import {SimpleGaugeVoter, SimpleGaugeVoterSetup} from "src/voting/SimpleGaugeVoterSetup.sol";

contract TestCreateLock is EscrowBase, IEscrowCurveUserStorage {
    function setUp() public override {
        super.setUp();

        // token.mint(address(this), 1_000_000_000 ether);
    }

    function _expTime(uint256 _time) internal pure returns (uint256) {
        if (_time % 1 weeks == 0) return _time;
        else return uint(_time) + 1 weeks - (_time % 1 weeks);
    }

    function testCannotCreateLockWithZeroValue() public {
        vm.expectRevert(ZeroAmount.selector);
        escrow.createLock(0);
    }

    function testCantMintToZeroAddress() public {
        token.mint(address(this), 1);
        token.approve(address(escrow), 1);

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
        uint256 expectedTime = _expTime(_time);

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
        // TODO extract these to separate functions with a common setup.
        // not needed right now.

        // check the various getters
        {
            // warp to the start date
            vm.warp(expectedTime);

            // voting power will be the same as the deposit
            // as we have no cooldown
            assertEq(escrow.votingPower(tokenId), _value, "value incorrect for the tokenid");
            assertEq(
                escrow.votingPowerForAccount(_depositor),
                _value,
                "value incorrect for account"
            );
        }

        // check the user has the nft:
        {
            assertEq(tokenId, tokenId, "wrong token id");
            assertEq(escrow.ownerOf(tokenId), _depositor);
            assertEq(escrow.balanceOf(_depositor), tokenId);
            assertEq(escrow.totalSupply(), tokenId);
        }

        // check the contract has tokens
        {
            assertEq(escrow.totalLocked(), _value, "!totalLocked");
            assertEq(token.balanceOf(address(escrow)), _value, "balance of NFT incorrect");
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

    // we don't fuzz or test aggregates here, that's covered by the above
    // we just run for 2 known users
    struct User {
        uint value;
        address addr;
    }

    function testCreateMultipleLocks() public {
        User[] memory users = new User[](2);
        User memory matt = User(1_000_500 ether, address(0x1));
        User memory shane = User(2_500_900 ether, address(0x2));
        users[0] = matt;
        users[1] = shane;

        uint total = matt.value + shane.value;

        // mint the dawgs some tokens
        token.mint(matt.addr, matt.value);
        token.mint(shane.addr, shane.value);

        uint expTime = _expTime(block.timestamp);

        // create the locks
        {
            vm.startPrank(matt.addr);
            {
                token.approve(address(escrow), matt.value);
                vm.expectEmit(true, true, true, true);
                emit Deposit(matt.addr, 1, expTime, matt.value, matt.value);
                escrow.createLock(matt.value);
            }
            vm.stopPrank();

            vm.startPrank(shane.addr);
            {
                token.approve(address(escrow), shane.value);
                vm.expectEmit(true, true, true, true);
                emit Deposit(shane.addr, 2, expTime, shane.value, total);
                escrow.createLock(shane.value);
            }
            vm.stopPrank();
        }

        for (uint i = 0; i < users.length; ++i) {
            User memory user = users[i];
            uint expectedTokenId = i + 1;

            uint256[] memory tokenIds = escrow.ownedTokens(user.addr);
            assertEq(tokenIds.length, 1, "user should only have 1 token");
            uint256 tokenId = tokenIds[0];

            // check the user has the nft:
            {
                assertEq(tokenId, expectedTokenId, "token id unexpected");
                assertEq(escrow.ownerOf(tokenId), user.addr, "owner should be the user");
                assertEq(escrow.balanceOf(user.addr), 1, "user should only have 1 token");
            }

            // check the user has the right lock
            {
                LockedBalance memory lock = escrow.locked(tokenId);
                assertEq(lock.amount, user.value);
                assertEq(lock.start, expTime);
            }
        }

        // check the aggregate values
        {
            assertEq(escrow.totalLocked(), total);
            assertEq(token.balanceOf(address(escrow)), total);
            assertEq(escrow.totalSupply(), 2);
        }
    }

    function testTimeLogicSnapsToNextDepositDate() public {
        // define 3 users:

        // shane deposits just before the next deposit date
        address shane = address(0x1);

        // matt deposits ON the next deposit date
        address matt = address(0x2);

        // phil deposits just after the next deposit date
        address phil = address(0x3);

        // mint tokens to each
        token.mint(shane, 1 ether);
        token.mint(matt, 1 ether);
        token.mint(phil, 1 ether);

        // warp to genesis: this makes it easy to calculate deposit dates
        vm.warp(0);

        // now the next deposit is 1 week from now
        uint expectedNextDeposit = EpochDurationLib.DEPOSIT_INTERVAL;

        // shane deposits just before the next deposit date
        vm.warp(expectedNextDeposit - 1);
        vm.startPrank(shane);
        {
            token.approve(address(escrow), 1 ether);
            escrow.createLock(1 ether);
        }
        vm.stopPrank();

        // matt deposits ON the next deposit date
        vm.warp(expectedNextDeposit);
        vm.startPrank(matt);
        {
            token.approve(address(escrow), 1 ether);
            escrow.createLock(1 ether);
        }
        vm.stopPrank();

        // phil deposits just after the next deposit date
        vm.warp(expectedNextDeposit + 1);
        vm.startPrank(phil);
        {
            token.approve(address(escrow), 1 ether);
            escrow.createLock(1 ether);
        }
        vm.stopPrank();

        // our expected behaviour:
        // shane's lock should snap to the nearest deposit date (+1 second)
        assertEq(
            escrow.locked(1).start,
            expectedNextDeposit,
            "shane's lock should snap to the upcoming deposit date"
        );
        // matt  is an edge case, they should also snap to the nearest deposit date (+0 seconds)
        assertEq(
            escrow.locked(2).start,
            expectedNextDeposit,
            "matt's lock should snap to the upcoming deposit date"
        );
        // phil should snap to the next deposit date (+1 week)
        assertEq(
            escrow.locked(3).start,
            expectedNextDeposit + EpochDurationLib.DEPOSIT_INTERVAL,
            "phil's lock should snap to the next deposit date"
        );
    }

    function testFuzz_createLockFor(address _who, uint128 _value) public {
        vm.assume(_who != address(0));
        vm.assume(_value > 0);
        vm.warp(1);
        escrow.setWhitelisted(_who, true);

        token.mint(address(this), _value);
        token.approve(address(escrow), _value);

        vm.expectEmit(true, true, true, true);
        emit Deposit(_who, 1, 1 weeks, _value, _value);
        escrow.createLockFor(_value, _who);
    }
    //   Creating a lock:
    // Creating a lock for someone:
    // - Test we can make a lock for someone else
}

contract Mock {}