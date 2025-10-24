pragma solidity ^0.8.17;

import {Base} from "./Base.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

contract TestUndelegate is Base {
    function setUp() public override {
        super.setUp();
    }

    modifier givenDelegatedTokens() {
        dg.setDelegateAddress(alice);

        _mockLocked(multiIds[0], 10, weekStartTs((block.timestamp)));
        _mockLocked(multiIds[1], 25, weekStartTs((block.timestamp)));

        dg.delegate(multiIds);
        _;
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
        dg.undelegate(new uint256[](0));
    }

    function test_shouldRevertIfPaused() public {
        dg.setDelegateAddress(alice);

        dg.pause();

        vm.expectRevert("Pausable: paused");
        dg.undelegate(getIds(1));
    }

    function testRevert_IfNotApprovedOrOwner() public givenDelegatedTokens {
        _mockApprovedOwner(false);

        vm.expectRevert(NotApprovedOrOwner.selector);
        dg.undelegate(multiIds);
    }

    function testRevert_IfNoDelegateeSet() public {
        vm.expectRevert(DelegateeNotSet.selector);

        dg.undelegate(singleId);
    }

    function testRevert_IfTokenListEmpty() public {
        dg.setDelegateAddress(alice);

        vm.expectRevert(TokenListEmpty.selector);
        dg.undelegate(new uint256[](0));
    }

    function testRevert_IfTokenNotDelegated() public givenDelegatedTokens {
        uint256 tokenId = 5;
        _mockLocked(tokenId, 10, weekStartTs(block.timestamp));

        vm.expectRevert(abi.encodeWithSelector(TokenNotDelegated.selector, tokenId));
        dg.undelegate(getIds(tokenId));
    }

    function test_EmitsTheEvents() public givenDelegatedTokens {
        vm.expectEmit();
        emit TokensUndelegated(sender, alice, multiIds);

        dg.undelegate(multiIds);
    }

    function test_CorrectlyDecreasesDelegatedTokenCount() public givenDelegatedTokens {
        uint256 tokenCount = dg.numberOfDelegatedTokens(sender);

        dg.undelegate(getIds(1));

        assertEq(dg.numberOfDelegatedTokens(sender), tokenCount - 1);
    }

    function test_SetsDelegatedTokenToFalse() public givenDelegatedTokens {
        dg.undelegate(getIds(1));

        assertEq(dg.tokenIsDelegated(1), false);
    }
}
