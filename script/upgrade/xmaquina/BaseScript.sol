// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {Script} from "forge-std/Script.sol";
import {IExecutor, Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

interface IMultisig {
    struct MultisigSettings {
        bool onlyListed;
        uint16 minApprovals;
    }

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed creator,
        uint64 startDate,
        uint64 endDate,
        bytes metadata,
        Action[] actions,
        uint256 allowFailureMap
    );

    function isMember(address account) external view returns (bool);
    function multisigSettings() external view returns (MultisigSettings memory);
    function createProposal(
        bytes calldata _metadata,
        Action[] calldata _actions,
        uint256 _allowFailureMap,
        bool _approveProposal,
        bool _tryExecution,
        uint64 _startDate,
        uint64 _endDate
    ) external returns (uint256 proposalId);
    function execute(uint256 _proposalId) external;
    function approve(uint256 _proposalId, bool _tryExecution) external;
    function proposalCount() external view returns (uint256);
}

/**
 * @title BaseScript
 * @notice Base contract with shared interfaces, constants, and helper functions for all scripts
 */
abstract contract BaseScript is Script {
    string internal network;

    // ====================================================================
    // Deployment Addresses
    // ====================================================================

    address internal DAO;
    address internal ARAGON_DAO;

    address internal ARAGON_MULTISIG_PLUGIN;
    address internal MULTISIG_PLUGIN;
    address internal GAUGE_VOTER_PLUGIN;

    address internal TOKEN;
    address internal CURVE;
    address internal EXIT_QUEUE;
    address internal VOTING_ESCROW;
    address internal CLOCK;
    address internal NFT_LOCK;
    address internal ESCROW_IVOTES_ADAPTER;

    address internal TEAM_MEMBER_1;
    address internal TEAM_MEMBER_2;
    address internal TEAM_MEMBER_3;
    address internal TEAM_MEMBER_4;
    address internal TEAM_MEMBER_5;

    // Aragon Team Members Multisig (same for both networks)
    address internal constant ARAGON_MEMBER_1 = 0xd953216D672218db55cAb06c2406D5f8af89D720;
    address internal constant ARAGON_MEMBER_2 = 0xbC86D5E5F41B9D23BD2511d1CdbB9DcF1d4E2b38;
    address internal constant ARAGON_MEMBER_3 = 0x946138B088524414EEDaf0699BA10d7Fb5673A34;

    constructor() {
        _setNetworkConfig(vm.envString("NETWORK"));
    }

    function _setNetworkConfig(string memory _network) internal {
        network = _network;

        if (_isBaseNetwork(_network)) {
            ARAGON_DAO = 0xD488517eAf6780745C28E2f48cc1D6c2Df07b7c2;
            ARAGON_MULTISIG_PLUGIN = 0xBe3D415e5CE1B72F49E91AFdbf625cd6C3D25a74;
            DAO = 0xfEA21e0500022F34dE0a02Ae3A7D04dF923Ed020;
            MULTISIG_PLUGIN = 0x826CA0c721A1F1c2c6A469C65825d4E5a331e69d;
            GAUGE_VOTER_PLUGIN = 0x3e5598c1b34dA6E198E4Bd7d20Acb287D9e88c91;

            TOKEN = 0x940A319B75861014A220D9c6c144d108552B089B;
            CURVE = 0x90D5e0A9275b075752838d38ccaf6502d7375336;
            EXIT_QUEUE = 0x3B80f4F259F220C0Fb3e5Df266b93683644f0a6a;
            VOTING_ESCROW = 0xA85A38796B951CE87B378538b32B3E6Ee3C4C373;
            CLOCK = 0x808404567dd3Cc1A0152a9F489a8B22a2F7A6c7a;
            NFT_LOCK = 0xE6d5f7439Bc236C40054e2275f765f59343D4431;
            ESCROW_IVOTES_ADAPTER = 0x9C574B0f8526315b9defdf7539dD3d25B7Ec7618;
        } else if (_isPeaqNetwork(_network)) {
            ARAGON_DAO = 0x570494e1136E45761b59a42Bc56898dD748Fb5C1;
            ARAGON_MULTISIG_PLUGIN = 0xE175C2457BedDb4E03B718232ABFc4fd0947CB21;
            DAO = 0x38E4512E4Dbf69F526E30c4F58862bF0C7b26201;
            MULTISIG_PLUGIN = 0xD75F4470A88fe04E92Fc20929A6d215CCfaddC72;
            GAUGE_VOTER_PLUGIN = 0xB7ab2736EB5eA3adc1CB6583f2A733ef5f8073D4;

            TOKEN = 0x940A319B75861014A220D9c6c144d108552B089B;
            CURVE = 0xFE523090bf514f66c89306964e13169f345999F1;
            EXIT_QUEUE = 0x3FCc4dE2666BcEc1F04C2e99D1125b24526073FE;
            VOTING_ESCROW = 0xF12B6cB2563d7DAF7DbB17e65b4422DB11CA0A0f;
            CLOCK = 0xE0896d545367Eb89C409555828d2eF0266Fe861B;
            NFT_LOCK = 0x10F77088Db73936CA82AC52f6C7915a261E6B3C6;
            ESCROW_IVOTES_ADAPTER = 0x9A4d2dD5eE86cd16B0CeD51742Ee946C9e117789;
        } else {
            revert("Invalid NETWORK. Use base/base-mainnet or peaq/peaq-mainnet");
        }

        _setTeamMembers();
    }

    function _setTeamMembers() internal {
        TEAM_MEMBER_1 = 0xD8f8E00e9d9aB9600a910f133F8959737E143e84;
        TEAM_MEMBER_2 = 0x21b53a4E3A87A1bC26A486295Ae41C00B09b409A;
        TEAM_MEMBER_3 = 0x441873845621C28e90add422c444273D67f2F1cB;
        TEAM_MEMBER_4 = 0xAaC26d8bfA9d13398774F9e10DBAFb2Bac32FF7f;
        TEAM_MEMBER_5 = 0x55D9C48DDcD72fD4503E307DAd643d9bF7955270;
    }

    function _isBaseNetwork(string memory _network) internal pure returns (bool) {
        return _strEq(_network, "base") || _strEq(_network, "base-mainnet");
    }

    function _isPeaqNetwork(string memory _network) internal pure returns (bool) {
        return _strEq(_network, "peaq") || _strEq(_network, "peaq-mainnet");
    }

    function _strEq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function createProposalData(
        bytes memory metadata,
        Action[] memory actions
    ) internal view returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IMultisig.createProposal.selector,
                metadata,
                actions,
                0, // allowFailureMap - all actions must succeed
                false, // approveProposal - don't auto-approve
                false, // tryExecution - don't try to execute immediately
                uint64(0), // startDate - 0 means now
                uint64(block.timestamp + 5 days) // endDate
            );
    }

    function _serializeActions(
        Action[] memory _actions
    ) internal pure returns (string memory serialized) {
        string memory json = "[";

        for (uint i = 0; i < _actions.length; i++) {
            Action memory a = _actions[i];

            // Build individual action JSON manually
            json = string.concat(
                json,
                '{"to":"',
                vm.toString(a.to),
                '","value":',
                vm.toString(a.value),
                ',"data":"',
                vm.toString(a.data),
                '"}'
            );

            // Add comma if not last element
            if (i < _actions.length - 1) {
                json = string.concat(json, ",");
            }
        }

        json = string.concat(json, "]");
        return json;
    }

    function getLatestProposalId() internal returns (uint256 proposalId) {
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // ProposalCreated event signature - tuple should be encoded as (address,uint256,bytes)
        bytes32 proposalCreatedSig = keccak256(
            "ProposalCreated(uint256,address,uint64,uint64,bytes,(address,uint256,bytes)[],uint256)"
        );

        // Search for the ProposalCreated event from the main multisig
        for (uint i = logs.length; i > 0; i--) {
            if (
                logs[i - 1].topics[0] == proposalCreatedSig &&
                logs[i - 1].emitter == MULTISIG_PLUGIN
            ) {
                // First topic is the event signature, second is the indexed proposalId
                proposalId = uint256(logs[i - 1].topics[1]);
                return proposalId;
            }
        }

        revert("ProposalCreated event not found");
    }

    function createProposalViaAragonMultisig(
        string memory metadata,
        Action[] memory actions
    ) internal returns (uint256 proposalId) {
        IMultisig multisig = IMultisig(ARAGON_MULTISIG_PLUGIN);

        vm.prank(ARAGON_MEMBER_1);
        uint256 aragonProposalId = multisig.createProposal(
            bytes(metadata),
            actions,
            0, // allowFailureMap - all actions must succeed
            false, // approveProposal - approve with Aragon DAO's signature
            false, // tryExecution - don't try to execute immediately
            uint64(0), // startDate - 0 means now
            uint64(block.timestamp + 5 days) // endDate - 5 days from now
        );

        vm.prank(ARAGON_MEMBER_1);
        multisig.approve(aragonProposalId, false);

        vm.prank(ARAGON_MEMBER_2);
        multisig.approve(aragonProposalId, false);

        vm.prank(ARAGON_MEMBER_3);
        multisig.approve(aragonProposalId, false);

        vm.recordLogs();
        multisig.execute(aragonProposalId);
        proposalId = getLatestProposalId();

        vm.prank(ARAGON_DAO);
        IMultisig(MULTISIG_PLUGIN).approve(proposalId, false);

        // Actions are executed from the xmaquina multisig proposal.
        IMultisig(MULTISIG_PLUGIN).execute(proposalId);
    }
}
