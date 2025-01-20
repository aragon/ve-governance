// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {Multisig} from "@aragon/multisig/Multisig.sol";
import {VotingEscrow, Lock, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, ISimpleGaugeVoterSetupParams} from "src/voting/SimpleGaugeVoterSetup.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {GaugesDaoFactory, GaugePluginSet, DeploymentParameters, Deployment, TokenParameters, DAO} from "src/factory/GaugesDaoFactory.sol";

uint256 constant PROPOSAL_ID = 44; // pinned to block 18336106
contract TestUpgradeToV110 is Test {
    GaugesDaoFactory factory;
    GaugePluginSet modePluginSet;
    GaugePluginSet bptPluginSet;

    /// @dev Mode multisig executing via the dao
    Multisig modeMultisig;

    /// @dev Mode dao owning the contracts
    DAO modeDAO;

    /// @dev Aragon signer multisig on the mode multisig
    Multisig aragonMultisig = Multisig(address(0x4315B4D2C707981f7fA51DBE91079Ea8c44e2e95));

    Lock lockMode;
    Lock lockBPT;
    SimpleGaugeVoter voterMode;
    SimpleGaugeVoter voterBPT;

    address[] aragonSigners;
    address[] modeSigners;

    function setAragonSigners() internal {
        aragonSigners.push(address(0x946138B088524414EEDaf0699BA10d7Fb5673A34));
        aragonSigners.push(address(0xbd3eE47A1576F26454C65B96b7AbfaF8Ee9cB4a1));
        aragonSigners.push(address(0x3ffe3F16d47A54b1C6A3f47c9E6Ff5C2C1B32859));
        aragonSigners.push(address(0x9395e6b95afFee7d7b2b107127Fcc9e4167A336f));
    }

    function setModeSigners() internal {
        address[] memory signers = readMultisigMembers();
        for (uint256 i = 0; i < signers.length; i++) {
            modeSigners.push(signers[i]);
        }
    }

    function readMultisigMembers() public view returns (address[] memory result) {
        // JSON list of members
        string memory membersFilePath = vm.envString("MULTISIG_MEMBERS_JSON_FILE_NAME");
        string memory path = string.concat(vm.projectRoot(), membersFilePath);
        string memory strJson = vm.readFile(path);

        bool exists = vm.keyExistsJson(strJson, "$.members");
        if (!exists) revert("EmptyMultisig()");

        result = vm.parseJsonAddressArray(strJson, "$.members");

        if (result.length == 0) revert("EmptyMultisig()");
    }

    function _retrieveDeployment(address _factoryAddress) internal {
        factory = GaugesDaoFactory(_factoryAddress);
        Deployment memory deployment = factory.getDeployment();
        modePluginSet = deployment.gaugeVoterPluginSets[0];
        bptPluginSet = deployment.gaugeVoterPluginSets[1];
        modeMultisig = deployment.multisigPlugin;
        modeDAO = deployment.dao;

        // bind the voter and lock contracts
        lockMode = modePluginSet.nftLock;
        lockBPT = bptPluginSet.nftLock;

        voterMode = modePluginSet.plugin;
        voterBPT = bptPluginSet.plugin;
    }

    function testUpgrade() public {
        setModeSigners();

        _retrieveDeployment(vm.envAddress("FACTORY_ADDRESS"));

        // save the old impls
        address lockImplOld = lockMode.implementation();
        address voterImplOld = voterMode.implementation();
        address lockBPTImplOld = lockBPT.implementation();
        address voterBPTImplOld = voterBPT.implementation();

        // check the uri is not currently there and reverts if we call
        vm.startPrank(address(modeDAO));
        {
            try lockMode.setBaseURI("should revert") {
                revert("should revert");
            } catch {}

            try lockBPT.setBaseURI("should revert") {
                revert("should revert");
            } catch {}
        }
        vm.stopPrank();

        uint proposalId = createUpgradeProposal();

        _signExecuteMultisigProposal(proposalId, modeSigners, modeMultisig);

        // test
        address lockImplNew = lockMode.implementation();
        address voterImplNew = voterMode.implementation();
        address lockBPTImplNew = lockBPT.implementation();
        address voterBPTImplNew = voterBPT.implementation();

        assertNotEq(lockImplOld, lockImplNew);
        assertNotEq(voterImplOld, voterImplNew);
        assertNotEq(lockBPTImplOld, lockImplNew);
        assertNotEq(voterBPTImplOld, voterImplNew);

        // uri is there on the new locks
        vm.startPrank(address(modeDAO));
        {
            lockMode.setBaseURI("https://lockmode.com/");
            lockBPT.setBaseURI("https://lockbpt.com/");
        }
        vm.stopPrank();
    }

    function createUpgradeProposal() internal returns (uint256 proposalId) {
        IDAO.Action[] memory actions = buildActions();

        /// if the network is mode, the proposal will be created on the aragon multisig
        /// first, then reviewed, then sent to the mode team multisig for execution
        string memory network = vm.envString("NETWORK");
        if (strEq(network, "mode") || strEq(network, "mode-mainnet")) {
            setAragonSigners();
            IDAO.Action[] memory outerAction = new IDAO.Action[](1);

            outerAction[0] = IDAO.Action({
                to: address(modeMultisig),
                value: 0,
                data: abi.encodeCall(
                    modeMultisig.createProposal,
                    (
                        "metadata goes here",
                        actions,
                        0,
                        true,
                        false,
                        0,
                        uint64(block.timestamp) + 1 weeks
                    )
                )
            });

            // sign on aragon
            uint outerId;
            vm.startPrank(aragonSigners[0]);
            {
                outerId = _buildMsigProposal(outerAction, aragonSigners, aragonMultisig);
            }
            vm.stopPrank();

            _signExecuteMultisigProposal(outerId, aragonSigners, aragonMultisig);

            // we dont expose the inner proposal id, so we know in advance from the pinned block
            // what will be the next proposal id to be created
            proposalId = PROPOSAL_ID;
        }
        // if running on a testnet, we are directly creating the proposal on the mode multisig
        else if (strEq(network, "mode-sepolia")) {
            vm.startPrank(modeSigners[0]);
            {
                proposalId = _buildMsigProposal(actions, modeSigners, modeMultisig);
            }
            vm.stopPrank();
        } else {
            revert("Network not recognized, expected mode, mode-mainnet or mode-sepolia");
        }
    }

    function buildActions() internal returns (IDAO.Action[] memory) {
        // action 1: deploy new impls
        address lockImplNew = address(new Lock());
        address voterImplNew = address(new SimpleGaugeVoter());

        // action 2: upgradeTo
        IDAO.Action[] memory actions = new IDAO.Action[](4);
        actions[0] = IDAO.Action({
            to: address(lockMode),
            value: 0,
            data: abi.encodeCall(lockMode.upgradeTo, (lockImplNew))
        });

        actions[1] = IDAO.Action({
            to: address(voterMode),
            value: 0,
            data: abi.encodeCall(voterMode.upgradeTo, (voterImplNew))
        });

        actions[2] = IDAO.Action({
            to: address(lockBPT),
            value: 0,
            data: abi.encodeCall(lockBPT.upgradeTo, (lockImplNew))
        });

        actions[3] = IDAO.Action({
            to: address(voterBPT),
            value: 0,
            data: abi.encodeCall(voterBPT.upgradeTo, (voterImplNew))
        });

        return actions;
    }

    function _buildMsigProposal(
        IDAO.Action[] memory _actions,
        address[] memory _signers,
        Multisig _multisig
    ) internal returns (uint256 proposalId) {
        {
            proposalId = _multisig.createProposal({
                _metadata: "Outer proposal metadata",
                _actions: _actions,
                _allowFailureMap: 0,
                _approveProposal: true,
                _tryExecution: false,
                _startDate: 0,
                _endDate: uint64(block.timestamp) + 1 weeks
            });
        }

        return proposalId;
    }

    function _signExecuteMultisigProposal(
        uint256 _proposalId,
        address[] memory _signers,
        Multisig _multisig
    ) internal {
        // load all the proposers into memory other than the first

        if (_signers.length > 1) {
            // have them sign
            for (uint256 i = 1; i < _signers.length; i++) {
                vm.startPrank(_signers[i]);
                {
                    _multisig.approve(_proposalId, false);
                }
                vm.stopPrank();
            }
        }

        // prank the first signer who will create stuff
        vm.startPrank(_signers[0]);
        {
            _multisig.execute(_proposalId);
        }
        vm.stopPrank();
    }

    function strEq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}
