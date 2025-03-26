/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";

// aragon contracts
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DelegationMapper} from "@delegation/DelegationMapper.sol";

import {createTestDAO} from "@mocks/MockDAO.sol";
import {Lock, Clock, VotingEscrow, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, IEscrowCurveTokenStorage, IGaugeVote} from "../../versions.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {console2 as console} from "forge-std/console2.sol";

contract EscrowVotingPowerMock {
    struct Checkpoint {
        uint256 timestamp;
        uint256 value;
    }

    mapping(uint256 => Checkpoint[]) public tcps;
    mapping(uint256 => mapping(uint256 => uint256)) vps;

    bool isApproved = true;
    uint256 vp = 0;

    function write(uint256 _tokenId, uint256 _vp, uint256 _ts) public {
        tcps[_tokenId].push(Checkpoint({timestamp: _ts, value: _vp}));
    }

    function write(uint256 _tokenId, uint256 _vp) external {
        write(_tokenId, _vp, block.timestamp);
    }

    function setApproved(bool _isApproved) public {
        isApproved = _isApproved;
    }

    function votingPowerAt(uint256 _tokenId, uint256 _ts) external view returns (uint256) {
        Checkpoint[] storage tcps_ = tcps[_tokenId];

        uint256 val = 0;

        // simple linear search (ok for test).
        for (uint256 i = tcps_.length; i > 0; i--) {
            if (tcps_[i - 1].timestamp <= _ts) {
                val = tcps_[i - 1].value;
                break;
            }
        }

        return val;
    }

    function isApprovedOrOwner(
        address /* _spender */,
        uint256 /* _tokenId */
    ) public view returns (bool) {
        return isApproved;
    }
}

contract Base is Test {
    using ProxyLib for address;

    EscrowVotingPowerMock public escrow;
    DelegationMapper public dg;
    DAO dao;
    Clock clock;
    address deployer = address(this);

    address alice = address(123);
    address bob = address(456);

    uint256[] singleId = [1];
    uint256[] ids = [1, 2, 3];

    function setUp() public virtual {
        _deployDAO();
        clock = _deployClock(address(dao));

        escrow = new EscrowVotingPowerMock();
        dg = _deployDelegationMapper(address(dao), address(clock), address(escrow));
    }

    function assertDelegate(uint256 _tokenId, uint256 _ts, address _delegatee) internal {
        (address delegatee, ) = dg.getDelegate(_tokenId, _ts);
        assertEq(delegatee, _delegatee);
    }

    function _deployDAO() internal {
        dao = createTestDAO(deployer);
    }

    function _deployClock(address _dao) internal returns (Clock) {
        address impl = address(new Clock());
        bytes memory initCalldata = abi.encodeWithSelector(Clock.initialize.selector, _dao);
        return Clock(impl.deployUUPSProxy(initCalldata));
    }

    function _deployDelegationMapper(
        address _dao,
        address _clock,
        address _escrow
    ) public returns (DelegationMapper) {
        DelegationMapper impl = new DelegationMapper();

        bytes memory initCalldata = abi.encodeCall(
            DelegationMapper.initialize,
            (_dao, _escrow, _clock)
        );
        return DelegationMapper(address(impl).deployUUPSProxy(initCalldata));
    }
}
