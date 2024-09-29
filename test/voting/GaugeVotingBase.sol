pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

// aragon contracts
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO, PermissionManager} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
import {MockDAOFactory} from "@mocks/osx/MockDAOFactory.sol";
import {MockERC20} from "@mocks/MockERC20.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";

import "@helpers/OSxHelpers.sol";

import {Clock} from "@clock/Clock.sol";
import {ISimpleGaugeVoterStorageEventsErrors} from "src/voting/ISimpleGaugeVoter.sol";
import {IEscrowCurveUserStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {IWithdrawalQueueErrors} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {IGaugeVote} from "src/voting/ISimpleGaugeVoter.sol";
import {VotingEscrow, Lock, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, ISimpleGaugeVoterSetupParams} from "src/voting/SimpleGaugeVoterSetup.sol";

contract GaugeVotingBase is
    Test,
    IGaugeVote,
    IEscrowCurveUserStorage,
    ISimpleGaugeVoterStorageEventsErrors
{
    using ProxyLib for address;

    MultisigSetup multisigSetup;
    SimpleGaugeVoterSetup voterSetup;

    // permissions
    PermissionLib.MultiTargetPermission[] voterSetupPermissions;

    MockPluginSetupProcessor psp;
    MockDAOFactory daoFactory;
    MockERC20 token;

    Lock nftLock;
    VotingEscrow escrow;
    QuadraticIncreasingEscrow curve;
    SimpleGaugeVoter voter;
    ExitQueue queue;

    DAO dao;
    Clock clock;
    Multisig multisig;

    address deployer = address(0x420);

    uint256 constant COOLDOWN = 3 days;

    address voterBase;

    function setUp() public virtual {
        // clock reset
        vm.roll(0);
        vm.warp(0);

        // Deploy the OSx framework
        _deployOSX();
        // Deploy a DAO
        _deployDAOAndMSig();

        // new block for multisig
        vm.roll(1);
        // Define our pluginSetup contract to deploy the VE
        _setupVoterContracts();
        _applySetup();

        // unpause the contract
        voter.unpause();
    }

    function _deployOSX() internal {
        // deploy the mock PSP with the multisig  plugin
        multisigSetup = new MultisigSetup();
        psp = new MockPluginSetupProcessor(address(multisigSetup));
        daoFactory = new MockDAOFactory(psp);
    }

    function _deployDAOAndMSig() internal {
        // use the OSx DAO factory with the Plugin
        address[] memory members = new address[](1);
        members[0] = deployer;

        // encode a 1/1 multisig that can be adjusted later
        bytes memory data = abi.encode(
            members,
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 1})
        );

        dao = daoFactory.createDao(_mockDAOSettings(), _mockPluginSettings(data));

        // nonce 0 is something?
        // nonce 1 is implementation contract
        // nonce 2 is the msig contract behind the proxy
        multisig = Multisig(computeAddress(address(multisigSetup), 2));
    }

    function _setupVoterContracts() public {
        token = new MockERC20();

        voterBase = address(new SimpleGaugeVoter());

        // deploy setup
        voterSetup = new SimpleGaugeVoterSetup(
            voterBase,
            address(new QuadraticIncreasingEscrow()),
            address(new ExitQueue()),
            address(new VotingEscrow()),
            address(new Clock()),
            address(new Lock())
        );

        // push to the PSP
        psp.queueSetup(address(voterSetup));

        // prepare the installation
        bytes memory data = abi.encode(
            ISimpleGaugeVoterSetupParams({
                isPaused: true,
                token: address(token),
                veTokenName: "VE Token",
                veTokenSymbol: "VE",
                warmup: 3 days,
                cooldown: 3 days,
                feePercent: 0,
                minLock: 1,
                minDeposit: 1 wei
            })
        );
        (address pluginAddress, IPluginSetup.PreparedSetupData memory preparedSetupData) = psp
            .prepareInstallation(address(dao), _mockPrepareInstallationParams(data));

        // fetch the contracts
        voter = SimpleGaugeVoter(pluginAddress);
        address[] memory helpers = preparedSetupData.helpers;
        curve = QuadraticIncreasingEscrow(helpers[0]);
        queue = ExitQueue(helpers[1]);
        escrow = VotingEscrow(helpers[2]);
        clock = Clock(helpers[3]);
        nftLock = Lock(helpers[4]);

        // set the permissions
        for (uint i = 0; i < preparedSetupData.permissions.length; i++) {
            voterSetupPermissions.push(preparedSetupData.permissions[i]);
        }
    }

    function _actions() internal view returns (IDAO.Action[] memory) {
        IDAO.Action[] memory actions = new IDAO.Action[](9);

        // action 0: apply the ve installation
        actions[0] = IDAO.Action({
            to: address(psp),
            value: 0,
            data: abi.encodeCall(
                psp.applyInstallation,
                (address(dao), _mockApplyInstallationParams(address(escrow), voterSetupPermissions))
            )
        });

        // action 2: activate the curve on the ve
        actions[1] = IDAO.Action({
            to: address(escrow),
            value: 0,
            data: abi.encodeWithSelector(escrow.setCurve.selector, address(curve))
        });

        // action 3: activate the queue on the ve
        actions[2] = IDAO.Action({
            to: address(escrow),
            value: 0,
            data: abi.encodeWithSelector(escrow.setQueue.selector, address(queue))
        });

        // action 4: set the voter
        actions[3] = IDAO.Action({
            to: address(escrow),
            value: 0,
            data: abi.encodeWithSelector(escrow.setVoter.selector, address(voter))
        });

        // action 5: set the nft lock
        actions[4] = IDAO.Action({
            to: address(escrow),
            value: 0,
            data: abi.encodeWithSelector(escrow.setLockNFT.selector, address(nftLock))
        });

        // for testing, give this contract the admin roles on all the periphery contracts
        actions[5] = IDAO.Action({
            to: address(dao),
            value: 0,
            data: abi.encodeCall(
                PermissionManager.grant,
                (address(voter), address(this), voter.GAUGE_ADMIN_ROLE())
            )
        });

        actions[6] = IDAO.Action({
            to: address(dao),
            value: 0,
            data: abi.encodeCall(
                PermissionManager.grant,
                (address(escrow), address(this), escrow.ESCROW_ADMIN_ROLE())
            )
        });

        actions[7] = IDAO.Action({
            to: address(dao),
            value: 0,
            data: abi.encodeCall(
                PermissionManager.grant,
                (address(queue), address(this), queue.QUEUE_ADMIN_ROLE())
            )
        });

        actions[8] = IDAO.Action({
            to: address(dao),
            value: 0,
            data: abi.encodeCall(
                PermissionManager.grant,
                (address(curve), address(this), curve.CURVE_ADMIN_ROLE())
            )
        });

        return wrapGrantRevokeRoot(DAO(payable(address(dao))), address(psp), actions);
    }

    function _applySetup() internal {
        IDAO.Action[] memory actions = _actions();

        // execute the actions
        vm.startPrank(deployer);
        {
            multisig.createProposal({
                _metadata: "",
                _actions: actions,
                _allowFailureMap: 0,
                _approveProposal: true,
                _tryExecution: true,
                _startDate: 0,
                _endDate: uint64(block.timestamp + 1)
            });
        }
        vm.stopPrank();
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
