// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {AuctionProxy} from "./AuctionProxy.sol";
import {IAuction} from "./IAuction.sol";

contract AuctionFactory {

    address private _owner;

    uint256 public auctionId;

    mapping(uint256 => address) public auctions;

    event AuctionCreated(uint256 indexed auctionId, address indexed auction, address proxy);

    constructor() {
        _owner = msg.sender;
    }

    function createAuction(
        address auctionAddr,
        address nftAddr,
        uint256 startTime,
        uint256 endTime,
        uint256 priceDropInterval
    ) external returns (address, uint256) {
        require(msg.sender == _owner, "not owner");
        auctionId++;
        AuctionProxy auction = new AuctionProxy(auctionAddr);
        address addr = address(auction);
        IAuction(addr).initialize( _owner, nftAddr, startTime, endTime, priceDropInterval);
        auctions[auctionId] = addr;
        emit AuctionCreated(auctionId, auctionAddr, addr);
        return (addr, auctionId);
    }

}
