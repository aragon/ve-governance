// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Vm.sol";
import "forge-std/console2.sol";
import "./Precompiles.sol";

contract PrecompileHandler is Precompiles {
    address private constant VM_ADDRESS =
        address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));

    Vm public constant vm = Vm(VM_ADDRESS);

    bytes4 constant TRANSFER_SIG = bytes4(keccak256("transfer(address,address,uint256)"));

    constructor() {
        vm.etch(TRANSFER, proxyTo(TRANSFER_SIG));
        vm.label(TRANSFER, "TRANSFER");
    }

    function transfer(address from, address to, uint256 amount) public returns (bool) {
        vm.deal(from, from.balance - amount);
        vm.deal(to, to.balance + amount);
        return true;
    }

    function proxyTo(bytes4 sig) internal view returns (bytes memory) {
        address prec = address(this);
        bytes memory ptr;

        assembly {
            ptr := mload(0x40)
            mstore(ptr, 0x60)
            let mc := add(ptr, 0x20)
            let addrPrefix := shl(0xf8, 0x73)
            let addr := shl(0x58, prec)
            let sigPrefix := shl(0x50, 0x63)
            let shiftedSig := shl(0x30, shr(0xe0, sig))
            let suffix := 0x600060043601
            mstore(mc, or(addrPrefix, or(addr, or(sigPrefix, or(shiftedSig, suffix)))))
            mc := add(mc, 0x20)
            mstore(mc, 0x8260e01b82523660006004840137600080828434885af13d6000816000823e82)
            mc := add(mc, 0x20)
            mstore(mc, 0x60008114604a578282f35b8282fd000000000000000000000000000000000000)
            mstore(0x40, add(ptr, 0x80))
        }

        return ptr;
    }
}
