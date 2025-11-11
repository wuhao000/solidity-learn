// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {ERC721} from "../task2/ERC721.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

struct AuctionInfo {
    // 美元
    uint256 maxPrice;
    // 美元
    uint256 minPrice;
    // 衰减价格 美元
    uint256 dropPerTime;
    address owner;
}

enum TokenType {ETH, DAI}

/**
 * @title IAuction
 * @dev Auction合约的接口
 */
interface IAuction {

    /**
     * @dev 获取实现合约地址
     */
    function implementation() external view returns (address);

    /**
     * @dev 获取管理员地址
     */
    function admin() external view returns (address);

    /**
     * @dev 获取NFT合约地址
     * @return NFT合约地址
     */
    function nft() external view returns (ERC721);

    /**
     * @dev 结束拍卖
     * @return 剩余未处理的拍卖品的数量
     */
    function end() external payable returns (uint256);

    /**
     * @dev 提取获胜资金
     */
    function withdraw() external;

    /**
     * @dev 获取Chainlink数据源的最新答案
     * @return answer 价格答案
     * @return decimal 小数位数
     */
    function getChainlinkDataFeedLatestAnswer(
        TokenType symbol
    ) external view returns (int256 answer, uint8 decimal, uint256 createdAt, uint256 updatedAt);

    /**
     * @dev 上架NFT进行拍卖
     * @param tokenId 要上架的NFT的tokenId
     * @param minPrice 最低价 美元
     * @param maxPrice 最高价 美元
     */
    function putOnShelf(uint256 tokenId, uint256 maxPrice, uint256 minPrice) external;

    /**
     * @dev 从拍卖中移除NFT
     * @param tokenId 要移除的NFT的tokenId
     */
    function removeFromShelf(uint256 tokenId) external;

    /**
     * @dev 对NFT进行出价
     * @param tokenId 要出价的NFT的tokenId
     */
    function bid(uint256 tokenId) external payable;

}