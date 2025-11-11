// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {ERC721} from "../task2/ERC721.sol";
import {Auction} from "./Auction.sol";

contract AuctionProxy is Proxy {
    uint256 public constant MAX_FEE_PERCENT = 500;

    uint256 public constant MIN_FEE_PERCENT = 100;

    address public implementation;
    address public admin;

    constructor(address _implementation) {
        implementation = _implementation;
    }

    function _implementation() internal view override returns (address) {
        return implementation;
    }

    receive() external payable virtual {}
}
