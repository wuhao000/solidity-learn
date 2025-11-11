// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {AuctionProxy} from "./AuctionProxy.sol";

contract AuctionFactory {

    address private _owner;

    uint256 public auctionId;

    mapping(uint256 => address) public auctions;

    constructor() {
        _owner = msg.sender;
    }

    function initialize(
        address auctionAddr,
        address nftAddr,
        uint256 startTime,
        uint256 endTime,
        uint256 priceDropInterval
    ) external returns (address, uint256) {
        auctionId++;
        require(msg.sender == _owner, "not owner");
        AuctionProxy auction = new AuctionProxy(auctionAddr, _owner, nftAddr, startTime, endTime, priceDropInterval);
        address addr = address(auction);
        auctions[auctionId] = addr;
        return (addr, auctionId);
    }

}
