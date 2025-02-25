pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {QuadraticIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/QuadraticIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {VotingEscrow} from "src/escrow/increasing/VotingEscrowIncreasing.sol";
import {Lock} from "src/escrow/increasing/Lock.sol";

import {Test} from "forge-std/Test.sol";
import {SafeCastUpgradeable as SafeCast} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {CurveConstantLib} from "@libs/CurveConstantLib.sol";
import {Clock} from "../src/clock/Clock.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TestEscrow is Test {
    using ProxyLib for address;
    using SafeCast for uint256;

    uint208 internal TOKEN_5K = 5e21;

    uint256 internal WEEK = 604800;
    uint256 internal DAY = 86400;

    QuadraticIncreasingEscrow internal curve;
    VotingEscrow internal escrow;
    Clock internal clock;

    uint208 internal Lock_1_Amount = 50e18;
    uint208 internal Lock_2_Amount = 30e18;

    uint256 internal Slope_1 = Lock_1_Amount / CurveConstantLib.MAX_TIME;
    uint256 internal Slope_2 = Lock_2_Amount / CurveConstantLib.MAX_TIME;

    uint256 internal Lock_1_ts;
    uint256 internal Lock_1_start;

    uint256 internal Lock_2_ts;
    uint256 internal Lock_2_start;

    address public sender = address(123);

}