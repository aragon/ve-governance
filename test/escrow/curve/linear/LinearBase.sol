pragma solidity ^0.8.17;

import {TestHelpers} from "@helpers/TestHelpers.sol";
import {console2 as console} from "forge-std/console2.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {LinearIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/LinearIncreasingEscrow.sol";
import {Clock} from "@clock/Clock.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

contract MockEscrow {
    address public token;
    LinearIncreasingEscrow public curve;

    function setCurve(LinearIncreasingEscrow _curve) external {
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

contract LinearCurveBase is TestHelpers, ILockedBalanceIncreasing {
    using ProxyLib for address;
    LinearIncreasingEscrow internal curve;
    MockEscrow internal escrow;

    function setUp() public virtual override {
        super.setUp();
        escrow = new MockEscrow();

        address impl = address(new LinearIncreasingEscrow());

        bytes memory initCalldata = abi.encodeCall(
            LinearIncreasingEscrow.initialize,
            (address(escrow), address(dao), 3 days, address(clock))
        );

        curve = LinearIncreasingEscrow(impl.deployUUPSProxy(initCalldata));

        // grant this address admin privileges
        DAO(payable(address(dao))).grant({
            _who: address(this),
            _where: address(curve),
            _permissionId: curve.CURVE_ADMIN_ROLE()
        });

        escrow.setCurve(curve);
    }
}
