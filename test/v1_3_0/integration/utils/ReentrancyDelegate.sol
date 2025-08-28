pragma solidity ^0.8.17;
import {Test, console2 as console} from "forge-std/Test.sol";

contract ReentrancyDelegate {
    address public escrow;
    address public adapter;

    bytes public params;
    bool exploitEnabled;

    constructor(address _escrow, address _adapter) {
        escrow = _escrow;
        adapter = _adapter;
    }

    function setParams(bytes memory _params) public {
        params = _params;
    }

    function enableExploit(bool _status) public {
        exploitEnabled = _status;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public returns (bytes4) {
        if (!exploitEnabled) {
            return this.onERC721Received.selector;
        }

        (bool success, bytes memory returnData) = adapter.call(params);
        if (success) {
            return this.onERC721Received.selector;
        }

        // Bubble up revert reason
        if (returnData.length > 0) {
            assembly {
                let returndata_size := mload(returnData)
                revert(add(32, returnData), returndata_size)
            }
        } else {
            revert("Adapter call failed");
        }
    }
}
