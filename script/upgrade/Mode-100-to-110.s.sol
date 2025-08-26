pragma solidity ^0.8.17;
import {Script} from "forge-std/Script.sol";
import {Test, console2 as console} from "forge-std/Test.sol";

import {Multisig} from "@aragon/multisig/src/Multisig.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import {
    GaugesDaoFactory,
    GaugePluginSet,
    DeploymentParameters,
    Deployment,
    TokenParameters,
    DAO,
    IGaugeVote
} from "@factory/GaugesDaoFactory.sol";
import {
    VotingEscrow,
    Lock,
    Curve,
    ExitQueue,
    GaugeVoter,
    GaugeVoterSetup,
    IGaugeVoterSetupParams
} from "@setup/GaugeVoterSetup.sol";
import {TokenGaugeVoterV1_1_0 as GaugeVoterV1_1_0} from "@voting/TokenGaugeVoter_v1_1_0.sol";

import {Upgrades} from "@foundry-upgrades/src/LegacyUpgrades.sol";
import {Options} from "@foundry-upgrades/src/Options.sol";

contract UpgradeModeTo110 is Script, Test {
    /////////////////////////////////////////////
    // ----------- FIXED CONSTANTS ------------//
    /////////////////////////////////////////////

    string network = vm.envString("NETWORK");

    address factoryAddress = vm.envAddress("FACTORY_ADDRESS");

    address signer = vm.envAddress("SIGNER_ADDRESS");

    string membersFilePath = vm.envString("MULTISIG_MEMBERS_JSON_FILE_NAME");

    /// @dev metadata for the proposal, pinned to pinata
    bytes ipfsURI = bytes("ipfs://bafkreicqy5hgf6izqha6hoa6cudup4or5clfnilegyavwuhbr34xlihsea");

    function setAragonSigners() internal {
        aragonSigners.push(address(0x946138B088524414EEDaf0699BA10d7Fb5673A34));
        aragonSigners.push(address(0xbd3eE47A1576F26454C65B96b7AbfaF8Ee9cB4a1));
        aragonSigners.push(address(0x3ffe3F16d47A54b1C6A3f47c9E6Ff5C2C1B32859));
        aragonSigners.push(address(0x9395e6b95afFee7d7b2b107127Fcc9e4167A336f));
    }

    /// @dev We can't know the mode proposal in advance from tests, so this is pinned
    function getInternalProposalId(string memory _network) public view returns (uint256) {
        if (isMainnet(_network)) return 47;
        else if (isTestnet(_network)) return 1;
        else revert("Invalid network");
    }

    // hardcoded staker, may or may not be voting at block
    function getStaker(string memory _network) public view returns (address staker) {
        if (isMainnet(_network)) return 0xE28842dAF2cDe94EecC81b26A436eB043454F010;
        else if (isTestnet(_network)) return 0xE8375Ae2CaB4A9AB59097c500dD4b923c239ec01;
        else revert("Invalid network");
    }

    /// @dev the aragon multisig that will submit the proposal on mode
    function getAragonMultisig(string memory _network) public view returns (Multisig) {
        if (isMainnet(_network)) return Multisig(0x4315B4D2C707981f7fA51DBE91079Ea8c44e2e95);
        else if (isTestnet(_network)) return Multisig(0x14b1812260CB993bca69f204bC43586322d246d0);
        else revert("Invalid network");
    }

    /////////////////////////////////////////////
    // -------------- STATE VARIABLES ---------//
    /////////////////////////////////////////////

    GaugesDaoFactory factory;

    GaugePluginSet modePluginSet;
    GaugePluginSet bptPluginSet;

    /// @dev Mode multisig executing via the dao
    Multisig modeMultisig;

    /// @dev Mode dao owning the contracts
    DAO modeDAO;

    Lock lockMode;
    Lock lockBPT;
    GaugeVoter voterMode;
    GaugeVoter voterBPT;

    address[] aragonSigners;
    address[] modeSigners;

    /////////////////////////////////////////////
    // -------------- RUN FUNCTION ------------
    /////////////////////////////////////////////

    function run() public {
        bool isTestMode = false;
        (uint256 aragonProposalId, ) = _actionUpgrade(isTestMode);
        console.log("Aragon Proposal ID: ", aragonProposalId);
    }

    function _actionUpgrade(
        bool isTestMode
    ) internal returns (uint aragonProposalId, address voterImplNew) {
        setModeSigners();
        setAragonSigners();
        _retrieveDeployment(factoryAddress);

        _validateUpgrade();

        _startBroadcastOrPrank(isTestMode);
        {
            Action[] memory actions;
            (actions, voterImplNew) = buildActions();
            aragonProposalId = _createAragonMsigProposal(actions);
        }
        _stopBroadcastOrPrank(isTestMode);

        return (aragonProposalId, voterImplNew);
    }

    function _validateUpgrade() internal {
        Options memory options;

        string[] memory exclude = new string[](1);
        // disable initializers is invoked but the custom unsafe allow option is not set in the natspec
        exclude[0] = "lib/osx/packages/contracts/src/core/plugin/PluginUUPSUpgradeable.sol";
        options.exclude = exclude;

        options.referenceContract = "GaugeVoter.sol";
        Upgrades.validateUpgrade("GaugeVoter_v1_1_0.sol:GaugeVoterV1_1_0", options);
    }

    function buildActions() internal returns (Action[] memory, address) {
        // action 1: deploy new impls
        address voterImplNew = address(new GaugeVoterV1_1_0());

        // action 2: upgradeTo
        Action[] memory actions = new Action[](2);
        actions[0] = Action({
            to: address(voterMode),
            value: 0,
            data: abi.encodeCall(voterMode.upgradeTo, (voterImplNew))
        });

        actions[1] = Action({
            to: address(voterBPT),
            value: 0,
            data: abi.encodeCall(voterBPT.upgradeTo, (voterImplNew))
        });

        return (actions, voterImplNew);
    }

    function _startBroadcastOrPrank(bool isTestMode) internal {
        if (isTestMode) {
            vm.startPrank(signer);
        } else {
            vm.startBroadcast(signer);
        }
    }

    function _stopBroadcastOrPrank(bool isTestMode) internal {
        if (isTestMode) {
            vm.stopPrank();
        } else {
            vm.stopBroadcast();
        }
    }

    /////////////////////////////////////////////
    // -------------- TEST FUNCTIONS ----------//
    /////////////////////////////////////////////

    function testUpgrade() public {
        bool isTestMode = true;
        (uint256 aragonProposalId, address voterImplNew) = _actionUpgrade(isTestMode);
        _testUpgrade(aragonProposalId, voterImplNew);
    }

    function _testUpgrade(uint _aragonProposalId, address _voterImplNew) internal {
        // save the old impls
        address voterImplOld = voterMode.implementation();
        address voterBPTImplOld = voterBPT.implementation();

        _executeAragonProposal(_aragonProposalId);

        // get the internal proposal id on the mode multisig
        uint proposalId = getInternalProposalId(network);
        _signExecuteMultisigProposal(proposalId, modeSigners, modeMultisig);

        // begin the test
        address voterImplNew = voterMode.implementation();
        address voterBPTImplNew = voterBPT.implementation();

        assertNotEq(voterImplOld, voterImplNew);
        assertNotEq(voterBPTImplOld, voterImplNew);

        assertEq(voterImplNew, _voterImplNew);
        assertEq(voterBPTImplNew, _voterImplNew);

        // check that reset is allowed during a voting window

        // fetch a staker
        address staker = getStaker(network);

        // ensure we have vp
        vm.warp(block.timestamp + 1 weeks);

        // are they voting? if not, move to voting window
        uint veNFT = VotingEscrow(voterMode.escrow()).ownedTokens(staker)[0];
        if (!voterMode.isVoting(veNFT)) {
            // create the gauge and vote for it
            vm.startPrank(address(modeDAO));
            {
                voterMode.unpause();
                voterMode.createGauge(address(1993), "");
            }
            vm.stopPrank();

            // vote by moving to voting window
            if (!voterMode.votingActive()) {
                vm.warp(block.timestamp + 1 weeks);
            }

            vm.startPrank(staker);
            {
                IGaugeVote.GaugeVote[] memory votes = new IGaugeVote.GaugeVote[](1);
                votes[0] = IGaugeVote.GaugeVote({weight: 1, gauge: address(1993)});
                voterMode.vote(veNFT, votes);
            }
            vm.stopPrank();
        }

        // move to the dist window
        if (voterMode.votingActive()) {
            vm.warp(block.timestamp + 1 weeks);
        }

        // call reset
        assertEq(voterMode.isVoting(veNFT), true);
        assertEq(voterMode.votingActive(), false);

        vm.startPrank(staker);
        {
            voterMode.reset(veNFT);
        }
        vm.stopPrank();

        assertEq(voterMode.isVoting(veNFT), false);
    }

    /////////////////////////////////////////////
    // -------------- UTIL FUNCTIONS ----------//
    /////////////////////////////////////////////

    function setModeSigners() internal {
        address[] memory signers = readMultisigMembers();
        for (uint256 i = 0; i < signers.length; i++) {
            modeSigners.push(signers[i]);
        }
    }

    function readMultisigMembers() public view returns (address[] memory result) {
        // JSON list of members
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

    function _createAragonMsigProposal(
        Action[] memory _actions
    ) internal returns (uint256 proposalId) {
        Action[] memory outerAction = new Action[](1);

        outerAction[0] = Action({
            to: address(modeMultisig),
            value: 0,
            data: abi.encodeWithSignature(
                "createProposal(string,(address,uint256,bytes)[],uint256,bool,bool,uint256,uint64)",
                ipfsURI,
                _actions,
                0,
                true,
                false,
                0,
                uint64(block.timestamp) + 1 weeks
            )
        });

        // need to build on aragon first
        Multisig aragonMultisig = getAragonMultisig(network);
        proposalId = _buildMsigProposal(outerAction, aragonMultisig, false);
    }

    function _executeAragonProposal(uint outerId) internal {
        Multisig aragonMultisig = getAragonMultisig(network);
        _signExecuteMultisigProposal(outerId, aragonSigners, aragonMultisig);
    }

    function _buildMsigProposal(
        Action[] memory _actions,
        Multisig _multisig,
        bool _tryExecution
    ) internal returns (uint256 proposalId) {
        {
            proposalId = _multisig.createProposal({
                _metadata: ipfsURI,
                _actions: _actions,
                _allowFailureMap: 0,
                _approveProposal: true,
                _tryExecution: _tryExecution,
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
                    if (!_multisig.hasApproved(_proposalId, _signers[i]))
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

    function isMainnet(string memory _network) internal pure returns (bool) {
        return strEq(_network, "mode") || strEq(_network, "mode-mainnet");
    }

    function isTestnet(string memory _network) internal pure returns (bool) {
        return strEq(_network, "mode-sepolia");
    }
}
