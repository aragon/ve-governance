// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Test} from "forge-std/Test.sol";
import {AragonTest} from "../../base/AragonTest.sol";
import {SafeCastUpgradeable as SafeCast} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {
    Clock, 
    IClock, 
    Lock, 
    VotingEscrow, 
    QuadraticIncreasingEscrow, 
    IVotingEscrowIncreasing, 
    IEscrowCurveIncreasing, 
    IVotingEscrowIncreasing, 
    IVotingEscrowCoreErrors, 
    IMerge, 
    ISplit, 
    ILockedBalanceIncreasing, 
    IEscrowCurveGlobalStorage, 
    IEscrowCurveTokenStorage
} from "../../versions.sol";

import {CurveConstantLib} from "@libs/CurveConstantLib.sol";
import {MockERC20} from "@mocks/MockERC20.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";

contract EscrowBase is AragonTest, IEscrowCurveGlobalStorage, IEscrowCurveTokenStorage {
    using ProxyLib for address;
    using SafeCast for uint256;

    uint208 internal TOKEN_5K = 5e21;

    uint256 internal DAY = 86400;

    QuadraticIncreasingEscrow internal curve;
    VotingEscrow internal escrow;
    Clock internal clock;

    uint208 internal Lock_1_Amount = 50e18;
    uint208 internal Lock_2_Amount = 30e18;

    uint256 internal Lock_1_ts;
    uint256 internal Lock_1_start;

    uint256 internal Lock_2_ts;
    uint256 internal Lock_2_start;

    address public sender = address(123);

    uint256 public checkpointInterval;
    uint256 public maxTime;

    function lockedBalance(
        uint208 amount,
        uint48 start
    ) public pure returns (ILockedBalanceIncreasing.LockedBalance memory) {
        return ILockedBalanceIncreasing.LockedBalance(amount, start);
    }

    function getTimes()
        internal
        view
        returns (uint256 weekStartTs, uint256 endTs, uint256 currentTs)
    {
        weekStartTs = (block.timestamp / checkpointInterval) * checkpointInterval;
        endTs = weekStartTs + maxTime;
        currentTs = block.timestamp;
    }

    function slopeFP(uint256 _amount) internal view returns (int256) {
        return int256(_amount * (1e18 / maxTime));
    }

    function biasFP(uint256 _amount, uint256 _duration) internal view returns (int256) {
        return int256(_amount * 1e18 + ((_amount * (1e18 / maxTime)) * _duration));
    }

    function bias(uint256 _amount, uint256 _duration) internal view returns (int256 bias_) {
        return biasFP(_amount, _duration) / 1e18;
    }

    function slopeChanges(uint16 _seasonIndex, uint256 _end) internal view returns(int256 slope) {
        return curve.slopeChanges(_seasonIndex, _end);
    }

    function slopeChanges(uint256 _end) internal view returns(int256 slope) {
        return slopeChanges(0, _end);
    }

    function assertTotalSupply(uint256 _t, int256 _amountFP) internal view {
        assertEq(curve.supplyAt(_t), uint256(_amountFP / 1e18));
    }

    modifier givenExistingLock() {
        vm.warp(block.timestamp + 1 hours);
        uint256 tokenId = escrow.createLock(Lock_1_Amount);

        Lock_1_ts = block.timestamp;
        Lock_1_start = (block.timestamp / checkpointInterval) / checkpointInterval;
        _;
    }

    function setUp() public virtual {
        DAO _dao = DAO(payable(new ERC1967Proxy(address(new DAO()), bytes(""))));
        _dao.initialize({
            _metadata: bytes(""),
            _initialOwner: address(this),
            _trustedForwarder: address(0),
            daoURI_: "ipfs://"
        });

        clock = new Clock();
        checkpointInterval = clock.checkpointInterval();
        maxTime = IClock(clock).epochDuration() * CurveConstantLib.MAX_EPOCHS;

        MockERC20 token = new MockERC20();

        // deploy escrow proxy
        escrow = VotingEscrow(
            address(new VotingEscrow()).deployUUPSProxy(
                abi.encodeCall(
                    VotingEscrow.initialize,
                    (address(token), address(_dao), address(clock), 0)
                )
            )
        );

        // deploy curve proxy
        curve = QuadraticIncreasingEscrow(
            address(new QuadraticIncreasingEscrow()).deployUUPSProxy(
                abi.encodeCall(
                    QuadraticIncreasingEscrow.initialize,
                    (address(escrow), address(_dao), 0, address(clock))
                )
            )
        );

        _dao.grant({
            _who: address(this),
            _where: address(escrow),
            _permissionId: escrow.ESCROW_ADMIN_ROLE()
        });

        token.mint(sender, 10000000e18);

        escrow.setCurve(address(curve));
        escrow.setLockNFT(
            address(address(new Lock())).deployUUPSProxy(
                abi.encodeWithSelector(
                    Lock.initialize.selector,
                    address(escrow),
                    "nameoo",
                    "symbol",
                    address(_dao)
                )
            )
        );

        vm.startPrank(sender);
        token.approve(address(escrow), 10000000e18);
    }

}
