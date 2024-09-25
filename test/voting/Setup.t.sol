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

import "@helpers/OSxHelpers.sol";

import {IEscrowCurveUserStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {IWithdrawalQueueErrors} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {IGaugeVote} from "src/voting/ISimpleGaugeVoter.sol";
import {VotingEscrow, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, ISimpleGaugeVoterSetupParams} from "src/voting/SimpleGaugeVoterSetup.sol";

import {GaugeVotingBase} from "./GaugeVotingBase.sol";

import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";

contract VoterSetupTest is GaugeVotingBase {
    error WrongHelpersArrayLength(uint256 length);

    function testInstallAndUninstall() public {
        // Verify permissions have been granted
        assertTrue(dao.hasPermission(address(voter), address(dao), voter.GAUGE_ADMIN_ROLE(), ""));
        assertTrue(
            dao.hasPermission(address(escrow), address(dao), escrow.ESCROW_ADMIN_ROLE(), "")
        );
        assertTrue(dao.hasPermission(address(queue), address(dao), queue.QUEUE_ADMIN_ROLE(), ""));
        assertTrue(dao.hasPermission(address(curve), address(dao), curve.CURVE_ADMIN_ROLE(), ""));
        assertTrue(
            dao.hasPermission(
                address(voter),
                address(dao),
                voter.UPGRADE_PLUGIN_PERMISSION_ID(),
                ""
            )
        );
        assertTrue(dao.hasPermission(address(clock), address(dao), clock.CLOCK_ADMIN_ROLE(), ""));
        assertTrue(
            dao.hasPermission(address(nftLock), address(dao), nftLock.LOCK_ADMIN_ROLE(), "")
        );
        assertTrue(dao.hasPermission(address(escrow), address(dao), escrow.PAUSER_ROLE(), ""));
        assertTrue(dao.hasPermission(address(escrow), address(dao), escrow.SWEEPER_ROLE(), ""));
        assertTrue(dao.hasPermission(address(queue), address(dao), queue.WITHDRAW_ROLE(), ""));

        // Prepare uninstallation and revoke permissions
        IPluginSetup.SetupPayload memory payload = IPluginSetup.SetupPayload({
            plugin: address(voter),
            currentHelpers: new address[](5),
            data: bytes("")
        });

        payload.currentHelpers[0] = address(curve);
        payload.currentHelpers[1] = address(queue);
        payload.currentHelpers[2] = address(escrow);
        payload.currentHelpers[3] = address(clock);
        payload.currentHelpers[4] = address(nftLock);

        PermissionLib.MultiTargetPermission[] memory revokePermissions = voterSetup
            .prepareUninstallation(address(dao), payload);

        vm.prank(address(dao));
        dao.applyMultiTargetPermissions(revokePermissions);

        // Verify permissions have been revoked
        assertFalse(dao.hasPermission(address(voter), address(dao), voter.GAUGE_ADMIN_ROLE(), ""));
        assertFalse(
            dao.hasPermission(address(escrow), address(dao), escrow.ESCROW_ADMIN_ROLE(), "")
        );
        assertFalse(dao.hasPermission(address(queue), address(dao), queue.QUEUE_ADMIN_ROLE(), ""));
        assertFalse(dao.hasPermission(address(curve), address(dao), curve.CURVE_ADMIN_ROLE(), ""));
        assertFalse(
            dao.hasPermission(
                address(voter),
                address(dao),
                voter.UPGRADE_PLUGIN_PERMISSION_ID(),
                ""
            )
        );
        assertFalse(dao.hasPermission(address(clock), address(dao), clock.CLOCK_ADMIN_ROLE(), ""));
        assertFalse(
            dao.hasPermission(address(nftLock), address(dao), nftLock.LOCK_ADMIN_ROLE(), "")
        );
        assertFalse(dao.hasPermission(address(escrow), address(dao), escrow.PAUSER_ROLE(), ""));
        assertFalse(dao.hasPermission(address(escrow), address(dao), escrow.SWEEPER_ROLE(), ""));
        assertFalse(dao.hasPermission(address(queue), address(dao), queue.WITHDRAW_ROLE(), ""));
    }

    function testCantPassIncorrectHelpers() public {
        address[] memory currentHelpers = new address[](2);
        currentHelpers[0] = address(curve);
        currentHelpers[1] = address(queue);

        IPluginSetup.SetupPayload memory payload = IPluginSetup.SetupPayload({
            plugin: address(voter),
            currentHelpers: currentHelpers,
            data: bytes("")
        });

        vm.startPrank(address(dao));
        {
            vm.expectRevert(
                abi.encodeWithSelector(WrongHelpersArrayLength.selector, currentHelpers.length)
            );
            voterSetup.prepareUninstallation(address(dao), payload);
        }
        vm.stopPrank();
    }

    function testInstallerAndUninstaller() public {
        bool isPaused = true;
        string memory veTokenName = "veTokenNameeeeee";
        string memory veTokenSymbol = "veTokenSymbollllll";
        address token = address(new MockERC20());
        uint256 warmup = 5 days;
        uint256 cooldown = 7 days;
        uint256 feePercent = 0.05e18;
        uint minLock = 2 weeks;

        ISimpleGaugeVoterSetupParams memory params = ISimpleGaugeVoterSetupParams({
            isPaused: isPaused,
            token: token,
            veTokenName: veTokenName,
            veTokenSymbol: veTokenSymbol,
            warmup: warmup,
            cooldown: cooldown,
            feePercent: feePercent,
            minLock: minLock
        });

        bytes memory encodedStruct = voterSetup.encodeSetupData(params);
        bytes32 encodedHash = keccak256(encodedStruct);

        bytes memory encodedArgs = voterSetup.encodeSetupData(
            isPaused,
            veTokenName,
            veTokenSymbol,
            token,
            cooldown,
            warmup,
            feePercent,
            minLock
        );
        bytes32 encodedArgsHash = keccak256(encodedArgs);

        assertEq(encodedHash, encodedArgsHash);
    }

    function testImplementation() public view {
        assertEq(voterSetup.implementation(), address(voterBase));
    }

    // coverage autism
    function testConstructor() public {
        new SimpleGaugeVoterSetup(
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        );
    }
}
