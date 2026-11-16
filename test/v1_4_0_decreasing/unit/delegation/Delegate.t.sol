pragma solidity ^0.8.17;

import {Base} from "./Base.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract TestDelegate is Base {
    function setUp() public override {
        super.setUp();
    }

    event DelegateChanged(address indexed from, address indexed to, address indexed delegate);

    modifier AutoDelegationEnabled() {
        dg.setAutoDelegationDisabled(false);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                      IVotes Delegate
    //////////////////////////////////////////////////////////////*/
    function test_shouldRevertIfPaused_IVotesDelegate() public {
        dg.pause();

        vm.expectRevert("Pausable: paused");
        dg.delegate(address(1));
    }

    function test_SkipsExpiredLock_IVotesDelegate() public {
        vm.warp(block.timestamp + maxTime + 1);
        dg.setAutoDelegationDisabled(false);

        uint256 amount = getFlooredAmount(100e18);
        uint256 start = weekStartTs(block.timestamp);
        _mockLocked(multiIds[0], amount, start);
        // This lock is expired
        _mockLocked(multiIds[1], amount, start - maxTime);
        _mockIsLockExpiredAtNextCheckpoint(multiIds[1], true);

        _mockOwnedTokens(sender, multiIds);

        dg.delegate(bob);

        assertTrue(dg.tokenIsDelegated(multiIds[0]));
        assertFalse(dg.tokenIsDelegated(multiIds[1]));
        assertEq(dg.numberOfDelegatedTokens(sender), multiIds.length - 1);

        // Only the live lock adds voting power
        vm.warp(start);
        assertEq(dg.getVotes(bob), amount);
    }

    function test_DelegatesNothingIfAllLocksExpired_IVotesDelegate() public {
        dg.setAutoDelegationDisabled(false);

        _mockIsLockExpiredAtNextCheckpoint(multiIds[0], true);
        _mockIsLockExpiredAtNextCheckpoint(multiIds[1], true);
        _mockOwnedTokens(sender, multiIds);

        dg.delegate(bob);

        assertEq(dg.delegates(sender), bob);
        assertFalse(dg.tokenIsDelegated(multiIds[0]));
        assertFalse(dg.tokenIsDelegated(multiIds[1]));
        assertEq(dg.numberOfDelegatedTokens(sender), 0);
    }

    function test_UndelegatesExpiredLockWithoutRedelegating_IVotesDelegate() public {
        dg.setAutoDelegationDisabled(false);

        uint256 amount = getFlooredAmount(100e18);
        uint256 start = weekStartTs(block.timestamp);
        _mockLocked(multiIds[0], amount, start);
        _mockLocked(multiIds[1], amount, start);
        _mockOwnedTokens(sender, multiIds);

        dg.delegate(alice);
        assertEq(dg.numberOfDelegatedTokens(sender), multiIds.length);

        // The second lock then expires
        _mockIsLockExpiredAtNextCheckpoint(multiIds[1], true);

        dg.delegate(bob);

        assertTrue(dg.tokenIsDelegated(multiIds[0]));
        assertFalse(dg.tokenIsDelegated(multiIds[1]));
        assertEq(dg.numberOfDelegatedTokens(sender), multiIds.length - 1);

        // Alice loses both locks, and Bob only gets the live one
        vm.warp(start);
        assertEq(dg.getVotes(alice), 0);
        assertEq(dg.getVotes(bob), amount);
    }

    function test_Sets_DelegateeForFirstTime() public {
        _mockOwnedTokens(address(this), new uint256[](0));
        vm.expectEmit();
        emit DelegateChanged(sender, address(0), alice);

        dg.delegate(alice);

        assertEq(dg.delegates(sender), alice);
        assertEq(dg.numberOfDelegatedTokens(sender), 0);
    }

    function test_Updates_Delegatee() public {
        _mockOwnedTokens(address(this), new uint256[](0));
        dg.delegate(alice);

        vm.expectEmit();
        emit DelegateChanged(sender, alice, bob);

        dg.delegate(bob);

        assertEq(dg.delegates(sender), bob);
        assertEq(dg.numberOfDelegatedTokens(sender), 0);
    }

    function test_UndelegatesAndDelegatesToNewAddress() public {
        // Mock tokenIds 1|2|3 with their voting power 
        // and locked amounts  and attach to `sender`.
        address sender = address(this);

        uint256[] memory ownedTokens = new uint256[](3);
        ownedTokens[0] = 1;
        ownedTokens[1] = 2;
        ownedTokens[2] = 3;

        uint256 amount1 = getFlooredAmount(101e18);
        uint256 amount2 = getFlooredAmount(102e18);
        uint256 amount3 = getFlooredAmount(103e18);
        _mockOwnedTokens(sender, ownedTokens);
        _mockLocked(ownedTokens[0], amount1, weekStartTs(block.timestamp));
        _mockLocked(ownedTokens[1], amount2, weekStartTs(block.timestamp));
        _mockLocked(ownedTokens[2], amount3, weekStartTs(block.timestamp));
        _mockVotingPower(ownedTokens[0], 1);
        _mockVotingPower(ownedTokens[1], 1);
        _mockVotingPower(ownedTokens[2], 1);

        uint256[] memory delegatedIds = new uint256[](2);
        delegatedIds[0] = 2;
        delegatedIds[1] = 3;

        // only delegate 2 and 3 tokenIds to alice.
        dg.setAutoDelegationDisabled(true);
        dg.delegate(alice);
        dg.delegate(delegatedIds);
        assertEq(dg.numberOfDelegatedTokens(sender), 2);

        // turn on auto delegation, so when delegate is called,
        // it should undelegate 2 and 3 tokenIds from alice and
        // delegate all ownedTokens(1, 2, 3) to Bob.
        dg.setAutoDelegationDisabled(false);
        dg.delegate(bob);

        vm.warp(block.timestamp + 1 weeks);

        assertEq(dg.delegates(sender), bob);
        assertEq(dg.numberOfDelegatedTokens(sender), 3);

        assertEq(dg.getVotes(alice), 0);

        uint256 elapsed = block.timestamp - previousCheckpointTs(block.timestamp);
        uint256 expectedVPBob = bias(amount1, elapsed) +
            bias(amount2, elapsed) +
            bias(amount3, elapsed);

        assertEq(dg.getVotes(bob), expectedVPBob);
    }

    /*//////////////////////////////////////////////////////////////
                    Delegate(uint256[] tokenIds)
    //////////////////////////////////////////////////////////////*/
    function test_shouldRevertIfPaused() public {
        dg.setDelegateAddress(alice);

        dg.pause();
        
        vm.expectRevert("Pausable: paused");
        dg.delegate(getIds(1));
    }

    function testRevert_IfNotAllowed() public {
        dao.revoke({
            _who: address(type(uint160).max),
            _where: address(dg),
            _permissionId: dg.DELEGATION_TOKEN_ROLE()
        });
        bytes memory data = abi.encodeWithSelector(
            DaoUnauthorized.selector,
            address(dao),
            address(dg),
            address(this),
            dg.DELEGATION_TOKEN_ROLE()
        );
        vm.expectRevert(data);
        dg.delegate(new uint256[](0));
    }

    function testRevert_IfNoDelegateeIsSet() public {
        vm.expectRevert(DelegateeNotSet.selector);

        dg.delegate(singleId);
    }

    function testRevert_IfTokenListEmpty() public {
        dg.setDelegateAddress(alice);

        vm.expectRevert(TokenListEmpty.selector);
        dg.delegate(new uint256[](0));
    }

    function testRevert_IfLockExpiredAtLeastForOneToken() public {
        vm.warp(block.timestamp + maxTime + 1);
        dg.setDelegateAddress(alice);

        _mockLocked(multiIds[0], 10, weekStartTs(block.timestamp));
        // This lock is expired
        _mockLocked(multiIds[1], 10, weekStartTs(block.timestamp) - maxTime);
        _mockIsLockExpiredAtNextCheckpoint(multiIds[1], true);

        vm.expectRevert(abi.encodeWithSelector(LockExpired.selector, multiIds[1]));
        dg.delegate(multiIds);
    }

    function testRevert_IfNotOwner() public {
        dg.setDelegateAddress(alice);

        // Mock that someone else (alice) is the owner, not this contract
        _mockOwner(alice);

        vm.expectRevert(NotOwner.selector);
        dg.delegate(singleId);
    }

    function testRevert_IfNotOwnerOfOneTokenButOwnerOfAnother() public {
        dg.setDelegateAddress(alice);

        // sender (address(this)) owns token 1 but not token 2
        // token 2 is owned by alice but approved to address(this)
        _mockOwnerOf(multiIds[0], address(this));
        _mockOwnerOf(multiIds[1], alice);
        _mockGetApproved(multiIds[1], address(this));

        // Verify that token 2 is approved to address(this)
        assertEq(IERC721(address(lockNFT)).getApproved(multiIds[1]), address(this));

        _mockLocked(multiIds[0], 10, weekStartTs(block.timestamp));
        _mockLocked(multiIds[1], 10, weekStartTs(block.timestamp));

        // Should fail because sender doesn't own token 2, even though it's approved
        vm.expectRevert(NotOwner.selector);
        dg.delegate(multiIds);
    }

    function testRevert_IfTokenAlreadyDelegated() public {
        dg.setDelegateAddress(alice);

        _mockLocked(singleId[0], 10, weekStartTs(block.timestamp));
        dg.delegate(singleId);

        vm.expectRevert(abi.encodeWithSelector(TokenAlreadyDelegated.selector, singleId[0]));

        dg.delegate(singleId);
    }

    function test_EmitsTheEvents() public {
        dg.setDelegateAddress(alice);

        _mockLocked(multiIds[0], 10, weekStartTs(block.timestamp));
        _mockLocked(multiIds[1], 10, weekStartTs(block.timestamp));

        vm.expectEmit();
        emit TokensDelegated(sender, alice, multiIds);

        dg.delegate(multiIds);
    }

    function test_CorrectlySetsDelegatedTokenCount() public {
        dg.setDelegateAddress(alice);
        uint256 start = weekStartTs((block.timestamp));

        _mockLocked(multiIds[0], 10, start);
        _mockLocked(multiIds[1], 10, start);
        dg.delegate(multiIds);

        assertEq(dg.numberOfDelegatedTokens(sender), multiIds.length);

        _mockLocked(3, 10, start);
        _mockVotingPower(3, 1);

        dg.delegate(getIds(3));

        assertEq(dg.numberOfDelegatedTokens(sender), multiIds.length + 1);
    }

    function test_SetsDelegatedTokenToTrue() public {
        dg.setDelegateAddress(alice);
        _mockLocked(1, 10, weekStartTs((block.timestamp)));
        dg.delegate(getIds(1));

        assertEq(dg.tokenIsDelegated(1), true);
    }
}
