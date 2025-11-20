// SPDX-License-Identifier: MIT
pragma solidity ^0.8;


contract OnlyOwner {

    address private _owner;


    constructor() {
        _owner = msg.sender;
    }


    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    function _onlyOwner() internal view {
        require(_owner == msg.sender, "not owner");
    }

}