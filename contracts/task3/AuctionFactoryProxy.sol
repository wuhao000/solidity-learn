// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {AuctionProxy} from "./AuctionProxy.sol";
import {IAuction} from "./IAuction.sol";
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";

contract AuctionFactoryProxy is Proxy {
    address public implementation;
    address public admin;

    address private _owner;

    uint256 public auctionId;

    mapping(uint256 => address) public auctions;

    event AuctionCreated(uint256 indexed auctionId, address indexed auction, address proxy);

    constructor(address impl) {
        implementation = impl;
    }

    function _implementation() internal view override returns (address) {
        return implementation;
    }

    receive() external payable virtual {}

}
