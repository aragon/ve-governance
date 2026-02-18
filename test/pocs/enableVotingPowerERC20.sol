// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {AddressGaugeVoter} from "@voting/AddressGaugeVoter.sol";
import {IAddressGaugeVoter, IAddressGaugeVote} from "@voting/IAddressGaugeVoter.sol";
import {Clock} from "@clock/Clock.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

// ──────────────────────────────────────────────────────────
// Modified ERC20Votes that calls updateVotingPower on transfer
// ──────────────────────────────────────────────────────────

contract ERC20VotesWithGaugeHook is ERC20Votes {
    address public voter;

    constructor() ERC20("GaugeToken", "GT") ERC20Permit("GaugeToken") {}

    function setVoter(address _voter) external {
        voter = _voter;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function clock() public view virtual override returns (uint48) {
        return SafeCast.toUint48(block.timestamp);
    }

    function CLOCK_MODE() public view virtual override returns (string memory) {
        require(clock() == block.timestamp);
        return "mode=timestamp&from=default";
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        // First let OZ update the voting power checkpoints
        super._afterTokenTransfer(from, to, amount);

        if (voter == address(0)) return;

        // Resolve the delegatees whose voting power changed
        address fromDelegatee = (from != address(0)) ? delegates(from) : address(0);
        address toDelegatee = (to != address(0)) ? delegates(to) : address(0);

        // Only call if at least one side has a delegatee
        if (fromDelegatee != address(0) || toDelegatee != address(0)) {
            address effFrom = fromDelegatee != address(0) ? fromDelegatee : toDelegatee;
            address effTo = toDelegatee != address(0) ? toDelegatee : fromDelegatee;
            IAddressGaugeVoter(voter).updateVotingPower(effFrom, effTo);
        }
    }
}

// ──────────────────────────────────────────────────────────
// Test harness
// ──────────────────────────────────────────────────────────

contract EnableVotingPowerERC20Test is Test {
    // Constants matching Clock.sol
    uint256 constant EPOCH_DURATION = 2 weeks;
    uint256 constant VOTE_WINDOW_BUFFER = 1 hours;

    DAO dao;
    Clock clockImpl;
    Clock clockProxy;
    AddressGaugeVoter voterImpl;
    AddressGaugeVoter voterProxy;
    ERC20VotesWithGaugeHook token;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    address gauge1 = makeAddr("gauge1");
    address gauge2 = makeAddr("gauge2");
    address gauge3 = makeAddr("gauge3");

    function setUp() public {
        // Deploy DAO
        {
            DAO daoImpl = new DAO();
            dao = DAO(payable(new ERC1967Proxy(address(daoImpl), bytes(""))));
            dao.initialize({
                _metadata: bytes(""),
                _initialOwner: address(this),
                _trustedForwarder: address(0),
                daoURI_: "ipfs://"
            });
        }

        // Deploy Clock
        {
            clockImpl = new Clock();
            clockProxy = Clock(address(new ERC1967Proxy(
                address(clockImpl),
                abi.encodeCall(Clock.initialize, (address(dao)))
            )));
        }

        // Deploy token
        token = new ERC20VotesWithGaugeHook();

        // Deploy AddressGaugeVoter with hook enabled
        // The "escrow" is the token itself since transfers trigger the hook
        {
            voterImpl = new AddressGaugeVoter();
            voterProxy = AddressGaugeVoter(address(new ERC1967Proxy(
                address(voterImpl),
                abi.encodeCall(AddressGaugeVoter.initialize, (
                    address(dao),
                    address(token),   // escrow = token (it calls updateVotingPower)
                    false,            // not paused
                    address(clockProxy),
                    address(token),   // ivotesAdapter = token (implements IVotes)
                    true              // enableUpdateVotingPowerHook = true
                ))
            )));
        }

        // Wire token to voter
        token.setVoter(address(voterProxy));

        // Grant GAUGE_ADMIN_ROLE to this contract
        bytes32 gaugeAdminRole = voterProxy.GAUGE_ADMIN_ROLE();
        dao.grant(address(voterProxy), address(this), gaugeAdminRole);

        // Create gauges
        voterProxy.createGauge(gauge1, "gauge1");
        voterProxy.createGauge(gauge2, "gauge2");
        voterProxy.createGauge(gauge3, "gauge3");

        // Mint tokens and self-delegate
        token.mint(alice, 1000e18);
        token.mint(bob, 500e18);
        token.mint(carol, 300e18);

        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);
        vm.prank(carol);
        token.delegate(carol);
    }

    // ── Helpers ──────────────────────────────────────────

    function _warpToVotingActive() internal {
        // Warp to start of next epoch + buffer so voting is active
        uint256 epoch = clockProxy.currentEpoch();
        uint256 nextEpochStart = (epoch + 1) * EPOCH_DURATION;
        vm.warp(nextEpochStart + VOTE_WINDOW_BUFFER + 1);
        assertTrue(clockProxy.votingActive(), "voting should be active");
    }

    function _warpToNextEpochVoting() internal {
        uint256 epoch = clockProxy.currentEpoch();
        uint256 nextEpochStart = (epoch + 1) * EPOCH_DURATION;
        vm.warp(nextEpochStart + VOTE_WINDOW_BUFFER + 1);
        assertTrue(clockProxy.votingActive(), "voting should be active");
    }

    function _makeVote(address gauge, uint256 weight) internal pure returns (IAddressGaugeVote.GaugeVote[] memory) {
        IAddressGaugeVote.GaugeVote[] memory votes = new IAddressGaugeVote.GaugeVote[](1);
        votes[0] = IAddressGaugeVote.GaugeVote(weight, gauge);
        return votes;
    }

    function _makeVotes(
        address g1, uint256 w1,
        address g2, uint256 w2
    ) internal pure returns (IAddressGaugeVote.GaugeVote[] memory) {
        IAddressGaugeVote.GaugeVote[] memory votes = new IAddressGaugeVote.GaugeVote[](2);
        votes[0] = IAddressGaugeVote.GaugeVote(w1, g1);
        votes[1] = IAddressGaugeVote.GaugeVote(w2, g2);
        return votes;
    }

    function _makeVotes3(
        address g1, uint256 w1,
        address g2, uint256 w2,
        address g3, uint256 w3
    ) internal pure returns (IAddressGaugeVote.GaugeVote[] memory) {
        IAddressGaugeVote.GaugeVote[] memory votes = new IAddressGaugeVote.GaugeVote[](3);
        votes[0] = IAddressGaugeVote.GaugeVote(w1, g1);
        votes[1] = IAddressGaugeVote.GaugeVote(w2, g2);
        votes[2] = IAddressGaugeVote.GaugeVote(w3, g3);
        return votes;
    }

    // ── Test 1: Basic single-epoch voting ────────────────

    function test_basicVoting() public {
        _warpToVotingActive();

        vm.prank(alice);
        voterProxy.vote(_makeVote(gauge1, 100));

        assertEq(voterProxy.isVoting(alice), true);
        assertEq(voterProxy.gaugeVotes(gauge1), 1000e18);
        assertEq(voterProxy.totalVotingPowerCast(), 1000e18);
    }

    // ── Test 2: Votes persist across epochs ──────────────

    function test_votesPersistAcrossEpochs() public {
        _warpToVotingActive();
        uint256 epoch1 = clockProxy.currentEpoch();

        // Alice votes in epoch 1
        vm.prank(alice);
        voterProxy.vote(_makeVotes(gauge1, 60, gauge2, 40));

        // Verify votes
        uint256 gauge1VotesE1 = voterProxy.gaugeVotes(gauge1);
        uint256 gauge2VotesE1 = voterProxy.gaugeVotes(gauge2);
        assertGt(gauge1VotesE1, 0, "gauge1 should have votes");
        assertGt(gauge2VotesE1, 0, "gauge2 should have votes");

        // Move to next epoch
        _warpToNextEpochVoting();
        uint256 epoch2 = clockProxy.currentEpoch();
        assertTrue(epoch2 > epoch1, "should be new epoch");

        // With hook enabled, votes are stored in epoch 0 and persist
        assertTrue(voterProxy.isVoting(alice), "alice should still be voting");
        assertEq(voterProxy.gaugeVotes(gauge1), gauge1VotesE1, "gauge1 votes should persist");
        assertEq(voterProxy.gaugeVotes(gauge2), gauge2VotesE1, "gauge2 votes should persist");
    }

    // ── Test 3: Multi-voter, multi-gauge, multi-epoch ────

    function test_multiVoterMultiGaugeMultiEpoch() public {
        _warpToVotingActive();

        // Epoch 1: all three voters cast
        {
            vm.prank(alice);
            voterProxy.vote(_makeVotes3(gauge1, 50, gauge2, 30, gauge3, 20));

            vm.prank(bob);
            voterProxy.vote(_makeVotes(gauge1, 70, gauge2, 30));

            vm.prank(carol);
            voterProxy.vote(_makeVote(gauge3, 100));
        }

        // Snapshot epoch 1 totals
        uint256 g1Total;
        uint256 g2Total;
        uint256 g3Total;
        {
            g1Total = voterProxy.gaugeVotes(gauge1);
            g2Total = voterProxy.gaugeVotes(gauge2);
            g3Total = voterProxy.gaugeVotes(gauge3);

            // gauge1: alice 50% of 1000 + bob 70% of 500 = 500 + 350 = 850
            assertApproxEqAbs(g1Total, 850e18, 1e18, "gauge1 epoch1");
            // gauge2: alice 30% of 1000 + bob 30% of 500 = 300 + 150 = 450
            assertApproxEqAbs(g2Total, 450e18, 1e18, "gauge2 epoch1");
            // gauge3: alice 20% of 1000 + carol 100% of 300 = 200 + 300 = 500
            assertApproxEqAbs(g3Total, 500e18, 1e18, "gauge3 epoch1");
        }

        // Move to epoch 2 - votes should persist
        _warpToNextEpochVoting();

        {
            assertEq(voterProxy.gaugeVotes(gauge1), g1Total, "g1 persists");
            assertEq(voterProxy.gaugeVotes(gauge2), g2Total, "g2 persists");
            assertEq(voterProxy.gaugeVotes(gauge3), g3Total, "g3 persists");
        }

        // Bob resets and changes his vote
        {
            vm.prank(bob);
            voterProxy.reset();

            vm.prank(bob);
            voterProxy.vote(_makeVote(gauge3, 100));
        }

        // Verify updated totals
        {
            // gauge1 lost bob's 350, now just alice's 500
            assertApproxEqAbs(voterProxy.gaugeVotes(gauge1), 500e18, 1e18, "g1 after bob reset");
            // gauge2 lost bob's 150, now just alice's 300
            assertApproxEqAbs(voterProxy.gaugeVotes(gauge2), 300e18, 1e18, "g2 after bob reset");
            // gauge3: alice 200 + carol 300 + bob 500 = 1000
            assertApproxEqAbs(voterProxy.gaugeVotes(gauge3), 1000e18, 1e18, "g3 after bob revote");
        }

        // Move to epoch 3 - verify persistence again
        _warpToNextEpochVoting();

        {
            assertApproxEqAbs(voterProxy.gaugeVotes(gauge1), 500e18, 1e18, "g1 epoch3");
            assertApproxEqAbs(voterProxy.gaugeVotes(gauge2), 300e18, 1e18, "g2 epoch3");
            assertApproxEqAbs(voterProxy.gaugeVotes(gauge3), 1000e18, 1e18, "g3 epoch3");
        }
    }

    // ── Test 4: Transfer decreases voting power auto-adjusts ──

    function test_transferDecreasesVotingPowerAutoAdjusts() public {
        _warpToVotingActive();

        // Alice votes with all 1000
        vm.prank(alice);
        voterProxy.vote(_makeVote(gauge1, 100));
        assertEq(voterProxy.gaugeVotes(gauge1), 1000e18);

        // Alice transfers 600 tokens to bob -> alice has 400 left
        // The _afterTokenTransfer hook should call updateVotingPower
        vm.prank(alice);
        token.transfer(bob, 600e18);

        // Alice's voting power decreased from 1000 to 400
        // updateVotingPower should have auto-adjusted
        assertEq(token.getVotes(alice), 400e18, "alice votes after transfer");
        assertApproxEqAbs(voterProxy.gaugeVotes(gauge1), 400e18, 1e18, "gauge1 auto-adjusted");
    }

    // ── Test 5: Transfer increases voting power does NOT auto-inflate ──

    function test_transferIncreasesVotingPowerNoInflation() public {
        _warpToVotingActive();

        // Alice votes with 1000
        vm.prank(alice);
        voterProxy.vote(_makeVote(gauge1, 100));
        assertEq(voterProxy.gaugeVotes(gauge1), 1000e18);

        // Bob transfers 500 to alice -> alice now has 1500
        vm.prank(bob);
        token.transfer(alice, 500e18);

        assertEq(token.getVotes(alice), 1500e18, "alice votes after receiving");
        // Votes should NOT inflate - still 1000
        assertEq(voterProxy.gaugeVotes(gauge1), 1000e18, "gauge1 should not inflate");
    }

    // ── Test 6: Revote after power increase to capture new power ──

    function test_revoteAfterPowerIncrease() public {
        _warpToVotingActive();

        vm.prank(alice);
        voterProxy.vote(_makeVote(gauge1, 100));
        assertEq(voterProxy.gaugeVotes(gauge1), 1000e18);

        // Bob sends 500 to alice
        vm.prank(bob);
        token.transfer(alice, 500e18);

        // Alice must manually revote to use new power
        vm.prank(alice);
        voterProxy.vote(_makeVote(gauge1, 100));

        assertApproxEqAbs(voterProxy.gaugeVotes(gauge1), 1500e18, 1e18, "gauge1 after revote");
    }

    // ── Test 7: Full scenario - multi-epoch with transfers ──

    function test_fullScenarioMultiEpochWithTransfers() public {
        // ── Epoch 1: initial votes ──
        _warpToVotingActive();

        {
            vm.prank(alice);
            voterProxy.vote(_makeVotes(gauge1, 70, gauge2, 30));

            vm.prank(bob);
            voterProxy.vote(_makeVote(gauge2, 100));
        }

        uint256 g1E1;
        uint256 g2E1;
        {
            g1E1 = voterProxy.gaugeVotes(gauge1);
            g2E1 = voterProxy.gaugeVotes(gauge2);
            // g1: alice 70% of 1000 = 700
            assertApproxEqAbs(g1E1, 700e18, 1e18, "g1 e1");
            // g2: alice 30% of 1000 + bob 100% of 500 = 300 + 500 = 800
            assertApproxEqAbs(g2E1, 800e18, 1e18, "g2 e1");
        }

        // ── Epoch 2: alice transfers to carol, carol votes ──
        _warpToNextEpochVoting();

        // Votes persist
        assertEq(voterProxy.gaugeVotes(gauge1), g1E1, "g1 persists e2");

        // Alice transfers 400 to carol
        vm.prank(alice);
        token.transfer(carol, 400e18);

        // Alice's gauge votes auto-adjusted (1000 → 600)
        {
            uint256 g1AfterTransfer = voterProxy.gaugeVotes(gauge1);
            uint256 g2AfterTransfer = voterProxy.gaugeVotes(gauge2);
            // alice had 70/30 split on 1000, now on 600: 420/180
            assertApproxEqAbs(g1AfterTransfer, 420e18, 1e18, "g1 after alice transfer");
            // g2: alice 180 + bob 500 = 680
            assertApproxEqAbs(g2AfterTransfer, 680e18, 1e18, "g2 after alice transfer");
        }

        // Carol now has 300 + 400 = 700 tokens
        assertEq(token.getVotes(carol), 700e18, "carol balance");

        // Carol votes
        vm.prank(carol);
        voterProxy.vote(_makeVotes(gauge1, 50, gauge3, 50));

        {
            // g1: alice 420 + carol 350 = 770
            assertApproxEqAbs(voterProxy.gaugeVotes(gauge1), 770e18, 1e18, "g1 with carol");
            // g3: carol 350
            assertApproxEqAbs(voterProxy.gaugeVotes(gauge3), 350e18, 1e18, "g3 with carol");
        }

        // ── Epoch 3: verify all votes still persist ──
        _warpToNextEpochVoting();

        {
            assertApproxEqAbs(voterProxy.gaugeVotes(gauge1), 770e18, 1e18, "g1 epoch3");
            assertApproxEqAbs(voterProxy.gaugeVotes(gauge2), 680e18, 1e18, "g2 epoch3");
            assertApproxEqAbs(voterProxy.gaugeVotes(gauge3), 350e18, 1e18, "g3 epoch3");
            assertTrue(voterProxy.isVoting(alice), "alice still voting e3");
            assertTrue(voterProxy.isVoting(bob), "bob still voting e3");
            assertTrue(voterProxy.isVoting(carol), "carol still voting e3");
        }
    }

    // ── Test 8: Double voting prevention ──

    function test_doubleVotingPrevented() public {
        _warpToVotingActive();

        vm.prank(alice);
        voterProxy.vote(_makeVote(gauge1, 100));

        // Alice transfers all to bob
        vm.prank(alice);
        token.transfer(bob, 1000e18);

        // Alice's votes auto-decreased to 0
        assertEq(voterProxy.gaugeVotes(gauge1), 0, "gauge1 zeroed");
        assertEq(token.getVotes(alice), 0, "alice has no power");

        // Bob votes - should use his own power (500 original + 1000 received = 1500)
        vm.prank(bob);
        voterProxy.vote(_makeVote(gauge2, 100));

        assertApproxEqAbs(voterProxy.gaugeVotes(gauge2), 1500e18, 1e18, "bob votes with full power");
        // No double-spending: gauge1 = 0, gauge2 = 1500, total = 1500
        assertApproxEqAbs(voterProxy.totalVotingPowerCast(), 1500e18, 1e18, "total power correct");
    }

    // ── Test 9: Delegation to third party ──

    function test_delegationToThirdParty() public {
        _warpToVotingActive();

        // Alice delegates to carol
        vm.prank(alice);
        token.delegate(carol);

        // Carol now has her own 300 + alice's 1000 = 1300 voting power
        assertEq(token.getVotes(carol), 1300e18, "carol has delegated power");
        assertEq(token.getVotes(alice), 0, "alice has no power after delegation");

        // Carol votes
        vm.prank(carol);
        voterProxy.vote(_makeVotes(gauge1, 50, gauge2, 50));

        assertApproxEqAbs(voterProxy.gaugeVotes(gauge1), 650e18, 1e18, "g1");
        assertApproxEqAbs(voterProxy.gaugeVotes(gauge2), 650e18, 1e18, "g2");

        // Persist to next epoch
        _warpToNextEpochVoting();
        assertApproxEqAbs(voterProxy.gaugeVotes(gauge1), 650e18, 1e18, "g1 persists");
    }
}
