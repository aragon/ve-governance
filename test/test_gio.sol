pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {QuadraticIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/QuadraticIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {Test} from "forge-std/Test.sol";
import {SafeCastUpgradeable as SafeCast} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {CurveConstantLib} from "@libs/CurveConstantLib.sol";

contract TestQuadraticIncreasingCurve is Test {
    using SafeCast for uint256;

    uint208 internal TOKEN_10K = 1e22;
    uint256 internal WEEK = 604800;
    uint256 internal DAY = 86400;

    function test_gio() public {
        
        QuadraticIncreasingEscrow b = new QuadraticIncreasingEscrow();

        uint256 startTime = block.timestamp;
        uint256 endTime = (startTime / CurveConstantLib.WEEK) * CurveConstantLib.WEEK + CurveConstantLib.MAX_TIME;

        b.checkpoint(
            1, 
            ILockedBalanceIncreasing.LockedBalance(0, 0, 0), 
            ILockedBalanceIncreasing.LockedBalance(TOKEN_10K, startTime.toUint48(), endTime.toUint48())
        );

        // b.checkpoint(
        //     1, 
        //     ILockedBalanceIncreasing.LockedBalance(0, 0, 0), 
        //     ILockedBalanceIncreasing.LockedBalance(TOKEN_10K, startTime.toUint48(), endTime.toUint48())
        // );

        console.log("supply per days");
        for(uint256 i = 0; i < 6; i++) {
            console.log("supply after %i day: ", i, b.supplyAt(block.timestamp + i*DAY) / 1e18);
        }

        console.log("=============");
        
        console.log("supply per weeks");
        for(uint256 i = 0; i < 6; i++) {
            console.log("supply after %i week: ", i, b.supplyAt(block.timestamp + i*WEEK) / 1e18);
        }

        console.log("supply after MAX_TIME", b.supplyAt(block.timestamp + CurveConstantLib.MAX_TIME + CurveConstantLib.MAX_TIME) / 1e18);


        // console.log("supply after one day: ", b.supplyAt(block.timestamp + 3*700000) / 1e18);
        // console.log("supply after 2 days: ", b.supplyAt(block.timestamp + 3*700000) / 1e18);
        // console.log("supply after 3 days: ", b.supplyAt(block.timestamp + 3*700000) / 1e18);
    }

}
