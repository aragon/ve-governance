pragma solidity ^0.8.17;

import {EscrowBase} from "./EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

import {
    Clock, 
    IClock, 
    Lock, 
    VotingEscrow, 
    LinearIncreasingEscrow, 
    IVotingEscrowIncreasing, 
    IEscrowCurveIncreasing, 
    IVotingEscrowIncreasing, 
    IVotingEscrowCoreErrors, 
    IMerge, 
    ISplit, 
    ILockedBalanceIncreasing, 
    IEscrowCurveGlobalStorage, 
    IEscrowCurveTokenStorage
} from "../../../versions.sol";

contract TestEscrowMerge is EscrowBase, IEscrowCurveTokenStorage {
    function setUp() public override {
        super.setUp();
    }

   function test_shouldRevert_IfNotMatureAndDifferentStart() public {
        uint256 from = escrow.createLock(Lock_1_Amount);

        // Warp so start dates end up different..
        vm.warp(block.timestamp + checkpointInterval);
        uint256 to = escrow.createLock(Lock_2_Amount);

        //reverts as start dates are different and tokens are not mature.
        vm.expectRevert(
            abi.encodeWithSelector(IMerge.CannotMerge.selector, from, to)
        );
        escrow.merge(from, to);
    }

    function test_shouldRevert_IfSenderIsNotApprovedOrOwner() public {
        uint256 from = escrow.createLock(Lock_1_Amount);
        uint256 to = escrow.createLock(Lock_2_Amount);

        vm.startPrank(address(999));
        vm.expectRevert(IVotingEscrowCoreErrors.NotApprovedOrOwner.selector);
        escrow.merge(from, to);
    }

    function test_shouldRevert_BothNFTsAreSame() public {
        uint256 from = escrow.createLock(Lock_1_Amount);

        vm.expectRevert(IMerge.SameNFT.selector);
        escrow.merge(from, from);
    }
}