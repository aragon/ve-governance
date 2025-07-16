pragma solidity ^0.8.17;

import {Base} from "./Base.sol";
import {IVotingEscrowCore} from "../../versions.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract TestBalanceOf is Base {
    function setUp() public override {
        super.setUp();
    }

    function test_shouldReturnZeroIfLockNFTIsZero() public {
        vm.mockCall(
            address(escrow),
            abi.encodeWithSelector(IVotingEscrowCore.lockNFT.selector),
            abi.encode(address(0))
        );
        assertEq(dg.balanceOf(address(this)), 0);
    }

    function test_shouldReturnCorrectBalance() public {
        address lockNft = address(123);
        vm.mockCall(
            address(escrow),
            abi.encodeWithSelector(IVotingEscrowCore.lockNFT.selector),
            abi.encode(lockNft)
        );

        vm.mockCall(
            address(lockNft),
            abi.encodeWithSelector(IERC721.balanceOf.selector, address(this)),
            abi.encode(15)
        );

        assertEq(dg.balanceOf(address(this)), 15);
    }
}
