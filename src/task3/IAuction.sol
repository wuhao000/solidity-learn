// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {ERC721} from "../task2/ERC721.sol";
import {AggregatorV3Interface} from "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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
     * @dev 检查NFT是否已上架
     * @param tokenId NFT的tokenId
     * @return 是否已上架
     */
    function shelf(uint256 tokenId) external view returns (bool);

    /**
     * @dev 检查拍卖是否开始
     * @return 拍卖是否开始
     */
    function started() external view returns (bool);

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
    function getChainlinkDataFeedLatestAnswer() external view returns (int256 answer, uint8 decimal);

    /**
     * @dev 上架NFT进行拍卖
     * @param tokenId 要上架的NFT的tokenId
     */
    function onShelf(uint256 tokenId) external;

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

    /**
     * @dev 退款事件
     * @param target 退款目标地址
     * @param amount 退款金额
     */
    event Refund(address indexed target, uint256 amount);

    /**
     * @dev 新出价事件
     * @param tokenId NFT的tokenId
     * @param addr 出价者地址
     * @param amount 出价金额
     */
    event NewBid(uint256 indexed tokenId, address indexed addr, uint256 amount);
}