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

import {IVotingEscrowEventsStorageErrors} from "@escrow-interfaces/IVotingEscrowIncreasing.sol";
import {VotingEscrow} from "@escrow/VotingEscrowIncreasing.sol";
import {QuadraticIncreasingEscrow} from "@escrow/QuadraticIncreasingEscrow.sol";
import {ExitQueue} from "@escrow/ExitQueue.sol";
import {SimpleGaugeVoter, SimpleGaugeVoterSetup} from "src/voting/SimpleGaugeVoterSetup.sol";

contract EscrowBase is Test, IVotingEscrowEventsStorageErrors {
    using ProxyLib for address;
    string name = "Voting Escrow";
    string symbol = "VE";

    MockPluginSetupProcessor psp;
    MockDAOFactory daoFactory;
    MockERC20 token;

    VotingEscrow escrow;
    QuadraticIncreasingEscrow curve;
    SimpleGaugeVoter voter;
    ExitQueue queue;

    DAO dao;
    Multisig multisig;
    MultisigSetup multisigSetup;
    address deployer = address(this);

    function setUp() public virtual {
        // _deployOSX();
        _deployDAO();

        // deploy our contracts
        token = new MockERC20();
        escrow = _deployEscrow(address(token), address(dao), name, symbol);
        curve = _deployCurve(address(escrow), address(dao), 3 days);

        // to be added as proxies
        voter = _deployVoter(address(dao), address(escrow), false);
        queue = _deployExitQueue(address(escrow), 3 days, address(dao));

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

        // link them
        escrow.setCurve(address(curve));
        escrow.setVoter(address(voter));
        escrow.setQueue(address(queue));
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
        string memory _name,
        string memory _symbol
    ) public returns (VotingEscrow) {
        VotingEscrow impl = new VotingEscrow();

        bytes memory initCalldata = abi.encodeCall(
            VotingEscrow.initialize,
            (_token, _dao, _name, _symbol)
        );
        return VotingEscrow(address(impl).deployUUPSProxy(initCalldata));
    }

    function _deployCurve(
        address _escrow,
        address _dao,
        uint256 _warmup
    ) public returns (QuadraticIncreasingEscrow) {
        QuadraticIncreasingEscrow impl = new QuadraticIncreasingEscrow();

        bytes memory initCalldata = abi.encodeCall(
            QuadraticIncreasingEscrow.initialize,
            (_escrow, _dao, _warmup)
        );
        return QuadraticIncreasingEscrow(address(impl).deployUUPSProxy(initCalldata));
    }

    function _deployVoter(
        address _dao,
        address _escrow,
        bool _reset
    ) public returns (SimpleGaugeVoter) {
        return new SimpleGaugeVoter(_dao, _escrow, _reset);

        // bytes memory initCalldata = abi.encodeCall(
        //     SimpleGaugeVoter.initialize,
        //     (address(dao), address(escrow), address(curve))
        // );
        // return SimpleGaugeVoter(address(impl).deployUUPSProxy(initCalldata));
    }

    function _deployExitQueue(
        address _escrow,
        uint _cooldown,
        address _dao
    ) public returns (ExitQueue) {
        return new ExitQueue(_escrow, _cooldown, _dao);

        // bytes memory initCalldata = abi.encodeCall(
        //     ExitQueue.initialize,
        //     (address(escrow))
        // );
        // return ExitQueue(address(impl).deployUUPSProxy(initCalldata));
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
