// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {ERC721} from "../task2/ERC721.sol";

contract AuctionProxy is Proxy {
    uint256 public constant MAX_FEE_PERCENT = 500;

    uint256 public constant MIN_FEE_PERCENT = 100;

    address public implementation;
    address public admin;
    ERC721 public nft;
    /**
     * 拍卖开始时间
     */
    uint256 public startTime;
    /**
     * 拍卖结束时间
     */
    uint256 public endTime;

    /**
     * 价格衰减时间间隔（秒）
     */
    uint256 public priceDropInterval;
    /**
     * 合约所有者
     */
    address public owner;

    /**
     * 从开始时间到结束时间的衰减次数
     */
    uint256 public dropTimes;

    uint256 private _feePercentDropPerTime;

    constructor(
        address _impl,
        address _admin,
        address nftAddr,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _priceDropInterval
    ) {
        implementation = _impl;
        admin = _admin;
        owner = _admin;
        nft = ERC721(nftAddr);
        admin = owner; // 设置管理员为owner
        startTime = _startTime;
        endTime = _endTime;
        priceDropInterval = _priceDropInterval;
        dropTimes = (_endTime - _startTime) / _priceDropInterval;
        _feePercentDropPerTime = (MAX_FEE_PERCENT - MIN_FEE_PERCENT) / dropTimes;
    }

    function _implementation() internal view override returns (address) {
        return implementation;
    }

    receive() external payable virtual {}
}
