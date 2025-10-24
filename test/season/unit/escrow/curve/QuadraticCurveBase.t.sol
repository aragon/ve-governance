pragma solidity ^0.8.17;

import {TestHelpers} from "@helpers/TestHelpers.sol";
import {console2 as console} from "forge-std/console2.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {
    Clock,
    QuadraticIncreasingEscrow,
    ILockedBalanceIncreasing,
    IVotingEscrowIncreasing as IVotingEscrow,
    IEscrowCurveIncreasing as IEscrowCurve
} from "../../../versions.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {FixedPointBase} from "../../../base/FixedPointBase.sol";
import {CurveConstantLib} from "@libs/CurveConstantLib.sol";

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

contract QuadraticCurveBase is TestHelpers, ILockedBalanceIncreasing, FixedPointBase {
    using ProxyLib for address;
    QuadraticIncreasingEscrow internal curve;
    MockEscrow internal escrow;
    Clock internal clock;

    function setUp() public virtual override {
        super.setUp();
        escrow = new MockEscrow();

        address clockImpl = address(new Clock());
        bytes memory initClockCalldata = abi.encodeWithSelector(Clock.initialize.selector, dao);
        clock = Clock(clockImpl.deployUUPSProxy(initClockCalldata));

        address impl = address(new QuadraticIncreasingEscrow());

        bytes memory initCalldata = abi.encodeCall(
            QuadraticIncreasingEscrow.initialize,
            (address(escrow), address(dao), 3 days, address(clock))
        );

        curve = QuadraticIncreasingEscrow(impl.deployUUPSProxy(initCalldata));

        // grant this address admin privileges
        DAO(payable(address(dao))).grant({
            _who: address(this),
            _where: address(curve),
            _permissionId: curve.CURVE_ADMIN_ROLE()
        });

        DAO(payable(address(dao))).grant({
            _who: address(this),
            _where: address(clock),
            _permissionId: clock.CLOCK_ADMIN_ROLE()
        });

        escrow.setCurve(curve);

        FixedPointBase.initialize(
            clock.epochDuration() * CurveConstantLib.MAX_EPOCHS,
            clock.checkpointInterval()
        );
    }
}
