pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

// aragon contracts
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
import {MockDAOFactory} from "@mocks/osx/MockDAOFactory.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

import "./helpers/OSxHelpers.sol";

import {Clock} from "@clock/Clock.sol";
import {IEscrowCurveTokenStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {IWithdrawalQueueErrors} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {IGaugeVote} from "src/voting/ISimpleGaugeVoter.sol";
import {VotingEscrow, Lock, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, ISimpleGaugeVoterSetupParams} from "src/voting/SimpleGaugeVoterSetup.sol";

import {Deploy, DeploymentParameters, GaugesDaoFactory} from "script/Deploy.s.sol";

/**
 * This is an enhanced e2e test that aims to do the following:
 * 1. Use factory contract to deploy identically to production
 * 2. Setup a test harness for connecting to either fork or local node
 * 3. A more robust suite of lifecylce tests for multiple users entering and exiting
 * 4. A more robust suite for admininstration of the contracts
 */
contract TestE2EV2 is Test, IWithdrawalQueueErrors, IGaugeVote, IEscrowCurveTokenStorage {
    GaugesDaoFactory factory;

    enum TestMode {
        Local,
        Fork
    }

    /*///////////////////////////////////////////////////////////////
                                Setup
    //////////////////////////////////////////////////////////////*/

    /// The test here will run in 2 modes:
    /// 1. Local Mode (Not yet supported): we deploy the OSx contracts locally using mocks to expedite testing
    /// 2. Fork Mode (Supported): we pass in the real contracts and test against a forked network
    function setUp() public {
        // deploy the deploy script
        Deploy deploy = new Deploy();

        // fetch the deployment parameters
        DeploymentParameters memory deploymentParameters = deploy.getDeploymentParameters(
            vm.envBool("DEPLOY_AS_PRODUCTION")
        );

        // any env modifications you need to make to the deployment parameters
        // can be done here
        if (_getTestMode() == TestMode.Local) {
            revert("Local mode not supported yet");
            // setup OSx mocks
            // write the addresses
        }

        // random ens domain
        deploymentParameters.voterEnsSubdomain = _hToS(
            keccak256(abi.encodePacked("gauges", block.timestamp))
        );

        // deploy the factory
        factory = new GaugesDaoFactory(deploymentParameters);
    }

    /*///////////////////////////////////////////////////////////////
                              Tests
    //////////////////////////////////////////////////////////////*/

    function testCanDeploy() public {
        factory.deployOnce();
    }

    /*///////////////////////////////////////////////////////////////
                              Utils
    //////////////////////////////////////////////////////////////*/

    function _getTestMode() public view returns (TestMode) {
        string memory mode = vm.envString("TEST_MODE");
        if (keccak256(abi.encodePacked(mode)) == keccak256(abi.encodePacked("fork"))) {
            return TestMode.Fork;
        } else if (keccak256(abi.encodePacked(mode)) == keccak256(abi.encodePacked("local"))) {
            return TestMode.Local;
        } else {
            revert("Invalid test mode");
        }
    }

    function _hToS(bytes32 _hash) public pure returns (string memory) {
        bytes memory hexString = new bytes(64);
        bytes memory alphabet = "0123456789abcdef";

        for (uint256 i = 0; i < 32; i++) {
            hexString[i * 2] = alphabet[uint8(_hash[i] >> 4)];
            hexString[1 + i * 2] = alphabet[uint8(_hash[i] & 0x0f)];
        }

        return string(hexString);
    }
}
