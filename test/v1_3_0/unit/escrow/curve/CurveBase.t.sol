pragma solidity ^0.8.17;

import {TestHelpers} from "@helpers/TestHelpers.sol";

import {DAO} from "@mocks/MockDAO.sol";
import {
    Clock,
    Curve,
    ILockedBalanceIncreasing,
    IVotingEscrowIncreasing as IVotingEscrow,
    IEscrowCurveIncreasing as IEscrowCurve
} from "../../../versions.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {FixedPointBase} from "../../../base/FixedPointBase.sol";
import {CurveConstantLib} from "@libs/CurveConstantLib.sol";

contract MockEscrow {
    address public token;
    Curve public curve;
    mapping(uint => IVotingEscrow.LockedBalance) locked_;

    function setCurve(Curve _curve) external {
        curve = _curve;
    }

    function setLocked(uint256 _tokenId, IVotingEscrow.LockedBalance memory _locked) external {
        locked_[_tokenId] = _locked;
    }

    function checkpoint(
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _oldLocked,
        IVotingEscrow.LockedBalance memory _newLocked
    ) external {
        locked_[_tokenId] = _newLocked;
        return curve.checkpoint(_tokenId, _oldLocked, _newLocked);
    }

    function locked(uint256 _tokenId) external view returns (IVotingEscrow.LockedBalance memory) {
        return locked_[_tokenId];
    }
}

contract CurveBase is TestHelpers, FixedPointBase, ILockedBalanceIncreasing {
    using ProxyLib for address;
    Curve internal curve;
    MockEscrow internal escrow;
    Clock internal clock;

    function setUp() public virtual override {
        super.setUp();
        escrow = new MockEscrow();

        address clockImpl = address(new Clock());
        bytes memory initClockCalldata = abi.encodeWithSelector(Clock.initialize.selector, dao);
        clock = Clock(clockImpl.deployUUPSProxy(initClockCalldata));

        (int256[3] memory coefficients, uint256 maxEpoch) = CurveConstantLib.getCoefficients();
        address impl = address(new Curve(coefficients, maxEpoch));

        bytes memory initCalldata = abi.encodeCall(
            Curve.initialize,
            (address(escrow), address(dao), address(clock))
        );

        curve = Curve(impl.deployUUPSProxy(initCalldata));

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

        FixedPointBase.initialize(curve.maxTime(), clock.checkpointInterval(), coefficients[1]);
    }
}
