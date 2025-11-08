// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {ERC721} from "../task2/ERC721.sol";
import {Strings} from "../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {AggregatorV3Interface} from "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract Auction {
    AggregatorV3Interface internal dataFeed;
    using Strings for uint256;
    ERC721 public nft;

    /**
     * NFT是否已上架
     */
    mapping(uint256 => bool) public shelf;

    /**
     * tokenId => 最高出价者
     */
    mapping(uint256 => address) private _bids;

    /**
     * tokenId => 最高出价（eth）
     */
    mapping(uint256 => uint256) private _maxBids;

    mapping(address => uint256) private _winFunds;

    /**
     * 拍卖中的tokenId
     */
    uint256[] private _onShelf;

    /**
     * 合约所有者
     */
    address private _owner;

    /**
     * 拍卖是否开始
     */
    bool public started = true;

    /**
     * 退款事件
     */
    event Refund(address target, uint256 amount);

    /**
     * 退款失败事件
     */
    event RefundFailed(address target, uint256 amount);

    /**
     * 新出价
     *
     * @param tokenId NFT
     * @param addr 出价者
     * @param amount 出价（ETH）
     */
    event NewBid(uint256 tokenId, address addr, uint256 amount);

    constructor(address nftAddr) {
        dataFeed = AggregatorV3Interface(0x694AA1769357215DE4FAC081bf1f309aDC325306);
        nft = ERC721(nftAddr);
        _owner = msg.sender;
    }

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    function _onlyOwner() internal view {
        require(msg.sender == _owner, "not owner");
    }

    modifier isStarted() {
        _isStarted();
        _;
    }

    function _isStarted() internal view {
        require(started, "not started or ended");
    }

    /**
     * 结束拍卖
     * @return 剩余未处理的拍卖品的数量
     */
    function end() external payable onlyOwner returns (uint256) {
        require(_onShelf.length > 0, "all handled.");
        started = false;
        // 每次调用最多处理10笔，防止gas超出导致永远无法提取
        for (uint256 i = 0; i < 5; i++) {
            if (_onShelf.length == 0) {
                return 0;
            }
            uint256 tokenId = _onShelf[_onShelf.length - 1];
            address tokenOwner = nft.ownerOf(tokenId);
            _winFunds[tokenOwner] = _maxBids[tokenId];
            delete _bids[tokenId];
            delete _maxBids[tokenId];
            nft.safeTransferFrom(address(this), _bids[tokenId], tokenId);
            _onShelf.pop();
        }
        return _onShelf.length;
    }

    function withdraw() external payable {
        require(_winFunds[msg.sender] > 0, "no funds.");
        uint256 val = _winFunds[msg.sender];
        _winFunds[msg.sender] = 0;
        (bool success,) = msg.sender.call{value: val}("");
        require(success, "transfer failed");
    }

    /**
     * Returns the latest answer.
     */
    function getChainlinkDataFeedLatestAnswer() public view returns (int256, uint8) {
        uint8 decimal = dataFeed.decimals();
        // prettier-ignore
        (
        /* uint80 roundId */
            ,
            int256 answer,
        /*uint256 startedAt*/
            ,
        /*uint256 updatedAt*/
            ,
        /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        return (answer, decimal);
    }

    /**
     * 上架拍卖
     */
    function onShelf(uint256 tokenId) external isStarted {
        require(nft.ownerOf(tokenId) == msg.sender, "not owner");
        require(shelf[tokenId] == false, "already on shelf");
        shelf[tokenId] = true;
        _onShelf.push(tokenId);
    }

    function removeFromShelf(uint256 tokenId) external isStarted {
        require(shelf[tokenId], "not on shelf");
        require(nft.ownerOf(tokenId) == msg.sender, "not owner");
        shelf[tokenId] = false;
        for (uint8 i = 0; i < _onShelf.length; i++) {
            if (_onShelf[i] == tokenId) {
                _onShelf[i] = _onShelf[_onShelf.length - 1];
                _onShelf.pop();
                break;
            }
        }
    }

    /**
     * 出价，使用eth
     */
    function bid(uint256 tokenId) external payable isStarted {
        address oldBidder = _bids[tokenId];
        require(shelf[tokenId], "not on shelf");
        require(oldBidder != msg.sender, "current highest bid is still your's");
        uint256 maxPrice = _maxBids[tokenId];
        (int256 price, uint8 decimal) = getChainlinkDataFeedLatestAnswer();
        require(price > 0, "need price > 0");
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 usd = maxPrice * uint256(price) / (10 ** (18 + decimal));
        require(
            msg.value > _maxBids[tokenId],
            string.concat("current highest bid is ", uint256(usd).toString(), " usd, Your bid must be higher.")
        );
        _maxBids[tokenId] = msg.value;
        _bids[tokenId] = msg.sender;
        if (oldBidder != address(0) && _maxBids[tokenId] > 0) {
            (bool success,) = oldBidder.call{value: _maxBids[tokenId]}("");
            require(success, "Refund failed");
        }
        emit NewBid(tokenId, msg.sender, msg.value);
    }

}
