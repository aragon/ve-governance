pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {QuadraticIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/QuadraticIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {QuadraticCurveBase, MockEscrow} from "./QuadraticCurveBase.t.sol";

contract TestQuadraticIncreasingCurve is QuadraticCurveBase {
    // check that our constants are initialized correctly
    // check the escrow is set
    function testEscrowInitializesCorrectly() public {
        // MockEscrow escrow = new MockEscrow();
        // QuadraticIncreasingEscrow curve_ = new QuadraticIncreasingEscrow();
        // curve_.initialize(address(escrow), address(dao));
        // assertEq(address(curve_.escrow()), address(escrow));
    }
    // validate the bias bounding works
    // warmup: TODO - how do we ensure the warmup doesn't add to an epoch that snaps
    // in the future
    // warmup: variable warmup perid (create a setter)
    // warmup: empty warmup period returns fase
    // supplyAt reverts
    // same block checkpointing overwrite user point history
    // updating checkpoint with a lower balance
    // updating checkpoint with a higher balance
    // updating with the same balance
    // only the escrow can call checkpoint
    // point index with large number of points
    // - if userepoch 0 return 0
    // - if latest user epoch before ts, return the latest user epoch
    // - implicit zero balance
    // understand at what boundary the curve starts to break down by doing a very small and very large
    // deposit
    // test the bound bias caps at the boundary
    // test that the cooldown correcty  calculates
    // test a checkpoint correctly saves the user point
    // test that the cooldown is respected for the NFT balance
    // test the fetched NFT balance from a point in timeFirst
    // TODO: check aero tests for other ideas
}
