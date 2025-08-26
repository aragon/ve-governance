// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
import {PluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginSetup.sol";

contract PlaceholderSetup {
    function prepareInstallation(
        address,
        bytes calldata
    ) external returns (address plugin, PluginSetup.PreparedSetupData memory preparedSetupData) {}
}
