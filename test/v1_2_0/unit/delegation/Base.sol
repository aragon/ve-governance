/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";

// aragon contracts
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {EscrowIVotesAdapter} from "@delegation/EscrowIVotesAdapter.sol";

import {createTestDAO} from "@mocks/MockDAO.sol";
import {Clock, IClock, VotingEscrow} from "../../versions.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {ILockedBalanceIncreasing} from "@escrow/IVotingEscrowIncreasing.sol";
import {
    IEscrowIVotesAdapterStorage,
    IEscrowIVotesAdapterErrorsAndEvents
} from "@delegation/IEscrowIVotesAdapter.sol";
import {CurveConstantLib} from "@libs/CurveConstantLib.sol";
import {FixedPointBase} from "../../base/FixedPointBase.sol";
import {IDelegateUpdateVotingPower} from "@delegation/IEscrowIVotesAdapter.sol";

contract EscrowVotingPowerMock is IDelegateUpdateVotingPower {
    function updateVotingPower(address a, address b) external {

    }
}

contract EscrowIVotesAdapterA is EscrowIVotesAdapter {
    function pointHistory_(
        address _account,
        uint256 _index
    ) public view returns (GlobalPoint memory) {
        return pointHistory[_account][_index];
    }

    function slopeChanges_(address _account, uint256 _end) public view returns (int256) {
        return slopeChanges[_account][_end];
    }
}

contract Base is
    IEscrowIVotesAdapterStorage,
    IEscrowIVotesAdapterErrorsAndEvents,
    FixedPointBase,
    Test
{
    using ProxyLib for address;

    EscrowVotingPowerMock public escrow;
    EscrowIVotesAdapterA public dg;
    DAO dao;
    Clock clock;
    address deployer = address(this);

    address alice = address(123);
    address bob = address(456);
    address sender = address(this);

    uint256[] singleId = [1];
    uint256[] multiIds = [1, 2];

    function setUp() public virtual {
        _deployDAO();
        clock = _deployClock(address(dao));

        escrow = new EscrowVotingPowerMock();
        dg = _deployEscrowIVotesAdapter(address(dao), address(clock), address(escrow));

        _mockApprovedOwner(true);

        uint256 maxTime = IClock(clock).epochDuration() * CurveConstantLib.MAX_EPOCHS;

        super.initialize(maxTime, clock.checkpointInterval());
    }

    function _deployDAO() internal {
        dao = createTestDAO(deployer);
    }

    function _deployClock(address _dao) internal returns (Clock) {
        address impl = address(new Clock());
        bytes memory initCalldata = abi.encodeWithSelector(Clock.initialize.selector, _dao);
        return Clock(impl.deployUUPSProxy(initCalldata));
    }

    function _deployEscrowIVotesAdapter(
        address _dao,
        address _clock,
        address _escrow
    ) public returns (EscrowIVotesAdapterA) {
        EscrowIVotesAdapterA impl = new EscrowIVotesAdapterA();

        bytes memory initCalldata = abi.encodeCall(
            EscrowIVotesAdapter.initialize,
            (_dao, _escrow, _clock)
        );
        return EscrowIVotesAdapterA(address(impl).deployUUPSProxy(initCalldata));
    }

    function getIds(uint256 _tokenId) internal view returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](1);
        ids[0] = _tokenId;
        return ids;
    }

    function getIds(uint256 _tokenId1, uint256 _tokenId2) internal view returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](2);
        ids[0] = _tokenId1;
        ids[1] = _tokenId2;
        return ids;
    }

    function assertGlobalPoint(
        address _account,
        uint256 _expectedLatestIndex,
        int256 _biasFP,
        int256 _slopeFP,
        uint256 _writtenTs
    ) internal view {
        uint256 latestIndex = dg.latestPointIndex(_account);
        assertEq(latestIndex, _expectedLatestIndex);

        GlobalPoint memory p = dg.pointHistory_(_account, latestIndex);
        assertEq(p.writtenTs, _writtenTs);
        assertEq(p.bias, _biasFP);
        assertEq(p.slope, _slopeFP);
    }

    function assertSlopeChange(address _account, uint256 _end, uint256 _amount) internal view {
        assertEq(dg.slopeChanges_(_account, _end), slopeFP(_amount));
    }

    function _mockApprovedOwner(bool _approved) internal {
        vm.mockCall(
            address(escrow),
            abi.encodeWithSelector(VotingEscrow.isApprovedOrOwner.selector),
            abi.encode(_approved)
        );
    }

    function _mockOwnedTokens(address _account, uint256[] memory _ids) internal {
        vm.mockCall(
            address(escrow),
            abi.encodeWithSelector(VotingEscrow.ownedTokens.selector, (_account)),
            abi.encode(_ids)
        );
    }

    function _mockLocked(uint256 _tokenId, uint256 _amount, uint256 _start) internal {
        vm.mockCall(
            address(escrow),
            abi.encodeWithSelector(VotingEscrow.locked.selector, (_tokenId)),
            abi.encode(ILockedBalanceIncreasing.LockedBalance(uint208(_amount), uint48(_start)))
        );
    }
}
