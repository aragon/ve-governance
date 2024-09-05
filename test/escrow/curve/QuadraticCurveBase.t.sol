pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

import {QuadraticIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/QuadraticIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";

contract MockEscrow {
    address public token;
    QuadraticIncreasingEscrow public curve;

    function setCurve(QuadraticIncreasingEscrow _curve) external {
        curve = _curve;
    }

    function checkpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) external {
        return curve.checkpoint(_tokenId, _oldLocked, _newLocked);
    }
}

contract QuadraticCurveBase is Test, ILockedBalanceIncreasing {
    QuadraticIncreasingEscrow internal curve;
    MockEscrow internal escrow;

    function setUp() public {
        escrow = new MockEscrow();
        curve = new QuadraticIncreasingEscrow(address(escrow));
        escrow.setCurve(curve);
    }
}
