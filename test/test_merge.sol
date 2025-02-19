pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {QuadraticIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/QuadraticIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {VotingEscrow} from "src/escrow/increasing/VotingEscrowIncreasing.sol";
import {Lock} from "src/escrow/increasing/Lock.sol";

import {Test} from "forge-std/Test.sol";
import {SafeCastUpgradeable as SafeCast} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {CurveConstantLib} from "@libs/CurveConstantLib.sol";
import {Clock} from "../src/clock/Clock.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TestMerge is Test {
    using ProxyLib for address;
    using SafeCast for uint256;

    uint208 internal TOKEN_10K = 1e22;
    uint208 internal TOKEN_5K = 5e21;

    uint256 internal WEEK = 604800;
    uint256 internal DAY = 86400;

    QuadraticIncreasingEscrow internal b;
    VotingEscrow internal escrow;
    Clock internal c;
    uint256 MAX_TIME = CurveConstantLib.MAX_TIME;
    MockERC20 internal token;

    address public sender = address(123);

    function lockedBalance(uint208 amount, uint48 start, uint48 end) public pure returns(ILockedBalanceIncreasing.LockedBalance memory){
        return ILockedBalanceIncreasing.LockedBalance(amount, start, end);
    }

    function setUp() public {
        DAO _dao = DAO(payable(new ERC1967Proxy(address(new DAO()), bytes(""))));
        _dao.initialize({
            _metadata: bytes(""),
            _initialOwner: address(this),
            _trustedForwarder: address(0),
            daoURI_: "ipfs://"
        });

        b = new QuadraticIncreasingEscrow();
        c = new Clock();
        address impl = address(new VotingEscrow());

        token = new MockERC20();
        
        
        escrow = VotingEscrow(impl.deployUUPSProxy(
            abi.encodeCall(
                VotingEscrow.initialize,
                (address(token), address(_dao), address(c), 0)
            )
        ));

        _dao.grant({
            _who: address(this),
            _where: address(escrow),
            _permissionId: escrow.ESCROW_ADMIN_ROLE()
        });


        escrow.setCurve(address(b));
        escrow.setLockNFT(
            address(address(new Lock())).deployUUPSProxy(
                abi.encodeWithSelector(
                    Lock.initialize.selector,
                    address(escrow),
                    "nameoo",
                    "symbol",
                    address(_dao)
                )
            )
        );
    }


    function test_oe() public {
        address giorgi = address(123);
        address jordan = address(456);

        token.mint(giorgi, TOKEN_10K);
        token.mint(jordan, TOKEN_10K);

        vm.prank(giorgi);
        token.approve(address(escrow), TOKEN_10K);

        vm.prank(jordan);
        token.approve(address(escrow), TOKEN_10K);
        
        uint256 lockTime = block.timestamp;
        uint256 lockWeekStart = (block.timestamp / WEEK) * WEEK;
        vm.prank(giorgi);
        uint256 from = escrow.createLock(50e18); // 1

        vm.prank(jordan);
        uint256 to = escrow.createLock(30e18); // 2

        // vm.expectRevert(); // reverts as tokens are not mature
        // escrow.merge(from, to);

        uint256 mergeWeekStart = lockWeekStart + MAX_TIME;
        uint256 mergeTime = mergeWeekStart + 10;
        vm.warp(mergeTime);

        escrow.merge(from, to);

        assertEq(
            b.supplyAt(mergeTime), 
            30e18 + (30e18 / MAX_TIME) * (mergeWeekStart - lockWeekStart) +
            50e18 + (50e18 / MAX_TIME) * (mergeWeekStart - lockWeekStart)
        );


    }
    

    // // 1. Deposit 10k where `startTime` rounds to prev week start.
    // //    1.a check that totalSupply is 0 before depositTime.
    // //    1.b check that totalSupply is 10k + slope * (depositTime - startTime) at `depositTime`.
    // //    1.c check that totalSupply at `depositTime + 2 days` is equal to 10k + slope * (depositTime + 2 days - startTime)
    // // 2. Deposit another 10k where `depositTime` is the same as before.
    // //    2.a check that totalSupply is still 0 before the `depositTime`.
    // //    2.b check that toalSupply at depositTime is 2 * (10k + slope * (depositTime - startTime))
    // //    2.c check that totalSupply at `depositTime + 2 days` is equal to  2 * (10k + slope * (depositTime + 2 days - startTime))
    // // 3. Deposit another 10k where `depositTime` is in the next week and startTime of this is next week exactly.
    // //    3.a check that totalSupply at thirdDepositTime - 1 is not including the third deposit's calculation.
    // //    3.b check that totalSupply at `thirdDepositTime` is  TOKEN_10K * 2 + 2 * slope * (thirdDepositTime - startTime) + TOKEN_10K + slope * (thirdDepositTime - newStartTime)
    // function test_1() public {
    //     vm.startPrank(sender);
    //     uint256 firstDepositTime = block.timestamp;
    //     uint256 startTime = (firstDepositTime / WEEK) * WEEK;        
    //     uint256 endTime = startTime + MAX_TIME;
    //     uint256 twoDaysAfterFirstDeposit = firstDepositTime + 2 days;

    //     uint256 slope = TOKEN_10K / MAX_TIME;

    //     // Deposit 10k token.
    //     escrow.createLock(TOKEN_10K);

    //     assertEq(b.supplyAt(firstDepositTime - 1), 0);
    //     assertEq(b.supplyAt(firstDepositTime), TOKEN_10K + slope * (firstDepositTime - startTime));
    //     assertEq(
    //         b.supplyAt(twoDaysAfterFirstDeposit), 
    //         TOKEN_10K + slope * (twoDaysAfterFirstDeposit - startTime)
    //     );

    //     // Deposit another 10k at `firstDepositTime`, which must create a new `UserPoint` 
    //     // which includes previous deposit's bias and slope as well.
    //    escrow.createLock(TOKEN_10K);

    //     assertEq(b.supplyAt(firstDepositTime - 1), 0);
    //     assertEq(b.supplyAt(firstDepositTime), TOKEN_10K * 2 + 2 * slope * (firstDepositTime - startTime));
    //     assertEq(
    //         b.supplyAt(twoDaysAfterFirstDeposit), 
    //         TOKEN_10K * 2 + 2 * slope * (twoDaysAfterFirstDeposit - startTime)
    //     );
        
    //     uint256 thirdDepositTime = firstDepositTime + WEEK;
    //     vm.warp(thirdDepositTime);
    //     uint256 newStartTime = (thirdDepositTime / WEEK) * WEEK;      
    //     uint256 newEndTime = newStartTime + MAX_TIME;
        
    //     // Deposit again 10k
    //     escrow.createLock(TOKEN_10K);

    //     // supply before third deposit must not include third deposit.
    //     assertEq(
    //         b.supplyAt(thirdDepositTime - 1), 
    //         TOKEN_10K * 2 + 2 * slope * (thirdDepositTime - 1 - startTime) 
    //     );

    //     assertEq(
    //         b.supplyAt(thirdDepositTime), 
    //         TOKEN_10K * 2 + 2 * slope * (thirdDepositTime - startTime) + TOKEN_10K + slope * (thirdDepositTime - newStartTime)
    //     );
    // }

    // // 1. Deposit 10k at `depositTime = block.timestamp`
    // //    1.a check that totalSupply at `endTime - 10` and `endTime - 5` are different and increasing.
    // //    1.b check that whatever totalSupply is at `endTime`, it stays the same at `endTime + x`.
    // function test_2() public {
    //     vm.startPrank(sender);
    //     uint256 firstDepositTime = block.timestamp;
    //     uint256 startTime = (firstDepositTime / WEEK) * WEEK;        
    //     uint256 endTime = startTime + MAX_TIME;

    //     // Deposit 10k token at `startTime`
    //     escrow.createLock(TOKEN_10K);

    //     uint256 a1 = b.supplyAt(endTime - 10);
    //     uint256 b1 = b.supplyAt(endTime - 5);
    //     assertGt(b1, a1);

    //     uint256 c1 = b.supplyAt(endTime);
    //     uint256 c2 = b.supplyAt(endTime + 10);
    //     uint256 c3 = b.supplyAt(endTime + 300000);
    //     assertEq(c1, c2);
    //     assertEq(c2, c3);
    // }

    // // 1. Deposit 10k at `startTime`
    // // 2. Deposit 10k at `newStartTime = startTime + WEEK`.
    // //    2.a check that `newStartTime - 1`, totalSupply is 10k + (10k / MAX_TIME) * (newStartTime - 1 - startTime)
    // //    2.b check that totalSupply is 0 at `newStartTime`.
    // // 3. Deposit 10k again at `newStartTime = startTime + WEEK`
    // //    3.a see below what we test...
    // function test_3() public {
    //     vm.startPrank(sender);
    //     uint256 firstDepositTime = block.timestamp;
    //     uint256 startTime = (firstDepositTime / WEEK) * WEEK;        
    //     uint256 endTime = startTime + MAX_TIME;
    //     uint256 slope = TOKEN_10K / MAX_TIME;

    //     // Deposit 10k token
    //     uint256 tokenId = escrow.createLock(TOKEN_10K);

    //     uint256 newDepositTime = firstDepositTime + WEEK;
    //     vm.warp(newDepositTime);
    //     uint256 newStartTime = (newDepositTime / WEEK) * WEEK;        
    //     uint256 newEndTime = newStartTime + MAX_TIME;
        
    //     escrow.makeIt0(tokenId);
        
    //     assertEq(
    //         b.supplyAt(newDepositTime - 1),
    //         TOKEN_10K + slope * (newDepositTime - 1 - startTime)
    //     );

    //     assertEq(b.supplyAt(newDepositTime), 0);

    //     // Deposit 10k token at `newStartTime`
    //     b.checkpoint(
    //         1, 
    //         lockedBalance(0, 0, 0),
    //         lockedBalance(TOKEN_10K, newStartTime.toUint48(), newEndTime.toUint48())
    //     );

    //     // when we deposited 0 above, `slopeChanges` must have updated to remove 
    //     // that slope from it. Otherwise, below will fail.
    //     assertEq(
    //         b.supplyAt(endTime + 1),
    //         TOKEN_10K + slope * (endTime + 1 - newStartTime)
    //     );
    // }


    // // 1. Deposit 50. 
    // // 2. deposit 30.
    // // 2. Deposit 0.
    // // 3. see if it succeeds
    // function test_4() public {
    //     vm.startPrank(sender);
    //     uint256 firstDepositTime = block.timestamp;
    //     uint256 startTime = (firstDepositTime / WEEK) * WEEK;        
    //     uint256 endTime = startTime + MAX_TIME;
    //     uint256 slope = 50e18 / MAX_TIME;

    //     uint256 tokenId = escrow.createLock(50e18);

    //     uint256 newDepositTime = firstDepositTime + WEEK;
    //     vm.warp(newDepositTime);
    //     uint256 newStartTime = (newDepositTime / WEEK) * WEEK;        
    //     uint256 newEndTime = newStartTime + MAX_TIME;

    //     escrow.increaseAmountFor(tokenId, 30e18, true);

    //     newDepositTime = newDepositTime + 20 minutes;
    //     vm.warp(newDepositTime);
    //     newStartTime = (newDepositTime / WEEK) * WEEK;        
    //     newEndTime = newStartTime + MAX_TIME;
    //     escrow.makeIt0(tokenId);

    //     assertEq(b.supplyAt(newDepositTime), 0);
    // }

    // // NOTE: on the 2nd deposit, end date doesn't change..
    // // 1. Deposit 50
    // // 2. Deposit 30
    // // 3. deposit 0
    // // 3. see if it succeeds
    // function test_5() public {
    //     vm.startPrank(sender);
    //     uint256 firstDepositTime = block.timestamp;
    //     uint256 startTime = (firstDepositTime / WEEK) * WEEK;        
    //     uint256 endTime = startTime + MAX_TIME;
    //     uint256 slope = 50e18 / MAX_TIME;

    //     // Deposit 10k token
    //     uint256 tokenId = escrow.createLock(50e18);

    //     uint256 newDepositTime = firstDepositTime + WEEK;
    //     vm.warp(newDepositTime);
    //     uint256 newStartTime = (newDepositTime / WEEK) * WEEK;        
    //     uint256 newEndTime = newStartTime + MAX_TIME;

    //     escrow.increaseAmountFor(tokenId, 30e18, false);
    
    //     newDepositTime = newDepositTime + 20 minutes;
    //     vm.warp(newDepositTime);
    //     newStartTime = (newDepositTime / WEEK) * WEEK;        
    //     newEndTime = newStartTime + MAX_TIME;
    //     escrow.makeIt0(tokenId);
        
    //     assertEq(b.supplyAt(newDepositTime), 0);
    // }
}
