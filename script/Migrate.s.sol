// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {DAO, IDAO} from "@aragon/osx/core/dao/DAO.sol";
import {GaugesDaoFactory, DeploymentParameters, Deployment, TokenParameters} from "../src/factory/GaugesDaoFactory.sol";
import {Multisig, MultisigSetup as MultisigPluginSetup} from "@aragon/osx/plugins/governance/multisig/MultisigSetup.sol";
import {Clock, Lock, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, ISimpleGaugeVoterSetupParams} from "src/voting/SimpleGaugeVoterSetup.sol";
import {VotingEscrowV1_1_0 as VotingEscrow} from "src/escrow/increasing/VotingEscrowIncreasing_v1_1_0.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {MockERC20} from "@mocks/MockERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {GaugesDaoFactory, GaugePluginSet, Deployment} from "src/factory/GaugesDaoFactory.sol";
import {DeployGauges, DeploymentParameters} from "script/DeployGauges.s.sol";

contract Migrate is Script {
    GaugesDaoFactory srcFactory;
    GaugePluginSet srcMode;
    GaugePluginSet srcBPT;

    address srcFactoryAddress = address(0x123);
    address dstFactoryAddress = address(0x456);

    Multisig srcMultisig;
    DAO srcDAO;

    GaugesDaoFactory dstFactory;
    GaugePluginSet dstMode;
    GaugePluginSet dstBPT;

    Multisig dstMultisig;
    DAO dstDAO;

    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("Deploying from:", vm.addr(privKey));

        _;

        vm.stopBroadcast();
    }

    function run() public broadcast {
        // 1. get the old and the new factory
        srcFactory = GaugesDaoFactory(srcFactoryAddress);
        Deployment memory srcDeployment = srcFactory.getDeployment();
        srcMode = srcDeployment.gaugeVoterPluginSets[0];
        srcBPT = srcDeployment.gaugeVoterPluginSets[1];
        srcMultisig = srcDeployment.multisigPlugin;
        srcDAO = srcDeployment.dao;

        dstFactory = GaugesDaoFactory(dstFactoryAddress);
        Deployment memory dstDeployment = dstFactory.getDeployment();
        dstMode = dstDeployment.gaugeVoterPluginSets[0];
        dstBPT = dstDeployment.gaugeVoterPluginSets[1];
        dstMultisig = dstDeployment.multisigPlugin;
        dstDAO = dstDeployment.dao;

        GaugePluginSet[] memory srcGaugePluginSets = new GaugePluginSet[](2);
        srcGaugePluginSets[0] = srcMode;
        srcGaugePluginSets[1] = srcBPT;

        GaugePluginSet[] memory dstGaugePluginSets = new GaugePluginSet[](2);
        dstGaugePluginSets[0] = dstMode;
        dstGaugePluginSets[1] = dstBPT;

        for (uint i = 0; i < srcGaugePluginSets.length; i++) {
            GaugePluginSet memory srcGaugePluginSet = srcGaugePluginSets[i];
            GaugePluginSet memory dstGaugePluginSet = dstGaugePluginSets[i];
            _upgradeSrcContracts(srcGaugePluginSet, dstGaugePluginSet);
            _enableMigrationDst(srcGaugePluginSet, dstGaugePluginSet);
            _enableMigrationSrc(srcGaugePluginSet, dstGaugePluginSet);
        }
    }

    // upgrade src
    function _upgradeSrcContracts(GaugePluginSet memory src, GaugePluginSet memory dst) public {
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

    function _enableMigrationDst(GaugePluginSet memory src, GaugePluginSet memory dst) public {
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
                    VotingEscrow(address(dst.votingEscrow)).MIGRATOR_ROLE()
                )
            )
        });

        _buildSignProposal(actions, dstMultisig);
    }

    function _enableMigrationSrc(GaugePluginSet memory src, GaugePluginSet memory dst) public {
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        // pause the dst staking contract
        actions[0] = IDAO.Action({
            to: address(src.votingEscrow),
            value: 0,
            data: abi.encodeCall(
                VotingEscrow(address(src.votingEscrow)).enableMigration,
                (address(dst.votingEscrow))
            )
        });

        _buildSignProposal(actions, srcMultisig);
    }

    function _buildSignProposal(
        IDAO.Action[] memory actions,
        Multisig multisig
    ) internal returns (uint256 proposalId) {
        // prank the first signer who will create stuff
        proposalId = multisig.createProposal({
            _metadata: "",
            _actions: actions,
            _allowFailureMap: 0,
            _approveProposal: true,
            _tryExecution: true,
            _startDate: 0,
            _endDate: uint64(block.timestamp) + 3 days
        });

        return proposalId;
    }
    // enable src
}
