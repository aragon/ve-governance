pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";
import {UUPSUpgradeable as UUPS} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./helpers/OSxHelpers.sol";

import {Clock} from "@clock/Clock.sol";
import {IEscrowCurveTokenStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {IWithdrawalQueueErrors} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {IGaugeVote} from "src/voting/ISimpleGaugeVoter.sol";
import {VotingEscrow, Lock, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, ISimpleGaugeVoterSetupParams} from "src/voting/SimpleGaugeVoterSetup.sol";

import {GaugesDaoFactory, GaugePluginSet, Deployment} from "src/factory/GaugesDaoFactory.sol";
import {Deploy, DeploymentParameters} from "script/Deploy.s.sol";

interface IERC20Mint is IERC20 {
    function mint(address _to, uint256 _amount) external;
}

contract GhettoMultisig {
    function approveCallerToSpendTokenWithID(address _token, uint256 _id) external {
        _token.call(abi.encodeWithSignature("approve(address,uint256)", msg.sender, _id));
    }
}

contract MultisigReceiver is GhettoMultisig {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

/**
 * This is an enhanced e2e test that aims to do the following:
 * 1. Use factory contract to deploy identically to production
 * 2. Setup a test harness for connecting to either fork or local node
 * 3. A more robust suite of lifecylce tests for multiple users entering and exiting
 * 4. A more robust suite for admininstration of the contracts
 * 5. Ability to connect to an existing deployment and test on the real network
 */
contract TestE2EV2 is Test, IWithdrawalQueueErrors, IGaugeVote, IEscrowCurveTokenStorage {
    error VotingInactive();
    error OnlyEscrow();
    error GaugeDoesNotExist(address _pool);
    error AmountTooSmall();
    error NotApprovedOrOwner();
    error NoVotingPower();
    error NotWhitelisted();
    error NothingToSweep();
    error MinLockNotReached(uint256 tokenId, uint48 minLock, uint48 earliestExitDate);

    uint constant MONTH = 2592000;

    GaugesDaoFactory factory;

    address gauge0 = address(0xc0ffee);
    address gauge1 = address(0x1bad1dea);

    // consistent distributor in fork tests
    address distributor = address(0x1337);

    // although these exist on the factory a bit easier to access here
    // these only reference the FIRST set of contracts, if deploying multiple
    // fetch from the factory
    SimpleGaugeVoter voter;
    QuadraticIncreasingEscrow curve;
    ExitQueue queue;
    VotingEscrow escrow;
    Clock clock;
    Lock lock;
    Multisig multisig;
    DAO dao;
    IERC20Mint token;

    MultisigReceiver jordisMultisig;

    address[] signers;

    enum TestMode {
        /// @dev Not yet supported
        Local,
        /// @dev use the factory to deploy the contracts
        ForkDeploy,
        /// @dev do not deploy the contracts, use the existing ones
        ForkExisting
    }

    /*///////////////////////////////////////////////////////////////
                                Setup
    /////////////////////////////////////////////balanceCarlos////////////////*/

    /// The test here will run in 2 modes:
    /// 1. Local Mode (Not yet supported): we deploy the OSx contracts locally using mocks to expedite testing
    /// 2. Fork Mode: Deploy (Supported): we pass in the real OSx contracts and deploy via the factory
    /// 3. Fork Mode: Existing (Supported): we don't deploy via the factory, we use the existing contract for everything
    function setUp() public {
        // deploy the deploy script
        Deploy deploy = new Deploy();

        // fetch the deployment parameters
        DeploymentParameters memory deploymentParameters = deploy.getDeploymentParameters(
            vm.envBool("DEPLOY_AS_PRODUCTION")
        );

        signers = deploy.readMultisigMembers();

        // any env modifications you need to make to the deployment parameters
        // can be done here
        if (_getTestMode() == TestMode.Local) {
            revert("Local mode not supported yet");
            // setup OSx mocks
            // write the addresses
        }

        // deploy the contracts via the factory
        if (_getTestMode() == TestMode.ForkDeploy) {
            // random ens domain
            deploymentParameters.voterEnsSubdomain = _hToS(
                keccak256(abi.encodePacked("gauges", block.timestamp))
            );

            // deploy the factory
            factory = new GaugesDaoFactory(deploymentParameters);

            // execute the deployment - doing at setup caches it
            factory.deployOnce();
        }
        // connect to the existing factory to fetch the contract addresses
        else if (_getTestMode() == TestMode.ForkExisting) {
            address factoryAddress = vm.envAddress("FACTORY");
            if (factoryAddress == address(0)) {
                revert("Factory address not set");
            }
            factory = GaugesDaoFactory(factoryAddress);
        }

        // set our contracts
        Deployment memory deployment = factory.getDeployment();

        // if deploying multiple tokens, you can adjust the index here
        GaugePluginSet memory pluginSet = deployment.gaugeVoterPluginSets[0];

        voter = SimpleGaugeVoter(pluginSet.plugin);
        curve = QuadraticIncreasingEscrow(pluginSet.curve);
        queue = ExitQueue(pluginSet.exitQueue);
        escrow = VotingEscrow(pluginSet.votingEscrow);
        clock = Clock(pluginSet.clock);
        lock = Lock(pluginSet.nftLock);
        multisig = Multisig(deployment.multisigPlugin);
        dao = DAO(deployment.dao);
        token = IERC20Mint(escrow.token());

        require(_resolveMintTokens(), "Failed to mint tokens");

        // increment the block by 1 to ensure we have a new block
        // A new multisig requires this after changing settings

        vm.roll(block.number + 1);
    }

    /*///////////////////////////////////////////////////////////////
                              Admin Tests
    //////////////////////////////////////////////////////////////*/

    /// we have 2 sets of tests here:
    /// 1. Administrator tests: these tests the long term administration of the contract
    /// and validate that the multisig is able to adjust all the parameters and upgrade the contracts
    /// also test critical reverts and unhappy paths

    /// 2. User/Lifecycle tests: these tests ensure that users can enter, vote and exit.
    /// We test with a handful of live users to ensure that the system is robust
    /// 2a. ensure that both parallel deploys work
    /// also test critical reverts and unhappy paths

    // All contracts are UUPS the multisig must be able to upgrade them freely
    // We use a simple placeholder contract to test this
    function testAdministratorsCanUpgradeAllTheContracts() public {
        // deploy the upgraded contract
        Upgraded upgraded = new Upgraded();

        address[] memory protocolContracts = new address[](6);
        protocolContracts[0] = address(voter);
        protocolContracts[1] = address(curve);
        protocolContracts[2] = address(queue);
        protocolContracts[3] = address(escrow);
        protocolContracts[4] = address(clock);
        protocolContracts[5] = address(lock);

        for (uint256 i = 0; i < protocolContracts.length; i++) {
            // build the proposal
            IDAO.Action[] memory actions = new IDAO.Action[](1);
            actions[0] = IDAO.Action({
                to: protocolContracts[i],
                value: 0,
                data: abi.encodeCall(UUPS(protocolContracts[i]).upgradeTo, address(upgraded))
            });

            // build the proposal
            uint256 proposalId = _buildMsigProposal(actions);

            // sign and execute
            _signExecuteMultisigProposal(proposalId);
        }

        // run a manual confirmation against the ABIs to see the upgrade has happened
        vm.expectRevert("Non upgradable");
        voter.upgradeTo(address(this));

        vm.expectRevert("Non upgradable");
        curve.upgradeTo(address(this));

        vm.expectRevert("Non upgradable");
        queue.upgradeTo(address(this));

        vm.expectRevert("Non upgradable");
        escrow.upgradeTo(address(this));

        vm.expectRevert("Non upgradable");
        clock.upgradeTo(address(this));

        vm.expectRevert("Non upgradable");
        lock.upgradeTo(address(this));
    }

    // test we can pause and unpause
    // this applies to the escrow contract and also to the voting contract
    function testPauseAndUnPause() public {
        // voting - unpause first as deployed paused
        {
            IDAO.Action[] memory actions = new IDAO.Action[](1);
            actions[0] = IDAO.Action({
                to: address(voter),
                value: 0,
                data: abi.encodeCall(voter.unpause, ())
            });

            _buildSignProposal(actions);

            // check
            assertEq(voter.paused(), false);
        }

        // repause
        {
            IDAO.Action[] memory actions = new IDAO.Action[](1);
            actions[0] = IDAO.Action({
                to: address(voter),
                value: 0,
                data: abi.encodeCall(voter.pause, ())
            });

            _buildSignProposal(actions);

            // check
            assertEq(voter.paused(), true);
        }

        // escrow
        // pause
        {
            IDAO.Action[] memory actions = new IDAO.Action[](1);
            actions[0] = IDAO.Action({
                to: address(escrow),
                value: 0,
                data: abi.encodeCall(escrow.pause, ())
            });

            _buildSignProposal(actions);

            // check
            assertEq(escrow.paused(), true);
        }

        // the paused escrow should prevent editing locks
        vm.expectRevert("Pausable: paused");
        escrow.createLock(100 ether);

        vm.expectRevert("Pausable: paused");
        escrow.createLockFor(100 ether, address(this));

        vm.expectRevert("Pausable: paused");
        escrow.withdraw(0);

        vm.expectRevert("Pausable: paused");
        escrow.beginWithdrawal(0);

        vm.expectRevert("Pausable: paused");
        escrow.resetVotesAndBeginWithdrawal(0);

        // unpause
        {
            IDAO.Action[] memory actions = new IDAO.Action[](1);
            actions[0] = IDAO.Action({
                to: address(escrow),
                value: 0,
                data: abi.encodeCall(escrow.unpause, ())
            });

            _buildSignProposal(actions);

            // check
            assertEq(escrow.paused(), false);
        }
    }

    // test the DAO setup - it should be root on itself and the factory should not be root
    // the multisig should have execute on the DAO
    function testDAOSetup() public view {
        assertTrue(
            dao.isGranted({
                _who: address(dao),
                _where: address(dao),
                _permissionId: dao.ROOT_PERMISSION_ID(),
                _data: bytes("")
            })
        );

        assertFalse(
            dao.isGranted({
                _who: address(factory),
                _where: address(dao),
                _permissionId: dao.ROOT_PERMISSION_ID(),
                _data: bytes("")
            })
        );

        assertTrue(
            dao.hasPermission({
                _who: address(multisig),
                _where: address(dao),
                _permissionId: dao.EXECUTE_PERMISSION_ID(),
                _data: bytes("")
            })
        );

        // all the multisig signers should be on the multisig
        for (uint i = 0; i < signers.length; i++) {
            assertTrue(multisig.isMember(signers[i]));
        }

        // check the Dao has the critical roles in all the contracts

        // escrow
        assertTrue(
            dao.isGranted({
                _who: address(dao),
                _where: address(escrow),
                _permissionId: escrow.ESCROW_ADMIN_ROLE(),
                _data: bytes("")
            }),
            "DAO should have escrow admin role"
        );

        assertTrue(
            dao.isGranted({
                _who: address(dao),
                _where: address(escrow),
                _permissionId: escrow.PAUSER_ROLE(),
                _data: bytes("")
            }),
            "DAO should have escrow pauser role"
        );

        assertTrue(
            dao.isGranted({
                _who: address(dao),
                _where: address(escrow),
                _permissionId: escrow.SWEEPER_ROLE(),
                _data: bytes("")
            }),
            "DAO should have escrow sweeper role"
        );

        // voter

        assertTrue(
            dao.isGranted({
                _who: address(dao),
                _where: address(voter),
                _permissionId: voter.GAUGE_ADMIN_ROLE(),
                _data: bytes("")
            }),
            "DAO should have voter gauge admin role"
        );

        assertTrue(
            dao.isGranted({
                _who: address(dao),
                _where: address(voter),
                _permissionId: voter.UPGRADE_PLUGIN_PERMISSION_ID(),
                _data: bytes("")
            }),
            "DAO should have voter upgrade plugin role"
        );

        // lock

        assertTrue(
            dao.isGranted({
                _who: address(dao),
                _where: address(lock),
                _permissionId: lock.LOCK_ADMIN_ROLE(),
                _data: bytes("")
            }),
            "DAO should have lock admin role"
        );

        // queue
        assertTrue(
            dao.isGranted({
                _who: address(dao),
                _where: address(queue),
                _permissionId: queue.QUEUE_ADMIN_ROLE(),
                _data: bytes("")
            }),
            "DAO should have queue admin role"
        );

        assertTrue(
            dao.isGranted({
                _who: address(dao),
                _where: address(queue),
                _permissionId: queue.WITHDRAW_ROLE(),
                _data: bytes("")
            }),
            "DAO should have queue withdraw role"
        );

        // clock

        assertTrue(
            dao.isGranted({
                _who: address(dao),
                _where: address(clock),
                _permissionId: clock.CLOCK_ADMIN_ROLE(),
                _data: bytes("")
            }),
            "DAO should have clock admin role"
        );

        // curve
        assertTrue(
            dao.isGranted({
                _who: address(dao),
                _where: address(curve),
                _permissionId: curve.CURVE_ADMIN_ROLE(),
                _data: bytes("")
            }),
            "DAO should have curve admin role"
        );
    }

    /*///////////////////////////////////////////////////////////////
                          User/Lifecycle Tests
    //////////////////////////////////////////////////////////////*/

    /// here we walkthrough a user journey with 3 users
    /// carlos will have 2 locks, holding both at the same time
    /// javi will have 1 lock minted at the same time as user 1 holds both
    /// carlos will mint his lock for him
    /// jordi will have 1 lock minted after user 1 has exited one of their locks
    /// jordi will have a smart contract wallet
    /// we will have them create the lock, vote across a couple epochs, and then exit
    /// we will also have them attempt to circumvent the system and fail
    /// finally we will define one attacker who will attempt to attack the system and fail

    // 3 caballeros
    address carlos = address(0xca7105);
    address javi = address(0x7af1);
    address jordi = address(0x707d1);

    uint balanceCarlos = 1000 ether;
    uint balanceJavi = 0 ether;
    uint balanceJordi = 1_234 ether;

    uint depositCarlos0 = 250 ether;
    uint depositCarlos1 = 500 ether;
    uint depositCarlosJavi = 250 ether;

    // 1 attacker
    address jordan = address(0x707da);

    uint epochStartTime;

    // warp relative to the start of the test
    function goToEpochStartPlus(uint _time) public {
        vm.warp(epochStartTime + _time);
    }

    function testLifeCycle() public {
        // we are in the voting period based on the pinned block so let's wait till the next epoch
        uint nextEpoch = clock.epochStartTs();
        vm.warp(nextEpoch);
        epochStartTime = block.timestamp;

        // set up labels
        {
            vm.label(carlos, "Carlos");
            vm.label(javi, "Javi");
            vm.label(jordi, "Jordi");
            vm.label(jordan, "Jordan");
        }

        // first we give the guys each some tokens of the underlying
        {
            vm.startPrank(distributor);
            {
                token.transfer(carlos, balanceCarlos);
                token.transfer(jordi, balanceJordi);
            }
            vm.stopPrank();
        }

        // carlos goes first and makes the first deposit, it's at the start of the
        // week, so we would expect him to be warm after 1 week
        // we wait a couple of days and he makes a deposit for javi
        // we expect his warmup to carryover also to the next week
        // we expect both of their locks to start accruing voting power on the same day
        {
            goToEpochStartPlus(1 days);

            vm.startPrank(carlos);
            {
                token.approve(address(escrow), balanceCarlos);

                // we also check he can't create too small a lock
                vm.expectRevert(AmountTooSmall.selector);
                escrow.createLock(100 ether - 1);

                escrow.createLock(depositCarlos0);

                goToEpochStartPlus(6 days);

                escrow.createLockFor(depositCarlosJavi, javi);
            }
            vm.stopPrank();

            // check carlos has token 1, javi has token   2
            assertEq(lock.ownerOf(1), carlos, "Carlos should own token 1");
            assertEq(lock.ownerOf(2), javi, "Javi should own token 2");

            // check the token points written
            TokenPoint memory tp1_1 = curve.tokenPointHistory(1, 1);
            TokenPoint memory tp2_1 = curve.tokenPointHistory(2, 1);

            assertEq(tp1_1.bias, depositCarlos0, "Carlos point 1 should have the correct bias");
            assertEq(tp2_1.bias, depositCarlosJavi, "Javi point should have the correct bias");

            assertEq(
                tp1_1.checkpointTs,
                epochStartTime + clock.checkpointInterval(),
                "carlos point should have the correct checkpoint"
            );
            assertEq(
                tp2_1.checkpointTs,
                epochStartTime + clock.checkpointInterval(),
                "Javi point should have the correct checkpoint"
            );

            assertEq(
                tp1_1.writtenTs,
                epochStartTime + 1 days,
                "Carlos point should have the correct written timestamp"
            );
            assertEq(
                tp2_1.writtenTs,
                epochStartTime + 6 days,
                "Javi point should have the correct written timestamp"
            );

            // check the contract has the correct total
            assertEq(
                escrow.totalLocked(),
                depositCarlos0 + depositCarlosJavi,
                "Total locked should be the sum of the two deposits"
            );

            // checked the locked balances and the token points
            assertEq(
                escrow.locked(1).amount,
                depositCarlos0,
                "Carlos should have the correct amount locked"
            );
            assertEq(
                escrow.locked(2).amount,
                depositCarlosJavi,
                "Javi should have the correct amount locked"
            );

            // start date in the future - carlos will not be warm as his lock is not active yet
            assertFalse(curve.isWarm(1), "Carlos should not be warm");
            assertFalse(curve.isWarm(2), "Javi should not be warm");

            assertEq(escrow.votingPower(1), 0, "Carlos should have no voting power");
            assertEq(escrow.votingPower(2), 0, "Javi should have no voting power");

            assertEq(
                escrow.locked(1).start,
                escrow.locked(2).start,
                "Both locks should start at the same time"
            );
            assertEq(
                escrow.locked(1).start,
                epochStartTime + clock.checkpointInterval(),
                "Both locks should start at the next checkpoint"
            );

            // fast forward to the checkpoint interval carlos is warm and has voting power, javi is not
            goToEpochStartPlus(clock.checkpointInterval());

            assertEq(
                escrow.votingPower(1),
                curve.getBias(0, depositCarlos0),
                "Carlos should not yet have voting power"
            );
            assertTrue(curve.isWarm(1), "Carlos should not be warm");

            assertEq(escrow.votingPower(2), 0, "Javi should not have the correct voting power");
            assertFalse(curve.isWarm(2), "Javi should not be warm");
        }

        // carlos can't even begin an exit because of the min lock
        {
            vm.startPrank(carlos);
            {
                lock.approve(address(escrow), 1);

                TokenPoint memory tp1_1 = curve.tokenPointHistory(1, 1);

                uint expectedMinLock = tp1_1.checkpointTs + MONTH;

                vm.expectRevert(
                    abi.encodeWithSelector(MinLockNotReached.selector, 1, MONTH, expectedMinLock)
                );
                escrow.beginWithdrawal(1);
            }
            vm.stopPrank();
        }

        // we fast forward 4 weeks and check the expected balances
        {
            goToEpochStartPlus(4 weeks);

            // Generalising this is a bit hard...
            // we could check a < x < b, but checking x exactly is tedious
        }

        // we have carlos make a second deposit and validate that his total voting power is initially unchanged
        {
            vm.startPrank(carlos);
            {
                escrow.createLock(depositCarlos1);
            }
            vm.stopPrank();

            // check the token points written
            TokenPoint memory tp1_2 = curve.tokenPointHistory(3, 1);

            assertEq(tp1_2.bias, depositCarlos1, "Carlos point 2 should have the correct bias");
            assertEq(
                tp1_2.checkpointTs,
                epochStartTime + 4 weeks + clock.checkpointInterval(),
                "Carlos point should have the correct checkpoint"
            );
            assertEq(
                tp1_2.writtenTs,
                epochStartTime + 4 weeks,
                "Carlos point should have the correct written timestamp"
            );

            // check the voting power is unchanged (my boi aint warm)
            assertEq(
                escrow.votingPower(3),
                0,
                "Carlos should have no voting power on the second lock"
            );
            assertFalse(curve.isWarm(3), "Carlos should not be warm on the second lock");

            // check the total voting power on the escrow
            assertEq(
                escrow.totalLocked(),
                depositCarlos0 + depositCarlos1 + depositCarlosJavi,
                "Total locked should be the sum of the two deposits"
            );

            // calculate elapsed time since we made the first lock
            uint timeElapsedSinceFirstLock = block.timestamp -
                curve.tokenPointHistory(1, 1).checkpointTs;

            assertEq(
                escrow.votingPowerForAccount(carlos),
                curve.getBias(timeElapsedSinceFirstLock, depositCarlos0),
                "Carlos should only have the first lock active"
            );
        }
        // we then fast forward 1 week and check that his voting power has increased as expected with the new lock
        {
            goToEpochStartPlus(5 weeks);

            // calculate elapsed time since we made the first lock
            uint timeElapsedSinceFirstLock = block.timestamp -
                curve.tokenPointHistory(1, 1).checkpointTs;

            // elased time is zero so should be exactly equal to the bias
            assertEq(
                escrow.votingPowerForAccount(carlos),
                curve.getBias(timeElapsedSinceFirstLock, depositCarlos0) + depositCarlos1,
                "Carlos should have extra voting power"
            );
        }

        // jordan tries to enter the queue with one of their locks
        {
            vm.startPrank(jordan);
            {
                bytes memory erc721ownererr = "ERC721: caller is not token owner or approved";
                for (uint i = 1; i <= 3; i++) {
                    vm.expectRevert(OnlyEscrow.selector);
                    queue.queueExit(i, jordan);

                    // lingering permissions from carlos' approval
                    if (i == 1) {
                        vm.expectRevert(bytes("ERC721: transfer from incorrect owner"));
                    } else {
                        vm.expectRevert(erc721ownererr);
                    }

                    escrow.beginWithdrawal(i);
                }
            }
            vm.stopPrank();
        }

        // the guys try to vote but it's paused
        {
            assertFalse(clock.votingActive(), "Voting should not be active");

            address[3] memory stakers = [carlos, javi, jordi];
            GaugeVote[] memory votes = new GaugeVote[](0);
            for (uint i = 0; i < 3; i++) {
                address staker = stakers[i];
                vm.startPrank(staker);
                {
                    vm.expectRevert("Pausable: paused");
                    voter.vote(1, votes);
                }
                vm.stopPrank();
            }

            // same issue when unpaused, votes aren't active
            IDAO.Action[] memory actions = new IDAO.Action[](1);
            actions[0] = IDAO.Action({
                to: address(voter),
                value: 0,
                data: abi.encodeCall(voter.unpause, ())
            });
            _buildSignProposal(actions);

            for (uint i = 0; i < 3; i++) {
                address staker = stakers[i];
                vm.startPrank(staker);
                {
                    vm.expectRevert(VotingInactive.selector);
                    voter.vote(1, votes);
                }
                vm.stopPrank();
            }

            // move to the next voting window, should not be active at the start of the voting window
            goToEpochStartPlus(6 weeks);

            assertFalse(clock.votingActive(), "Voting should not be active");

            // go one hour further - 1, still no

            goToEpochStartPlus(6 weeks + 1 hours - 1);

            assertFalse(clock.votingActive(), "Voting should not be active");

            // go one SECOND further, now it should be active

            goToEpochStartPlus(6 weeks + 1 hours);

            assertTrue(clock.votingActive(), "Voting should be active");
        }

        // the guys vote after a gauge is created and the voting is active, they split votes between the gauges
        {
            // can't frontrun the voting for a non existent gauge
            GaugeVote[] memory incorrectVotes = new GaugeVote[](1);
            incorrectVotes[0] = GaugeVote({gauge: address(123), weight: 1});

            vm.startPrank(carlos);
            {
                vm.expectRevert(abi.encodeWithSelector(GaugeDoesNotExist.selector, address(123)));
                voter.vote(1, incorrectVotes);
            }
            vm.stopPrank();

            // create the gauge
            {
                string memory metadataURI0 = "ipfs://gauge0";
                string memory metadataURI1 = "ipfs://gauge1";
                IDAO.Action[] memory actions = new IDAO.Action[](2);
                actions[0] = IDAO.Action({
                    to: address(voter),
                    value: 0,
                    data: abi.encodeWithSelector(voter.createGauge.selector, gauge0, metadataURI0)
                });
                actions[1] = IDAO.Action({
                    to: address(voter),
                    value: 0,
                    data: abi.encodeWithSelector(voter.createGauge.selector, gauge1, metadataURI1)
                });

                _buildSignProposal(actions);

                // gauges should exist and be active
                assertTrue(voter.isActive(gauge0), "Gauge 0 should be active");
                assertTrue(voter.isActive(gauge1), "Gauge 1 should be active");

                // check the metadata
                assertEq(
                    voter.getGauge(gauge0).metadataURI,
                    metadataURI0,
                    "Gauge 0 should have the correct metadata"
                );
                assertEq(
                    voter.getGauge(gauge1).metadataURI,
                    metadataURI1,
                    "Gauge 1 should have the correct metadata"
                );
            }

            // jordan tries voting for someone else and fails
            {
                GaugeVote[] memory votes = new GaugeVote[](2);
                votes[0] = GaugeVote({gauge: gauge0, weight: 1});
                votes[1] = GaugeVote({gauge: gauge1, weight: 1});

                vm.startPrank(jordan);
                {
                    vm.expectRevert(NotApprovedOrOwner.selector);
                    voter.vote(1, votes);

                    // what about a non-existent id
                    vm.expectRevert("ERC721: invalid token ID");
                    voter.vote(123, votes);
                }
                vm.stopPrank();
            }

            // the boys vote: carlos votes with multiple and jord with a single
            {
                GaugeVote[] memory votes = new GaugeVote[](2);

                // carlos is 50 50
                votes[0] = GaugeVote({gauge: gauge0, weight: 1});
                votes[1] = GaugeVote({gauge: gauge1, weight: 1});
                uint[] memory ids = new uint[](2);
                ids[0] = 1;
                ids[1] = 3;

                vm.startPrank(carlos);
                {
                    voter.voteMultiple(ids, votes);
                }
                vm.stopPrank();

                // javi votes for the one gauge
                votes = new GaugeVote[](1);
                votes[0] = GaugeVote({gauge: gauge0, weight: 1});

                vm.startPrank(javi);
                {
                    voter.vote(2, votes);
                }
                vm.stopPrank();

                // check the votes - we should have all of javi's votes (id 2) for gauge 0
                // carlos' votes should be split between the two gauges
                // in total the second gauge should have 50% of the votes of carlos' votes
                // and the first 100% of javi's votes + 50% of carlos' votes
                assertEq(
                    voter.votes(1, gauge0),
                    escrow.votingPower(1) / 2,
                    "Carlos 1 g 0 should have the correct votes"
                );
                assertEq(
                    voter.votes(1, gauge1),
                    escrow.votingPower(1) / 2,
                    "Carlos 1 g 1 should have the correct votes"
                );
                assertEq(
                    voter.votes(2, gauge0),
                    escrow.votingPower(2),
                    "Javi should have the correct votes"
                );
                assertEq(
                    voter.votes(3, gauge0),
                    escrow.votingPower(3) / 2,
                    "Carlos 3 g 0 should have the correct votes"
                );
                assertEq(
                    voter.votes(3, gauge1),
                    escrow.votingPower(3) / 2,
                    "Carlos 3 g 1 should have the correct votes"
                );

                // check the gauge votes
                assertEq(
                    voter.gaugeVotes(gauge0),
                    escrow.votingPower(2) + escrow.votingPower(1) / 2 + escrow.votingPower(3) / 2
                );
                assertEq(
                    voter.gaugeVotes(gauge1),
                    escrow.votingPower(1) / 2 + escrow.votingPower(3) / 2
                );
            }
        }

        // jordi create a deposit mid vote and tries to vote - he should have no voting power
        {
            vm.startPrank(jordi);
            {
                token.approve(address(escrow), balanceJordi);

                // bad contract first
                GhettoMultisig badMultisig = new GhettoMultisig();

                vm.expectRevert("ERC721: transfer to non ERC721Receiver implementer");
                escrow.createLockFor(balanceJordi, address(badMultisig));

                // he fixes it
                jordisMultisig = new MultisigReceiver();

                escrow.createLockFor(balanceJordi, address(jordisMultisig));

                // allow jordi to vote on behalf of his msig
                jordisMultisig.approveCallerToSpendTokenWithID(address(lock), 4);

                GaugeVote[] memory votes = new GaugeVote[](2);
                votes[0] = GaugeVote({gauge: gauge0, weight: 1});
                votes[1] = GaugeVote({gauge: gauge1, weight: 1});

                vm.expectRevert(NoVotingPower.selector);
                voter.vote(4, votes);
            }
            vm.stopPrank();
        }

        // javi updates his vote
        {
            GaugeVote[] memory votes = new GaugeVote[](1);
            votes[0] = GaugeVote({gauge: gauge1, weight: 1});

            vm.startPrank(javi);
            {
                voter.vote(2, votes);
            }
            vm.stopPrank();

            // check the votes - we should have all of javi's votes (id 2) for gauge 1
            // carlos' votes should be split between the two gauges
            // in total the second gauge should have 100% of Javi's votes + 50% of the votes of carlos' votes
            // and the first 50% of carlos' votes
            assertEq(
                voter.votes(1, gauge0),
                escrow.votingPower(1) / 2,
                "Carlos 1 g 0 should have the correct votes"
            );

            assertEq(
                voter.votes(1, gauge1),
                escrow.votingPower(1) / 2,
                "Carlos 1 g 1 should have the correct votes"
            );

            assertEq(voter.votes(2, gauge0), 0, "Javi should have the correct votes");

            assertEq(
                voter.votes(2, gauge1),
                escrow.votingPower(2),
                "Javi should have the correct votes"
            );

            assertEq(
                voter.votes(3, gauge0),
                escrow.votingPower(3) / 2,
                "Carlos 3 g 0 should have the correct votes"
            );

            assertEq(
                voter.votes(3, gauge1),
                escrow.votingPower(3) / 2,
                "Carlos 3 g 1 should have the correct votes"
            );

            // check the gauge votes
            assertEq(
                voter.gaugeVotes(gauge0),
                escrow.votingPower(1) / 2 + escrow.votingPower(3) / 2
            );

            assertEq(
                voter.gaugeVotes(gauge1),
                escrow.votingPower(2) + escrow.votingPower(1) / 2 + escrow.votingPower(3) / 2
            );
        }

        // at distribution we wait
        // the guys try and exit but can't
        {
            // go to 1 hour - 1 second before vote closes
            goToEpochStartPlus(7 weeks - 1 hours - 1);

            assertTrue(clock.votingActive(), "Voting should be active");

            // closes the next second
            goToEpochStartPlus(7 weeks - 1 hours);

            assertFalse(clock.votingActive(), "Voting should not be active");

            // carlos tries to exit
            vm.startPrank(carlos);
            {
                vm.expectRevert(VotingInactive.selector);
                escrow.resetVotesAndBeginWithdrawal(1);

                vm.expectRevert(CannotExit.selector);
                escrow.beginWithdrawal(1);
            }
            vm.stopPrank();
        }

        // we wait till voting is over and they begin the exit - carlos does anyhow
        // we check he can't exit early and someone can't exit for him
        {
            goToEpochStartPlus(8 weeks + 1 hours);

            vm.startPrank(carlos);
            {
                lock.approve(address(escrow), 1);
                escrow.resetVotesAndBeginWithdrawal(1);
            }
            vm.stopPrank();

            // carlos doesnt have the nft - its in the queue but he has a ticket
            assertEq(lock.ownerOf(1), address(escrow), "Carlos should not own the nft");
            assertEq(queue.queue(1).holder, carlos, "Carlos should be in the queue");

            // expected exit date is:
            // now + cooldown given that it crosses the cp boundary
            assertEq(
                queue.queue(1).exitDate,
                epochStartTime + 8 weeks + 1 hours + queue.cooldown(),
                "Carlos should be able to exit at the next checkpoint"
            );

            // second user point wrttien
            TokenPoint memory tp1_2 = curve.tokenPointHistory(1, 2);

            assertEq(tp1_2.bias, 0, "Carlos point 1_2 should have the correct bias");
            assertEq(
                tp1_2.checkpointTs,
                epochStartTime + 8 weeks + clock.checkpointInterval(),
                "Carlos point should have the correct checkpoint"
            );
            assertEq(
                tp1_2.writtenTs,
                epochStartTime + 8 weeks + 1 hours,
                "Carlos point should have the correct written timestamp"
            );

            // he can't exit early
            vm.startPrank(carlos);
            {
                vm.expectRevert(CannotExit.selector);
                escrow.withdraw(1);

                // go to cooldown end
                goToEpochStartPlus(8 weeks + 1 hours + MONTH);

                // can't exit yet
                vm.expectRevert(CannotExit.selector);
                escrow.withdraw(1);

                // + 1s he can (1738616401)
                goToEpochStartPlus(8 weeks + 1 hours + MONTH + 1);

                escrow.withdraw(1);
            }
            vm.stopPrank();

            // he should have his original amount back, minus any fees
            assertEq(
                token.balanceOf(carlos),
                depositCarlos0 - (queue.feePercent() * depositCarlos0) / 10_000,
                "Carlos should have the correct balance after exiting"
            );

            // check the total locked
            assertEq(
                escrow.totalLocked(),
                depositCarlos1 + depositCarlosJavi + balanceJordi,
                "Total locked should be the sum of the two deposits"
            );

            // there are no fees in our contract
            assertEq(token.balanceOf(address(queue)), 0, "Queue should have no fees");
        }

        // governance changes some params: warmup is now one day, cooldown is a week
        {
            IDAO.Action[] memory actions = new IDAO.Action[](2);
            actions[0] = IDAO.Action({
                to: address(curve),
                value: 0,
                data: abi.encodeWithSelector(curve.setWarmupPeriod.selector, 1 days)
            });
            actions[1] = IDAO.Action({
                to: address(queue),
                value: 0,
                data: abi.encodeWithSelector(queue.setCooldown.selector, 1 weeks)
            });

            _buildSignProposal(actions);

            // check the new params
            assertEq(curve.warmupPeriod(), 1 days, "Curve should have the correct warmup period");
            assertEq(queue.cooldown(), 1 weeks, "Queue should have the correct cooldown period");
        }

        // carlos creates a new lock 12 h the window opens, he should be warm tomorrow
        {
            goToEpochStartPlus(10 weeks - 12 hours);

            vm.startPrank(carlos);
            {
                token.approve(address(escrow), depositCarlos0);
                escrow.createLock(depositCarlos0);
            }
            vm.stopPrank();

            // nope
            goToEpochStartPlus(10 weeks + 12 hours);
            assertFalse(curve.isWarm(5), "Carlos should not be warm");

            // +1s
            goToEpochStartPlus(10 weeks + 12 hours + 1);
            assertTrue(curve.isWarm(5), "Carlos should be warm");
        }

        // javi goes for an exit, he should be able to exit in a week
        {
            goToEpochStartPlus(10 weeks + 3 days);

            vm.startPrank(javi);
            {
                voter.reset(2);
                lock.approve(address(escrow), 2);
                escrow.beginWithdrawal(2);
            }
            vm.stopPrank();

            // javi doesnt have the nft - its in the queue but he has a ticket
            assertEq(lock.ownerOf(2), address(escrow), "Javi should not own the nft");
            assertEq(queue.queue(2).holder, javi, "Javi should be in the queue");

            // exit date should be 1 week from now
            assertEq(
                queue.queue(2).exitDate,
                epochStartTime + 11 weeks + 3 days,
                "Javi should be able to exit in a week"
            );

            // go there + 1 and exit
            goToEpochStartPlus(11 weeks + 3 days + 1);

            vm.startPrank(javi);
            {
                escrow.withdraw(2);
            }
            vm.stopPrank();

            // total locked should be carlos' 2 deposits + jordis
            assertEq(
                escrow.totalLocked(),
                depositCarlos0 + depositCarlos1 + balanceJordi,
                "Total locked should be the sum of the deposits"
            );
        }

        // jordi tries to send his nft to the lock and queue, and can't but he accidentally sends it to the escrow
        {
            vm.startPrank(jordi);
            {
                vm.expectRevert(NotWhitelisted.selector);
                lock.transferFrom(jordi, address(queue), 4);

                vm.expectRevert(NotWhitelisted.selector);
                lock.transferFrom(jordi, address(lock), 4);

                // he sends it to the escrow
                lock.transferFrom(address(jordisMultisig), address(escrow), 4);
            }
            vm.stopPrank();

            assertEq(lock.ownerOf(4), address(escrow), "Jordi should not own the nft");

            // he can't get it back now :(
            vm.startPrank(jordi);
            {
                vm.expectRevert("ERC721: caller is not token owner or approved");
                lock.transferFrom(address(escrow), jordi, 4);
            }
            vm.stopPrank();
        }

        // we recover it from him
        {
            IDAO.Action[] memory actions = new IDAO.Action[](3);
            actions[0] = IDAO.Action({
                to: address(lock),
                value: 0,
                data: abi.encodeWithSelector(lock.setWhitelisted.selector, address(jordi), true)
            });
            actions[1] = IDAO.Action({
                to: address(escrow),
                value: 0,
                data: abi.encodeWithSelector(escrow.sweepNFT.selector, 4, jordi)
            });
            actions[2] = IDAO.Action({
                to: address(lock),
                value: 0,
                data: abi.encodeWithSelector(lock.setWhitelisted.selector, address(jordi), false)
            });

            _buildSignProposal(actions);

            // check he has it
            assertEq(lock.ownerOf(4), jordi, "Jordi should own the nft");
        }

        // jordan convinces the dev team to give him sweeper access and tries to rug all the tokens, he cant
        {
            IDAO.Action[] memory actions = new IDAO.Action[](1);
            actions[0] = IDAO.Action({
                to: address(dao),
                value: 0,
                data: abi.encodeCall(dao.grant, (address(escrow), jordan, escrow.SWEEPER_ROLE()))
            });
            _buildSignProposal(actions);

            vm.prank(distributor);
            token.transfer(jordan, 100 ether);

            vm.startPrank(jordan);
            {
                vm.expectRevert(NothingToSweep.selector);
                escrow.sweep();

                // however he sends some of his own tokens and can get those out
                token.transfer(address(escrow), 100 ether);

                assertEq(token.balanceOf(jordan), 0, "Jordan should have no tokens");

                escrow.sweep();

                assertEq(token.balanceOf(jordan), 100 ether, "Jordan should have his tokens");
            }
            vm.stopPrank();
        }

        // we get all the guys to exit and unwind their positions
        {
            // warp to a voting window - must pass the min lock
            goToEpochStartPlus(16 weeks + 2 hours);

            vm.startPrank(carlos);
            {
                lock.approve(address(escrow), 3);
                lock.approve(address(escrow), 5);

                escrow.resetVotesAndBeginWithdrawal(3);
                escrow.beginWithdrawal(5);
            }
            vm.stopPrank();

            vm.startPrank(jordi);
            {
                lock.approve(address(escrow), 4);
                escrow.beginWithdrawal(4);
            }
            vm.stopPrank();

            // fast forward a month
            goToEpochStartPlus(16 weeks + 2 hours + MONTH);

            // carlos exits
            vm.startPrank(carlos);
            {
                escrow.withdraw(3);
                escrow.withdraw(5);
            }
            vm.stopPrank();

            // jordi exits
            vm.startPrank(jordi);
            {
                escrow.withdraw(4);
            }
            vm.stopPrank();
        }

        // we check the end state of the contracts
        {
            // no votes
            assertEq(voter.totalVotingPowerCast(), 0, "Voter should have no votes");
            assertEq(voter.gaugeVotes(gauge0), 0, "Gauge 0 should have no votes");
            assertEq(voter.gaugeVotes(gauge1), 0, "Gauge 1 should have no votes");

            // no tokens
            assertEq(token.balanceOf(address(escrow)), 0, "Escrow should have no tokens");
            assertEq(escrow.totalLocked(), 0, "Escrow should have no locked tokens");

            // no locks
            assertEq(lock.totalSupply(), 0, "Lock should have no tokens");
        }
    }

    // run a quick sanity fork test with both real tokens

    // run a test with different parameters

    /*///////////////////////////////////////////////////////////////
                              Utils
    //////////////////////////////////////////////////////////////*/

    function _getTestMode() internal view returns (TestMode) {
        string memory mode = vm.envString("TEST_MODE");
        if (keccak256(abi.encodePacked(mode)) == keccak256(abi.encodePacked("fork-deploy"))) {
            return TestMode.ForkDeploy;
        } else if (
            keccak256(abi.encodePacked(mode)) == keccak256(abi.encodePacked("fork-existing"))
        ) {
            return TestMode.ForkExisting;
        } else if (keccak256(abi.encodePacked(mode)) == keccak256(abi.encodePacked("local"))) {
            return TestMode.Local;
        } else {
            revert("Invalid test mode - valid options are fork-deploy, fork-existing, local");
        }
    }

    function _hToS(bytes32 _hash) internal pure returns (string memory) {
        bytes memory hexString = new bytes(64);
        bytes memory alphabet = "0123456789abcdef";

        for (uint256 i = 0; i < 32; i++) {
            hexString[i * 2] = alphabet[uint8(_hash[i] >> 4)];
            hexString[1 + i * 2] = alphabet[uint8(_hash[i] & 0x0f)];
        }

        return string(hexString);
    }

    function _buildMsigProposal(
        IDAO.Action[] memory actions
    ) internal returns (uint256 proposalId) {
        // prank the first signer who will create stuff
        vm.startPrank(signers[0]);
        {
            proposalId = multisig.createProposal({
                _metadata: "",
                _actions: actions,
                _allowFailureMap: 0,
                _approveProposal: true,
                _tryExecution: false,
                _startDate: 0,
                _endDate: uint64(block.timestamp) + 3 days
            });
        }
        vm.stopPrank();

        return proposalId;
    }

    function _signExecuteMultisigProposal(uint256 _proposalId) internal {
        // load all the proposers into memory other than the first

        if (signers.length > 1) {
            // have them sign
            for (uint256 i = 1; i < signers.length; i++) {
                vm.startPrank(signers[i]);
                {
                    multisig.approve(_proposalId, false);
                }
                vm.stopPrank();
            }
        }

        // prank the first signer who will create stuff
        vm.startPrank(signers[0]);
        {
            multisig.execute(_proposalId);
        }
        vm.stopPrank();
    }

    function _buildSignProposal(
        IDAO.Action[] memory actions
    ) internal returns (uint256 proposalId) {
        proposalId = _buildMsigProposal(actions);
        _signExecuteMultisigProposal(proposalId);
        return proposalId;
    }

    /// depending on the network, we need different approaches to mint tokens
    /// on a fork
    function _resolveMintTokens() internal returns (bool) {
        try token.mint(address(distributor), 3_000 ether) {
            return true;
        } catch {}

        // next check if ownable - we can spoof this
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSignature("owner()"));

        if (success) {
            address owner = abi.decode(data, (address));
            vm.prank(owner);
            token.mint(address(distributor), 3_000 ether);
            return true;
        }

        // next we just try a good old fashioned find a whale and rug them in the test
        address whale = vm.envAddress("TOKEN_TEST_WHALE");
        if (whale == address(0)) {
            return false;
        }

        vm.prank(whale);
        token.transfer(address(distributor), 3_000 ether);
        return true;
    }
}

contract Upgraded is UUPS {
    function _authorizeUpgrade(address) internal pure override {
        revert("Non upgradable");
    }
}
