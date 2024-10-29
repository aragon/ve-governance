pragma solidity ^0.8.17;

import {AragonTest} from "../base/AragonTest.sol";
import {console2 as console} from "forge-std/console2.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";
import {UUPSUpgradeable as UUPS} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../helpers/OSxHelpers.sol";

import {Clock} from "@clock/Clock.sol";
import {IEscrowCurveTokenStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {IWithdrawalQueueErrors} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {IGaugeVote} from "src/voting/ISimpleGaugeVoter.sol";
import {VotingEscrow, Lock, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, ISimpleGaugeVoterSetupParams} from "src/voting/SimpleGaugeVoterSetup.sol";

import {GaugesDaoFactory, GaugePluginSet, Deployment} from "src/factory/GaugesDaoFactory.sol";
import {DeployGauges, DeploymentParameters} from "script/DeployGauges.s.sol";

interface IERC20Mint is IERC20 {
    function mint(address _to, uint256 _amount) external;
}

contract GhettoMultisig {
    function approveCallerToSpendTokenWithID(
        address _token,
        uint256 _id
    ) external returns (bool, bytes memory) {
        return _token.call(abi.encodeWithSignature("approve(address,uint256)", msg.sender, _id));
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
contract TestE2EV2 is AragonTest, IWithdrawalQueueErrors, IGaugeVote, IEscrowCurveTokenStorage {
    error VotingInactive();
    error OnlyEscrow();
    error GaugeDoesNotExist(address _pool);
    error NotApprovedOrOwner();
    error NoVotingPower();
    error NotWhitelisted();
    error NothingToSweep();

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

    MultisigReceiver carolsMultisig;

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
    /////////////////////////////////////////////////////////////*/

    /// The test here will run in 2 modes:
    /// 1. Local Mode (Not yet supported): we deploy the OSx contracts locally using mocks to expedite testing
    /// 2. Fork Mode: Deploy (Supported): we pass in the real OSx contracts and deploy via the factory
    /// 3. Fork Mode: Existing (Supported): we don't deploy via the factory, we use the existing contract for everything
    function setUp() public {
        // deploy the deploy script
        DeployGauges deploy = new DeployGauges();

        // fetch the deployment parameters
        DeploymentParameters memory deploymentParameters = deploy.getDeploymentParameters(
            vm.envOr("DEPLOY_AS_PRODUCTION", false)
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
        else if (_getTestMode() == TestMode.ForkDeploy) {
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
            address factoryAddress = vm.envOr("FACTORY_ADDRESS", address(0));
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
    /// alice will have 2 locks, holding both at the same time
    /// bob will have 1 lock minted at the same time as user 1 holds both
    /// alice will mint his lock for him
    /// carol will have 1 lock minted after user 1 has exited one of their locks
    /// carol will have a smart contract wallet
    /// we will have them create the lock, vote across a couple epochs, and then exit
    /// we will also have them attempt to circumvent the system and fail
    /// finally we will define one attacker who will attempt to attack the system and fail

    uint balanceAlice = 1000 ether;
    uint balanceBob = 0 ether;
    uint balanceCarol = 1_234 ether;

    uint depositAlice0 = 250 ether;
    uint depositAlice1 = 500 ether;
    uint depositAliceBob = 250 ether;

    // 1 attacker (david)

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

        // first we give the guys each some tokens of the underlying
        {
            vm.startPrank(distributor);
            {
                token.transfer(alice, balanceAlice);
                token.transfer(carol, balanceCarol);
            }
            vm.stopPrank();
        }

        // alice goes first and makes the first deposit, it's at the start of the
        // week, so we would expect him to be warm by the end of the week if using <6 day
        // we wait a couple of days and he makes a deposit for bob
        // we expect his warmup to carryover to the next week
        // we expect both of their locks to start accruing voting power on the same day
        {
            goToEpochStartPlus(1 days);

            vm.startPrank(alice);
            {
                token.approve(address(escrow), balanceAlice);

                escrow.createLock(depositAlice0);

                goToEpochStartPlus(6 days);

                escrow.createLockFor(depositAliceBob, bob);
            }
            vm.stopPrank();

            // check alice has token 1, bob has token   2
            assertEq(lock.ownerOf(1), alice, "Alice should own token 1");
            assertEq(lock.ownerOf(2), bob, "Bob should own token 2");

            // check the token points written
            TokenPoint memory tp1_1 = curve.tokenPointHistory(1, 1);
            TokenPoint memory tp2_1 = curve.tokenPointHistory(2, 1);

            assertEq(tp1_1.bias, depositAlice0, "Alice point 1 should have the correct bias");
            assertEq(tp2_1.bias, depositAliceBob, "Bob point should have the correct bias");

            assertEq(
                tp1_1.checkpointTs,
                epochStartTime + clock.checkpointInterval(),
                "Alice point should have the correct checkpoint"
            );
            assertEq(
                tp2_1.checkpointTs,
                epochStartTime + clock.checkpointInterval(),
                "Bob point should have the correct checkpoint"
            );

            assertEq(
                tp1_1.writtenTs,
                epochStartTime + 1 days,
                "Alice point should have the correct written timestamp"
            );
            assertEq(
                tp2_1.writtenTs,
                epochStartTime + 6 days,
                "Bob point should have the correct written timestamp"
            );

            // check the contract has the correct total
            assertEq(
                escrow.totalLocked(),
                depositAlice0 + depositAliceBob,
                "Total locked should be the sum of the two deposits"
            );

            // checked the locked balances and the token points
            assertEq(
                escrow.locked(1).amount,
                depositAlice0,
                "Alice should have the correct amount locked"
            );
            assertEq(
                escrow.locked(2).amount,
                depositAliceBob,
                "Bob should have the correct amount locked"
            );

            // start date in the future - alice will not be warm as his lock is not active yet
            assertFalse(curve.isWarm(1), "Alice should not be warm");
            assertFalse(curve.isWarm(2), "Bob should not be warm");

            assertEq(escrow.votingPower(1), 0, "Alice should have no voting power");
            assertEq(escrow.votingPower(2), 0, "Bob should have no voting power");

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

            // fast forward to the checkpoint interval alice is warm and has voting power, bob is not
            goToEpochStartPlus(clock.checkpointInterval());

            assertEq(escrow.votingPower(1), depositAlice0, "Alice should have voting power");
            assertTrue(curve.isWarm(1), "Alice should not be warm");

            assertEq(escrow.votingPower(2), 0, "Bob should not have the correct voting power");
            assertFalse(curve.isWarm(2), "Bob should not be warm");
        }

        // we fast forward 4 weeks and check the expected balances
        {
            goToEpochStartPlus(4 weeks);

            // Generalising this is a bit hard...
            // we could check a < x < b, but checking x exactly is tedious
        }

        // we have alice make a second deposit and validate that his total voting power is initially unchanged
        {
            vm.startPrank(alice);
            {
                escrow.createLock(depositAlice1);
            }
            vm.stopPrank();

            // check the token points written
            TokenPoint memory tp1_2 = curve.tokenPointHistory(3, 1);

            assertEq(tp1_2.bias, depositAlice1, "Alice point 2 should have the correct bias");
            assertEq(
                tp1_2.checkpointTs,
                epochStartTime + 4 weeks + clock.checkpointInterval(),
                "Alice point should have the correct checkpoint"
            );
            assertEq(
                tp1_2.writtenTs,
                epochStartTime + 4 weeks,
                "Alice point should have the correct written timestamp"
            );

            // check the voting power is unchanged (my boi aint warm)
            assertEq(
                escrow.votingPower(3),
                0,
                "Alice should have no voting power on the second lock"
            );
            assertFalse(curve.isWarm(3), "Alice should not be warm on the second lock");

            // check the total voting power on the escrow
            assertEq(
                escrow.totalLocked(),
                depositAlice0 + depositAlice1 + depositAliceBob,
                "Total locked should be the sum of the two deposits"
            );

            // calculate elapsed time since we made the first lock
            uint timeElapsedSinceFirstLock = block.timestamp -
                curve.tokenPointHistory(1, 1).checkpointTs;

            assertEq(
                escrow.votingPowerForAccount(alice),
                curve.getBias(timeElapsedSinceFirstLock, depositAlice0),
                "Alice should only have the first lock active"
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
                escrow.votingPowerForAccount(alice),
                curve.getBias(timeElapsedSinceFirstLock, depositAlice0) + depositAlice1,
                "Alice should now have the correct aggregate voting power"
            );
        }

        // david tries to enter the queue with one of their locks
        {
            vm.startPrank(david);
            {
                bytes memory erc721ownererr = "ERC721: caller is not token owner or approved";
                for (uint i = 1; i <= 3; i++) {
                    vm.expectRevert(OnlyEscrow.selector);
                    queue.queueExit(i, david);

                    vm.expectRevert(erc721ownererr);
                    escrow.beginWithdrawal(i);
                }
            }
            vm.stopPrank();
        }

        // the guys try to vote but it's paused
        {
            assertFalse(clock.votingActive(), "Voting should not be active");

            address[3] memory stakers = [alice, bob, carol];
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

            vm.startPrank(alice);
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

            // david tries voting for someone else and fails
            {
                GaugeVote[] memory votes = new GaugeVote[](2);
                votes[0] = GaugeVote({gauge: gauge0, weight: 1});
                votes[1] = GaugeVote({gauge: gauge1, weight: 1});

                vm.startPrank(david);
                {
                    vm.expectRevert(NotApprovedOrOwner.selector);
                    voter.vote(1, votes);

                    // what about a non-existent id
                    vm.expectRevert("ERC721: invalid token ID");
                    voter.vote(123, votes);
                }
                vm.stopPrank();
            }

            // the boys vote: alice votes with multiple and carol with a single
            {
                GaugeVote[] memory votes = new GaugeVote[](2);

                // alice is 50 50
                votes[0] = GaugeVote({gauge: gauge0, weight: 1});
                votes[1] = GaugeVote({gauge: gauge1, weight: 1});
                uint[] memory ids = new uint[](2);
                ids[0] = 1;
                ids[1] = 3;

                vm.startPrank(alice);
                {
                    voter.voteMultiple(ids, votes);
                }
                vm.stopPrank();

                // bob votes for the one gauge
                votes = new GaugeVote[](1);
                votes[0] = GaugeVote({gauge: gauge0, weight: 1});

                vm.startPrank(bob);
                {
                    voter.vote(2, votes);
                }
                vm.stopPrank();

                // check the votes - we should have all of bob's votes (id 2) for gauge 0
                // alice' votes should be split between the two gauges
                // in total the second gauge should have 50% of the votes of alice' votes
                // and the first 100% of bob's votes + 50% of alice' votes
                assertEq(
                    voter.votes(1, gauge0),
                    escrow.votingPower(1) / 2,
                    "Alice 1 g 0 should have the correct votes"
                );
                assertEq(
                    voter.votes(1, gauge1),
                    escrow.votingPower(1) / 2,
                    "Alice 1 g 1 should have the correct votes"
                );
                assertEq(
                    voter.votes(2, gauge0),
                    escrow.votingPower(2),
                    "Bob should have the correct votes"
                );
                assertEq(
                    voter.votes(3, gauge0),
                    escrow.votingPower(3) / 2,
                    "Alice 3 g 0 should have the correct votes"
                );
                assertEq(
                    voter.votes(3, gauge1),
                    escrow.votingPower(3) / 2,
                    "Alice 3 g 1 should have the correct votes"
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

        // carol create a deposit mid vote and tries to vote - he should have no voting power
        {
            vm.startPrank(carol);
            {
                token.approve(address(escrow), balanceCarol);

                // bad contract first
                GhettoMultisig badMultisig = new GhettoMultisig();

                vm.expectRevert("ERC721: transfer to non ERC721Receiver implementer");
                escrow.createLockFor(balanceCarol, address(badMultisig));

                // he fixes it
                carolsMultisig = new MultisigReceiver();

                escrow.createLockFor(balanceCarol, address(carolsMultisig));

                // allow carol to vote on behalf of his msig
                carolsMultisig.approveCallerToSpendTokenWithID(address(lock), 4);

                GaugeVote[] memory votes = new GaugeVote[](2);
                votes[0] = GaugeVote({gauge: gauge0, weight: 1});
                votes[1] = GaugeVote({gauge: gauge1, weight: 1});

                vm.expectRevert(NoVotingPower.selector);
                voter.vote(4, votes);
            }
            vm.stopPrank();
        }

        // bob updates his vote
        {
            GaugeVote[] memory votes = new GaugeVote[](1);
            votes[0] = GaugeVote({gauge: gauge1, weight: 1});

            vm.startPrank(bob);
            {
                voter.vote(2, votes);
            }
            vm.stopPrank();

            // check the votes - we should have all of bob's votes (id 2) for gauge 1
            // alice' votes should be split between the two gauges
            // in total the second gauge should have 100% of Bob's votes + 50% of the votes of alice' votes
            // and the first 50% of alice' votes
            assertEq(
                voter.votes(1, gauge0),
                escrow.votingPower(1) / 2,
                "Alice 1 g 0 should have the correct votes"
            );

            assertEq(
                voter.votes(1, gauge1),
                escrow.votingPower(1) / 2,
                "Alice 1 g 1 should have the correct votes"
            );

            assertEq(voter.votes(2, gauge0), 0, "Bob should have the correct votes");

            assertEq(
                voter.votes(2, gauge1),
                escrow.votingPower(2),
                "Bob should have the correct votes"
            );

            assertEq(
                voter.votes(3, gauge0),
                escrow.votingPower(3) / 2,
                "Alice 3 g 0 should have the correct votes"
            );

            assertEq(
                voter.votes(3, gauge1),
                escrow.votingPower(3) / 2,
                "Alice 3 g 1 should have the correct votes"
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

            // alice tries to exit
            vm.startPrank(alice);
            {
                vm.expectRevert(VotingInactive.selector);
                escrow.resetVotesAndBeginWithdrawal(1);

                vm.expectRevert(CannotExit.selector);
                escrow.beginWithdrawal(1);
            }
            vm.stopPrank();
        }

        // we wait till voting is over and they begin the exit - alice does anyhow
        // we check he can't exit early and someone can't exit for him
        {
            goToEpochStartPlus(8 weeks + 1 hours);

            vm.startPrank(alice);
            {
                lock.approve(address(escrow), 1);
                escrow.resetVotesAndBeginWithdrawal(1);
            }
            vm.stopPrank();

            // alice doesnt have the nft - its in the queue but he has a ticket
            assertEq(lock.ownerOf(1), address(escrow), "Alice should not own the nft");
            assertEq(queue.queue(1).holder, alice, "Alice should be in the queue");

            // exit date should be the next checkpoint
            assertEq(
                queue.queue(1).exitDate,
                epochStartTime + 8 weeks + clock.checkpointInterval(),
                "Alice should be able to exit at the next checkpoint"
            );

            // second user point wrttien
            TokenPoint memory tp1_2 = curve.tokenPointHistory(1, 2);

            assertEq(tp1_2.bias, 0, "Alice point 1_2 should have the correct bias");
            assertEq(
                tp1_2.checkpointTs,
                epochStartTime + 8 weeks + clock.checkpointInterval(),
                "Alice point should have the correct checkpoint"
            );
            assertEq(
                tp1_2.writtenTs,
                epochStartTime + 8 weeks + 1 hours,
                "Alice point should have the correct written timestamp"
            );

            // he can't exit early
            vm.startPrank(alice);
            {
                vm.expectRevert(CannotExit.selector);
                escrow.withdraw(1);

                // he waits till the end of the week to exit
                goToEpochStartPlus(9 weeks);

                // can't exit yet
                vm.expectRevert(CannotExit.selector);
                escrow.withdraw(1);

                // + 1s he can

                goToEpochStartPlus(9 weeks + 1);

                escrow.withdraw(1);
            }
            vm.stopPrank();

            // he should have his original amount back, minus any fees
            assertEq(
                token.balanceOf(alice),
                depositAlice0 - (queue.feePercent() * depositAlice0) / 10_000,
                "Alice should have the correct balance after exiting"
            );

            // check the total locked
            assertEq(
                escrow.totalLocked(),
                depositAlice1 + depositAliceBob + balanceCarol,
                "Total locked should be the sum of the two deposits"
            );
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

        // alice creates a new lock 12 h the window opens, he should be warm tomorrow
        {
            goToEpochStartPlus(10 weeks - 12 hours);

            vm.startPrank(alice);
            {
                token.approve(address(escrow), depositAlice0);
                escrow.createLock(depositAlice0);
            }
            vm.stopPrank();

            // nope
            goToEpochStartPlus(10 weeks + 12 hours);
            assertFalse(curve.isWarm(5), "Alice should not be warm");

            // +1s
            goToEpochStartPlus(10 weeks + 12 hours + 1);
            assertTrue(curve.isWarm(5), "Alice should be warm");
        }

        // bob goes for an exit, he should be able to exit in a week
        {
            goToEpochStartPlus(10 weeks + 3 days);

            vm.startPrank(bob);
            {
                voter.reset(2);
                lock.approve(address(escrow), 2);
                escrow.beginWithdrawal(2);
            }
            vm.stopPrank();

            // bob doesnt have the nft - its in the queue but he has a ticket
            assertEq(lock.ownerOf(2), address(escrow), "Bob should not own the nft");
            assertEq(queue.queue(2).holder, bob, "Bob should be in the queue");

            // exit date should be 1 week from now
            assertEq(
                queue.queue(2).exitDate,
                epochStartTime + 11 weeks + 3 days,
                "Bob should be able to exit in a week"
            );

            // go there + 1 and exit
            goToEpochStartPlus(11 weeks + 3 days + 1);

            vm.startPrank(bob);
            {
                escrow.withdraw(2);
            }
            vm.stopPrank();

            // total locked should be alice' 2 deposits + carols
            assertEq(
                escrow.totalLocked(),
                depositAlice0 + depositAlice1 + balanceCarol,
                "Total locked should be the sum of the deposits"
            );
        }

        // carol tries to send his nft to the lock and queue, and can't but he accidentally sends it to the escrow
        {
            vm.startPrank(carol);
            {
                vm.expectRevert(NotWhitelisted.selector);
                lock.transferFrom(carol, address(queue), 4);

                vm.expectRevert(NotWhitelisted.selector);
                lock.transferFrom(carol, address(lock), 4);

                // he sends it to the escrow
                lock.transferFrom(address(carolsMultisig), address(escrow), 4);
            }
            vm.stopPrank();

            assertEq(lock.ownerOf(4), address(escrow), "Carol should not own the nft");

            // he can't get it back now :(
            vm.startPrank(carol);
            {
                vm.expectRevert("ERC721: caller is not token owner or approved");
                lock.transferFrom(address(escrow), carol, 4);
            }
            vm.stopPrank();
        }

        // we recover it from him
        {
            IDAO.Action[] memory actions = new IDAO.Action[](3);
            actions[0] = IDAO.Action({
                to: address(lock),
                value: 0,
                data: abi.encodeWithSelector(lock.setWhitelisted.selector, address(carol), true)
            });
            actions[1] = IDAO.Action({
                to: address(escrow),
                value: 0,
                data: abi.encodeWithSelector(escrow.sweepNFT.selector, 4, carol)
            });
            actions[2] = IDAO.Action({
                to: address(lock),
                value: 0,
                data: abi.encodeWithSelector(lock.setWhitelisted.selector, address(carol), false)
            });

            _buildSignProposal(actions);

            // check he has it
            assertEq(lock.ownerOf(4), carol, "Carol should own the nft");
        }

        // david convinces the dev team to give him sweeper access and tries to rug all the tokens, he cant
        {
            IDAO.Action[] memory actions = new IDAO.Action[](1);
            actions[0] = IDAO.Action({
                to: address(dao),
                value: 0,
                data: abi.encodeCall(dao.grant, (address(escrow), david, escrow.SWEEPER_ROLE()))
            });
            _buildSignProposal(actions);

            vm.prank(distributor);
            token.transfer(david, 100 ether);

            vm.startPrank(david);
            {
                vm.expectRevert(NothingToSweep.selector);
                escrow.sweep();

                // however he sends some of his own tokens and can get those out
                token.transfer(address(escrow), 100 ether);

                assertEq(token.balanceOf(david), 0, "David should have no tokens");

                escrow.sweep();

                assertEq(token.balanceOf(david), 100 ether, "David should have his tokens");
            }
            vm.stopPrank();
        }

        // we get all the guys to exit and unwind their positions
        {
            // warp to a voting window
            goToEpochStartPlus(12 weeks + 2 hours);

            vm.startPrank(alice);
            {
                lock.approve(address(escrow), 3);
                lock.approve(address(escrow), 5);

                escrow.resetVotesAndBeginWithdrawal(3);
                escrow.beginWithdrawal(5);
            }
            vm.stopPrank();

            vm.startPrank(carol);
            {
                lock.approve(address(escrow), 4);
                escrow.beginWithdrawal(4);
            }
            vm.stopPrank();

            // fast forward like 5 weeks
            goToEpochStartPlus(16 weeks);

            // alice exits
            vm.startPrank(alice);
            {
                escrow.withdraw(3);
                escrow.withdraw(5);
            }
            vm.stopPrank();

            // carol exits
            vm.startPrank(carol);
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
        // FORK_TEST_MODE is defined on the Makefile, depending on the target
        string memory mode = vm.envOr("FORK_TEST_MODE", string("fork-deploy"));
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
    function _resolveMintTokens() internal returns (bool) {
        // if deploying a mock, mint will be open
        try token.mint(address(distributor), 3_000 ether) {
            return true;
        } catch {}

        // next we just try a good old fashioned find a whale and rug them in the test
        address whale = vm.envOr("TEST_TOKEN_WHALE", address(0));
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
