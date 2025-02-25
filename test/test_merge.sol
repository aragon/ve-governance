// pragma solidity ^0.8.17;

// import {console2 as console} from "forge-std/console2.sol";

// import {QuadraticIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/QuadraticIncreasingEscrow.sol";
// import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
// import {VotingEscrow} from "src/escrow/increasing/VotingEscrowIncreasing.sol";
// import {Lock} from "src/escrow/increasing/Lock.sol";

// import {Test} from "forge-std/Test.sol";
// import {SafeCastUpgradeable as SafeCast} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

// import {CurveConstantLib} from "@libs/CurveConstantLib.sol";
// import {Clock} from "../src/clock/Clock.sol";
// import {MockERC20} from "./mocks/MockERC20.sol";
// import {ProxyLib} from "@libs/ProxyLib.sol";
// import {DAO} from "@aragon/osx/core/dao/DAO.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// contract TestMerge is Test {
//     using ProxyLib for address;
//     using SafeCast for uint256;

//     uint208 internal TOKEN_10K = 1e22;
//     uint208 internal TOKEN_5K = 5e21;

//     uint256 internal WEEK = 604800;
//     uint256 internal DAY = 86400;

//     QuadraticIncreasingEscrow internal b;
//     VotingEscrow internal escrow;
//     Clock internal c;
//     uint256 MAX_TIME = CurveConstantLib.MAX_TIME;
//     MockERC20 internal token;

//     address internal giorgi = address(123);
//     address internal jordan = address(456);

//     address public sender = address(123);

//     function lockedBalance(uint208 amount, uint48 start) public pure returns(ILockedBalanceIncreasing.LockedBalance memory){
//         return ILockedBalanceIncreasing.LockedBalance(amount, start);
//     }

//     function setUp() public {
//         DAO _dao = DAO(payable(new ERC1967Proxy(address(new DAO()), bytes(""))));
//         _dao.initialize({
//             _metadata: bytes(""),
//             _initialOwner: address(this),
//             _trustedForwarder: address(0),
//             daoURI_: "ipfs://"
//         });

//         b = new QuadraticIncreasingEscrow();
//         c = new Clock();
//         address impl = address(new VotingEscrow());

//         token = new MockERC20();
        
        
//         escrow = VotingEscrow(impl.deployUUPSProxy(
//             abi.encodeCall(
//                 VotingEscrow.initialize,
//                 (address(token), address(_dao), address(c), 0)
//             )
//         ));

//         _dao.grant({
//             _who: address(this),
//             _where: address(escrow),
//             _permissionId: escrow.ESCROW_ADMIN_ROLE()
//         });


//         escrow.setCurve(address(b));
//         escrow.setLockNFT(
//             address(address(new Lock())).deployUUPSProxy(
//                 abi.encodeWithSelector(
//                     Lock.initialize.selector,
//                     address(escrow),
//                     "nameoo",
//                     "symbol",
//                     address(_dao)
//                 )
//             )
//         );

//         token.mint(giorgi, TOKEN_10K);
//         token.mint(jordan, TOKEN_10K);

//         vm.prank(giorgi);
//         token.approve(address(escrow), TOKEN_10K);

//         vm.prank(jordan);
//         token.approve(address(escrow), TOKEN_10K);
//     }


//     function test_1() public {
//         vm.prank(giorgi);
//         uint256 from = escrow.createLock(50e18);

//         vm.prank(jordan);
//         vm.warp(block.timestamp + WEEK);
//         uint256 to = escrow.createLock(50e18);
        
//         vm.expectRevert(); //reverts as start dates are different and tokens are not mature.
//         escrow.merge(from, to);
//     }
    
//     // 1. Giorgi locks 50 and Jordan locks 30 at the same week start.
//     // 2. We merge after both tokens maxed out.
//     function test_2() public {
//         uint256 weekStart = (block.timestamp / WEEK) * WEEK;

//         vm.prank(giorgi);
//         uint256 from = escrow.createLock(50e18); // 1

//         vm.prank(jordan);
//         uint256 to = escrow.createLock(30e18); // 2

//         uint256 endTime = weekStart + MAX_TIME;
//         uint256 mergeTime = endTime + 10;
//         vm.warp(mergeTime);

//         escrow.merge(from, to);

//         assertEq(
//             b.supplyAt(mergeTime), 
//             30e18 + (30e18 / MAX_TIME) * (endTime - weekStart) +
//             50e18 + (50e18 / MAX_TIME) * (endTime - weekStart)
//         );

//         assertEq(
//             b.supplyAt(mergeTime + 10), 
//             30e18 + (30e18 / MAX_TIME) * (endTime - weekStart) +
//             50e18 + (50e18 / MAX_TIME) * (endTime - weekStart)
//         );
//     }

//     function test_3() public {
//         uint256 weekStart = (block.timestamp / WEEK) * WEEK;
//         vm.prank(giorgi);
//         uint256 from = escrow.createLock(50e18); // 1

//         vm.prank(jordan);
//         uint256 to = escrow.createLock(30e18); // 2

//         uint256 mergeWeekStart = weekStart + 2 weeks;
//         uint256 mergeTime = mergeWeekStart + 20 minutes;
//         vm.warp(mergeTime);

//         escrow.merge(from, to);

//         assertEq(
//             b.supplyAt(mergeTime), 
//             30e18 + (30e18 / MAX_TIME) * (mergeTime - weekStart) +
//             50e18 + (50e18 / MAX_TIME) * (mergeTime - weekStart)
//         );
//     }
// }
