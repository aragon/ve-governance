// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "@solmate/utils/SignedWadMath.sol";

// shared interface for fixed point math implementations.
library SignedFixedPointMath {
    // solmate does this unchecked to save gas, easier to do this here
    // be extremely careful that you are doing all operations in FP
    // unlike PRB Math (unsupported in solidity 0.8.17)
    // solmate will not warn you that you are operating in scaled down mode
    function toFP(int256 x) internal pure returns (int256) {
        return x * 1e18;
    }

    function fromFP(int256 x) internal pure returns (int256) {
        return x / 1e18;
    }

    function mul(int256 x, int256 y) internal pure returns (int256) {
        return wadMul(x, y);
    }

    function div(int256 x, int256 y) internal pure returns (int256) {
        return wadDiv(x, y);
    }

    function add(int256 x, int256 y) internal pure returns (int256) {
        return x + y;
    }

    function sub(int256 x, int256 y) internal pure returns (int256) {
        return x - y;
    }

    function pow(int256 x, int256 y) internal pure returns (int256) {
        require(x >= 0, "FixedPointMath: x < 0");
        if (x == 0) return 0;
        return wadPow(x, y);
    }

    function lt(int256 x, int256 y) internal pure returns (bool) {
        return x < y;
    }

    function gt(int256 x, int256 y) internal pure returns (bool) {
        return x > y;
    }
}
