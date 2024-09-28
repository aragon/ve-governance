pragma solidity ^0.8.17;

import {EscrowBase} from "./EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

import {IEscrowCurveUserStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {VotingEscrow} from "@escrow/VotingEscrowIncreasing.sol";
import {Lock} from "@escrow/Lock.sol";

import {SimpleGaugeVoter, SimpleGaugeVoterSetup} from "src/voting/SimpleGaugeVoterSetup.sol";
import {IGaugeVote} from "src/voting/ISimpleGaugeVoter.sol";

contract TestLockMintBurn is EscrowBase, IEscrowCurveUserStorage, IGaugeVote {
    function testDeploy(
        string memory _name,
        string memory _symbol,
        address _dao,
        address _escrow
    ) public {
        vm.expectEmit(true, false, false, true);
        emit WhitelistSet(address(_escrow), true);
        Lock _nftLock = _deployLock(_escrow, _name, _symbol, _dao);

        assertEq(_nftLock.name(), _name);
        assertEq(_nftLock.symbol(), _symbol);
        assertEq(_nftLock.escrow(), _escrow);
        assertEq(address(_nftLock.dao()), _dao);
    }

    function testFuzz_OnlyEscrowCanMint(address _notEscrow) public {
        vm.assume(_notEscrow != address(escrow));

        vm.expectRevert(OnlyEscrow.selector);

        vm.prank(_notEscrow);
        nftLock.mint(address(123), 1);

        assertEq(nftLock.balanceOf(address(123)), 0);
        assertEq(nftLock.totalSupply(), 0);

        vm.prank(address(escrow));
        nftLock.mint(address(123), 1);

        assertEq(nftLock.balanceOf(address(123)), 1);
        assertEq(nftLock.totalSupply(), 1);
    }

    function testFuzz_OnlyEscrowCanBurn(address _notEscrow) public {
        vm.assume(_notEscrow != address(escrow));

        vm.prank(address(escrow));
        nftLock.mint(address(123), 1);

        vm.expectRevert(OnlyEscrow.selector);

        vm.prank(_notEscrow);
        nftLock.burn(1);

        assertEq(nftLock.balanceOf(address(123)), 1);
        assertEq(nftLock.totalSupply(), 1);

        vm.prank(address(escrow));
        nftLock.burn(1);

        assertEq(nftLock.balanceOf(address(123)), 0);
        assertEq(nftLock.totalSupply(), 0);
    }

    // HAL-14 receiver must implement ERC721Receiver
    function testCannotMintToNonReceiver() public {
        vm.prank(address(escrow));
        vm.expectRevert("ERC721: transfer to non ERC721Receiver implementer");
        nftLock.mint(address(this), 1);
    }

    // HAL-14 test reentrancy with safe mint
    function testReentrantCantCallMint() public {
        NFTReentrant reentrant = new NFTReentrant();

        Lock newLock = _deployLock(address(reentrant), "name", "symbol", address(dao));

        vm.prank(address(reentrant));
        vm.expectRevert("revert");
        newLock.mint(address(reentrant), 1);
    }
}

contract NFTReentrant {
    function onERC721Received(address, address, uint256, bytes memory) public returns (bytes4) {
        (bool success, ) = msg.sender.call(
            abi.encodeWithSignature("mint(address,uint256)", address(this), 1)
        );
        if (!success) {
            revert("revert");
        }
        return this.onERC721Received.selector;
    }
}
