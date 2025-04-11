/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";

// aragon contracts
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
import {MockDAOFactory} from "@mocks/osx/MockDAOFactory.sol";
import {MockERC20} from "@mocks/MockERC20.sol";
import {createTestDAO} from "@mocks/MockDAO.sol";

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "@helpers/OSxHelpers.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";

import {
    Lock,
    Clock,
    VotingEscrow,
    LinearIncreasingEscrow,
    ExitQueue,
    SimpleGaugeVoter,
    SimpleGaugeVoterSetup,
    IVotingEscrowEventsStorageErrorsEvents,
    IWhitelistErrors,
    IWhitelistEvents,
    ISplitEventsAndErrors,
    IEscrowCurveTokenStorage,
    IEscrowCurveGlobalStorage,
    EscrowIVotesAdapter
} from "../versions.sol";

import {CurveConstantLib} from "@libs/CurveConstantLib.sol";
import {FixedPointBase} from "./FixedPointBase.sol";

contract EscrowBase is
    Test,
    FixedPointBase,
    IVotingEscrowEventsStorageErrorsEvents,
    IEscrowCurveTokenStorage,
    IEscrowCurveGlobalStorage,
    IWhitelistErrors,
    IWhitelistEvents,
    ISplitEventsAndErrors
{
    using ProxyLib for address;
    string name = "Voting Escrow";
    string symbol = "VE";

    MockPluginSetupProcessor psp;
    MockDAOFactory daoFactory;
    MockERC20 token;

    Lock nftLock;
    VotingEscrow escrow;
    LinearIncreasingEscrow curve;
    SimpleGaugeVoter voter;
    ExitQueue queue;
    Clock clock;
    EscrowIVotesAdapter ivotesAdapter;

    DAO dao;
    Multisig multisig;
    MultisigSetup multisigSetup;
    address deployer = address(this);

    uint208 internal TOKEN_5K = 5e21;

    uint256 internal DAY = 86400;

    uint208 internal Lock_1_Amount = 50e18;
    uint208 internal Lock_2_Amount = 30e18;

    uint256 internal Lock_1_ts;
    uint256 internal Lock_1_start;

    uint256 internal Lock_2_ts;
    uint256 internal Lock_2_start;

    uint48 public warmupPeriod;

    error OnlyEscrow();

    function setUp() public virtual {
        // _deployOSX();
        _deployDAO();

        // deploy our contracts
        token = new MockERC20();
        clock = _deployClock(address(dao));

        warmupPeriod = 3 days;

        escrow = _deployEscrow(address(token), address(dao), address(clock), 1);
        curve = _deployCurve(address(escrow), address(dao), warmupPeriod, address(clock));
        nftLock = _deployLock(address(escrow), name, symbol, address(dao));
        ivotesAdapter = _deployEscrowIVotesAdapter(address(dao), address(escrow), address(clock));

        super.initialize(curve.maxTime(), clock.checkpointInterval());

        // to be added as proxies
        voter = _deployVoter(
            address(dao),
            address(escrow),
            false,
            address(clock),
            address(ivotesAdapter)
        );
        queue = _deployExitQueue(address(escrow), 3 days, address(dao), 0, address(clock), 1);

        // grant this contract admin privileges
        dao.grant({
            _who: address(this),
            _where: address(escrow),
            _permissionId: escrow.ESCROW_ADMIN_ROLE()
        });

        // grant this contract pause role
        dao.grant({
            _who: address(this),
            _where: address(escrow),
            _permissionId: escrow.PAUSER_ROLE()
        });

        // give this contract admin privileges on the peripherals
        dao.grant({
            _who: address(this),
            _where: address(voter),
            _permissionId: voter.GAUGE_ADMIN_ROLE()
        });

        dao.grant({
            _who: address(this),
            _where: address(queue),
            _permissionId: queue.QUEUE_ADMIN_ROLE()
        });

        dao.grant({
            _who: address(this),
            _where: address(curve),
            _permissionId: curve.CURVE_ADMIN_ROLE()
        });

        dao.grant({
            _who: address(this),
            _where: address(nftLock),
            _permissionId: nftLock.LOCK_ADMIN_ROLE()
        });

        // link them
        escrow.setCurve(address(curve));
        escrow.setVoter(address(voter));
        escrow.setQueue(address(queue));
        escrow.setLockNFT(address(nftLock));
        escrow.setIVotesAdapter(address(ivotesAdapter));
    }

    modifier givenExistingLock() {
        vm.warp(block.timestamp + 1 hours);
        uint256 tokenId = escrow.createLock(Lock_1_Amount);

        Lock_1_ts = block.timestamp;
        Lock_1_start = (block.timestamp / checkpointInterval) / checkpointInterval;
        _;
    }

    function mintAndApproveEscrow() internal {
        token.mint(address(this), 10000000e18);
        token.approve(address(escrow), 10000000e18);
    }

    function slopeChanges(uint256 _end) internal view returns (int256 slope) {
        return curve.slopeChanges(_end);
    }

    function assertTokenPoint(
        uint256 _tokenId,
        uint256 _expectedLatestIndex,
        int256 _biasFP,
        int256 _slopeFP,
        uint256 _checkpointTs,
        uint256 _writtenTs
    ) internal view {
        uint256 tokenLatestIndex = curve.tokenPointLatestIndex(_tokenId);
        assertEq(tokenLatestIndex, _expectedLatestIndex);
        TokenPoint memory tokenP = curve.tokenPointHistory(_tokenId, tokenLatestIndex);
        assertEq(tokenP.coefficients[0], _biasFP);
        assertEq(tokenP.coefficients[1], _slopeFP);
        assertEq(tokenP.checkpointTs, _checkpointTs);
        assertEq(tokenP.writtenTs, _writtenTs);
    }

    function assertGlobalPoint(
        uint256 _expectedLatestIndex,
        int256 _biasFP,
        int256 _slopeFP,
        uint256 _writtenTs
    ) internal view {
        uint256 latestIndex = curve.globalPointLatestIndex();
        assertEq(latestIndex, _expectedLatestIndex);
        GlobalPoint memory p = curve.globalPointHistory(latestIndex);
        assertEq(p.writtenTs, _writtenTs);
        assertEq(p.bias, _biasFP);
        assertEq(p.slope, _slopeFP);
    }

    function assertTotalSupply(uint256 _t, int256 _amountFP) internal view {
        assertEq(curve.supplyAt(_t), uint256(_amountFP / 1e18));
    }

    function assertVotingPower(uint256 _tokenId, int256 _amountFP) internal view {
        assertVotingPower(_tokenId, block.timestamp, _amountFP);
    }

    function assertVotingPower(uint256 _tokenId, uint256 _t, int256 _amountFP) internal view {
        assertEq(curve.votingPowerAt(_tokenId, _t), uint256(_amountFP / 1e18));
    }

    // The default sender to contract calls ends up a test contract itself.
    // We add this receiver so tokens can be minted to test contract.
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
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

    function _deployEscrow(
        address _token,
        address _dao,
        address _clock,
        uint256 _minDeposit
    ) public returns (VotingEscrow) {
        VotingEscrow impl = new VotingEscrow();

        bytes memory initCalldata = abi.encodeCall(
            VotingEscrow.initialize,
            (_token, _dao, _clock, _minDeposit)
        );
        return VotingEscrow(address(impl).deployUUPSProxy(initCalldata));
    }

    function _deployEscrowIVotesAdapter(
        address _dao,
        address _escrow,
        address _clock
    ) public returns (EscrowIVotesAdapter) {
        EscrowIVotesAdapter impl = new EscrowIVotesAdapter();

        bytes memory initCalldata = abi.encodeCall(
            EscrowIVotesAdapter.initialize,
            (_dao, _escrow, _clock)
        );
        return EscrowIVotesAdapter(address(impl).deployUUPSProxy(initCalldata));
    }

    function _deployLock(
        address _escrow,
        string memory _name,
        string memory _symbol,
        address _dao
    ) public returns (Lock) {
        Lock impl = new Lock();

        bytes memory initCalldata = abi.encodeWithSelector(
            Lock.initialize.selector,
            _escrow,
            _name,
            _symbol,
            _dao
        );
        return Lock(address(impl).deployUUPSProxy(initCalldata));
    }

    function _deployCurve(
        address _escrow,
        address _dao,
        uint48 _warmup,
        address _clock
    ) public returns (LinearIncreasingEscrow) {
        LinearIncreasingEscrow impl = new LinearIncreasingEscrow();

        bytes memory initCalldata = abi.encodeCall(
            LinearIncreasingEscrow.initialize,
            (_escrow, _dao, _warmup, _clock)
        );
        return LinearIncreasingEscrow(address(impl).deployUUPSProxy(initCalldata));
    }

    function _deployVoter(
        address _dao,
        address _escrow,
        bool _reset,
        address _clock,
        address _ivotesAdapter
    ) public returns (SimpleGaugeVoter) {
        SimpleGaugeVoter impl = new SimpleGaugeVoter();

        bytes memory initCalldata = abi.encodeCall(
            SimpleGaugeVoter.initialize,
            (_dao, _escrow, _reset, _clock, _ivotesAdapter, true)
        );
        return SimpleGaugeVoter(address(impl).deployUUPSProxy(initCalldata));
    }

    function _deployExitQueue(
        address _escrow,
        uint48 _cooldown,
        address _dao,
        uint256 _feePercent,
        address _clock,
        uint48 _minLock
    ) public returns (ExitQueue) {
        ExitQueue impl = new ExitQueue();

        bytes memory initCalldata = abi.encodeCall(
            ExitQueue.initialize,
            (_escrow, _cooldown, _dao, _feePercent, _clock, _minLock)
        );
        return ExitQueue(address(impl).deployUUPSProxy(initCalldata));
    }

    function _deployClock(address _dao) internal returns (Clock) {
        address impl = address(new Clock());
        bytes memory initCalldata = abi.encodeWithSelector(Clock.initialize.selector, _dao);
        return Clock(impl.deployUUPSProxy(initCalldata));
    }

    function _deployOSX() internal {
        // deploy the mock PSP with the multisig  plugin
        multisigSetup = new MultisigSetup();
        psp = new MockPluginSetupProcessor(address(multisigSetup));
        daoFactory = new MockDAOFactory(psp);
    }

    function _deployDAO() internal {
        dao = createTestDAO(deployer);
    }
}
