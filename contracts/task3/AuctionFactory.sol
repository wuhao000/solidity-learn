// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {AuctionProxy} from "./AuctionProxy.sol";
import {IAuction} from "./IAuction.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract AuctionFactory is UUPSUpgradeable, Initializable {
    address public implementation;
    address public admin;

    address public owner;

    uint256 public auctionId;

    mapping(uint256 => address) public auctions;

    event AuctionCreated(uint256 indexed auctionId, address indexed auction, address proxy);

    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) external initializer {
        owner = _owner;
    }

    function createAuction(
        address auctionAddr,
        address nftAddr,
        uint256 startTime,
        uint256 endTime,
        uint256 priceDropInterval
    ) external returns (address, uint256) {
        require(msg.sender == owner, "not owner");
        auctionId++;
        AuctionProxy auction = new AuctionProxy(auctionAddr);
        address addr = address(auction);
        IAuction(addr).initialize(owner, nftAddr, startTime, endTime, priceDropInterval);
        auctions[auctionId] = addr;
        emit AuctionCreated(auctionId, auctionAddr, addr);
        return (addr, auctionId);
    }

    function _authorizeUpgrade(address newImplementation) internal override {
        require(msg.sender == admin, "not admin");
        implementation = newImplementation;
    }
}
