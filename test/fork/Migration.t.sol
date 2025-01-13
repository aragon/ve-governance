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

/**
 * Test the upgrade of the migration contracts and the move to the new contracts
 * We do the following steps: 
  1. Deploy the new contracts 
  2. Deploy upgraded implementations to the voting and staking contracts 
  3. Pause the new staking contract 
  4. upgrade the old contracts
  4. Add the old staking contract as the migration target 
  5. Enable the migration 

  6. Grab all the mode stakers and run a test to see that they can migrate. 
  7. for those in the exit queue, ensure they can still exit


 */
contract TestMigrate is AragonTest {
    GaugesDaoFactory srcFactory;
    GaugePluginSet src;

    Multisig srcMultisig;
    DAO srcDAO;

    GaugesDaoFactory dstFactory;
    GaugePluginSet dst;

    Multisig dstMultisig;
    DAO dstDAO;

    DeployGauges deploy;
    address[] signers;

    address[] stakers;

    enum ModeOrBPT {
        MODE,
        BPT
    }

    uint8 constant modeOrBPT = uint8(ModeOrBPT.BPT);

    function setUp() public {
        deploy = new DeployGauges();

        signers = deploy.readMultisigMembers();

        _fetchOldDeploy();
        _deployNew();
        vm.roll(block.number + 1);
        _upgradeSrcContracts();
        _enableMigrationDst();
        _enableMigrationSrc();
        _loadStakers();
    }

    /// Tests

    function testMigrate() public {
        // warp a few days to allow warmups
        vm.warp(block.timestamp + 1 weeks);
        {
            uint totalLocked = src.votingEscrow.totalLocked();
            uint balance = IERC20(src.votingEscrow.token()).balanceOf(address(src.votingEscrow));
            console.log("[PRE] Total Locked: %s, Balance: %s", totalLocked, balance);
        }

        for (uint256 i = 0; i < stakers.length; i++) {
            uint totalLockedPre = src.votingEscrow.totalLocked();
            address staker = stakers[i];
            // get the tokens of the staker
            uint[] memory veNFTs = src.votingEscrow.ownedTokens(staker);

            // get the balance locked in the contract
            uint totalLockedStakerPre;
            uint totalLockedStakerPost;
            uint totalNotMigrated;
            for (uint j = 0; j < veNFTs.length; j++) {
                uint tokenId = veNFTs[j];
                totalLockedStakerPre += src.votingEscrow.locked(tokenId).amount;
                // migrate the token
                vm.startPrank(staker);
                {
                    src.nftLock.approve(address(src.votingEscrow), tokenId);
                    try src.votingEscrow.migrateFrom(tokenId) returns (uint newTokenId) {
                        totalLockedStakerPost += dst.votingEscrow.locked(newTokenId).amount;
                    } catch {
                        console.log(
                            "Migration failed for staker: %s with tokenId %s",
                            _hToS(staker),
                            tokenId
                        );
                        totalNotMigrated += src.votingEscrow.locked(tokenId).amount;
                    }
                }
                vm.stopPrank();
            }

            if (totalLockedStakerPre == 0) {
                console.log("Staker: %s, no tokens to migrate", _hToS(staker));
            } else
                console.log(
                    "Staker: %s, Total Locked Before: %s, Total locked After: %s",
                    staker,
                    totalLockedStakerPre,
                    totalLockedStakerPost
                );

            assertEq(totalLockedStakerPre, totalLockedStakerPost + totalNotMigrated, _hToS(staker));
            if (totalNotMigrated > 0) console.log("Total Not Migrated: %s", totalNotMigrated);
        }
        {
            uint totalLocked = src.votingEscrow.totalLocked();
            uint balance = IERC20(src.votingEscrow.token()).balanceOf(address(src.votingEscrow));
            uint totalLockeddst = dst.votingEscrow.totalLocked();
            uint balancedst = IERC20(src.votingEscrow.token()).balanceOf(address(dst.votingEscrow));
            console.log("[POST:src] Total Locked: %s, Balance: %s", totalLocked, balance);
            console.log("[POST:dst] Total Locked: %s, Balance: %s", totalLockeddst, balancedst);
        }
    }

    // fetch the most recent deploy
    function _fetchOldDeploy() internal {
        DeploymentParameters memory deploymentParameters = deploy.getDeploymentParameters(false);

        address factoryAddress = vm.envOr("FACTORY_ADDRESS", address(0));
        if (factoryAddress == address(0)) {
            revert("Factory address not set");
        }
        srcFactory = GaugesDaoFactory(factoryAddress);

        Deployment memory deployment = srcFactory.getDeployment();
        src = deployment.gaugeVoterPluginSets[modeOrBPT];
        srcMultisig = deployment.multisigPlugin;
        srcDAO = deployment.dao;
    }

    function _deployNew() internal {
        DeploymentParameters memory deploymentParameters = deploy.getDeploymentParameters(false);

        deploymentParameters.voterEnsSubdomain = _hToS(
            keccak256(abi.encodePacked("gauges", block.timestamp))
        );

        // deploy the factory
        dstFactory = new GaugesDaoFactory(deploymentParameters);
        dstFactory.deployOnce();

        Deployment memory deployment = dstFactory.getDeployment();
        dst = deployment.gaugeVoterPluginSets[modeOrBPT];

        dstMultisig = deployment.multisigPlugin;
        dstDAO = deployment.dao;
    }

    // create the multisig transaction to upgrade the voter and escrow
    function _upgradeSrcContracts() public {
        // fetch the implementation contracts for the voter and escrow in the new deploy
        address voterImpl = SimpleGaugeVoter(address(dst.plugin)).implementation();
        address escrowImpl = VotingEscrow(address(dst.votingEscrow)).implementation();

        // first we need to upgrade both contracts
        IDAO.Action[] memory actions = new IDAO.Action[](2);
        actions[0] = IDAO.Action({
            to: address(src.plugin),
            value: 0,
            data: abi.encodeCall(src.plugin.upgradeTo, (voterImpl))
        });

        actions[1] = IDAO.Action({
            to: address(src.votingEscrow),
            value: 0,
            data: abi.encodeCall(src.votingEscrow.upgradeTo, (escrowImpl))
        });

        _buildSignProposal(actions, srcMultisig);
    }

    function _enableMigrationDst() public {
        // on the destination:
        IDAO.Action[] memory actions = new IDAO.Action[](2);
        // pause the dst staking contract
        actions[0] = IDAO.Action({
            to: address(dst.votingEscrow),
            value: 0,
            data: abi.encodeCall(dst.votingEscrow.pause, ())
        });

        // grant the migrator role on the prev staking contract
        actions[1] = IDAO.Action({
            to: address(dstDAO),
            value: 0,
            data: abi.encodeCall(
                dstDAO.grant,
                (
                    address(dst.votingEscrow),
                    address(src.votingEscrow),
                    dst.votingEscrow.MIGRATOR_ROLE()
                )
            )
        });

        _buildSignProposal(actions, dstMultisig);
    }

    function _enableMigrationSrc() public {
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        // pause the dst staking contract
        actions[0] = IDAO.Action({
            to: address(src.votingEscrow),
            value: 0,
            data: abi.encodeCall(src.votingEscrow.enableMigration, (address(dst.votingEscrow)))
        });

        _buildSignProposal(actions, srcMultisig);
    }

    function _loadStakers() internal {
        // Load the JSON file as a string
        string memory json = vm.readFile("./test/fork/stakers.json");

        // Parse the JSON into an array of Staker structs
        bytes memory data = vm.parseJson(json, ""); // Assuming root of JSON
        stakers = abi.decode(data, (address[]));
    }

    /// Utils
    function _hToS(address _addr) internal pure returns (string memory) {
        return _hToS(bytes32(uint256(uint160(_addr))));
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
        IDAO.Action[] memory actions,
        Multisig multisig
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

    function _signExecuteMultisigProposal(uint256 _proposalId, Multisig multisig) internal {
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
        IDAO.Action[] memory actions,
        Multisig multisig
    ) internal returns (uint256 proposalId) {
        proposalId = _buildMsigProposal(actions, multisig);
        _signExecuteMultisigProposal(proposalId, multisig);
        return proposalId;
    }
}
