// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {ERC721} from "../task2/ERC721.sol";
import {Strings} from "../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {AggregatorV3Interface} from "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IAuction, AuctionInfo, TokenType} from './IAuction.sol';
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";


contract Auction is IAuction, ReentrancyGuard {

    using SafeERC20 for IERC20;

    address public override implementation;
    address public override admin;


    using Strings for uint256;
    ERC721 public nft;

    /**
     * 拍卖品信息
     */
    mapping(uint256 => AuctionInfo) public shelf;

    mapping(address => mapping(TokenType => uint256)) private _winFunds;

    /**
     * 拍卖中的tokenId
     */
    uint256[] private _onShelf;

    /**
     * 合约所有者
     */
    address private _owner;

    uint256 public startTime;
    uint256 public endTime;
    uint256 public priceDropInterval;
    uint256 private _dropTimes;

    mapping(TokenType => address) private _feedsAddress;

    mapping(TokenType => address) private _tokenContractAddress;

    /**
     *
     * @param _priceDropInterval 价格衰减的时间间隔（秒）
     */
    constructor(address nftAddr, address owner, uint256 _startTime, uint256 _endTime, uint256 _priceDropInterval) {
        nft = ERC721(nftAddr);
        _owner = owner;
        startTime = _startTime;
        endTime = _endTime;
        priceDropInterval = _priceDropInterval;
        _dropTimes = (_endTime - _startTime) / _priceDropInterval;
        _feedsAddress[TokenType.DAI] = 0x14866185B1962B63C3Ea9E03Bc1da838bab34C19;
        _feedsAddress[TokenType.ETH] = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        _tokenContractAddress[TokenType.DAI] = 0x3e622317f8C93f7328350cF0B56d9eD4C620C5d6;
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
        require(block.timestamp <= endTime && block.timestamp >= startTime, "auction not started or ended.");
    }

    /**
     * 结束拍卖
     * @return 剩余未处理的拍卖品的数量
     */
    function end() external payable onlyOwner returns (uint256) {
        require(block.timestamp > endTime, "not reach the end time");
        require(_onShelf.length > 0, "all handled.");
        // 每次调用最多处理10笔，防止gas超出导致永远无法提取
        for (uint256 i = 0; i < 5; i++) {
            if (_onShelf.length == 0) {
                return 0;
            }
            uint256 tokenId = _onShelf[_onShelf.length - 1];
            AuctionInfo storage info = shelf[tokenId];
            address oldOwner = info.owner;
            delete shelf[tokenId];
            _onShelf.pop();
            nft.safeTransferFrom(address(this), oldOwner, tokenId);
        }
        return _onShelf.length;
    }

    function getPrice(uint256 tokenId) public view returns (uint256) {
        AuctionInfo storage info = shelf[tokenId];
        if (block.timestamp < startTime) {
            return info.maxPrice;
        } else if (block.timestamp > endTime) {
            return info.minPrice;
        } else {
            uint256 elapsed = (block.timestamp - startTime) / priceDropInterval;
            uint256 dropPrice = elapsed * info.dropPerTime;
            if (dropPrice >= info.maxPrice - info.minPrice) {
                return info.minPrice;
            }
            return info.maxPrice - dropPrice;
        }
    }

    // 升级函数，改变逻辑合约地址，只能由admin调用。选择器：0x0900f010
    // UUPS中，逻辑函数中必须包含升级函数，不然就不能再升级了。
    function upgrade(address newImplementation) external {
        require(msg.sender == admin);
        implementation = newImplementation;
    }

    function withdraw() external {
        require(_winFunds[msg.sender][TokenType.ETH] > 0 || _winFunds[msg.sender][TokenType.DAI] > 0, "no funds.");
        _withdraw(TokenType.ETH);
        _withdraw(TokenType.DAI);
    }

    function _withdraw(TokenType tokenSymbol) internal {
        uint256 val = _winFunds[msg.sender][tokenSymbol];
        if (val > 0) {
            _winFunds[msg.sender][tokenSymbol] = 0;
            if (tokenSymbol == TokenType.ETH) {
                (bool success,) = msg.sender.call{value: val}("");
                require(success, "eth transfer failed");
            } else {
                IERC20 tokenContract = IERC20(_tokenContractAddress[tokenSymbol]);
                tokenContract.safeTransfer(msg.sender, val);
            }
        }
    }

    /**
     * Returns the latest answer.
     */
    function getChainlinkDataFeedLatestAnswer(TokenType symbol) public view returns (int256, uint8, uint256, uint256) {
        AggregatorV3Interface dataFeed = AggregatorV3Interface(_feedsAddress[symbol]);
        uint8 decimal = dataFeed.decimals();
        // prettier-ignore
        (
            /* uint80 roundId */
            ,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        return (answer, decimal, startedAt, updatedAt);
    }

    /**
     * 上架拍卖, 需提前授权nft给当前合约
     */
    function putOnShelf(uint256 tokenId, uint256 maxPrice, uint256 minPrice) external isStarted {
        require(nft.ownerOf(tokenId) == msg.sender, "not owner");
        require(shelf[tokenId].owner == address(0), "already on shelf");
        require(maxPrice >= minPrice, "max price less than min price");
        _onShelf.push(tokenId);
        uint256 dropPerTime = (maxPrice - minPrice) / _dropTimes;
        shelf[tokenId] = AuctionInfo({
            maxPrice: maxPrice,
            minPrice: minPrice,
            dropPerTime: dropPerTime,
            owner: msg.sender
        });
        nft.safeTransferFrom(msg.sender, address(this), tokenId);
    }

    function removeFromShelf(uint256 tokenId) external isStarted {
        require(shelf[tokenId].owner == msg.sender, "not owner");
        _removeToken(tokenId);
        nft.safeTransferFrom(address(this), msg.sender, tokenId);
    }

    function _removeToken(uint256 tokenId) private {
        delete shelf[tokenId];
        for (uint256 i = 0; i < _onShelf.length; i++) {
            if (_onShelf[i] == tokenId) {
                _onShelf[i] = _onShelf[_onShelf.length - 1];
                _onShelf.pop();
                break;
            }
        }
    }

    function bidWithToken(uint256 tokenId, TokenType tokenSymbol, uint256 tokenAmount) external isStarted nonReentrant {
        _bid(tokenId, tokenSymbol, tokenAmount);
    }

    /**
     * 出价，使用eth
     */
    function bid(uint256 tokenId) external payable isStarted nonReentrant {
        _bid(tokenId, TokenType.ETH, msg.value);
    }

    function _bid(uint256 tokenId, TokenType tokenSymbol, uint256 tokenValue) internal {
        AuctionInfo storage info = shelf[tokenId];
        require(info.owner != address(0), "not on shelf");
        _removeToken(tokenId);
        uint256 price = getPrice(tokenId);
        uint256 usd = getAuctionPriceUsd(tokenSymbol, tokenValue);
        require(usd >= price, "payment less than price");
        _winFunds[info.owner][tokenSymbol] += tokenValue;
        if (tokenSymbol != TokenType.ETH) {
            address addr = _tokenContractAddress[tokenSymbol];
            require(addr != address(0), 'Token not supported');
            IERC20 tokenContract = IERC20(addr);
            tokenContract.safeTransferFrom(msg.sender, address(this), tokenValue);
        }
        nft.safeTransferFrom(address(this), msg.sender, tokenId);
    }

    function getAuctionPriceUsd(TokenType symbol, uint256 value) private view returns (uint256) {
        (int256 price, uint8 decimal, ,) = getChainlinkDataFeedLatestAnswer(symbol);
        require(price > 0, "need price > 0");
        // forge-lint: disable-next-line(unsafe-typecast)
        return value * uint256(price) / (10 ** (18 + decimal));
    }

}
