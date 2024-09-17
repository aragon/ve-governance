pragma solidity ^0.8.17;

import {EscrowBase} from "./EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

import {IEscrowCurveUserStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {VotingEscrow} from "@escrow/VotingEscrow.sol";
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
}
