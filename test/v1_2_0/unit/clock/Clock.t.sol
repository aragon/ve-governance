pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

// aragon contracts
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/src/MultisigSetup.sol";

import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
import {MockDAOFactory} from "@mocks/osx/MockDAOFactory.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

import "@helpers/OSxHelpers.sol";

import {Clock} from "../../versions.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";

contract TestClock is Test {
    using ProxyLib for address;

    Clock clock;
    DAO dao;
    Multisig multisig;

    function setUp() public {
        // deploy the mock PSP with the multisig  plugin
        MultisigSetup multisigSetup = new MultisigSetup();
        MockPluginSetupProcessor psp = new MockPluginSetupProcessor(address(multisigSetup));
        MockDAOFactory daoFactory = new MockDAOFactory(psp);

        // use the OSx DAO factory with the Plugin
        address[] memory members = new address[](1);
        members[0] = address(this);

        // encode a 1/1 multisig that can be adjusted later
        bytes memory data = abi.encode(
            members,
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 1}),
            IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call}),
            bytes("0x11")
        );

        dao = daoFactory.createDao(_mockDAOSettings(), _mockPluginSettings(data));
        multisig = Multisig(computeAddress(address(multisigSetup), 2));

        // deploy the clock
        Clock base = new Clock();
        clock = Clock(
            address(base).deployUUPSProxy(
                abi.encodeWithSelector(Clock.initialize.selector, address(dao))
            )
        );

        vm.warp(0);
    }

    function testClockOverTime() public {
        for (uint i = 0; i < 10; ++i) {
            uint start = block.timestamp;

            // start
            assertEq(clock.elapsedInEpoch(), 0);
            assertEq(clock.currentEpoch(), i);
            assertEq(clock.epochStartsIn(), 0);
            assertEq(clock.epochStartTs(), block.timestamp);
            assertEq(clock.epochVoteStartTs(), block.timestamp + 1 hours);
            assertEq(clock.epochVoteStartsIn(), 1 hours);
            assertEq(clock.epochVoteEndTs(), block.timestamp + 1 weeks - 1 hours);
            assertEq(clock.epochVoteEndsIn(), 1 weeks - 1 hours);
            assertEq(clock.votingActive(), false);
            assertEq(clock.epochPrevCheckpointTs(), block.timestamp);
            assertEq(clock.epochPrevCheckpointElapsed(), 0);
            assertEq(clock.epochNextCheckpointTs(), block.timestamp + 1 weeks);
            assertEq(clock.epochNextCheckpointIn(), 1 weeks);
            assertEq(clock.epochStartsIn(), 0);

            // +1hr: voting starts
            vm.warp(start + 1 hours);

            assertEq(clock.elapsedInEpoch(), 1 hours);
            assertEq(clock.currentEpoch(), i);
            assertEq(clock.epochStartsIn(), 2 weeks - 1 hours);
            assertEq(clock.epochStartTs(), block.timestamp + 2 weeks - 1 hours);
            assertEq(clock.epochVoteStartTs(), block.timestamp);
            assertEq(clock.epochVoteStartsIn(), 0);
            assertEq(clock.epochVoteEndTs(), block.timestamp + 1 weeks - 2 hours);
            assertEq(clock.epochVoteEndsIn(), 1 weeks - 2 hours);
            assertEq(clock.votingActive(), true);
            assertEq(clock.epochPrevCheckpointTs(), block.timestamp - 1 hours);
            assertEq(clock.epochPrevCheckpointElapsed(), 1 hours);
            assertEq(clock.epochNextCheckpointTs(), block.timestamp + 1 weeks - 1 hours);
            assertEq(clock.epochNextCheckpointIn(), 1 weeks - 1 hours);
            assertEq(clock.epochStartsIn(), 2 weeks - 1 hours);

            // +1 week - 1 hours: voting ends
            vm.warp(start + 1 weeks - 1 hours);

            assertEq(clock.elapsedInEpoch(), 1 weeks - 1 hours);
            assertEq(clock.currentEpoch(), i);
            assertEq(clock.epochStartsIn(), 1 weeks + 1 hours);
            assertEq(clock.epochStartTs(), block.timestamp + 1 weeks + 1 hours);
            assertEq(clock.epochVoteStartTs(), block.timestamp + 1 weeks + 2 hours);
            assertEq(clock.epochVoteStartsIn(), 1 weeks + 2 hours);
            assertEq(clock.epochVoteEndTs(), block.timestamp);
            assertEq(clock.epochVoteEndsIn(), 0);
            assertEq(clock.votingActive(), false);
            assertEq(clock.epochPrevCheckpointTs(), block.timestamp + 1 hours - 1 weeks);
            assertEq(clock.epochPrevCheckpointElapsed(), 1 weeks - 1 hours);
            assertEq(clock.epochNextCheckpointTs(), block.timestamp + 1 hours);
            assertEq(clock.epochNextCheckpointIn(), 1 hours);
            assertEq(clock.epochStartsIn(), 1 weeks + 1 hours);

            // +1 week: next deposit opens
            vm.warp(start + 1 weeks);

            assertEq(clock.elapsedInEpoch(), 1 weeks);
            assertEq(clock.currentEpoch(), i);
            assertEq(clock.epochStartsIn(), 1 weeks);
            assertEq(clock.epochStartTs(), block.timestamp + 1 weeks);
            assertEq(clock.epochVoteStartTs(), block.timestamp + 1 weeks + 1 hours);
            assertEq(clock.epochVoteStartsIn(), 1 weeks + 1 hours);
            assertEq(clock.epochVoteEndTs(), block.timestamp);
            assertEq(clock.epochVoteEndsIn(), 0);
            assertEq(clock.votingActive(), false);
            assertEq(clock.epochPrevCheckpointTs(), block.timestamp);
            assertEq(clock.epochPrevCheckpointElapsed(), 0);
            assertEq(clock.epochNextCheckpointTs(), block.timestamp + 1 weeks);
            assertEq(clock.epochNextCheckpointIn(), 1 weeks);
            assertEq(clock.epochStartsIn(), 1 weeks);

            // whole of next week calculates correctly

            vm.warp(start + 1 weeks + 3 days);

            assertEq(clock.elapsedInEpoch(), 1 weeks + 3 days);
            assertEq(clock.currentEpoch(), i);
            assertEq(clock.epochStartsIn(), 4 days);
            assertEq(clock.epochStartTs(), block.timestamp + 4 days);
            assertEq(clock.epochVoteStartTs(), block.timestamp + 4 days + 1 hours);
            assertEq(clock.epochVoteStartsIn(), 4 days + 1 hours);
            assertEq(clock.epochVoteEndTs(), block.timestamp);
            assertEq(clock.epochVoteEndsIn(), 0);
            assertEq(clock.votingActive(), false);
            assertEq(clock.epochPrevCheckpointTs(), block.timestamp - 3 days);
            assertEq(clock.epochPrevCheckpointElapsed(), 3 days);
            assertEq(clock.epochNextCheckpointTs(), block.timestamp + 4 days);
            assertEq(clock.epochNextCheckpointIn(), 4 days);
            assertEq(clock.epochStartsIn(), 4 days);

            // dist window closing
            vm.warp(start + 2 weeks - 1 hours);

            assertEq(clock.elapsedInEpoch(), 2 weeks - 1 hours);
            assertEq(clock.currentEpoch(), i);
            assertEq(clock.epochStartsIn(), 1 hours);
            assertEq(clock.epochStartTs(), block.timestamp + 1 hours);
            assertEq(clock.epochVoteStartTs(), block.timestamp + 2 hours);
            assertEq(clock.epochVoteStartsIn(), 2 hours);
            assertEq(clock.epochVoteEndTs(), block.timestamp);
            assertEq(clock.epochVoteEndsIn(), 0);
            assertEq(clock.votingActive(), false);
            assertEq(clock.epochPrevCheckpointTs(), block.timestamp + 1 hours - 7 days);
            assertEq(clock.epochPrevCheckpointElapsed(), 1 weeks - 1 hours);
            assertEq(clock.epochNextCheckpointTs(), block.timestamp + 1 hours);
            assertEq(clock.epochNextCheckpointIn(), 1 hours);
            assertEq(clock.epochStartsIn(), 1 hours);

            // +1 week + 2 hours: next epoch starts
            vm.warp(start + 2 weeks);
        }
    }
}
