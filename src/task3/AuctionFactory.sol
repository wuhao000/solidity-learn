// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {Auction} from './Auction.sol';

contract AuctionFactory {

    address private _owner;

    constructor() {
        _owner = msg.sender;
    }

    function initialize(address nftAddr) external returns (address) {
        require(msg.sender == _owner, "not owner");
        Auction auction = new Auction(nftAddr, _owner);
        return address(auction);
    }

}