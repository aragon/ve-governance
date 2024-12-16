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

import "@helpers/OSxHelpers.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";

import {IVotingEscrowEventsStorageErrorsEvents} from "@escrow-interfaces/IVotingEscrowIncreasing.sol";
import {IMigrateableEventsAndErrors} from "@escrow-interfaces/IMigrateable.sol";
import {IWhitelistErrors, IWhitelistEvents} from "@escrow-interfaces/ILock.sol";
import {Lock} from "@escrow/Lock.sol";
import {VotingEscrow} from "@escrow/VotingEscrowIncreasing.sol";
import {QuadraticIncreasingEscrow} from "@escrow/QuadraticIncreasingEscrow.sol";
import {ExitQueue} from "@escrow/ExitQueue.sol";
import {SimpleGaugeVoter, SimpleGaugeVoterSetup} from "src/voting/SimpleGaugeVoterSetup.sol";
import {Clock} from "@clock/Clock.sol";

struct Deployment {
    MockERC20 token;
    Lock nftLock;
    VotingEscrow escrow;
    QuadraticIncreasingEscrow curve;
    SimpleGaugeVoter voter;
    ExitQueue queue;
    Clock clock;
    DAO dao;
    Multisig multisig;
    MultisigSetup multisigSetup;
    address deployer;
}

contract MigrationBase is
    Test,
    IVotingEscrowEventsStorageErrorsEvents,
    IWhitelistErrors,
    IWhitelistEvents,
    IMigrateableEventsAndErrors
{
    using ProxyLib for address;

    string name = "Voting Escrow";
    string symbol = "VE";

    Deployment src;
    Deployment dst;

    function setUp() public virtual {
        MockERC20 token = new MockERC20();
        src = _deploy(token);
        dst = _deploy(token);
    }

    function _deploy(MockERC20 _token) internal returns (Deployment memory deployment) {
        deployment.deployer = address(this);

        // Deploy DAO
        deployment.dao = _deployDAO(deployment.deployer);

        // Deploy ERC20 Token
        deployment.token = _token;

        // Deploy Clock
        deployment.clock = _deployClock(address(deployment.dao));

        // Deploy Voting Escrow
        deployment.escrow = _deployEscrow(
            address(deployment.token),
            address(deployment.dao),
            address(deployment.clock),
            1
        );

        // Deploy Curve
        deployment.curve = _deployCurve(
            address(deployment.escrow),
            address(deployment.dao),
            3 days,
            address(deployment.clock)
        );

        // Deploy Lock
        deployment.nftLock = _deployLock(
            address(deployment.escrow),
            name,
            symbol,
            address(deployment.dao)
        );

        // Deploy Exit Queue
        deployment.queue = _deployExitQueue(
            address(deployment.escrow),
            3 days,
            address(deployment.dao),
            0,
            address(deployment.clock),
            1
        );

        // deploy voter
        deployment.voter = _deployVoter(
            address(deployment.dao),
            address(deployment.escrow),
            false,
            address(deployment.clock)
        );

        // Grant necessary roles
        deployment.dao.grant({
            _who: address(this),
            _where: address(deployment.escrow),
            _permissionId: deployment.escrow.ESCROW_ADMIN_ROLE()
        });

        deployment.dao.grant({
            _who: address(this),
            _where: address(deployment.escrow),
            _permissionId: deployment.escrow.PAUSER_ROLE()
        });

        deployment.dao.grant({
            _who: address(this),
            _where: address(deployment.queue),
            _permissionId: deployment.queue.QUEUE_ADMIN_ROLE()
        });

        deployment.dao.grant({
            _who: address(this),
            _where: address(deployment.curve),
            _permissionId: deployment.curve.CURVE_ADMIN_ROLE()
        });

        deployment.dao.grant({
            _who: address(this),
            _where: address(deployment.nftLock),
            _permissionId: deployment.nftLock.LOCK_ADMIN_ROLE()
        });

        deployment.dao.grant({
            _who: address(this),
            _where: address(deployment.voter),
            _permissionId: deployment.voter.GAUGE_ADMIN_ROLE()
        });

        // Link contracts
        deployment.escrow.setCurve(address(deployment.curve));
        deployment.escrow.setQueue(address(deployment.queue));
        deployment.escrow.setLockNFT(address(deployment.nftLock));
        deployment.escrow.setVoter(address(deployment.voter));

        return deployment;
    }

    function _deployDAO(address deployer) internal returns (DAO) {
        return createTestDAO(deployer);
    }

    function _deployClock(address _dao) internal returns (Clock) {
        address impl = address(new Clock());
        bytes memory initCalldata = abi.encodeWithSelector(Clock.initialize.selector, _dao);
        return Clock(impl.deployUUPSProxy(initCalldata));
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
    ) public returns (QuadraticIncreasingEscrow) {
        QuadraticIncreasingEscrow impl = new QuadraticIncreasingEscrow();

        bytes memory initCalldata = abi.encodeCall(
            QuadraticIncreasingEscrow.initialize,
            (_escrow, _dao, _warmup, _clock)
        );
        return QuadraticIncreasingEscrow(address(impl).deployUUPSProxy(initCalldata));
    }

    function _deployVoter(
        address _dao,
        address _escrow,
        bool _reset,
        address _clock
    ) public returns (SimpleGaugeVoter) {
        SimpleGaugeVoter impl = new SimpleGaugeVoter();

        bytes memory initCalldata = abi.encodeCall(
            SimpleGaugeVoter.initialize,
            (_dao, _escrow, _reset, _clock)
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

    function _authErr(
        address _dao,
        address _caller,
        address _contract,
        bytes32 _perm
    ) internal view returns (bytes memory) {
        return abi.encodeWithSelector(DaoUnauthorized.selector, _dao, _contract, _caller, _perm);
    }
}
