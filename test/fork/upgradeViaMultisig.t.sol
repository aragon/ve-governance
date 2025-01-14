// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {Multisig} from "@aragon/multisig/Multisig.sol";
import {VotingEscrow, Lock, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, ISimpleGaugeVoterSetupParams} from "src/voting/SimpleGaugeVoterSetup.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";

uint256 constant PROPOSAL_ID = 44; // pinned to block 18336106
contract TestUpgradeToV110 is Test {
    /// @dev Aragon signer multisig on the mode multisig
    Multisig aragonMultisig = Multisig(address(0x4315B4D2C707981f7fA51DBE91079Ea8c44e2e95));

    /// @dev Mode multisig owning the contracts
    Multisig modeMultisig = Multisig(address(0x0eB63a3565942D16C1c1211bD78F1B3Dcfe1A254));

    /// also the bpt
    Lock lockMode = Lock(address(0x06ab1Dc3c330E9CeA4fDF0C7C6F6Fb6442A4273C));
    Lock lockBPT = Lock(address(0x19d1c7958b2CacBc796b51b98F7d86ccaa6950eE));
    SimpleGaugeVoter voterMode =
        SimpleGaugeVoter(address(0x71439Ae82068E19ea90e4F506c74936aE170Cf58));
    SimpleGaugeVoter voterBPT =
        SimpleGaugeVoter(address(0x2aA8A5C1Af4EA11A1f1F10f3b73cfB30419F77Fb));

    address[] aragonSigners;
    address[] modeSigners;

    function setAragonSigners() internal {
        aragonSigners.push(address(0x946138B088524414EEDaf0699BA10d7Fb5673A34));
        aragonSigners.push(address(0xbd3eE47A1576F26454C65B96b7AbfaF8Ee9cB4a1));
        aragonSigners.push(address(0x3ffe3F16d47A54b1C6A3f47c9E6Ff5C2C1B32859));
        aragonSigners.push(address(0x9395e6b95afFee7d7b2b107127Fcc9e4167A336f));
    }

    function setModeSigners() internal {
        modeSigners.push(address(0x7d37E514aFB8CB7BD921b06317b5fC42066c3222));
        modeSigners.push(address(0x0825BdB1A5868682B1F880CF1E743e0bA4634ceC));
        modeSigners.push(address(0x3B6B12fd2a042A82b2E3e4BB94611C4e054004bC));
        modeSigners.push(address(0x712A7e401cC0dB2D61707af269EdE852A1E53192));
    }

    function testUpgrade() public {
        setAragonSigners();
        setModeSigners();

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

        // this needs to be wrapped into a create proposal action on the mode msig via the aragon

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
        uint outerId = _buildMsigProposal(outerAction, aragonSigners, aragonMultisig);

        _signExecuteMultisigProposal(outerId, aragonSigners, aragonMultisig);

        // sign on mode
        _signExecuteMultisigProposal(PROPOSAL_ID, modeSigners, modeMultisig);

        // test
        assertEq(lockMode.implementation(), lockImplNew);
        assertEq(voterMode.implementation(), voterImplNew);
        assertEq(lockBPT.implementation(), lockImplNew);
        assertEq(voterBPT.implementation(), voterImplNew);

        // uri is there on the new locks
        lockMode.tokenURI(1);
        lockBPT.tokenURI(1);
    }

    function _buildMsigProposal(
        IDAO.Action[] memory _actions,
        address[] memory _signers,
        Multisig _multisig
    ) internal returns (uint256 proposalId) {
        // prank the first signer who will create stuff
        vm.startPrank(_signers[0]);
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
        vm.stopPrank();

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
}
