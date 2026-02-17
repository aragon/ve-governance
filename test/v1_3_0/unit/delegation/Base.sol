/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

// aragon contracts
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import {createTestDAO} from "@mocks/MockDAO.sol";
import {
    ILockedBalanceIncreasing,
    Clock,
    IClock,
    VotingEscrow,
    EscrowIVotesAdapter,
    IEscrowIVotesAdapterStorage,
    IEscrowIVotesAdapterErrorsAndEvents,
    SimpleGaugeVoter,
    IVotingEscrowCore
} from "../../versions.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {CurveConstantLib} from "@libs/CurveConstantLib.sol";
import {IDelegateUpdateVotingPower} from "@delegation/IEscrowIVotesAdapter.sol";

import {FixedPointBase} from "../../base/FixedPointBase.sol";

contract EscrowVotingPowerMock is IDelegateUpdateVotingPower {
    function updateVotingPower(address a, address b) external {}
}

contract MockLockNFT {
    // This is a mock - actual ownerOf calls will be mocked via vm.mockCall
}

contract EscrowIVotesAdapterA is EscrowIVotesAdapter {
    constructor(
        int256[3] memory coefficients,
        uint256 maxEpoch
    ) EscrowIVotesAdapter(coefficients, maxEpoch) {}

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
    MockLockNFT public lockNFT;
    SimpleGaugeVoter public voter;
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
        lockNFT = new MockLockNFT();
        dg = _deployEscrowIVotesAdapter(address(dao), address(clock), address(escrow));
        voter = _deployVoter(address(dao), address(clock), address(escrow), address(dg));

        _mockLockNFT();
        _mockOwner(address(this));
        // _mockPermissions();

        uint256 maxTime = IClock(clock).epochDuration() * CurveConstantLib.MAX_EPOCHS;

        FixedPointBase.initialize(maxTime, clock.checkpointInterval());

        // grant this contract admin role
        dao.grant({
            _who: address(this),
            _where: address(dg),
            _permissionId: dg.DELEGATION_ADMIN_ROLE()
        });

        dao.grant({
            _who: address(type(uint160).max),
            _where: address(dg),
            _permissionId: dg.DELEGATION_TOKEN_ROLE()
        });

        // almost all tests need delegation to be disabled by default
        // to test thoroughly the behaviour of the functions.
        // So we set it to true.
        dg.setAutoDelegationDisabled(true);

        // delegate function calls `VotingPower` on escrow
        // and reverts if the returned result is 0.
        // The below tokenIds are the ones we test the function with,
        // So we mock them to return non-zero value, so tests don't fail.
        _mockVotingPower(singleId[0], 1);
        _mockVotingPower(multiIds[0], 1);
        _mockVotingPower(multiIds[1], 1);
    }

    function _deployDAO() internal {
        dao = createTestDAO(deployer);
    }

    function _deployClock(address _dao) internal returns (Clock) {
        address impl = address(new Clock());
        bytes memory initCalldata = abi.encodeWithSelector(Clock.initialize.selector, _dao);
        return Clock(impl.deployUUPSProxy(initCalldata));
    }

    function _deployVoter(
        address _dao,
        address _clock,
        address _escrow,
        address _ivotesAdapter
    ) internal returns (SimpleGaugeVoter) {
        address impl = address(new SimpleGaugeVoter());
        bytes memory initCalldata = abi.encodeWithSelector(
            SimpleGaugeVoter.initialize.selector,
            _dao,
            _escrow,
            false,
            _clock,
            _ivotesAdapter,
            true
        );
        return SimpleGaugeVoter(impl.deployUUPSProxy(initCalldata));
    }

    function _deployEscrowIVotesAdapter(
        address _dao,
        address _clock,
        address _escrow
    ) public returns (EscrowIVotesAdapterA) {
        (int256[3] memory coefficients, uint256 maxEpochs) = CurveConstantLib.getCoefficients();
        EscrowIVotesAdapterA impl = new EscrowIVotesAdapterA(coefficients, maxEpochs);
        bool startPaused = false;

        bytes memory initCalldata = abi.encodeCall(
            EscrowIVotesAdapter.initialize,
            (_dao, _escrow, _clock, startPaused)
        );
        return EscrowIVotesAdapterA(address(impl).deployUUPSProxy(initCalldata));
    }

    function getIds(uint256 _tokenId) internal pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](1);
        ids[0] = _tokenId;
        return ids;
    }

    function getIds(uint256 _tokenId1, uint256 _tokenId2) internal pure returns (uint256[] memory) {
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

    function _mockLockNFT() internal {
        vm.mockCall(
            address(escrow),
            abi.encodeWithSelector(IVotingEscrowCore.lockNFT.selector),
            abi.encode(address(lockNFT))
        );
    }

    function _mockOwner(address _owner) internal {
        vm.mockCall(
            address(lockNFT),
            abi.encodeWithSelector(bytes4(keccak256("ownerOf(uint256)"))),
            abi.encode(_owner)
        );
    }

    function _mockOwnerOf(uint256 _tokenId, address _owner) internal {
        vm.mockCall(
            address(lockNFT),
            abi.encodeWithSelector(bytes4(keccak256("ownerOf(uint256)")), _tokenId),
            abi.encode(_owner)
        );
    }

    function _mockGetApproved(uint256 _tokenId, address _approved) internal {
        vm.mockCall(
            address(lockNFT),
            abi.encodeWithSelector(bytes4(keccak256("getApproved(uint256)")), _tokenId),
            abi.encode(_approved)
        );
    }

    function _mockPermissions() internal {
        vm.mockCall(
            address(dao),
            abi.encodeWithSelector(DAO.hasPermission.selector),
            abi.encode(true)
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

    function _mockVotingPower(uint256 _tokenId, uint256 _vp) internal {
        vm.mockCall(
            address(escrow),
            abi.encodeWithSelector(VotingEscrow.votingPower.selector, (_tokenId)),
            abi.encode(_vp)
        );
    }

    function _authErr(
        address _caller,
        address _contract,
        bytes32 _perm
    ) internal view returns (bytes memory) {
        return
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                _contract,
                _caller,
                _perm
            );
    }
}
