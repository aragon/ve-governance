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

contract TestEscrowTransfers is EscrowBase, IEscrowCurveUserStorage {
    uint deposit = 100e18;
    uint tokenId;

    function setUp() public override {
        super.setUp();

        // create an NFT
        token.mint(address(this), deposit);
        token.approve(address(escrow), deposit);
        tokenId = escrow.createLock(deposit);
    }

    function testCannotTransferByDefault() public {
        vm.expectRevert(NotWhitelisted.selector);
        escrow.transferFrom(address(this), address(123), tokenId);

        vm.expectRevert(NotWhitelisted.selector);
        escrow.safeTransferFrom(address(this), address(123), tokenId);
    }

    function testCanTransferIfWhitelisted() public {
        escrow.setWhitelisted(address(123), true);

        escrow.transferFrom(address(this), address(123), tokenId);

        assertEq(token.balanceOf(address(123)), deposit);
        assertEq(token.balanceOf(address(this)), 0);

        // todo - reset the voting power
    }
}
