// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface IERC721EnumerableMintableBurnable is IERC721Enumerable {
    function mint(address to, uint256 tokenId) external;

    function burn(uint256 tokenId) external;
}
