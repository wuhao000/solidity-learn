// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";


contract AuctionProxy is Proxy {

    address public implementation;
    address public admin;

    constructor(address _implementation, address _admin) {
        implementation = _implementation;
        admin = _admin;
    }

    function _implementation() internal view override returns (address) {
        return implementation;
    }

}