// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.8;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {MockDAOFactory, PluginSetupRef} from "@mocks/osx/MockDAOFactory.sol";
import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";

function bytes32ToAddress(bytes32 _bytes32) pure returns (address) {
    return address(uint160(uint256(_bytes32)));
}

/// @dev call the PSP with an action wrapped in grant/revoke root permissions
function wrapGrantRevokeRoot(DAO _dao, address _psp, IDAO.Action memory _action) view returns (IDAO.Action[] memory) {
    IDAO.Action[] memory actions = new IDAO.Action[](3);
    actions[0] = IDAO.Action({
        to: address(_dao),
        value: 0,
        data: abi.encodeCall(_dao.grant, (address(_dao), _psp, _dao.ROOT_PERMISSION_ID()))
    });

    actions[1] = _action;

    actions[2] = IDAO.Action({
        to: address(_dao),
        value: 0,
        data: abi.encodeCall(_dao.revoke, (address(_dao), _psp, _dao.ROOT_PERMISSION_ID()))
    });

    return actions;
}

/// @dev call the PSP with actions wrapped in grant/revoke root permissions
function wrapGrantRevokeRoot(
    DAO _dao,
    address _psp,
    IDAO.Action[] memory _actions
) view returns (IDAO.Action[] memory) {
    uint8 len = uint8(_actions.length);
    IDAO.Action[] memory actions = new IDAO.Action[](len + 2);
    actions[0] = IDAO.Action({
        to: address(_dao),
        value: 0,
        data: abi.encodeCall(_dao.grant, (address(_dao), _psp, _dao.ROOT_PERMISSION_ID()))
    });

    for (uint8 i = 0; i < len; i++) {
        actions[i + 1] = _actions[i];
    }

    actions[len + 1] = IDAO.Action({
        to: address(_dao),
        value: 0,
        data: abi.encodeCall(_dao.revoke, (address(_dao), _psp, _dao.ROOT_PERMISSION_ID()))
    });

    return actions;
}

// eth address derivation using RLP encoding
// use this if you can't get the address directly and don't have access to CREATE2
function computeAddress(address target, uint8 nonce) pure returns (address) {
    bytes memory data;
    if (nonce == 0) {
        data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), target, bytes1(0x80));
    } else if (nonce <= 0x7f) {
        data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), target, uint8(nonce));
    } else if (nonce <= 0xff) {
        data = abi.encodePacked(bytes1(0xd7), bytes1(0x94), target, bytes1(0x81), uint8(nonce));
    } else if (nonce <= 0xffff) {
        data = abi.encodePacked(bytes1(0xd8), bytes1(0x94), target, bytes1(0x82), uint16(nonce));
    } else if (nonce <= 0xffffff) {
        data = abi.encodePacked(bytes1(0xd9), bytes1(0x94), target, bytes1(0x83), uint24(nonce));
    } else {
        data = abi.encodePacked(bytes1(0xda), bytes1(0x94), target, bytes1(0x84), uint32(nonce));
    }

    return bytes32ToAddress(keccak256(data));
}

function _mockDAOSettings() pure returns (MockDAOFactory.DAOSettings memory) {
    return
        MockDAOFactory.DAOSettings({
            trustedForwarder: address(0),
            daoURI: "test",
            subdomain: "test",
            metadata: new bytes(0)
        });
}

// all this data is unused in the mock
function _mockPluginSetupRef() pure returns (PluginSetupRef memory) {
    return
        PluginSetupRef({pluginSetupRepo: PluginRepo(address(0)), versionTag: PluginRepo.Tag({release: 1, build: 0})});
}

function _mockPrepareInstallationParams(
    bytes memory data
) pure returns (MockPluginSetupProcessor.PrepareInstallationParams memory) {
    return MockPluginSetupProcessor.PrepareInstallationParams(_mockPluginSetupRef(), data);
}

function _mockApplyInstallationParams(
    address plugin,
    PermissionLib.MultiTargetPermission[] memory permissions
) pure returns (MockPluginSetupProcessor.ApplyInstallationParams memory) {
    return
        MockPluginSetupProcessor.ApplyInstallationParams(
            _mockPluginSetupRef(),
            plugin,
            permissions,
            bytes32("helpersHash")
        );
}

/// we don't use most of the plugin settings in the mock so just ignore it
function _mockPluginSettings(bytes memory data) pure returns (MockDAOFactory.PluginSettings[] memory) {
    MockDAOFactory.PluginSettings[] memory settings = new MockDAOFactory.PluginSettings[](1);
    settings[0] = MockDAOFactory.PluginSettings({pluginSetupRef: _mockPluginSetupRef(), data: data});
    return settings;
}

function _mockPrepareUninstallationParams(
    IPluginSetup.SetupPayload memory payload
) pure returns (MockPluginSetupProcessor.PrepareUninstallationParams memory) {
    return MockPluginSetupProcessor.PrepareUninstallationParams(_mockPluginSetupRef(), payload);
}

function _mockApplyUninstallationParams(
    address plugin,
    PermissionLib.MultiTargetPermission[] memory permissions
) pure returns (MockPluginSetupProcessor.ApplyUninstallationParams memory) {
    return MockPluginSetupProcessor.ApplyUninstallationParams(plugin, _mockPluginSetupRef(), permissions);
}
