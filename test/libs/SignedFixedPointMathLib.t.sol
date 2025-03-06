// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import {Test, console2 as console} from "forge-std/Test.sol"; // Assuming you're using Foundry for testing
import "@libs/SignedFixedPointMathLib.sol";

contract SignedFixedPointMathTest is Test {
    using SignedFixedPointMath for int256;

    function testToFP() public {
        int256 eth = 1 ether; // 1 ETH = 1e18
        assertEq(SignedFixedPointMath.toFP(1), 1e18);
        assertEq(SignedFixedPointMath.toFP(eth), eth * 1e18); // 1 ETH scaled up to 1e36

        int256 quarterEth = eth / 4; // 0.25 ETH
        assertEq(SignedFixedPointMath.toFP(quarterEth), (1e18 / 4) * 1e18); // Scaled down to 0.25
    }

    function testFromFP() public {
        int256 scaledEth = 1e18; // 1 in FP format
        assertEq(SignedFixedPointMath.fromFP(scaledEth), 1); // Should return 1

        int256 scaledQuarter = 100e18 / 4; // 0.25 in FP format
        assertEq(SignedFixedPointMath.fromFP(scaledQuarter), 25); // Should return 0.25 ETH
    }

    function testMul() public {
        int256 eth = 100 ether;
        int256 quarterEth = 1 ether / 4;

        int256 result = eth.mul(quarterEth);
        assertEq(SignedFixedPointMath.fromFP(result), 25); // 1 * 0.25 = 0.25 ETH
    }

    function testDiv() public {
        int256 eth = 1 ether;
        int256 quarterEth = eth / 4;

        int256 result = SignedFixedPointMath.div(eth.toFP(), quarterEth.toFP());
        assertEq(SignedFixedPointMath.fromFP(result), 4); // 1 ETH / 0.25 ETH = 4
    }

    function testAdd() public {
        int256 eth = 1 ether;
        int256 halfEth = eth / 2;

        int256 result = SignedFixedPointMath.add(eth.toFP(), halfEth.toFP());
        assertEq(SignedFixedPointMath.fromFP(result), 1.5 ether); // 1 + 0.5 = 1.5 ETH
    }

    function testSub() public {
        int256 eth = 1 ether;
        int256 halfEth = eth / 2;

        int256 result = SignedFixedPointMath.sub(eth.toFP(), halfEth.toFP());
        assertEq(SignedFixedPointMath.fromFP(result), 0.5 ether); // 1 - 0.5 = 0.5 ETH
    }

    function testPow() public {
        int256 base = 2;
        int256 exp = 3;

        int256 result = SignedFixedPointMath.pow(base.toFP(), exp.toFP());
        assertApproxEqAbs(result, (8 ether), 20);
    }

    function testPowZero() public {
        int256 base = 0;
        int256 exp = 3;

        int256 result = SignedFixedPointMath.pow(base.toFP(), exp.toFP());
        assertEq(result, 0);
    }

    function testPowNegativeReverts() public {
        int256 base = -1;
        int256 exp = 3;

        vm.expectRevert(NegativeBase.selector);
        SignedFixedPointMath.pow(base.toFP(), exp.toFP());
    }

    function testComparison() public {
        int256 eth = 1 ether;
        int256 halfEth = eth / 2;

        assertTrue(SignedFixedPointMath.lt(halfEth.toFP(), eth.toFP()));
        assertTrue(SignedFixedPointMath.gt(eth.toFP(), halfEth.toFP()));
    }
}
